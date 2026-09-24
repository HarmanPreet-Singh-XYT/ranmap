import '../../core/network/backend_client.dart';

/// Phone number OTP verification via ranmap-server (Twilio Verify).
/// The client never talks to Twilio directly — the backend holds the
/// Twilio credentials and, on a successful code check, writes
/// phone_number + phone_verified to the caller's own profile with the
/// Supabase secret key.
class PhoneRepository {
  static const _timeout = Duration(seconds: 20);

  Future<void> sendCode(String phoneNumber) async {
    await BackendClient.postJson(
      '/phone/send-code',
      {'phoneNumber': phoneNumber},
      timeout: _timeout,
      fallbackMessage: 'Could not send the code',
    );
  }

  Future<void> checkCode({required String phoneNumber, required String code}) async {
    await BackendClient.postJson(
      '/phone/check-code',
      {'phoneNumber': phoneNumber, 'code': code},
      timeout: _timeout,
      fallbackMessage: 'Could not verify the code',
    );
  }
}
