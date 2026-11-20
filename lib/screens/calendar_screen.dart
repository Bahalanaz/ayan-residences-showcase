import 'package:flutter/material.dart';

import '../admin/admin_state.dart' show adminState;
import '../state/app_state.dart';
import '../state/demo.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart' show TabBody;

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
const _shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Month calendar showing repair visits, building maintenance, rent due dates
/// and notices. Tap a day to list what happens on it.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month = DateTime(appState.today.year, appState.today.month);
  late DateTime _selected = appState.today;

  bool _wholeMonth = false;

  void _shift(int by) =>
      setState(() => _month = DateTime(_month.year, _month.month + by));

  /// The tenant's own calendar items plus what is on record for them:
  /// work at their unit or building, rent due dates and cheque dates.
  List<CalendarEvent> _allEvents() => [
        ...appState.events,
        if (!demoData) ...adminState.tenantEvents(appState.currentTenant),
      ];

  List<CalendarEvent> _eventsOn(DateTime d) => _allEvents().where((e) => _sameDay(e.date, d)).toList();

  /// Everything scheduled in the month on screen, grouped by day.
  List<Widget> _monthSchedule() {
    final all = _allEvents()
        .where((e) => e.date.year == _month.year && e.date.month == _month.month)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (all.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text('Nothing scheduled this month.',
                style: TextStyle(color: AppColors.slate300)),
          ),
        ),
      ];
    }
    final out = <Widget>[];
    DateTime? last;
    for (final e in all) {
      if (last == null || !_sameDay(last, e.date)) {
        out.add(Text(
            '${_weekdayNames[e.date.weekday - 1]}, ${_shortMonths[e.date.month - 1]} ${e.date.day}'
                .toUpperCase(),
            style: const TextStyle(
                color: AppColors.gold400,
                fontSize: 13,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800)));
        last = e.date;
      }
      out.add(_EventTile(e));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([appState, adminState]),
      builder: (context, _) {
        final today = appState.today;
        final events = _eventsOn(_selected);
        final isToday = _sameDay(_selected, today);
        return TabBody(children: [
          const ScreenHeader('Calendar', subtitle: 'Repairs, maintenance and due dates'),
          Row(children: [
            IconButton(
              onPressed: () => _shift(-1),
              icon: const Icon(Icons.chevron_left, color: Colors.white),
            ),
            Expanded(
              child: Text('${_monthNames[_month.month - 1].toUpperCase()} ${_month.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w800)),
            ),
            IconButton(
              onPressed: () => _shift(1),
              icon: const Icon(Icons.chevron_right, color: Colors.white),
            ),
          ]),
          MonthPanel(
            month: _month,
            today: today,
            selected: _selected,
            hasEvents: (d) => _eventsOn(d).isNotEmpty,
            countOn: (d) => _eventsOn(d).length,
            onSelect: (d) => setState(() => _selected = d),
          ),
          SegmentedTabs(
            labels: const ['Selected day', 'Whole month'],
            index: _wholeMonth ? 1 : 0,
            onChanged: (i) => setState(() => _wholeMonth = i == 1),
          ),
          if (!_wholeMonth) ...[
            Row(children: [
              Text(
                  isToday
                      ? 'TODAY'
                      : '${_weekdayNames[_selected.weekday - 1]}, ${_shortMonths[_selected.month - 1]} ${_selected.day}'
                          .toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.gold400,
                      fontSize: 13,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800)),
            ]),
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('Nothing scheduled on this day.',
                      style: TextStyle(color: AppColors.slate300)),
                ),
              ),
            for (final e in events) _EventTile(e),
          ] else
            ..._monthSchedule(),
        ]);
      },
    );
  }
}

class MonthPanel extends StatelessWidget {
  const MonthPanel({
    super.key,
    required this.month,
    required this.today,
    required this.selected,
    required this.hasEvents,
    required this.countOn,
    required this.onSelect,
  });
  final DateTime month, today, selected;
  final bool Function(DateTime) hasEvents;
  final int Function(DateTime) countOn;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday % 7; // Sunday-first grid
    final cells = <DateTime?>[
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= daysInMonth; d++) DateTime(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.green600, AppColors.green900],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.gold500.withValues(alpha: .35)),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: Column(children: [
        Row(children: [
          for (final l in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
            Expanded(
              child: Center(
                child: Text(l,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        GridView.count(
          padding: EdgeInsets.zero,
          crossAxisCount: 7,
          childAspectRatio: .86,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final d in cells)
              if (d == null)
                const SizedBox.shrink()
              else
                DayCell(
                  d,
                  isToday: _sameDay(d, today),
                  isSelected: _sameDay(d, selected),
                  dots: countOn(d).clamp(0, 3),
                  onTap: () => onSelect(d),
                ),
          ],
        ),
      ]),
    );
  }
}

class DayCell extends StatelessWidget {
  const DayCell(this.date, {
    super.key,
    required this.isToday,
    required this.isSelected,
    required this.dots,
    required this.onTap,
  });
  final DateTime date;
  final bool isToday, isSelected;
  final int dots;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? AppColors.gold500 : null,
            border: !isSelected && isToday
                ? Border.all(color: AppColors.gold400, width: 1.5)
                : null,
          ),
          child: Text('${date.day}',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected || isToday ? FontWeight.w800 : FontWeight.w500,
                  color: isSelected ? AppColors.green900 : Colors.white)),
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 5,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < dots; i++)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: const BoxDecoration(
                    color: AppColors.gold400, shape: BoxShape.circle),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile(this.e);
  final CalendarEvent e;

  @override
  Widget build(BuildContext context) {
    final (label, pill, icon) = switch (e.kind) {
      EventKind.repair => ('Repair', Pill.pending('REPAIR'), Icons.build_rounded),
      EventKind.maintenance =>
        ('Maintenance', Pill.info('MAINTENANCE'), Icons.handyman_rounded),
      EventKind.rent => ('Rent', Pill.urgent('RENT DUE'), Icons.account_balance_wallet_rounded),
      EventKind.notice => ('Notice', Pill.neutral('NOTICE'), Icons.campaign_rounded),
    };
    assert(label.isNotEmpty);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 66,
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(e.time,
              style: const TextStyle(
                  color: AppColors.slate300, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ),
      Expanded(
        child: AppCard(
          radius: 18,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            IconBadge(icon, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.green800)),
                const SizedBox(height: 2),
                Text(e.subtitle,
                    style: const TextStyle(fontSize: 12, color: AppColors.slate500)),
                const SizedBox(height: 6),
                pill,
              ]),
            ),
          ]),
        ),
      ),
    ]);
  }
}
