import 'package:flutter/material.dart';

import '../../state/chat_state.dart';
import '../../theme.dart';
import '../../widgets/chat_view.dart';
import '../admin_state.dart';

/// Management's side of one tenant's private chat. Same layout as the tenant app.
class AdminChatScreen extends StatelessWidget {
  const AdminChatScreen(this.tenant, {super.key});
  final TenantRec tenant;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.green800,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.gold500,
              child: Icon(Icons.person, size: 20, color: AppColors.green900),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tenant.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    tenant.unitLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.slate300,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: AppColors.gold500.withValues(alpha: .25),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ChatView(tenant: tenant.name, me: ChatSender.admin),
          ),
        ),
      ),
    );
  }
}
