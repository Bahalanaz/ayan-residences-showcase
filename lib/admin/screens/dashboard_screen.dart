import 'package:flutter/material.dart';

import '../../screens/shell.dart' show TabBody;
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/common.dart';
import '../admin_state.dart';
import '../../state/chat_state.dart';
import '../../screens/home_screen.dart' show push;
import 'complaints_admin_screen.dart';
import 'messages_admin_screen.dart';
import 'notices_admin_screen.dart';
import 'units_screen.dart';
import 'leases_screen.dart';
import 'maintenance_admin_screen.dart';
import 'reports_admin_screen.dart' show ReportVerificationScreen;
import 'payments_admin_screen.dart';
import 'cheques_screen.dart' show ChequeVerificationScreen;

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([adminState, chatState]),
      builder: (context, _) {
        final s = adminState;
        // Things waiting on the admin for each unit: unread chats, documents
        // to check and lease requests. Shown as a gold dot on Occupancy.
        final reserved = s.units
            .where((u) => u.status == UnitStatus.reserved)
            .length;
        final unitConcerns =
            (s.wants('Messages from tenants')
                ? s.tenants.fold<int>(
                    0,
                    (n, t) => n + chatState.unread(ChatSender.admin, t.name),
                  )
                : 0) +
            (s.wants('Tenant documents to check') ? s.docsToReview : 0) +
            (s.wants('Lease requests and endings') ? s.pendingRequests : 0);
        final attention = <(IconData, String, String, VoidCallback)>[
          if (s.toVerify > 0 && s.wants('Payment proofs to verify'))
            (
              Icons.payments_rounded,
              '${s.toVerify} payment proofs to verify',
              'Tenants are waiting for confirmation',
              () => push(context, const PaymentsAdminScreen()),
            ),
          if (s.openReports > 0 && s.wants('Damage and maintenance reports'))
            (
              Icons.build_rounded,
              '${s.openReports} reports to review',
              'Maintenance, damage and modification requests',
              () => push(context, const ReportVerificationScreen()),
            ),
          if (s.pendingRequests > 0 && s.wants('Lease requests and endings'))
            (
              Icons.autorenew_rounded,
              '${s.pendingRequests} lease requests',
              'Renewals and move-out notices',
              () => push(context, const LeasesScreen()),
            ),
          if (s.leasesEndingWithin(s.renewalNoticeDays).isNotEmpty &&
              s.wants('Lease requests and endings'))
            (
              Icons.event_repeat_rounded,
              '${s.leasesEndingWithin(s.renewalNoticeDays).length} ${s.leasesEndingWithin(s.renewalNoticeDays).length == 1 ? 'lease ends' : 'leases end'} within ${s.renewalNoticeDays} days',
              'Renew, or plan the move-out',
              () => push(context, const LeasesScreen()),
            ),
          if (s.docsToReview > 0 && s.wants('Tenant documents to check'))
            (
              Icons.badge_outlined,
              '${s.docsToReview} tenant ${s.docsToReview == 1 ? 'document' : 'documents'} to check',
              'Approve, or ask for a new one',
              () => push(context, const UnitsScreen()),
            ),
          if (s.overdueCount > 0 && s.wants('Overdue rent'))
            (
              Icons.warning_amber_rounded,
              '${s.overdueCount} overdue rent charges',
              'Remind tenants to pay',
              () => push(context, const PaymentsAdminScreen()),
            ),
          if (s.openComplaints > 0 && s.wants('Complaints'))
            (
              Icons.report_gmailerrorred_outlined,
              '${s.openComplaints} open complaints',
              'Tenants are waiting for a response',
              () => push(context, const ComplaintsAdminScreen()),
            ),
          if (s.unreadMessages > 0 && s.wants('Messages from tenants'))
            (
              Icons.chat_bubble_outline_rounded,
              '${s.unreadMessages} unanswered messages',
              'Private messages from tenants',
              () => push(context, const MessagesAdminScreen()),
            ),
        ];
        return TabBody(
          children: [
            Row(
              children: [
                const SizedBox(width: 56, height: 38, child: AppLogo(size: 38)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_greeting()} · ADMIN',
                        style: const TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.8,
                          fontWeight: FontWeight.w800,
                          color: AppColors.gold500,
                        ),
                      ),
                      const Text(
                        'Ayan Residences',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Today's date and how much is waiting, at a glance.
            _TodayStrip(waiting: attention.length),
            // Full width: payments are the main thing to check, and it keeps
            // the grid below even.
            _WideStat(
              'Payment verification',
              '${s.toVerify}',
              s.toVerify == 0
                  ? 'All caught up'
                  : 'Payment proofs waiting for you',
              Icons.account_balance_wallet_rounded,
              () => push(context, const PaymentsAdminScreen()),
              badge: s.wants('Payment proofs to verify') ? s.toVerify : 0,
            ),
            GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _Stat(
                  'Occupancy',
                  '${s.occupied}/${s.units.length}',
                  // A unit whose tenant's lease has not started yet is reserved.
                  reserved == 0
                      ? 'units occupied'
                      : 'occupied · $reserved reserved',
                  Icons.apartment_rounded,
                  () => push(context, const UnitsScreen()),
                  badge: unitConcerns,
                ),
                _Stat(
                  'Scheduling',
                  '${s.upcomingWork.length}',
                  s.upcomingWork.isEmpty
                      ? 'nothing scheduled'
                      : 'next: ${monthShort[s.upcomingWork.first.date.month - 1]} ${s.upcomingWork.first.date.day}',
                  Icons.handyman_rounded,
                  () => push(context, const MaintenanceAdminScreen()),
                ),
                _Stat(
                  'Report verification',
                  '${s.openReports}',
                  '${s.reports.where((r) => r.status == ReportStatus.pending).length} pending',
                  Icons.fact_check_outlined,
                  () => push(context, const ReportVerificationScreen()),
                  badge: s.wants('Damage and maintenance reports')
                      ? s.reports
                            .where((r) => r.status == ReportStatus.pending)
                            .length
                      : 0,
                ),
                _Stat(
                  'Cheque verification',
                  '${s.chequesWithNewPhotos.length + s.chequesToBank.length + s.chequesDeposited.length}',
                  '${s.chequesWithNewPhotos.length} new · ${s.chequesToBank.length} to bank · ${s.chequesDeposited.length} to confirm',
                  Icons.payments_outlined,
                  () => push(context, const ChequeVerificationScreen()),
                  badge: s.wants('Cheques to bank or confirm')
                      ? s.chequesWithNewPhotos.length + s.chequesToBank.length
                      : 0,
                ),
                _Stat(
                  'Announcements',
                  '${s.announcements.length}',
                  s.announcements.isEmpty
                      ? 'none published'
                      : 'latest: ${s.announcements.first.title}',
                  Icons.campaign_rounded,
                  () => push(context, const NoticesAdminScreen()),
                ),
                _Stat(
                  'Complaints',
                  '${s.openComplaints}',
                  s.openComplaints == 0
                      ? 'all resolved'
                      : 'waiting for a response',
                  Icons.report_gmailerrorred_outlined,
                  () => push(context, const ComplaintsAdminScreen()),
                  badge: s.wants('Complaints')
                      ? s.complaints
                            .where((c) => c.status == ComplaintStatus.open)
                            .length
                      : 0,
                ),
              ],
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Needs your attention',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.green800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (attention.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'All caught up.',
                        style: TextStyle(color: AppColors.slate500),
                      ),
                    ),
                  for (final a in attention)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      onTap: a.$4,
                      leading: IconBadge(a.$1, size: 36),
                      title: Text(
                        a.$2,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.green800,
                        ),
                      ),
                      subtitle: Text(
                        a.$3,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.slate500,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.slate400,
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

String _greeting() {
  final h = DateTime.now().hour;
  return h < 12 ? 'GOOD MORNING' : (h < 18 ? 'GOOD AFTERNOON' : 'GOOD EVENING');
}

/// A slim bar under the title: today's date and whether anything waits.
class _TodayStrip extends StatelessWidget {
  const _TodayStrip({required this.waiting});
  final int waiting;

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final t = appState.today;
    final clear = waiting == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.green900,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold500.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.today_rounded, size: 18, color: AppColors.gold400),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_days[t.weekday - 1]}, ${_months[t.month - 1]} ${t.day}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: Motion.medium,
            child: Container(
              key: ValueKey(clear),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: clear ? AppColors.emeraldBg : AppColors.gold500,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                clear ? 'All caught up' : '$waiting to check',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: clear ? AppColors.emerald : AppColors.green900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain gold dot in the top-right corner of a card when something there needs
/// the admin (a message, a new photo, a report). Hidden at 0.
class _AlertDot extends StatelessWidget {
  const _AlertDot({required this.count, required this.child, this.fill = true});
  final int count;
  final Widget child;

  /// True in the grid (the card fills its cell); false for a card that sizes
  /// itself.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (fill) Positioned.fill(child: child) else child,
        Positioned(
          top: -6,
          right: -6,
          child: IgnorePointer(
            child: Pulse(
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  gradient: goldGradient,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.green800, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Number style shared by the stat cards: even-width digits so counting
/// doesn't wobble, tight tracking for a crisp look.
const _figures = [FontFeature.tabularFigures()];

class _Stat extends StatelessWidget {
  const _Stat(
    this.label,
    this.value,
    this.sub,
    this.icon,
    this.onTap, {
    this.badge = 0,
  });
  final String label, value, sub;
  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return _AlertDot(count: badge, child: _card());
  }

  Widget _card() {
    return AppCard(
      onTap: onTap,
      radius: 20,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label on the left, icon tucked in the top-right corner.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate500,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconBadge(icon, size: 30),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: CountUpText(
              value,
              style: const TextStyle(
                fontSize: 28,
                height: 1.05,
                letterSpacing: -.6,
                fontWeight: FontWeight.w800,
                fontFeatures: _figures,
                color: AppColors.green800,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: AppColors.slate400,
            ),
          ),
        ],
      ),
    );
  }
}

/// The headline card across the full width, in the same deep green and gold
/// as the Finance net-profit card, so the most important number stands out.
class _WideStat extends StatelessWidget {
  const _WideStat(
    this.label,
    this.value,
    this.sub,
    this.icon,
    this.onTap, {
    this.badge = 0,
  });
  final String label, value, sub;
  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return _AlertDot(count: badge, fill: false, child: _card());
  }

  Widget _card() {
    return PressScale(
      scale: .975,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.green700, AppColors.green900],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.gold500.withValues(alpha: .55)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashColor: AppColors.gold500.withValues(alpha: .15),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w800,
                            color: AppColors.gold400,
                          ),
                        ),
                        const SizedBox(height: 6),
                        CountUpText(
                          value,
                          style: const TextStyle(
                            fontSize: 36,
                            height: 1,
                            letterSpacing: -.8,
                            fontWeight: FontWeight.w800,
                            fontFeatures: _figures,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          sub,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.slate300,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: goldGradient,
                      borderRadius: BorderRadius.circular(17),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(icon, size: 26, color: AppColors.green900),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.gold400,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
