import 'package:flutter/material.dart';

import 'dart:typed_data';

import '../../screens/contract_screen.dart' show ordinal;
import '../../screens/home_screen.dart' show push;
import '../../state/app_state.dart' show appState;
import 'move_out_screen.dart';
import '../../screens/shell.dart' show SubPage;
import '../../state/sync.dart' show EditingGuard, Sync;
import '../../theme.dart';
import '../../widgets/chat_view.dart' show PdfTile, pickPdf;
import '../../widgets/common.dart';
import '../admin_state.dart';

/// Management's side of the tenant's "Rental Contract & Lease" screen: edit
/// the lease dates and terms the tenant sees, and assign the contract PDF.
class ContractAdminScreen extends StatefulWidget {
  const ContractAdminScreen(this.tenant, {super.key});
  final TenantRec tenant;
  @override
  State<ContractAdminScreen> createState() => _ContractAdminScreenState();
}

class _ContractAdminScreenState extends State<ContractAdminScreen>
    with EditingGuard {
  @override
  void initState() {
    super.initState();
    // The contracts (current and earlier) download now.
    Sync.fetchTenant(widget.tenant);
  }

  late DateTime _start = parseDate(widget.tenant.leaseStart) ?? appState.today;
  late DateTime _end =
      parseDate(widget.tenant.leaseEnd) ??
      DateTime(
        appState.today.year + 1,
        appState.today.month,
        appState.today.day - 1,
      );
  late int _dueDay = widget.tenant.dueDay;
  late int _cheques = widget.tenant.chequesPerYear;

  /// Takes the tenant's saved terms again (after a renewal changed them).
  void _reload() {
    _start = parseDate(_t.leaseStart) ?? _start;
    _end = parseDate(_t.leaseEnd) ?? _end;
    _dueDay = _t.dueDay;
    _cheques = _t.chequesPerYear;
    _rent.text = _plain(_t.rent);
    _deposit.text = _plain(_t.deposit);
    _dirty = false;
  }

  late final bool _isVilla = adminState.isVilla(widget.tenant.name);
  late final _rent = TextEditingController(text: _plain(widget.tenant.rent));
  late final _deposit = TextEditingController(
    text: _plain(widget.tenant.deposit),
  );
  final _key = GlobalKey<FormState>();
  bool _dirty = false;

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  TenantRec get _t => widget.tenant;

  @override
  void dispose() {
    _rent.dispose();
    _deposit.dispose();
    super.dispose();
  }

  int get _months => ((_end.difference(_start).inDays + 1) / 30.4375).round();

  Future<void> _pickDate(bool start) async {
    final d = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (d == null) return;
    setState(() {
      if (start) {
        _start = d;
      } else {
        _end = d;
      }
      _dirty = true;
    });
  }

  void _save() {
    if (!_key.currentState!.validate()) return;
    if (!_end.isAfter(_start)) {
      toast(context, 'The end date must be after the start date.');
      return;
    }
    adminState.updateLease(
      _t,
      start: _start,
      end: _end,
      rent: double.parse(_rent.text),
      dueDay: _dueDay,
      deposit: double.parse(_deposit.text),
      chequesPerYear: _isVilla ? _cheques : null,
    );
    setState(() => _dirty = false);
    toast(context, 'Lease updated. ${_t.name} sees the new terms.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) => SubPage(
        title: 'Contract & lease',
        bottom: GoldButton(
          label: 'Save changes',
          icon: Icons.check_rounded,
          onPressed: _dirty ? _save : null,
        ),
        children: [
          // Who this is for.
          AppCard(
            radius: 20,
            child: Row(
              children: [
                const IconBadge(Icons.person_rounded, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.green800,
                        ),
                      ),
                      Text(
                        '${_t.unitLabel} · ${_t.stayType}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.slate500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Form(
            key: _key,
            onChanged: () => setState(() => _dirty = true),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Label('Lease period'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _DateField(
                              'Start date',
                              _start,
                              () => _pickDate(true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DateField(
                              'Expiration date',
                              _end,
                              () => _pickDate(false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _end.isAfter(_start) ? 'Lease term: $_months months' : 'The expiration date must be after the start date',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _end.isAfter(_start)
                              ? AppColors.slate500
                              : AppColors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const _Label('Key lease terms'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FieldLabel(
                        '${adminState.rentLabelOf(_t)} (${currencySign(_isVilla)})',
                      ),
                      TextFormField(
                        controller: _rent,
                        keyboardType: TextInputType.number,
                        validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0
                            ? 'Enter the rent'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      const FieldLabel('Rent is due on'),
                      _DueDayField(
                        day: _dueDay,
                        onChanged: (v) => setState(() {
                          _dueDay = v;
                          _dirty = true;
                        }),
                      ),
                      // Villas pay by post-dated cheques; the count is agreed
                      // with the tenant when the contract is signed.
                      if (_isVilla) ...[
                        const SizedBox(height: 12),
                        const FieldLabel('Cheques per year'),
                        SegmentedTabs(
                          light: true,
                          labels: const ['1', '2', '3', '4'],
                          index: _cheques - 1,
                          onChanged: (i) => setState(() {
                            _cheques = i + 1;
                            _dirty = true;
                          }),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Each post-dated cheque pays ${12 ~/ _cheques} months of rent.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.slate500,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      FieldLabel(
                        'Security deposit (${currencySign(_isVilla)})',
                      ),
                      TextFormField(
                        controller: _deposit,
                        keyboardType: TextInputType.number,
                        validator: (v) => (double.tryParse(v ?? '') ?? -1) < 0
                            ? 'Enter the deposit'
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const _Label('Contract file'),
          AppCard(child: _ContractFile(_t)),
          // Renewal: start the next lease from here.
          const _Label('Renewal'),
          Builder(
            builder: (context) {
              final request = adminState.renewalRequestOf(_t);
              final days = _t.daysLeft;
              return AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const IconBadge(Icons.autorenew_rounded, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                days < 0
                                    ? 'Lease ended ${_t.leaseEnd}'
                                    : 'Lease ends ${_t.leaseEnd}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.green800,
                                ),
                              ),
                              Text(
                                days < 0
                                    ? '${-days} days ago'
                                    : 'In $days days',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.slate500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (days <= adminState.renewalNoticeDays)
                          Pill.pending('DUE SOON'),
                      ],
                    ),
                    if (request != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.slate50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_t.name} asked: ${request.kind}${request.note.isEmpty ? '' : '\n"${request.note}"'}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: AppColors.green800,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (_t.nextLease case final next?)
                      // A renewal already agreed, waiting for its start date.
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.event_available_rounded,
                              color: AppColors.emerald,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Renewed: ${next.start} - ${next.end}, ${peso(next.rent, dhs: _isVilla)} a ${adminState.rentPeriodOf(_t)}. Starts by itself on ${next.start}.',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: AppColors.green800,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                final ok = await confirmAction(
                                  context,
                                  title: 'Cancel the renewal?',
                                  message:
                                      '${_t.name} will be told. The current lease still ends ${_t.leaseEnd}.',
                                  action: 'Cancel renewal',
                                );
                                if (ok) adminState.cancelScheduledRenewal(_t);
                                if (mounted) setState(() {});
                              },
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      GoldButton(
                        label: 'Renew lease',
                        icon: Icons.autorenew_rounded,
                        onPressed: _dirty
                            ? () => toast(
                                context,
                                'Save or undo your changes first.',
                              )
                            : () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => RenewLeaseScreen(_t),
                                  ),
                                );
                                if (mounted) setState(_reload);
                              },
                      ),
                    const SizedBox(height: 10),
                    // End the tenancy: inspection, deposit, close the account.
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        foregroundColor: AppColors.red,
                        side: const BorderSide(
                          color: AppColors.redBg,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _dirty
                          ? () => toast(
                              context,
                              'Save or undo your changes first.',
                            )
                          : () => push(context, MoveOutScreen(_t)),
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text(
                        'Move out',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (_t.pastLeases.isNotEmpty) ...[
            const _Label('Previous leases'),
            for (final l in _t.pastLeases)
              AppCard(
                child: Row(
                  children: [
                    const IconBadge(Icons.history_rounded, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${l.start} - ${l.end}',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.green800,
                            ),
                          ),
                          Text(
                            '${peso(l.rent, dhs: _isVilla)} a ${adminState.rentPeriodOf(_t)}'
                            '${_isVilla ? ' · ${l.chequesPerYear} cheques a year' : ''}'
                            '${l.contractName == null ? '' : ' · ${l.contractName}'}',
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
          ],
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _DateField extends StatelessWidget {
  const _DateField(this.label, this.date, this.onTap);
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.slate50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.slate200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.slate500,
                    ),
                  ),
                ),
                const Icon(
                  Icons.edit_calendar_outlined,
                  size: 15,
                  color: AppColors.gold600,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              formatDate(date),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.green800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The contract PDF: assign it, view it, replace it or remove it.
class _ContractFile extends StatelessWidget {
  const _ContractFile(this.t);
  final TenantRec t;

  Future<void> _pick(BuildContext context) async {
    final pdf = await pickPdf(context);
    if (pdf == null || !context.mounted) return;
    adminState.assignContract(t, pdf.$1, pdf.$2);
    toast(context, 'Contract assigned to ${t.name}');
  }

  @override
  Widget build(BuildContext context) {
    if (t.contractName == null) {
      return Column(
        children: [
          const Icon(
            Icons.picture_as_pdf_outlined,
            size: 38,
            color: AppColors.slate300,
          ),
          const SizedBox(height: 6),
          const Text(
            'No contract assigned yet',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: AppColors.green800,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'The tenant sees it under My Contract as soon as you add it.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.slate500),
          ),
          const SizedBox(height: 14),
          GoldButton(
            label: 'Assign contract (PDF)',
            icon: Icons.upload_file_rounded,
            onPressed: () => _pick(context),
          ),
        ],
      );
    }
    final at = t.contractAssignedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showAppSheet(
            context,
            title: 'Contract',
            builder: (_) => _ContractPreview(t),
          ),
          child: PdfTile(
            name: t.contractName!,
            size: t.contractPdf?.length ?? 0,
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.slate400,
            ),
          ),
        ),
        if (at != null) ...[
          const SizedBox(height: 8),
          Text(
            'Assigned ${formatDate(at)} · visible to ${t.name}',
            style: const TextStyle(fontSize: 12, color: AppColors.slate500),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GoldButton(
                label: 'Replace',
                icon: Icons.swap_horiz_rounded,
                compact: true,
                onPressed: () => _pick(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red,
                  side: const BorderSide(color: AppColors.red),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  adminState.removeContract(t);
                  toast(context, 'Contract removed');
                },
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text(
                  'Remove',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// What the admin sees when opening the assigned contract. (Showing the PDF
/// pages needs a PDF viewer package.)
class _ContractPreview extends StatelessWidget {
  const _ContractPreview(this.t);
  final TenantRec t;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PdfTile(name: t.contractName!, size: t.contractPdf?.length ?? 0),
        const SizedBox(height: 10),
        Container(
          height: 180,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.slate50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.slate200),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.picture_as_pdf_outlined,
                size: 36,
                color: AppColors.slate400,
              ),
              SizedBox(height: 6),
              Text(
                'Page preview',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate500,
                ),
              ),
              Text(
                'Pages of the PDF will show here',
                style: TextStyle(fontSize: 11.5, color: AppColors.slate400),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GoldButton(
          label: 'Download PDF',
          icon: Icons.download_rounded,
          onPressed: () {
            popOnce(context);
            toast(context, 'Downloading ${t.contractName}...');
          },
        ),
      ],
    );
  }
}

/// Pick the day of the month rent is due from a calendar-like grid, instead
/// of scrolling a list of 31 lines.
class _DueDayField extends StatelessWidget {
  const _DueDayField({required this.day, required this.onChanged});
  final int day;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final d = await showAppSheet<int>(
          context,
          title: 'Rent is due on',
          builder: (_) => _DayGrid(selected: day),
        );
        if (d != null) onChanged(d);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          prefixIcon: Icon(
            Icons.event_repeat_rounded,
            size: 18,
            color: AppColors.gold600,
          ),
          suffixIcon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.slate500,
          ),
        ),
        child: Text(
          '${ordinal(day)} of every month',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.green800,
          ),
        ),
      ),
    );
  }
}

class _DayGrid extends StatelessWidget {
  const _DayGrid({required this.selected});
  final int selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pick the day each month rent is due.',
          style: TextStyle(fontSize: 12.5, color: AppColors.slate500),
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (var i = 1; i <= 31; i++)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => popOnce(context, i),
                child: Ink(
                  decoration: BoxDecoration(
                    color: i == selected
                        ? AppColors.gold500
                        : AppColors.slate50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: i == selected
                          ? AppColors.gold600
                          : AppColors.slate200,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      "$i",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: i == selected
                            ? AppColors.green900
                            : AppColors.green800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (selected > 28) ...[
          const SizedBox(height: 10),
          const Text(
            'In shorter months, rent is due on the last day (Feb 28, Apr 30...).',
            style: TextStyle(fontSize: 12, color: AppColors.slate500),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Renews a lease in one step: new dates (a year from the day after the
/// current one ends), rent, cheques per year for villas, the new signed
/// contract, and the new year's cheques. The old terms are kept as history.
class RenewLeaseScreen extends StatefulWidget {
  const RenewLeaseScreen(this.tenant, {super.key});
  final TenantRec tenant;
  @override
  State<RenewLeaseScreen> createState() => _RenewLeaseScreenState();
}

class _RenewLeaseScreenState extends State<RenewLeaseScreen> {
  TenantRec get _t => widget.tenant;
  late final bool _isVilla = adminState.isVilla(_t.name);

  late DateTime _start = (parseDate(_t.leaseEnd) ?? appState.today).add(
    const Duration(days: 1),
  );
  late DateTime _end = _yearAfter(_start);
  late final _rent = TextEditingController(text: _t.rent.toStringAsFixed(0));
  late int _cheques = _t.chequesPerYear;
  bool _planCheques = true;
  String? _pdfName;
  Uint8List? _pdf;
  final _key = GlobalKey<FormState>();

  /// The day before the same date next year (Nov 15 -> Nov 14).
  static DateTime _yearAfter(DateTime d) =>
      dueDateIn(d.year + 1, d.month, d.day).subtract(const Duration(days: 1));

  @override
  void dispose() {
    _rent.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool start) async {
    final d = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2024),
      lastDate: DateTime(2040),
    );
    if (d == null) return;
    setState(() {
      if (start) {
        _start = d;
        _end = _yearAfter(d);
      } else {
        _end = d;
      }
    });
  }

  Future<void> _pickContract() async {
    final pdf = await pickPdf(context);
    if (pdf == null || !mounted) return;
    setState(() {
      _pdfName = pdf.$1;
      _pdf = pdf.$2;
    });
  }

  void _renew() {
    if (!_key.currentState!.validate()) return;
    if (!_end.isAfter(_start)) {
      toast(context, 'The end date must be after the start date.');
      return;
    }
    adminState.renewLease(
      _t,
      start: _start,
      end: _end,
      rent: double.parse(_rent.text),
      chequesPerYear: _isVilla ? _cheques : null,
      contractName: _pdfName,
      contractPdf: _pdf,
      planNewCheques: _isVilla && _planCheques,
    );
    popOnce(context);
    toast(
      context,
      _t.nextLease != null
          ? 'Renewal saved. It starts on ${formatDate(_start)}; ${_t.name} has been told.'
          : 'Lease renewed. ${_t.name} has been told.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final rent = double.tryParse(_rent.text) ?? 0;
    final months = 12 ~/ _cheques;
    return SubPage(
      title: 'Renew lease',
      bottom: GoldButton(
        label: 'Renew lease',
        icon: Icons.check_rounded,
        onPressed: _renew,
      ),
      children: [
        // What is being replaced.
        AppCard(
          radius: 20,
          child: Row(
            children: [
              const IconBadge(Icons.history_rounded, size: 42),
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
                      'Current lease: ${_t.leaseStart} - ${_t.leaseEnd}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.slate500,
                      ),
                    ),
                    Text(
                      '${peso(_t.rent, dhs: _isVilla)} a ${adminState.rentPeriodOf(_t)}',
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
        Form(
          key: _key,
          onChanged: () => setState(() {}),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Label('New lease period'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _DateField(
                            'Start date',
                            _start,
                            () => _pickDate(true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DateField(
                            'Expiration date',
                            _end,
                            () => _pickDate(false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (_) {
                        // Warn when the new lease leaves a gap or overlaps the
                        // current one, and say when it takes effect.
                        final end = parseDate(_t.leaseEnd);
                        final gap = end == null
                            ? 0
                            : _start.difference(end).inDays - 1;
                        final today = DateTime(
                          appState.today.year,
                          appState.today.month,
                          appState.today.day,
                        );
                        final later = _start.isAfter(today);
                        final (text, warn) = gap > 0
                            ? (
                                '$gap ${gap == 1 ? 'day' : 'days'} between the leases with no lease. Is that right?',
                                true,
                              )
                            : gap < 0
                            ? (
                                'Overlaps the current lease by ${-gap} ${gap == -1 ? 'day' : 'days'}: the new lease will replace it from ${formatDate(_start)}.',
                                true,
                              )
                            : (
                                'Starts the day after the current lease ends.',
                                false,
                              );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  warn
                                      ? Icons.warning_amber_rounded
                                      : Icons.check_circle_outline_rounded,
                                  size: 16,
                                  color: warn
                                      ? AppColors.amber
                                      : AppColors.emerald,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    text,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.35,
                                      color: warn
                                          ? AppColors.amber
                                          : AppColors.slate500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (later) ...[
                              const SizedBox(height: 6),
                              Text(
                                'The current rent and contract stay until then; the new terms start on ${formatDate(_start)} by themselves.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: AppColors.slate500,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const _Label('New terms'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FieldLabel(
                      '${adminState.rentLabelOf(_t)} (${currencySign(_isVilla)})',
                    ),
                    TextFormField(
                      controller: _rent,
                      keyboardType: TextInputType.number,
                      validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0
                          ? 'Enter the rent'
                          : null,
                    ),
                    if (rent > 0 && rent != _t.rent)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${rent > _t.rent ? 'Up' : 'Down'} ${peso((rent - _t.rent).abs(), dhs: _isVilla)} from ${peso(_t.rent, dhs: _isVilla)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.gold700,
                          ),
                        ),
                      ),
                    if (_isVilla) ...[
                      const SizedBox(height: 12),
                      const FieldLabel('Cheques per year'),
                      SegmentedTabs(
                        light: true,
                        labels: const ['1', '2', '3', '4'],
                        index: _cheques - 1,
                        onChanged: (i) => setState(() => _cheques = i + 1),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Set up the cheques now: $_cheques of ${peso(adminState.monthlyRentOf(_t, rent) * months, dhs: true)} each, the first dated ${formatDate(_start)}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                color: AppColors.green800,
                              ),
                            ),
                          ),
                          Switch(
                            value: _planCheques,
                            activeTrackColor: AppColors.gold500,
                            onChanged: (v) => setState(() => _planCheques = v),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const _Label('New signed contract'),
              AppCard(
                child: _pdf == null
                    ? InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _pickContract,
                        child: const Row(
                          children: [
                            IconBadge(Icons.upload_file_rounded, size: 44),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Add the renewed contract (PDF)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.green800,
                                    ),
                                  ),
                                  Text(
                                    'Optional now; you can add it later',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.slate500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.slate400,
                            ),
                          ],
                        ),
                      )
                    : Row(
                        children: [
                          const IconBadge(
                            Icons.picture_as_pdf_rounded,
                            size: 44,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _pdfName!,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.green800,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _pickContract,
                            child: const Text(
                              'Change',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.gold700,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 10),
              const Text(
                'The current lease and contract are kept under Previous leases. The tenant is told about the new terms.',
                style: TextStyle(fontSize: 12, color: AppColors.slate300),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
