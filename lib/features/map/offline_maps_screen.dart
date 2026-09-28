import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_data.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../data/models/trip.dart';
import '../trip/trip_providers.dart';
import 'map_engine/map_engine.dart';
import 'offline_regions.dart';

/// Downloads a trip's map region for offline use, and manages what's already
/// saved.
///
/// A region is a bounding box around the trip's route, downloaded as Mapbox
/// tile packs (via [TileStore]) for the current basemap style. Tiles are served
/// from disk by the map SDK once present, so the route renders with no signal.
class OfflineMapsScreen extends ConsumerStatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  ConsumerState<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends ConsumerState<OfflineMapsScreen> {
  // Zoom range the SDK recommends for road-trip detail (regional → streets).
  static const _minZoom = 0;
  static const _maxZoom = 16;

  TileStore? _store;
  List<TileRegion> _regions = const [];
  final Map<String, double> _progress = {};
  bool _loading = true;
  String? _error;

  static String _regionId(String tripId) => offlineRegionId(tripId);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final store = await TileStore.createDefault();
      final regions = await store.allTileRegions();
      if (!mounted) return;
      setState(() {
        _store = store;
        _regions = regions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _refreshRegions() async {
    final store = _store;
    if (store == null) return;
    final regions = await store.allTileRegions();
    if (mounted) setState(() => _regions = regions);
  }

  Future<void> _download(Trip trip) async {
    final store = _store;
    final polygon = routeBoundsPolygon(trip.routePolyline);
    if (store == null) return;
    if (polygon == null) {
      showAppToast(context, 'This trip has no route to download.', error: true);
      return;
    }
    final regionId = _regionId(trip.id);
    setState(() => _progress[regionId] = 0);
    try {
      await store.loadTileRegion(
        regionId,
        TileRegionLoadOptions(
          geometry: polygon,
          descriptorsOptions: [
            TilesetDescriptorOptions(
              styleURI: RanmapMapStyle.standard.uri,
              minZoom: _minZoom,
              maxZoom: _maxZoom,
            ),
          ],
          acceptExpired: true,
          networkRestriction: NetworkRestriction.NONE,
        ),
        (progress) {
          final required = progress.requiredResourceCount;
          if (!mounted) return;
          setState(() {
            _progress[regionId] = required <= 0
                ? 0
                : (progress.completedResourceCount / required).clamp(0.0, 1.0);
          });
        },
      );
      if (!mounted) return;
      setState(() => _progress.remove(regionId));
      await _refreshRegions();
      if (mounted) showAppToast(context, 'Map saved for offline use.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _progress.remove(regionId));
      showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(TileRegion region) async {
    final store = _store;
    if (store == null) return;
    try {
      await store.removeRegion(region.id);
      await _refreshRegions();
      if (mounted) showAppToast(context, 'Offline map removed.');
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    // The SDK needs the vendored token installed before any tiles are fetched.
    final tokenAsync = ref.watch(mapboxTokenProvider);
    final tripsAsync = ref.watch(myTripsProvider);
    final trips = tripsAsync.valueOrNull ?? const <Trip>[];
    final downloadable = trips
        .where((t) => t.routePolyline != null && t.routePolyline!.isNotEmpty)
        .toList();
    final regionIds = {for (final r in _regions) r.id};

    return BrandScaffold(
      header: BrandHeader(
        title: 'Offline maps',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(BrandSpace.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: BrandText.bodyMd.copyWith(
                        color: BrandColors.textBody,
                      ),
                    ),
                    const SizedBox(height: BrandSpace.md),
                    BrandPrimaryButton(
                      label: 'Retry',
                      expand: false,
                      onPressed: () {
                        setState(() {
                          _loading = true;
                          _error = null;
                        });
                        _init();
                      },
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(
                top: BrandSpace.md,
                bottom: BrandSpace.xl,
              ),
              children: [
                if (tokenAsync.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: BrandSpace.md),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_regions.isNotEmpty) ...[
                  const BrandSectionHeader(
                    icon: Icons.download_done_rounded,
                    title: 'Saved for offline',
                  ),
                  const SizedBox(height: BrandSpace.sm),
                  BrandCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandSpace.md,
                      vertical: BrandSpace.xs,
                    ),
                    child: Column(
                      children: [
                        for (final (i, region) in _regions.indexed) ...[
                          if (i > 0) const BrandRowDivider(),
                          BrandListRow(
                            icon: Icons.offline_pin_rounded,
                            iconColor: BrandColors.primary,
                            title: _titleFor(region.id, trips),
                            subtitle:
                                '~${_formatBytes(region.completedResourceSize)} · ${region.completedResourceCount}/${region.requiredResourceCount} tiles',
                            showChevron: false,
                            trailing: BrandFieldAction(
                              icon: Icons.delete_outline_rounded,
                              color: BrandColors.error,
                              onTap: () => _delete(region),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: BrandSpace.lg),
                ],
                const BrandSectionHeader(
                  icon: Icons.map_outlined,
                  title: 'Your routes',
                ),
                const SizedBox(height: BrandSpace.sm),
                if (downloadable.isEmpty)
                  const BrandCard(
                    padding: EdgeInsets.all(BrandSpace.md),
                    child: Text(
                      'Plan a route on a trip and it will show up here to save '
                      'for offline use.',
                    ),
                  )
                else
                  BrandCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandSpace.md,
                      vertical: BrandSpace.xs,
                    ),
                    child: Column(
                      children: [
                        for (final (i, trip) in downloadable.indexed) ...[
                          if (i > 0) const BrandRowDivider(),
                          _RouteRow(
                            trip: trip,
                            downloaded: regionIds.contains(_regionId(trip.id)),
                            progress: _progress[_regionId(trip.id)],
                            enabled: !tokenAsync.isLoading,
                            onDownload: () => _download(trip),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: BrandSpace.md),
                Text(
                  'Downloads map tiles for the route’s area on the current '
                  'basemap. Saved regions keep working with no signal.',
                  style: BrandText.bodySm.copyWith(
                    color: BrandColors.textMuted,
                  ),
                ),
              ],
            ),
    );
  }

  static String _titleFor(String regionId, List<Trip> trips) {
    final id = regionId.startsWith('trip:') ? regionId.substring(5) : regionId;
    for (final trip in trips) {
      if (trip.id == id) return trip.title;
    }
    return 'Saved region';
  }
}

/// One downloadable route: title, state, and a download action (or progress).
class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.trip,
    required this.downloaded,
    required this.progress,
    required this.enabled,
    required this.onDownload,
  });

  final Trip trip;
  final bool downloaded;
  final double? progress;
  final bool enabled;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final downloading = progress != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BrandText.titleSm.copyWith(
                    color: BrandColors.textHeadline,
                  ),
                ),
                if (downloading) ...[
                  const SizedBox(height: 6),
                  BrandProgressBar(value: progress!),
                ] else
                  Text(
                    downloaded ? 'Saved offline' : 'Not downloaded',
                    style: BrandText.bodySm.copyWith(
                      color: downloaded
                          ? BrandColors.primary
                          : BrandColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: BrandSpace.sm),
          if (!downloading)
            downloaded
                ? Icon(
                    Icons.check_circle_rounded,
                    size: 22,
                    color: BrandColors.primary,
                  )
                : BrandSecondaryButton(
                    label: 'Download',
                    expand: false,
                    onPressed: enabled ? onDownload : null,
                  ),
        ],
      ),
    );
  }
}
