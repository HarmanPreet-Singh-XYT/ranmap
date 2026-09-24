import '../../core/network/backend_client.dart';

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
  static const _timeout = Duration(seconds: 20);

  Future<VoiceToken> fetchToken({String? tripId, String? groupId}) async {
    assert((tripId == null) != (groupId == null), 'Pass exactly one of tripId/groupId');
    final data = await BackendClient.postJson(
      '/voice/token',
      {'tripId': ?tripId, 'groupId': ?groupId},
      timeout: _timeout,
      fallbackMessage: 'Could not start the voice channel',
    );
    return VoiceToken.fromJson(data);
  }
}
