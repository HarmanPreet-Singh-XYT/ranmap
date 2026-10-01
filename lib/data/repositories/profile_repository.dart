import '../models/profile.dart';
import '../services/supabase_service.dart';

class ProfileRepository {
  final _client = SupabaseService.client;

  Future<Profile?> fetchMyProfile() async {
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return null;
    final row = await _client
        .from('profiles')
        .select(kProfilePublicColumns)
        .eq('id', uid)
        .maybeSingle()
        // Bound the wait: a stalled socket must surface as an error the router
        // can recover from, not leave a returning user on the splash forever.
        .timeout(const Duration(seconds: 20));
    return row == null ? null : Profile.fromJson(row);
  }

  Future<bool> isUsernameAvailable(String username) async {
    final row = await _client
        .from('profiles')
        .select('id')
        .ilike('username', _escapeLike(username))
        .maybeSingle();
    return row == null;
  }

  Future<Profile> createProfile(Profile profile) async {
    final row = await _client
        .from('profiles')
        .insert(profile.toJson())
        .select(kProfilePublicColumns)
        .single();
    return Profile.fromJson(row);
  }

  /// Updates the editable profile fields. Only the columns the client is
  /// granted UPDATE on are sent (see 0005_phone_verification.sql): notably not
  /// `id`/`phone_verified`, and not `phone_number`/`socials`. The profile is
  /// usually built from [fetchMyProfile], which doesn't carry phone/socials,
  /// so sending those here would blank them out.
  Future<Profile> updateProfile(Profile profile) async {
    final row = await _client
        .from('profiles')
        .update({
          'username': profile.username,
          'display_name': profile.displayName,
          'avatar_id': profile.avatarId,
          'vehicle_type': profile.vehicleType,
        })
        .eq('id', profile.id)
        .select(kProfilePublicColumns)
        .single();
    return Profile.fromJson(row);
  }

  /// Fuzzy username search. Prefers the `search_profiles` RPC (substring +
  /// trigram similarity, so a typo still finds the handle — see
  /// 0017_profile_search.sql), and falls back to a plain substring match when
  /// the RPC isn't there, so the app works before the migration is applied.
  Future<List<Profile>> searchByUsername(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];
    try {
      final data = await _client.rpc(
        'search_profiles',
        params: {'p_query': trimmed},
      );
      return (data as List)
          .map((r) => Profile.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _searchByUsernameSubstring(trimmed);
    }
  }

  /// A single profile by id (public columns only), or null if it doesn't exist.
  Future<Profile?> fetchById(String id) async {
    final row = await _client
        .from('profiles')
        .select(kProfilePublicColumns)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  /// Which of [groupIds] the user is an active member of — the groups held in
  /// common when [groupIds] are the viewer's own.
  Future<Set<String>> activeGroupIdsOf(
    String userId,
    List<String> groupIds,
  ) async {
    if (groupIds.isEmpty) return {};
    final rows = await _client
        .from('group_members')
        .select('group_id')
        .eq('user_id', userId)
        .eq('status', 'active')
        .inFilter('group_id', groupIds);
    return {for (final r in rows as List) r['group_id'] as String};
  }

  /// Which of [tripIds] the user is on.
  Future<Set<String>> tripIdsOf(String userId, List<String> tripIds) async {
    if (tripIds.isEmpty) return {};
    final rows = await _client
        .from('trip_members')
        .select('trip_id')
        .eq('user_id', userId)
        .inFilter('trip_id', tripIds);
    return {for (final r in rows as List) r['trip_id'] as String};
  }

  /// A single profile by its exact handle, or null when no such user exists.
  /// Used where the handle is already known (e.g. an invite link's inviter) and
  /// a fuzzy search would be wasteful and could return a near-match.
  Future<Profile?> fetchByUsername(String username) async {
    final row = await _client
        .from('profiles')
        .select(kProfilePublicColumns)
        .eq('username', username)
        .maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  Future<List<Profile>> _searchByUsernameSubstring(String query) async {
    final myUid = SupabaseService.currentUser?.id;
    final rows = await _client
        .from('profiles')
        .select(kProfilePublicColumns)
        .ilike('username', '%${_escapeLike(query)}%')
        // Exclude yourself: adding yourself would be rejected anyway, and the
        // "Add" button on your own row is confusing.
        .neq('id', myUid ?? '')
        .limit(20);
    return (rows as List)
        .map((r) => Profile.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// The current user's private fields (phone_number / socials /
  /// phone_verified / who may message them), which are not readable through a
  /// normal select (see 0002_rls_hardening.sql and 0050).
  Future<
    ({
      String? phoneNumber,
      Map<String, String> socials,
      bool phoneVerified,
      bool dmFromStrangers,
    })
  >
  fetchMyPrivate() async {
    final data = await _client.rpc('my_private_profile');
    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) {
      return (
        phoneNumber: null,
        socials: const <String, String>{},
        phoneVerified: false,
        dmFromStrangers: false,
      );
    }
    final row = rows.first;
    return (
      phoneNumber: row['phone_number'] as String?,
      socials: (row['socials'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          const <String, String>{},
      phoneVerified: row['phone_verified'] as bool? ?? false,
      dmFromStrangers: row['dm_from_strangers'] as bool? ?? false,
    );
  }

  /// Updates only the socials. A phone number change must go through the OTP
  /// flow in PhoneRepository (0005_phone_verification.sql resets
  /// phone_verified whenever phone_number changes via a client write).
  Future<void> updateMySocials(Map<String, String> socials) async {
    final uid = SupabaseService.currentUserId;
    await _client.from('profiles').update({'socials': socials}).eq('id', uid);
  }

  /// Whether people who aren't friends may start a DM. Friends can always write;
  /// this only decides the stranger case (see `get_or_create_conversation`).
  Future<void> setDmFromStrangers(bool allow) async {
    final uid = SupabaseService.currentUserId;
    await _client
        .from('profiles')
        .update({'dm_from_strangers': allow})
        .eq('id', uid);
  }

  /// PostgREST `ilike` treats `%` and `_` as wildcards — escape them so a
  /// search for "a_b" doesn't match "axb".
  String _escapeLike(String input) =>
      input.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
}
