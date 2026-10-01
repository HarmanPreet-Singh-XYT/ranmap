import '../models/profile.dart';
import '../services/supabase_service.dart';

class FriendRepository {
  final _client = SupabaseService.client;

  Future<void> sendRequest(String addresseeId) async {
    final uid = SupabaseService.currentUserId;
    await _client.from('friendships').insert({
      'requester_id': uid,
      'addressee_id': addresseeId,
      'status': 'pending',
    });
  }

  /// Sends a friend request to the owner of [username] (used when someone opens
  /// that user's invite link). Returns false when no such username exists; other
  /// errors still throw.
  Future<bool> sendRequestByUsername(String username) async {
    final row = await _client
        .from('profiles')
        .select('id')
        .eq('username', username)
        .maybeSingle();
    if (row == null) return false;
    await sendRequest(row['id'] as String);
    return true;
  }

  /// Accept an incoming request, or delete it (decline). Declining removes the
  /// row rather than setting a permanent `blocked` status, so the other party
  /// can request again later.
  Future<void> respond({required String friendshipId, required bool accept}) async {
    if (accept) {
      await _client.from('friendships').update({'status': 'accepted'}).eq('id', friendshipId);
    } else {
      await _client.from('friendships').delete().eq('id', friendshipId);
    }
  }

  /// Cancel a request you sent, or remove an existing friend.
  Future<void> remove(String friendshipId) async {
    await _client.from('friendships').delete().eq('id', friendshipId);
  }

  /// Requests sent to me, still pending, with the requester's profile joined.
  Future<List<Map<String, dynamic>>> incomingRequests() async {
    final uid = SupabaseService.currentUserId;
    final rows = await _client
        .from('friendships')
        .select(
          'id, requester_id, status, '
          'requester:profiles!friendships_requester_id_fkey($kProfilePublicColumns)',
        )
        .eq('addressee_id', uid)
        .eq('status', 'pending');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Requests I've sent that are still pending, with the addressee's profile joined.
  Future<List<Map<String, dynamic>>> outgoingRequests() async {
    final uid = SupabaseService.currentUserId;
    final rows = await _client
        .from('friendships')
        .select(
          'id, addressee_id, status, '
          'addressee:profiles!friendships_addressee_id_fkey($kProfilePublicColumns)',
        )
        .eq('requester_id', uid)
        .eq('status', 'pending');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Accepted friends (either direction), with the other party's profile joined.
  Future<List<Map<String, dynamic>>> friends() async {
    final uid = SupabaseService.currentUserId;
    final rows = await _client
        .from('friendships')
        .select(
          'id, requester_id, addressee_id, '
          'requester:profiles!friendships_requester_id_fkey($kProfilePublicColumns), '
          'addressee:profiles!friendships_addressee_id_fkey($kProfilePublicColumns)',
        )
        .eq('status', 'accepted')
        .or('requester_id.eq.$uid,addressee_id.eq.$uid');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// The friendship row (any status) between me and [otherId], or null.
  Future<Map<String, dynamic>?> friendshipWith(String otherId) async {
    final me = SupabaseService.currentUserId;
    final rows = await _client
        .from('friendships')
        .select('id, requester_id, addressee_id, status')
        .or(
          'and(requester_id.eq.$me,addressee_id.eq.$otherId),'
          'and(requester_id.eq.$otherId,addressee_id.eq.$me)',
        )
        .limit(1);
    final list = rows as List;
    return list.isEmpty ? null : list.first as Map<String, dynamic>;
  }
}
