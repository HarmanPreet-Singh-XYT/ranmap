import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/widgets/brand/brand_scaffold.dart';
import 'ai_conversations_screen.dart';
import 'chat_channels_screen.dart';

/// Hub for the AI trip assistant and group text/voice chat. Group Chat
/// lists a channel per trip/group (ChatChannelsScreen); each channel's
/// ChatScreen has a "Join voice" action that opens a live LiveKit voice
/// channel (VoiceChannelScreen) sharing the same channel identity as text.
///
/// A bottom-nav tab root, so it wears the brand shell without a back
/// affordance and leaves the bottom inset to the home nav bar.
class ChatHubScreen extends StatelessWidget {
  const ChatHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      bottomSafeArea: false,
      header: const BrandHeader(title: 'Chat & Voice', showBack: false),
      child: FTabs(
        expands: true,
        children: const [
          FTabEntry(
            label: Text('AI Assistant'),
            child: AiConversationsScreen(showAppBar: false),
          ),
          FTabEntry(label: Text('Group Chat'), child: ChatChannelsScreen()),
        ],
      ),
    );
  }
}
