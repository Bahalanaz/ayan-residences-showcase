import 'package:flutter/material.dart';

import '../../screens/shell.dart' show SubPage;
import '../../state/app_state.dart' show appState;
import '../../state/sync.dart' show EditingGuard;
import '../../theme.dart';
import '../../widgets/common.dart';
import '../admin_state.dart';

/// Ends a tenancy: the move-out date, the deposit
/// (refund less damage, or the villa's cheques handed back), then the
/// account is closed and the unit freed. The tenant stays on record under
/// Former tenants.
class MoveOutScreen extends StatefulWidget {
  const MoveOutScreen(this.tenant, {super.key});
  final TenantRec tenant;

  @override
  State<MoveOutScreen> createState() => _MoveOutScreenState();
}

class _MoveOutScreenState extends State<MoveOutScreen> with EditingGuard {
  TenantRec get _t => widget.tenant;
  late final bool _villa = adminState.isVilla(_t.name);

  late DateTime _date = () {
    final today = DateTime(
      appState.today.year,
      appState.today.month,
      appState.today.day,
    );
    final end = parseDate(_t.leaseEnd);
    // Default: the lease end if it is still ahead, otherwise today.
    return end != null &&
            end.isAfter(today) &&
            end.difference(today).inDays <= 31
        ? end
        : today;
  }();

  final _deduction = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _deduction.dispose();
    _reason.dispose();
    super.dispose();
  }

  double get _deduct =>
      double.tryParse(_deduction.text.replaceAll(',', '')) ?? 0;

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime(2040),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _confirm() async {
    if (_deduct > 0 && _reason.text.trim().isEmpty) {
      toast(context, 'Say what the deduction is for.');
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Move ${_t.name} out?',
      message:
          'Their account will be closed and ${_t.unit} set to vacant. '
          'They are kept under Former tenants with this record.',
      action: 'Move out',
    );
    if (!ok || !mounted) return;
    adminState.moveOut(
      _t,
      date: _date,
      deduction: _deduct,
      reason: _reason.text.trim(),
      inspection: '',
    );
    Navigator.of(context).popUntil((r) => r.isFirst);
    toast(context, '${_t.name} moved out. ${_t.unit} is now vacant.');
  }

  @override
  Widget build(BuildContext context) {
    String money(double v) => peso(v, dhs: _villa);
    final open = adminState.charges
        .where((c) => c.tenant == _t.name && !c.paid)
        .toList();
    final dropped = open
        .where((c) => (parseDate(c.due) ?? DateTime(0)).isAfter(_date))
        .toList();
    final owed = open
        .where((c) => !dropped.contains(c))
        .fold(0.0, (n, c) => n + c.remaining);
    final returning = _villa
        ? adminState.cheques
              .where(
                (c) =>
                    c.tenant == _t.name &&
                    c.status == ChequeStatus.held &&
                    c.returnedOn == null &&
                    (c.kind == ChequeKind.deposit || !c.date.isBefore(_date)),
              )
              .toList()
        : const <ChequeRec>[];
    final refund = (_t.deposit - _deduct).clamp(0, double.infinity).toDouble();

    return SubPage(
      title: 'Move out',
      bottom: GoldButton(
        label: 'Confirm move-out',
        icon: Icons.logout_rounded,
        onPressed: _confirm,
      ),
      children: [
        AppCard(
          child: Row(
            children: [
              const IconBadge(Icons.person_outline_rounded, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green800,
                      ),
                    ),
                    Text(
                      '${_t.unit} · lease ${_t.leaseStart} - ${_t.leaseEnd}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.slate500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Date.
        AppCard(
          onTap: _pickDate,
          child: Row(
            children: [
              const IconBadge(Icons.event_rounded, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Move-out date',
                      style: TextStyle(fontSize: 12, color: AppColors.slate500),
                    ),
                    Text(
                      formatDate(_date),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green800,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit_calendar_rounded, color: AppColors.gold700),
            ],
          ),
        ),
        // Deposit.
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _villa ? 'Damage charge' : 'Security deposit',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _villa
                    ? 'Villas have a deposit cheque instead of cash. Enter any damage to charge; it is recorded as owed.'
                    : 'Held: ${money(_t.deposit)}. Enter a deduction for damage found, if any.',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppColors.slate500,
                ),
              ),
              const SizedBox(height: 10),
              FieldLabel('Deduction (${currencySign(_villa)})'),
              TextField(
                controller: _deduction,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: '0'),
              ),
              if (_deduct > 0) ...[
                const SizedBox(height: 10),
                const FieldLabel('Reason'),
                TextField(
                  controller: _reason,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Broken cabinet door',
                  ),
                ),
              ],
            ],
          ),
        ),
        // Summary.
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Summary',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
              const SizedBox(height: 6),
              if (!_villa) ...[
                KeyValueRow('Deposit held', money(_t.deposit)),
                if (_deduct > 0)
                  KeyValueRow('Deduction', '- ${money(_deduct)}'),
                KeyValueRow('Refund to tenant', money(refund)),
                if (_deduct > _t.deposit)
                  KeyValueRow(
                    'Damage beyond the deposit',
                    money(_deduct - _t.deposit),
                  ),
              ],
              if (_villa)
                KeyValueRow(
                  'Cheques to hand back',
                  returning.isEmpty
                      ? 'None'
                      : '${returning.length} (${returning.any((c) => c.kind == ChequeKind.deposit) ? 'incl. deposit cheque' : 'post-dated'})',
                ),
              KeyValueRow('Still unpaid', owed > 0 ? money(owed) : 'Nothing'),
              KeyValueRow(
                'Charges dropped (after move-out)',
                dropped.isEmpty ? 'None' : '${dropped.length}',
                last: true,
              ),
            ],
          ),
        ),
        if (owed > 0)
          Text(
            '${_t.name} still owes ${money(owed)}. It is kept on their former-tenant record so you can follow it up.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.gold400,
            ),
          ),
      ],
    );
  }
}
