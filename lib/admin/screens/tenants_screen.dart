import 'package:flutter/material.dart';

import '../../screens/home_screen.dart' show push;
import '../../screens/shell.dart' show SubPage;
import '../../theme.dart';
import '../../widgets/common.dart';
import '../admin_state.dart';

class TenantsScreen extends StatelessWidget {
  const TenantsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) => SubPage(
        title: 'Tenants',
        children: [
          for (final t in adminState.tenants)
            AppCard(
              radius: 18,
              onTap: () => push(context, TenantDetailScreen(t)),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.gold500,
                    child: Icon(Icons.person, color: AppColors.green900),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.green800,
                          ),
                        ),
                        Text(
                          '${t.unitLabel} · ${t.stayType}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.slate500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  t.balance > 0
                      ? Pill.urgent(
                          peso(t.balance, dhs: adminState.isVilla(t.name)),
                        )
                      : Pill.verified('Paid up'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class TenantDetailScreen extends StatelessWidget {
  const TenantDetailScreen(this.t, {super.key});
  final TenantRec t;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final payments = adminState.payments
            .where((p) => p.tenant == t.name)
            .toList();
        return SubPage(
          title: t.name,
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Profile',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.green800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  KeyValueRow('Unit', t.unitLabel),
                  KeyValueRow('Phone', t.phone),
                  KeyValueRow('Email', t.email),
                  KeyValueRow('Stay type', t.stayType),
                  KeyValueRow(
                    adminState.rentLabelOf(t),
                    peso(t.rent, dhs: adminState.isVilla(t.name)),
                    last: true,
                  ),
                ],
              ),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Lease',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.green800,
                          ),
                        ),
                      ),
                      if (t.daysLeft <= 90)
                        t.daysLeft <= 30
                            ? Pill.urgent('${t.daysLeft} days left')
                            : Pill.pending('${t.daysLeft} days left'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  KeyValueRow('Start', t.leaseStart),
                  KeyValueRow('End', t.leaseEnd, last: true),
                  const SizedBox(height: 10),
                  NavyButton(
                    label: 'Upload new lease agreement',
                    icon: Icons.upload_file_rounded,
                    onPressed: () => toast(
                      context,
                      'Lease uploaded. ${t.name} can see it in the app.',
                    ),
                  ),
                ],
              ),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Balance',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.green800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    peso(t.balance, dhs: adminState.isVilla(t.name)),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: t.balance > 0 ? AppColors.red : AppColors.emerald,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final p in payments)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${p.title} · ${p.date}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.slate600,
                              ),
                            ),
                          ),
                          Text(
                            peso(p.amount, dhs: adminState.isVilla(t.name)),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.green800,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Security deposit',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.green800,
                          ),
                        ),
                      ),
                      t.depositNote == null
                          ? Pill.info('HELD')
                          : Pill.verified('SETTLED'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.depositNote ??
                        peso(t.deposit, dhs: adminState.isVilla(t.name)),
                    style: TextStyle(
                      fontSize: t.depositNote == null ? 24 : 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.gold600,
                    ),
                  ),
                  if (t.depositNote == null) ...[
                    const SizedBox(height: 10),
                    GoldButton(
                      label: 'Settle deposit (move-out)',
                      onPressed: () => showAppSheet(
                        context,
                        title: 'Settle deposit',
                        builder: (_) => _SettleForm(t),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SettleForm extends StatefulWidget {
  const _SettleForm(this.t);
  final TenantRec t;
  @override
  State<_SettleForm> createState() => _SettleFormState();
}

class _SettleFormState extends State<_SettleForm> {
  final _deduction = TextEditingController(text: '0');
  final _reason = TextEditingController();

  @override
  void dispose() {
    _deduction.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = double.tryParse(_deduction.text) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyValueRow(
          'Deposit held',
          peso(widget.t.deposit, dhs: adminState.isVilla(widget.t.name)),
        ),
        const SizedBox(height: 8),
        FieldLabel(
          'Deductions (${currencySign(adminState.isVilla(widget.t.name))}) — damages, unpaid bills',
        ),
        TextField(
          controller: _deduction,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        const FieldLabel('Reason'),
        TextField(controller: _reason),
        const SizedBox(height: 12),
        KeyValueRow(
          'Refund to tenant',
          peso(
            (widget.t.deposit - d).clamp(0, double.infinity),
            dhs: adminState.isVilla(widget.t.name),
          ),
          last: true,
        ),
        const SizedBox(height: 16),
        GoldButton(
          label: 'Record refund',
          onPressed: () {
            adminState.settleDeposit(
              widget.t,
              d,
              _reason.text.trim().isEmpty
                  ? 'no reason given'
                  : _reason.text.trim(),
            );
            popOnce(context);
            toast(context, 'Deposit settled');
          },
        ),
      ],
    );
  }
}
