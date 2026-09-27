import '../models/saved_place.dart';
import '../services/supabase_service.dart';

/// The AI copilot's saved places (`ai_saved_places`), written by the
/// `save_place` tool (see `server/src/lib/ai-tools.ts`). RLS restricts every
/// row to its owner (the `ai_saved_places_owner` policy in 0001_init.sql), so a
/// plain select already returns only the current user's rows; the explicit
/// `user_id` filter makes that intent obvious and keeps the query narrow.
class SavedPlaceRepository {
  final _client = SupabaseService.client;

  // Bound the list so a long-lived account can't pull an unbounded number of
  // rows into memory / onto the map overlay.
  static const _maxSavedPlaces = 200;

  /// The current user's saved places, newest first.
  Future<List<SavedPlace>> fetchSavedPlaces() async {
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client
        .from('ai_saved_places')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(_maxSavedPlaces);
    return (rows as List)
        .map((r) => SavedPlace.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}
