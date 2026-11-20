import 'package:flutter/material.dart';

import '../../state/app_state.dart' show appState;
import '../../state/sync.dart' show Sync;
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/chat_view.dart' show chooseDocument;
import '../admin_state.dart';

const _months = [
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
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Fri, Nov 14 · 2:00 PM"
String stayMoment(DateTime d) =>
    '${_days[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day} · ${clockTime(d)}';

/// The unit's Scheduling tab. For a condo: guest check-ins and check-outs,
/// entered by the admin (condo guests have no app account). For other
/// units: the repairs and maintenance scheduled there.
class UnitScheduling extends StatelessWidget {
  const UnitScheduling(this.u, {super.key});
  final UnitRec u;

  @override
  Widget build(BuildContext context) {
    return u.type == 'Condo' ? _CondoSchedule(u) : _WorkSchedule(u);
  }
}

class _CondoSchedule extends StatelessWidget {
  const _CondoSchedule(this.u);
  final UnitRec u;

  @override
  Widget build(BuildContext context) {
    // By day: the guest whose nights include tonight is "staying now".
    final now = adminState.currentBooking(u.name);
    final next = adminState.nextBooking(u.name);
    final all = adminState.bookingsFor(u.name);
    final current = [?now];
    final upcoming = next == null
        ? <Booking>[]
        : all.where((b) => !b.checkIn.isBefore(next.checkIn)).toList();
    final past = all
        .where((b) => b != now && !upcoming.contains(b))
        .toList()
        .reversed
        .toList();
    void add() => showAppSheet(
      context,
      title: 'New booking',
      builder: (_) => BookingForm(u),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        GoldButton(
          label: 'Schedule a stay',
          icon: Icons.add_rounded,
          onPressed: add,
        ),
        if (all.isEmpty) ...[
          const SizedBox(height: 16),
          EmptyState(
            icon: Icons.event_available_outlined,
            title: 'No stays yet',
            message: 'Schedule the first guest to start tracking this condo.',
            actionLabel: 'Schedule a stay',
            onAction: add,
            onDark: false,
          ),
        ],
        if (current.isNotEmpty) ...[
          const _Head('Staying now'),
          for (final b in current) _BookingCard(u, b, highlight: true),
        ],
        if (upcoming.isNotEmpty) ...[
          const _Head('Upcoming'),
          for (final b in upcoming) _BookingCard(u, b),
        ],
        if (past.isNotEmpty) ...[
          const _Head('Past stays'),
          for (final b in past) _BookingCard(u, b, faded: true),
        ],
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: AppColors.green800,
      ),
    ),
  );
}

class _BookingCard extends StatelessWidget {
  const _BookingCard(
    this.u,
    this.b, {
    this.highlight = false,
    this.faded = false,
  });
  final UnitRec u;
  final Booking b;
  final bool highlight, faded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: faded ? .7 : 1,
        child: AppCard(
          radius: 18,
          // A past stay is a record: open its details, not the edit form.
          onTap: () => upcomingOrNow(b)
              ? showAppSheet(
                  context,
                  title: 'Edit booking',
                  builder: (_) => BookingForm(u, existing: b),
                )
              : showAppSheet(
                  context,
                  title: 'Stay details',
                  builder: (_) => _DayDetails(
                    u,
                    DateTime(b.checkIn.year, b.checkIn.month, b.checkIn.day),
                    b,
                  ),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      b.guest.isEmpty ? 'Guest' : b.guest,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green800,
                      ),
                    ),
                  ),
                  if (highlight) Pill.verified('IN HOUSE'),
                ],
              ),
              const SizedBox(height: 10),
              _Moment(Icons.login_rounded, 'Check-in', stayMoment(b.checkIn)),
              const SizedBox(height: 6),
              _Moment(
                Icons.logout_rounded,
                'Check-out',
                stayMoment(b.checkOut),
              ),
              const Divider(height: 20),
              Text(
                '${b.nights} ${b.nights == 1 ? 'night' : 'nights'} · ${b.guests} ${b.guests == 1 ? 'guest' : 'guests'}'
                '${b.amount > 0 ? ' · ${peso(b.amount)}' : ''}'
                '${b.deposit > 0 ? ' · deposit ${peso(b.deposit)}' : ''}'
                '${b.phone.isEmpty ? '' : ' · ${b.phone}'}',
                style: const TextStyle(fontSize: 12, color: AppColors.slate500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Moment extends StatelessWidget {
  const _Moment(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: AppColors.gold600),
      const SizedBox(width: 8),
      SizedBox(
        width: 74,
        child: Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: AppColors.slate500),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppColors.green800,
          ),
        ),
      ),
    ],
  );
}

/// Add or edit a condo stay: guest, check-in and check-out (date and time),
/// how many guests and the amount (condo stays are paid before arrival).
class BookingForm extends StatefulWidget {
  const BookingForm(this.u, {super.key, this.existing, this.startDay});
  final UnitRec u;
  final Booking? existing;

  /// For a new stay picked on the calendar: the check-in day.
  final DateTime? startDay;
  @override
  State<BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends State<BookingForm> {
  final _key = GlobalKey<FormState>();
  late final _guest = TextEditingController(text: widget.existing?.guest ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');

  /// The guest's ID and other files for this stay.
  late final List<GuestFile> _files = [...?widget.existing?.files];

  /// The unit's deposit by default (a new stay), or what was entered.
  late final _deposit = TextEditingController(
    text: (widget.existing?.deposit ?? widget.u.deposit).toStringAsFixed(0),
  );
  late final _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : widget.existing!.amount.toStringAsFixed(0),
  );
  late int _guests = widget.existing?.guests ?? 1;

  // Default stay: from tomorrow 2:00 PM to the day after at 12:00 PM.
  late DateTime _in =
      widget.existing?.checkIn ??
      (widget.startDay == null
          ? null
          : DateTime(
              widget.startDay!.year,
              widget.startDay!.month,
              widget.startDay!.day,
              14,
            )) ??
      DateTime(
        appState.today.year,
        appState.today.month,
        appState.today.day + 1,
        14,
      );
  late DateTime _out =
      widget.existing?.checkOut ??
      DateTime(_in.year, _in.month, _in.day + 1, 12);

  /// Set by hand; otherwise the amount follows nights x nightly rate.
  bool _amountEdited = false;

  @override
  void initState() {
    super.initState();
    _amountEdited = widget.existing != null;
    _syncAmount();
  }

  @override
  void dispose() {
    _guest.dispose();
    _phone.dispose();
    _amount.dispose();
    _deposit.dispose();
    super.dispose();
  }

  int get _nights => DateTime(
    _out.year,
    _out.month,
    _out.day,
  ).difference(DateTime(_in.year, _in.month, _in.day)).inDays;

  /// The unit's rate for one night (a weekly or monthly rate is spread over
  /// 7 or 30 nights).
  double get _perNight => switch (widget.u.rateUnit) {
    'week' => widget.u.rate / 7,
    'month' => widget.u.rate / 30,
    'year' => widget.u.rate / 365,
    _ => widget.u.rate,
  };

  double get _autoAmount =>
      (_perNight * (_nights < 1 ? 1 : _nights)).roundToDouble();

  /// Amount = nights x nightly rate, unless the admin typed their own.
  void _syncAmount() {
    if (_amountEdited) return;
    _amount.text = _autoAmount.toStringAsFixed(0);
  }

  /// Today, so past days can't be booked. Check-out can't be before
  /// check-in. An existing past stay keeps its own dates pickable.
  DateTime _earliest(bool checkIn) {
    final t = appState.today;
    var first = DateTime(t.year, t.month, t.day);
    if (!checkIn) {
      first = DateTime(_in.year, _in.month, _in.day).isAfter(first)
          ? DateTime(_in.year, _in.month, _in.day)
          : first;
    }
    final cur = checkIn ? _in : _out;
    final day = DateTime(cur.year, cur.month, cur.day);
    return day.isBefore(first) ? day : first;
  }

  /// True when another stay in this unit already has the night of [day].
  bool _bookedNight(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return adminState.bookingsFor(widget.u.name).any((b) {
      if (b == widget.existing) return false;
      final a = DateTime(b.checkIn.year, b.checkIn.month, b.checkIn.day);
      final z = DateTime(b.checkOut.year, b.checkOut.month, b.checkOut.day);
      return !d.isBefore(a) && d.isBefore(z);
    });
  }

  Future<void> _pick(bool checkIn) async {
    final cur = checkIn ? _in : _out;
    final first = _earliest(checkIn);
    // Nights other guests already have are greyed out. For check-in the
    // night of that day must be free; for check-out, the night before it.
    bool free(DateTime day) =>
        !_bookedNight(checkIn ? day : day.subtract(const Duration(days: 1)));
    // The picker must open on a day that can be picked.
    var start = DateTime(cur.year, cur.month, cur.day);
    if (start.isBefore(first)) start = first;
    var guard = 0;
    while (!free(start) && guard++ < 730) {
      start = start.add(const Duration(days: 1));
    }
    final d = await showDialog<DateTime>(
      context: context,
      builder: (_) => _StayDayPicker(
        title: checkIn ? 'Check-in day' : 'Check-out day',
        initial: start,
        first: first,
        booked: (day) => !free(day),
      ),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      initialEntryMode: TimePickerEntryMode.input,
      context: context,
      initialTime: TimeOfDay.fromDateTime(cur),
    );
    if (!mounted) return;
    final picked = DateTime(
      d.year,
      d.month,
      d.day,
      t?.hour ?? cur.hour,
      t?.minute ?? cur.minute,
    );
    setState(() {
      if (checkIn) {
        final length = _out.difference(_in);
        _in = picked;
        // Keep the stay length when the arrival moves.
        if (!_out.isAfter(_in)) {
          _out = _in.add(length.isNegative ? const Duration(days: 1) : length);
        }
      } else {
        _out = picked;
      }
      _syncAmount();
    });
  }

  /// A problem with the booking, in a window over the form (not a message
  /// hidden behind it).
  Future<void> _problem(String title, String message) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.green800,
        ),
      ),
      content: Text(
        message,
        style: const TextStyle(height: 1.4, color: AppColors.slate600),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold500,
            foregroundColor: AppColors.green900,
          ),
          onPressed: () => popOnce(ctx),
          child: const Text(
            'OK',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );

  /// The earliest check-in, from the end of [clash] on, that fits a stay as
  /// long as the one entered without running into another guest.
  DateTime _earliestFree(Booking clash) {
    final length = _out.difference(_in);
    var start = clash.checkOut;
    for (var i = 0; i < 50; i++) {
      final next = adminState.clashingBooking(
        widget.u.name,
        start,
        start.add(length),
        except: widget.existing,
      );
      if (next == null) break;
      start = next.checkOut;
    }
    return start;
  }

  /// The times overlap another guest: say whose stay and until when, and
  /// offer the earliest time the same stay would fit.
  Future<void> _clashWindow(Booking clash) async {
    final start = _earliestFree(clash);
    final end = start.add(_out.difference(_in));
    final use = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Not available',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.green800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Another guest${clash.guest.isEmpty ? '' : ' (${clash.guest})'} is booked from '
              '${stayMoment(clash.checkIn)} to ${stayMoment(clash.checkOut)}.',
              style: const TextStyle(height: 1.4, color: AppColors.slate600),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.gold500),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'EARLIEST AVAILABLE',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w800,
                      color: AppColors.gold700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stayMoment(start),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.green800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => popOnce(ctx, false),
            child: const Text(
              'Change it myself',
              style: TextStyle(color: AppColors.slate500),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold500,
              foregroundColor: AppColors.green900,
            ),
            onPressed: () => popOnce(ctx, true),
            child: const Text(
              'Use this time',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (use == true && mounted) {
      setState(() {
        _in = start;
        // Keep the check-out entered if it still comes after; otherwise keep
        // the same length of stay.
        if (!_out.isAfter(start)) _out = end;
        _syncAmount();
      });
    }
  }

  void _save() {
    if (!_key.currentState!.validate()) return;
    if (!_out.isAfter(_in)) {
      _problem(
        'Check-out is too early',
        'Check-out must be after check-in (${stayMoment(_in)}).',
      );
      return;
    }
    final today = DateTime(
      appState.today.year,
      appState.today.month,
      appState.today.day,
    );
    if (widget.existing == null && _in.isBefore(today)) {
      _problem(
        'That day has passed',
        'Choose today or a later day for check-in.',
      );
      return;
    }
    final clash = adminState.clashingBooking(
      widget.u.name,
      _in,
      _out,
      except: widget.existing,
    );
    if (clash != null) {
      _clashWindow(clash);
      return;
    }
    adminState.saveBooking(
      widget.existing,
      Booking(
        id: '',
        unit: widget.u.name,
        guest: _guest.text.trim(),
        phone: _phone.text.trim(),
        guests: _guests,
        checkIn: _in,
        checkOut: _out,
        amount: double.tryParse(_amount.text) ?? 0,
        deposit: double.tryParse(_deposit.text) ?? 0,
        files: _files,
      ),
    );
    popOnce(context);
    toast(
      context,
      widget.existing == null
          ? 'Stay scheduled. It is on the calendar.'
          : 'Booking updated.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.existing;
    return Form(
      key: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('Guest name'),
          TextFormField(
            controller: _guest,
            textCapitalization: TextCapitalization.words,
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Enter the guest\'s name' : null,
          ),
          const SizedBox(height: 12),
          _WhenField(
            Icons.login_rounded,
            'Check-in',
            stayMoment(_in),
            () => _pick(true),
          ),
          const SizedBox(height: 10),
          _WhenField(
            Icons.logout_rounded,
            'Check-out',
            stayMoment(_out),
            () => _pick(false),
          ),
          const SizedBox(height: 6),
          Text(
            _out.isAfter(_in)
                ? '$_nights ${_nights == 1 ? 'night' : 'nights'}'
                : 'Check-out must be after check-in',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _out.isAfter(_in) ? AppColors.slate500 : AppColors.red,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('Guests'),
                    Row(
                      children: [
                        IconButton.outlined(
                          onPressed: _guests > 1
                              ? () => setState(() => _guests--)
                              : null,
                          icon: const Icon(Icons.remove_rounded, size: 18),
                        ),
                        Expanded(
                          child: Text(
                            '$_guests',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.green800,
                            ),
                          ),
                        ),
                        IconButton.outlined(
                          onPressed: () => setState(() => _guests++),
                          icon: const Icon(Icons.add_rounded, size: 18),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('Amount (₱)'),
                    TextFormField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() => _amountEdited = true),
                    ),
                    // How it was worked out, or a way back to it after typing.
                    if (!_amountEdited)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${peso(_perNight)} × $_nights ${_nights == 1 ? 'night' : 'nights'}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.slate500,
                          ),
                        ),
                      )
                    else
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 28),
                        ),
                        onPressed: () => setState(() {
                          _amountEdited = false;
                          _syncAmount();
                        }),
                        child: Text(
                          'Use rate (${peso(_autoAmount)})',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.gold700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const FieldLabel('Security deposit (₱)'),
          TextFormField(
            controller: _deposit,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Returned at check-out',
            ),
          ),
          const SizedBox(height: 12),
          const FieldLabel('Contact number (optional)'),
          TextFormField(controller: _phone, keyboardType: TextInputType.phone),
          const SizedBox(height: 12),
          // The guest's ID and other files for this stay, kept on
          // record after the stay.
          const FieldLabel('Guest files (ID, booking slip)'),
          for (final g in _files)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => viewGuestFile(context, g),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: g.isPdf || g.bytes == null
                              ? const IconBadge(
                                  Icons.picture_as_pdf_rounded,
                                  size: 44,
                                )
                              : Image.memory(
                                  g.bytes!,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const IconBadge(
                                    Icons.image_outlined,
                                    size: 44,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            g.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.green800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: () => setState(() => _files.remove(g)),
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppColors.slate400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.green800,
              side: const BorderSide(color: AppColors.gold500),
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () async {
              final file = await chooseDocument(context);
              if (file == null || !mounted) return;
              setState(
                () => _files.add(
                  GuestFile(
                    label: file.$1,
                    fileName: file.$1,
                    bytes: file.$2,
                    added: appState.today,
                  ),
                ),
              );
            },
            icon: const Icon(
              Icons.upload_file_rounded,
              color: AppColors.gold600,
            ),
            label: Text(
              _files.isEmpty ? 'Upload a file' : 'Add another file',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 16),
          GoldButton(
            label: b == null ? 'Schedule stay' : 'Save changes',
            onPressed: _save,
          ),
          if (b != null)
            Center(
              child: TextButton.icon(
                onPressed: () {
                  final why = adminState.whyKeepBooking(b);
                  if (why != null) {
                    toast(context, why);
                    return;
                  }
                  adminState.removeBooking(b);
                  popOnce(context);
                  toast(context, 'Booking removed.');
                },
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppColors.red,
                ),
                label: const Text(
                  'Remove booking',
                  style: TextStyle(
                    color: AppColors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WhenField extends StatelessWidget {
  const _WhenField(this.icon, this.label, this.value, this.onTap);
  final IconData icon;
  final String label, value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.gold600),
          const SizedBox(width: 10),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.edit_calendar_outlined,
            size: 18,
            color: AppColors.gold600,
          ),
        ],
      ),
    ),
  );
}

/// Apartments and villas: the work scheduled in this unit.
class _WorkSchedule extends StatelessWidget {
  const _WorkSchedule(this.u);
  final UnitRec u;

  @override
  Widget build(BuildContext context) {
    final work = adminState.workItems.where((w) => w.where == u.name).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        if (work.isEmpty)
          const EmptyState(
            icon: Icons.event_available_outlined,
            title: 'Nothing scheduled',
            message: 'Work you schedule for this unit (Dashboard → Scheduling) shows here.',
            onDark: false,
          ),
        for (final w in work)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              radius: 18,
              child: Row(
                children: [
                  IconBadge(
                    w.kind == AdminEventKind.repair
                        ? Icons.build_rounded
                        : w.kind == AdminEventKind.modification
                        ? Icons.architecture_rounded
                        : w.kind == AdminEventKind.inspection
                        ? Icons.fact_check_outlined
                        : Icons.handyman_rounded,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          w.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.green800,
                            decoration: w.done
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        Text(
                          '${_days[w.date.weekday - 1]}, ${_months[w.date.month - 1]} ${w.date.day} · ${w.time}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.slate500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (w.done) Pill.verified('DONE'),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A condo's operating costs: this month's total, what came in from stays,
/// every cost entered, and a form to add one.
class CostsSheet extends StatefulWidget {
  const CostsSheet(this.u, {super.key});
  final UnitRec u;
  @override
  State<CostsSheet> createState() => _CostsSheetState();
}

class _CostsSheetState extends State<CostsSheet> {
  final _title = TextEditingController();
  String _type = adminState.costTypes.first;
  static const _other = 'Others';
  static const _addNew = '+ add new cost option';

  Future<void> _newType() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewCostType(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    setState(() => _type = adminState.addCostType(name));
  }

  final _amount = TextEditingController();
  DateTime _date = appState.today;

  /// The month whose costs are listed; starts on the current one.
  DateTime _month = DateTime(appState.today.year, appState.today.month);

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

  Future<void> _pickMonth() async {
    final picked = await showAppSheet<DateTime>(
      context,
      title: 'Choose a month',
      builder: (_) => _MonthPicker(selected: _month),
    );
    if (picked != null) setState(() => _month = picked);
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _add() {
    final amount = double.tryParse(_amount.text) ?? 0;
    final title = _type == _other ? _title.text.trim() : _type;
    if (title.isEmpty || amount <= 0) {
      showProblem(
        context,
        'Missing details',
        'Enter what it was for and the amount.',
      );
      return;
    }
    adminState.addCost(
      widget.u.name,
      CostEntry(title: title, amount: amount, date: _date),
    );
    setState(() => _month = DateTime(_date.year, _date.month));
    _title.clear();
    _amount.clear();
    FocusScope.of(context).unfocus();
    toast(context, 'Cost added.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final u = widget.u;
        final list = adminState
            .costsFor(u.name)
            .where(
              (c) => c.date.year == _month.year && c.date.month == _month.month,
            )
            .toList();
        final total = list.fold(0.0, (n, c) => n + c.amount);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FieldLabel('Add a cost'),
            DropdownField(
              title: 'What was it for?',
              value: _type,
              options: [
                for (final t in adminState.costTypes)
                  PickerOption(value: t, label: t),
                const PickerOption(
                  value: _other,
                  label: _other,
                  subtitle: 'Type what it was for',
                ),
                const PickerOption(
                  value: _addNew,
                  label: 'Add a new option',
                  subtitle: 'Saved to this list for next time',
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
            if (_type == _other) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'What was it for?'),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Amount (₱)'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2035),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                  icon: const Icon(
                    Icons.event_outlined,
                    size: 18,
                    color: AppColors.gold600,
                  ),
                  label: Text(
                    '${_months[_date.month - 1]} ${_date.day}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.green800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            GoldButton(
              label: 'Add cost',
              icon: Icons.add_rounded,
              onPressed: _add,
            ),
            const SizedBox(height: 16),
            // Which month's costs to show: arrows step a month, the middle
            // opens a month and year picker.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.slate200),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed: () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1),
                    ),
                    icon: const Icon(
                      Icons.chevron_left_rounded,
                      color: AppColors.gold600,
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _pickMonth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            Text(
                              '${_monthNames[_month.month - 1]} ${_month.year}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.green800,
                              ),
                            ),
                            Text(
                              '${list.length} ${list.length == 1 ? 'cost' : 'costs'} · ${peso(total)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.slate500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed: () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1),
                    ),
                    icon: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.gold600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No costs in ${_monthNames[_month.month - 1]} ${_month.year}.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.slate500,
                  ),
                ),
              ),
            for (final c in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  c.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
                subtitle: Text(
                  '${_months[c.date.month - 1]} ${c.date.day}, ${c.date.year}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      peso(c.amount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.green800,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => adminState.removeCost(u.name, c),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppColors.slate400,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Pick a month: the year with arrows, then one of twelve months.
class _MonthPicker extends StatefulWidget {
  const _MonthPicker({required this.selected});
  final DateTime selected;
  @override
  State<_MonthPicker> createState() => _MonthPickerState();
}

class _MonthPickerState extends State<_MonthPicker> {
  late int _year = widget.selected.year;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous year',
              onPressed: () => setState(() => _year--),
              icon: const Icon(
                Icons.chevron_left_rounded,
                color: AppColors.gold600,
              ),
            ),
            Expanded(
              child: Text(
                '$_year',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next year',
              onPressed: () => setState(() => _year++),
              icon: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.gold600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.6,
          children: [
            for (var m = 1; m <= 12; m++)
              Builder(
                builder: (context) {
                  final on =
                      _year == widget.selected.year &&
                      m == widget.selected.month;
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => popOnce(context, DateTime(_year, m)),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: on ? goldGradient : null,
                        color: on ? null : AppColors.slate50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: on ? AppColors.gold600 : AppColors.slate200,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _months[m - 1],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: on ? AppColors.green900 : AppColors.green800,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Opens a guest file full screen: a photo with pinch-zoom, or a PDF's name.
Future<void> viewGuestFile(BuildContext context, GuestFile f) async {
  // Downloaded the first time it is opened.
  if (f.bytes == null) {
    await Sync.fetch([f]);
    if (!context.mounted) return;
    if (f.bytes == null) {
      toast(
        context,
        'Could not open the file. Check your internet connection.',
      );
      return;
    }
  }
  await showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: f.isPdf ? Colors.white : Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: f.isPdf
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 56,
                    color: AppColors.gold600,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    f.fileName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.green800,
                    ),
                  ),
                ],
              ),
            )
          : InteractiveViewer(
              maxScale: 5,
              child: Image.memory(
                f.bytes!,
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(40),
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
            ),
    ),
  );
}

/// Name a new kind of operational cost (saved for next time).
class _NewCostType extends StatefulWidget {
  const _NewCostType();
  @override
  State<_NewCostType> createState() => _NewCostTypeState();
}

class _NewCostTypeState extends State<_NewCostType> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    title: const Text(
      'New cost option',
      style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.green800),
    ),
    content: TextField(
      controller: _name,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        hintText: 'e.g. Laundry, Gas, Pest control',
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
        child: const Text('Add', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
    ],
  );
}

/// A condo's month calendar on Overview: nights already booked (upcoming in
/// gold, the guest staying now in green, past in grey) and free nights.
/// Tap a booked night to open that stay, or a free one to book it.
class CondoCalendar extends StatefulWidget {
  const CondoCalendar(this.u, {super.key});
  final UnitRec u;
  @override
  State<CondoCalendar> createState() => _CondoCalendarState();
}

/// Soft red for stays that are over, so they stand apart from free days.
const _pastRed = Color(0xFFF4C7C3);

class _CondoCalendarState extends State<CondoCalendar> {
  late DateTime _month = DateTime(appState.today.year, appState.today.month);

  /// The day whose stay is shown under the calendar; today at first.
  late DateTime _selected = DateTime(
    appState.today.year,
    appState.today.month,
    appState.today.day,
  );

  static const _names = [
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

  /// The stay on day [d]: from its check-in day through its check-out day
  /// (the guest is still there the morning they leave). On a changeover day
  /// the one leaving is shown.
  Booking? _stayOn(DateTime d) =>
      adminState.bookingsFor(widget.u.name).where((b) {
        final a = DateTime(b.checkIn.year, b.checkIn.month, b.checkIn.day);
        final z = DateTime(b.checkOut.year, b.checkOut.month, b.checkOut.day);
        return !d.isBefore(a) && !d.isAfter(z);
      }).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final u = widget.u;
    final t = appState.today;
    final today = DateTime(t.year, t.month, t.day);
    // Green for the guest there today, including on their check-out day.
    final current = adminState.currentBooking(u.name) ?? _stayOn(today);
    final first = DateTime(_month.year, _month.month, 1);
    final daysIn = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday - 1; // Monday first
    var booked = 0;
    for (var day = 1; day <= daysIn; day++) {
      if (_stayOn(DateTime(_month.year, _month.month, day)) != null) booked++;
    }

    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysIn; day++)
        Builder(
          builder: (context) {
            final d = DateTime(_month.year, _month.month, day);
            final stay = _stayOn(d);
            final past = d.isBefore(today);
            final Color? bg = stay == null
                ? null
                : stay == current
                ? AppColors.emerald
                : !upcomingOrNow(stay)
                ? _pastRed
                : AppColors.gold500;
            final fg = stay == null
                ? (past ? AppColors.slate300 : AppColors.green800)
                : (bg == AppColors.gold500
                      ? AppColors.green900
                      : bg == _pastRed
                      ? const Color(0xFF8C2F2B)
                      : Colors.white);
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              // Only booked nights open; booking new stays is on Scheduling.
              onTap: stay == null
                  ? null
                  : () {
                      setState(() => _selected = d);
                      showAppSheet(
                        context,
                        title: 'Stay details',
                        builder: (_) => _DayDetails(u, d, stay),
                      );
                    },
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bg ?? (past ? Colors.transparent : Colors.white),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: d == _selected
                        ? AppColors.green900
                        : d == today
                        ? AppColors.green800
                        : (bg == null && !past
                              ? AppColors.slate200
                              : Colors.transparent),
                    width: d == _selected
                        ? 3
                        : d == today
                        ? 2
                        : 1,
                  ),
                ),
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            );
          },
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Stay calendar',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Previous month',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1),
              ),
              icon: const Icon(
                Icons.chevron_left_rounded,
                color: AppColors.gold600,
              ),
            ),
            Text(
              '${_names[_month.month - 1]} ${_month.year}',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AppColors.green800,
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month + 1),
              ),
              icon: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.gold600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final w in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Text(
                  w,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate400,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 5,
          crossAxisSpacing: 5,
          padding: EdgeInsets.zero,
          children: cells,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _Legend(AppColors.gold500, 'Booked'),
            _Legend(AppColors.emerald, 'Guest in'),
            _Legend(_pastRed, 'Past stay'),
            _Legend(Colors.white, 'Free', border: true),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '$booked of $daysIn days booked in ${_names[_month.month - 1]} · tap a booked day to see it',
          style: const TextStyle(fontSize: 12, color: AppColors.slate500),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label, {this.border = false});
  final Color color;
  final String label;
  final bool border;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: border ? Border.all(color: AppColors.slate300) : null,
        ),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppColors.slate600),
      ),
    ],
  );
}

/// Date picker for a stay, in the app's colours: a dark green header with
/// the chosen date, a cream month grid, the chosen day in gold. Nights other
/// guests already have are shaded and struck through (they can't be picked);
/// past days are faded.
class _StayDayPicker extends StatefulWidget {
  const _StayDayPicker({
    required this.title,
    required this.initial,
    required this.first,
    required this.booked,
  });
  final String title;
  final DateTime initial, first;
  final bool Function(DateTime day) booked;
  @override
  State<_StayDayPicker> createState() => _StayDayPickerState();
}

class _StayDayPickerState extends State<_StayDayPicker> {
  late DateTime _month = DateTime(widget.initial.year, widget.initial.month);
  late DateTime _picked = widget.initial;

  static const _names = [
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

  @override
  Widget build(BuildContext context) {
    final first = DateTime(_month.year, _month.month, 1);
    final daysIn = DateTime(_month.year, _month.month + 1, 0).day;
    final canGoBack = DateTime(
      _month.year,
      _month.month,
    ).isAfter(DateTime(widget.first.year, widget.first.month));
    final t = appState.today;
    final today = DateTime(t.year, t.month, t.day);
    return Dialog(
      backgroundColor: AppColors.slate50,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: what is being picked and the day chosen so far.
          Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            color: AppColors.green800,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: AppColors.gold400,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  stayMoment(_picked).split(' · ').first,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: canGoBack
                          ? () => setState(
                              () => _month = DateTime(
                                _month.year,
                                _month.month - 1,
                              ),
                            )
                          : null,
                      icon: Icon(
                        Icons.chevron_left_rounded,
                        color: canGoBack
                            ? AppColors.gold600
                            : AppColors.slate200,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${_names[_month.month - 1]} ${_month.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.green800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1),
                      ),
                      icon: const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.gold600,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    for (final w in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                      Expanded(
                        child: Text(
                          w,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.gold700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  padding: EdgeInsets.zero,
                  children: [
                    for (var i = 0; i < first.weekday - 1; i++)
                      const SizedBox.shrink(),
                    for (var day = 1; day <= daysIn; day++)
                      Builder(
                        builder: (context) {
                          final d = DateTime(_month.year, _month.month, day);
                          final past = d.isBefore(widget.first);
                          final taken = !past && widget.booked(d);
                          final chosen =
                              d.year == _picked.year &&
                              d.month == _picked.month &&
                              d.day == _picked.day;
                          return InkWell(
                            customBorder: const CircleBorder(),
                            onTap: past || taken
                                ? null
                                : () => setState(() => _picked = d),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: chosen ? goldGradient : null,
                                color: chosen
                                    ? null
                                    : taken
                                    ? AppColors.slate200
                                    : null,
                                border: d == today && !chosen
                                    ? Border.all(
                                        color: AppColors.green800,
                                        width: 1.5,
                                      )
                                    : null,
                              ),
                              child: Text(
                                '$day',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: chosen
                                      ? FontWeight.w900
                                      : FontWeight.w700,
                                  decoration: taken
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: AppColors.slate400,
                                  color: chosen
                                      ? AppColors.green900
                                      : taken
                                      ? AppColors.slate400
                                      : past
                                      ? AppColors.slate300
                                      : AppColors.green800,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: AppColors.slate200,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Already booked',
                    style: TextStyle(fontSize: 12, color: AppColors.slate500),
                  ),
                ),
                TextButton(
                  onPressed: () => popOnce(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate500,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gold500,
                    foregroundColor: AppColors.green900,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => popOnce(context, _picked),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Under the stay calendar: the stay on the chosen day (guest, contact,
/// check-in and check-out, files), or a free day to book.
class _DayDetails extends StatelessWidget {
  const _DayDetails(this.u, this.day, this.stay);
  final UnitRec u;
  final DateTime day;
  final Booking? stay;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // Stays live: an edit made from here shows straight away.
    listenable: adminState,
    builder: (context, _) {
      if (stay != null && !adminState.bookings.contains(stay)) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'This stay was removed.',
            style: TextStyle(color: AppColors.slate500),
          ),
        );
      }
      return _content(context);
    },
  );

  Widget _content(BuildContext context) {
    final t = appState.today;
    final past = day.isBefore(DateTime(t.year, t.month, t.day));
    final b = stay;
    final current = b != null && b == adminState.currentBooking(u.name);
    final (String tag, Color tagBg, Color tagFg) = b == null
        ? ('FREE', AppColors.slate100, AppColors.slate500)
        : current
        ? ('GUEST IN', AppColors.emerald, Colors.white)
        : !upcomingOrNow(b)
        ? ('PAST STAY', _pastRed, const Color(0xFF8C2F2B))
        : ('BOOKED', AppColors.gold500, AppColors.green900);

    // Shown in a pop-up window, so no card around it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                stayMoment(day).split(' · ').first,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: tagBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                tag,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: tagFg,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (b == null) ...[
          Text(
            past ? 'No one stayed this night.' : 'This night is free.',
            style: const TextStyle(fontSize: 13, color: AppColors.slate500),
          ),
          if (!past) ...[
            const SizedBox(height: 12),
            GoldButton(
              label: 'Book this day',
              icon: Icons.add_rounded,
              compact: true,
              onPressed: () => showAppSheet(
                context,
                title: 'New booking',
                builder: (_) => BookingForm(u, startDay: day),
              ),
            ),
          ],
        ] else ...[
          _Line(
            Icons.person_outline_rounded,
            'Guest',
            b.guest.isEmpty ? 'Not given' : b.guest,
          ),
          _Line(
            Icons.call_outlined,
            'Contact',
            b.phone.isEmpty ? 'Not given' : b.phone,
          ),
          _Line(Icons.login_rounded, 'Check-in', stayMoment(b.checkIn)),
          _Line(Icons.logout_rounded, 'Check-out', stayMoment(b.checkOut)),
          _Line(
            Icons.group_outlined,
            'Stay',
            '${b.nights} ${b.nights == 1 ? 'night' : 'nights'} · ${b.guests} ${b.guests == 1 ? 'guest' : 'guests'}'
                '${b.amount > 0 ? ' · ${peso(b.amount)}' : ''}',
          ),
          _Line(
            Icons.savings_outlined,
            'Deposit',
            b.deposit <= 0
                ? 'None'
                : b.depositReturnedOn != null
                ? '${peso(b.depositLeft)} returned ${formatDate(b.depositReturnedOn!)}'
                : b.deductions.isEmpty
                ? peso(b.deposit)
                : '${peso(b.depositLeft)} left of ${peso(b.deposit)}',
          ),
          // What was taken off the deposit, and why.
          for (final d in b.deductions)
            Padding(
              padding: const EdgeInsets.only(left: 24, bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '- ${peso(d.amount)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      d.reason.isEmpty ? 'No reason given' : d.reason,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.slate600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ...[
            const SizedBox(height: 8),
            const Text(
              'Files',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.slate500,
              ),
            ),
            const SizedBox(height: 6),
            if (b.files.isEmpty)
              const Text(
                'No files uploaded for this stay.',
                style: TextStyle(fontSize: 12.5, color: AppColors.slate400),
              ),
            for (final g in b.files)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => viewGuestFile(context, g),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: g.isPdf || g.bytes == null
                            ? const IconBadge(
                                Icons.picture_as_pdf_rounded,
                                size: 40,
                              )
                            : Image.memory(
                                g.bytes!,
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const IconBadge(
                                  Icons.image_outlined,
                                  size: 40,
                                ),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          g.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.green800,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.visibility_outlined,
                        size: 18,
                        color: AppColors.gold600,
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 10),
          // Past stays are history: view only.
          if (upcomingOrNow(b))
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
                title: 'Edit booking',
                builder: (_) => BookingForm(u, existing: b),
              ),
              icon: const Icon(
                Icons.edit_outlined,
                size: 18,
                color: AppColors.gold600,
              ),
              label: const Text(
                'Edit booking',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, size: 16, color: AppColors.gold600),
        const SizedBox(width: 8),
        SizedBox(
          width: 74,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: AppColors.slate500),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.green800,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The security deposit of the guest staying now: what was collected, what
/// was taken off and why, what is left, and a form to take more off.
class DepositSheet extends StatefulWidget {
  const DepositSheet(this.b, {super.key});
  final Booking b;
  @override
  State<DepositSheet> createState() => _DepositSheetState();
}

class _DepositSheetState extends State<DepositSheet> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _deduct() {
    final b = widget.b;
    final amount = double.tryParse(_amount.text) ?? 0;
    if (amount <= 0) {
      showProblem(
        context,
        'No amount',
        'Enter how much to take off the deposit.',
      );
      return;
    }
    if (amount > b.depositLeft) {
      showProblem(
        context,
        'Too much',
        'Only ${peso(b.depositLeft)} of the deposit is left.',
      );
      return;
    }
    adminState.deductDeposit(b, amount, _reason.text.trim());
    _amount.clear();
    _reason.clear();
    FocusScope.of(context).unfocus();
    toast(context, '${peso(amount)} taken off the deposit.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final b = widget.b;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${b.guest} · until ${stayMoment(b.checkOut)}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.slate500),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.slate200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Left to return',
                    style: TextStyle(fontSize: 12, color: AppColors.slate500),
                  ),
                  Text(
                    peso(b.depositLeft),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.green800,
                    ),
                  ),
                  Text(
                    'of ${peso(b.deposit)} collected',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.slate500,
                    ),
                  ),
                ],
              ),
            ),
            if (b.deductions.isNotEmpty) ...[
              const SizedBox(height: 12),
              const FieldLabel('Taken off'),
              for (final d in b.deductions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          d.reason.isEmpty ? 'Deduction' : d.reason,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.green800,
                          ),
                        ),
                      ),
                      Text(
                        '- ${peso(d.amount)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.red,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 14),
            const FieldLabel('Take off the deposit'),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Amount (₱)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reason,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Reason (optional)'),
            ),
            const SizedBox(height: 12),
            GoldButton(
              label: 'Deduct',
              icon: Icons.remove_circle_outline_rounded,
              onPressed: b.depositReturnedOn == null ? _deduct : null,
            ),
            const SizedBox(height: 12),
            // At check-out: hand back what is left and record it.
            if (b.depositReturnedOn case final on?)
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.emerald,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${peso(b.depositLeft)} returned to ${b.guest} on ${formatDate(on)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.emerald,
                      ),
                    ),
                  ),
                ],
              )
            else if (b.deposit > 0)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  foregroundColor: AppColors.green800,
                  side: const BorderSide(color: AppColors.gold500),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () async {
                  final ok = await confirmAction(
                    context,
                    title: 'Return the deposit?',
                    message:
                        'Record that ${peso(b.depositLeft)} was handed back to ${b.guest}. '
                        'No more deductions can be made after this.',
                    action: 'Returned',
                    danger: false,
                  );
                  if (ok) adminState.returnDeposit(b);
                },
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: Text(
                  'Mark ${peso(b.depositLeft)} returned',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// False for a stay that is over (its check-out day is today or earlier and
/// it is not the guest staying now).
bool upcomingOrNow(Booking b) {
  final t = appState.today;
  final today = DateTime(t.year, t.month, t.day);
  return b == adminState.currentBooking(b.unit) ||
      DateTime(b.checkIn.year, b.checkIn.month, b.checkIn.day).isAfter(today);
}

/// "Damage occurred": every amount taken off guests' security deposits in a
/// month, with the reason and the stay. Pick the month with the arrows or by
/// tapping it (month and year).
class DamageSheet extends StatefulWidget {
  const DamageSheet(this.u, {super.key});
  final UnitRec u;
  @override
  State<DamageSheet> createState() => _DamageSheetState();
}

class _DamageSheetState extends State<DamageSheet> {
  DateTime _month = DateTime(appState.today.year, appState.today.month);

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

  Future<void> _pickMonth() async {
    final picked = await showAppSheet<DateTime>(
      context,
      title: 'Choose a month',
      builder: (_) => _MonthPicker(selected: _month),
    );
    if (picked != null) setState(() => _month = picked);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final list = adminState.deductionsIn(widget.u.name, _month);
        final total = list.fold(0.0, (n, d) => n + d.amount);
        final stays = list.map((d) => d.stay).toSet().length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month bar, same as operational costs.
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.slate200),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed: () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1),
                    ),
                    icon: const Icon(
                      Icons.chevron_left_rounded,
                      color: AppColors.gold600,
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _pickMonth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          '${_monthNames[_month.month - 1]} ${_month.year}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.green800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed: () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1),
                    ),
                    icon: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.gold600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // The month's numbers.
            Row(
              children: [
                Expanded(child: _Stat('Deducted', peso(total))),
                const SizedBox(width: 8),
                Expanded(child: _Stat('Times', '${list.length}')),
                const SizedBox(width: 8),
                Expanded(child: _Stat('Stays', '$stays')),
              ],
            ),
            const SizedBox(height: 14),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'No damage in ${_monthNames[_month.month - 1]} ${_month.year}.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.slate500,
                    ),
                  ),
                ),
              ),
            for (final d in list)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.slate200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const IconBadge(Icons.report_problem_outlined, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.reason.isEmpty ? 'No reason given' : d.reason,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.green800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${d.stay.guest.isEmpty ? 'Guest' : d.stay.guest} · '
                            '${stayMoment(d.stay.checkIn).split(' · ').first} - ${stayMoment(d.stay.checkOut).split(' · ').first}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.slate500,
                            ),
                          ),
                          Text(
                            'Deducted ${stayMoment(d.date).split(' · ').first}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.slate400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '- ${peso(d.amount)}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.red,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.slate50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.slate200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: AppColors.slate500),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.green800,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A problem shown in a window over the current sheet, where it can be
/// seen (a message at the bottom of the screen would be hidden behind it).
Future<void> showProblem(BuildContext context, String title, String message) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.green800,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(height: 1.4, color: AppColors.slate600),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold500,
              foregroundColor: AppColors.green900,
            ),
            onPressed: () => popOnce(ctx),
            child: const Text(
              'OK',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
