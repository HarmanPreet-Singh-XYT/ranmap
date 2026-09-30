import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/network/backend_client.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_sheet_surface.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/group.dart';
import '../../data/models/map_post.dart';
import '../../data/models/trip.dart';
import '../../data/services/supabase_service.dart';
import '../map/map_post_providers.dart';
import '../social/social_providers.dart';
import '../trip/trip_providers.dart';
import 'chat_providers.dart';

/// Something to send into a chat: a kind, its structured payload, and a plain
/// text [fallback] used as the message body (push previews, older app versions,
/// and "copy text").
class ChatShare {
  const ChatShare({
    required this.kind,
    required this.fallback,
    this.payload,
  });

  final ChatMessageKind kind;
  final String fallback;
  final Map<String, dynamic>? payload;

  /// A spot on the map — a dropped pin, a place, or the sender's own position.
  factory ChatShare.location({
    required double lat,
    required double lng,
    String? name,
  }) => ChatShare(
    kind: ChatMessageKind.location,
    fallback: name != null ? 'Shared location: $name' : 'Shared location',
    payload: {'lat': lat, 'lng': lng, 'name': ?name},
  );

  /// One or more pinned photos.
  factory ChatShare.photos({
    required List<String> postIds,
    required double lat,
    required double lng,
  }) => ChatShare(
    kind: ChatMessageKind.photo,
    fallback: postIds.length == 1
        ? 'Pinned image'
        : '${postIds.length} pinned images',
    payload: {
      'posts': [
        for (final id in postIds) {'id': id},
      ],
      'lat': lat,
      'lng': lng,
    },
  );

  /// A trip, as a card the recipient can open if they're on it.
  factory ChatShare.trip({required String tripId, required String title}) =>
      ChatShare(
        kind: ChatMessageKind.trip,
        fallback: 'Trip: $title',
        payload: {'trip_id': tripId, 'title': title},
      );
}

/// Sends [share] into [channel] and pings the other members.
///
/// Throws on failure (the caller decides how to surface it). Rich messages skip
/// the offline queue on purpose: a photo share also grants access on the server,
/// which only makes sense when it actually reaches it.
Future<void> sendChatShare(
  WidgetRef ref,
  ChatChannel channel,
  ChatShare share,
) async {
  await ref
      .read(chatRepositoryProvider)
      .sendMessage(
        tripId: channel.tripId,
        groupId: channel.groupId,
        conversationId: channel.conversationId,
        body: share.fallback,
        kind: share.kind,
        payload: share.payload,
      );
  ref.invalidate(chatMessagesProvider(channel));
  unawaited(notifyChatPush(channel, kind: share.kind));
}

/// Tells the server to push a chat message to the channel's other members.
/// Best-effort: the message is already stored, so a push failure isn't a send
/// failure.
Future<void> notifyChatPush(ChatChannel channel, {ChatMessageKind? kind}) async {
  try {
    await BackendClient.postJson(
      '/notifications/chat-message',
      {
        if (channel.tripId != null) 'tripId': channel.tripId,
        if (channel.groupId != null) 'groupId': channel.groupId,
        if (channel.conversationId != null)
          'conversationId': channel.conversationId,
        if (kind != null && kind != ChatMessageKind.text) 'kind': kind.wire,
      },
      fallbackMessage: 'Could not notify the channel',
    );
  } catch (_) {
    // Best-effort only.
  }
}

/// Opens a "Send to…" sheet listing friends (direct message), groups and trips,
/// and sends [share] to each one the user taps. Returns true if anything was
/// sent.
Future<bool> showShareToSheet(
  BuildContext context,
  WidgetRef ref, {
  required ChatShare share,
  String title = 'Send to',
}) async {
  final sent = await showFSheet<bool>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: 0.8,
    builder: (_) => _ShareToSheet(share: share, title: title),
  );
  return sent ?? false;
}

class _ShareToSheet extends ConsumerStatefulWidget {
  const _ShareToSheet({required this.share, required this.title});

  final ChatShare share;
  final String title;

  @override
  ConsumerState<_ShareToSheet> createState() => _ShareToSheetState();
}

class _ShareToSheetState extends ConsumerState<_ShareToSheet> {
  /// Destinations already sent to, so a second tap can't double-send.
  final Set<String> _sent = {};
  String? _sendingKey;

  Future<void> _send(String key, Future<ChatChannel> Function() resolve) async {
    if (_sendingKey != null || _sent.contains(key)) return;
    setState(() => _sendingKey = key);
    try {
      final channel = await resolve();
      await sendChatShare(ref, channel, widget.share);
      if (mounted) setState(() => _sent.add(key));
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _sendingKey = null);
    }
  }

  Widget _trailing(String key) {
    if (_sendingKey == key) {
      return const SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_sent.contains(key)) {
      return Icon(Icons.check_circle_rounded, color: BrandColors.primary);
    }
    return Icon(Icons.send_rounded, size: 18, color: BrandColors.textMuted);
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider).valueOrNull ?? const [];
    final groups = ref.watch(myGroupsProvider).valueOrNull ?? const <Group>[];
    final trips = ref.watch(myTripsProvider).valueOrNull ?? const <Trip>[];
    final myUid = SupabaseService.currentUser?.id;

    final people = <Map<String, dynamic>>[
      for (final row in friends)
        if ((row['requester_id'] == myUid ? row['addressee'] : row['requester'])
            case final Map<String, dynamic> person)
          person,
    ];
    final activeTrips = [
      for (final t in trips)
        if (t.status == TripStatus.active || t.status == TripStatus.planned) t,
    ];

    Widget section(String label, List<Widget> rows) => rows.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  top: BrandSpace.md,
                  bottom: BrandSpace.xs,
                ),
                child: Text(
                  label,
                  style: BrandText.labelLg.copyWith(
                    color: BrandColors.textMuted,
                  ),
                ),
              ),
              BrandCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: BrandSpace.md,
                  vertical: BrandSpace.xs,
                ),
                child: Column(children: rows),
              ),
            ],
          );

    List<Widget> rows(List<Widget> items) => [
      for (final (i, item) in items.indexed) ...[
        if (i > 0) const BrandRowDivider(),
        item,
      ],
    ];

    final nothing = people.isEmpty && groups.isEmpty && activeTrips.isEmpty;

    return BrandSheetSurface(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: BrandText.titleMd.copyWith(color: BrandColors.textHeadline),
            ),
            Text(
              widget.share.fallback,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
            ),
            if (nothing)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: BrandSpace.lg),
                child: Text(
                  'Add a friend, join a group or plan a trip to share with.',
                  style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
                ),
              ),
            section(
              'Friends',
              rows([
                for (final person in people)
                  BrandListRow(
                    icon: Icons.person_rounded,
                    iconColor: BrandColors.primary,
                    title: (person['display_name'] as String?)?.isNotEmpty == true
                        ? person['display_name'] as String
                        : '@${person['username']}',
                    subtitle: '@${person['username']}',
                    showChevron: false,
                    trailing: _trailing('u:${person['id']}'),
                    onTap: () => _send('u:${person['id']}', () async {
                      final id = await ref
                          .read(chatRepositoryProvider)
                          .conversationWith(person['id'] as String);
                      return ChatChannel.direct(id);
                    }),
                  ),
              ]),
            ),
            section(
              'Groups',
              rows([
                for (final g in groups)
                  BrandListRow(
                    icon: Icons.groups_rounded,
                    iconColor: BrandColors.primary,
                    title: g.name,
                    showChevron: false,
                    trailing: _trailing('g:${g.id}'),
                    onTap: () =>
                        _send('g:${g.id}', () async => ChatChannel.group(g.id)),
                  ),
              ]),
            ),
            section(
              'Trips',
              rows([
                for (final t in activeTrips)
                  BrandListRow(
                    icon: Icons.directions_car_filled_rounded,
                    iconColor: BrandColors.primary,
                    title: t.title,
                    showChevron: false,
                    trailing: _trailing('t:${t.id}'),
                    onTap: () =>
                        _send('t:${t.id}', () async => ChatChannel.trip(t.id)),
                  ),
              ]),
            ),
            const SizedBox(height: BrandSpace.md),
            TextButton(
              onPressed: () => Navigator.of(context).pop(_sent.isNotEmpty),
              child: Text(_sent.isEmpty ? 'Cancel' : 'Done'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets the user choose some of their own pinned photos to send. Returns the
/// chosen posts (oldest selection first), or null if dismissed.
Future<List<MapPost>?> showPhotoPickerSheet(BuildContext context) {
  return showFSheet<List<MapPost>>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: 0.85,
    builder: (_) => const _PhotoPickerSheet(),
  );
}

class _PhotoPickerSheet extends ConsumerStatefulWidget {
  const _PhotoPickerSheet();

  @override
  ConsumerState<_PhotoPickerSheet> createState() => _PhotoPickerSheetState();
}

class _PhotoPickerSheetState extends ConsumerState<_PhotoPickerSheet> {
  static const _max = 10;
  final List<MapPost> _picked = [];

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(allPhotosProvider);
    return BrandSheetSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Send pinned photos',
            style: BrandText.titleMd.copyWith(color: BrandColors.textHeadline),
          ),
          const SizedBox(height: BrandSpace.sm),
          Expanded(
            child: photosAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(friendlyError(e))),
              data: (all) {
                final mine = [
                  for (final p in all)
                    if (p.isMine) p.post,
                ];
                if (mine.isEmpty) {
                  return Center(
                    child: Text(
                      'You have no pinned photos yet.',
                      style: BrandText.bodyMd.copyWith(
                        color: BrandColors.textMuted,
                      ),
                    ),
                  );
                }
                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: mine.length,
                  itemBuilder: (context, i) {
                    final post = mine[i];
                    final index = _picked.indexWhere((p) => p.id == post.id);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (index >= 0) {
                          _picked.removeAt(index);
                        } else if (_picked.length < _max) {
                          _picked.add(post);
                        }
                      }),
                      child: _PickerThumb(post: post, order: index < 0 ? null : index + 1),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: BrandSpace.sm),
          FilledButton(
            onPressed: _picked.isEmpty
                ? null
                : () => Navigator.of(context).pop(List.of(_picked)),
            child: Text(
              _picked.isEmpty
                  ? 'Select photos'
                  : 'Send ${_picked.length} ${_picked.length == 1 ? 'photo' : 'photos'}',
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerThumb extends ConsumerWidget {
  const _PickerThumb({required this.post, required this.order});

  final MapPost post;
  final int? order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(mapPostSignedUrlProvider(post.storagePath));
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          urlAsync.when(
            loading: () => Container(color: BrandColors.surfaceContainerLow),
            error: (_, _) => Container(color: BrandColors.surfaceContainerLow),
            data: (url) => CachedNetworkImage(
              imageUrl: url,
              cacheKey: post.storagePath,
              fit: BoxFit.cover,
              memCacheWidth: 300,
            ),
          ),
          if (order != null) ...[
            Container(color: Colors.black38),
            Positioned(
              top: 6,
              right: 6,
              child: CircleAvatar(
                radius: 11,
                backgroundColor: BrandColors.primaryContainer,
                child: Text(
                  '$order',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.onPrimary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
