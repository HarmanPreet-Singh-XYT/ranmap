import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/widgets/app_action_sheet.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../social/friends_screen.dart';
import '../social/invite_share.dart';
import '../social/people_screen.dart';
import '../social/social_providers.dart';
import 'ai_conversations_screen.dart';
import 'chat_channels_screen.dart';
import 'direct_messages_screen.dart';
import 'new_chat_screen.dart';

/// Hub for direct messages, the AI trip assistant and group text/voice chat. Group Chat
/// lists a channel per trip/group (ChatChannelsScreen); each channel's
/// ChatScreen has a "Join voice" action that opens a live LiveKit voice
/// channel (VoiceChannelScreen) sharing the same channel identity as text.
///
/// A bottom-nav tab root, so it wears the brand shell without a back
/// affordance and leaves the bottom inset to the home nav bar. The header "+"
/// is the shortcut to everything people-related: message, add a friend, answer
/// requests, invite.
class ChatHubScreen extends ConsumerStatefulWidget {
  const ChatHubScreen({super.key});

  @override
  ConsumerState<ChatHubScreen> createState() => _ChatHubScreenState();
}

class _ChatHubScreenState extends ConsumerState<ChatHubScreen> {
  /// Someone with no friends and no groups has nobody to message yet: open on
  /// the AI assistant, which works on its own, instead of an empty inbox.
  late final int _initialTab = () {
    final friends = ref.read(friendsProvider).valueOrNull;
    final groups = ref.read(myGroupsProvider).valueOrNull;
    final alone =
        friends != null && groups != null && friends.isEmpty && groups.isEmpty;
    return alone ? 2 : 0;
  }();

  void _openFriends(BuildContext context, int tab) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => FriendsScreen(initialTab: tab)));
  }

  void _showPeopleMenu(BuildContext context, WidgetRef ref) {
    final requests =
        ref.read(incomingRequestsProvider).valueOrNull?.length ?? 0;
    showAppActionSheet(
      context,
      title: 'People',
      actions: [
        // The full list: friends, whoever you're riding with now, and everyone
        // you've ridden or grouped with — with message/add actions on each row.
        AppSheetAction(
          label: 'People you know',
          icon: Icons.diversity_3_rounded,
          onSelected: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PeopleScreen()),
          ),
        ),
        AppSheetAction(
          label: 'New message',
          icon: Icons.edit_outlined,
          onSelected: () => showNewChat(context),
        ),
        AppSheetAction(
          label: 'Add a friend',
          icon: Icons.person_add_alt_1_rounded,
          onSelected: () => _openFriends(context, 2),
        ),
        AppSheetAction(
          label: requests > 0
              ? 'Friend requests ($requests)'
              : 'Friend requests',
          icon: Icons.mark_email_unread_outlined,
          onSelected: () => _openFriends(context, 1),
        ),
        AppSheetAction(
          label: 'Your friends',
          icon: Icons.people_alt_outlined,
          onSelected: () => _openFriends(context, 0),
        ),
        AppSheetAction(
          label: 'Share invite link',
          icon: Icons.ios_share_rounded,
          onSelected: () => shareMyInviteLink(context, ref),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final requests =
        ref.watch(incomingRequestsProvider).valueOrNull?.length ?? 0;
    return BrandScaffold(
      bottomSafeArea: false,
      header: BrandHeader(
        title: 'Chat & Voice',
        showBack: false,
        action: Badge(
          isLabelVisible: requests > 0,
          label: Text('$requests'),
          child: IconButton(
            tooltip: 'Friends & messages',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showPeopleMenu(context, ref),
          ),
        ),
      ),
      child: FTabs(
        expands: true,
        control: FTabControl.managed(initial: _initialTab),
        children: const [
          FTabEntry(label: Text('Direct'), child: DirectMessagesScreen()),
          FTabEntry(label: Text('Groups'), child: ChatChannelsScreen()),
          FTabEntry(
            label: Text('AI'),
            child: AiConversationsScreen(showAppBar: false),
          ),
        ],
      ),
    );
  }
}
