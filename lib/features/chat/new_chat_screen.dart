import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../../core/widgets/pull_to_refresh.dart';
import '../../data/models/group.dart';
import '../../data/models/trip.dart';
import '../../data/services/supabase_service.dart';
import '../social/friends_screen.dart';
import '../social/groups_screen.dart';
import '../social/invite_share.dart';
import '../social/social_providers.dart';
import '../social/user_profile_screen.dart';
import '../trip/new_trip_screen.dart';
import '../trip/trip_providers.dart';
import 'chat_providers.dart';
import 'chat_screen.dart';
import 'direct_messages_screen.dart';

/// Opens the "start a chat" picker.
Future<void> showNewChat(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NewChatScreen()));

/// WhatsApp's "select contact" screen, for a road-trip app: one place to start
/// a conversation with any friend, group or trip, plus the shortcuts that grow
/// the network — add a friend, form a group, plan a trip.
class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(String text) =>
      _query.isEmpty || text.toLowerCase().contains(_query);

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  void _openGroup(Group g) => Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) =>
          ChatScreen(channel: ChatChannel.group(g.id), title: g.name),
    ),
  );

  void _openTrip(Trip t) => Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) =>
          ChatScreen(channel: ChatChannel.trip(t.id), title: t.title),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendsProvider);
    final groups = ref.watch(myGroupsProvider).valueOrNull ?? const <Group>[];
    final trips =
        [
          for (final t
              in ref.watch(myTripsProvider).valueOrNull ?? const <Trip>[])
            if (t.status == TripStatus.active || t.status == TripStatus.planned)
              t,
        ]..sort(
          (a, b) => a.status == b.status
              ? 0
              : a.status == TripStatus.active
              ? -1
              : 1,
        );

    final myUid = SupabaseService.currentUser?.id;
    final friends =
        <Map<String, dynamic>>[
          for (final row in friendsAsync.valueOrNull ?? const [])
            if ((row['requester_id'] == myUid
                    ? row['addressee']
                    : row['requester'])
                case final Map<String, dynamic> person)
              person,
        ]..sort(
          (a, b) => (a['username'] as String? ?? '').toLowerCase().compareTo(
            (b['username'] as String? ?? '').toLowerCase(),
          ),
        );

    final shownFriends = [
      for (final f in friends)
        if (_matches('${f['username']} ${f['display_name'] ?? ''}')) f,
    ];
    final shownGroups = [
      for (final g in groups)
        if (_matches(g.name)) g,
    ];
    final shownTrips = [
      for (final t in trips)
        if (_matches(t.title)) t,
    ];
    final searching = _query.isNotEmpty;

    return BrandScaffold(
      header: BrandHeader(
        title: 'New chat',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: BrandSpace.md),
            child: Container(
              decoration: BoxDecoration(
                color: BrandColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                textInputAction: TextInputAction.search,
                style: BrandText.bodyMd.copyWith(
                  color: BrandColors.textHeadline,
                ),
                decoration: InputDecoration(
                  hintText: 'Search friends, groups and trips',
                  hintStyle: BrandText.bodyMd.copyWith(
                    color: BrandColors.textMuted,
                  ),
                  icon: Icon(
                    Icons.search_rounded,
                    color: BrandColors.textMuted,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          Expanded(
            child: PullToRefresh(
              onRefresh: () => Future.wait([
                ref.refresh(friendsProvider.future),
                ref.refresh(myGroupsProvider.future),
                ref.refresh(myTripsProvider.future),
              ]),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(
                  top: BrandSpace.md,
                  bottom: BrandSpace.xl,
                ),
                children: [
                  if (!searching) ...[
                    _Shortcuts(
                      onNewGroup: () => createGroupFlow(context, ref),
                      onAddFriend: () =>
                          _push(const FriendsScreen(initialTab: 2)),
                      onPlanTrip: () => _push(const NewTripScreen()),
                      onInvite: () => shareMyInviteLink(context, ref),
                    ),
                    const SizedBox(height: BrandSpace.lg),
                  ],
                  if (friendsAsync.hasError && friends.isEmpty)
                    ErrorRetry(
                      error: friendsAsync.error!,
                      onRetry: () => ref.invalidate(friendsProvider),
                    ),
                  if (shownTrips.isNotEmpty)
                    _Section(
                      title: 'Trips',
                      children: [
                        for (final t in shownTrips)
                          _Tile(
                            leading: _IconCircle(
                              icon: t.status == TripStatus.active
                                  ? Icons.navigation_rounded
                                  : Icons.route_rounded,
                            ),
                            title: t.title,
                            subtitle: t.status == TripStatus.active
                                ? 'Live now'
                                : 'Planned',
                            onTap: () => _openTrip(t),
                          ),
                      ],
                    ),
                  if (shownGroups.isNotEmpty)
                    _Section(
                      title: 'Groups',
                      children: [
                        for (final g in shownGroups)
                          _Tile(
                            leading: AvatarView(
                              seed: g.avatarId,
                              size: 44,
                              background: BrandColors.surfaceContainerLow,
                              accentColor: BrandColors.primary,
                            ),
                            title: g.name,
                            subtitle: 'Group',
                            onTap: () => _openGroup(g),
                          ),
                      ],
                    ),
                  if (shownFriends.isNotEmpty)
                    _Section(
                      title: 'Friends',
                      children: [
                        for (final f in shownFriends)
                          _Tile(
                            leading: GestureDetector(
                              onTap: () =>
                                  openUserProfile(context, f['id'] as String),
                              child: AvatarView(
                                seed: f['avatar_id'] as String? ?? 'default',
                                size: 44,
                                background: BrandColors.surfaceContainerLow,
                                accentColor: BrandColors.primary,
                              ),
                            ),
                            title:
                                (f['display_name'] as String?)?.isNotEmpty ==
                                    true
                                ? f['display_name'] as String
                                : '@${f['username']}',
                            subtitle:
                                (f['display_name'] as String?)?.isNotEmpty ==
                                    true
                                ? '@${f['username']}'
                                : 'Friend',
                            onTap: () => openDirectChat(
                              context,
                              ref,
                              otherUserId: f['id'] as String,
                              title:
                                  (f['display_name'] as String?)?.isNotEmpty ==
                                      true
                                  ? f['display_name'] as String
                                  : '@${f['username']}',
                              replace: true,
                            ),
                          ),
                      ],
                    ),
                  if (searching &&
                      shownFriends.isEmpty &&
                      shownGroups.isEmpty &&
                      shownTrips.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: BrandSpace.xl),
                      child: Column(
                        children: [
                          Text(
                            'No matches for "$_query"',
                            style: BrandText.bodyMd.copyWith(
                              color: BrandColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: BrandSpace.sm),
                          TextButton(
                            onPressed: () =>
                                _push(const FriendsScreen(initialTab: 2)),
                            child: const Text('Find people to add'),
                          ),
                        ],
                      ),
                    ),
                  if (!searching && friends.isEmpty && !friendsAsync.isLoading)
                    Padding(
                      padding: const EdgeInsets.only(top: BrandSpace.sm),
                      child: Text(
                        'No friends yet — add some to message them.',
                        textAlign: TextAlign.center,
                        style: BrandText.bodyMd.copyWith(
                          color: BrandColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The growth shortcuts pinned above the contact list.
class _Shortcuts extends StatelessWidget {
  const _Shortcuts({
    required this.onNewGroup,
    required this.onAddFriend,
    required this.onPlanTrip,
    required this.onInvite,
  });

  final VoidCallback onNewGroup;
  final VoidCallback onAddFriend;
  final VoidCallback onPlanTrip;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      padding: const EdgeInsets.symmetric(
        horizontal: BrandSpace.md,
        vertical: BrandSpace.xs,
      ),
      child: Column(
        children: [
          BrandListRow(
            icon: Icons.group_add_rounded,
            iconColor: BrandColors.primary,
            title: 'New group',
            subtitle: 'A crew that rolls together',
            onTap: onNewGroup,
          ),
          const BrandRowDivider(),
          BrandListRow(
            icon: Icons.person_add_alt_1_rounded,
            iconColor: BrandColors.primary,
            title: 'Add friend',
            subtitle: 'Find by username',
            onTap: onAddFriend,
          ),
          const BrandRowDivider(),
          BrandListRow(
            icon: Icons.add_road_rounded,
            iconColor: BrandColors.primary,
            title: 'Plan a trip',
            subtitle: 'Every trip gets its own chat and voice',
            onTap: onPlanTrip,
          ),
          const BrandRowDivider(),
          BrandListRow(
            icon: Icons.ios_share_rounded,
            iconColor: BrandColors.primary,
            title: 'Invite friends',
            subtitle: 'Share your invite link',
            onTap: onInvite,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BrandSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: BrandSpace.xs,
              bottom: BrandSpace.sm,
            ),
            child: Text(
              title,
              style: BrandText.labelMd.copyWith(color: BrandColors.textMuted),
            ),
          ),
          BrandCard(
            padding: const EdgeInsets.symmetric(
              horizontal: BrandSpace.md,
              vertical: BrandSpace.xs,
            ),
            child: Column(
              children: [
                for (final (i, c) in children.indexed) ...[
                  if (i > 0) const BrandRowDivider(),
                  c,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BrandRadii.cardRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
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
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      width: 44,
      decoration: BoxDecoration(
        color: BrandColors.secondaryFixed.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: BrandColors.primary, size: 22),
    );
  }
}
