import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' hide Position;
import 'package:intl/intl.dart';

import '../../core/offline/outbox.dart';
import '../../core/offline/outbox_providers.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/error_text.dart';
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

  Future<void> _resolveCurrentLocation() async {
    try {
      final position =
          await Geolocator.getLastKnownPosition() ??
              await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(timeLimit: Duration(seconds: 15)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t determine a starting point for the map.')),
        );
      }
      return;
    }
    if (!mounted) return;
    final picked = await Navigator.of(context).push<Position>(
      MaterialPageRoute(
        builder: (_) => PickLocationScreen(initialCenter: Geo.pos(current!.lat, current.lng)),
      ),
    );
    if (picked != null) {
      setState(() => _point = LatLngPoint(picked.lat.toDouble(), picked.lng.toDouble()));
    }
  }

  Future<void> _pickPlannedArrival() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _plannedArrival ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_plannedArrival ?? now),
    );
    if (time == null) return;

    setState(() {
      _plannedArrival = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the stop a name');
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
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );

    final id = generateUuidV4();
    try {
      await ref.read(tripRepositoryProvider).addStop(stop, id: id);
      ref.invalidate(tripStopsProvider(widget.tripId));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (isNetworkError(e) || ref.read(isOfflineProvider)) {
        await ref.read(outboxProvider).enqueue(OutboxEntry(
              id: id,
              type: OutboxType.tripStop,
              payload: stop.toInsertJson(),
              createdAt: DateTime.now(),
            ));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("You're offline — this stop will sync when you reconnect.")),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Add stop')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _nameCtrl,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: const InputDecoration(labelText: 'Stop name'),
            ),
            const SizedBox(height: 16),
            Text('Type', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _kStopKinds.map((k) {
                final (id, label, icon) = k;
                return ChoiceChip(
                  avatar: Icon(icon, size: 18),
                  label: Text(label),
                  selected: _kind == id,
                  onSelected: (_) => setState(() => _kind = id),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Text('Location', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_outlined),
              title: Text(
                _resolvingLocation
                    ? 'Finding your location…'
                    : _point == null
                        ? 'No location set'
                        : '${_point!.lat.toStringAsFixed(5)}, ${_point!.lng.toStringAsFixed(5)}',
              ),
              trailing: TextButton(
                onPressed: _resolvingLocation ? null : _pickOnMap,
                child: const Text('Pick on map'),
              ),
            ),
            const SizedBox(height: 16),
            Text('Planned arrival (optional)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_outlined),
              title: Text(
                _plannedArrival == null
                    ? 'No ETA set'
                    : DateFormat.yMMMd().add_jm().format(_plannedArrival!),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_plannedArrival != null)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _plannedArrival = null),
                    ),
                  TextButton(onPressed: _pickPlannedArrival, child: const Text('Set ETA')),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppTheme.danger)),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Add stop'),
            ),
          ],
        ),
      ),
    );
  }
}
