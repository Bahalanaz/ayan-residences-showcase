import 'package:flutter/foundation.dart';
import 'demo.dart';

enum PaymentStatus { verified, pending }

class Payment {
  Payment({
    required this.title,
    required this.date,
    required this.method,
    required this.reference,
    required this.amount,
    required this.status,
  });
  final String title, date, method, reference;
  final double amount;
  final PaymentStatus status;
}

enum TicketStatus { pending, underReview, approved }

/// A GCash, Maya or bank account tenants can send rent to. Management adds,
/// edits and removes these from the More tab.
class PayAccount {
  PayAccount({
    required this.type,
    required this.name,
    required this.accountName,
    required this.number,
    this.qr,
  });

  /// 'GCash', 'Maya', 'Bank' or 'Other'.
  String type;

  /// What tenants see as the title, e.g. "GCash" or "BDO Unibank".
  String name;

  /// Who the account is registered to.
  String accountName;
  String number;

  bool get isWallet => type == 'GCash' || type == 'Maya';
  String get numberLabel => isWallet ? '$type number' : 'Account number';

  /// The number without spaces or dashes, for the copy button.
  String get copyText => number.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');

  /// A photo of the account's QR code (GCash, Maya, bank QR Ph) that tenants
  /// can scan or save. Uploaded by management; optional.
  Uint8List? qr;
}

/// What a report is about: something that needs routine fixing, or damage.
enum ReportType { maintenance, damage, modification }

class Ticket {
  Ticket({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.status,
    this.attachments = 0,
    this.type = ReportType.damage,
  });
  final String id, title, description, date;
  final TicketStatus status;
  final ReportType type;
  int attachments;

  /// The photos attached when the report was sent.
  final List<Uint8List> photos = [];
}

enum NoticeKind { emergency, schedule, repair, general }

class HouseRule {
  HouseRule(this.title, this.body);
  String title, body;
}

class Notice {
  Notice({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.date,
    this.requiresAck = true,
    this.to,
    this.audience,
  });
  final String id, title, body, date;
  final NoticeKind kind;

  /// Tenant name for a notice sent to one unit only; null means everyone.
  final String? to;

  /// For an announcement to some unit types only: the tenants it went to.
  /// Null means every tenant.
  final List<String>? audience;
  final bool requiresAck;
  bool acknowledged = false;
}

class ScheduleItem {
  const ScheduleItem(this.day, this.month, this.title, this.time);
  final String day, month, title, time;
}

class Message {
  Message({
    required this.category,
    required this.body,
    required this.date,
    this.reply,
  });
  final String category, body, date;
  final String? reply;
}

class DepositEntry {
  const DepositEntry(this.label, this.date, this.amount);
  final String label, date;
  final double amount; // negative = deduction / refund
}

class Inspection {
  const Inspection(this.title, this.date, this.signed, this.photos);
  final String title, date;
  final bool signed;
  final int photos;
}

enum EventKind { repair, maintenance, rent, notice }

class CalendarEvent {
  CalendarEvent({
    required this.date,
    required this.time,
    required this.title,
    required this.subtitle,
    required this.kind,
  });
  final DateTime date;
  final String time, title, subtitle;
  final EventKind kind;
}

class AppState extends ChangeNotifier {
  // Profile (filled in at sign-in; the demo starts as Juan).
  String name = demoData ? 'Juan Dela Cruz' : '';
  String email = demoData ? 'tenant@ayan.ph' : '';
  String phone = demoData ? '+63 917 123 4567' : '';
  String emergencyContact = demoData ? 'Maria Dela Cruz · +63 918 555 0142' : '';
  int occupants = demoData ? 2 : 1;

  // Lease
  String unit = demoData ? 'Unit 402 · Ayan Tower B' : '';
  double monthlyRent = demoData ? 8000 : 0;
  DateTime leaseStart = demoData ? DateTime(2026, 1, 1) : _dateOnly(DateTime.now());
  DateTime leaseEnd = demoData ? DateTime(2026, 12, 31) : _dateOnly(DateTime.now());

  /// Today's date: the real date, or Oct 26, 2026 in the demo.
  final DateTime today = demoData ? DateTime(2026, 10, 26) : _dateOnly(DateTime.now());

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Today written like "Oct 26, 2026".
  String get todayLabel {
    const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${mon[today.month - 1]} ${today.day.toString().padLeft(2, '0')}, ${today.year}';
  }
  String? renewalChoice;
  String? renewalStatus;

  int get daysRemaining => leaseEnd.difference(today).inDays;

  // Rent
  bool currentRentSubmitted = false;
  final List<Payment> payments = demoData ? [
    Payment(
        title: 'September Rent Payment',
        date: 'Sep 04, 2026',
        method: 'GCash',
        reference: '9821',
        amount: 8000,
        status: PaymentStatus.verified),
    Payment(
        title: 'August Rent Payment',
        date: 'Aug 03, 2026',
        method: 'BDO Bank',
        reference: '4110',
        amount: 8000,
        status: PaymentStatus.verified),
    Payment(
        title: 'July Rent Payment',
        date: 'Jul 05, 2026',
        method: 'GCash',
        reference: '1092',
        amount: 8000,
        status: PaymentStatus.verified),
  ] : [];

  /// Paid online through the payment gateway: confirmed at once, no review.
  bool currentRentPaid = false;

  void recordOnlinePayment({
    required String title,
    required String method,
    required double amount,
    required String reference,
    required String date,
  }) {
    payments.insert(
      0,
      Payment(
        title: title,
        date: date,
        method: method,
        reference: reference,
        amount: amount,
        status: PaymentStatus.verified,
      ),
    );
    currentRentPaid = true;
    notifyListeners();
  }

  /// A payment the admin recorded (cash, or proof received outside the app).
  void recordManualPayment({
    required String title,
    required String method,
    required double amount,
    required String reference,
    required String date,
    required bool clearsRent,
  }) {
    payments.insert(
      0,
      Payment(
        title: title,
        date: date,
        method: method,
        reference: reference,
        amount: amount,
        status: PaymentStatus.verified,
      ),
    );
    if (clearsRent) currentRentPaid = true;
    notifyListeners();
  }

  /// Set by the admin side so a submitted proof reaches "To verify".
  /// [charges]: the charges the tenant chose to pay with it (admin records).
  void Function(String tenant, String method, String reference, int months, DateTime? from,
      DateTime? to, double amount, String date, Uint8List? proof, List<Object> charges)? onProofSubmitted;

  /// The tenant sends proof for [months] months of rent covering [from] to [to].
  void submitPayment({
    required String method,
    required double amount,
    required String reference,
    int months = 1,
    DateTime? from,
    DateTime? to,
    String period = 'October',
    Uint8List? proof,
    List<Object> charges = const [],
    String? title,
  }) {
    const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final date = '${mon[today.month - 1]} ${today.day.toString().padLeft(2, '0')}, ${today.year}';
    payments.insert(
      0,
      Payment(
        title: title ?? '$period Rent Payment',
        date: date,
        method: method,
        reference: reference,
        amount: amount,
        status: PaymentStatus.pending,
      ),
    );
    onProofSubmitted?.call(currentTenant, method, reference, months, from, to, amount, date, proof, charges);
    currentRentSubmitted = true;
    notifyListeners();
  }

  // Deposit
  // One month's rent held as deposit (the tenant also pays 2 months advance).
  double deposit = demoData ? 8000 : 0;
  final List<DepositEntry> depositLedger = demoData ? const [
    DepositEntry('Security deposit received (1 month)', 'Dec 28, 2025', 8000),
  ] : const [];

  // Inspections
  final List<Inspection> inspections = demoData ? const [
    Inspection('Move-in Inspection', 'Signed Jan 01, 2026', true, 24),
    Inspection('Move-out Inspection', 'Not yet scheduled', false, 0),
  ] : const [];
  int interimPhotos = 0;
  void addInterimPhotos(int n) {
    interimPhotos += n;
    notifyListeners();
  }

  // Tickets
  final List<Ticket> tickets = demoData ? [
    Ticket(
        id: 'TK-1082',
        title: 'Bathroom Sink Faucet Leaking',
        description: 'Water dripping constantly under the pipe joint in master bath.',
        date: 'Oct 22, 2026',
        status: TicketStatus.pending,
        type: ReportType.maintenance,
        attachments: 2),
    Ticket(
        id: 'TK-0941',
        title: 'Living Room AC Filter Cleaning',
        description: 'Routine cleaning and checkup completed by maintenance team.',
        date: 'Sep 14, 2026',
        type: ReportType.maintenance,
        status: TicketStatus.approved),
  ] : [];
  int _ticketSeq = 1083;

  /// Set by the admin side so a new report reaches management.
  void Function(Ticket ticket)? onTicketAdded;

  void addTicketPhotos(Ticket t, int n) {
    t.attachments += n;
    notifyListeners();
  }

  void addTicket({
    required String issue,
    required String description,
    required int attachments,
    ReportType type = ReportType.damage,
    DateTime? visitDate,
    String? visitTime,
    List<Uint8List> photos = const [],
  }) {
    final id = demoData ? 'TK-${_ticketSeq++}' : 'TK-${uniqueCode()}';
    final ticket = Ticket(
      id: id,
      title: issue,
      description: description,
      date: todayLabel,
      status: TicketStatus.pending,
      attachments: attachments,
      type: type,
    )..photos.addAll(photos);
    tickets.insert(0, ticket);
    onTicketAdded?.call(ticket);
    // A repair visit the tenant asked for shows up on the calendar.
    if (visitDate != null) {
      events.add(CalendarEvent(
        date: visitDate,
        time: visitTime ?? 'Any time',
        title: issue,
        subtitle: 'Repair visit requested · $id',
        kind: EventKind.repair,
      ));
    }
    notifyListeners();
  }

  // Calendar
  final List<CalendarEvent> events = demoData ? [
    CalendarEvent(date: DateTime(2026, 10, 29), time: '9:00 AM', title: 'Bathroom faucet repair', subtitle: 'Technician visit · TK-1082', kind: EventKind.repair),
    CalendarEvent(date: DateTime(2026, 10, 30), time: '1:00 PM - 5:00 PM', title: 'Water tank cleaning', subtitle: 'Building maintenance · Water supply off', kind: EventKind.maintenance),
    CalendarEvent(date: DateTime(2026, 11, 2), time: '10:00 AM - 12:00 PM', title: 'Elevator 2 inspection', subtitle: 'Building maintenance · Elevator 1 stays active', kind: EventKind.maintenance),
    CalendarEvent(date: DateTime(2026, 11, 3), time: '9:00 AM - 4:00 PM', title: 'Rooftop waterproofing', subtitle: 'Building works · Expect some noise', kind: EventKind.maintenance),
    CalendarEvent(date: DateTime(2026, 11, 5), time: 'All day', title: 'Rent due', subtitle: '₱8,000 · GCash or bank transfer', kind: EventKind.rent),
    CalendarEvent(date: DateTime(2026, 11, 12), time: '10:00 AM', title: 'Fire drill', subtitle: 'Assemble at the parking lot', kind: EventKind.notice),
  ] : [];

  /// Puts this tenant's move-in and lease-end dates on their calendar,
  /// replacing the old ones when management changes the lease.
  void setLeaseDates(DateTime start, DateTime end) {
    leaseStart = start;
    leaseEnd = end;
    events.removeWhere((e) => e.subtitle.startsWith('Lease:'));
    events
      ..add(CalendarEvent(
          date: start,
          time: 'All day',
          title: 'Move-in day',
          subtitle: 'Lease: your lease starts',
          kind: EventKind.notice))
      ..add(CalendarEvent(
          date: end,
          time: 'All day',
          title: 'Lease ends',
          subtitle: 'Lease: move out unless renewed',
          kind: EventKind.notice));
    notifyListeners();
  }

  void addEvent(CalendarEvent e) {
    events.add(e);
    notifyListeners();
  }

  List<CalendarEvent> eventsOn(DateTime d) =>
      events.where((e) => e.date.year == d.year && e.date.month == d.month && e.date.day == d.day).toList();

  // Accounts tenants can send rent to (edited by the admin)
  final List<PayAccount> payAccounts = demoData ? [
    PayAccount(
        type: 'GCash', name: 'GCash', accountName: 'Ayan Residences Mgmt', number: '0917-889-2926'),
    PayAccount(
        type: 'Bank',
        name: 'BDO Unibank',
        accountName: 'Ayan Realty Inc',
        number: '0012-3456-7890'),
  ] : [];

  void savePayAccount(PayAccount? existing, PayAccount data) {
    if (existing == null) {
      payAccounts.add(data);
    } else {
      existing
        ..type = data.type
        ..name = data.name
        ..accountName = data.accountName
        ..number = data.number
        ..qr = data.qr;
    }
    notifyListeners();
  }

  void deletePayAccount(PayAccount a) {
    payAccounts.remove(a);
    notifyListeners();
  }

  // House rules (edited by the admin, read by tenants)
  final List<HouseRule> rules = demoData ? [
    HouseRule('Quiet Hours Policy',
        'Quiet hours are strictly enforced between 10:00 PM and 7:00 AM daily in all residential corridors.'),
    HouseRule('Waste Disposal Rules',
        'Garbage segregation is mandatory. Segregated bags must be dropped at the basement utility room between 6:00 AM - 9:00 AM only.'),
    HouseRule('Visitor Verification',
        'All visitors must present valid ID at the lobby guard counter before proceeding to upper residential floors.'),
    HouseRule('Pets & Common Areas',
        'Pets must be leashed in common areas. Owners are responsible for cleaning up after their animals.'),
    HouseRule('Smoking & Open Flames',
        'Smoking and open flames are not allowed inside units, stairwells, and corridors.'),
    HouseRule('Alterations & Repairs',
        'No structural alterations or repainting without written approval from management.'),
  ] : [];

  void saveRule(HouseRule? existing, String title, String body) {
    if (existing == null) {
      rules.add(HouseRule(title, body));
    } else {
      existing
        ..title = title
        ..body = body;
    }
    notifyListeners();
  }

  void deleteRule(HouseRule r) {
    rules.remove(r);
    notifyListeners();
  }

  // Notices: building-wide ones plus those sent to this tenant only.
  List<Notice> get notices =>
      allNotices
          .where((n) => n.to == currentTenant || (n.to == null && (n.audience?.contains(currentTenant) ?? true)))
          .toList();

  final List<Notice> allNotices = demoData ? [
    Notice(
        id: 'n1',
        kind: NoticeKind.emergency,
        title: 'Scheduled Water Main Interruption',
        body:
            'Please store sufficient water. Supply will be shut off from 1:00 PM to 5:00 PM today for pipe cleaning in Tower B.',
        date: 'Today, 8:00 AM',
        requiresAck: true),
    Notice(
        id: 'n2',
        kind: NoticeKind.schedule,
        title: 'Monthly Elevator Maintenance',
        body:
            'Elevator 2 will undergo safety inspection on Sunday between 10:00 AM - 12:00 PM. Elevator 1 remains active.',
        date: 'Oct 20, 2026'),
    Notice(
        id: 'n3',
        kind: NoticeKind.repair,
        title: 'Rooftop Waterproofing Works',
        body:
            'Contractors will be on the rooftop from Nov 3-7. Expect minor noise between 9:00 AM and 4:00 PM.',
        date: 'Oct 15, 2026',
        requiresAck: true),
    Notice(
        id: 'n4',
        kind: NoticeKind.general,
        title: 'Fire Drill Reminder',
        body:
            'Annual fire drill is scheduled on Nov 12 at 10:00 AM. Please follow the evacuation signage and assemble at the parking lot.',
        date: 'Oct 10, 2026'),
  ] : [];
  final List<ScheduleItem> schedule = demoData ? const [
    ScheduleItem('30', 'OCT', 'Water tank cleaning', '1:00 PM – 5:00 PM'),
    ScheduleItem('02', 'NOV', 'Elevator 2 inspection', '10:00 AM – 12:00 PM'),
    ScheduleItem('03', 'NOV', 'Rooftop waterproofing', '9:00 AM – 4:00 PM'),
    ScheduleItem('12', 'NOV', 'Fire drill', '10:00 AM'),
  ] : const [];

  /// Called by the admin side when a notice is published.
  void addNotice(Notice n) {
    allNotices.insert(0, n);
    notifyListeners();
  }

  int get pendingAcks =>
      notices.where((n) => n.requiresAck && !n.acknowledged).length;

  /// The tenant using this phone. Read receipts are recorded under this name.
  String currentTenant = demoData ? 'Juan Dela Cruz' : '';

  /// Set by the admin side so it can record who read which announcement.
  void Function(String noticeId, String tenant)? onNoticeRead;
  void Function(String tenant, String email, String phone, String emergency, int people)? onContactUpdated;

  void acknowledge(Notice n) {
    n.acknowledged = true;
    onNoticeRead?.call(n.id, currentTenant);
    notifyListeners();
  }

  // Messages
  final List<Message> messages = demoData ? [
    Message(
        category: 'Security / Parking Request',
        body: 'Is there an available parking slot for guest over the weekend?',
        date: 'Oct 18',
        reply: 'Yes, Slot B-12 is reserved for unit 402 for Oct 24-25. Pass issued.'),
  ] : [];
  void sendMessage(String category, String body) {
    messages.insert(0, Message(category: category, body: body, date: 'Today'));
    notifyListeners();
  }

  // Renewal / contact
  /// Set by the admin side so the request reaches Leases & requests.
  void Function(String tenant, String choice)? onRenewalRequested;

  void submitRenewal(String choice, String? newPhone) {
    renewalChoice = choice;
    renewalStatus = 'Submitted $todayLabel · Awaiting management review';
    onRenewalRequested?.call(currentTenant, choice);
    if (newPhone != null && newPhone.trim().isNotEmpty) phone = newPhone.trim();
    notifyListeners();
  }

  /// Juan's demo payments and reports, kept so signing in as him again after
  /// another tenant brings them back.
  List<Payment>? _demoPayments;
  List<Ticket>? _demoTickets;

  /// Fills the tenant app with the signed-in tenant's own details. The admin
  /// side calls this at sign-in with the tenant's record. [ownPayments] and
  /// [ownTickets] replace the demo ones for anyone but the demo tenant.
  void loadProfile({
    required String name,
    required String email,
    required String phone,
    required String unit,
    required double rent,
    required double deposit,
    required String emergency,
    required int occupants,
    List<Payment>? ownPayments,
    List<Ticket>? ownTickets,
  }) {
    _demoPayments ??= [...payments];
    _demoTickets ??= [...tickets];
    currentTenant = name;
    this.name = name;
    this.email = email;
    this.phone = phone;
    this.unit = unit;
    monthlyRent = rent;
    this.deposit = deposit;
    emergencyContact = emergency;
    this.occupants = occupants;
    payments
      ..clear()
      ..addAll(ownPayments ?? _demoPayments!);
    tickets
      ..clear()
      ..addAll(ownTickets ?? _demoTickets!);
    currentRentSubmitted = false;
    renewalChoice = null;
    renewalStatus = null;
    notifyListeners();
  }

  /// Payment accounts and house rules loaded from the database.
  void loadShared({required List<PayAccount> payAccounts, required List<HouseRule> rules}) {
    this.payAccounts
      ..clear()
      ..addAll(payAccounts);
    this.rules
      ..clear()
      ..addAll(rules);
    notifyListeners();
  }

  /// The signed-in tenant's notices and messages, loaded from the database.
  void loadTenantLists({required List<Notice> notices, required List<Message> messages}) {
    allNotices
      ..clear()
      ..addAll(notices);
    this.messages
      ..clear()
      ..addAll(messages);
    notifyListeners();
  }

  void updateContact(String newEmail, String newPhone, String emergency, [int? people]) {
    if (people != null) occupants = people;
    email = newEmail;
    phone = newPhone;
    emergencyContact = emergency;
    onContactUpdated?.call(currentTenant, email, phone, emergencyContact, occupants);
    notifyListeners();
  }
}

final appState = AppState();
