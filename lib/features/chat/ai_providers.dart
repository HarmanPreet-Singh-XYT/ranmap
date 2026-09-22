import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/ai_conversation.dart';
import '../../data/models/ai_message.dart';
import '../../data/repositories/ai_repository.dart';

final aiRepositoryProvider = Provider<AiRepository>((ref) => AiRepository());

final aiConversationsProvider = FutureProvider.autoDispose<List<AiConversation>>(
  (ref) => ref.watch(aiRepositoryProvider).fetchConversations(),
);

final aiMessagesProvider = FutureProvider.autoDispose.family<List<AiMessage>, String>(
  (ref, conversationId) => ref.watch(aiRepositoryProvider).fetchMessages(conversationId),
);
