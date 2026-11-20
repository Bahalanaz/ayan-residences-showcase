import 'package:flutter/material.dart';

import '../../screens/home_screen.dart' show push;
import '../../screens/shell.dart' show SubPage;
import '../../state/app_state.dart' show appState;
import '../../state/sync.dart' show Sync;
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/chat_view.dart' show showImageViewer;
import '../../widgets/export.dart' show shareReceipt;
import '../admin_state.dart';
import 'payment_methods_screen.dart';

/// Payment proofs to verify, payment history and charges.
class PaymentsAdminScreen extends StatefulWidget {
  const PaymentsAdminScreen({super.key});
  @override
  State<PaymentsAdminScreen> createState() => _PaymentsAdminScreenState();
}

class _PaymentsAdminScreenState extends State<PaymentsAdminScreen> {
  int _tab = 0;
  String _q = '';

  @override
  void initState() {
    super.initState();
    // Receipts of the payments waiting to be checked download now.
    Sync.fetch(
      adminState.payments.where((p) => p.status == PayStatus.submitted),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final s = adminState;
        bool hit(PaymentRec p) => matchesSearch(_q, [
          p.tenant,
          p.unit,
          p.title,
          p.method,
          p.reference,
          p.date,
        ]);
        final toVerify = s.payments
            .where((p) => p.status == PayStatus.submitted)
            .where(hit)
            .toList();
        final history = s.payments
            .where((p) => p.status != PayStatus.submitted)
            .where(hit)
            .toList();
        final chargesShown = s.charges
            .where((c) => matchesSearch(_q, [c.tenant, c.title, c.due]))
            .toList();
        return SubPage(
          title: 'Payment verification',
          children: [
            // For payments that did not come through the app: cash, or a GCash /
            // bank transfer whose proof arrived another way.
            // Two equal gold buttons side by side.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: GoldButton(
                      label: 'Record payment',
                      icon: Icons.edit_note_rounded,
                      onPressed: () => s.tenants.isEmpty
                          ? toast(context, 'Add a tenant account first.')
                          : showAppSheet(
                              context,
                              title: 'Record payment',
                              builder: (_) => const _RecordPaymentForm(),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GoldButton(
                      label: 'Methods',
                      icon: Icons.account_balance_wallet_outlined,
                      onPressed: () =>
                          push(context, const PaymentMethodsScreen()),
                    ),
                  ),
                ],
              ),
            ),
            SegmentedTabs(
              labels: ['To verify (${toVerify.length})', 'History', 'Charges'],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
            SearchField(
              hint: 'Search tenant, unit, reference',
              onChanged: (v) => setState(() => _q = v),
            ),
            // Ghost cards the first time the screen opens, then the real list.
            LoadingSwitch(
              skeleton: const SkeletonCards(),
              child: Column(
                children: [
                  if (_tab == 0) ...[
                    if (toVerify.isEmpty)
                      const EmptyState(
                        icon: Icons.task_alt_rounded,
                        title: 'All caught up',
                        message: 'No payment proofs are waiting for you.',
                      ),
                    for (final p in toVerify)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _ProofCard(p),
                      ),
                  ],
                  if (_tab == 1) ...[
                    if (history.isEmpty)
                      const EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No payments yet',
                        message: 'Verified and rejected payments will be listed here.',
                      ),
                    for (final p in history)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _ProofCard(p),
                      ),
                  ],
                  if (_tab == 2) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: GoldButton(
                        label: 'Add charge',
                        icon: Icons.add,
                        onPressed: () => s.tenants.isEmpty
                            ? toast(context, 'Add a tenant account first.')
                            : showAppSheet(
                                context,
                                title: 'Add charge',
                                builder: (_) => const _ChargeForm(),
                              ),
                      ),
                    ),
                    if (chargesShown.isEmpty)
                      const EmptyState(
                        icon: Icons.request_quote_outlined,
                        title: 'No charges yet',
                        message:
                            'Rent and other charges you add will show here.',
                      ),
                    for (final c in chargesShown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _ChargeCard(c),
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

class _ProofCard extends StatelessWidget {
  const _ProofCard(this.p);
  final PaymentRec p;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.tenant,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
              ),
              Text(
                peso(p.amount, dhs: adminState.isVilla(p.tenant)),
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
            ],
          ),
          Text(
            '${p.unit} · ${p.title}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.slate500),
          ),
          // The months the tenant says they paid; verifying moves their stay to
          // the end of this period.
          if (p.coversFrom != null && p.coversTo != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'Covers ${formatDate(p.coversFrom!)} - ${formatDate(p.coversTo!)}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.green800,
                ),
              ),
            ),
          Text(
            '${p.method}${p.reference.isEmpty ? '' : ' · Ref ${p.reference}'} · ${p.date}',
            style: const TextStyle(fontSize: 12, color: AppColors.slate400),
          ),
          if (p.recordedByAdmin)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                'Recorded by admin',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.gold700,
                ),
              ),
            ),
          const SizedBox(height: 10),
          if (p.status == PayStatus.submitted) ...[
            if (p.proof == null && Sync.waiting(p, 'proof'))
              Container(
                height: 160,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.slate50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.gold600,
                ),
              )
            else if (p.proof != null)
              GestureDetector(
                onTap: () => showImageViewer(context, p.proof!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    p.proof!,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              )
            else
              Container(
                height: 70,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.slate50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.slate200),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_outlined, color: AppColors.gold600),
                    SizedBox(width: 8),
                    Text(
                      'No receipt photo attached',
                      style: TextStyle(color: AppColors.slate500),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
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
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => showAppSheet(
                      context,
                      title: 'Reject payment',
                      builder: (_) => _RejectForm(p),
                    ),
                    child: const Text(
                      'Reject',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GoldButton(
                    label: 'Verify',
                    onPressed: () {
                      adminState.verifyPayment(p);
                      toast(
                        context,
                        'Payment verified. Receipt sent to ${p.tenant}.',
                      );
                    },
                  ),
                ),
              ],
            ),
          ] else
            Row(
              children: [
                p.status == PayStatus.verified
                    ? Pill.verified('Verified')
                    : Pill.urgent('Rejected'),
                if (p.reason != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.reason!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.slate500,
                      ),
                    ),
                  ),
                ],
                if (p.status == PayStatus.verified) ...[
                  const Spacer(),
                  // Save or send the receipt (PDF).
                  TextButton.icon(
                    onPressed: () async {
                      try {
                        await shareReceipt(
                          receiptNo:
                              'AR-${p.id.replaceAll(RegExp(r'\D'), '').padLeft(5, '0')}',
                          tenant: p.tenant,
                          unit: p.unit,
                          title: p.title,
                          method: p.method,
                          reference: p.reference,
                          date: p.date,
                          amount: p.amount,
                          aed: adminState.isVilla(p.tenant),
                        );
                      } catch (e) {
                        if (context.mounted) {
                          toast(
                            context,
                            "Couldn't make the receipt. Please try again.",
                          );
                        }
                      }
                    },
                    icon: const Icon(
                      Icons.receipt_long_rounded,
                      size: 18,
                      color: AppColors.gold700,
                    ),
                    label: const Text(
                      'Receipt',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.gold700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _RejectForm extends StatefulWidget {
  const _RejectForm(this.p);
  final PaymentRec p;
  @override
  State<_RejectForm> createState() => _RejectFormState();
}

class _RejectFormState extends State<_RejectForm> {
  final _reason = TextEditingController(
    text: 'Reference number does not match.',
  );

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Reason (the tenant will see this)'),
        TextField(controller: _reason, maxLines: 3),
        const SizedBox(height: 16),
        GoldButton(
          label: 'Reject payment',
          onPressed: () {
            adminState.rejectPayment(widget.p, _reason.text.trim());
            popOnce(context);
            toast(context, 'Payment rejected');
          },
        ),
      ],
    );
  }
}

/// Records a payment made outside the app and marks the charge it covers as
/// paid, so the tenant's month is cleared without needing their proof.
class _RecordPaymentForm extends StatefulWidget {
  const _RecordPaymentForm();
  @override
  State<_RecordPaymentForm> createState() => _RecordPaymentFormState();
}

class _RecordPaymentFormState extends State<_RecordPaymentForm> {
  static const _other = 'Other / advance (not tied to a charge)';

  /// The payment accounts management set up (GCash, banks...), plus cash.
  List<String> get _methods => {
    for (final a in appState.payAccounts)
      a.isWallet ? a.name : '${a.name} transfer',
    'Other bank transfer',
    'Cash',
  }.toList();

  final _key = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _title = TextEditingController(text: 'Advance payment');
  final _ref = TextEditingController();
  final _date = TextEditingController(text: formatDate(appState.today));
  late String _tenant = adminState.tenants.first.name;
  String _pays = '';
  late String _method = _methods.first;

  TenantRec get _t => adminState.tenants.firstWhere((t) => t.name == _tenant);
  List<ChargeRec> get _unpaid => adminState.unpaidFor(_tenant);

  String _label(ChargeRec c) =>
      '${c.title} · ${peso(c.remaining, dhs: adminState.isVilla(_tenant))} · due ${c.due}';

  @override
  void initState() {
    super.initState();
    _selectDefault();
  }

  /// Picks the oldest unpaid charge (what is usually being paid) and fills
  /// in its amount.
  void _selectDefault() {
    final list = _unpaid;
    if (list.isEmpty) {
      _pays = _other;
      _amount.clear();
    } else {
      final c = list.last;
      _pays = _label(c);
      _amount.text = c.remaining.toStringAsFixed(
        c.remaining == c.remaining.roundToDouble() ? 0 : 2,
      );
    }
  }

  ChargeRec? get _charge =>
      _unpaid.where((c) => _label(c) == _pays).firstOrNull;

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _ref.dispose();
    _date.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final charge = _charge;
    final amount = double.tryParse(_amount.text) ?? 0;
    final short =
        charge != null && amount > 0 && amount < charge.remaining - .009;
    return Form(
      key: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('Tenant'),
          DropdownField(
            value: _tenant,
            items: [for (final t in adminState.tenants) t.name],
            onChanged: (v) => setState(() {
              _tenant = v;
              _selectDefault();
            }),
          ),
          const SizedBox(height: 12),
          const FieldLabel('Payment is for'),
          DropdownField(
            value: _pays,
            items: [for (final c in _unpaid) _label(c), _other],
            onChanged: (v) => setState(() {
              _pays = v;
              final c = _charge;
              if (c != null) {
                _amount.text = c.remaining.toStringAsFixed(
                  c.remaining == c.remaining.roundToDouble() ? 0 : 2,
                );
              }
            }),
          ),
          if (charge == null) ...[
            const SizedBox(height: 12),
            const FieldLabel('Description'),
            TextFormField(
              controller: _title,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Describe the payment' : null,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FieldLabel(
                      'Amount (${currencySign(adminState.isVilla(_tenant))})',
                    ),
                    TextFormField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0
                          ? 'Enter an amount'
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('Paid on'),
                    TextFormField(
                      controller: _date,
                      validator: (v) => parseDate(v ?? '') == null
                          ? 'e.g. Nov 3, 2026'
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (short)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Less than the charge, so ${charge.title} stays open with ${peso(charge.amount - amount, dhs: adminState.isVilla(_tenant))} still owed.',
                style: const TextStyle(fontSize: 12, color: AppColors.amber),
              ),
            ),
          const SizedBox(height: 12),
          const FieldLabel('Method'),
          DropdownField(
            value: _method,
            items: _methods,
            onChanged: (v) => setState(() => _method = v),
          ),
          if (_method != 'Cash') ...[
            const SizedBox(height: 12),
            const FieldLabel('Reference number (optional)'),
            TextFormField(
              controller: _ref,
              decoration: const InputDecoration(hintText: 'From the receipt'),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Marked verified right away. ${_t.name} gets a "Payment received" notice'
            '${charge != null && charge.title.toLowerCase().contains('rent') ? ', and their paid-until date moves forward.' : '.'}',
            style: const TextStyle(fontSize: 12, color: AppColors.slate500),
          ),
          const SizedBox(height: 16),
          GoldButton(
            label: 'Record and mark paid',
            icon: Icons.check_rounded,
            onPressed: () {
              if (!_key.currentState!.validate()) return;
              adminState.recordPayment(
                _t,
                charge: charge,
                title: _title.text.trim(),
                amount: double.parse(_amount.text),
                method: _method,
                reference: _ref.text.trim(),
                date: _date.text.trim(),
              );
              popOnce(context);
              toast(context, 'Payment recorded for ${_t.name}');
            },
          ),
        ],
      ),
    );
  }
}

class _ChargeCard extends StatelessWidget {
  const _ChargeCard(this.c);
  final ChargeRec c;
  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: 18,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
                Text(
                  '${c.tenant} · due ${c.due}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.slate500,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                peso(
                  c.partlyPaid ? c.remaining : c.amount,
                  dhs: adminState.isVilla(c.tenant),
                ),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
              // A part-payment: what is left, and what was paid of the total.
              if (c.partlyPaid)
                Text(
                  'left of ${peso(c.amount, dhs: adminState.isVilla(c.tenant))}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.slate500,
                  ),
                ),
              const SizedBox(height: 4),
              c.paid
                  ? Pill.verified('Paid')
                  : c.partlyPaid
                  ? Pill.pending('Part paid')
                  : c.overdue
                  ? Pill.urgent('Overdue')
                  : Pill.pending('Upcoming'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for the name of a new charge type. It owns its text field so it is
/// only disposed once the dialog has fully closed.
class _NewTypeDialog extends StatefulWidget {
  const _NewTypeDialog();
  @override
  State<_NewTypeDialog> createState() => _NewTypeDialogState();
}

class _NewTypeDialogState extends State<_NewTypeDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: const Text(
        'New option',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.green800,
        ),
      ),
      content: TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'e.g. Parking, Key replacement',
        ),
        onSubmitted: (v) => popOnce(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => popOnce(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold500,
            foregroundColor: AppColors.green900,
          ),
          onPressed: () => popOnce(context, _name.text),
          child: const Text(
            'Add',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _ChargeForm extends StatefulWidget {
  const _ChargeForm();
  @override
  State<_ChargeForm> createState() => _ChargeFormState();
}

class _ChargeFormState extends State<_ChargeForm> {
  final _key = GlobalKey<FormState>();
  String _tenant = adminState.tenants.first.name;
  String _type = adminState.chargeTypes.first;
  final _amount = TextEditingController();

  /// Next month's 5th by default.
  DateTime _due = DateTime(appState.today.year, appState.today.month + 1, 5);

  /// Picker entry that asks for a new option.
  static const _addNew = '\u0000add';

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Asks for the name of a new charge type, adds it and selects it.
  Future<void> _newType() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewTypeDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    setState(() => _type = adminState.addChargeType(name));
  }

  Future<void> _pickDue() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (d != null) setState(() => _due = d);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('Tenant'),
          DropdownField(
            value: _tenant,
            items: [for (final t in adminState.tenants) t.name],
            onChanged: (v) => setState(() => _tenant = v),
          ),
          const SizedBox(height: 12),
          const FieldLabel('What is it for?'),
          DropdownField(
            value: _type,
            title: 'What is it for?',
            options: [
              for (final t in adminState.chargeTypes)
                PickerOption(value: t, label: t),
              const PickerOption(
                value: _addNew,
                label: 'Add a new option',
                subtitle: 'Type your own, like Parking or Key replacement',
                icon: Icons.add_rounded,
              ),
            ],
            onChanged: (v) {
              if (v == _addNew) {
                _newType();
              } else {
                setState(() => _type = v);
              }
            },
          ),
          const SizedBox(height: 12),
          FieldLabel('Amount (${currencySign(adminState.isVilla(_tenant))})'),
          TextFormField(
            controller: _amount,
            keyboardType: TextInputType.number,
            validator: (v) =>
                (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter an amount' : null,
          ),
          const SizedBox(height: 12),
          const FieldLabel('Due date'),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _pickDue,
            child: InputDecorator(
              decoration: const InputDecoration(
                prefixIcon: Icon(
                  Icons.event_outlined,
                  size: 18,
                  color: AppColors.gold600,
                ),
              ),
              child: Text(
                formatDate(_due),
                style: const TextStyle(fontSize: 14, color: AppColors.green800),
              ),
            ),
          ),
          const SizedBox(height: 16),
          GoldButton(
            label: 'Add charge',
            onPressed: () {
              if (!_key.currentState!.validate()) return;
              adminState.addCharge(
                _tenant,
                _type,
                double.parse(_amount.text),
                formatDate(_due),
              );
              popOnce(context);
              toast(context, 'Charge added');
            },
          ),
        ],
      ),
    );
  }
}
