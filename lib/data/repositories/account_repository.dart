import '../../core/network/backend_client.dart';

/// Account operations that only the server can perform — deleting the auth
/// user requires the Supabase secret key, so this goes through ranmap-server.
class AccountRepository {
  const AccountRepository();

  /// Permanently deletes the signed-in user's account and every row/file that
  /// belongs to it. The caller signs out afterwards.
  Future<void> deleteAccount() async {
    await BackendClient.postJson('/account/delete', const {});
  }
}
