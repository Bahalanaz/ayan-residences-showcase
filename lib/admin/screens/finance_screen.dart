import 'package:flutter/material.dart';

import '../../screens/shell.dart' show TabBody;
import '../../state/app_state.dart' show appState;
import '../../theme.dart';
import '../../widgets/common.dart';

import 'package:printing/printing.dart';

import '../admin_state.dart';
import '../../widgets/signed_document.dart' show showPdf;
import 'finance_report.dart';

const _monthNames = [
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

/// The money for a period (any start and end day, both included) across
/// every property. Pesos (apartments, condos) and dirhams (villas) are kept
/// apart: they are never added together.
class _Period {
  _Period(DateTime from, DateTime to)
    : start = DateTime(from.year, from.month, from.day),
      end = DateTime(to.year, to.month, to.day) {
    final s = adminState;
    bool inside(DateTime? d) {
      if (d == null) return false;
      final day = DateTime(d.year, d.month, d.day);
      return !day.isBefore(start) && !day.isAfter(end);
    }

    // Apartment payments verified in the period (rent and other charges).
    for (final p in s.payments) {
      if (p.status != PayStatus.verified || !inside(parseDate(p.date))) {
        continue;
      }
      if (s.isVilla(p.tenant)) {
        // Villa rent comes from cleared cheques (counted below); other
        // verified villa payments (repairs charged to the tenant) count here.
        if (!p.method.startsWith('Cheque')) villaIncome += p.amount;
        continue;
      }
      apartmentIncome += p.amount;
      if (p.method.toLowerCase().contains('online')) onlinePayments += p.amount;
    }
    // Villa cheques that cleared in the period (by their date).
    for (final c in s.cheques.where(
      (c) => c.kind == ChequeKind.postDated && inside(c.date),
    )) {
      if (c.status == ChequeStatus.cleared) villaIncome += c.amount;
      if (c.status == ChequeStatus.bounced) bounced++;
    }
    // Condos: stays (by check-in), damage taken off deposits, running costs,
    // and how many nights were booked or free.
    for (final u in s.units.where((u) => u.type == 'Condo')) {
      final stays = s.bookingsFor(u.name);
      final income = stays
          .where((b) => inside(b.checkIn))
          .fold(0.0, (n, b) => n + b.amount);
      final cost = s
          .costsFor(u.name)
          .where((c) => inside(c.date))
          .fold(0.0, (n, c) => n + c.amount);
      final damage = [
        for (final b in stays)
          for (final d in b.deductions)
            if (inside(d.date)) d.amount,
      ].fold(0.0, (n, a) => n + a);
      condoIncome += income;
      condoCosts += cost;
      damageRecovered += damage;
      perUnit.add((u, income + damage, cost));
      this.stays += stays.where((b) => inside(b.checkIn)).length;

      // A night is booked when it falls between a stay's check-in day and
      // the day before its check-out.
      var booked = 0;
      for (
        var d = start;
        !d.isAfter(end);
        d = DateTime(d.year, d.month, d.day + 1)
      ) {
        if (stays.any(
          (b) =>
              !DateTime(
                b.checkIn.year,
                b.checkIn.month,
                b.checkIn.day,
              ).isAfter(d) &&
              DateTime(
                b.checkOut.year,
                b.checkOut.month,
                b.checkOut.day,
              ).isAfter(d),
        )) {
          booked++;
        }
      }
      usage.add((
        unit: u,
        stays: stays
            .where(
              (b) =>
                  b.checkIn.isBefore(end.add(const Duration(days: 1))) &&
                  b.checkOut.isAfter(start),
            )
            .length,
        booked: booked,
        free: days - booked,
      ));
    }
    // Apartments: a day is occupied when a lease on the unit (the tenant's
    // current one or an earlier one) covers it.
    for (final u in s.units.where(
      (u) => u.type == 'Apartment' || u.type == 'Villa',
    )) {
      final leases = <(DateTime, DateTime)>[
        for (final t in s.tenants.where((t) => t.unit == u.name)) ...[
          if (parseDate(t.leaseStart) != null && parseDate(t.leaseEnd) != null)
            (parseDate(t.leaseStart)!, parseDate(t.leaseEnd)!),
          for (final p in t.pastLeases)
            if (parseDate(p.start) != null && parseDate(p.end) != null)
              (parseDate(p.start)!, parseDate(p.end)!),
        ],
      ];
      var occupied = 0;
      for (
        var d = start;
        !d.isAfter(end);
        d = DateTime(d.year, d.month, d.day + 1)
      ) {
        if (leases.any((l) => !l.$1.isAfter(d) && !l.$2.isBefore(d))) {
          occupied++;
        }
      }
      aptUsage.add((
        unit: u,
        leases: leases
            .where((l) => !l.$1.isAfter(end) && !l.$2.isBefore(start))
            .length,
        occupied: occupied,
        vacant: days - occupied,
      ));
    }
    for (final u in s.units.where((u) => u.type != 'Condo')) {
      final income = u.type == 'Villa'
          ? s.cheques
                .where(
                  (c) =>
                      c.status == ChequeStatus.cleared &&
                      c.kind == ChequeKind.postDated &&
                      inside(c.date) &&
                      s.tenants.any(
                        (t) => t.name == c.tenant && t.unit == u.name,
                      ),
                )
                .fold(0.0, (n, c) => n + c.amount)
          : s.payments
                .where(
                  (p) =>
                      p.status == PayStatus.verified &&
                      p.unit == u.name &&
                      inside(parseDate(p.date)),
                )
                .fold(0.0, (n, p) => n + p.amount);
      perUnit.add((u, income, 0));
    }
    // Payment gateway fees: an estimate on online payments.
    gatewayFees = onlinePayments * feeRate;
    // Repairs and maintenance with a cost entered on the schedule.
    workPeso = s.workCostIn(start, end, villas: false);
    // Each unit's recurring monthly expenses (internet, Netflix...).
    monthlyPeso = s.monthlyExpensesIn(start, end, villas: false);
    monthlyAed = s.monthlyExpensesIn(start, end, villas: true);
    // Of those jobs, what tenants were asked to pay and what they have paid
    // (the paid part is already in income through the verified payment).
    for (final w in s.workItems.where(
      (w) => w.tenantPays && w.chargeRec != null && inside(w.date),
    )) {
      if (s.isVillaUnit(w.where)) continue;
      workCharged += w.charge;
      workChargePaid += w.chargeRec!.paid
          ? w.chargeRec!.amount
          : w.chargeRec!.paidAmount;
    }
    workAed = s.workCostIn(start, end, villas: true);
    // Taxes at the rates the admin set, on the period's income; a fixed
    // monthly tax counts for the share of each month in the period.
    for (final t in s.taxes) {
      final amount = t.isFixed
          ? t.fixedMonthly * months
          : (t.onVillas ? villaIncome : pesoIncome) * t.percent / 100;
      taxLines.add((tax: t, amount: amount));
      if (t.onVillas) {
        taxAed += amount;
      } else {
        taxPeso += amount;
      }
    }
  }

  final DateTime start, end;

  /// Days in the period, both ends included.
  int get days => end.difference(start).inDays + 1;

  /// The period just before this one, of the same length (for comparing).
  _Period get previous => _Period(
    start.subtract(Duration(days: days)),
    start.subtract(const Duration(days: 1)),
  );

  /// Months in the period, counting part months by their days (October = 1,
  /// a whole year = 12, Oct 16-31 = about 0.52).
  double get months {
    var total = 0.0;
    var m = DateTime(start.year, start.month);
    while (!m.isAfter(end)) {
      final last = DateTime(m.year, m.month + 1, 0);
      final from = start.isAfter(m) ? start : m;
      final to = end.isBefore(last) ? end : last;
      total += (to.difference(from).inDays + 1) / last.day;
      m = DateTime(m.year, m.month + 1);
    }
    return total;
  }

  /// The share the payment gateway keeps on online payments (set in Fees).
  static double get feeRate => adminState.gatewayFeePercent / 100;

  /// Repair and maintenance costs from the schedule.
  double workPeso = 0, workAed = 0;

  /// Units' recurring monthly expenses in the period.
  double monthlyPeso = 0, monthlyAed = 0;

  /// Work charged to tenants in the period (pesos), and how much is paid.
  double workCharged = 0, workChargePaid = 0;

  double apartmentIncome = 0,
      condoIncome = 0,
      damageRecovered = 0,
      condoCosts = 0;
  double onlinePayments = 0, gatewayFees = 0;
  double villaIncome = 0; // AED
  int bounced = 0, stays = 0;
  final List<(UnitRec, double income, double cost)> perUnit = [];

  /// Per condo: stays touching the period, nights booked, nights free.
  final List<({UnitRec unit, int stays, int booked, int free})> usage = [];

  /// Per apartment and villa: leases touching the period, days occupied,
  /// days vacant.
  final List<({UnitRec unit, int leases, int occupied, int vacant})> aptUsage =
      [];

  double get pesoIncome => apartmentIncome + condoIncome + damageRecovered;
  double get pesoCosts => condoCosts + workPeso + monthlyPeso + gatewayFees;

  /// Taxes owed on the period's income, at the rates set.
  final List<({TaxRate tax, double amount})> taxLines = [];
  double taxPeso = 0, taxAed = 0;

  /// Profit after costs, fees and taxes.
  double get pesoNet => pesoIncome - pesoCosts - taxPeso;
  double get villaNet => villaIncome - workAed - monthlyAed - taxAed;
}

/// The money overview: profit for a chosen month, where it came from, what
/// it cost, what is still owed and what is held as deposits.
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});
  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  /// Month, Year or Custom (any start and end date).
  int _mode = 0;
  DateTime _month = DateTime(appState.today.year, appState.today.month);
  int _year = appState.today.year;
  late DateTimeRange _custom = DateTimeRange(
    start: DateTime(appState.today.year, appState.today.month, 1),
    end: appState.today,
  );

  _Period get _period => switch (_mode) {
    0 => _Period(_month, DateTime(_month.year, _month.month + 1, 0)),
    1 => _Period(DateTime(_year), DateTime(_year, 12, 31)),
    _ => _Period(_custom.start, _custom.end),
  };

  /// "October 2026", "2026" or "Oct 3 - Nov 12, 2026".
  String get _label => switch (_mode) {
    0 => '${_monthNames[_month.month - 1]} ${_month.year}',
    1 => '$_year',
    _ => _rangeText(_custom.start, _custom.end),
  };

  /// The period before, written like the period ("September 2026", "2025"...).
  String get _previousLabel => switch (_mode) {
    0 => () {
      final p = DateTime(_month.year, _month.month - 1);
      return '${_monthNames[p.month - 1]} ${p.year}';
    }(),
    1 => '${_year - 1}',
    _ => () {
      final p = _period.previous;
      return _rangeText(p.start, p.end);
    }(),
  };

  /// The finance report as an income statement (this period against the
  /// one before), then either shown on screen ([view]) or shared (save,
  /// print, send by WhatsApp or email).
  Future<void> _reportPdf({
    required _Period m,
    required double? change,
    required double owed,
    required int unpaidCount,
    required double owedOverdue,
    required int overdueCount,
    required double chequesSoon,
    required double staysSoon,
    required double aptDeposits,
    required double villaDeposits,
    required double condoDeposits,
    required int occupied,
    required int units,
    bool view = false,
  }) async {
    final p = m.previous;
    final t = appState.today;
    final hasVillas = adminState.units.any((u) => u.type == 'Villa');
    String pct(double part, double whole) =>
        whole == 0 ? '-' : '${(part / whole * 100).toStringAsFixed(0)}%';
    double taxOf(_Period x, TaxRate tax) =>
        x.taxLines.where((l) => l.tax == tax).fold(0.0, (n, l) => n + l.amount);
    final feeLabel =
        'Payment gateway fees (${(_Period.feeRate * 100).toStringAsFixed(1)}%)';
    String taxLabel(TaxRate tax) => tax.isFixed
        ? '${tax.name} (${pdfMoney(tax.fixedMonthly, aed: tax.onVillas)} a month)'
        : '${tax.name} (${_pct(tax.percent)})';

    try {
      final bytes = await buildFinancePdf(
        period: _label,
        previousPeriod: _previousLabel,
        generatedOn:
            '${_monthNames[t.month - 1].substring(0, 3)} ${t.day}, ${t.year}',
        netPeso: pdfMoney(m.pesoNet),
        netVillas: pdfMoney(m.villaNet, aed: true),
        comparison: change == null
            ? 'No peso revenue in the period before to compare.'
            : '${change >= 0 ? '+' : ''}${(change * 100).toStringAsFixed(0)}% vs $_previousLabel',
        statements: [
          (
            title: 'Apartments and condos',
            currency: 'Philippine pesos (PHP)',
            lines: [
              heading('Revenue'),
              line(
                'Apartment rent and charges',
                m.apartmentIncome,
                p.apartmentIncome,
              ),
              line('Condo stays', m.condoIncome, p.condoIncome),
              line(
                'Damage deducted from deposits',
                m.damageRecovered,
                p.damageRecovered,
              ),
              subtotal('Total revenue', m.pesoIncome, p.pesoIncome),
              heading('Expenses'),
              line(
                'Condo running costs',
                m.condoCosts,
                p.condoCosts,
                cost: true,
              ),
              line(
                'Repairs and maintenance',
                m.workPeso,
                p.workPeso,
                cost: true,
              ),
              line(
                'Monthly unit expenses',
                m.monthlyPeso,
                p.monthlyPeso,
                cost: true,
              ),
              line(feeLabel, m.gatewayFees, p.gatewayFees, cost: true),
              subtotal('Total expenses', m.pesoCosts, p.pesoCosts, cost: true),
              if (adminState.taxes.any((x) => !x.onVillas)) ...[
                heading('Taxes'),
                for (final tax in adminState.taxes.where((x) => !x.onVillas))
                  line(taxLabel(tax), taxOf(m, tax), taxOf(p, tax), cost: true),
                subtotal('Total taxes', m.taxPeso, p.taxPeso, cost: true),
              ],
              total('Net profit', m.pesoNet, p.pesoNet),
            ],
          ),
          if (hasVillas || m.villaIncome != 0 || p.villaIncome != 0)
            (
              title: 'Villas',
              currency: 'UAE dirhams (AED)',
              lines: [
                heading('Revenue'),
                line(
                  'Rent cheques cleared and other payments',
                  m.villaIncome,
                  p.villaIncome,
                ),
                subtotal('Total revenue', m.villaIncome, p.villaIncome),
                heading('Expenses'),
                line(
                  'Repairs and maintenance',
                  m.workAed,
                  p.workAed,
                  cost: true,
                ),
                line(
                  'Monthly unit expenses',
                  m.monthlyAed,
                  p.monthlyAed,
                  cost: true,
                ),
                subtotal(
                  'Total expenses',
                  m.workAed + m.monthlyAed,
                  p.workAed + p.monthlyAed,
                  cost: true,
                ),
                if (adminState.taxes.any((x) => x.onVillas)) ...[
                  heading('Taxes'),
                  for (final tax in adminState.taxes.where((x) => x.onVillas))
                    line(
                      taxLabel(tax),
                      taxOf(m, tax),
                      taxOf(p, tax),
                      cost: true,
                    ),
                  subtotal('Total taxes', m.taxAed, p.taxAed, cost: true),
                ],
                total('Net profit', m.villaNet, p.villaNet),
              ],
            ),
        ],
        ratios: [
          (
            label: 'Expenses / revenue (pesos)',
            now: pct(m.pesoCosts, m.pesoIncome),
            before: pct(p.pesoCosts, p.pesoIncome),
          ),
          (
            label: 'Taxes / revenue (pesos)',
            now: pct(m.taxPeso, m.pesoIncome),
            before: pct(p.taxPeso, p.pesoIncome),
          ),
          (
            label: 'Net margin (pesos)',
            now: pct(m.pesoNet, m.pesoIncome),
            before: pct(p.pesoNet, p.pesoIncome),
          ),
          if (hasVillas)
            (
              label: 'Net margin (villas)',
              now: pct(m.villaNet, m.villaIncome),
              before: pct(p.villaNet, p.villaIncome),
            ),
          (label: 'Condo stays', now: '${m.stays}', before: '${p.stays}'),
          (
            label: 'Bounced cheques',
            now: '${m.bounced}',
            before: '${p.bounced}',
          ),
        ],
        tables: [
          (
            title: 'Owed and coming up',
            columns: ['', 'Amount'],
            rows: [
              ['Unpaid charges ($unpaidCount)', pdfMoney(owed)],
              ['Overdue ($overdueCount)', pdfMoney(owedOverdue)],
              if (hasVillas)
                [
                  'Villa cheques due in the next 30 days',
                  pdfMoney(chequesSoon, aed: true),
                ],
              ['Condo stays booked in the next 30 days', pdfMoney(staysSoon)],
            ],
          ),
          (
            title: 'Deposits held',
            columns: ['', 'Amount'],
            rows: [
              ['Apartment security deposits', pdfMoney(aptDeposits)],
              if (hasVillas)
                ['Villa deposit cheques', pdfMoney(villaDeposits, aed: true)],
              ['Condo guests staying now', pdfMoney(condoDeposits)],
            ],
          ),
          (
            title: 'Occupancy ($occupied of $units units occupied now)',
            columns: [
              'Unit',
              'Stays / leases',
              'Days used',
              'Days free',
              'Used',
            ],
            rows: [
              for (final c in m.usage)
                [
                  '${c.unit.name} (Condo)',
                  '${c.stays}',
                  '${c.booked}',
                  '${c.free}',
                  '${m.days == 0 ? 0 : (c.booked * 100 / m.days).round()}%',
                ],
              for (final a in m.aptUsage)
                [
                  '${a.unit.name} (${a.unit.type})',
                  '${a.leases}',
                  '${a.occupied}',
                  '${a.vacant}',
                  '${m.days == 0 ? 0 : (a.occupied * 100 / m.days).round()}%',
                ],
            ],
          ),
          (
            title: 'By unit',
            columns: ['Unit', 'Revenue', 'Costs', 'Net'],
            rows: [
              for (final (u, income, cost) in m.perUnit)
                [
                  '${u.name} (${u.type})',
                  pdfMoney(income, aed: u.type == 'Villa'),
                  cost > 0 ? pdfMoney(-cost, aed: u.type == 'Villa') : '-',
                  pdfMoney(income - cost, aed: u.type == 'Villa'),
                ],
            ],
          ),
        ],
      );
      final name =
          'Ayan financial report ${_label.replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ').trim()}';
      if (view) {
        if (mounted) showPdf(context, bytes, name);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: '$name.pdf');
      }
    } catch (e) {
      if (mounted) toast(context, "Couldn't make the PDF. Please try again.");
    }
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(2035),
      initialDateRange: _custom,
      helpText: 'Choose the dates',
      // The app's look: dark-green header, cream calendar, gold selection.
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          scaffoldBackgroundColor: AppColors.slate50,
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppColors.green800,
            onPrimary: Colors.white,
            secondary: AppColors.gold500,
            surface: AppColors.slate50,
            onSurface: AppColors.green800,
            onSurfaceVariant: AppColors.gold700,
            primaryContainer: AppColors.gold500,
            onPrimaryContainer: AppColors.green900,
            secondaryContainer: AppColors.gold500.withValues(alpha: .25),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.green800,
            foregroundColor: Colors.white,
            iconTheme: IconThemeData(color: Colors.white),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.gold400,
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          datePickerTheme: DatePickerThemeData(
            backgroundColor: AppColors.slate50,
            rangePickerBackgroundColor: AppColors.slate50,
            rangePickerHeaderBackgroundColor: AppColors.green800,
            rangePickerHeaderForegroundColor: Colors.white,
            rangePickerHeaderHelpStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.gold400,
            ),
            rangePickerHeaderHeadlineStyle: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
            headerBackgroundColor: AppColors.green800,
            headerForegroundColor: Colors.white,
            dividerColor: AppColors.gold500,
            weekdayStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.gold700,
            ),
            dayStyle: const TextStyle(fontWeight: FontWeight.w700),
            dayForegroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? AppColors.green900
                  : s.contains(WidgetState.disabled)
                  ? AppColors.slate300
                  : AppColors.green800,
            ),
            dayBackgroundColor: WidgetStateProperty.resolveWith(
              (s) =>
                  s.contains(WidgetState.selected) ? AppColors.gold500 : null,
            ),
            todayForegroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? AppColors.green900
                  : AppColors.green800,
            ),
            todayBorder: const BorderSide(
              color: AppColors.green800,
              width: 1.5,
            ),
            rangeSelectionBackgroundColor: AppColors.gold500.withValues(
              alpha: .25,
            ),
          ),
        ),
        child: child!,
      ),
    );
    if (r != null) setState(() => _custom = r);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final s = adminState;
        final m = _period;
        final prev = m.previous;
        final today = appState.today;

        // Owed now (not tied to the month picked).
        final unpaid = s.charges.where((c) => !c.paid).toList();
        final owed = unpaid.fold(0.0, (n, c) => n + c.remaining);
        final overdue = unpaid.where((c) => c.overdue).toList();
        final owedOverdue = overdue.fold(0.0, (n, c) => n + c.remaining);
        // Deposits held right now.
        final aptDeposits = s.tenants
            .where(
              (t) =>
                  s.units.any((u) => u.name == t.unit && u.type == 'Apartment'),
            )
            .fold(0.0, (n, t) => n + t.deposit);
        final villaDeposits = s.cheques
            .where(
              (c) =>
                  c.kind == ChequeKind.deposit && c.status == ChequeStatus.held,
            )
            .fold(0.0, (n, c) => n + c.amount);
        final condoDeposits = s.units
            .where((u) => u.type == 'Condo')
            .map((u) => s.currentBooking(u.name))
            .whereType<Booking>()
            .fold(0.0, (n, b) => n + b.depositLeft);
        // Coming in over the next 30 days.
        final soon = today.add(const Duration(days: 30));
        final chequesSoon = s.cheques
            .where(
              (c) =>
                  c.kind == ChequeKind.postDated &&
                  (c.status == ChequeStatus.held ||
                      c.status == ChequeStatus.deposited) &&
                  !c.date.isAfter(soon),
            )
            .fold(0.0, (n, c) => n + c.amount);
        final staysSoon = s.bookings
            .where((b) => b.checkIn.isAfter(today) && !b.checkIn.isAfter(soon))
            .fold(0.0, (n, b) => n + b.amount);
        final occupied = s.units
            .where((u) => u.status == UnitStatus.occupied)
            .length;
        final change = prev.pesoNet == 0
            ? null
            : (m.pesoNet - prev.pesoNet) / prev.pesoNet.abs();

        return TabBody(
          children: [
            const ScreenHeader(
              'Finance',
              subtitle: 'Profit, revenue, costs and what is owed',
            ),
            // Which dates the numbers cover: a month, a whole year, or any
            // start and end date.
            SegmentedTabs(
              labels: const ['Month', 'Year', 'Custom'],
              index: _mode,
              onChanged: (i) => setState(() => _mode = i),
            ),
            _PeriodBar(
              label: _label,
              sub: _mode == 2 ? '${m.days} days · tap to change' : null,
              onPrev: _mode == 2
                  ? null
                  : () => setState(
                      () => _mode == 0
                          ? _month = DateTime(_month.year, _month.month - 1)
                          : _year--,
                    ),
              onNext: _mode == 2
                  ? null
                  : () => setState(
                      () => _mode == 0
                          ? _month = DateTime(_month.year, _month.month + 1)
                          : _year++,
                    ),
              onTap: _mode == 2 ? _pickRange : null,
            ),

            // Profit for the month.
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.green800, AppColors.greenDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: AppColors.gold500.withValues(alpha: .5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NET PROFIT · ${_label.toUpperCase()}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w800,
                      color: AppColors.gold400,
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: CountUpText(
                      peso(m.pesoNet),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    '+ ${peso(m.villaNet, dhs: true)} from villas',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.gold400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (change != null) ...[
                        Icon(
                          change >= 0
                              ? Icons.trending_up_rounded
                              : Icons.trending_down_rounded,
                          size: 18,
                          color: change >= 0
                              ? AppColors.emerald
                              : AppColors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${change >= 0 ? '+' : ''}${(change * 100).toStringAsFixed(0)}% vs the period before',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.slate300,
                          ),
                        ),
                      ] else
                        const Text(
                          'No pesos last month to compare',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.slate300,
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 22, color: Colors.white24),
                  Row(
                    children: [
                      Expanded(
                        child: _Mini(
                          'Revenue',
                          peso(m.pesoIncome),
                          AppColors.emerald,
                        ),
                      ),
                      Expanded(
                        child: _Mini(
                          'Costs, fees & tax',
                          peso(m.pesoCosts + m.taxPeso),
                          AppColors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Where the money came from.
            _Card(
              title: 'Revenue',
              children: [
                _Row(
                  Icons.apartment_rounded,
                  'Apartment rent & charges',
                  peso(m.apartmentIncome),
                ),
                _Row(
                  Icons.hotel_outlined,
                  'Condo stays (${m.stays})',
                  peso(m.condoIncome),
                ),
                _Row(
                  Icons.report_problem_outlined,
                  'Damage deducted from deposits',
                  peso(m.damageRecovered),
                ),
                _Row(
                  Icons.villa_outlined,
                  'Villa cheques cleared',
                  peso(m.villaIncome, dhs: true),
                  gold: true,
                ),
              ],
            ),

            // What it cost.
            _Card(
              title: 'Costs & fees',
              children: [
                _Row(
                  Icons.receipt_long_outlined,
                  'Condo operational costs',
                  peso(m.condoCosts),
                ),
                _Row(
                  Icons.handyman_outlined,
                  'Repairs & maintenance',
                  peso(m.workPeso),
                ),
                _Row(
                  Icons.autorenew_rounded,
                  'Monthly expenses (units)',
                  peso(m.monthlyPeso),
                ),
                if (m.workCharged > 0)
                  _Note(
                    'Of these, ${peso(m.workCharged)} was charged to tenants; ${peso(m.workChargePaid)} is paid so far '
                    'and counted in revenue. The rest counts once their payment is verified.',
                  ),
                if (m.workAed > 0)
                  _Row(
                    Icons.handyman_outlined,
                    'Villa repairs & maintenance',
                    peso(m.workAed, dhs: true),
                    gold: true,
                  ),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => const _FeesDialog(),
                  ),
                  child: _Row(
                    Icons.percent_rounded,
                    'Payment gateway fees (${(_Period.feeRate * 100).toStringAsFixed(1)}%) ✎',
                    peso(m.gatewayFees),
                  ),
                ),
                const _Note(
                  'Repair and maintenance costs come from the cost entered on each job in Scheduling. Tap the gateway fee to change its rate.',
                ),
              ],
            ),

            // Taxes: rates the admin types in (they change often).
            _Card(
              title: 'Taxes',
              children: [
                if (m.taxLines.isEmpty)
                  const _Note('No taxes set. Tap Edit taxes to add one.'),
                for (final t in m.taxLines)
                  _Row(
                    Icons.account_balance_outlined,
                    t.tax.isFixed
                        ? '${t.tax.name} (${peso(t.tax.fixedMonthly, dhs: t.tax.onVillas)} a month)'
                        : '${t.tax.name} (${_pct(t.tax.percent)} of ${t.tax.onVillas ? 'villa' : 'peso'} revenue)',
                    peso(t.amount, dhs: t.tax.onVillas),
                    gold: t.tax.onVillas,
                  ),
                if (m.taxLines.isNotEmpty) ...[
                  const Divider(height: 14),
                  _Row(
                    Icons.functions_rounded,
                    'Total tax',
                    peso(m.taxPeso),
                    red: true,
                  ),
                  if (m.taxAed > 0)
                    _Row(
                      Icons.functions_rounded,
                      'Total tax (villas)',
                      peso(m.taxAed, dhs: true),
                      red: true,
                    ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.green800,
                    side: const BorderSide(color: AppColors.gold500),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => showAppSheet(
                    context,
                    title: 'Taxes',
                    builder: (_) => const _TaxSheet(),
                  ),
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: AppColors.gold600,
                  ),
                  label: const Text(
                    'Edit taxes',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),

            // Still to collect.
            _Card(
              title: 'Owed to you now',
              children: [
                _Row(
                  Icons.request_quote_outlined,
                  'Unpaid charges (${unpaid.length})',
                  peso(owed),
                ),
                _Row(
                  Icons.warning_amber_rounded,
                  'Overdue (${overdue.length})',
                  peso(owedOverdue),
                  red: overdue.isNotEmpty,
                ),
                _Row(
                  Icons.event_repeat_rounded,
                  'Villa cheques due in 30 days',
                  peso(chequesSoon, dhs: true),
                  gold: true,
                ),
                _Row(
                  Icons.event_available_outlined,
                  'Condo stays booked in 30 days',
                  peso(staysSoon),
                ),
                if (m.bounced > 0)
                  _Row(
                    Icons.money_off_rounded,
                    'Bounced cheques this month',
                    '${m.bounced}',
                    red: true,
                  ),
              ],
            ),

            // Money held that isn't yours to keep.
            _Card(
              title: 'Deposits held',
              children: [
                _Row(
                  Icons.savings_outlined,
                  'Apartment security deposits',
                  peso(aptDeposits),
                ),
                _Row(
                  Icons.payments_outlined,
                  'Villa deposit cheques',
                  peso(villaDeposits, dhs: true),
                  gold: true,
                ),
                _Row(
                  Icons.hotel_outlined,
                  'Condo guests staying now',
                  peso(condoDeposits),
                ),
                const _Note(
                  'Deposits are returned at move-out, so they are not counted as revenue.',
                ),
              ],
            ),

            // Occupancy.
            _Card(
              title: 'Occupancy',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: s.units.isEmpty
                              ? 0
                              : occupied / s.units.length,
                          minHeight: 12,
                          backgroundColor: AppColors.slate100,
                          color: AppColors.gold500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$occupied/${s.units.length} occupied',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.green800,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Usage per property type: a summary of all its units, with each
            // unit's numbers under "Show each unit".
            _UsageCard(
              title: 'Condo usage · $_label',
              icon: Icons.hotel_outlined,
              days: m.days,
              countLabel: 'Times used',
              usedLabel: 'Nights booked',
              idleLabel: 'Nights free',
              word: 'used',
              items: [
                for (final c in m.usage)
                  (
                    name: c.unit.name,
                    count: c.stays,
                    used: c.booked,
                    idle: c.free,
                  ),
              ],
            ),
            _UsageCard(
              title: 'Apartment usage · $_label',
              icon: Icons.apartment_rounded,
              days: m.days,
              countLabel: 'Leases',
              usedLabel: 'Days occupied',
              idleLabel: 'Days vacant',
              word: 'occupied',
              items: [
                for (final a in m.aptUsage.where(
                  (a) => a.unit.type == 'Apartment',
                ))
                  (
                    name: a.unit.name,
                    count: a.leases,
                    used: a.occupied,
                    idle: a.vacant,
                  ),
              ],
            ),
            _UsageCard(
              title: 'Villa usage · $_label',
              icon: Icons.villa_outlined,
              days: m.days,
              countLabel: 'Leases',
              usedLabel: 'Days occupied',
              idleLabel: 'Days vacant',
              word: 'occupied',
              items: [
                for (final a in m.aptUsage.where((a) => a.unit.type == 'Villa'))
                  (
                    name: a.unit.name,
                    count: a.leases,
                    used: a.occupied,
                    idle: a.vacant,
                  ),
              ],
            ),

            // Each unit's money for the period.
            _Card(
              title: 'By unit · $_label',
              children: [
                for (final (u, income, cost) in m.perUnit)
                  _Row(
                    switch (u.type) {
                      'Villa' => Icons.villa_outlined,
                      'Condo' => Icons.hotel_outlined,
                      _ => Icons.apartment_rounded,
                    },
                    '${u.name} · ${u.type}',
                    cost > 0
                        ? '${peso(income - cost, dhs: u.type == 'Villa')} net'
                        : peso(income, dhs: u.type == 'Villa'),
                    gold: u.type == 'Villa',
                  ),
              ],
            ),
            // Reports for the period: look at it, share it, or the raw lines.
            Builder(
              builder: (context) {
                void pdf({bool view = false}) => _reportPdf(
                  view: view,
                  m: m,
                  change: change,
                  owed: owed,
                  unpaidCount: unpaid.length,
                  owedOverdue: owedOverdue,
                  overdueCount: overdue.length,
                  chequesSoon: chequesSoon,
                  staysSoon: staysSoon,
                  aptDeposits: aptDeposits,
                  villaDeposits: villaDeposits,
                  condoDeposits: condoDeposits,
                  occupied: occupied,
                  units: s.units.length,
                );
                return AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reports',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.green800,
                        ),
                      ),
                      Text(
                        'Financial report for $_label',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.slate500,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _ExportTile(
                              icon: Icons.visibility_outlined,
                              label: 'View',
                              hint: 'See the PDF',
                              primary: true,
                              onTap: () => pdf(view: true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _ExportTile(
                              icon: Icons.picture_as_pdf_rounded,
                              label: 'PDF',
                              hint: 'Save or send',
                              primary: true,
                              onTap: pdf,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value, this.color);
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppColors.slate300),
      ),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => AppCard(
    radius: 20,
    child: Column(
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
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row(
    this.icon,
    this.label,
    this.value, {
    this.gold = false,
    this.red = false,
  });
  final IconData icon;
  final String label, value;
  final bool gold, red;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.gold600),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.slate600),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: red
                ? AppColors.red
                : gold
                ? AppColors.gold700
                : AppColors.green800,
          ),
        ),
      ],
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        height: 1.35,
        color: AppColors.slate400,
      ),
    ),
  );
}

/// "Oct 3 - Nov 12, 2026" (the year once when both dates share it).
String _rangeText(DateTime a, DateTime b) {
  String d(DateTime x) =>
      '${_monthNames[x.month - 1].substring(0, 3)} ${x.day}';
  return a.year == b.year
      ? '${d(a)} - ${d(b)}, ${b.year}'
      : '${d(a)}, ${a.year} - ${d(b)}, ${b.year}';
}

/// The dark bar showing the period: arrows for a month or year; for custom
/// dates, tap it to choose the start and end.
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.label,
    this.sub,
    this.onPrev,
    this.onNext,
    this.onTap,
  });
  final String label;
  final String? sub;
  final VoidCallback? onPrev, onNext, onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.green900,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: onTap == null ? 0 : 10,
            horizontal: 4,
          ),
          child: Row(
            children: [
              if (onPrev != null)
                IconButton(
                  tooltip: 'Previous',
                  onPressed: onPrev,
                  icon: const Icon(
                    Icons.chevron_left_rounded,
                    color: AppColors.gold400,
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Icon(
                    Icons.date_range_rounded,
                    color: AppColors.gold400,
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    if (sub != null)
                      Text(
                        sub!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.slate300,
                        ),
                      ),
                  ],
                ),
              ),
              if (onNext != null)
                IconButton(
                  tooltip: 'Next',
                  onPressed: onNext,
                  icon: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.gold400,
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(
                    Icons.edit_calendar_rounded,
                    color: AppColors.gold400,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UseStat extends StatelessWidget {
  const _UseStat(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.green800,
        ),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 11.5, color: AppColors.slate500),
      ),
    ],
  );
}

/// "3%" or "2.5%".
String _pct(double p) =>
    '${p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toString()}%';

/// The tax rates: change a rate, add a tax, or remove one. Every change
/// shows on the Finance numbers straight away.
class _TaxSheet extends StatelessWidget {
  const _TaxSheet();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rates change often: keep them up to date here. Each one is taken from the revenue of the period on screen.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.slate500,
            ),
          ),
          const SizedBox(height: 12),
          for (final t in adminState.taxes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  title: Text(
                    t.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.green800,
                    ),
                  ),
                  subtitle: Text(
                    t.isFixed
                        ? 'Fixed amount each month${t.onVillas ? ' (AED)' : ''}'
                        : 'On ${t.onVillas ? 'villa revenue (AED)' : 'peso revenue'}',
                  ),
                  trailing: Text(
                    t.isFixed
                        ? peso(t.fixedMonthly, dhs: t.onVillas)
                        : _pct(t.percent),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.gold700,
                    ),
                  ),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => _TaxDialog(existing: t),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          GoldButton(
            label: 'Add a tax',
            icon: Icons.add_rounded,
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const _TaxDialog(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaxDialog extends StatefulWidget {
  const _TaxDialog({this.existing});
  final TaxRate? existing;
  @override
  State<_TaxDialog> createState() => _TaxDialogState();
}

class _TaxDialogState extends State<_TaxDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _rate = TextEditingController(
    text: widget.existing == null
        ? ''
        : widget.existing!.isFixed
        ? widget.existing!.fixedMonthly.toStringAsFixed(2)
        : _pct(widget.existing!.percent).replaceAll('%', ''),
  );
  late bool _villas = widget.existing?.onVillas ?? false;

  /// A fixed amount each month instead of a percentage of income.
  late bool _fixed = widget.existing?.isFixed ?? false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.existing;
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(
        t == null ? 'Add a tax' : 'Edit tax',
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.green800,
        ),
      ),
      content: SizedBox(
        // A set width: the dialog measures its content, and the tabs below
        // cannot be measured that way.
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Name, e.g. Percentage tax',
              ),
            ),
            const SizedBox(height: 10),
            SegmentedTabs(
              light: true,
              labels: const ['% of revenue', 'Fixed monthly'],
              index: _fixed ? 1 : 0,
              onChanged: (i) => setState(() => _fixed = i == 1),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _rate,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: _fixed
                  ? InputDecoration(
                      hintText: 'Amount each month',
                      prefixText: '${currencySign(_villas)} ',
                    )
                  : const InputDecoration(hintText: 'Rate', suffixText: '%'),
            ),
            const SizedBox(height: 10),
            SegmentedTabs(
              light: true,
              labels: _fixed
                  ? const ['In pesos', 'In AED (villas)']
                  : const ['Peso revenue', 'Villa revenue (AED)'],
              index: _villas ? 1 : 0,
              onChanged: (i) => setState(() => _villas = i == 1),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.red),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (t != null)
          TextButton(
            onPressed: () {
              adminState.removeTax(t);
              popOnce(context);
            },
            child: const Text('Remove', style: TextStyle(color: AppColors.red)),
          ),
        TextButton(
          onPressed: () => popOnce(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold500,
            foregroundColor: AppColors.green900,
          ),
          onPressed: () {
            final rate = double.tryParse(_rate.text.trim().replaceAll(',', ''));
            if (_name.text.trim().isEmpty ||
                rate == null ||
                rate < 0 ||
                (!_fixed && rate > 100) ||
                (_fixed && rate == 0)) {
              setState(
                () => _error = _fixed
                    ? 'Enter a name and the amount each month.'
                    : 'Enter a name and a rate from 0 to 100.',
              );
              return;
            }
            adminState.saveTax(
              t,
              TaxRate(
                name: _name.text.trim(),
                percent: _fixed ? 0 : rate,
                fixedMonthly: _fixed ? rate : 0,
                onVillas: _villas,
              ),
            );
            popOnce(context);
          },
          child: const Text(
            'Save',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

/// How much one type of unit (condos, apartments or villas) was used in the
/// period: a summary across all of them, and each unit when expanded.
class _UsageCard extends StatefulWidget {
  const _UsageCard({
    required this.title,
    required this.icon,
    required this.days,
    required this.countLabel,
    required this.usedLabel,
    required this.idleLabel,
    required this.word,
    required this.items,
  });
  final String title, countLabel, usedLabel, idleLabel;

  /// "used" or "occupied", after the percentage.
  final String word;
  final IconData icon;
  final int days;
  final List<({String name, int count, int used, int idle})> items;

  @override
  State<_UsageCard> createState() => _UsageCardState();
}

class _UsageCardState extends State<_UsageCard> {
  bool _open = false;

  int _pct(int used, int units) => widget.days == 0 || units == 0
      ? 0
      : (used * 100 / (widget.days * units)).round();

  Widget _block(
    String name,
    int count,
    int used,
    int idle,
    int units, {
    bool big = false,
  }) {
    final pct = _pct(used, units);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(widget.icon, size: big ? 20 : 18, color: AppColors.gold600),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: big ? 14.5 : 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
            ),
            Text(
              '$pct% ${widget.word}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.gold700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: big ? 12 : 10,
            backgroundColor: AppColors.slate100,
            color: AppColors.gold500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _UseStat(widget.countLabel, '$count')),
            Expanded(child: _UseStat(widget.usedLabel, '$used')),
            Expanded(child: _UseStat(widget.idleLabel, '$idle')),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final n = items.length;
    return _Card(
      title: widget.title,
      children: [
        if (n == 0)
          const _Note('No units of this type yet.')
        else ...[
          // All units together.
          _block(
            'All $n ${n == 1 ? 'unit' : 'units'}',
            items.fold(0, (s, i) => s + i.count),
            items.fold(0, (s, i) => s + i.used),
            items.fold(0, (s, i) => s + i.idle),
            n,
            big: true,
          ),
          const SizedBox(height: 6),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Text(
                    _open ? 'Hide each unit' : 'Show each unit',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.gold700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _open ? .5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.gold700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Each unit.
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      for (final i in items) ...[
                        const Divider(height: 22),
                        _block(i.name, i.count, i.used, i.idle, 1),
                      ],
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}

/// The fee rates the numbers use: the payment gateway's cut on online
/// payments, and the fee charged when a villa cheque bounces.
class _FeesDialog extends StatefulWidget {
  const _FeesDialog();
  @override
  State<_FeesDialog> createState() => _FeesDialogState();
}

class _FeesDialogState extends State<_FeesDialog> {
  final _gateway = TextEditingController(
    text: adminState.gatewayFeePercent.toString(),
  );
  final _bounced = TextEditingController(
    text: adminState.bouncedChequeFee.toStringAsFixed(0),
  );
  String? _error;

  @override
  void dispose() {
    _gateway.dispose();
    _bounced.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fees'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('Payment gateway fee (online payments)'),
          TextField(
            controller: _gateway,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(suffixText: '%'),
          ),
          const SizedBox(height: 12),
          const FieldLabel('Bounced cheque fee (villas)'),
          TextField(
            controller: _bounced,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              prefixText: 'AED ',
              hintText: '0 for none',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 12.5, color: AppColors.red),
              ),
            ),
        ],
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
          onPressed: () {
            final g = double.tryParse(_gateway.text.trim());
            final b = double.tryParse(_bounced.text.trim().replaceAll(',', ''));
            if (g == null || g < 0 || g > 20 || b == null || b < 0) {
              setState(
                () => _error = 'Enter a gateway fee from 0 to 20% and a bounced fee of 0 or more.',
              );
              return;
            }
            adminState.setFees(gateway: g, bounced: b);
            popOnce(context);
          },
          child: const Text(
            'Save',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

/// One report action: an icon, a short name and what it does. The main one
/// is gold.
class _ExportTile extends StatelessWidget {
  const _ExportTile({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String label, hint;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              gradient: primary ? goldGradient : null,
              color: primary ? null : AppColors.slate50,
              borderRadius: BorderRadius.circular(16),
              border: primary ? null : Border.all(color: AppColors.slate200),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: primary
                        ? Colors.white.withValues(alpha: .35)
                        : AppColors.gold500.withValues(alpha: .14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 21,
                    color: primary ? AppColors.green900 : AppColors.gold700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: primary ? AppColors.green900 : AppColors.green800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: primary
                        ? AppColors.green900.withValues(alpha: .75)
                        : AppColors.slate500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
