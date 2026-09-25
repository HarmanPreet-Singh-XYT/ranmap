import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import 'chat_providers.dart';
import 'voice_providers.dart';

/// A voice channel for one trip/group: join/leave, mute toggle, and a live
/// participant list. Voice and text share the same channel identity
/// (ChatChannel.roomKey is used as the LiveKit room name).
class VoiceChannelScreen extends ConsumerStatefulWidget {
  final ChatChannel channel;
  final String title;

  const VoiceChannelScreen({super.key, required this.channel, required this.title});

  @override
  ConsumerState<VoiceChannelScreen> createState() => _VoiceChannelScreenState();
}

class _VoiceChannelScreenState extends ConsumerState<VoiceChannelScreen> {
  static const _maxReconnectAttempts = 5;

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _events;
  bool _connecting = true;
  bool _muted = false;
  bool _reconnecting = false;
  bool _leaving = false;
  bool _joining = false;
  int _reconnectAttempts = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _join();
  }

  @override
  void dispose() {
    _leaving = true;
    unawaited(_teardownRoom());
    super.dispose();
  }

  /// Tears down the current room and its event listener, if any.
  Future<void> _teardownRoom() async {
    _events?.dispose();
    _events = null;
    final room = _room;
    _room = null;
    if (room == null) return;
    room.removeListener(_onRoomChanged);
    try {
      await room.disconnect();
    } catch (_) {}
    try {
      await room.dispose();
    } catch (_) {}
  }

  Future<void> _join({bool initial = true}) async {
    // Guard against overlapping joins (Retry + reconnect timer + initState).
    if (_joining) return;
    _joining = true;
    setState(() {
      if (initial) _connecting = true;
      _error = null;
    });
    await _teardownRoom();

    lk.Room? room;
    try {
      final voiceToken = await ref.read(voiceRepositoryProvider).fetchToken(
            tripId: widget.channel.tripId,
            groupId: widget.channel.groupId,
          );
      room = lk.Room();
      room.addListener(_onRoomChanged);
      await room.connect(voiceToken.url, voiceToken.token);
      // Preserve the user's mute intent across a reconnect instead of forcing
      // the mic on behind a "muted" indicator.
      await room.localParticipant?.setMicrophoneEnabled(!_muted);
      if (!mounted) {
        room.removeListener(_onRoomChanged);
        await room.disconnect();
        await room.dispose();
        return;
      }
      _attachRoomEvents(room);
      setState(() {
        _room = room;
        _connecting = false;
        _reconnecting = false;
        _reconnectAttempts = 0;
      });
    } catch (e) {
      // Tear down the half-open room (and its listener) so a failed connect /
      // mic-enable doesn't leak it — "Retry" would otherwise stack rooms.
      if (room != null) {
        room.removeListener(_onRoomChanged);
        await room.disconnect();
        await room.dispose();
      }
      if (!mounted) return;
      // Voice is a Pro feature: show the paywall (never a generic error, and
      // never a reconnect loop), then return to the channel list.
      if (isPremiumRequired(e)) {
        setState(() {
          _error = friendlyError(e);
          _connecting = false;
          _reconnecting = false;
        });
        await showPaywall(context, feature: PremiumFeature.voice);
        if (mounted) Navigator.of(context).maybePop();
        return;
      }
      // A dropped connection during an auto-reconnect retries again; a failed
      // first join (bad token, not a member, backend down) surfaces an error
      // with a manual Retry instead of looping.
      if (_reconnectAttempts > 0) {
        _scheduleReconnect();
      } else {
        setState(() {
          _error = friendlyError(e);
          _connecting = false;
          _reconnecting = false;
        });
      }
    } finally {
      _joining = false;
    }
  }

  void _attachRoomEvents(lk.Room room) {
    final events = room.createListener();
    events.on<lk.RoomReconnectingEvent>((_) {
      if (mounted) setState(() => _reconnecting = true);
    });
    events.on<lk.RoomReconnectedEvent>((_) {
      if (mounted) setState(() => _reconnecting = false);
    });
    // Fired when LiveKit's own reconnect attempts are exhausted (or the room
    // was closed) — re-join from scratch.
    events.on<lk.RoomDisconnectedEvent>((_) {
      if (!_leaving && mounted) _scheduleReconnect();
    });
    _events = events;
  }

  void _scheduleReconnect() {
    if (_leaving || !mounted) return;
    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnectAttempts) {
      setState(() {
        _reconnecting = false;
        _connecting = false;
        _error = 'Lost connection to the voice channel.';
      });
      return;
    }
    setState(() => _reconnecting = true);
    // Exponential backoff: 1s, 2s, 4s, 8s, 16s (capped at 30s).
    final seconds = math.min(30, 1 << (_reconnectAttempts - 1));
    Future.delayed(Duration(seconds: seconds), () {
      if (!_leaving && mounted) _join(initial: false);
    });
  }

  void _onRoomChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    final room = _room;
    if (room?.localParticipant == null) return;
    final next = !_muted;
    try {
      await room!.localParticipant!.setMicrophoneEnabled(!next);
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
      return;
    }
    // The room may have been torn down while the await was in flight.
    if (!mounted) return;
    setState(() => _muted = next);
  }

  Future<void> _leave() async {
    _leaving = true;
    await _teardownRoom();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    final room = _room;

    // "Travel together": this channel is unlocked when ANY member is Pro, even
    // if the current user isn't — surface that so it's clear why it works.
    final channel = widget.channel;
    final proAsync = channel.tripId != null
        ? ref.watch(tripProProvider(channel.tripId!))
        : ref.watch(groupProProvider(channel.groupId!));
    final proUnlocked = proAsync.valueOrNull ?? false;

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text('${widget.title} · Voice'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).maybePop())],
      ),
      footer: room == null
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FButton.icon(
                    onPress: _toggleMute,
                    variant: _muted ? .primary : .outline,
                    size: .lg,
                    semanticsLabel: _muted ? 'Unmute' : 'Mute',
                    child: Icon(_muted ? Icons.mic_off_rounded : Icons.mic_rounded),
                  ),
                  const SizedBox(width: 16),
                  FButton.icon(
                    onPress: _leave,
                    variant: .destructive,
                    size: .lg,
                    semanticsLabel: 'Leave voice',
                    child: const Icon(Icons.call_end_rounded),
                  ),
                ],
              ),
            ),
      child: _connecting
          ? const Center(child: FCircularProgress())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.foreground)),
                        const SizedBox(height: 16),
                        FButton(onPress: () => _join(), child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : room == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const FCircularProgress(),
                          if (_reconnecting) ...[
                            const SizedBox(height: 12),
                            Text('Reconnecting…', style: TextStyle(color: c.mutedForeground)),
                          ],
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        if (_reconnecting) ...[
                          const FProgress(),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text('Reconnecting…', style: TextStyle(color: c.mutedForeground)),
                          ),
                        ],
                        if (proUnlocked) const _ProVoiceBanner(),
                        Expanded(child: _ParticipantList(room: room)),
                      ],
                    ),
    );
  }
}

class _ProVoiceBanner extends StatelessWidget {
  const _ProVoiceBanner();

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    return Container(
      width: double.infinity,
      color: c.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_rounded, size: 18, color: c.highway),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Pro voice — unlocked for everyone here',
              style: TextStyle(color: c.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticipantList extends StatelessWidget {
  final lk.Room room;

  const _ParticipantList({required this.room});

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    final participants = <lk.Participant>[
      if (room.localParticipant != null) room.localParticipant!,
      ...room.remoteParticipants.values,
    ];

    if (participants.isEmpty) {
      return Center(child: Text('Connecting…', style: TextStyle(color: c.mutedForeground)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: participants.length,
      itemBuilder: (context, i) {
        final participant = participants[i];
        final isLocal = participant is lk.LocalParticipant;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FTile(
            prefix: Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: participant.isSpeaking ? c.success : c.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person,
                size: 20,
                color: participant.isSpeaking ? Colors.white : c.foreground,
              ),
            ),
            title: Text(participant.name.isNotEmpty ? participant.name : participant.identity),
            subtitle: Text(isLocal ? 'You' : 'In voice'),
            suffix: Icon(
              participant.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              color: participant.isMuted ? c.mutedForeground : c.success,
            ),
          ),
        );
      },
    );
  }
}
