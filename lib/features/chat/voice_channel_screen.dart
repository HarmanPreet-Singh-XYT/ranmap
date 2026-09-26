import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_alert.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
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

  const VoiceChannelScreen({
    super.key,
    required this.channel,
    required this.title,
  });

  @override
  ConsumerState<VoiceChannelScreen> createState() => _VoiceChannelScreenState();
}

class _VoiceChannelScreenState extends ConsumerState<VoiceChannelScreen> {
  static const _maxReconnectAttempts = 5;

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _events;
  Timer? _reconnectTimer;
  bool _connecting = true;
  bool _muted = false;
  bool _reconnecting = false;
  bool _leaving = false;
  bool _joining = false;
  int _reconnectAttempts = 0;
  String? _error;

  /// True when the OS blocked microphone access. The call stays connected (the
  /// user can still hear others); a hint is shown instead of failing the join.
  bool _micDenied = false;

  @override
  void initState() {
    super.initState();
    _join();
  }

  @override
  void dispose() {
    _leaving = true;
    _reconnectTimer?.cancel();
    unawaited(_teardownRoom());
    super.dispose();
  }

  /// Tears down the current room and its event listener, if any.
  Future<void> _teardownRoom() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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
    // A fresh join (initial or manual Retry) starts the backoff over, so a
    // previously exhausted reconnect loop doesn't immediately give up again.
    if (initial) _reconnectAttempts = 0;
    setState(() {
      if (initial) _connecting = true;
      _error = null;
    });
    await _teardownRoom();

    lk.Room? room;
    try {
      final voiceToken = await ref
          .read(voiceRepositoryProvider)
          .fetchToken(
            tripId: widget.channel.tripId,
            groupId: widget.channel.groupId,
          );
      room = lk.Room();
      room.addListener(_onRoomChanged);
      await room.connect(voiceToken.url, voiceToken.token);
      // Route voice to the loudspeaker (not the earpiece) and let the SDK apply
      // its communication audio-session preset.
      unawaited(_configureAudio());
      // Preserve the user's mute intent across a reconnect instead of forcing
      // the mic on behind a "muted" indicator. A blocked mic must not tear down
      // a working call — join anyway and surface a hint.
      try {
        await room.localParticipant?.setMicrophoneEnabled(!_muted);
        _micDenied = false;
      } catch (_) {
        _micDenied = true;
      }
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
    _reconnectTimer?.cancel();
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
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (!_leaving && mounted) _join(initial: false);
    });
  }

  /// Best-effort platform audio setup: prefer the loudspeaker over the earpiece.
  Future<void> _configureAudio() async {
    try {
      await lk.AudioManager.instance.setSpeakerOutputPreferred(true);
    } catch (_) {
      // Unsupported platform / no audio session: keep the default route.
    }
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
    setState(() {
      _muted = next;
      if (!next) _micDenied = false;
    });
  }

  Future<void> _leave() async {
    _leaving = true;
    await _teardownRoom();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;

    // "Travel together": this channel is unlocked when ANY member is Pro, even
    // if the current user isn't — surface that so it's clear why it works.
    final channel = widget.channel;
    final proAsync = channel.tripId != null
        ? ref.watch(tripProProvider(channel.tripId!))
        : ref.watch(groupProProvider(channel.groupId!));
    final proUnlocked = proAsync.valueOrNull ?? false;

    final Widget content;
    if (_connecting) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(BrandSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandAlert(message: _error!),
              const SizedBox(height: BrandSpace.md),
              BrandPrimaryButton(
                label: 'Retry',
                expand: false,
                onPressed: () => _join(),
              ),
            ],
          ),
        ),
      );
    } else if (room == null) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (_reconnecting) ...[
              const SizedBox(height: BrandSpace.sm),
              Text(
                'Reconnecting…',
                style: BrandText.bodyMd.copyWith(color: BrandColors.textMuted),
              ),
            ],
          ],
        ),
      );
    } else {
      content = Column(
        children: [
          if (_reconnecting) ...[
            const Padding(
              padding: EdgeInsets.only(top: BrandSpace.sm),
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(BrandSpace.sm),
              child: Text(
                'Reconnecting…',
                style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
              ),
            ),
          ],
          if (_micDenied)
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: BrandSpace.md,
                vertical: BrandSpace.xs,
              ),
              child: BrandAlert(
                variant: BrandAlertVariant.info,
                message: 'Microphone access is blocked — enable it in Settings to talk.',
              ),
            ),
          if (proUnlocked)
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: BrandSpace.md,
                vertical: BrandSpace.xs,
              ),
              child: BrandAlert(
                variant: BrandAlertVariant.info,
                message: 'Pro voice — unlocked for everyone here',
              ),
            ),
          Expanded(child: _ParticipantList(room: room)),
        ],
      );
    }

    return BrandScaffold(
      header: BrandHeader(
        title: '${widget.title} · Voice',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        children: [
          Expanded(child: content),
          if (room != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: BrandSpace.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  BrandSecondaryButton(
                    label: _muted ? 'Unmute' : 'Mute',
                    expand: false,
                    leading: Icon(
                      _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      size: 20,
                      color: BrandColors.textHeadlineAlt,
                    ),
                    onPressed: _toggleMute,
                  ),
                  const SizedBox(width: BrandSpace.md),
                  _LeaveButton(onPressed: _leave),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The red "leave voice" pill — the brand's destructive call-to-action.
class _LeaveButton extends StatelessWidget {
  const _LeaveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return BrandPressable(
      onTap: onPressed,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: BrandColors.error,
          borderRadius: BrandRadii.pill,
          boxShadow: BrandShadows.subtle,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.call_end_rounded,
              size: 20,
              color: BrandColors.onPrimary,
            ),
            const SizedBox(width: 8),
            Text(
              'Leave',
              style: BrandText.labelLg.copyWith(color: BrandColors.onPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParticipantList extends StatelessWidget {
  final lk.Room room;

  const _ParticipantList({required this.room});

  @override
  Widget build(BuildContext context) {
    final participants = <lk.Participant>[
      if (room.localParticipant != null) room.localParticipant!,
      ...room.remoteParticipants.values,
    ];

    if (participants.isEmpty) {
      return Center(
        child: Text(
          'Connecting…',
          style: BrandText.bodyMd.copyWith(color: BrandColors.textMuted),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: BrandSpace.sm),
      children: [
        BrandCard(
          padding: const EdgeInsets.symmetric(
            horizontal: BrandSpace.md,
            vertical: BrandSpace.xs,
          ),
          child: Column(
            children: [
              for (final (i, participant) in participants.indexed) ...[
                if (i > 0) const BrandRowDivider(),
                _ParticipantRow(participant: participant),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({required this.participant});

  final lk.Participant participant;

  @override
  Widget build(BuildContext context) {
    final isLocal = participant is lk.LocalParticipant;
    return BrandListRow(
      icon: Icons.person_rounded,
      iconBackground: participant.isSpeaking
          ? BrandColors.accentMint
          : BrandColors.surfaceContainerLow,
      iconColor: BrandColors.textHeadline,
      title: participant.name.isNotEmpty
          ? participant.name
          : participant.identity,
      subtitle: isLocal ? 'You' : 'In voice',
      showChevron: false,
      trailing: Icon(
        participant.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
        size: 20,
        color: participant.isMuted
            ? BrandColors.textMuted
            : BrandColors.primary,
      ),
    );
  }
}
