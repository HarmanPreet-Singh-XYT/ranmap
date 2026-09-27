import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/saved_place.dart';
import '../../data/repositories/saved_place_repository.dart';

final savedPlaceRepositoryProvider = Provider<SavedPlaceRepository>(
  (ref) => SavedPlaceRepository(),
);

/// The current user's AI-saved places (the copilot's `save_place` output),
/// newest first. Rendered as bookmark pins on the map and listed in the
/// no-convoy bottom card.
final savedPlacesProvider = FutureProvider.autoDispose<List<SavedPlace>>((ref) {
  return ref.watch(savedPlaceRepositoryProvider).fetchSavedPlaces();
});
