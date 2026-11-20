import 'package:flutter/material.dart';

import '../../screens/shell.dart' show SubPage;
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../state/app_state.dart' show appState;
import '../admin_state.dart';
import 'cheque_detail_screen.dart';

Pill _statusPill(ChequeStatus s) => switch (s) {
  ChequeStatus.held => Pill.neutral('HELD'),
  ChequeStatus.deposited => Pill.info('DEPOSITED'),
  ChequeStatus.cleared => Pill.verified('CLEARED'),
  ChequeStatus.bounced => Pill.urgent('BOUNCED'),
};

/// "2025-2026" for the lease year starting [y] ("2026" if it starts Jan 1).
String yearLabel(DateTime y) =>
    y.month == 1 && y.day == 1 ? '${y.year}' : '${y.year}-${y.year + 1}';

/// The last day of the lease year starting [y].
DateTime yearEnd(DateTime y) =>
    dueDateIn(y.year + 1, y.month, y.day).subtract(const Duration(days: 1));

/// Every cheque for a villa tenant: the deposit cheque and the post-dated
/// ones. Management ([admin]) plans them and moves each through its status;
/// the tenant only reads.
class ChequesScreen extends StatefulWidget {
  const ChequesScreen(this.tenant, {super.key, this.admin = false});
  final String tenant;
  final bool admin;

  @override
  State<ChequesScreen> createState() => _ChequesScreenState();
}

class _ChequesScreenState extends State<ChequesScreen> {
  /// The lease year the tenant is looking at; null means the current one.
  DateTime? _shown;

  String get tenant => widget.tenant;
  bool get admin => widget.admin;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final rec = adminState.tenants
            .where((t) => t.name == tenant)
            .firstOrNull;
        final all = adminState.chequesFor(tenant);
        final deposit = all.where((c) => c.kind == ChequeKind.deposit).toList();
        final pdc = all.where((c) => c.kind == ChequeKind.postDated).toList();
        // Post-dated cheques grouped by lease year, oldest first.
        final byYear = <DateTime, List<ChequeRec>>{};
        for (final c in pdc) {
          final y = rec == null
              ? DateTime(c.date.year)
              : adminState.leaseYearOf(rec, c.date);
          byYear.putIfAbsent(y, () => []).add(c);
        }
        final years = byYear.keys.toList()..sort();
        // The tenant sees one year at a time, starting on the current one.
        // The arrows go through every year of the lease (and the next, for a
        // renewal), not only years that have cheques.
        final now = rec == null
            ? null
            : adminState.leaseYearOf(rec, appState.today);
        final nav = ({
          ...years,
          if (rec != null) ...adminState.leaseYears(rec),
        }.toList()..sort());
        final shown = nav.contains(_shown)
            ? _shown!
            : nav.contains(now)
            ? now!
            : (nav.isEmpty ? null : nav.last);
        final at = shown == null ? -1 : nav.indexOf(shown);
        return SubPage(
          title: admin ? 'Cheques · $tenant' : 'My Cheques',
          children: [
            if (admin && rec != null)
              Row(
                children: [
                  Expanded(
                    child: GoldButton(
                      label: 'Plan cheques',
                      icon: Icons.auto_awesome_motion_outlined,
                      compact: true,
                      onPressed: () => showAppSheet(
                        context,
                        title: 'Plan post-dated cheques',
                        builder: (_) => _PlanForm(rec),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GoldButton(
                      label: 'Add cheque',
                      icon: Icons.add_rounded,
                      compact: true,
                      onPressed: () => showAppSheet(
                        context,
                        title: 'Add a cheque',
                        builder: (_) => _AddForm(tenant),
                      ),
                    ),
                  ),
                ],
              ),
            const _Section(
              'Deposit cheque',
              'Held like a security deposit; returned at move-out.',
            ),
            if (deposit.isEmpty) const _None('No deposit cheque recorded yet.'),
            for (final c in deposit) _ChequeCard(c, admin: admin),
            if (admin && pdc.isEmpty) ...[
              const _Section(
                'Post-dated cheques',
                'Banked on the date written on each cheque.',
              ),
              const _None(
                'None yet. Tap Plan cheques to set up 1 to 4 for the year.',
              ),
            ],
            // Tenant: pick the year with the arrows, then see that year's cheques.
            if (!admin && shown != null) ...[
              const _Section(
                'Post-dated cheques',
                'Banked on the date written on each cheque.',
              ),
              _YearSwitcher(
                year: shown,
                isCurrent: shown == now,
                onPrev: at > 0
                    ? () => setState(() => _shown = nav[at - 1])
                    : null,
                onNext: at < nav.length - 1
                    ? () => setState(() => _shown = nav[at + 1])
                    : null,
              ),
              if ((byYear[shown] ?? const []).isEmpty)
                const _None(
                  'No cheques for this year yet. Management adds them once agreed.',
                )
              else ...[
                Text(
                  '${byYear[shown]!.where((c) => c.status == ChequeStatus.cleared).length} of ${byYear[shown]!.length} cleared',
                  style: const TextStyle(
                    color: AppColors.slate300,
                    fontSize: 12,
                  ),
                ),
                for (final c in byYear[shown]!) _ChequeCard(c, admin: false),
              ],
            ],
            if (admin)
              for (final y in years) ...[
                _Section(
                  'Post-dated cheques · ${yearLabel(y)}',
                  '${formatDate(y)} - ${formatDate(yearEnd(y))} · '
                      '${byYear[y]!.where((c) => c.status == ChequeStatus.cleared).length} of ${byYear[y]!.length} cleared',
                ),
                for (final c in byYear[y]!) _ChequeCard(c, admin: admin),
              ],
          ],
        );
      },
    );
  }
}

/// A card with the lease year in the middle and round gold arrow buttons on
/// each side; an arrow fades out when there is no year that way.
class _YearSwitcher extends StatelessWidget {
  const _YearSwitcher({
    required this.year,
    required this.isCurrent,
    this.onPrev,
    this.onNext,
  });
  final DateTime year;
  final bool isCurrent;
  final VoidCallback? onPrev, onNext;

  Widget _arrow(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
    message: tip,
    child: PressScale(
      enabled: onTap != null,
      scale: .9,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: onTap == null ? .35 : 1,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: onTap == null ? null : goldGradient,
              color: onTap == null ? AppColors.slate100 : null,
              shape: BoxShape.circle,
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Icon(icon, color: AppColors.green900),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        children: [
          _arrow(Icons.chevron_left_rounded, 'Previous year', onPrev),
          Expanded(
            child: Column(
              children: [
                Text(
                  yearLabel(year),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatDate(year)} - ${formatDate(yearEnd(year))}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.slate500,
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(height: 6),
                  Pill.verified('THIS YEAR'),
                ],
              ],
            ),
          ),
          _arrow(Icons.chevron_right_rounded, 'Next year', onNext),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.subtitle);
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.slate300, fontSize: 12),
        ),
      ],
    ),
  );
}

class _None extends StatelessWidget {
  const _None(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => AppCard(
    child: Text(
      text,
      style: const TextStyle(fontSize: 12.5, color: AppColors.slate500),
    ),
  );
}

/// Management's to-do list for villa cheques, across all tenants: cheques
/// whose date has come (take them to the bank) and banked cheques waiting to
/// be confirmed as cleared or bounced. Tap one to update it.
class ChequeVerificationScreen extends StatelessWidget {
  const ChequeVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        // A cheque with a new photo is listed once, under New photos.
        final toBank = adminState.chequesToBank
            .where((c) => !c.newPhoto)
            .toList();
        final deposited = adminState.chequesDeposited
            .where((c) => !c.newPhoto)
            .toList();
        final photos = adminState.chequesWithNewPhotos;
        return SubPage(
          title: 'Cheque verification',
          children: [
            const _Section(
              'New photos',
              'Uploaded by tenants. Open each one to check it.',
            ),
            if (photos.isEmpty) const _None('No new cheque photos.'),
            for (final c in photos)
              _ChequeCard(c, admin: true, showTenant: true),
            const _Section(
              'Ready to bank',
              'The date on these cheques has come.',
            ),
            if (toBank.isEmpty) const _None('Nothing to bank right now.'),
            for (final c in toBank)
              _ChequeCard(c, admin: true, showTenant: true),
            const _Section(
              'Deposited',
              'Banked. Confirm when each one clears or bounces.',
            ),
            if (deposited.isEmpty) const _None('No cheques waiting to clear.'),
            for (final c in deposited)
              _ChequeCard(c, admin: true, showTenant: true),
          ],
        );
      },
    );
  }
}

class _ChequeCard extends StatelessWidget {
  const _ChequeCard(this.c, {required this.admin, this.showTenant = false});
  final ChequeRec c;
  final bool admin;

  /// On the all-tenants list, say whose cheque it is.
  final bool showTenant;

  @override
  Widget build(BuildContext context) {
    final deposit = c.kind == ChequeKind.deposit;
    final bits = [
      if (c.chequeNo.isNotEmpty) 'No. ${c.chequeNo}',
      if (c.bank.isNotEmpty) c.bank,
      if (!deposit && c.months > 0)
        '${c.months} ${c.months == 1 ? 'month' : 'months'} of rent',
      if (c.replaces != null) 'replaces a bounced cheque',
      if (c.returnedOn != null) 'handed back ${c.returnedOn}',
    ];
    return AppCard(
      radius: 18,
      onTap: admin
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => ChequeDetailScreen(c)),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // On the all-tenants list: which villa, then whose.
          if (showTenant) ...[
            Row(
              children: [
                const Icon(
                  Icons.villa_outlined,
                  size: 16,
                  color: AppColors.gold600,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${adminState.tenants.where((t) => t.name == c.tenant).firstOrNull?.unitLabel ?? 'No unit'} · ${c.tenant}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.gold700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  peso(c.amount, dhs: true),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
              ),
              _statusPill(c.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            deposit
                ? 'Dated ${formatDate(c.date)}'
                : 'Banks on ${formatDate(c.date)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.gold700,
            ),
          ),
          if (c.hasPhoto)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.photo_camera_outlined,
                    size: 14,
                    color: c.newPhoto ? AppColors.gold600 : AppColors.slate400,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    c.newPhoto
                        ? 'New photo · ${c.uploadedOn}'
                        : 'Photo checked',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: c.newPhoto
                          ? AppColors.gold700
                          : AppColors.slate400,
                    ),
                  ),
                ],
              ),
            ),
          if (bits.isNotEmpty)
            Text(
              bits.join(' · '),
              style: const TextStyle(fontSize: 12, color: AppColors.slate500),
            ),
        ],
      ),
    );
  }
}

class _PlanForm extends StatefulWidget {
  const _PlanForm(this.t);
  final TenantRec t;
  @override
  State<_PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends State<_PlanForm> {
  late int _perYear = widget.t.chequesPerYear;
  late final List<DateTime> _years = adminState.leaseYears(widget.t);

  /// The first lease year without any cheques yet; otherwise the latest.
  late DateTime _year = _years.firstWhere(
    (y) => !adminState
        .chequesFor(widget.t.name)
        .any(
          (c) =>
              c.kind == ChequeKind.postDated &&
              adminState.leaseYearOf(widget.t, c.date) == y,
        ),
    orElse: () => _years.last,
  );

  String _yearOption(DateTime y) =>
      '${yearLabel(y)}  (${formatDate(y)} - ${formatDate(yearEnd(y))})';

  @override
  Widget build(BuildContext context) {
    final months = 12 ~/ _perYear;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Which year?'),
        DropdownField(
          title: 'Lease year',
          value: _yearOption(_year),
          items: [for (final y in _years) _yearOption(y)],
          onChanged: (v) => setState(
            () => _year = _years.firstWhere((y) => _yearOption(y) == v),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'How many post-dated cheques for the year?',
          style: TextStyle(fontSize: 12.5, color: AppColors.slate500),
        ),
        const SizedBox(height: 10),
        SegmentedTabs(
          light: true,
          labels: const ['1', '2', '3', '4'],
          index: _perYear - 1,
          onChanged: (i) => setState(() => _perYear = i + 1),
        ),
        const SizedBox(height: 12),
        Text(
          '$_perYear ${_perYear == 1 ? 'cheque' : 'cheques'} of ${peso(adminState.monthlyRentOf(widget.t) * months, dhs: true)}, each paying $months ${months == 1 ? 'month' : 'months'}, dated from ${formatDate(_year)}. Cheques already banked are kept.',
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            color: AppColors.green800,
          ),
        ),
        const SizedBox(height: 16),
        GoldButton(
          label: 'Create cheques',
          onPressed: () {
            adminState.planCheques(widget.t, _perYear, yearStart: _year);
            popOnce(context);
            toast(context, 'Cheques planned for ${yearLabel(_year)}.');
          },
        ),
      ],
    );
  }
}

class _AddForm extends StatefulWidget {
  const _AddForm(this.tenant);
  final String tenant;
  @override
  State<_AddForm> createState() => _AddFormState();
}

class _AddFormState extends State<_AddForm> {
  final _key = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _no = TextEditingController();
  final _bank = TextEditingController();
  int _kind = 1; // 0 deposit, 1 post-dated
  int _months = 3;
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _amount.dispose();
    _no.dispose();
    _bank.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const monthChoices = [1, 2, 3, 4, 6, 12];
    return Form(
      key: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedTabs(
            light: true,
            labels: const ['Deposit', 'Post-dated'],
            index: _kind,
            onChanged: (i) => setState(() => _kind = i),
          ),
          const SizedBox(height: 12),
          const FieldLabel('Amount (AED)'),
          TextFormField(
            controller: _amount,
            keyboardType: TextInputType.number,
            validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0
                ? 'Enter the amount'
                : null,
          ),
          const SizedBox(height: 12),
          FieldLabel(
            _kind == 0
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
                lastDate: DateTime(2035),
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
          if (_kind == 1) ...[
            const SizedBox(height: 12),
            const FieldLabel('Months of rent it pays for'),
            SegmentedTabs(
              light: true,
              labels: [for (final m in monthChoices) '$m'],
              index: monthChoices.indexOf(_months),
              onChanged: (i) => setState(() => _months = monthChoices[i]),
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
            label: 'Save cheque',
            onPressed: () {
              if (!_key.currentState!.validate()) return;
              adminState.addCheque(
                widget.tenant,
                _kind == 0 ? ChequeKind.deposit : ChequeKind.postDated,
                double.parse(_amount.text),
                _date,
                months: _kind == 0 ? 0 : _months,
                chequeNo: _no.text.trim(),
                bank: _bank.text.trim(),
              );
              popOnce(context);
              toast(context, 'Cheque added.');
            },
          ),
        ],
      ),
    );
  }
}
