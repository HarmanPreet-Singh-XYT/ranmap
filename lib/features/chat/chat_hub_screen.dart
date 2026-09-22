import 'package:flutter/material.dart';

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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chat & Voice'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'AI Assistant'),
              Tab(text: 'Group Chat'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AiConversationsScreen(showAppBar: false),
            ChatChannelsScreen(),
          ],
        ),
      ),
    );
  }
}
