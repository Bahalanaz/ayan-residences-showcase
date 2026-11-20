import 'package:flutter/material.dart';

import '../../screens/shell.dart' show SubPage;
import '../../state/sync.dart' show Sync;
import '../../theme.dart';
import '../../widgets/common.dart';
import '../admin_state.dart';

/// One cheque, for management to verify: the photo the tenant uploaded, the
/// cheque details, then where it is (held, deposited, cleared, bounced).
class ChequeDetailScreen extends StatefulWidget {
  const ChequeDetailScreen(this.c, {super.key});
  final ChequeRec c;
  @override
  State<ChequeDetailScreen> createState() => _ChequeDetailScreenState();
}

class _ChequeDetailScreenState extends State<ChequeDetailScreen> {
  late ChequeStatus _status = widget.c.status;

  @override
  void initState() {
    super.initState();
    // The photo downloads when the cheque is opened.
    Sync.fetch([widget.c]).then((_) {
      if (mounted) setState(() {});
    });
  }

  static const _choices = [
    (ChequeStatus.held, 'Held', 'Not yet banked', Icons.inventory_2_outlined),
    (
      ChequeStatus.deposited,
      'Deposited',
      'Banked, waiting to clear',
      Icons.account_balance_outlined,
    ),
    (
      ChequeStatus.cleared,
      'Cleared',
      'The money is in. Extends paid-through',
      Icons.verified_outlined,
    ),
    (
      ChequeStatus.bounced,
      'Bounced',
      'Returned by the bank',
      Icons.error_outline_rounded,
    ),
  ];

  void _save() {
    final c = widget.c;
    final extends_ =
        _status == ChequeStatus.cleared &&
        c.status != ChequeStatus.cleared &&
        c.kind == ChequeKind.postDated;
    adminState.setChequeStatus(c, _status);
    popOnce(context);
    toast(
      context,
      extends_
          ? 'Cleared. Paid-through date extended.'
          : 'Saved. Cheque is ${_status.name}.',
    );
  }

  Future<void> _remove() async {
    final why = adminState.whyKeepCheque(widget.c);
    if (why != null) {
      toast(context, why);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this cheque?'),
        content: const Text('It will be taken off the tenant\'s list.'),
        actions: [
          TextButton(
            onPressed: () => popOnce(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => popOnce(ctx, true),
            child: const Text('Remove', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    adminState.removeCheque(widget.c);
    popOnce(context);
    toast(context, 'Cheque removed.');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final deposit = c.kind == ChequeKind.deposit;
    return SubPage(
      title: deposit ? 'Deposit cheque' : 'Post-dated cheque',
      bottom: GoldButton(
        label: _status == c.status && c.newPhoto
            ? 'Photo checked, keep as ${_status.name}'
            : 'Save verification',
        icon: Icons.check_rounded,
        onPressed: _status == c.status && !c.newPhoto ? null : _save,
      ),
      children: [
        // The uploaded photo; tap to zoom.
        _PhotoCard(c),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      peso(c.amount, dhs: true),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green800,
                      ),
                    ),
                  ),
                  _pill(c.status),
                ],
              ),
              const SizedBox(height: 10),
              KeyValueRow('Tenant', c.tenant),
              KeyValueRow(
                'Unit',
                adminState.tenants
                        .where((t) => t.name == c.tenant)
                        .firstOrNull
                        ?.unitLabel ??
                    'No unit',
              ),
              KeyValueRow(
                'Type',
                deposit ? 'Deposit cheque' : 'Post-dated cheque',
              ),
              KeyValueRow(deposit ? 'Dated' : 'Banks on', formatDate(c.date)),
              if (!deposit)
                KeyValueRow(
                  'Pays for',
                  '${c.months} ${c.months == 1 ? 'month' : 'months'} of rent',
                ),
              KeyValueRow(
                'Cheque number',
                c.chequeNo.isEmpty ? 'Not given' : c.chequeNo,
              ),
              KeyValueRow('Bank', c.bank.isEmpty ? 'Not given' : c.bank),
              if (c.replaces != null)
                KeyValueRow(
                  'Replaces',
                  'Bounced cheque ${adminState.cheques.where((x) => x.id == c.replaces).firstOrNull?.chequeNo ?? ''}'
                      .trim(),
                ),
              if (c.returnedOn != null)
                KeyValueRow('Handed back', c.returnedOn!),
              KeyValueRow(
                'Photo uploaded',
                c.uploadedOn ?? 'Not yet',
                last: true,
              ),
              // Details can change until the cheque has cleared or bounced
              // (after that it is history).
              if (c.status == ChequeStatus.held ||
                  c.status == ChequeStatus.deposited) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: AppColors.green800,
                    side: const BorderSide(color: AppColors.gold500),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () async {
                    await showAppSheet(
                      context,
                      title: 'Edit cheque',
                      builder: (_) => _EditForm(c),
                    );
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: AppColors.gold700,
                  ),
                  label: const Text(
                    'Edit details',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Verify',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
              const Text(
                'Check the photo against the details, then set where the cheque is.',
                style: TextStyle(fontSize: 12, color: AppColors.slate500),
              ),
              const SizedBox(height: 12),
              for (final o in _choices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _Choice(
                    icon: o.$4,
                    title: o.$2,
                    sub:
                        o.$1 == ChequeStatus.bounced &&
                            c.kind == ChequeKind.postDated
                        ? 'Returned by the bank. A replacement due in 7 days is added${adminState.bouncedChequeFee > 0 ? ', plus a ${peso(adminState.bouncedChequeFee, dhs: true)} fee' : ''}.'
                        : o.$3,
                    selected: _status == o.$1,
                    danger: o.$1 == ChequeStatus.bounced,
                    onTap: () => setState(() => _status = o.$1),
                  ),
                ),
              const SizedBox(height: 4),
              Center(
                child: TextButton.icon(
                  onPressed: _remove,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.red,
                    size: 18,
                  ),
                  label: const Text(
                    'Remove cheque',
                    style: TextStyle(
                      color: AppColors.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Pill _pill(ChequeStatus s) => switch (s) {
  ChequeStatus.held => Pill.neutral('HELD'),
  ChequeStatus.deposited => Pill.info('DEPOSITED'),
  ChequeStatus.cleared => Pill.verified('CLEARED'),
  ChequeStatus.bounced => Pill.urgent('BOUNCED'),
};

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.sub,
    required this.selected,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String title, sub;
  final bool selected, danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = danger ? AppColors.red : AppColors.gold600;
    return PressScale(
      child: Material(
        color: selected ? accent.withValues(alpha: .08) : AppColors.slate50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? accent : AppColors.slate200,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: selected ? accent : AppColors.slate400),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.green800,
                        ),
                      ),
                      Text(
                        sub,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.slate500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? accent : AppColors.slate300,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The tenant's photo of the cheque. Without one yet, a drawn preview of the
/// cheque from its details, clearly marked as not a photo.
class _PhotoCard extends StatelessWidget {
  const _PhotoCard(this.c);
  final ChequeRec c;

  @override
  Widget build(BuildContext context) {
    final photo = c.photo;
    final hasPhoto = photo != null && photo.isNotEmpty;
    // On the server, still downloading.
    if (!hasPhoto && Sync.waiting(c, 'photo')) {
      return const AppCard(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          height: 160,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.gold600,
            ),
          ),
        ),
      );
    }
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasPhoto ? Icons.photo_outlined : Icons.hide_image_outlined,
                size: 18,
                color: hasPhoto ? AppColors.gold600 : AppColors.slate400,
              ),
              const SizedBox(width: 6),
              Text(
                hasPhoto
                    ? 'Photo from the tenant · tap to zoom'
                    : 'No photo uploaded yet',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasPhoto)
            GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  backgroundColor: Colors.black,
                  insetPadding: const EdgeInsets.all(12),
                  child: InteractiveViewer(
                    maxScale: 5,
                    child: Image.memory(photo),
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  photo,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            )
          else
            Opacity(opacity: .75, child: _ChequeArt(c)),
        ],
      ),
    );
  }
}

/// A simple drawing of a cheque filled in from its details.
class _ChequeArt extends StatelessWidget {
  const _ChequeArt(this.c);
  final ChequeRec c;

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(
      fontSize: 9.5,
      color: AppColors.slate400,
      letterSpacing: .6,
    );
    const value = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: AppColors.green800,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3EEDF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                c.bank.isEmpty ? 'BANK' : c.bank.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: AppColors.green800,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              const Text('DATE  ', style: label),
              Text(formatDate(c.date), style: value),
            ],
          ),
          const SizedBox(height: 14),
          const Text('PAY', style: label),
          const Text('Ayan Residences', style: value),
          const Divider(height: 14),
          Row(
            children: [
              const Text('AED  ', style: label),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.slate300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  peso(c.amount, dhs: true).replaceFirst('AED ', ''),
                  style: value,
                ),
              ),
              const Spacer(),
              const Text('SIGNATURE ________', style: label),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '⑈ ${c.chequeNo.isEmpty ? '000000' : c.chequeNo} ⑈',
            style: const TextStyle(
              fontSize: 12,
              letterSpacing: 2,
              color: AppColors.slate500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Edits a cheque's amount, date, months, number and bank.
class _EditForm extends StatefulWidget {
  const _EditForm(this.c);
  final ChequeRec c;
  @override
  State<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends State<_EditForm> {
  final _key = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.c.amount.toStringAsFixed(0),
  );
  late final _no = TextEditingController(text: widget.c.chequeNo);
  late final _bank = TextEditingController(text: widget.c.bank);
  late DateTime _date = widget.c.date;
  late int _months = widget.c.months;
  static const _monthChoices = [1, 2, 3, 4, 6, 12];

  @override
  void dispose() {
    _amount.dispose();
    _no.dispose();
    _bank.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deposit = widget.c.kind == ChequeKind.deposit;
    return Form(
      key: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('Amount (AED)'),
          TextFormField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) =>
                (double.tryParse((v ?? '').replaceAll(',', '')) ?? 0) <= 0
                ? 'Enter the amount'
                : null,
          ),
          const SizedBox(height: 12),
          FieldLabel(
            deposit
                ? 'Date on the cheque'
                : 'Date written (when it can be banked)',
          ),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2040),
              );
              if (d != null) setState(() => _date = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                prefixIcon: Icon(
                  Icons.event_outlined,
                  size: 18,
                  color: AppColors.gold600,
                ),
              ),
              child: Text(
                formatDate(_date),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.green800,
                ),
              ),
            ),
          ),
          if (!deposit) ...[
            const SizedBox(height: 12),
            const FieldLabel('Months of rent it pays for'),
            SegmentedTabs(
              light: true,
              labels: [for (final m in _monthChoices) '$m'],
              index: _monthChoices.contains(_months)
                  ? _monthChoices.indexOf(_months)
                  : 2,
              onChanged: (i) => setState(() => _months = _monthChoices[i]),
            ),
          ],
          const SizedBox(height: 12),
          const FieldLabel('Cheque number (optional)'),
          TextFormField(controller: _no),
          const SizedBox(height: 12),
          const FieldLabel('Bank (optional)'),
          TextFormField(controller: _bank),
          const SizedBox(height: 16),
          GoldButton(
            label: 'Save changes',
            onPressed: () {
              if (!_key.currentState!.validate()) return;
              adminState.updateCheque(
                widget.c,
                amount: double.parse(_amount.text.replaceAll(',', '')),
                date: _date,
                months: deposit ? 0 : _months,
                chequeNo: _no.text.trim(),
                bank: _bank.text.trim(),
              );
              popOnce(context);
              toast(context, 'Cheque updated.');
            },
          ),
        ],
      ),
    );
  }
}
