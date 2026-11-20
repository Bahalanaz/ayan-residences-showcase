import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../admin/admin_state.dart'
    show
        ChargeRec,
        PayStatus,
        RentState,
        TenantRec,
        addMonthsToPaidUntil,
        adminState,
        dueDateIn,
        formatDate,
        monthShort,
        parseDate;
import '../state/app_state.dart';
import '../state/demo.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/export.dart' show shareReceipt;
import '../admin/screens/cheques_screen.dart' show ChequesScreen;
import 'cheque_upload_screen.dart';
import 'checkout_screen.dart';

/// Wallet accounts (GCash, Maya) get a wallet icon, everything else a bank.
IconData payAccountIcon(PayAccount a) => a.isWallet
    ? Icons.account_balance_wallet_rounded
    : Icons.account_balance_rounded;

/// Payment page: Pay Now (online), Payment Details (where to send money
/// yourself) and Payment Proof (which month, the receipt). The history of past
/// payments opens from the Monthly Rent card on Home.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  late int _tab = widget.initialTab;

  /// Which account (GCash, BDO) the tenant picked on the Details tab.
  final _method = ValueNotifier<int>(0);

  @override
  void dispose() {
    _method.dispose();
    super.dispose();
  }

  /// After paying or sending proof: show the history.
  void _openHistory() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const PaymentHistoryScreen()));

  @override
  Widget build(BuildContext context) {
    // Villa tenants pay by cheque and have their own upload screen.
    if (adminState.isVilla(appState.currentTenant)) {
      return const ChequeUploadScreen();
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.green800,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          adminState.isVilla(appState.currentTenant)
              ? 'Upload Cheques'
              : 'Payment',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListenableBuilder(
              listenable: appState,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  // Villa tenants only send proof of payment: no tabs.
                  if (adminState.isVilla(appState.currentTenant))
                    _PayNow(
                      details: false,
                      method: _method,
                      onSubmitted: _openHistory,
                    )
                  else ...[
                    SegmentedTabs(
                      labels: const [
                        'Pay Now',
                        'Payment Details',
                        'Payment Proof',
                      ],
                      index: _tab,
                      onChanged: (i) => setState(() => _tab = i),
                    ),
                    const SizedBox(height: 14),
                    // All three stay alive, so a receipt picked on one tab is
                    // still there after a look at another.
                    IndexedStack(
                      index: _tab,
                      children: [
                        _PayOnline(onDone: _openHistory),
                        _PayNow(
                          details: true,
                          method: _method,
                          onSubmitted: _openHistory,
                        ),
                        _PayNow(
                          details: false,
                          method: _method,
                          onSubmitted: _openHistory,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- Pay online

/// Pay in the app through the payment gateway: pick what to pay, pick a
/// method, see the total, pay. Manual transfer + proof stays as a fallback.
class _PayOnline extends StatefulWidget {
  const _PayOnline({required this.onDone});
  final VoidCallback onDone;
  @override
  State<_PayOnline> createState() => _PayOnlineState();
}

class _PayOnlineState extends State<_PayOnline> {
  int _method = 0;
  bool _all = false;

  /// Whoever pays the gateway fee. Set false if the owner absorbs it.
  static const tenantPaysFee = true;

  Future<void> _pay(List<ChargeRec> charges, double amount, String what) async {
    final m = payMethods[_method];
    final fee = tenantPaysFee ? m.feeFor(amount) : 0.0;
    final result = await Navigator.of(context).push<CheckoutResult>(
      MaterialPageRoute(
        builder: (_) =>
            CheckoutScreen(method: m, what: what, amount: amount, fee: fee),
      ),
    );
    if (result == null || !mounted) return;
    final d = result.paidAt;
    final date =
        '${monthShort[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';
    final tenant = appState.currentTenant;
    for (final c in charges) {
      adminState.recordOnlinePayment(
        tenant,
        c.title,
        c.amount,
        '${m.name} (online)',
        result.reference,
        date,
      );
    }
    appState.recordOnlinePayment(
      title: '$what payment',
      method: m.name,
      amount: amount + fee,
      reference: result.reference,
      date: date,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PaymentSuccessScreen(
          what: what,
          method: m.name,
          amount: amount,
          fee: fee,
          result: result,
        ),
      ),
    );
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final unpaid = adminState.unpaidFor(appState.currentTenant);
    if (appState.currentRentPaid || unpaid.isEmpty) {
      return Column(
        children: [
          AppCard(
            child: Column(
              children: [
                const Icon(
                  Icons.verified_rounded,
                  size: 44,
                  color: AppColors.emerald,
                ),
                const SizedBox(height: 8),
                const Text(
                  "You're all paid up",
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Nothing is due right now. Your next rent will show here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.slate500),
                ),
                const SizedBox(height: 14),
                GoldButton(
                  label: 'View payment history',
                  onPressed: widget.onDone,
                ),
              ],
            ),
          ),
        ],
      );
    }

    final latest = unpaid.first;
    final chosen = _all ? unpaid : [latest];
    final amount = chosen.fold<double>(0, (a, c) => a + c.remaining);
    final what = _all && unpaid.length > 1
        ? 'All dues (${unpaid.length})'
        : latest.title;
    final m = payMethods[_method];
    final fee = tenantPaysFee ? m.feeFor(amount) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // What is due: a plain white card like the rest of the screen.
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Amount due',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate500,
                    ),
                  ),
                  const Spacer(),
                  if (chosen.any((c) => c.overdue)) Pill.urgent('Overdue'),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                peso(amount),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _all && unpaid.length > 1
                    ? '${unpaid.length} unpaid charges'
                    : '${latest.title} · due ${latest.due}',
                style: const TextStyle(fontSize: 13, color: AppColors.slate500),
              ),
              if (unpaid.length > 1) ...[
                const SizedBox(height: 14),
                SegmentedTabs(
                  light: true,
                  labels: ['Latest due', 'All dues (${unpaid.length})'],
                  index: _all ? 1 : 0,
                  onChanged: (i) => setState(() => _all = i == 1),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        const _SectionLabel('Pay with'),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          child: Column(
            children: [
              for (var i = 0; i < payMethods.length; i++)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  selected: i == _method,
                  selectedTileColor: AppColors.gold500.withValues(alpha: .1),
                  onTap: () => setState(() => _method = i),
                  leading: IconBadge(payMethods[i].icon, size: 40),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          payMethods[i].name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.green800,
                          ),
                        ),
                      ),
                      if (payMethods[i].recommended) ...[
                        const SizedBox(width: 6),
                        Pill.verified('LOWEST FEE'),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    payMethods[i].sub,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.slate500,
                    ),
                  ),
                  trailing: Icon(
                    i == _method
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: i == _method
                        ? AppColors.gold600
                        : AppColors.slate300,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const _SectionLabel('Summary'),
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Column(
            children: [
              KeyValueRow(what, peso(amount)),
              if (tenantPaysFee)
                KeyValueRow('Processing fee (${m.name})', peso(fee)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.green800,
                        ),
                      ),
                    ),
                    Text(
                      peso(amount + fee),
                      style: const TextStyle(
                        fontSize: 18,
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
        const SizedBox(height: 18),
        GoldButton(
          label: 'Pay ${peso(amount + fee)}',
          icon: Icons.lock_rounded,
          onPressed: () => _pay(chosen, amount, what),
        ),
        const SizedBox(height: 10),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 14,
              color: AppColors.slate300,
            ),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Secured by Xendit · confirmed instantly',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.slate300),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------- Manual transfer + proof

/// Paying outside the app, split over two tabs: the account details to send to
/// ([details] true) and the proof (month, receipt, reference). The chosen
/// account is shared between them through [method].
class _PayNow extends StatefulWidget {
  const _PayNow({
    required this.onSubmitted,
    required this.details,
    required this.method,
  });
  final VoidCallback onSubmitted;
  final bool details;
  final ValueNotifier<int> method;
  @override
  State<_PayNow> createState() => _PayNowState();
}

class _PayNowState extends State<_PayNow> {
  int get _method => widget.method.value;
  set _method(int v) => widget.method.value = v;

  /// The accounts management set up; the chosen one stays in range even if
  /// accounts were removed.
  List<PayAccount> get _accounts => appState.payAccounts;
  PayAccount? get _chosen => _accounts.isEmpty
      ? null
      : _accounts[_method.clamp(0, _accounts.length - 1)];
  String? _receipt;
  Uint8List? _receiptBytes;

  /// Villa tenants pay by cheque, so the proof is a photo of the cheque.
  bool get _cheque => adminState.isVilla(appState.currentTenant);
  String? _error;

  // ---- the months being paid, and what they work out to
  TenantRec? get _rec => adminState.tenants
      .where((t) => t.name == appState.currentTenant)
      .firstOrNull;

  /// The last day already paid for: the end of the latest fully paid rent
  /// month (or cleared cheques, for a villa). Nothing paid yet: the day
  /// before the lease starts, so the first month offered is the lease's
  /// first month.
  DateTime get _paidUntil {
    final r = _rec;
    final paid = r == null ? null : adminState.rentPaidUntil(r);
    if (paid != null) return paid;
    final start = parseDate(r?.leaseStart ?? '');
    if (start != null) return start.subtract(const Duration(days: 1));
    return DateTime(appState.today.year, appState.today.month, 0);
  }

  DateTime? get _leaseEnd => parseDate(_rec?.leaseEnd ?? '');

  /// How many months to offer: up to 6, and never past the lease end.
  int get _listed {
    final end = _leaseEnd;
    var n = 0;
    while (n < 6 && (end == null || !_monthStart(n).isAfter(end))) {
      n++;
    }
    return n;
  }

  /// No month left to pay: the lease is paid (or sent for) to its end.
  bool get _leasePaid => _pendingCount >= _listed;

  // One month's rent (a villa priced by the year: a twelfth of it).
  double get _rent => _rec == null ? appState.monthlyRent : adminState.monthlyRentOf(_rec!);

  static const _monthNames = [
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

  /// The tenant taps the month they are paying through; everything from the
  /// first month still to pay up to it is included. Index into the month list.
  int? _through;

  /// First day / last day of the [i]th month after what is already paid.
  DateTime _monthStart(int i) => i == 0
      ? _paidUntil.add(const Duration(days: 1))
      : addMonthsToPaidUntil(_paidUntil, i).add(const Duration(days: 1));
  /// Never past the lease end: the last month stops on the lease's last day.
  DateTime _monthEnd(int i) {
    final d = addMonthsToPaidUntil(_paidUntil, i + 1);
    final end = _leaseEnd;
    return end != null && d.isAfter(end) ? end : d;
  }

  /// Proofs this tenant already sent that are waiting for management.
  DateTime? get _pendingThrough {
    DateTime? latest;
    for (final p in adminState.payments) {
      if (p.tenant == appState.currentTenant &&
          p.status == PayStatus.submitted &&
          p.coversTo != null &&
          (latest == null || p.coversTo!.isAfter(latest))) {
        latest = p.coversTo;
      }
    }
    return latest;
  }

  /// Months (from the first) whose proof is already with management.
  int get _pendingCount {
    final pending = _pendingThrough;
    var n = 0;
    while (n < _listed && pending != null && !_monthEnd(n).isAfter(pending)) {
      n++;
    }
    return n;
  }

  /// Index of the last month included in this payment.
  int get _last =>
      (_through ?? _pendingCount).clamp(
        _pendingCount,
        _listed - 1 < _pendingCount ? _pendingCount : _listed - 1,
      );
  int get _months => _last - _pendingCount + 1;
  DateTime get _from => _monthStart(_pendingCount);
  DateTime get _to => _monthEnd(_last);
  /// Rent left out of this payment (tap the only chosen month again).
  bool _noRent = false;

  /// Months of rent in this payment (0 when only charges are paid).
  int get _rentMonths => _cheque || _noRent || _leasePaid ? 0 : _months;
  double get _total => _rent * _months;
  double get _rentTotal => _rent * _rentMonths;

  /// Charges (not monthly rent) the tenant chose to pay with this proof.
  final Set<ChargeRec> _picked = Set.identity();

  /// Open charges that are not monthly rent and not already in a proof
  /// waiting for management.
  List<ChargeRec> get _chargeOptions {
    final pending = {
      for (final p in adminState.payments)
        if (p.tenant == appState.currentTenant && p.status == PayStatus.submitted) ...p.covers,
    };
    return adminState
        .unpaidFor(appState.currentTenant)
        .where((c) => !adminState.isRentCharge(c) && !pending.contains(c))
        .toList()
      ..sort((a, b) => (parseDate(a.due) ?? DateTime(0)).compareTo(parseDate(b.due) ?? DateTime(0)));
  }

  double get _chargesTotal => _picked.fold(0.0, (n, c) => n + c.remaining);

  /// Everything in this payment: rent months and chosen charges.
  double get _grandTotal => _rentTotal + _chargesTotal;

  String _monthLabel(int i) {
    final d = _monthStart(i);
    return '${_monthNames[(d.month + (d.day > 15 ? 1 : 0) - 1) % 12]} ${d.month == 12 && d.day > 15 ? d.year + 1 : d.year}';
  }

  /// "October 2026" for one month, "October - December 2026" for several.
  String get _period {
    final a = _monthLabel(_pendingCount), b = _monthLabel(_last);
    return _months == 1 ? a : '$a - $b';
  }

  bool get _pastLease {
    final end = parseDate(_rec?.leaseEnd ?? '');
    return end != null && _to.isAfter(end);
  }

  /// The month picker and what it adds up to.
  List<Widget> _monthsCard() {
    final today = appState.today;
    final firstFree = _pendingCount;
    if (_leasePaid) {
      // Every month up to the lease end is paid or already sent.
      return [
        const _SectionLabel('Which month are you paying for?'),
        AppCard(
          child: Text(
            'Your rent is covered up to the end of your lease'
            '${_rec?.leaseEnd == null ? '' : ' (${_rec!.leaseEnd})'}. '
            'Ask management about a renewal to pay further months.',
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.slate600,
            ),
          ),
        ),
      ];
    }
    return [
      const _SectionLabel('Which month are you paying for?'),
      AppCard(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _listed; i++)
              _MonthRow(
                label: _monthLabel(i),
                dates:
                    '${formatDate(_monthStart(i))} - ${formatDate(_monthEnd(i))}',
                amount: peso(_rent),
                state: i < firstFree
                    ? _MonthState.sent
                    : _monthEnd(i).isBefore(today)
                    ? _MonthState.overdue
                    : !_monthStart(i).isAfter(today)
                    ? _MonthState.due
                    : _MonthState.upcoming,
                selected: !_noRent && i >= firstFree && i <= _last,
                onTap: i < firstFree
                    ? null
                    : () => setState(() {
                          if (!_noRent && _months == 1 && i == _last) {
                            _noRent = true; // pay only charges this time
                          } else {
                            _noRent = false;
                            _through = i;
                          }
                        }),
              ),
            const Divider(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _noRent
                              ? 'No rent in this payment'
                              : _months == 1
                                  ? _period
                                  : '$_period ($_months months)',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.slate600,
                          ),
                        ),
                      ),
                      Text(
                        peso(_rentTotal, dhs: _cheque),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.green800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _cheque
                        ? 'Upload a photo of the cheque for ${peso(_total, dhs: _cheque)} below.'
                        : _noRent
                            ? 'Tap a month to add rent again.'
                            : 'Once verified, your stay is paid until ${formatDate(_to)}.',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.slate500,
                    ),
                  ),
                  if (_pastLease)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'This goes past your lease end (${_rec?.leaseEnd}). Ask management about a renewal.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.amber,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
    ];
  }

  /// "Which charges are you paying for?": repairs, fees, utilities... The
  /// tenant ticks the ones this proof pays; the total adds up below.
  List<Widget> _chargesCard() {
    final options = _chargeOptions;
    _picked.removeWhere((c) => !options.contains(c));
    if (options.isEmpty) return const [];
    final villa = _cheque;
    return [
      const _SectionLabel('Which charges are you paying for?'),
      AppCard(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in options)
              _MonthRow(
                label: c.title,
                dates: c.partlyPaid
                    ? 'Due ${c.due} · ${peso(c.paidAmount, dhs: villa)} already paid'
                    : 'Due ${c.due}',
                amount: peso(c.remaining, dhs: villa),
                state: c.overdue
                    ? _MonthState.overdue
                    : (parseDate(c.due) ?? DateTime(9999)).isAfter(appState.today)
                        ? _MonthState.upcoming
                        : _MonthState.due,
                selected: _picked.contains(c),
                onTap: () => setState(() => _picked.contains(c) ? _picked.remove(c) : _picked.add(c)),
              ),
            const Divider(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Expanded(
                    child: Text('Total to send',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.slate600)),
                  ),
                  Text(peso(_grandTotal, dhs: villa),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.green800)),
                ]),
                const SizedBox(height: 4),
                Text(
                  _rentMonths == 0 && _picked.isEmpty
                      ? 'Tick the charges this payment is for.'
                      : [
                          if (_rentMonths > 0) '$_rentMonths ${_rentMonths == 1 ? 'month' : 'months'} of rent',
                          if (_picked.isNotEmpty) '${_picked.length} ${_picked.length == 1 ? 'charge' : 'charges'}',
                        ].join(' + '),
                  style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.slate500),
                ),
              ]),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
    ];
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        setState(() {
          _receipt = file.name;
          _receiptBytes = bytes;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) toast(context, 'Could not open your photos.');
    }
  }

  void _submit() {
    if (_receipt == null) {
      setState(
        () => _error = _cheque
            ? 'Please upload a photo of the cheque.'
            : 'Please upload your receipt.',
      );
      return;
    }
    if (_grandTotal <= 0 && !(_cheque && _picked.isEmpty)) {
      setState(() => _error = 'Choose a month or a charge to pay for.');
      return;
    }
    // Villa: the photo goes on the cheque itself, for management to verify
    // (unless they are paying charges, which is a normal payment proof).
    if (_cheque && _picked.isEmpty) {
      final c = adminState.uploadChequePhoto(
        appState.currentTenant,
        _receiptBytes ?? Uint8List(0),
      );
      setState(() {
        _receipt = null;
        _receiptBytes = null;
        _error = null;
      });
      toast(
        context,
        'Cheque photo sent (${formatDate(c.date)}). Management will verify it.',
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ChequesScreen(appState.currentTenant),
        ),
      );
      return;
    }
    final charges = _picked.toList();
    final what = [
      if (_rentMonths > 0) _period,
      if (charges.length == 1) charges.first.title,
      if (charges.length > 1) '${charges.length} charges',
    ].join(' + ');
    appState.submitPayment(
      method: _chosen?.name ?? 'Transfer',
      amount: _grandTotal,
      reference: '',
      months: _rentMonths,
      from: _rentMonths > 0 ? _from : null,
      to: _rentMonths > 0 ? _to : null,
      period: _period,
      proof: _receiptBytes,
      charges: charges,
      title: _rentMonths > 0 && charges.isEmpty ? null : '$what payment',
    );
    _picked.clear();
    _noRent = false;
    setState(() {
      _receipt = null;
      _receiptBytes = null;
      _error = null;
    });
    toast(context, 'Proof sent for $what. Management will verify it.');
    widget.onSubmitted();
  }

  @override
  Widget build(BuildContext context) {
    final m = _chosen;
    Widget copyRow(String label, String value, String copy) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.slate500,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: copy));
              toast(context, 'Copied $value');
            },
            icon: const Icon(
              Icons.copy_rounded,
              size: 18,
              color: AppColors.gold600,
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Same look as Pay Now: white cards, section labels, one gold button.
        if (!widget.details && !_cheque) ..._monthsCard(),
        if (!widget.details) ..._chargesCard(),
        if (widget.details && m == null)
          const EmptyState(
            icon: Icons.account_balance_outlined,
            title: 'No payment accounts yet',
            message: 'Management has not added an account to send to. Use Pay Now to pay in the app.',
          ),
        if (widget.details && m != null) ...[
          const _SectionLabel('Send to'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Column(
              children: [
                for (var i = 0; i < _accounts.length; i++)
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    selected: _accounts[i] == m,
                    selectedTileColor: AppColors.gold500.withValues(alpha: .1),
                    onTap: () => setState(() => _method = i),
                    leading: IconBadge(payAccountIcon(_accounts[i]), size: 40),
                    title: Text(
                      _accounts[i].name,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green800,
                      ),
                    ),
                    subtitle: Text(
                      _accounts[i].accountName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.slate500,
                      ),
                    ),
                    trailing: Icon(
                      _accounts[i] == m
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: _accounts[i] == m
                          ? AppColors.gold600
                          : AppColors.slate300,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _SectionLabel('Account details'),
          AppCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Column(
              children: [
                copyRow('Account name', m.accountName, m.accountName),
                const Divider(height: 8),
                copyRow(m.numberLabel, m.number, m.copyText),
              ],
            ),
          ),
          // The account's QR code, when management added one: scan it from
          // another phone, or open it big and screenshot it.
          if (m.qr != null) ...[
            const SizedBox(height: 18),
            const _SectionLabel('Scan to pay'),
            AppCard(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(
                        backgroundColor: Colors.white,
                        insetPadding: const EdgeInsets.all(16),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: InteractiveViewer(
                            maxScale: 4,
                            child: Image.memory(m.qr!),
                          ),
                        ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        m.qr!,
                        height: 220,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.qr_code_2_rounded,
                          size: 120,
                          color: AppColors.gold600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${m.name} QR · tap to enlarge',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.slate500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
        if (!widget.details) ...[
          if (_cheque) ...[
            const _SectionLabel('Which cheque'),
            Builder(
              builder: (context) {
                final c = adminState.chequeAwaitingPhoto(
                  appState.currentTenant,
                );
                return AppCard(
                  child: Row(
                    children: [
                      const IconBadge(Icons.payments_outlined, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c == null
                                  ? 'A new cheque'
                                  : peso(c.amount, dhs: true),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.green800,
                              ),
                            ),
                            Text(
                              c == null
                                  ? 'Management will fill in the details.'
                                  : 'Post-dated cheque · banks on ${formatDate(c.date)}',
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
                );
              },
            ),
            const SizedBox(height: 18),
          ],
          const _SectionLabel('Your proof'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _pickReceipt,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.slate50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.slate200),
                    ),
                    child: Row(
                      children: [
                        _receipt == null
                            ? const IconBadge(
                                Icons.upload_file_rounded,
                                size: 44,
                              )
                            : IconBadge(
                                Icons.check_rounded,
                                size: 44,
                                fg: AppColors.emerald,
                                bg: AppColors.emerald.withValues(alpha: .12),
                              ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _receipt ??
                                    (_cheque
                                        ? 'Upload your cheque'
                                        : 'Upload your receipt'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.green800,
                                ),
                              ),
                              Text(
                                _receipt == null
                                    ? 'JPG, PNG or PDF · max 5 MB'
                                    : 'Tap to change',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.slate500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.slate400,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.red,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          GoldButton(
            label: 'Submit proof',
            icon: Icons.send_rounded,
            onPressed: _submit,
          ),
          const SizedBox(height: 10),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.schedule_rounded, size: 14, color: AppColors.slate300),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Management checks it before it counts as paid',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.slate300),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

enum _MonthState { sent, overdue, due, upcoming }

/// One month in the picker: tap to pay through this month. Months whose proof
/// was already sent are shown but can't be picked again.
class _MonthRow extends StatelessWidget {
  const _MonthRow({
    required this.label,
    required this.dates,
    required this.amount,
    required this.state,
    required this.selected,
    required this.onTap,
  });
  final String label, dates, amount;
  final _MonthState state;

  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sent = state == _MonthState.sent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: PressScale(
        enabled: !sent,
        scale: .985,
        child: Material(
          color: selected
              ? AppColors.gold500.withValues(alpha: .14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? AppColors.gold500 : AppColors.slate200,
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    sent
                        ? Icons.schedule_rounded
                        : selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 22,
                    color: sent
                        ? AppColors.slate400
                        : selected
                        ? AppColors.gold600
                        : AppColors.slate300,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: sent
                                ? AppColors.slate400
                                : AppColors.green800,
                          ),
                        ),
                        Text(
                          dates,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.slate500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        amount,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: sent ? AppColors.slate400 : AppColors.green800,
                        ),
                      ),
                      if (state != _MonthState.upcoming) ...[
                        const SizedBox(height: 4),
                        switch (state) {
                          _MonthState.sent => Pill.info('PROOF SENT'),
                          _MonthState.overdue => Pill.urgent('OVERDUE'),
                          _ => Pill.pending('DUE'),
                        },
                      ],
                    ],
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 2),
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

// ---------------------------------------------------------------- History

/// Past payments and this month's billing. Opens from the Monthly Rent card.
class PaymentHistoryScreen extends StatelessWidget {
  const PaymentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.green800,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Payment History',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListenableBuilder(
              listenable: appState,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: const [_History()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History();

  @override
  Widget build(BuildContext context) {
    final s = appState;
    return LoadingSwitch(skeleton: const SkeletonCards(), child: _content(s));
  }

  Widget _content(AppState s) {
    const months = [
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
    final t = s.today;
    final villa = adminState.isVilla(appState.currentTenant);
    final tenant = adminState.tenants
        .where((x) => x.name == s.currentTenant)
        .firstOrNull;
    final due = dueDateIn(t.year, t.month, tenant?.dueDay ?? 5);
    // This month's share of the rent (a villa priced by the year: a twelfth).
    final monthly = tenant == null ? s.monthlyRent : adminState.monthlyRentOf(tenant);
    // No unit yet: no billing to show.
    final hasUnit = demoData || (tenant != null && tenant.unit.isNotEmpty);
    return Column(
      children: [
        if (!hasUnit)
          const AppCard(
            child: Text(
              'No unit assigned yet. Your monthly billing will show here once management assigns your unit.',
              style: TextStyle(fontSize: 13, color: AppColors.slate500),
            ),
          ),
        if (hasUnit)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${months[t.month - 1]} ${t.year} Billing',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.slate500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      peso(monthly, dhs: villa),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green800,
                      ),
                    ),
                    switch (adminState.rentStateOf(s.currentTenant)) {
                      RentState.paid => Pill.verified('Paid'),
                      RentState.awaiting => Pill.info('Proof submitted'),
                      RentState.due => Pill.pending(
                        'Due ${months[due.month - 1].substring(0, 3)} ${due.day}',
                      ),
                    },
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.slate50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        '${adminState.rentPeriodOf(tenant) == 'month' ? 'Base Rent' : 'Monthly share'}: ${peso(monthly, dhs: villa)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.slate600,
                        ),
                      ),
                      const Text(
                        'Water/Elec: Billed Separate',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.slate600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Transaction History',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < s.payments.length; i++)
                _PaymentRow(s.payments[i], last: i == s.payments.length - 1),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _Channels(),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow(this.p, {required this.last});
  final Payment p;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final ok = p.status == PaymentStatus.verified;
    return Container(
      padding: EdgeInsets.only(bottom: last ? 0 : 12, top: 0),
      margin: EdgeInsets.only(bottom: last ? 0 : 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.slate100)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: ok ? AppColors.emeraldBg : AppColors.amberBg,
            child: Icon(
              ok ? Icons.check : Icons.schedule,
              size: 16,
              color: ok ? AppColors.emerald : AppColors.amber,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
                Text(
                  '${p.date} • ${p.method}${p.reference.isEmpty ? '' : ' (Ref #${p.reference})'}',
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
                peso(p.amount, dhs: adminState.isVilla(appState.currentTenant)),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
              Text(
                ok ? 'Verified' : 'Pending review',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ok ? AppColors.emerald : AppColors.amber,
                ),
              ),
            ],
          ),
          // A verified payment has a receipt to save or send.
          if (ok)
            IconButton(
              tooltip: 'Receipt',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.receipt_long_rounded,
                color: AppColors.gold700,
                size: 20,
              ),
              onPressed: () async {
                try {
                  await shareReceipt(
                    receiptNo:
                        'AR-${(p.reference.replaceAll(RegExp(r'\D'), '') + p.date.replaceAll(RegExp(r'\D'), '')).padLeft(6, '0').substring(0, 6)}',
                    tenant: appState.currentTenant,
                    unit: appState.unit,
                    title: p.title,
                    method: p.method,
                    reference: p.reference.isEmpty ? '-' : p.reference,
                    date: p.date,
                    amount: p.amount,
                    aed: adminState.isVilla(appState.currentTenant),
                  );
                } catch (e) {
                  if (context.mounted) {
                    toast(context, "Couldn't make the receipt. Please try again.");
                  }
                }
              },
            ),
        ],
      ),
    );
  }
}

class _Channels extends StatelessWidget {
  const _Channels();

  // Listens itself: as a const widget it is not rebuilt with the screen, so
  // accounts the admin adds would only show after leaving the screen.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: appState,
        builder: (context, _) => _content(context),
      );

  Widget _content(BuildContext context) {
    Widget row(String title, String sub, String value, String copy) =>
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.green800,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.slate600.withValues(alpha: .5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                    Text(
                      sub,
                      style: const TextStyle(
                        color: AppColors.slate300,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: AppColors.gold400,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.copy_rounded,
                  size: 16,
                  color: AppColors.slate300,
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: copy));
                  toast(context, 'Copied $copy');
                },
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.green700.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.slate600.withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: AppColors.gold400),
              SizedBox(width: 6),
              Text(
                'OFFICIAL PAYMENT CHANNELS',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: .6,
                  fontWeight: FontWeight.w800,
                  color: AppColors.gold400,
                ),
              ),
            ],
          ),
          for (final a in appState.payAccounts)
            row(
              a.isWallet ? '${a.name} Account' : a.name,
              a.accountName,
              a.number,
              a.copyText,
            ),
          const SizedBox(height: 10),
          const Text(
            'Always include your unit number in the transfer note, then upload the receipt here so management can verify it.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.slate300,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
