import 'package:flutter/material.dart';
import '../../core/widgets/haptic_switch.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_alert.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/permissions/app_permission_hint.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import 'chat_providers.dart';
import 'voice_session.dart';

/// The voice channel for one trip/group: join/leave, mute or push-to-talk, and
/// a live participant list. The connection itself lives in [voiceSessionProvider]
/// so it outlives this screen (and can start on its own when a trip goes
/// active); this screen just joins the channel if needed and renders the state.
/// Voice and text share the same channel identity (ChatChannel.roomKey is the
/// LiveKit room name).
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
  @override
  void initState() {
    super.initState();
    // Providers can't be modified during the build phase.
    Future.microtask(_join);
  }

  Future<void> _join() async {
    if (!mounted) return;
    await ref
        .read(voiceSessionProvider.notifier)
        .join(widget.channel, title: widget.title);
  }

  Future<void> _onPremiumRequired() async {
    final controller = ref.read(voiceSessionProvider.notifier);
    // Voice is a Pro feature: show the paywall (never a generic error, and
    // never a reconnect loop), then return to the channel list.
    await controller.leave(byUser: false);
    if (!mounted) return;
    await showPaywall(context, feature: PremiumFeature.voice);
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _report(Future<String?> action) async {
    final message = await action;
    if (message != null && mounted) {
      showAppToast(context, message, error: true);
    }
  }

  Future<void> _leave() async {
    await ref.read(voiceSessionProvider.notifier).leave();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(voiceSessionProvider, (previous, next) {
      if (next.premiumRequired &&
          !(previous?.premiumRequired ?? false) &&
          next.channel == widget.channel) {
        _onPremiumRequired();
      }
    });

    final session = ref.watch(voiceSessionProvider);
    final controller = ref.read(voiceSessionProvider.notifier);
    // The session may be on a different channel for a frame, until join() swaps.
    final here = session.channel == widget.channel;
    final status = here ? session.status : VoiceStatus.connecting;
    final room = here && status == VoiceStatus.connected
        ? controller.room
        : null;

    // "Travel together": this channel is unlocked when ANY member is Pro, even
    // if the current user isn't — surface that so it's clear why it works.
    final channel = widget.channel;
    final proAsync = channel.tripId != null
        ? ref.watch(tripProProvider(channel.tripId!))
        : ref.watch(groupProProvider(channel.groupId!));
    final proUnlocked = proAsync.valueOrNull ?? false;

    final Widget content;
    if (status == VoiceStatus.error) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(BrandSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandAlert(message: session.error ?? 'Voice unavailable.'),
              const SizedBox(height: BrandSpace.md),
              BrandPrimaryButton(
                label: 'Retry',
                expand: false,
                onPressed: _join,
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
            if (here && session.reconnecting) ...[
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
          if (session.reconnecting) ...[
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
          if (session.micDenied)
            AppPermissionHint(
              message: 'Microphone access is blocked — enable it in Settings to talk.',
              onRetry: () => _report(controller.retryMicrophone()),
            ),
          if (session.cameraDenied)
            AppPermissionHint(
              // Not "blocked": the toggle can also fail because another app holds
              // the camera, and asserting a denial the user didn't make is worse
              // than leaving it as the first thing to check.
              message:
                  "Couldn't start the camera — check camera access in Settings, "
                  'then retry.',
              retryLabel: 'Retry',
              onRetry: () => _report(controller.toggleCamera()),
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
          Expanded(child: _ParticipantArea(room: room)),
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
              child: Column(
                children: [
                  _PttToggle(
                    value: session.ptt,
                    onChanged: (on) => _report(controller.setPtt(on)),
                  ),
                  const SizedBox(height: BrandSpace.md),
                  // A Wrap, not a Row: the controls grow (the flip-camera toggle
                  // only exists while video is on) and a fixed Row ran off the
                  // right edge on narrow phones.
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: BrandSpace.sm,
                    runSpacing: BrandSpace.sm,
                    children: [
                      if (session.ptt)
                        _HoldToTalkButton(
                          talking: session.talking,
                          onStart: () => _report(controller.setTalking(true)),
                          onStop: () => _report(controller.setTalking(false)),
                        )
                      else
                        BrandSecondaryButton(
                          label: session.muted ? 'Unmute' : 'Mute',
                          expand: false,
                          leading: Icon(
                            session.muted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            size: 20,
                            color: BrandColors.textHeadlineAlt,
                          ),
                          onPressed: () => _report(controller.toggleMute()),
                        ),
                      _IconToggle(
                        icon: session.deafened
                            ? Icons.headset_off_rounded
                            : Icons.headset_rounded,
                        label: session.deafened ? 'Undeafen' : 'Deafen',
                        active: session.deafened,
                        onPressed: () => controller.toggleDeafen(),
                      ),
                      _IconToggle(
                        icon: session.cameraOn
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                        label: session.cameraOn ? 'Stop video' : 'Start video',
                        active: session.cameraOn,
                        onPressed: () => _report(controller.toggleCamera()),
                      ),
                      if (session.cameraOn)
                        _IconToggle(
                          icon: Icons.cameraswitch_rounded,
                          label: 'Flip camera',
                          active: false,
                          onPressed: () => _report(controller.switchCamera()),
                        ),
                      _LeaveButton(onPressed: _leave),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Shows a video grid when anyone (self or a teammate) is publishing video;
/// otherwise the plain participant list. Video is opt-in per member, so this
/// degrades to the audio-only list when nobody has a camera on.
class _ParticipantArea extends StatelessWidget {
  const _ParticipantArea({required this.room});

  final lk.Room room;

  static lk.VideoTrack? _localVideo(lk.LocalParticipant p) {
    for (final pub in p.videoTrackPublications) {
      final track = pub.track;
      if (track != null) return track;
    }
    return null;
  }

  static lk.VideoTrack? _remoteVideo(lk.RemoteParticipant p) {
    for (final pub in p.videoTrackPublications) {
      final track = pub.track;
      if (track != null) return track;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <_TileData>[];
    final local = room.localParticipant;
    if (local != null) {
      tiles.add(
        _TileData(
          name: 'You',
          track: _localVideo(local),
          speaking: local.isSpeaking,
          muted: local.isMuted,
        ),
      );
    }
    for (final p in room.remoteParticipants.values) {
      tiles.add(
        _TileData(
          name: p.name.isNotEmpty ? p.name : p.identity,
          track: _remoteVideo(p),
          speaking: p.isSpeaking,
          muted: p.isMuted,
        ),
      );
    }
    if (!tiles.any((t) => t.track != null)) {
      return _ParticipantList(room: room);
    }
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(BrandSpace.sm),
      mainAxisSpacing: BrandSpace.sm,
      crossAxisSpacing: BrandSpace.sm,
      children: [for (final tile in tiles) _VideoTile(data: tile)],
    );
  }
}

/// Everything one video tile needs about a participant.
class _TileData {
  const _TileData({
    required this.name,
    required this.track,
    required this.speaking,
    required this.muted,
  });

  final String name;
  final lk.VideoTrack? track;
  final bool speaking;
  final bool muted;
}

/// One participant's tile: their video (or a placeholder), a name + mic badge,
/// and a speaker highlight. Tapping a live tile opens it full-screen.
class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.data});

  final _TileData data;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: data.track == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => _FullScreenVideo(data: data)),
            ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: BrandColors.neutralButton,
          borderRadius: BorderRadius.circular(12),
          border: data.speaking
              ? Border.all(color: BrandColors.primary, width: 2)
              : null,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (data.track != null)
              lk.VideoTrackRenderer(data.track!)
            else
              Center(
                child: Icon(
                  Icons.person_rounded,
                  size: 32,
                  color: BrandColors.textMuted,
                ),
              ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    data.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    size: 14,
                    color: BrandColors.textHeadline,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    data.name,
                    style: BrandText.labelSm.copyWith(
                      color: BrandColors.textHeadline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One participant's video full-screen (tapped from a grid tile).
class _FullScreenVideo extends StatelessWidget {
  const _FullScreenVideo({required this.data});

  final _TileData data;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(data.name),
      ),
      body: Center(
        child: data.track == null
            ? const Text('Camera off', style: TextStyle(color: Colors.white))
            : lk.VideoTrackRenderer(data.track!),
      ),
    );
  }
}

/// A round icon control (deafen, camera) for the call action row.
class _IconToggle extends StatelessWidget {
  const _IconToggle({
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        child: BrandPressable(
          onTap: onPressed,
          child: Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              color: active
                  ? BrandColors.primaryContainer
                  : BrandColors.neutralButton,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 22,
              color: active ? BrandColors.onPrimary : BrandColors.textHeadline,
            ),
          ),
        ),
      ),
    );
  }
}

/// A "push-to-talk" mode switch, sitting above the call controls.
class _PttToggle extends StatelessWidget {
  const _PttToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BrandSpace.md),
      child: Row(
        children: [
          Icon(
            Icons.record_voice_over_rounded,
            size: 18,
            color: BrandColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Push to talk',
              style: BrandText.titleSm.copyWith(
                color: BrandColors.textHeadline,
              ),
            ),
          ),
          HapticSwitch(value: value, onChange: onChanged),
        ],
      ),
    );
  }
}

/// A press-and-hold mic button: open while held, closed on release. The
/// convoy's walkie-talkie affordance.
class _HoldToTalkButton extends StatelessWidget {
  const _HoldToTalkButton({
    required this.talking,
    required this.onStart,
    required this.onStop,
  });

  final bool talking;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final fg = talking ? BrandColors.onPrimary : BrandColors.textHeadline;
    final iconColor = talking ? BrandColors.onPrimary : BrandColors.primary;
    return GestureDetector(
      onTapDown: (_) => onStart(),
      onTapUp: (_) => onStop(),
      onTapCancel: onStop,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: talking
              ? BrandColors.primaryContainer
              : BrandColors.neutralButton,
          borderRadius: BrandRadii.pill,
          boxShadow: talking ? BrandShadows.primaryGlow : BrandShadows.subtle,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              talking ? Icons.mic_rounded : Icons.mic_none_rounded,
              size: 20,
              color: iconColor,
            ),
            const SizedBox(width: 8),
            Text(
              talking ? 'Talking…' : 'Hold to talk',
              style: BrandText.labelLg.copyWith(color: fg),
            ),
          ],
        ),
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Real live level from LiveKit, shown only while they're speaking.
          if (participant.isSpeaking && !participant.isMuted) ...[
            _LevelMeter(level: participant.audioLevel),
            const SizedBox(width: 8),
          ],
          Icon(
            participant.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            size: 20,
            color: participant.isMuted
                ? BrandColors.textMuted
                : BrandColors.primary,
          ),
        ],
      ),
    );
  }
}

/// A tiny level meter driven by LiveKit's real `audioLevel` (0..1).
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 18,
      alignment: Alignment.bottomCenter,
      decoration: BoxDecoration(
        color: BrandColors.surfaceContainerHigh,
        borderRadius: BrandRadii.pill,
      ),
      child: FractionallySizedBox(
        heightFactor: level.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: BrandColors.primaryContainer,
            borderRadius: BrandRadii.pill,
          ),
        ),
      ),
    );
  }
}
