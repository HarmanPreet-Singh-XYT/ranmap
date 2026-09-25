import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'ai_conversations_screen.dart';
import 'chat_channels_screen.dart';

/// Hub for the AI trip assistant and group text/voice chat. Group Chat
/// lists a channel per trip/group (ChatChannelsScreen); each channel's
/// ChatScreen has a "Join voice" action that opens a live LiveKit voice
/// channel (VoiceChannelScreen) sharing the same channel identity as text.
class ChatHubScreen extends StatelessWidget {
  const ChatHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      childPad: false,
      header: FHeader(title: const Text('Chat & Voice')),
      child: FTabs(
        expands: true,
        children: const [
          FTabEntry(label: Text('AI Assistant'), child: AiConversationsScreen(showAppBar: false)),
          FTabEntry(label: Text('Group Chat'), child: ChatChannelsScreen()),
        ],
      ),
    );
  }
}
