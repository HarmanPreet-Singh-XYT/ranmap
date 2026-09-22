import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/env.dart';
import '../../core/util/backend_error.dart';
import '../services/supabase_service.dart';

class VoiceToken {
  final String url;
  final String token;
  final String roomName;

  const VoiceToken({required this.url, required this.token, required this.roomName});

  factory VoiceToken.fromJson(Map<String, dynamic> json) => VoiceToken(
        url: json['url'] as String,
        token: json['token'] as String,
        roomName: json['roomName'] as String,
      );
}

/// Mints a LiveKit room token via ranmap-server — the client never holds a
/// LiveKit API key. The backend checks trip/group membership before
/// issuing a token (see server/src/routes/voice.ts), the same rule RLS
/// already enforces for chat_messages.
class VoiceRepository {
  final _client = SupabaseService.client;

  static const _timeout = Duration(seconds: 20);

  Future<VoiceToken> fetchToken({String? tripId, String? groupId}) async {
    assert((tripId == null) != (groupId == null), 'Pass exactly one of tripId/groupId');
    final token = _client.auth.currentSession?.accessToken;
    if (token == null) throw StateError('Not signed in');

    final response = await http
        .post(
          Uri.parse('${Env.backendUrl}/voice/token'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'tripId': ?tripId,
            'groupId': ?groupId,
          }),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception(
        backendErrorMessage(response.statusCode, response.body, 'Request failed'),
      );
    }
    return VoiceToken.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
