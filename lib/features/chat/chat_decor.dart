import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/widgets/avatar_view.dart';
import '../../data/models/trip.dart';
import '../social/group_detail_screen.dart';
import '../social/social_providers.dart';
import '../social/user_profile_screen.dart';
import '../trip/trip_detail_screen.dart';
import '../trip/trip_providers.dart';
import 'chat_providers.dart';
import 'voice_channel_screen.dart';

/// A faint road-trip doodle wallpaper behind the messages (WhatsApp's pattern,
/// in this app's vocabulary), so an empty or sparse thread doesn't read as a
/// blank page. Drawn once per size and cached by [RepaintBoundary].
class ChatBackground extends StatelessWidget {
  const ChatBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: BrandColors.surfaceContainerLow.withValues(alpha: 0.45),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _DoodlePainter(
                BrandColors.textMuted.withValues(alpha: 0.10),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _DoodlePainter extends CustomPainter {
  _DoodlePainter(this.color);

  final Color color;

  static const _icons = <IconData>[
    Icons.directions_car_rounded,
    Icons.place_rounded,
    Icons.alt_route_rounded,
    Icons.explore_rounded,
    Icons.local_gas_station_rounded,
    Icons.terrain_rounded,
    Icons.camera_alt_rounded,
    Icons.two_wheeler_rounded,
    Icons.local_cafe_rounded,
    Icons.flag_rounded,
    Icons.landscape_rounded,
    Icons.sports_score_rounded,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 76.0;
    final cols = (size.width / cell).ceil() + 1;
    final rows = (size.height / cell).ceil() + 1;
    var n = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        // Stagger alternate rows and vary icon/rotation deterministically so the
        // pattern looks scattered but never shimmers between repaints.
        // A cheap integer hash, so neighbours differ without any visible grid.
        final h =
            ((r * 73856093) ^ (c * 19349663) ^ (n * 83492791)) & 0x7fffffff;
        final icon = _icons[h % _icons.length];
        n++;
        final dx =
            c * cell + (r.isOdd ? cell / 2 : 0) + ((c * 7 + r * 3) % 11) - 5;
        final dy = r * cell + ((c * 5 + r * 9) % 13) - 6;
        final tp = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontSize: 26,
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        canvas.save();
        canvas.translate(dx + tp.width / 2, dy + tp.height / 2);
        canvas.rotate(((c * 37 + r * 53) % 60 - 30) * math.pi / 180);
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_DoodlePainter old) => old.color != color;
}

/// The chat's top bar: back, the person/group/trip's avatar and name with a
/// live subtitle, and the actions that belong to it. Tapping the title area
/// opens their profile (a person), or the group / trip itself.
class ChatHeader extends ConsumerWidget {
  const ChatHeader({super.key, required this.channel, required this.title});

  final ChatChannel channel;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String subtitle = '';
    Widget avatar = _CircleIcon(icon: Icons.chat_rounded);
    VoidCallback? openInfo;

    if (channel.isDirect) {
      final conv = (ref.watch(conversationsProvider).valueOrNull ?? const [])
          .where((c) => c.id == channel.conversationId)
          .firstOrNull;
      if (conv != null) {
        subtitle = conv.title == '@${conv.username}'
            ? 'Tap for profile'
            : '@${conv.username}';
        avatar = AvatarView(seed: conv.avatarId, size: 40);
        openInfo = () => openUserProfile(context, conv.otherId);
      }
    } else if (channel.groupId != null) {
      final group = (ref.watch(myGroupsProvider).valueOrNull ?? const [])
          .where((g) => g.id == channel.groupId)
          .firstOrNull;
      final count = ref
          .watch(groupMembersProvider(channel.groupId!))
          .valueOrNull
          ?.where((m) => m['status'] == 'active')
          .length;
      subtitle = count == null
          ? 'Group'
          : '$count member${count == 1 ? '' : 's'}';
      if (group != null) {
        avatar = AvatarView(seed: group.avatarId, size: 40);
        openInfo = () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => GroupDetailScreen(group: group)),
        );
      }
    } else if (channel.tripId != null) {
      final trip = (ref.watch(myTripsProvider).valueOrNull ?? const [])
          .where((t) => t.id == channel.tripId)
          .firstOrNull;
      final count = ref
          .watch(tripMembersProvider(channel.tripId!))
          .valueOrNull
          ?.length;
      final status = switch (trip?.status) {
        TripStatus.active => 'Live now',
        TripStatus.planned => 'Planned',
        TripStatus.completed => 'Completed',
        _ => 'Trip',
      };
      subtitle = count == null
          ? status
          : '$status · $count member${count == 1 ? '' : 's'}';
      avatar = _CircleIcon(
        icon: trip?.status == TripStatus.active
            ? Icons.navigation_rounded
            : Icons.route_rounded,
      );
      if (trip != null) {
        openInfo = () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => TripDetailScreen(trip: trip)));
      }
    }

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: BrandSpace.xs),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border: Border(bottom: BorderSide(color: BrandColors.hairline)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: InkWell(
              onTap: openInfo,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    avatar,
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BrandText.titleSm.copyWith(
                              color: BrandColors.textHeadline,
                            ),
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BrandText.bodySm.copyWith(
                                color: BrandColors.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Voice rooms belong to trips and groups; a direct message has none.
          if (!channel.isDirect)
            IconButton(
              tooltip: 'Voice channel',
              icon: const Icon(Icons.call_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      VoiceChannelScreen(channel: channel, title: title),
                ),
              ),
            ),
          if (openInfo != null)
            IconButton(
              tooltip: channel.isDirect
                  ? 'View profile'
                  : channel.groupId != null
                  ? 'Group info'
                  : 'Trip details',
              icon: Icon(
                channel.isDirect
                    ? Icons.person_rounded
                    : Icons.info_outline_rounded,
              ),
              onPressed: openInfo,
            ),
        ],
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      width: 40,
      decoration: BoxDecoration(
        color: BrandColors.secondaryFixed.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: BrandColors.primary, size: 22),
    );
  }
}
