import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_alert.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
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
              child: Column(
                children: [
                  _PttToggle(
                    value: session.ptt,
                    onChanged: (on) => _report(controller.setPtt(on)),
                  ),
                  const SizedBox(height: BrandSpace.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                      const SizedBox(width: BrandSpace.md),
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
          FSwitch(value: value, onChange: onChanged),
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
