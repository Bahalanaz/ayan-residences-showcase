import 'package:flutter/material.dart';

import '../../screens/calendar_screen.dart' show MonthPanel;
import '../../screens/shell.dart' show TabBody;
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../admin_state.dart';

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
const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _shortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// One calendar for the whole business: repairs, maintenance, rent due dates,
/// lease endings and guest stays across apartments, condos and villas.
class CalendarAdminScreen extends StatefulWidget {
  const CalendarAdminScreen({super.key});
  @override
  State<CalendarAdminScreen> createState() => _CalendarAdminScreenState();
}

class _CalendarAdminScreenState extends State<CalendarAdminScreen> {
  static const _filters = ['All', 'Apartment', 'Condo', 'Villa'];

  late DateTime _month = DateTime(appState.today.year, appState.today.month);
  late DateTime _selected = appState.today;
  int _filter = 0;
  bool _wholeMonth = false;

  /// 0 all, 1 maintenance (and inspections), 2 repairs, 3 condo
  /// check-ins and check-outs, 4 contracts and leases.
  int _kind = 0;

  bool _kindMatches(AdminEvent e) => switch (_kind) {
    1 =>
      e.kind == AdminEventKind.maintenance ||
          e.kind == AdminEventKind.inspection,
    2 =>
      e.kind == AdminEventKind.repair || e.kind == AdminEventKind.modification,
    3 => e.kind == AdminEventKind.stay,
    4 => e.kind == AdminEventKind.lease,
    _ => true,
  };

  void _shift(int by) =>
      setState(() => _month = DateTime(_month.year, _month.month + by));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final today = appState.today;
        final all = adminState.calendarEvents.where(_kindMatches).where((e) {
          if (_filter == 0) return true;
          return adminState.typeOfEvent(e) == _filters[_filter];
        }).toList();
        List<AdminEvent> on(DateTime d) =>
            all.where((e) => _sameDay(e.date, d)).toList()
              ..sort((a, b) => a.time.compareTo(b.time));
        final events = on(_selected);

        /// Everything in the month on screen, grouped by day.
        List<Widget> monthList() {
          final inMonth =
              all
                  .where(
                    (e) =>
                        e.date.year == _month.year &&
                        e.date.month == _month.month,
                  )
                  .toList()
                ..sort((a, b) => a.date.compareTo(b.date));
          if (inMonth.isEmpty) {
            return const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Nothing scheduled this month.',
                    style: TextStyle(color: AppColors.slate300),
                  ),
                ),
              ),
            ];
          }
          final out = <Widget>[];
          DateTime? last;
          for (final e in inMonth) {
            if (last == null || !_sameDay(last, e.date)) {
              out.add(
                Text(
                  '${_weekdayNames[e.date.weekday - 1]}, ${_shortMonths[e.date.month - 1]} ${e.date.day}'
                      .toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.gold400,
                    fontSize: 13,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );
              last = e.date;
            }
            out.add(_EventTile(e));
          }
          return out;
        }

        final isToday = _sameDay(_selected, today);
        return TabBody(
          children: [
            const ScreenHeader('Calendar'),
            // What to list under the calendar: the picked day, or the month.
            SegmentedTabs(
              labels: const ['Selected day', 'Whole month'],
              index: _wholeMonth ? 1 : 0,
              onChanged: (i) => setState(() => _wholeMonth = i == 1),
            ),
            SegmentedTabs(
              labels: const ['All', 'Apartments', 'Condo', 'Villa'],
              index: _filter,
              onChanged: (i) => setState(() => _filter = i),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: () => _shift(-1),
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                ),
                Expanded(
                  child: Text(
                    '${_monthNames[_month.month - 1].toUpperCase()} ${_month.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _shift(1),
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                ),
              ],
            ),
            MonthPanel(
              month: _month,
              today: today,
              selected: _selected,
              hasEvents: (d) => on(d).isNotEmpty,
              countOn: (d) => on(d).length,
              onSelect: (d) => setState(() => _selected = d),
            ),
            // Which kind of event to show (dots and list follow it).
            SegmentedTabs(
              labels: const [
                'All',
                'Maintenance',
                'Repairs',
                'Check-in/out',
                'Leases',
              ],
              index: _kind,
              onChanged: (i) => setState(() => _kind = i),
            ),
            if (!_wholeMonth) ...[
              Row(
                children: [
                  Text(
                    isToday
                        ? 'TODAY'
                        : '${_weekdayNames[_selected.weekday - 1]}, ${_shortMonths[_selected.month - 1]} ${_selected.day}'
                              .toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.gold400,
                      fontSize: 13,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              if (events.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Nothing scheduled on this day.',
                      style: TextStyle(color: AppColors.slate300),
                    ),
                  ),
                ),
              for (final e in events) _EventTile(e),
            ] else
              ...monthList(),
          ],
        );
      },
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile(this.e);
  final AdminEvent e;

  @override
  Widget build(BuildContext context) {
    final (pill, icon) = switch (e.kind) {
      AdminEventKind.repair => (Pill.pending('REPAIR'), Icons.build_rounded),
      AdminEventKind.maintenance => (
        Pill.info('MAINTENANCE'),
        Icons.handyman_rounded,
      ),
      AdminEventKind.inspection => (
        Pill.neutral('INSPECTION'),
        Icons.fact_check_outlined,
      ),
      AdminEventKind.modification => (
        Pill.pending('MODIFICATION'),
        Icons.architecture_rounded,
      ),
      AdminEventKind.rent => (
        Pill.urgent('RENT DUE'),
        Icons.account_balance_wallet_rounded,
      ),
      AdminEventKind.lease => (
        Pill.neutral('LEASE END'),
        Icons.event_busy_rounded,
      ),
      AdminEventKind.stay => (Pill.verified('STAY'), Icons.luggage_rounded),
    };
    final type = adminState.typeOfEvent(e);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 66,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              e.time,
              style: const TextStyle(
                color: AppColors.slate300,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Expanded(
          child: AppCard(
            radius: 18,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                IconBadge(icon, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.green800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${e.unit} · $type${e.detail == null ? '' : ' · ${e.detail}'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.slate500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      pill,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
