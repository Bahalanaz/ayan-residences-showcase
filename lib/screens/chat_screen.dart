import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/chat_view.dart';

/// Opens the chat as its own full screen, so the bottom bar is hidden while
/// the tenant is in the conversation (like WhatsApp or Messenger).
void openChat(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChatPage()));
}

/// The tenant's private chat with management.
class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.green800,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Row(children: [
          Container(
            width: 40,
            height: 40,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: AppColors.greenDeep,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.gold500.withValues(alpha: .6)),
            ),
            child: const AppLogo(size: 28),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ayan Residences',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              Text('Management · private chat',
                  style: TextStyle(fontSize: 12, color: AppColors.slate300)),
            ]),
          ),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.gold500.withValues(alpha: .25)),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListenableBuilder(
              // The tenant can change after logging in as someone else.
              listenable: appState,
              builder: (context, _) => ChatView(
                key: ValueKey(appState.currentTenant),
                tenant: appState.currentTenant,
                me: ChatSender.tenant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
