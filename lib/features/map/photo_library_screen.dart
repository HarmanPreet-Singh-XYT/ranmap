import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/geo_distance.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_skeleton.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/map_post.dart';
import '../../data/models/trip.dart';
import '../trip/trip_providers.dart';
import 'map_photo_tile.dart';
import 'map_post_providers.dart';
import 'saved_place_providers.dart';

/// Photos within this distance of each other belong to the same location.
const _spotRadiusMeters = 150.0;

/// How close a saved place / trip endpoint must be to name a spot after it.
const _saveNameRadiusMeters = 300.0;
const _tripNameRadiusMeters = 2000.0;

/// One location in the library: the photos taken there and what to call it.
class _PhotoSpot {
  _PhotoSpot(this.lat, this.lng);

  double lat;
  double lng;
  final List<MapPost> posts = [];
  String title = '';

  DateTime get latest => posts
      .map((p) => p.createdAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);
}

/// Every photo in one place, grouped by location. Each location is a
/// collapsible section, and the search box filters by place, caption, trip or
/// poster — so finding a photo doesn't mean hunting for its pin on the map.
class PhotoLibraryScreen extends ConsumerStatefulWidget {
  const PhotoLibraryScreen({super.key});

  @override
  ConsumerState<PhotoLibraryScreen> createState() => _PhotoLibraryScreenState();
}

enum _Scope { all, mine, others }

class _PhotoLibraryScreenState extends ConsumerState<PhotoLibraryScreen> {
  final _search = TextEditingController();
  String _query = '';
  _Scope _scope = _Scope.all;
  final Set<String> _expanded = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Groups [posts] into locations (greedy, nearest-centre within the radius),
  /// names each one, and orders them by most recent photo.
  List<_PhotoSpot> _buildSpots(
    List<MapPost> posts,
    Map<String, Trip> trips,
    List<({String name, double lat, double lng})> landmarks,
  ) {
    final spots = <_PhotoSpot>[];
    for (final post in posts) {
      _PhotoSpot? home;
      var best = _spotRadiusMeters;
      for (final spot in spots) {
        final d = haversineMeters(spot.lat, spot.lng, post.lat, post.lng);
        if (d <= best) {
          best = d;
          home = spot;
        }
      }
      if (home == null) {
        home = _PhotoSpot(post.lat, post.lng);
        spots.add(home);
      }
      home.posts.add(post);
      // Keep the centre on the running mean so a long strip doesn't drift.
      final n = home.posts.length;
      home.lat += (post.lat - home.lat) / n;
      home.lng += (post.lng - home.lng) / n;
    }
    for (final spot in spots) {
      spot.posts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      spot.title = _nameFor(spot, trips, landmarks);
    }
    spots.sort((a, b) => b.latest.compareTo(a.latest));
    return spots;
  }

  String _nameFor(
    _PhotoSpot spot,
    Map<String, Trip> trips,
    List<({String name, double lat, double lng})> landmarks,
  ) {
    String? nearest;
    var best = double.infinity;
    for (final l in landmarks) {
      final d = haversineMeters(spot.lat, spot.lng, l.lat, l.lng);
      final limit = l.name.startsWith('\u0000')
          ? _tripNameRadiusMeters
          : _saveNameRadiusMeters;
      if (d <= limit && d < best) {
        best = d;
        nearest = l.name.replaceFirst('\u0000', '');
      }
    }
    if (nearest != null && nearest.trim().isNotEmpty) return nearest;
    return 'Spot at ${spot.lat.toStringAsFixed(3)}, ${spot.lng.toStringAsFixed(3)}';
  }

  bool _matches(
    MapPost post,
    _PhotoSpot spot,
    Map<String, Trip> trips,
    Map<String, LibraryPhoto> byId,
    String q,
  ) {
    final haystack = [
      spot.title,
      ...?byId[post.id]?.groupNames,
      post.caption ?? '',
      post.posterUsername ?? '',
      trips[post.tripId]?.title ?? '',
      DateFormat.yMMMd().format(post.createdAt.toLocal()),
      DateFormat.MMMM().format(post.createdAt.toLocal()),
    ].join(' ').toLowerCase();
    return q.split(RegExp(r'\s+')).every(haystack.contains);
  }

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(allPhotosProvider);
    final trips = {
      for (final t in ref.watch(myTripsProvider).valueOrNull ?? const <Trip>[])
        t.id: t,
    };
    final saved = ref.watch(savedPlacesProvider).valueOrNull ?? const [];
    // Landmarks that can name a spot: saved places (tight radius) and trip
    // endpoints (wide radius, marked with a leading NUL so the matcher can tell
    // them apart without a second list).
    final landmarks = <({String name, double lat, double lng})>[
      for (final p in saved)
        if (p.point != null)
          (name: p.name, lat: p.point!.lat, lng: p.point!.lng),
      for (final t in trips.values) ...[
        if (t.originPoint != null && (t.originName ?? '').isNotEmpty)
          (
            name: '\u0000${t.originName}',
            lat: t.originPoint!.lat,
            lng: t.originPoint!.lng,
          ),
        if (t.destinationPoint != null && (t.destinationName ?? '').isNotEmpty)
          (
            name: '\u0000${t.destinationName}',
            lat: t.destinationPoint!.lat,
            lng: t.destinationPoint!.lng,
          ),
      ],
    ];

    return BrandScaffold(
      header: BrandHeader(
        title: 'Photos',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: photosAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: BrandSpace.md),
          child: BrandSkeletonList(count: 5),
        ),
        error: (e, _) => ErrorRetry(
          error: e,
          onRetry: () => ref.invalidate(allPhotosProvider),
        ),
        data: (photos) {
          final byId = {for (final p in photos) p.post.id: p};
          final mineCount = photos.where((p) => p.isMine).length;
          final scoped = [
            for (final p in photos)
              if (_scope == _Scope.all ||
                  (_scope == _Scope.mine) == p.isMine)
                p.post,
          ];
          final posts = scoped;
          if (photos.isEmpty) {
            return const Center(
              child: BrandEmptyState(
                icon: Icons.photo_library_outlined,
                title: 'No photos yet',
                message:
                    'Hold a spot on the map and choose Photo to pin pictures there. They collect here, grouped by place.',
              ),
            );
          }
          final spots = _buildSpots(posts, trips, landmarks);
          final hasOthers = photos.length > mineCount;
          final q = _query.trim().toLowerCase();
          final searching = q.isNotEmpty;

          // When searching, each spot shows only its matching photos.
          final visible = <({_PhotoSpot spot, List<MapPost> posts})>[];
          for (final spot in spots) {
            final hits = searching
                ? [
                    for (final p in spot.posts)
                      if (_matches(p, spot, trips, byId, q)) p,
                  ]
                : spot.posts;
            if (hits.isNotEmpty) visible.add((spot: spot, posts: hits));
          }
          final photoCount = visible.fold<int>(0, (n, e) => n + e.posts.length);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: BrandSpace.md),
                child: BrandTextField(
                  controller: _search,
                  hint: 'Search places, captions, trips…',
                  leadingIcon: Icons.search_rounded,
                  textInputAction: TextInputAction.search,
                  onChanged: (v) => setState(() => _query = v),
                  trailing: searching
                      ? IconButton(
                          tooltip: 'Clear',
                          icon: Icon(
                            Icons.close_rounded,
                            color: BrandColors.textMuted,
                          ),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                ),
              ),
              if (hasOthers && mineCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: BrandSpace.sm),
                  child: Row(
                    children: [
                      for (final (scope, label) in const [
                        (_Scope.all, 'All'),
                        (_Scope.mine, 'Mine'),
                        (_Scope.others, 'From others'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(label),
                            selected: _scope == scope,
                            onSelected: (_) => setState(() => _scope = scope),
                          ),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: BrandSpace.sm),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    searching
                        ? '$photoCount ${photoCount == 1 ? 'photo' : 'photos'} in ${visible.length} ${visible.length == 1 ? 'place' : 'places'}'
                        : '${posts.length} ${posts.length == 1 ? 'photo' : 'photos'} · ${spots.length} ${spots.length == 1 ? 'place' : 'places'}',
                    style: BrandText.bodySm.copyWith(
                      color: BrandColors.textMuted,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: BrandEmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No matches',
                          message: searching
                              ? 'Nothing matches "${_query.trim()}".'
                              : 'No photos in this view.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: BrandSpace.lg),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: BrandSpace.sm),
                        itemBuilder: (context, i) {
                          final entry = visible[i];
                          final key =
                              '${entry.spot.lat.toStringAsFixed(4)},${entry.spot.lng.toStringAsFixed(4)}';
                          return _SpotSection(
                            spot: entry.spot,
                            shown: entry.posts,
                            posterNames: {
                              for (final p in entry.posts)
                                if (!(byId[p.id]?.isMine ?? true))
                                  '@${p.posterUsername ?? 'someone'}',
                            }.toList(),
                            tripTitles: {
                              for (final p in entry.spot.posts)
                                if (trips[p.tripId]?.title != null)
                                  trips[p.tripId]!.title,
                            }.toList(),
                            // Searching opens every hit so results are visible.
                            expanded: searching || _expanded.contains(key),
                            onToggle: () => setState(() {
                              if (!_expanded.add(key)) _expanded.remove(key);
                            }),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SpotSection extends StatelessWidget {
  const _SpotSection({
    required this.spot,
    required this.shown,
    required this.tripTitles,
    required this.posterNames,
    required this.expanded,
    required this.onToggle,
  });

  final _PhotoSpot spot;
  final List<MapPost> shown;
  final List<String> tripTitles;

  /// Usernames of other people whose photos are in this spot.
  final List<String> posterNames;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final latest = DateFormat.yMMMd().format(spot.latest.toLocal());
    final count = shown.length;
    final subtitle = [
      '$count ${count == 1 ? 'photo' : 'photos'}',
      if (tripTitles.isNotEmpty)
        tripTitles.length == 1 ? tripTitles.first : '${tripTitles.length} trips',
      if (posterNames.isNotEmpty)
        'by ${posterNames.length <= 2 ? posterNames.join(', ') : '${posterNames.length} others'}',
      latest,
    ].join(' · ');

    return BrandCard(
      padding: const EdgeInsets.symmetric(
        horizontal: BrandSpace.md,
        vertical: BrandSpace.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: BrandColors.secondaryFixed.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.place_rounded,
                      size: 20,
                      color: BrandColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spot.title,
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
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: BrandColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(bottom: BrandSpace.sm),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemCount: shown.length,
                itemBuilder: (context, i) => MapPhotoTile(
                  post: shown[i],
                  stack: shown,
                  cacheWidth: 300,
                  showPosterHandle: true,
                  borderRadius: BrandRadii.miniRadius,
                ),
              ),
            )
          else
            // Collapsed: a peek of the first few photos.
            Padding(
              padding: const EdgeInsets.only(bottom: BrandSpace.sm),
              child: SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, i) => SizedBox(
                    width: 56,
                    child: MapPhotoTile(
                      post: shown[i],
                      stack: shown,
                      cacheWidth: 300,
                      showPosterHandle: true,
                      borderRadius: BrandRadii.miniRadius,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
