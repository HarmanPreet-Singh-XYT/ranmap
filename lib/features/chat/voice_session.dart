import 'dart:async';
import '../../core/feedback/app_feedback.dart';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../core/router/auth_state_provider.dart';
import '../../core/util/error_text.dart';
import '../premium/premium_providers.dart';
import 'chat_providers.dart';
import 'voice_providers.dart';

enum VoiceStatus { idle, connecting, connected, error }

/// A snapshot of the app-wide voice session. The LiveKit room itself lives on
/// [VoiceSession.room]; [revision] bumps whenever it changes (participants,
/// speakers, mute) so listeners rebuild.
class VoiceSessionState {
  const VoiceSessionState({
    this.channel,
    this.title = 'Voice',
    this.status = VoiceStatus.idle,
    this.reconnecting = false,
    this.muted = false,
    this.ptt = false,
    this.talking = false,
    this.micDenied = false,
    this.premiumRequired = false,
    this.error,
    this.revision = 0,
  });

  final ChatChannel? channel;
  final String title;
  final VoiceStatus status;
  final bool reconnecting;
  final bool muted;

  /// Push-to-talk: the mic stays muted until the button is held.
  final bool ptt;
  final bool talking;

  /// The OS blocked microphone access. The call stays connected (the user can
  /// still hear others); a hint is shown instead of failing the join.
  final bool micDenied;

  /// The channel needs Pro and no member has it. Shown as a paywall for an
  /// explicit join, ignored for an automatic one.
  final bool premiumRequired;
  final String? error;
  final int revision;

  bool get inCall => channel != null && status != VoiceStatus.idle;

  VoiceSessionState copyWith({
    ChatChannel? channel,
    String? title,
    VoiceStatus? status,
    bool? reconnecting,
    bool? muted,
    bool? ptt,
    bool? talking,
    bool? micDenied,
    bool? premiumRequired,
    Object? error = _keep,
    int? revision,
  }) => VoiceSessionState(
    channel: channel ?? this.channel,
    title: title ?? this.title,
    status: status ?? this.status,
    reconnecting: reconnecting ?? this.reconnecting,
    muted: muted ?? this.muted,
    ptt: ptt ?? this.ptt,
    talking: talking ?? this.talking,
    micDenied: micDenied ?? this.micDenied,
    premiumRequired: premiumRequired ?? this.premiumRequired,
    error: identical(error, _keep) ? this.error : error as String?,
    revision: revision ?? this.revision,
  );
}

const _keep = Object();

/// Owns the single voice connection for the whole app, so a call survives
/// navigation and can start on its own when a trip goes active.
class VoiceSession extends Notifier<VoiceSessionState> {
  static const _maxReconnectAttempts = 5;

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _events;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  /// Bumped on every join/leave so an in-flight connect for a stale channel
  /// discards itself instead of clobbering the current session.
  int _generation = 0;

  /// Channels the user left on purpose; auto-join won't pull them back in.
  final Set<String> _optedOut = {};

  lk.Room? get room => _room;

  bool wasLeftByUser(ChatChannel channel) =>
      _optedOut.contains(channel.roomKey);

  @override
  VoiceSessionState build() {
    ref.onDispose(() {
      _generation++;
      _reconnectTimer?.cancel();
      unawaited(_teardownRoom());
    });
    // Never carry a call across accounts: drop it (and any opt-outs) on sign-out.
    ref.listen(authStateProvider, (_, next) {
      if (next.valueOrNull?.session == null) {
        _optedOut.clear();
        unawaited(leave(byUser: false));
      }
    });
    return const VoiceSessionState();
  }

  /// Joins [channel], switching away from any other channel. A no-op when
  /// already connecting/connected to it. [auto] marks a join the app started
  /// itself: it never opens a paywall, and stays quiet when voice isn't
  /// available.
  Future<void> join(
    ChatChannel channel, {
    String title = 'Voice',
    bool auto = false,
  }) async {
    final current = state;
    final sameChannel = current.channel == channel;
    if (sameChannel &&
        (current.status == VoiceStatus.connecting ||
            current.status == VoiceStatus.connected)) {
      return;
    }
    if (!auto) _optedOut.remove(channel.roomKey);

    final generation = ++_generation;
    _reconnectAttempts = 0;
    await _teardownRoom();
    state = VoiceSessionState(
      channel: channel,
      title: title,
      status: VoiceStatus.connecting,
      // Keep the user's mute/PTT choice when just retrying the same channel.
      muted: sameChannel ? current.muted : false,
      ptt: sameChannel ? current.ptt : false,
    );
    await _connect(generation, channel, auto: auto);
  }

  Future<void> _connect(
    int generation,
    ChatChannel channel, {
    bool auto = false,
  }) async {
    lk.Room? room;
    try {
      final voiceToken = await ref
          .read(voiceRepositoryProvider)
          .fetchToken(tripId: channel.tripId, groupId: channel.groupId);
      if (generation != _generation) return;
      room = lk.Room();
      room.addListener(_onRoomChanged);
      await room.connect(voiceToken.url, voiceToken.token);
      if (generation != _generation) {
        await _dispose(room);
        return;
      }
      // Route voice to the loudspeaker (not the earpiece).
      unawaited(_configureAudio());
      // Preserve the user's mute intent across a reconnect. A blocked mic must
      // not tear down a working call — join anyway and surface a hint.
      var micDenied = false;
      try {
        await room.localParticipant?.setMicrophoneEnabled(!state.muted);
      } catch (_) {
        micDenied = true;
      }
      if (generation != _generation) {
        await _dispose(room);
        return;
      }
      _room = room;
      _attachRoomEvents(room, generation);
      _reconnectAttempts = 0;
      state = state.copyWith(
        status: VoiceStatus.connected,
        reconnecting: false,
        micDenied: micDenied,
        error: null,
      );
      // You're in — the same rising two-note cue Discord plays.
      AppFeedback.medium();
      AppFeedback.play(Sfx.voiceJoin);
    } catch (e) {
      if (room != null) await _dispose(room);
      if (generation != _generation) return;
      if (isPremiumRequired(e)) {
        // Voice is a Pro feature. An automatic join just stays out of the way;
        // an explicit one lets the screen show the paywall.
        state = auto
            ? const VoiceSessionState()
            : state.copyWith(
                status: VoiceStatus.error,
                reconnecting: false,
                premiumRequired: true,
                error: friendlyError(e),
              );
        return;
      }
      // A dropped connection retries; a failed first join (bad token, not a
      // member, backend down) surfaces an error with a manual Retry.
      if (_reconnectAttempts > 0) {
        _scheduleReconnect(generation, channel);
      } else {
        state = state.copyWith(
          status: VoiceStatus.error,
          reconnecting: false,
          error: friendlyError(e),
        );
      }
    }
  }

  void _attachRoomEvents(lk.Room room, int generation) {
    final events = room.createListener();
    events.on<lk.RoomReconnectingEvent>((_) {
      if (generation == _generation) {
        state = state.copyWith(reconnecting: true);
      }
    });
    events.on<lk.RoomReconnectedEvent>((_) {
      if (generation == _generation) {
        state = state.copyWith(reconnecting: false);
      }
    });
    // LiveKit's own reconnect attempts are exhausted (or the room was closed):
    // re-join from scratch.
    events.on<lk.RoomDisconnectedEvent>((_) {
      final channel = state.channel;
      if (generation == _generation && channel != null) {
        _scheduleReconnect(generation, channel);
      }
    });
    // Someone else joining or leaving the room, as an audible presence cue.
    events.on<lk.ParticipantConnectedEvent>((_) {
      if (generation == _generation) {
        AppFeedback.play(Sfx.voiceJoin, volume: 0.5);
      }
    });
    events.on<lk.ParticipantDisconnectedEvent>((_) {
      if (generation == _generation) {
        AppFeedback.play(Sfx.voiceLeave, volume: 0.5);
      }
    });
    // Fresh `audioLevel`s as members start/stop speaking.
    events.on<lk.ActiveSpeakersChangedEvent>((_) => _onRoomChanged());
    _events = events;
  }

  void _scheduleReconnect(int generation, ChatChannel channel) {
    if (generation != _generation) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnectAttempts) {
      state = state.copyWith(
        status: VoiceStatus.error,
        reconnecting: false,
        error: 'Lost connection to the voice channel.',
      );
      return;
    }
    state = state.copyWith(status: VoiceStatus.connecting, reconnecting: true);
    // Exponential backoff: 1s, 2s, 4s, 8s, 16s (capped at 30s).
    final seconds = math.min(30, 1 << (_reconnectAttempts - 1));
    _reconnectTimer = Timer(Duration(seconds: seconds), () async {
      if (generation != _generation) return;
      await _teardownRoom();
      if (generation != _generation) return;
      await _connect(generation, channel);
    });
  }

  Future<void> _configureAudio() async {
    try {
      await lk.AudioManager.instance.setSpeakerOutputPreferred(true);
    } catch (_) {
      // Unsupported platform / no audio session: keep the default route.
    }
  }

  void _onRoomChanged() {
    if (_room == null) return;
    state = state.copyWith(revision: state.revision + 1);
  }

  Future<void> _teardownRoom() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _events?.dispose();
    _events = null;
    final room = _room;
    _room = null;
    if (room != null) await _dispose(room);
  }

  Future<void> _dispose(lk.Room room) async {
    room.removeListener(_onRoomChanged);
    try {
      await room.disconnect();
    } catch (_) {}
    try {
      await room.dispose();
    } catch (_) {}
  }

  /// Leaves the call. [byUser] remembers the choice so auto-join doesn't pull
  /// the user straight back into the same trip's channel.
  Future<void> leave({bool byUser = true}) async {
    final channel = state.channel;
    final wasConnected = state.status == VoiceStatus.connected;
    if (byUser && channel != null) _optedOut.add(channel.roomKey);
    _generation++;
    await _teardownRoom();
    state = const VoiceSessionState();
    if (wasConnected) {
      AppFeedback.light();
      AppFeedback.play(Sfx.voiceLeave);
    }
  }

  Future<String?> toggleMute() => _setMicrophone(muted: !state.muted);

  /// Switches between open-mic and push-to-talk. Entering PTT mutes the mic
  /// until the button is held; leaving restores open-mic.
  Future<String?> setPtt(bool on) async {
    state = state.copyWith(
      ptt: on,
      talking: false,
      muted: on ? true : state.muted,
    );
    return _setMicrophone(muted: state.muted, keepState: true);
  }

  /// While the push-to-talk button is held the mic opens; releasing closes it.
  Future<String?> setTalking(bool talking) async {
    if (!state.ptt) return null;
    return _setMicrophone(muted: !talking, talking: talking);
  }

  /// Returns null on success, or a user-facing error message.
  Future<String?> _setMicrophone({
    required bool muted,
    bool? talking,
    bool keepState = false,
  }) async {
    final participant = _room?.localParticipant;
    if (participant == null) return null;
    try {
      await participant.setMicrophoneEnabled(!muted);
    } catch (e) {
      state = state.copyWith(micDenied: true);
      return friendlyError(e);
    }
    if (_room == null) return null;
    if (!keepState) {
      // Mute/unmute blips, but not for push-to-talk's constant open/close.
      if (!state.ptt && muted != state.muted) {
        AppFeedback.selection();
        AppFeedback.play(muted ? Sfx.mute : Sfx.unmute, volume: 0.6);
      }
      state = state.copyWith(
        muted: muted,
        talking: talking ?? state.talking,
        micDenied: muted ? state.micDenied : false,
      );
    }
    return null;
  }
}

final voiceSessionProvider = NotifierProvider<VoiceSession, VoiceSessionState>(
  VoiceSession.new,
);
