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
        .maybeSingle();
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

  Future<List<Profile>> searchByUsername(String query) async {
    if (query.trim().length < 2) return const [];
    final rows = await _client
        .from('profiles')
        .select(kProfilePublicColumns)
        .ilike('username', '%${_escapeLike(query.trim())}%')
        .limit(20);
    return (rows as List).map((r) => Profile.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// The current user's private fields (phone_number / socials /
  /// phone_verified), which are not readable through a normal select (see
  /// 0002_rls_hardening.sql).
  Future<({String? phoneNumber, Map<String, String> socials, bool phoneVerified})>
      fetchMyPrivate() async {
    final data = await _client.rpc('my_private_profile');
    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) {
      return (phoneNumber: null, socials: const <String, String>{}, phoneVerified: false);
    }
    final row = rows.first;
    return (
      phoneNumber: row['phone_number'] as String?,
      socials: (row['socials'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          const <String, String>{},
      phoneVerified: row['phone_verified'] as bool? ?? false,
    );
  }

  /// Updates only the socials. A phone number change must go through the OTP
  /// flow in PhoneRepository (0005_phone_verification.sql resets
  /// phone_verified whenever phone_number changes via a client write).
  Future<void> updateMySocials(Map<String, String> socials) async {
    final uid = SupabaseService.currentUserId;
    await _client.from('profiles').update({'socials': socials}).eq('id', uid);
  }

  /// PostgREST `ilike` treats `%` and `_` as wildcards — escape them so a
  /// search for "a_b" doesn't match "axb".
  String _escapeLike(String input) =>
      input.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
}
