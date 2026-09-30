import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import 'voice_channel_screen.dart';
import 'voice_session.dart';

/// A slim, always-visible strip for the app-wide voice session: where you're in
/// voice, a mute toggle, and leave. Tapping the label opens the full channel.
/// Renders nothing when there is no session.
class VoiceMiniBar extends ConsumerWidget {
  const VoiceMiniBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(voiceSessionProvider);
    final channel = session.channel;
    if (channel == null || !session.inCall) return const SizedBox.shrink();

    final controller = ref.read(voiceSessionProvider.notifier);
    final connected = session.status == VoiceStatus.connected;
    final failed = session.status == VoiceStatus.error;
    final label = failed
        ? 'Voice unavailable — tap to retry'
        : connected && !session.reconnecting
        ? 'In voice · ${session.title}'
        : 'Connecting voice…';

    return Material(
      color: BrandColors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BrandSpace.md),
        child: Row(
          children: [
            Icon(
              failed ? Icons.error_outline_rounded : Icons.graphic_eq_rounded,
              size: 18,
              color: BrandColors.onPrimary,
            ),
            const SizedBox(width: BrandSpace.sm),
            Expanded(
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VoiceChannelScreen(
                      channel: channel,
                      title: session.title,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.labelLg.copyWith(
                      color: BrandColors.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
            if (connected && !session.ptt)
              IconButton(
                tooltip: session.muted ? 'Unmute' : 'Mute',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  session.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  color: BrandColors.onPrimary,
                ),
                onPressed: controller.toggleMute,
              ),
            IconButton(
              tooltip: 'Leave voice',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.call_end_rounded, color: BrandColors.onPrimary),
              onPressed: controller.leave,
            ),
          ],
        ),
      ),
    );
  }
}
