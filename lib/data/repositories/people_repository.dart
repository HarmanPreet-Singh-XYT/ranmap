import '../models/person.dart';
import '../services/supabase_service.dart';

/// The people the current user shares a context with, in one query.
///
/// `people_around_me()` (0050) does the joining server-side: friendships, the
/// crews of running trips, people from past trips, and shared groups, collapsed
/// to one row per person with the strongest reason plus whether they may be
/// messaged. Doing it here would mean a request per trip and per group.
class PeopleRepository {
  final _client = SupabaseService.client;

  Future<List<Person>> aroundMe() async {
    final data = await _client.rpc('people_around_me');
    final rows = (data as List?) ?? const [];
    return [
      for (final row in rows)
        if (row is Map<String, dynamic>) Person.fromJson(row),
    ];
  }

  /// Reads one person's row, for a screen that already has their id.
  Future<Person?> byId(String userId) async {
    if (userId.isEmpty) return null;
    try {
      return (await aroundMe()).firstWhere((p) => p.userId == userId);
    } catch (_) {
      return null;
    }
  }
}
