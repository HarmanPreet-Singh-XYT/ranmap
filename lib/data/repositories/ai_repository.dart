import '../../core/network/backend_client.dart';
import '../models/ai_conversation.dart';
import '../models/ai_message.dart';
import '../services/supabase_service.dart';

/// Talks to ranmap-server (see server/), which holds the Gemini API key
/// and executes AI tool calls (saving places, scheduling trips, creating
/// trips) with the Supabase secret key. The client never talks to the LLM
/// directly.
class AiRepository {
  final _client = SupabaseService.client;

  /// The assistant may make several tool round-trips, so allow a generous
  /// timeout — but not an unbounded one, or a hung server leaves the UI stuck.
  static const _timeout = Duration(seconds: 60);

  // Bound the list sizes so a long-lived account can't pull an unbounded
  // number of rows into memory.
  static const _maxConversations = 100;
  static const _maxMessages = 200;

  Future<List<AiConversation>> fetchConversations() async {
    final rows = await _client
        .from('ai_conversations')
        .select('id, title, created_at')
        .order('created_at', ascending: false)
        .limit(_maxConversations);
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
        .order('created_at')
        .limit(_maxMessages);
    return (rows as List)
        .map((r) => AiMessage.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Sends [content] to the assistant for [conversationId] ("new" to start a
  /// fresh conversation) and returns the new conversation id.
  Future<String> sendMessage({required String conversationId, required String content}) async {
    final data = await BackendClient.postJson(
      '/ai/conversations/$conversationId/messages',
      {'content': content},
      timeout: _timeout,
      fallbackMessage: 'AI assistant request failed',
    );
    // The server persists the turn before replying, so a malformed success body
    // shouldn't make the client lose the conversation — fall back to the id we
    // sent to rather than throwing on the cast.
    final id = data['conversationId'];
    if (id is String && id.isNotEmpty) return id;
    return conversationId;
  }
}
