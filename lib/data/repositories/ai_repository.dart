import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/env.dart';
import '../../core/util/backend_error.dart';
import '../models/ai_conversation.dart';
import '../models/ai_message.dart';
import '../services/supabase_service.dart';

/// Talks to ranmap-server (see server/), which holds the Anthropic API key
/// and executes AI tool calls (saving places, scheduling trips, creating
/// trips) with the Supabase secret key. The client never talks to the LLM
/// directly.
class AiRepository {
  final _client = SupabaseService.client;

  /// The assistant may make several tool round-trips, so allow a generous
  /// timeout — but not an unbounded one, or a hung server leaves the UI stuck.
  static const _timeout = Duration(seconds: 60);

  Future<List<AiConversation>> fetchConversations() async {
    final rows = await _client
        .from('ai_conversations')
        .select('id, title, created_at')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => AiConversation.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteConversation(String conversationId) async {
    await _client.from('ai_conversations').delete().eq('id', conversationId);
  }

  Future<List<AiMessage>> fetchMessages(String conversationId) async {
    final rows = await _client
        .from('ai_messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at');
    return (rows as List)
        .map((r) => AiMessage.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Sends [content] to the assistant for [conversationId] ("new" to start a
  /// fresh conversation) and returns the new conversation id.
  Future<String> sendMessage({required String conversationId, required String content}) async {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null) throw StateError('Not signed in');

    final response = await http
        .post(
          Uri.parse('${Env.backendUrl}/ai/conversations/$conversationId/messages'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'content': content}),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception(
        backendErrorMessage(response.statusCode, response.body, 'AI assistant request failed'),
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['conversationId'] as String;
  }
}
