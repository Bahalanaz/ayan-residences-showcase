import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../admin_state.dart';

const _months = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

/// Schedule repairs and maintenance for a unit or a whole property. Scheduled
/// work appears on the admin calendar (and on the tenant's, when it affects them).
class MaintenanceAdminScreen extends StatefulWidget {
  const MaintenanceAdminScreen({super.key});
  @override
  State<MaintenanceAdminScreen> createState() => _MaintenanceAdminScreenState();
}

class _MaintenanceAdminScreenState extends State<MaintenanceAdminScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.green800,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Scheduling',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.gold500,
        foregroundColor: AppColors.green900,
        icon: const Icon(Icons.add),
        label: const Text(
          'Schedule',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        onPressed: () => adminState.units.isEmpty
            ? toast(context, 'Add a unit first (Properties → Add unit).')
            : showAppSheet(
                context,
                title: 'Schedule work',
                builder: (_) => const ScheduleForm(),
              ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListenableBuilder(
              listenable: adminState,
              builder: (context, _) {
                final upcoming = adminState.upcomingWork;
                final done = adminState.workItems.where((w) => w.done).toList();
                final shown = _tab == 0 ? upcoming : done;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                  children: [
                    SegmentedTabs(
                      labels: [
                        'Upcoming (${upcoming.length})',
                        'Done (${done.length})',
                      ],
                      index: _tab,
                      onChanged: (i) => setState(() => _tab = i),
                    ),
                    const SizedBox(height: 14),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 50),
                        child: Center(
                          child: Text(
                            _tab == 0
                                ? 'Nothing scheduled. Tap Schedule to add a repair or maintenance.'
                                : 'Nothing completed yet.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.slate300),
                          ),
                        ),
                      ),
                    for (final w in shown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _WorkCard(w),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkCard extends StatelessWidget {
  const _WorkCard(this.w);
  final WorkItem w;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: 18,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: w.done ? AppColors.slate400 : AppColors.green800,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  '${w.date.day}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _months[w.date.month - 1],
                  style: const TextStyle(
                    color: AppColors.gold400,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  w.title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                    decoration: w.done ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${w.where} · ${w.time}${w.cost > 0 ? ' · ${peso(w.cost, dhs: adminState.isVillaUnit(w.where) || w.where == 'Ayan Villas')}' : ''}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.slate500,
                  ),
                ),
                // The tenant pays: the request and whether it has been paid.
                if (w.tenantPays && w.chargedTenant != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${w.chargedTenant} pays ${peso(w.charge, dhs: adminState.isVillaUnit(w.where))}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.green800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (w.chargeRec?.paid ?? false)
                          Pill.verified('PAID')
                        else if (w.chargeRec?.partlyPaid ?? false)
                          Pill.pending('PART PAID')
                        else
                          Pill.pending('UNPAID'),
                      ],
                    ),
                  ),
                if (w.days.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${_months[w.date.month - 1]} ${w.date.day} - ${_months[w.endDate.month - 1]} ${w.endDate.day} · ${w.days.length} days',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.gold700,
                      ),
                    ),
                  ),
                if (w.notes.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    w.notes,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.slate500,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                switch (w.kind) {
                  AdminEventKind.repair => Pill.pending('REPAIR'),
                  AdminEventKind.inspection => Pill.neutral('INSPECTION'),
                  AdminEventKind.modification => Pill.pending('MODIFICATION'),
                  _ => Pill.info('MAINTENANCE'),
                },
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.slate500),
            onSelected: (v) {
              if (v == 'done') adminState.setWorkDone(w, !w.done);
              if (v == 'remove') {
                final why = adminState.whyKeepWork(w);
                if (why != null) {
                  toast(context, why);
                } else {
                  adminState.removeWork(w);
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'done',
                child: Text(w.done ? 'Mark as upcoming' : 'Mark as done'),
              ),
              const PopupMenuItem(value: 'remove', child: Text('Remove')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Schedules a repair, maintenance or inspection. Opened from Scheduling,
/// or from a report with its details filled in ([title], [where], [kind],
/// [tenantPays], [charge]).
class ScheduleForm extends StatefulWidget {
  const ScheduleForm({
    super.key,
    this.title,
    this.where,
    this.kind = 0,
    this.tenantPays = false,
    this.charge,
  });
  final String? title, where;

  /// 0 repair, 1 maintenance, 2 inspection, 3 modification.
  final int kind;
  final bool tenantPays;
  final double? charge;
  @override
  State<ScheduleForm> createState() => _ScheduleFormState();
}

class _ScheduleFormState extends State<ScheduleForm> {
  final _key = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.title ?? '');

  /// What the job costs management (or the value of what was damaged).
  final _cost = TextEditingController();

  /// What the tenant is asked to pay, when the tenant pays.
  late final _charge = TextEditingController(
    text: (widget.charge ?? 0) > 0 ? widget.charge!.toStringAsFixed(0) : '',
  );
  late int _kind =
      widget.kind; // 0 repair, 1 maintenance, 2 inspection, 3 modification
  late bool _tenantPays = widget.tenantPays;
  late String _where =
      widget.where != null && _targets().any((t) => t.value == widget.where)
      ? widget.where!
      : _targets().first.value;

  double _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '')) ?? 0;
  // A job defaults to today and to a single day.
  DateTime _date = appState.today;
  DateTime _endDate = appState.today;

  String _fmt(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
  TimeOfDay? _start;
  TimeOfDay? _end;

  /// Whole properties first, then every unit grouped under its property.
  List<PickerOption> _targets() {
    final props = [
      for (final p in {for (final u in adminState.units) u.property}) p,
    ];
    return [
      for (final p in props)
        PickerOption(
          value: p,
          label: p,
          subtitle:
              'Whole building · ${adminState.units.where((u) => u.property == p).length} units',
          icon: Icons.apartment_rounded,
          group: 'Whole property',
          // A property of one kind shows under that filter; a mixed one under all.
          kind: {
            for (final u in adminState.units.where((u) => u.property == p))
              u.type,
          }.singleOrNull,
        ),
      for (final u in adminState.units)
        PickerOption(
          value: u.name,
          label: u.name,
          subtitle: '${u.property} · ${u.type}',
          kind: u.type,
          person: u.status == UnitStatus.vacant
              ? null
              : adminState.tenantOfUnit(u.name)?.name ?? u.tenant,
          icon: switch (u.type) {
            'Villa' => Icons.house_rounded,
            'Condo' => Icons.domain_rounded,
            _ => Icons.meeting_room_rounded,
          },
          group: u.property,
          badge: switch (u.status) {
            UnitStatus.vacant => 'Vacant',
            UnitStatus.reserved => 'Reserved',
            UnitStatus.occupied => 'Occupied',
          },
          badgeColor: switch (u.status) {
            UnitStatus.vacant => AppColors.slate500,
            UnitStatus.reserved => AppColors.amber,
            UnitStatus.occupied => AppColors.emerald,
          },
        ),
    ];
  }

  @override
  void dispose() {
    _title.dispose();
    _cost.dispose();
    _charge.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = appState.today;
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (d == null) return;
    setState(() {
      // Moving the start past the end keeps it a one-day job.
      if (_endDate.isBefore(d)) _endDate = d;
      _date = d;
    });
  }

  Future<void> _pickEndDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _date,
      lastDate: DateTime(_date.year + 2),
    );
    if (d != null) setState(() => _endDate = d);
  }

  int _mins(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _pickStart() async {
    final t = await showTimePicker(
      initialEntryMode: TimePickerEntryMode.input,
      context: context,
      initialTime: _start ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (t != null) setState(() => _start = t);
  }

  /// The end is optional: leave it empty when the admin does not know yet.
  Future<void> _pickEnd() async {
    final s = _start ?? const TimeOfDay(hour: 9, minute: 0);
    final t = await showTimePicker(
      initialEntryMode: TimePickerEntryMode.input,
      context: context,
      initialTime: _end ?? TimeOfDay(hour: (s.hour + 1) % 24, minute: s.minute),
    );
    if (t != null) setState(() => _end = t);
  }

  /// The money fields under "Who pays?": the cost when management pays; the
  /// value of the damage and the amount to charge when the tenant pays, with
  /// what management makes (or loses) on it.
  List<Widget> _money() {
    final villa = adminState.isVillaUnit(_where) || _where == 'Ayan Villas';
    final sign = currencySign(villa);
    if (!_tenantPays) {
      return [
        FieldLabel('Cost ($sign, optional)'),
        TextFormField(
          controller: _cost,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Deducted in Finance on the start date',
          ),
        ),
      ];
    }
    final payer = adminState.tenantOfUnit(_where);
    final value = _num(_cost), charge = _num(_charge);
    final diff = charge - value;
    return [
      if (payer == null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppColors.amberBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            adminState.units.any((u) => u.name == _where && u.type == 'Condo')
                ? 'Condo guests have no account to charge. Take it from their deposit instead.'
                : 'No tenant lives in $_where. Pick the tenant\'s unit to charge them.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppColors.amber,
            ),
          ),
        ),
      FieldLabel('Value of the damage / cost of the work ($sign)'),
      TextFormField(
        controller: _cost,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText: 'What it costs to fix or replace',
        ),
      ),
      const SizedBox(height: 12),
      FieldLabel('Amount to charge the tenant ($sign)'),
      TextFormField(
        controller: _charge,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText: 'Sent to them as a payment request',
        ),
      ),
      if (payer != null) ...[
        const SizedBox(height: 8),
        Text(
          'Payment request goes to ${payer.name}, due on the start date.',
          style: const TextStyle(fontSize: 12, color: AppColors.slate500),
        ),
        if (charge > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              diff == 0
                  ? 'Covers the cost exactly, once paid.'
                  : diff > 0
                  ? 'Profit of ${peso(diff, dhs: villa)} once paid.'
                  : 'Management still pays ${peso(-diff, dhs: villa)} of it.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: diff >= 0 ? AppColors.emerald : AppColors.red,
              ),
            ),
          ),
      ],
    ];
  }

  String _timeLabel(BuildContext context) {
    if (_start == null) return 'All day';
    final s = _start!.format(context);
    return _end == null ? s : '$s - ${_end!.format(context)}';
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedTabs(
            light: true,
            labels: const [
              'Repair',
              'Maintenance',
              'Inspection',
              'Modification',
            ],
            index: _kind,
            onChanged: (i) => setState(() => _kind = i),
          ),
          const SizedBox(height: 14),
          const FieldLabel('What needs doing'),
          TextFormField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Fix leaking faucet',
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Describe the job' : null,
          ),
          const SizedBox(height: 12),
          const FieldLabel('Where (a unit, or a whole property)'),
          DropdownField(
            title: 'Where is the job?',
            value: _where,
            options: _targets(),
            onChanged: (v) => setState(() => _where = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FieldBlock(
                  'Start date',
                  _Pick(Icons.event_outlined, _fmt(_date), _pickDate),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FieldBlock(
                  'End date',
                  _Pick(
                    Icons.event_available_outlined,
                    _fmt(_endDate),
                    _pickEndDate,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _date == _endDate
                ? 'A one-day job. Change the end date if it runs longer.'
                : 'Runs ${_endDate.difference(_date).inDays + 1} days.',
            style: const TextStyle(fontSize: 12, color: AppColors.slate500),
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FieldBlock(
                  'Start time',
                  _Pick(
                    Icons.schedule,
                    _start == null ? 'All day' : _start!.format(context),
                    _pickStart,
                    onClear: _start == null
                        ? null
                        : () => setState(() {
                            _start = null;
                            _end = null;
                          }),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FieldBlock(
                  'End time',
                  _Pick(
                    Icons.schedule_outlined,
                    _end == null ? 'No end time' : _end!.format(context),
                    _pickEnd,
                    onClear: _end == null
                        ? null
                        : () => setState(() => _end = null),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Who pays for the job: management (a cost), or the tenant (they are
          // sent a payment request).
          const FieldLabel('Who pays?'),
          SegmentedTabs(
            light: true,
            labels: const ['Management', 'Tenant'],
            index: _tenantPays ? 1 : 0,
            onChanged: (i) => setState(() => _tenantPays = i == 1),
          ),
          const SizedBox(height: 12),
          ..._money(),
          const SizedBox(height: 16),
          GoldButton(
            label: 'Schedule',
            onPressed: () {
              if (!_key.currentState!.validate()) return;
              final payer = adminState.tenantOfUnit(_where);
              if (_tenantPays && payer == null) {
                toast(
                  context,
                  'No tenant lives in $_where to charge. Pick their unit, or choose Management.',
                );
                return;
              }
              if (_tenantPays && _num(_charge) <= 0) {
                toast(context, 'Enter how much the tenant has to pay.');
                return;
              }
              if (_end != null && _start == null) {
                toast(
                  context,
                  'Add a start time first, or clear the end time.',
                );
                return;
              }
              if (_end != null && _mins(_end!) <= _mins(_start!)) {
                toast(context, 'The end time must be after the start time.');
                return;
              }
              adminState.scheduleWork(
                WorkItem(
                    date: _date,
                    endDate: _endDate,
                    time: _timeLabel(context),
                    title: _title.text.trim(),
                    where: _where,
                    kind: const [
                      AdminEventKind.repair,
                      AdminEventKind.maintenance,
                      AdminEventKind.inspection,
                      AdminEventKind.modification,
                    ][_kind],
                    cost: _num(_cost),
                  )
                  ..tenantPays = _tenantPays
                  ..charge = _tenantPays ? _num(_charge) : 0,
              );
              popOnce(context);
              toast(
                context,
                _tenantPays
                    ? 'Scheduled. A payment request was sent to ${payer!.name}.'
                    : 'Scheduled. It is now on the calendar.',
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A label above a field.
class _FieldBlock extends StatelessWidget {
  const _FieldBlock(this.label, this.child);
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [FieldLabel(label), child],
  );
}

/// A tappable field that opens a date or time picker, with an optional clear
/// button for values that can be left empty.
class _Pick extends StatelessWidget {
  const _Pick(this.icon, this.text, this.onTap, {this.onClear});
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          prefixIcon: Icon(icon, size: 18, color: AppColors.gold600),
          suffixIcon: onClear == null
              ? null
              : IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.close,
                    size: 16,
                    color: AppColors.slate400,
                  ),
                  onPressed: onClear,
                ),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, color: AppColors.green800),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
