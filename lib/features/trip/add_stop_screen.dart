import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:geolocator/geolocator.dart' hide Position;

import '../../core/offline/outbox.dart';
import '../../core/offline/outbox_providers.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_alert.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../data/models/trip.dart';
import '../../data/models/trip_stop.dart';
import '../../data/services/supabase_service.dart';
// `LocationSettings` collides with mapbox's; hide it so geolocator's is used.
import '../map/map_engine/map_engine.dart' hide LocationSettings;
import '../map/pick_location_screen.dart';
import 'trip_providers.dart';

const _kStopKinds = [
  ('food', 'Food', Icons.restaurant_rounded),
  ('scenery', 'Scenery', Icons.landscape_rounded),
  ('fuel', 'Fuel', Icons.local_gas_station_rounded),
  ('rest', 'Rest', Icons.hotel_rounded),
  ('custom', 'Custom', Icons.place_rounded),
];

/// Add a planned/ad-hoc stop to a trip: defaults the pin to the device's
/// current location, but lets the user drag-pick any point on the map, set
/// an optional planned-arrival time, and appends it to the end of the
/// trip's stop order (see TripRepository.addStop).
class AddStopScreen extends ConsumerStatefulWidget {
  const AddStopScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<AddStopScreen> createState() => _AddStopScreenState();
}

class _AddStopScreenState extends ConsumerState<AddStopScreen> {
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _kind = 'custom';
  LatLngPoint? _point;
  DateTime? _plannedArrival;
  bool _resolvingLocation = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolveCurrentLocation();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolveCurrentLocation() async {
    try {
      final position =
          await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              timeLimit: Duration(seconds: 15),
            ),
          );
      if (!mounted) return;
      setState(() {
        _point = LatLngPoint(position.latitude, position.longitude);
        _resolvingLocation = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _resolvingLocation = false;
      });
    }
  }

  Future<void> _pickOnMap() async {
    if (_resolvingLocation) return;
    var current = _point;
    // Avoid dropping the pin at Null Island (0,0) when we never resolved a
    // location — try once more, then tell the user instead of silently
    // opening the map in the wrong place.
    if (current == null) {
      await _resolveCurrentLocation();
      current = _point;
    }
    if (current == null) {
      if (mounted) {
        showAppToast(
          context,
          "Couldn't determine a starting point for the map.",
          error: true,
        );
      }
      return;
    }
    if (!mounted) return;
    final picked = await Navigator.of(context).push<Position>(
      MaterialPageRoute(
        builder: (_) => PickLocationScreen(
          initialCenter: Geo.pos(current!.lat, current.lng),
        ),
      ),
    );
    if (picked != null) {
      setState(
        () =>
            _point = LatLngPoint(picked.lat.toDouble(), picked.lng.toDouble()),
      );
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final nameValidationError = nameError(name, label: 'Stop name');
    if (nameValidationError != null) {
      setState(() => _error = nameValidationError);
      return;
    }
    final notes = _notesCtrl.text.trim();
    final notesValidationError = notesError(notes);
    if (notesValidationError != null) {
      setState(() => _error = notesValidationError);
      return;
    }
    if (_point == null) {
      setState(() => _error = 'Pick a location for the stop');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final stop = TripStop.draft(
      tripId: widget.tripId,
      createdBy: SupabaseService.currentUserId,
      name: name,
      point: _point!,
      kind: _kind,
      plannedArrival: _plannedArrival,
      notes: notes.isEmpty ? null : notes,
    );

    final id = generateUuidV4();
    try {
      await ref.read(tripRepositoryProvider).addStop(stop, id: id);
      ref.invalidate(tripStopsProvider(widget.tripId));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (isNetworkError(e) || ref.read(isOfflineProvider)) {
        await ref
            .read(outboxProvider)
            .enqueue(
              OutboxEntry(
                id: id,
                type: OutboxType.tripStop,
                payload: stop.toInsertJson(),
                createdAt: DateTime.now(),
              ),
            );
        if (mounted) {
          showAppToast(
            context,
            "You're offline — this stop will sync when you reconnect.",
          );
          Navigator.of(context).pop();
        }
      } else {
        setState(() => _error = friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      header: BrandHeader(
        title: 'Add stop',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: ListView(
        padding: const EdgeInsets.only(
          top: BrandSpace.md,
          bottom: BrandSpace.xl,
        ),
        children: [
          const _FieldLabel('Stop name'),
          BrandTextField(
            controller: _nameCtrl,
            maxLength: kNameMaxLength,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: BrandSpace.lg),
          Text(
            'Type',
            style: BrandText.weight(
              BrandText.titleSm,
              700,
            ).copyWith(color: BrandColors.textHeadline),
          ),
          const SizedBox(height: BrandSpace.sm),
          Wrap(
            spacing: BrandSpace.sm,
            runSpacing: BrandSpace.sm,
            children: _kStopKinds.map((entry) {
              final (id, label, icon) = entry;
              final selected = _kind == id;
              return selected
                  ? BrandPrimaryButton(
                      label: label,
                      leadingIcon: icon,
                      trailingIcon: null,
                      glow: false,
                      expand: false,
                      onPressed: () => setState(() => _kind = id),
                    )
                  : BrandSecondaryButton(
                      label: label,
                      leading: Icon(
                        icon,
                        size: 18,
                        color: BrandColors.textHeadlineAlt,
                      ),
                      expand: false,
                      onPressed: () => setState(() => _kind = id),
                    );
            }).toList(),
          ),
          const SizedBox(height: BrandSpace.md),
          const _FieldLabel('Notes (optional)'),
          BrandTextField(
            controller: _notesCtrl,
            maxLength: kNotesMaxLength,
            maxLines: 3,
          ),
          const SizedBox(height: BrandSpace.lg),
          Text(
            'Location',
            style: BrandText.weight(
              BrandText.titleSm,
              700,
            ).copyWith(color: BrandColors.textHeadline),
          ),
          const SizedBox(height: BrandSpace.sm),
          BrandCard(
            padding: const EdgeInsets.symmetric(
              horizontal: BrandSpace.md,
              vertical: BrandSpace.xs,
            ),
            child: BrandListRow(
              icon: Icons.place_outlined,
              iconColor: BrandColors.primary,
              title: _resolvingLocation
                  ? 'Finding your location…'
                  : _point == null
                  ? 'No location set'
                  : '${_point!.lat.toStringAsFixed(5)}, ${_point!.lng.toStringAsFixed(5)}',
              trailing: BrandSecondaryButton(
                label: 'Pick on map',
                expand: false,
                onPressed: _resolvingLocation ? null : _pickOnMap,
              ),
            ),
          ),
          const SizedBox(height: BrandSpace.lg),
          Text(
            'Planned arrival (optional)',
            style: BrandText.weight(
              BrandText.titleSm,
              700,
            ).copyWith(color: BrandColors.textHeadline),
          ),
          const SizedBox(height: BrandSpace.sm),
          FDateField.calendar(
            label: const Text('Date'),
            selectionControl: FDateSelectionControl.managedSingle(
              initial: _plannedArrival,
              onChange: (date) => setState(() {
                if (date == null) {
                  _plannedArrival = null;
                  return;
                }
                final t = _plannedArrival ?? DateTime.now();
                _plannedArrival = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  t.hour,
                  t.minute,
                );
              }),
            ),
          ),
          const SizedBox(height: BrandSpace.md),
          FTimeField.picker(
            label: const Text('Time'),
            control: FTimeFieldControl.managed(
              initial: _plannedArrival == null
                  ? null
                  : FTime(_plannedArrival!.hour, _plannedArrival!.minute),
              onChange: (time) => setState(() {
                if (time == null) return;
                final d = _plannedArrival ?? DateTime.now();
                _plannedArrival = DateTime(
                  d.year,
                  d.month,
                  d.day,
                  time.hour,
                  time.minute,
                );
              }),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: BrandSpace.lg),
            BrandAlert(message: _error!),
          ],
          const SizedBox(height: BrandSpace.lg),
          BrandPrimaryButton(
            label: 'Add stop',
            onPressed: _saving ? null : _save,
            loading: _saving,
          ),
        ],
      ),
    );
  }
}

/// A small muted field caption sitting above a [BrandTextField].
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: BrandText.labelMd.copyWith(color: BrandColors.textBody),
    ),
  );
}
