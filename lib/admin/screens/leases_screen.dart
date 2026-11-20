import 'package:flutter/material.dart';

import '../../screens/home_screen.dart' show push;
import '../../screens/shell.dart' show SubPage;
import '../../theme.dart';
import '../../widgets/common.dart';
import '../admin_state.dart';
import 'contract_admin_screen.dart';
import 'move_out_screen.dart';

/// Renewal / move-out requests and leases that end soon.
class LeasesScreen extends StatelessWidget {
  const LeasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final ending = adminState.tenants.toList()
          ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
        return SubPage(
          title: 'Leases & requests',
          children: [
            const Text(
              'Requests',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (adminState.requests.isEmpty)
              const Text(
                'No requests.',
                style: TextStyle(color: AppColors.slate300),
              ),
            for (final r in adminState.requests)
              AppCard(
                radius: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${r.tenant} · ${r.unit}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.green800,
                            ),
                          ),
                        ),
                        Text(
                          r.date,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.slate400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      r.kind,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.gold700,
                      ),
                    ),
                    Text(
                      r.note,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.slate600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (r.status == RequestStatus.pending)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.red,
                                side: const BorderSide(color: AppColors.red),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              onPressed: () {
                                adminState.decide(r, false);
                                toast(context, 'Request declined');
                              },
                              child: const Text(
                                'Decline',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            // Approving a renewal means renewing the lease: open
                            // the renewal form; it marks the request approved.
                            child: Builder(
                              builder: (context) {
                                final t = adminState.tenants
                                    .where((x) => x.name == r.tenant)
                                    .firstOrNull;
                                final renewal =
                                    r.kind.toLowerCase().contains('renewal') &&
                                    t != null;
                                final moveOut =
                                    r.kind.toLowerCase().contains('move') &&
                                    t != null;
                                return GoldButton(
                                  label: renewal
                                      ? 'Renew lease'
                                      : moveOut
                                      ? 'Start move-out'
                                      : 'Approve',
                                  onPressed: () {
                                    if (moveOut) {
                                      push(context, MoveOutScreen(t));
                                      return;
                                    }
                                    if (renewal) {
                                      push(context, RenewLeaseScreen(t));
                                      return;
                                    }
                                    adminState.decide(r, true);
                                    toast(context, 'Request approved');
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      )
                    else
                      r.status == RequestStatus.approved
                          ? Pill.verified('Approved')
                          : Pill.urgent('Declined'),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            const Text(
              'Lease end dates',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            for (final t in ending)
              AppCard(
                radius: 18,
                onTap: () => push(context, ContractAdminScreen(t)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${t.name} · ${t.unit}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.green800,
                            ),
                          ),
                          Text(
                            t.nextLease != null
                                ? 'Ends ${t.leaseEnd} · renewal starts ${t.nextLease!.start}'
                                : t.pastLeases.isEmpty
                                ? 'Ends ${t.leaseEnd}'
                                : 'Ends ${t.leaseEnd} · renewed',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.slate500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    t.nextLease != null
                        ? Pill.verified('RENEWED')
                        : t.daysLeft <= 30
                        ? Pill.urgent('${t.daysLeft} days')
                        : t.daysLeft <= 90
                        ? Pill.pending('${t.daysLeft} days')
                        : Pill.neutral('${t.daysLeft} days'),
                  ],
                ),
              ),
            if (adminState.formerTenants.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Text(
                'Former tenants',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              for (final f in adminState.formerTenants)
                AppCard(
                  radius: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${f.name} · ${f.unit}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.green800,
                              ),
                            ),
                          ),
                          f.owedAtMoveOut > 0
                              ? Pill.urgent(
                                  'OWES ${peso(f.owedAtMoveOut, dhs: f.unitType == 'Villa')}',
                                )
                              : Pill.neutral('SETTLED'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Moved out ${formatDate(f.movedOut)} · lease ${f.leaseStart} - ${f.leaseEnd}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.slate500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        f.depositNote,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.green800,
                        ),
                      ),
                      if (f.inspection.isNotEmpty)
                        Text(
                          f.inspection,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.slate500,
                          ),
                        ),
                      if (f.phone.isNotEmpty)
                        Text(
                          f.phone,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.slate400,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
