import 'package:flutter/material.dart';

import '../admin/admin_state.dart'
    show ChequeStatus, RentState, adminState, formatDate;
import '../admin/screens/cheques_screen.dart' show ChequesScreen;
import '../state/app_state.dart';
import '../state/demo.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../state/chat_state.dart';
import 'chat_screen.dart';
import 'contract_screen.dart';
import 'maintenance_screen.dart';
import 'cheque_upload_screen.dart';
import 'payments_screen.dart';
import 'shell.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final s = appState;
        final notice = s.notices.firstOrNull;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => tabIndex.value = 3,
                    child: const CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.gold500,
                      child: Icon(Icons.person, color: AppColors.green900),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AYAN RESIDENCES',
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1.8,
                            fontWeight: FontWeight.w800,
                            color: AppColors.gold500,
                          ),
                        ),
                        Text(
                          'Hello, ${s.name.split(' ').first}!',
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => tabIndex.value = 2,
                    icon: Badge(
                      isLabelVisible: s.pendingAcks > 0,
                      smallSize: 10,
                      backgroundColor: AppColors.gold500,
                      child: const Icon(
                        Icons.notifications_none_rounded,
                        color: AppColors.slate300,
                        size: 26,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBody(
                children: [
                  const Text(
                    'Your personal rental dashboard',
                    style: TextStyle(color: AppColors.slate300, fontSize: 12),
                  ),
                  if (adminState.isVilla(s.currentTenant))
                    _ChequeCard(s.currentTenant)
                  else
                    _RentCard(s),
                  GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.1,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      adminState.isVilla(s.currentTenant)
                          ? _Action(
                              Icons.payments_outlined,
                              'Upload Cheques',
                              'Send a photo of your cheque',
                              () => push(context, const ChequeUploadScreen()),
                            )
                          : _Action(
                              Icons.account_balance_wallet_rounded,
                              'Pay Rent',
                              'Submit payment details',
                              () => push(context, const PaymentsScreen()),
                            ),
                      _Action(
                        Icons.build_rounded,
                        'Property Maintenance',
                        'Upload photos or videos',
                        () => push(context, const MaintenanceScreen()),
                      ),
                      _Action(
                        Icons.description_outlined,
                        'My Contract',
                        'View rental agreement',
                        () => push(context, const ContractScreen()),
                      ),
                      // Chat lives here now (not in the bottom bar); the badge
                      // shows unread messages from management.
                      ListenableBuilder(
                        listenable: chatState,
                        builder: (context, _) => _Action(
                          Icons.chat_bubble_outline_rounded,
                          'Contact Management',
                          'Chat with management',
                          () => openChat(context),
                          badge: chatState.unread(
                            ChatSender.tenant,
                            s.currentTenant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // The newest notice, when there is one.
                  if (notice != null)
                    AppCard(
                      color: AppColors.greenDeep,
                      border: Border.all(
                        color: AppColors.gold500.withValues(alpha: .5),
                      ),
                      onTap: () => tabIndex.value = 2,
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const IconBadge(
                            Icons.campaign_rounded,
                            size: 42,
                            fg: AppColors.gold400,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'LATEST NOTICE',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                    color: AppColors.gold400,
                                  ),
                                ),
                                Text(
                                  notice.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  notice.body,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.slate300,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: AppColors.slate300,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

void push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

class _RentCard extends StatelessWidget {
  const _RentCard(this.s);
  final AppState s;

  @override
  Widget build(BuildContext context) {
    final rec = adminState.tenants
        .where((t) => t.name == s.currentTenant)
        .firstOrNull;
    // No unit yet: nothing is due, so no amount, status or due date.
    if (!demoData && (rec == null || rec.unit.isEmpty)) {
      return const AppCard(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monthly Rent',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.slate500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'No unit assigned yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.green800,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Your rent and due date will show here once management assigns your unit.',
              style: TextStyle(fontSize: 12, color: AppColors.slate500),
            ),
          ],
        ),
      );
    }
    // The due day from the tenant's lease, as the admin set it.
    final dueDay = rec?.dueDay ?? 5;
    return AppCard(
      onTap: () => push(context, const PaymentHistoryScreen()),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                // "Monthly Rent", or "Yearly Rent" for a villa priced by the year.
                adminState.rentLabelOf(rec).replaceFirst('rent', 'Rent').replaceFirst('rate', 'Rate'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate500,
                ),
              ),
              switch (adminState.rentStateOf(s.currentTenant)) {
                RentState.paid => Pill.verified('Paid'),
                RentState.awaiting => Pill.info('Awaiting Verification'),
                RentState.due => Pill.pending('Pending'),
              },
            ],
          ),
          const SizedBox(height: 6),
          CountUpText(
            peso(s.monthlyRent),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppColors.green800,
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 12, color: AppColors.slate500),
              children: [
                const TextSpan(text: 'Due date: '),
                TextSpan(
                  text: '${ordinal(dueDay)} of every month',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.green800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(
    this.icon,
    this.title,
    this.subtitle,
    this.onTap, {
    this.badge = 0,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  /// Unread count shown at the top right; hidden when 0.
  final int badge;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconBadge(icon, size: 34),
              const Spacer(),
              if (badge > 0)
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badge',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: AppColors.slate500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Villa tenants pay by cheque: the card shows the next post-dated cheque and
/// opens the full list.
class _ChequeCard extends StatelessWidget {
  const _ChequeCard(this.tenant);
  final String tenant;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final next = adminState.nextCheque(tenant);
        final all = adminState.chequesFor(tenant);
        return AppCard(
          onTap: () => push(context, ChequesScreen(tenant)),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Next Cheque',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.slate500,
                    ),
                  ),
                  if (next == null)
                    Pill.verified('All cleared')
                  else
                    switch (next.status) {
                      ChequeStatus.deposited => Pill.info('Deposited'),
                      ChequeStatus.bounced => Pill.urgent('Bounced'),
                      _ => Pill.pending('Held'),
                    },
                ],
              ),
              const SizedBox(height: 6),
              Text(
                next == null ? '-' : peso(next.amount, dhs: true),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.slate500,
                  ),
                  children: [
                    const TextSpan(text: 'Post-dated cheque · '),
                    TextSpan(
                      text: next == null
                          ? '${all.where((c) => c.kind.name == 'postDated').length} cheques on file'
                          : 'banks on ${formatDate(next.date)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.green800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
