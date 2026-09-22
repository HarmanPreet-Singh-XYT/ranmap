import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/env.dart';
import '../../core/util/backend_error.dart';
import '../services/supabase_service.dart';

/// Phone number OTP verification via ranmap-server (Twilio Verify).
/// The client never talks to Twilio directly — the backend holds the
/// Twilio credentials and, on a successful code check, writes
/// phone_number + phone_verified to the caller's own profile with the
/// Supabase secret key.
class PhoneRepository {
  final _client = SupabaseService.client;

  static const _timeout = Duration(seconds: 20);

  Future<void> sendCode(String phoneNumber) async {
    await _post('/phone/send-code', {'phoneNumber': phoneNumber});
  }

  Future<void> checkCode({required String phoneNumber, required String code}) async {
    await _post('/phone/check-code', {'phoneNumber': phoneNumber, 'code': code});
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null) throw StateError('Not signed in');

    final response = await http
        .post(
          Uri.parse('${Env.backendUrl}$path'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception(
        backendErrorMessage(response.statusCode, response.body, 'Request failed'),
      );
    }
  }
}
