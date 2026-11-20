import 'package:flutter/foundation.dart';

import '../config/supabase_config.dart';
import '../state/app_state.dart';
import '../state/demo.dart';
import '../widgets/common.dart' show peso;

/// Admin login (demo only).
const adminUsername = '1234';

/// Demo admin password; the More tab can change it until the app restarts.
String adminPassword = '1234';

const stayTypes = ['Daily', 'Weekly', 'Monthly', 'Yearly'];

/// How a property type is billed: apartments monthly, condos day to day,
/// villas yearly.
String bedroomLabel(int n) => n == 0
    ? 'Studio'
    : n == 1
    ? '1 bedroom'
    : '$n bedrooms';

int bedroomCount(String label) =>
    label == 'Studio' ? 0 : int.parse(label.split(' ').first);

String stayTypeFor(String propertyType) => switch (propertyType) {
  'Condo' => 'Daily',
  'Villa' => 'Yearly',
  _ => 'Monthly',
};

// ----------------------------------------------------------------- Units

enum UnitStatus { vacant, reserved, occupied }

/// Physical condition, independent of whether anyone lives there.
enum UnitCondition { good, underMaintenance, underRepair, underModification }

class UnitRec {
  UnitRec({
    required this.property,
    required this.type,
    required this.name,
    required this.rate,
    required this.rateUnit,
    this.status = UnitStatus.vacant,
    this.tenant,
    this.photo,
    this.condition = UnitCondition.good,
    this.bedrooms = 1,
    this.depositAmount,
  });
  final String property;
  String type, name, rateUnit;
  double rate;

  /// 0 means a studio.
  int bedrooms;

  /// Security deposit; null means the same as one rate.
  double? depositAmount;
  double get deposit => depositAmount ?? rate;
  UnitStatus status;
  UnitCondition condition;
  String? tenant;

  /// Photo picked when the unit was added. Null shows a themed card with an icon for its type.
  Uint8List? photo;

  /// Its row in the database (null until saved, and in the demo).
  int? id;

  /// Where its photo is stored in the database's file storage.
  String? photoPath;

  /// When the admin deleted it. A deleted unit is only archived: it leaves
  /// the lists, but its payments, stays, reports and costs stay on record
  /// for Finance and the PDF reports.
  DateTime? archivedAt;
}

/// Saved settings for adding units quickly (everything except the unit name).
class UnitTemplate {
  UnitTemplate({
    required this.name,
    required this.property,
    required this.type,
    required this.bedrooms,
    required this.rateUnit,
    this.rate,
    this.photo,
  });
  final String name, property, type, rateUnit;
  final int bedrooms;
  final double? rate;
  Uint8List? photo;

  /// Where its photo is stored in the database's file storage.
  String? photoPath;
}

// --------------------------------------------------------------- Tenants

/// A tenant account: the login, the unit and lease details. Every detail can
/// be edited by the admin after the account is created.
class TenantRec {
  TenantRec({
    required this.name,
    required this.unit,
    required this.phone,
    required this.email,
    required this.stayType,
    required this.rent,
    required this.leaseStart,
    required this.leaseEnd,
    required this.username,
    required this.password,
    this.balance = 0,
    this.deposit = 0,
    this.depositNote,
    Map<String, bool>? docs,
    this.paidFrom,
    this.paidUntil,
    this.signedLease,
    this.emergencyContact = '',
    this.occupants = 1,
  }) : docs = docs ?? {for (final d in tenantDocs) d: false};

  String name, unit, phone, email, stayType, leaseStart, leaseEnd;
  String username, password;
  double rent, balance, deposit;
  String? depositNote; // set once settled

  /// Its tenant row and current lease row in the database (null until
  /// saved, and in the demo).
  int? id, leaseId;

  /// Profile details the tenant declares in their app.
  String emergencyContact;
  int occupants;

  /// Documents the TENANT uploads (true) or has not yet (false).
  final Map<String, bool> docs;

  /// The files the tenant uploaded, by document name (name + bytes).
  final Map<String, ({String name, Uint8List bytes})> docFiles = {};

  /// Photo of the signed lease, provided by the ADMIN.
  Uint8List? signedLease;

  /// A signed lease / contract that is on the server but not downloaded to
  /// this phone yet (it downloads when opened).
  bool signedLeaseOnServer = false, contractOnServer = false;
  bool get hasSignedLease => signedLease != null || signedLeaseOnServer;
  bool get hasContract => contractPdf != null || contractOnServer;

  /// Day of the month rent is due (1-31).
  int dueDay = 5;

  /// Villa tenants: how many post-dated cheques they give a year (1-4),
  /// agreed when the contract is signed.
  int chequesPerYear = 4;

  /// Lease length in whole months (rounded), from the lease dates.
  int get termMonths {
    final a = parseDate(leaseStart), b = parseDate(leaseEnd);
    if (a == null || b == null) return 0;
    return ((b.difference(a).inDays + 1) / 30.4375).round();
  }

  /// The contract PDF the admin assigned; the tenant views it in their app.
  String? contractName;
  Uint8List? contractPdf;
  DateTime? contractAssignedAt;

  /// The stay that has been paid for: first day and last day covered.
  DateTime? paidFrom, paidUntil;

  /// Shown wherever the unit is listed; empty means a ready account with no
  /// unit assigned yet.
  String get unitLabel => unit.isEmpty ? 'No unit yet' : unit;

  /// Days until the lease ends, from today.
  int get daysLeft {
    final end = parseDate(leaseEnd);
    if (end == null) return 365;
    final t = appState.today;
    return end.difference(DateTime(t.year, t.month, t.day)).inDays;
  }

  /// Uploaded documents management has checked and accepted.
  final Set<String> docVerified = {};

  /// Documents management turned down, with the reason ("Blurred photo").
  final Map<String, String> docRejected = {};

  /// Earlier leases, newest first, kept when the lease is renewed.
  final List<LeaseTerm> pastLeases = [];

  /// Set once the tenant has been reminded that this lease is ending.
  bool endReminded = false;

  /// A renewal agreed before the current lease ends: it takes over on its
  /// start date (see [AdminState.applyDueRenewals]).
  LeaseTerm? nextLease;
}

/// A tenant who has moved out: kept on record after the account is closed.
class FormerTenant {
  FormerTenant({
    required this.name,
    required this.unit,
    required this.unitType,
    required this.phone,
    required this.email,
    required this.leaseStart,
    required this.leaseEnd,
    required this.movedOut,
    required this.depositNote,
    required this.inspection,
    required this.owedAtMoveOut,
    required this.pastLeases,
  });
  final String name, unit, unitType, phone, email, leaseStart, leaseEnd;
  final DateTime movedOut;
  final String depositNote, inspection;

  /// Charges still unpaid when they left (0 when all settled).
  final double owedAtMoveOut;
  final List<LeaseTerm> pastLeases;
}

/// One thing the admin did, for the activity log.
class LogEntry {
  LogEntry(this.at, this.action, this.detail);
  final DateTime at;
  final String action, detail;
}

/// A tenant's document: not uploaded, waiting for management to check it,
/// accepted, or turned down (to upload again).
enum DocState { missing, toReview, verified, rejected }

/// A lease as it was before a renewal: its dates, rent and contract.
class LeaseTerm {
  LeaseTerm({
    required this.start,
    required this.end,
    required this.rent,
    required this.chequesPerYear,
    this.contractName,
    this.contractPdf,
  });
  final String start, end;
  final double rent;
  final int chequesPerYear;
  final String? contractName;

  /// Null until downloaded when it came from the server.
  Uint8List? contractPdf;
}

const _monthIdx = {
  'Jan': 1,
  'Feb': 2,
  'Mar': 3,
  'Apr': 4,
  'May': 5,
  'Jun': 6,
  'Jul': 7,
  'Aug': 8,
  'Sep': 9,
  'Oct': 10,
  'Nov': 11,
  'Dec': 12,
};
const monthShort = [
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

/// Reads dates written like "Nov 5, 2026" or "Nov 05, 2026".
DateTime? parseDate(String s) {
  final m = RegExp(r'^(\w{3}) (\d{1,2}), (\d{4})$').firstMatch(s.trim());
  if (m == null) return null;
  final month = _monthIdx[m.group(1)];
  return month == null
      ? null
      : DateTime(int.parse(m.group(3)!), month, int.parse(m.group(2)!));
}

String formatDate(DateTime d) =>
    '${monthShort[d.month - 1]} ${d.day}, ${d.year}';

/// The date rent is due in [month] of [year] for a tenant whose due day is
/// [day]. A month too short for it uses its last day, so a due day of 31 is
/// Feb 28 (29 in a leap year), Apr 30, and so on.
DateTime dueDateIn(int year, int month, int day) {
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > last ? last : day);
}

/// How each kind of unit is priced: condos by the night, apartments by the
/// month, villas by the year. Set by the type, never picked by hand.
String ratePeriodFor(String type) => switch (type) {
  'Condo' => 'night',
  'Villa' => 'year',
  _ => 'month',
};

/// The paid-through date after paying [months] more months. If [until] is the
/// last day of a month (Sep 30) the result is also a month's last day (Nov 30);
/// otherwise it keeps the same day of the month (Nov 14 -> Jan 14).
DateTime addMonthsToPaidUntil(DateTime until, int months) {
  final lastDay = DateTime(until.year, until.month + 1, 0).day;
  if (until.day == lastDay) {
    return DateTime(until.year, until.month + months + 1, 0);
  }
  final target = DateTime(until.year, until.month + months, 1);
  final days = DateTime(target.year, target.month + 1, 0).day;
  return DateTime(
    target.year,
    target.month,
    until.day > days ? days : until.day,
  );
}

/// Documents shown on a unit's Tenant tab.
/// What a villa tenant provides instead: identity and residency papers.
const villaDocs = ['Passport', 'Visa', 'EID', 'Ejari'];

/// What every tenant provides (from the move-in checklist): an ID, a photo, and
/// the clearances management needs to approve them.
const tenantDocs = [
  'Valid ID',
  'ID picture',
  'Barangay clearance',
  'Police clearance',
  'NBI clearance',
];

// -------------------------------------------------------------- Calendar

enum AdminEventKind {
  repair,
  maintenance,
  inspection,
  rent,
  lease,
  stay,
  modification,
}

/// A repair or maintenance job scheduled by the admin.
class WorkItem {
  WorkItem({
    required this.date,
    required this.time,
    required this.title,
    required this.where,
    required this.kind,
    this.notes = '',
    this.done = false,
    this.cost = 0,
    DateTime? endDate,
  }) : endDate = endDate ?? date;

  /// What the job cost (in the unit's currency), counted in Finance on the
  /// job's first day. 0 when not entered. When the tenant pays, this is the
  /// value of what was damaged / what the work cost management.
  double cost;

  /// Who pays: false = management (a plain cost), true = the tenant (they
  /// are sent a payment request for [charge]).
  bool tenantPays = false;

  /// What the tenant is asked to pay. Can differ from [cost]: the difference
  /// is management's profit (or loss) once the tenant has paid.
  double charge = 0;

  /// The tenant who was charged, and the payment request sent to them.
  String? chargedTenant;
  ChargeRec? chargeRec;
  DateTime date;

  /// Last day of the job. The same as [date] for a one-day job.
  DateTime endDate;
  String time, title, where, notes;
  AdminEventKind kind; // repair or maintenance
  bool done;

  /// Every day the job runs, first to last.
  List<DateTime> get days {
    final out = <DateTime>[];
    var d = DateTime(date.year, date.month, date.day);
    final last = DateTime(endDate.year, endDate.month, endDate.day);
    while (!d.isAfter(last)) {
      out.add(d);
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return out.isEmpty ? [date] : out;
  }
}

class AdminEvent {
  const AdminEvent({
    required this.date,
    required this.time,
    required this.title,
    required this.unit,
    required this.kind,
    this.detail,
  });
  final DateTime date;
  final String time, title, unit;
  final AdminEventKind kind;
  final String? detail;
}

// -------------------------------------------------------------- Payments

enum PayStatus { submitted, verified, rejected }

/// A tenant's rent as their app shows it.
enum RentState { paid, awaiting, due }

class PaymentRec {
  PaymentRec({
    required this.id,
    required this.tenant,
    required this.unit,
    required this.title,
    required this.amount,
    required this.method,
    required this.reference,
    required this.date,
    this.status = PayStatus.submitted,
    this.reason,
    this.recordedByAdmin = false,
    this.months = 1,
    this.coversFrom,
    this.coversTo,
  });
  final String id, tenant, unit, title, method, reference, date;
  final double amount;
  PayStatus status;
  String? reason;

  /// How many months of rent this payment covers, and the period they span
  /// (the tenant picks the months; the dates are worked out from what is
  /// already paid).
  final int months;
  final DateTime? coversFrom, coversTo;

  /// Entered by the admin (cash, or proof that arrived outside the app)
  /// instead of being submitted by the tenant.
  final bool recordedByAdmin;

  /// The receipt photo the tenant attached (null when there is none).
  Uint8List? proof;

  /// The charges the tenant chose to pay with this proof (beside rent).
  final List<ChargeRec> covers = [];
}

class ChargeRec {
  ChargeRec({
    required this.tenant,
    required this.title,
    required this.amount,
    required this.due,
    this.paid = false,
    this.overdue = false,
  });
  final String tenant, title;

  /// Rent charges follow the lease: an unpaid one moves if the due day or
  /// rent changes.
  String due;
  double amount;
  bool paid, overdue;

  /// Paid so far toward this charge (a part-payment leaves it open).
  double paidAmount = 0;

  /// What is still owed on it.
  double get remaining =>
      paid ? 0 : (amount - paidAmount).clamp(0, amount).toDouble();

  /// True once something has been paid but not all of it.
  bool get partlyPaid => !paid && paidAmount > 0;
}

// --------------------------------------------------------------- Reports

enum ReportStatus { pending, underReview, approved }

enum DamageKind { accident, intentional }

class ReportUpdate {
  const ReportUpdate(this.text, this.date);
  final String text, date;
}

class DamageReport {
  DamageReport({
    required this.id,
    required this.tenant,
    required this.unit,
    required this.issue,
    required this.description,
    required this.date,
    this.attachments = 0,
    this.status = ReportStatus.pending,
    this.type = ReportType.damage,
    List<ReportUpdate>? updates,
  }) : updates = updates ?? [];
  final String id, tenant, unit, issue, description, date;

  /// Routine maintenance, or damage (which gets classified accident or intentional).
  final ReportType type;

  /// Photos and videos; grows when the tenant adds more to the same report.
  int attachments;
  ReportStatus status;

  /// Progress notes from management ("Plumber booked for Friday"), newest first.
  final List<ReportUpdate> updates;
  DamageKind? kind;
  double deduction = 0;
  String note = '';

  /// Photos the admin attached (manual reports); tenant reports keep a count.
  final List<Uint8List> photoFiles = [];
}

// -------------------------------------------------------------- Complaints

enum ComplaintStatus { open, inProgress, resolved }

class ComplaintRec {
  ComplaintRec({
    required this.tenant,
    required this.unit,
    required this.category,
    required this.body,
    required this.date,
    this.status = ComplaintStatus.open,
    this.response,
  });
  final String tenant, unit, category, body, date;
  ComplaintStatus status;

  /// What the admin told the tenant about it.
  String? response;
}

const complaintCategories = [
  'Noise',
  'Neighbors',
  'Cleanliness',
  'Facilities',
  'Staff',
  'Other',
];

// ----------------------------------------------------------------- Cheques

/// Villa tenants pay with cheques: one deposit cheque up front, then
/// post-dated cheques (1 to 4 a year) that are banked on the date written.
enum ChequeKind { deposit, postDated }

enum ChequeStatus { held, deposited, cleared, bounced }

class ChequeRec {
  ChequeRec({
    required this.id,
    required this.tenant,
    required this.kind,
    required this.amount,
    required this.date,
    this.months = 0,
    this.chequeNo = '',
    this.bank = '',
    this.status = ChequeStatus.held,
  });
  final String id, tenant;
  final ChequeKind kind;
  double amount;

  /// The date written on a post-dated cheque (the day it can be banked).
  DateTime date;

  /// Months of rent a post-dated cheque pays for; 0 for the deposit cheque.
  int months;
  String chequeNo, bank;
  ChequeStatus status;

  /// The photo of the cheque the tenant uploaded, for management to check.
  Uint8List? photo;
  String? uploadedOn;

  /// True once management has looked at the uploaded photo (saved a status
  /// on the cheque's screen). A new photo resets it.
  bool photoChecked = false;

  /// Set once the tenant has been reminded that the cheque date is near.
  bool reminded = false;

  bool get hasPhoto => uploadedOn != null;
  bool get newPhoto => hasPhoto && !photoChecked;

  /// The bounced cheque this one replaces (its id), if any.
  String? replaces;

  /// Set when the cheque was handed back to the tenant (deposit cheque at
  /// move-out, or unbanked cheques when a lease ends early).
  String? returnedOn;
}

// ---------------------------------------------------------- Condo bookings
/// "2:00 PM" for a date's time of day.
String clockTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// A tax the admin enters by hand: a name and a rate, on peso income or on
/// villa income (AED).
class TaxRate {
  TaxRate({
    required this.name,
    this.percent = 0,
    this.onVillas = false,
    this.fixedMonthly = 0,
  });
  String name;
  double percent;
  bool onVillas;

  /// A set amount each month instead of a percentage (e.g. a business
  /// permit fee spread monthly). Used when above 0.
  double fixedMonthly;
  bool get isFixed => fixedMonthly > 0;
}

/// A condo stay the admin enters by hand: condo guests are short-stay and
/// get no app account, so the unit is tracked here instead.
/// Each booking's files, by booking id (kept outside the booking so a hot
/// reload of the demo never leaves a booking without a list).
final Map<String, List<GuestFile>> _bookingFiles = {};
final Map<String, double> _bookingDeposits = {};
final Map<String, List<({double amount, String reason, DateTime date})>>
_depositDeductions = {};
final Map<String, DateTime> _depositReturned = {};

class Booking {
  Booking({
    required this.id,
    required this.unit,
    required this.guest,
    required this.checkIn,
    required this.checkOut,
    this.phone = '',
    this.guests = 1,
    this.amount = 0,
    double deposit = 0,
    List<GuestFile>? files,
  }) {
    if (files != null) _bookingFiles[id] = files;
    _bookingDeposits[id] = deposit;
  }
  final String id;
  String unit, guest, phone;

  /// The guest's ID and other files, uploaded with the booking and kept on
  /// record after the stay.
  List<GuestFile> get files => _bookingFiles.putIfAbsent(id, () => []);

  /// Date and time of arrival and departure.
  DateTime checkIn, checkOut;
  int guests;
  double amount;

  /// Security deposit collected for the stay, returned at check-out.
  double get deposit => _bookingDeposits[id] ?? 0;
  set deposit(double v) => _bookingDeposits[id] = v;

  /// Amounts taken off the deposit during the stay (amount and reason).
  List<({double amount, String reason, DateTime date})> get deductions =>
      _depositDeductions.putIfAbsent(id, () => []);

  /// What is left of the deposit after deductions.
  double get depositLeft =>
      deposit - deductions.fold(0.0, (n, d) => n + d.amount);

  /// When what was left of the deposit was handed back; null while held.
  DateTime? get depositReturnedOn => _depositReturned[id];

  /// Nights stayed (by calendar date).
  int get nights => DateTime(
    checkOut.year,
    checkOut.month,
    checkOut.day,
  ).difference(DateTime(checkIn.year, checkIn.month, checkIn.day)).inDays;
}

/// A file the landlady keeps for a condo stay (guest ID, booking slip,
/// payment screenshot). Condo guests have no account, so files are uploaded
/// by management and viewed again here.
class GuestFile {
  GuestFile({
    required this.label,
    required this.fileName,
    required this.bytes,
    required this.added,
  });
  final String label, fileName;

  /// Null until downloaded when it came from the server.
  Uint8List? bytes;
  final DateTime added;
  bool get isPdf => fileName.toLowerCase().endsWith('.pdf');
}

/// Something a unit costs every month (Netflix, internet, association dues),
/// deducted from profit each month from [since] on, until [until] when it was
/// stopped.
class MonthlyExpense {
  MonthlyExpense({
    required this.name,
    required this.amount,
    required this.since,
    this.until,
  });
  String name;
  double amount;

  /// First month it is charged (the day is ignored).
  DateTime since;

  /// Last month it is charged; null while it is still running.
  DateTime? until;
}

/// A saved monthly expense (name and amount) to add quickly. Each one belongs
/// to a unit type: a condo template only shows on condos, an apartment one
/// only on apartments.
class ExpenseTemplate {
  ExpenseTemplate({
    required this.name,
    required this.amount,
    required this.unitType,
  });
  String name;
  double amount;

  /// "Apartment" or "Condo".
  final String unitType;
}

/// Money spent running a unit (cleaning, electricity, supplies), entered by
/// the admin so a condo's earnings can be weighed against its costs.
class CostEntry {
  CostEntry({required this.title, required this.amount, required this.date});
  final String title;
  final double amount;
  final DateTime date;
}

// ---------------------------------------------------- Notices / messages

class AdminNotice {
  AdminNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    required this.date,
    required this.recipients,
    Set<String>? readBy,
    this.to,
    this.automatic = false,
    this.unitTypes,
  }) : readBy = readBy ?? {};

  /// Tenant name when sent to one unit only; null for a building-wide one.
  final String? to;

  /// Sent by the app itself (cheque updates, reminders), not written by
  /// management. These go to the tenant but are not listed as announcements.
  final bool automatic;

  /// Which unit types it went to ("Apartment", "Villa", "Condo"); null
  /// for one unit or an older announcement.
  final List<String>? unitTypes;

  /// Same id as the copy the tenants receive.
  final String id, title, body, date;
  final NoticeKind kind;

  /// Tenants this was sent to (apartments and villas; condo stays are not on the app).
  final List<String> recipients;
  final Set<String> readBy;

  int get read => readBy.length;
  int get total => recipients.length;
}

class AdminMessage {
  AdminMessage({
    required this.tenant,
    required this.unit,
    required this.category,
    required this.body,
    required this.date,
    this.reply,
  });
  final String tenant, unit, category, body, date;
  String? reply;
}

enum RequestStatus { pending, approved, declined }

class LeaseRequest {
  LeaseRequest({
    required this.tenant,
    required this.unit,
    required this.kind,
    required this.date,
    required this.note,
    this.status = RequestStatus.pending,
  });
  final String tenant, unit, kind, date, note;
  RequestStatus status;
}

// ----------------------------------------------------------------- State

class AdminState extends ChangeNotifier {
  AdminState() {
    // When a tenant marks an announcement as read, record it for the admin.
    appState.onNoticeRead = markNoticeRead;
    appState.onTicketAdded = _reportFromTicket;
    appState.onProofSubmitted = _paymentFromProof;
    appState.onRenewalRequested = (tenant, choice) {
      final t = tenants.where((x) => x.name == tenant).firstOrNull;
      requests.insert(
        0,
        LeaseRequest(
          tenant: tenant,
          unit: t?.unit ?? '',
          kind: choice.replaceFirst('Request ', ''),
          date: formatDate(appState.today),
          note: 'Sent from the tenant app.',
        ),
      );
      notifyListeners();
    };
    appState.onContactUpdated = (tenant, email, phone, emergency, people) {
      final t = tenants.where((x) => x.name == tenant).firstOrNull;
      if (t == null) return;
      t.email = email;
      t.phone = phone;
      t.emergencyContact = emergency;
      t.occupants = people;
      notifyListeners();
    };
    _syncTenantLeaseEvents();
    // Demo: documents already uploaded count as checked, except Paolo's visa,
    // which is waiting for management to look at it.
    for (final t in tenants) {
      t.docVerified.addAll(
        t.docs.entries.where((e) => e.value).map((e) => e.key),
      );
    }
    tenants
        .where((t) => t.name == 'Paolo Garcia')
        .firstOrNull
        ?.docVerified
        .remove('Visa');
    refreshCondoStatuses();
    refreshConditions();
    applyDueRenewals();
    generateRentCharges();
    refreshLeaseStatuses();
    // Demo: deposit deductions on past condo stays.
    Booking? stay(String id) => bookings.where((b) => b.id == id).firstOrNull;
    stay('B-1')?.deductions.add((
      amount: 800,
      reason: 'Stained bedsheet',
      date: DateTime(2026, 9, 14),
    ));
    stay('B-2')?.deductions.add((
      amount: 1500,
      reason: 'Broken drinking glass and plate',
      date: DateTime(2026, 10, 6),
    ));
    stay('B-3')?.deductions.add((
      amount: 500,
      reason: 'Lost key card',
      date: DateTime(2026, 10, 22),
    ));
    stay('B-10')?.deductions.add((
      amount: 1200,
      reason: 'Scratched dining table',
      date: DateTime(2026, 10, 17),
    ));
    sendChequeReminders();
    sendLeaseEndReminders();
  }

  /// Signs a tenant into the tenant app: their profile, unit, rent, payments
  /// and reports replace whoever was there before. The demo tenant (Juan)
  /// keeps the app's built-in demo history.
  void signInTenant(String name) {
    final t = tenants.where((x) => x.name == name).firstOrNull;
    if (t == null) {
      appState.currentTenant = name;
      return;
    }
    final u = _unit(t.unit);
    final demo = name == 'Juan Dela Cruz';
    appState.loadProfile(
      name: t.name,
      email: t.email,
      phone: t.phone,
      unit: u == null ? t.unitLabel : '${u.name} · ${u.property}',
      rent: t.rent,
      deposit: t.deposit,
      emergency: t.emergencyContact,
      occupants: t.occupants,
      ownPayments: demo
          ? null
          : [
              for (final p in payments.where(
                (p) => p.tenant == name && p.status != PayStatus.rejected,
              ))
                Payment(
                  title: p.title,
                  date: p.date,
                  method: p.method,
                  reference: p.reference,
                  amount: p.amount,
                  status: p.status == PayStatus.verified
                      ? PaymentStatus.verified
                      : PaymentStatus.pending,
                ),
            ],
      ownTickets: demo
          ? null
          : [
              for (final r in reports.where((r) => r.tenant == name))
                Ticket(
                  id: r.id,
                  title: r.issue,
                  description: r.description,
                  date: r.date,
                  attachments: r.attachments,
                  type: r.type,
                  status: switch (r.status) {
                    ReportStatus.pending => TicketStatus.pending,
                    ReportStatus.underReview => TicketStatus.underReview,
                    ReportStatus.approved => TicketStatus.approved,
                  },
                ),
            ],
    );
    _syncTenantLeaseEvents();
  }

  /// Keeps the logged-in tenant's calendar in step with their lease dates.
  void _syncTenantLeaseEvents() {
    final t = tenants
        .where((x) => x.name == appState.currentTenant)
        .firstOrNull;
    final a = t == null ? null : parseDate(t.leaseStart);
    final b = t == null ? null : parseDate(t.leaseEnd);
    if (a != null && b != null) appState.setLeaseDates(a, b);
  }

  static const _audienceSeed = [
    'Juan Dela Cruz',
    'Grace Santos',
    'Paolo Garcia',
  ];

  final List<UnitRec> units = demoData
      ? [
          UnitRec(
            property: 'Ayan Tower B',
            type: 'Apartment',
            name: 'Unit 402',
            rate: 8000,
            rateUnit: 'month',
            status: UnitStatus.occupied,
            tenant: 'Juan Dela Cruz',
          ),
          UnitRec(
            property: 'Ayan Tower B',
            type: 'Apartment',
            name: 'Unit 2B',
            rate: 8000,
            rateUnit: 'month',
          ),
          UnitRec(
            property: 'Ayan Tower B',
            type: 'Apartment',
            name: 'Unit 305',
            rate: 9500,
            rateUnit: 'month',
            status: UnitStatus.reserved,
            tenant: 'Mark Villanueva',
          ),
          UnitRec(
            property: 'Ayan Tower B',
            type: 'Apartment',
            name: 'Unit 101',
            rate: 7500,
            rateUnit: 'month',
            status: UnitStatus.occupied,
            tenant: 'Grace Santos',
          ),
          UnitRec(
            property: 'Ayan Villas',
            type: 'Villa',
            name: 'Villa 1',
            rate: 22000,
            rateUnit: 'month',
            status: UnitStatus.reserved,
            tenant: 'Liza Fernandez',
          ),
          UnitRec(
            property: 'Ayan Villas',
            type: 'Villa',
            name: 'Villa 2',
            rate: 24000,
            rateUnit: 'month',
            status: UnitStatus.occupied,
            tenant: 'Paolo Garcia',
          ),
          UnitRec(
            property: 'Ayan Stays',
            type: 'Condo',
            name: 'Studio 3',
            rate: 2500,
            rateUnit: 'night',
          ),
          UnitRec(
            property: 'Ayan Stays',
            type: 'Condo',
            name: 'Condo 7A',
            rate: 14000,
            rateUnit: 'month',
          ),
        ]
      : [];

  final List<TenantRec> tenants = demoData
      ? [
          TenantRec(
            emergencyContact: 'Maria Dela Cruz · +63 918 555 0142',
            occupants: 2,
            name: 'Juan Dela Cruz',
            unit: 'Unit 402',
            phone: '+63 917 123 4567',
            email: 'tenant@ayan.ph',
            stayType: 'Yearly',
            rent: 8000,
            leaseStart: 'Jan 01, 2026',
            leaseEnd: 'Dec 31, 2026',
            username: '123',
            password: '123',
            balance: 8000,
            deposit: 8000,
            docs: {
              'Valid ID': true,
              'ID picture': true,
              'Barangay clearance': true,
              'Police clearance': false,
              'NBI clearance': false,
            },
            paidFrom: DateTime(2026, 1, 1),
            paidUntil: DateTime(2026, 9, 30),
          ),
          TenantRec(
            emergencyContact: 'Luis Santos · +63 917 222 3344',
            occupants: 1,
            name: 'Grace Santos',
            unit: 'Unit 101',
            phone: '+63 918 222 3344',
            email: 'grace@email.com',
            stayType: 'Monthly',
            rent: 7500,
            leaseStart: 'Aug 01, 2026',
            leaseEnd: 'Jul 31, 2027',
            username: 'grace101',
            password: 'ayan2468',
            balance: 0,
            deposit: 7500,
            docs: {
              'Valid ID': true,
              'ID picture': true,
              'Barangay clearance': true,
              'Police clearance': true,
              'NBI clearance': true,
            },
            paidFrom: DateTime(2026, 8, 1),
            paidUntil: DateTime(2026, 10, 31),
          ),
          TenantRec(
            emergencyContact: 'Elena Garcia · +63 920 111 2233',
            occupants: 3,
            name: 'Paolo Garcia',
            unit: 'Villa 2',
            phone: '+63 920 777 8899',
            email: 'paolo@email.com',
            stayType: 'Yearly',
            rent: 24000,
            leaseStart: 'Nov 15, 2025',
            leaseEnd: 'Nov 14, 2026',
            username: 'paolo2',
            password: 'ayan1357',
            balance: 24000,
            deposit: 24000,
            docs: {
              'Valid ID': true,
              'ID picture': true,
              'Barangay clearance': false,
              'Police clearance': false,
              'NBI clearance': false,
              'Passport': true,
              'Visa': true,
              'EID': false,
              'Ejari': false,
            },
            paidFrom: DateTime(2025, 11, 15),
            paidUntil: DateTime(2026, 9, 30),
          ),
          // A condo guest: day-to-day stay, so no lease year and no announcements.
          // Condo guests have no app account; their stays are kept as bookings.
        ]
      : [];

  final List<PaymentRec> payments = demoData
      ? [
          PaymentRec(
            id: 'P-31',
            tenant: 'Juan Dela Cruz',
            unit: 'Unit 402',
            title: 'October rent',
            amount: 8000,
            method: 'GCash',
            reference: '4821 0092',
            date: 'Oct 26, 2026',
          ),
          PaymentRec(
            id: 'P-30',
            tenant: 'Liza Fernandez',
            unit: 'Villa 1',
            title: '2 months advance + deposit',
            amount: 66000,
            method: 'BDO transfer',
            reference: '7731 2214',
            date: 'Oct 26, 2026',
          ),
          PaymentRec(
            id: 'P-29',
            tenant: 'Grace Santos',
            unit: 'Unit 101',
            title: 'October rent',
            amount: 7500,
            method: 'GCash',
            reference: '1190 5521',
            date: 'Oct 4, 2026',
            status: PayStatus.verified,
          ),
          PaymentRec(
            id: 'P-28',
            tenant: 'Paolo Garcia',
            unit: 'Villa 2',
            title: 'September rent',
            amount: 24000,
            method: 'GCash',
            reference: '9023 1176',
            date: 'Sep 5, 2026',
            status: PayStatus.verified,
          ),
        ]
      : [];

  final List<ChargeRec> charges = demoData
      ? [
          // Monthly rent for apartments is added by generateRentCharges() from each
          // lease (rent, due day, dates); other charges are added by the admin.
          ChargeRec(
            tenant: 'Grace Santos',
            title: 'Water bill',
            amount: 450,
            due: 'Oct 20, 2026',
            paid: true,
          ),
        ]
      : [];

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

  /// How many days before the due day a month's rent charge appears.
  int rentChargeLeadDays = 10;

  /// Adds each apartment tenant's monthly rent charges from their lease: one
  /// per month, for the lease's rent, due on the lease's due day (the last
  /// day in shorter months). Starts after what is already paid (paid-until)
  /// and runs up to the month whose due day is within [rentChargeLeadDays];
  /// stops at the lease end. Never adds the same month twice. A due date
  /// already passed is marked overdue. Runs when the app opens and when a
  /// lease changes (with a backend: once a day).
  void generateRentCharges() {
    final today = DateTime(
      appState.today.year,
      appState.today.month,
      appState.today.day,
    );
    final horizon = today.add(Duration(days: rentChargeLeadDays));
    for (final t in tenants) {
      if (_unit(t.unit)?.type != 'Apartment') {
        continue; // villas: cheques; condos: by hand
      }
      final start = parseDate(t.leaseStart);
      final end = parseDate(t.leaseEnd);
      if (start == null || end == null) continue;
      var m = DateTime(start.year, start.month);
      while (true) {
        final due = dueDateIn(m.year, m.month, t.dueDay);
        if (due.isAfter(horizon) || due.isAfter(end)) break;
        final covered = t.paidUntil != null && !t.paidUntil!.isBefore(due);
        final title = '${_monthNames[m.month - 1]} ${m.year} rent';
        final existing = charges
            .where((c) => c.tenant == t.name && c.title == title)
            .firstOrNull;
        if (existing != null && !existing.paid) {
          // Already listed: keep it in step with the lease.
          existing
            ..due = formatDate(due)
            ..amount = t.rent;
        } else if (!covered && existing == null) {
          charges.add(
            ChargeRec(
              tenant: t.name,
              title: title,
              amount: t.rent,
              due: formatDate(due),
              overdue: due.isBefore(today),
            ),
          );
        }
        m = DateTime(m.year, m.month + 1);
      }
    }
    // Keep overdue flags current for every open charge.
    for (final c in charges.where((c) => !c.paid)) {
      final d = parseDate(c.due);
      if (d != null) c.overdue = d.isBefore(today);
    }
  }

  final List<DamageReport> reports = demoData
      ? [
          DamageReport(
            id: 'TK-1082',
            tenant: 'Juan Dela Cruz',
            unit: 'Unit 402',
            issue: 'Bathroom sink faucet leaking',
            description: 'Water dripping constantly under the pipe joint in master bath.',
            date: 'Oct 22, 2026',
            attachments: 2,
            type: ReportType.maintenance,
            updates: [
              ReportUpdate(
                'Plumber booked for Oct 29, 9:00 AM. Please keep the area clear.',
                'Oct 23, 2026',
              ),
            ],
          ),
          DamageReport(
            id: 'TK-1079',
            tenant: 'Grace Santos',
            unit: 'Unit 101',
            issue: 'Cracked window glass',
            description: 'Living room window cracked after a heavy wind.',
            date: 'Oct 20, 2026',
            attachments: 3,
            status: ReportStatus.underReview,
          ),
          DamageReport(
              id: 'TK-1070',
              tenant: 'Paolo Garcia',
              unit: 'Villa 2',
              issue: 'Broken gate lock',
              description: 'Front gate lock no longer latches.',
              date: 'Oct 12, 2026',
              attachments: 1,
              status: ReportStatus.approved,
            )
            ..kind = DamageKind.accident
            ..note = 'Worn lock, replaced by management.',
        ]
      : [];

  /// What management wrote (building-wide or to one unit), without the
  /// app's automatic notices.
  List<AdminNotice> get announcements =>
      notices.where((n) => !n.automatic).toList();

  final List<AdminNotice> notices = demoData
      ? [
          AdminNotice(
            id: 'n1',
            title: 'Scheduled Water Main Interruption',
            body: 'Supply will be shut off from 1:00 PM to 5:00 PM today.',
            kind: NoticeKind.emergency,
            date: 'Today, 8:00 AM',
            recipients: _audienceSeed,
            readBy: {'Grace Santos', 'Paolo Garcia'},
          ),
          AdminNotice(
            id: 'n2',
            title: 'Monthly Elevator Maintenance',
            body: 'Elevator 2 inspection on Sunday, 10:00 AM - 12:00 PM.',
            kind: NoticeKind.schedule,
            date: 'Oct 20, 2026',
            recipients: _audienceSeed,
            readBy: {'Grace Santos', 'Paolo Garcia'},
          ),
        ]
      : [];

  final List<AdminMessage> messages = demoData
      ? [
          AdminMessage(
            tenant: 'Juan Dela Cruz',
            unit: 'Unit 402',
            category: 'Security / Parking Request',
            body: 'Is there an available parking slot for guests this weekend?',
            date: 'Oct 18',
            reply: 'Yes, Slot B-12 is reserved for Oct 24-25.',
          ),
          AdminMessage(
            tenant: 'Grace Santos',
            unit: 'Unit 101',
            category: 'Suggestion / Feedback',
            body: 'Can we get a bike rack near the entrance?',
            date: 'Today',
          ),
          AdminMessage(
            tenant: 'Paolo Garcia',
            unit: 'Villa 2',
            category: 'Private Complaint',
            body: 'The neighbor plays loud music after 10 PM.',
            date: 'Yesterday',
          ),
        ]
      : [];

  final List<ComplaintRec> complaints = demoData
      ? [
          ComplaintRec(
            tenant: 'Paolo Garcia',
            unit: 'Villa 2',
            category: 'Noise',
            body:
                'The neighbor plays loud music after 10 PM almost every night.',
            date: 'Yesterday',
          ),
          ComplaintRec(
            tenant: 'Grace Santos',
            unit: 'Unit 101',
            category: 'Cleanliness',
            body: 'The hallway trash bin on the 1st floor has not been emptied for days.',
            date: 'Oct 24',
            status: ComplaintStatus.inProgress,
            response: 'Housekeeping has been told. Pickup is scheduled tomorrow morning.',
          ),
          ComplaintRec(
            tenant: 'Juan Dela Cruz',
            unit: 'Unit 402',
            category: 'Facilities',
            body: 'Elevator 2 keeps stopping between floors.',
            date: 'Oct 19',
            status: ComplaintStatus.resolved,
            response: 'Technician fixed the elevator on Oct 21.',
          ),
        ]
      : [];

  // ------------------------------------------------------------- Cheques

  final List<ChequeRec> cheques = demoData
      ? [
          ChequeRec(
            id: 'CH-1',
            tenant: 'Paolo Garcia',
            kind: ChequeKind.deposit,
            amount: 24000,
            date: DateTime(2023, 11, 15),
            chequeNo: '000101',
            bank: 'Emirates NBD',
            status: ChequeStatus.held,
          ),
          // Earlier lease years (renewed each November), so past years have history:
          // 2023-2024 paid in one cheque, 2024-2025 in two (one bounced and was replaced).
          ChequeRec(
            id: 'CH-90',
            tenant: 'Paolo Garcia',
            kind: ChequeKind.postDated,
            amount: 264000,
            date: DateTime(2023, 11, 15),
            months: 12,
            chequeNo: '000102',
            bank: 'Emirates NBD',
            status: ChequeStatus.cleared,
          ),
          ChequeRec(
            id: 'CH-91',
            tenant: 'Paolo Garcia',
            kind: ChequeKind.postDated,
            amount: 138000,
            date: DateTime(2024, 11, 15),
            months: 6,
            chequeNo: '000231',
            bank: 'Emirates NBD',
            status: ChequeStatus.cleared,
          ),
          ChequeRec(
            id: 'CH-92',
            tenant: 'Paolo Garcia',
            kind: ChequeKind.postDated,
            amount: 138000,
            date: DateTime(2025, 5, 15),
            months: 6,
            chequeNo: '000232',
            bank: 'Emirates NBD',
            status: ChequeStatus.bounced,
          ),
          ChequeRec(
            id: 'CH-93',
            tenant: 'Paolo Garcia',
            kind: ChequeKind.postDated,
            amount: 138000,
            date: DateTime(2025, 5, 20),
            months: 6,
            chequeNo: '7710',
            bank: 'ADCB',
            status: ChequeStatus.cleared,
          ),
          ChequeRec(
            id: 'CH-2',
            tenant: 'Paolo Garcia',
            kind: ChequeKind.postDated,
            amount: 72000,
            date: DateTime(2025, 11, 15),
            months: 3,
            chequeNo: '000452',
            bank: 'Emirates NBD',
            status: ChequeStatus.cleared,
          ),
          ChequeRec(
            id: 'CH-3',
            tenant: 'Paolo Garcia',
            kind: ChequeKind.postDated,
            amount: 72000,
            date: DateTime(2026, 2, 15),
            months: 3,
            chequeNo: '000453',
            bank: 'Emirates NBD',
            status: ChequeStatus.cleared,
          ),
          ChequeRec(
            id: 'CH-4',
            tenant: 'Paolo Garcia',
            kind: ChequeKind.postDated,
            amount: 72000,
            date: DateTime(2026, 5, 15),
            months: 3,
            chequeNo: '000454',
            bank: 'Emirates NBD',
            status: ChequeStatus.cleared,
          ),
          ChequeRec(
            id: 'CH-5',
            tenant: 'Paolo Garcia',
            kind: ChequeKind.postDated,
            amount: 72000,
            date: DateTime(2026, 8, 15),
            months: 3,
            chequeNo: '000455',
            bank: 'Emirates NBD',
            status: ChequeStatus.deposited,
          ),
        ]
      : [];
  int _chequeSeq = 6;

  List<ChequeRec> chequesFor(String tenant) =>
      cheques.where((c) => c.tenant == tenant).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  /// Post-dated cheques whose date has come: ready to take to the bank.
  List<ChequeRec> get chequesToBank =>
      cheques
          .where(
            (c) =>
                c.kind == ChequeKind.postDated &&
                c.status == ChequeStatus.held &&
                !c.date.isAfter(appState.today),
          )
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  /// Cheques banked but not yet confirmed as cleared (or bounced).
  List<ChequeRec> get chequesDeposited =>
      cheques.where((c) => c.status == ChequeStatus.deposited).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  /// The next post-dated cheque still to be banked or cleared (a bounced one
  /// is replaced by a new cheque, so it is not "next").
  ChequeRec? nextCheque(String tenant) => chequesFor(tenant)
      .where(
        (c) =>
            c.kind == ChequeKind.postDated &&
            (c.status == ChequeStatus.held ||
                c.status == ChequeStatus.deposited),
      )
      .firstOrNull;

  /// Cheques the tenant still has to send a photo of: not yet cleared or
  /// bounced, and no photo yet. Oldest first.
  List<ChequeRec> chequesNeedingPhoto(String tenant) => chequesFor(tenant)
      .where(
        (c) =>
            !c.hasPhoto &&
            (c.status == ChequeStatus.held ||
                c.status == ChequeStatus.deposited),
      )
      .toList();

  /// The cheque a tenant's next photo belongs to by default: the earliest
  /// post-dated one still waiting for a photo.
  ChequeRec? chequeAwaitingPhoto(String tenant) =>
      chequesNeedingPhoto(tenant)
          .where((c) => c.kind == ChequeKind.postDated)
          .firstOrNull;

  /// Cheques with a photo management has not looked at yet.
  List<ChequeRec> get chequesWithNewPhotos =>
      cheques.where((c) => c.newPhoto).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  /// The tenant uploads a photo of a cheque: of [to] when they picked one,
  /// otherwise of the cheque waiting for one. With no cheque on file, a new
  /// one is added for management to fill in and verify.
  ChequeRec uploadChequePhoto(String tenant, Uint8List bytes, {ChequeRec? to}) {
    var c = to ?? chequeAwaitingPhoto(tenant);
    if (c == null) {
      final t = tenants.where((x) => x.name == tenant).firstOrNull;
      final months = 12 ~/ (t?.chequesPerYear ?? 4);
      addCheque(
        tenant,
        ChequeKind.postDated,
        (t == null ? 0.0 : monthlyRentOf(t)) * months,
        appState.today,
        months: months,
      );
      c = cheques.last;
    }
    c
      ..photo = bytes
      ..uploadedOn = formatDate(appState.today)
      ..photoChecked = false;
    notifyListeners();
    return c;
  }

  void addCheque(
    String tenant,
    ChequeKind kind,
    double amount,
    DateTime date, {
    int months = 0,
    String chequeNo = '',
    String bank = '',
  }) {
    cheques.add(
      ChequeRec(
        id: 'CH-${_chequeSeq++}',
        tenant: tenant,
        kind: kind,
        amount: amount,
        date: date,
        months: months,
        chequeNo: chequeNo,
        bank: bank,
      ),
    );
    notifyListeners();
  }

  /// Sets up the year's post-dated cheques: [perYear] of them (1 to 4), each
  /// paying 12 / perYear months of rent, dated from the lease start. Cheques
  /// not yet banked are replaced.
  ///
  /// [yearStart] picks which lease year (from [leaseYears]); the first one
  /// when left out. Only that year's unbanked cheques are replaced, and a
  /// date that already has a banked cheque is skipped, so nothing doubles up.
  void planCheques(
    TenantRec t,
    int perYear, {
    DateTime? yearStart,
    double? rent,
  }) {
    final monthly = monthlyRentOf(t, rent);
    final start = yearStart ?? (parseDate(t.leaseStart) ?? appState.today);
    final end = dueDateIn(start.year + 1, start.month, start.day);
    bool inYear(DateTime d) => !d.isBefore(start) && d.isBefore(end);
    final months = 12 ~/ perYear;
    cheques.removeWhere(
      (c) =>
          c.tenant == t.name &&
          c.kind == ChequeKind.postDated &&
          c.status == ChequeStatus.held &&
          inYear(c.date),
    );
    for (var i = 0; i < perYear; i++) {
      final d = dueDateIn(start.year, start.month + i * months, start.day);
      final banked = cheques.any(
        (c) =>
            c.tenant == t.name && c.kind == ChequeKind.postDated && c.date == d,
      );
      if (!banked) {
        addCheque(
          t.name,
          ChequeKind.postDated,
          monthly * months,
          d,
          months: months,
        );
      }
    }
    // Tell the tenant which cheques to prepare and photograph.
    final label = '${start.year}-${start.year + 1}';
    notifyTenant(
      t,
      'Cheques for $label',
      'Management set up $perYear post-dated ${perYear == 1 ? 'cheque' : 'cheques'} of ${peso(monthly * months, dhs: true)} for $label, '
          'the first dated ${formatDate(start)}. Please upload a photo of each one under Upload Cheques.',
    );
  }

  /// One month's rent for a tenant. The rent is entered the way the unit is
  /// priced: a villa priced by the year (AED 300,000 a year) is AED 25,000 a
  /// month, so 4 cheques of 3 months each are AED 75,000. [rent] overrides
  /// the tenant's current rent (e.g. a renewal's new rent).
  /// How a tenant's rent is counted, from how their unit is priced:
  /// "year", "week", "night" or "month".
  String rentPeriodOf(TenantRec? t) =>
      switch (t == null ? null : _unit(t.unit)?.rateUnit) {
        'year' => 'year',
        'week' => 'week',
        'night' => 'night',
        _ => 'month',
      };

  /// "Yearly rent", "Monthly rent", "Weekly rent" or "Nightly rate".
  String rentLabelOf(TenantRec? t) => switch (rentPeriodOf(t)) {
    'year' => 'Yearly rent',
    'week' => 'Weekly rent',
    'night' => 'Nightly rate',
    _ => 'Monthly rent',
  };

  double monthlyRentOf(TenantRec t, [double? rent]) {
    final r = rent ?? t.rent;
    return switch (_unit(t.unit)?.rateUnit) {
      'year' => r / 12,
      'week' => r * 52 / 12,
      'night' => r * 365 / 12,
      _ => r,
    };
  }

  /// The first day of the lease year [d] falls in. Lease years run from the
  /// lease start date (Nov 15, 2025 - Nov 14, 2026, then Nov 15, 2026 - ...).
  DateTime leaseYearOf(TenantRec t, DateTime d) {
    final a = parseDate(t.leaseStart) ?? DateTime(d.year, 1, 1);
    var months = (d.year - a.year) * 12 + d.month - a.month;
    if (d.day < a.day) months--;
    final k = (months / 12).floor();
    return dueDateIn(a.year + k, a.month, a.day);
  }

  /// The lease years a cheque can be planned for: every year of the lease,
  /// any year that already has cheques, plus the year after (for a renewal).
  List<DateTime> leaseYears(TenantRec t) {
    final a = parseDate(t.leaseStart) ?? appState.today;
    final e = parseDate(t.leaseEnd) ?? a;
    final years = <DateTime>{
      for (
        var d = leaseYearOf(t, a);
        !d.isAfter(e);
        d = dueDateIn(d.year + 1, d.month, a.day)
      )
        d,
      for (final c in chequesFor(t.name))
        if (c.kind == ChequeKind.postDated) leaseYearOf(t, c.date),
    }.toList()..sort();
    final last = years.isEmpty ? leaseYearOf(t, a) : years.last;
    return years..add(dueDateIn(last.year + 1, last.month, a.day));
  }

  /// Moves a cheque along: held, deposited, cleared or bounced, and tells the
  /// tenant. A post-dated cheque that clears is recorded as a payment (so it
  /// shows in payment history and the AED totals) and extends the tenant's
  /// paid-through date.
  void setChequeStatus(ChequeRec c, ChequeStatus status) {
    final old = c.status;
    final photoWasNew = c.newPhoto;
    c.status = status;
    if (status != old) {
      _log(
        'Cheque ${status.name}',
        '${c.tenant}: ${peso(c.amount, dhs: true)} dated ${formatDate(c.date)}',
      );
    }
    if (c.hasPhoto) c.photoChecked = true;
    final t = tenants.where((x) => x.name == c.tenant).firstOrNull;
    final amount = peso(c.amount, dhs: true);
    final when = formatDate(c.date);

    if (status == ChequeStatus.cleared &&
        old != ChequeStatus.cleared &&
        c.kind == ChequeKind.postDated) {
      final from = t?.paidUntil?.add(const Duration(days: 1));
      if (t?.paidUntil != null && c.months > 0) {
        t!.paidUntil = addMonthsToPaidUntil(t.paidUntil!, c.months);
      }
      _paymentFromCheque(c, t, from);
    }

    if (t == null || status == old) {
      // Same status: the admin only looked at the photo.
      if (t != null && photoWasNew) {
        notifyTenant(
          t,
          'Cheque photo checked',
          'Management checked the photo of your $amount cheque dated $when. Thank you.',
        );
      }
    } else {
      switch (status) {
        case ChequeStatus.deposited:
          notifyTenant(
            t,
            'Cheque deposited',
            'Your $amount cheque dated $when was deposited. We will let you know when it clears.',
          );
        case ChequeStatus.cleared:
          notifyTenant(
            t,
            'Cheque cleared',
            'Your $amount cheque dated $when has cleared. ${c.kind == ChequeKind.postDated ? 'Your rent is paid until ${t.paidUntil == null ? '-' : formatDate(t.paidUntil!)}.' : ''}',
          );
        case ChequeStatus.bounced:
          final fee = bouncedChequeFee;
          if (c.kind == ChequeKind.postDated) {
            // A replacement is expected within a week, for the same amount
            // and months. The tenant uploads a photo of it like any cheque.
            addCheque(
              t.name,
              ChequeKind.postDated,
              c.amount,
              _day(appState.today).add(const Duration(days: 7)),
              months: c.months,
            );
            cheques.last.replaces = c.id;
          }
          if (fee > 0) {
            addCharge(
              t.name,
              'Bounced cheque fee${c.chequeNo.isEmpty ? '' : ' (#${c.chequeNo})'}',
              fee,
              formatDate(_day(appState.today).add(const Duration(days: 7))),
              notify: false,
            );
          }
          notifyTenant(
            t,
            'Cheque bounced',
            'Your $amount cheque dated $when was returned by the bank. Please give a replacement cheque within 7 days'
                '${fee > 0 ? ' and pay the ${peso(fee, dhs: true)} bounced cheque fee' : ''}. '
                'Upload a photo of the new cheque under Upload Cheques.',
          );
        case ChequeStatus.held:
          if (photoWasNew) {
            notifyTenant(
              t,
              'Cheque photo checked',
              'Management checked the photo of your $amount cheque dated $when. Thank you.',
            );
          }
      }
    }
    notifyListeners();
  }

  /// A cleared post-dated cheque becomes a verified payment in the history.
  void _paymentFromCheque(ChequeRec c, TenantRec? t, DateTime? from) {
    final date = formatDate(appState.today);
    payments.insert(
      0,
      PaymentRec(
        id: 'P-${payments.length + 30}',
        tenant: c.tenant,
        unit: t?.unit ?? '',
        title: c.months == 1
            ? 'Rent · 1 month (cheque)'
            : 'Rent · ${c.months} months (cheque)',
        amount: c.amount,
        method: 'Cheque${c.bank.isEmpty ? '' : ' · ${c.bank}'}',
        reference: c.chequeNo.isEmpty ? '-' : c.chequeNo,
        date: date,
        status: PayStatus.verified,
        recordedByAdmin: true,
        months: c.months,
        coversFrom: from,
        coversTo: t?.paidUntil,
      ),
    );
    if (c.tenant == appState.currentTenant) {
      appState.recordManualPayment(
        title: 'Rent · ${c.months} months (cheque)',
        method: 'Cheque',
        amount: c.amount,
        reference: c.chequeNo.isEmpty ? '-' : c.chequeNo,
        date: date,
        clearsRent: false,
      );
    }
  }

  /// Reminds tenants a few days before a post-dated cheque's date, once per
  /// cheque, so the account has the money. Run when the app opens.
  void sendChequeReminders({int daysBefore = 3}) {
    final today = appState.today;
    for (final c in cheques) {
      final days = DateTime(
        c.date.year,
        c.date.month,
        c.date.day,
      ).difference(DateTime(today.year, today.month, today.day)).inDays;
      if (c.kind != ChequeKind.postDated ||
          c.status != ChequeStatus.held ||
          c.reminded ||
          days < 0 ||
          days > daysBefore) {
        continue;
      }
      final t = tenants.where((x) => x.name == c.tenant).firstOrNull;
      if (t == null) continue;
      c.reminded = true;
      notifyTenant(
        t,
        'Cheque date coming up',
        'Your ${peso(c.amount, dhs: true)} cheque is dated ${formatDate(c.date)}${days == 0 ? ' (today)' : ' (in $days ${days == 1 ? 'day' : 'days'})'}. Please make sure the funds are in your account.',
      );
    }
  }

  /// Changes a cheque's details (amount, date, months, number, bank).
  void updateCheque(
    ChequeRec c, {
    required double amount,
    required DateTime date,
    required int months,
    required String chequeNo,
    required String bank,
  }) {
    c
      ..amount = amount
      ..date = date
      ..months = months
      ..chequeNo = chequeNo
      ..bank = bank;
    _log(
      'Cheque edited',
      '${c.tenant}: ${peso(amount, dhs: true)} dated ${formatDate(date)}',
    );
    notifyListeners();
  }

  void removeCheque(ChequeRec c) {
    if (whyKeepCheque(c) != null) return;
    cheques.remove(c);
    notifyListeners();
  }

  // ------------------------------------------------- condo bookings & costs

  // Demo stays, all with a contact number and deposit. The demo's "today" is
  // Oct 26, 2026: stays before it are past (kept on record with their
  // guest, contact and deposit), Liza Cruz is in now, the rest are upcoming.
  final List<Booking> bookings = demoData
      ? [
          // Studio 3 (₱2,500 a night)
          Booking(
            id: 'B-1',
            unit: 'Studio 3',
            guest: 'Jessa Tan',
            phone: '+63 917 210 3344',
            guests: 2,
            checkIn: DateTime(2026, 9, 12, 14),
            checkOut: DateTime(2026, 9, 14, 12),
            amount: 5000,
            deposit: 2500,
          ),
          Booking(
            id: 'B-2',
            unit: 'Studio 3',
            guest: 'Rico Bautista',
            phone: '+63 918 552 0198',
            guests: 1,
            checkIn: DateTime(2026, 10, 3, 14),
            checkOut: DateTime(2026, 10, 6, 12),
            amount: 7500,
            deposit: 2500,
          ),
          Booking(
            id: 'B-3',
            unit: 'Studio 3',
            guest: 'Mark Lim',
            phone: '+63 917 880 1122',
            guests: 2,
            checkIn: DateTime(2026, 10, 20, 14),
            checkOut: DateTime(2026, 10, 22, 12),
            amount: 5000,
            deposit: 2500,
          ),
          Booking(
            id: 'B-4',
            unit: 'Studio 3',
            guest: 'Liza Cruz',
            phone: '+63 915 774 2210',
            guests: 2,
            checkIn: DateTime(2026, 10, 25, 14),
            checkOut: DateTime(2026, 10, 27, 12),
            amount: 5000,
            deposit: 2500,
          ),
          Booking(
            id: 'B-5',
            unit: 'Studio 3',
            guest: 'Carlo Mendoza',
            phone: '+63 921 456 7788',
            guests: 1,
            checkIn: DateTime(2026, 10, 30, 14),
            checkOut: DateTime(2026, 11, 2, 12),
            amount: 7500,
            deposit: 2500,
          ),
          Booking(
            id: 'B-6',
            unit: 'Studio 3',
            guest: 'Anna Reyes',
            phone: '+63 918 333 4455',
            guests: 3,
            checkIn: DateTime(2026, 11, 14, 14),
            checkOut: DateTime(2026, 11, 16, 11),
            amount: 5000,
            deposit: 2500,
          ),
          Booking(
            id: 'B-7',
            unit: 'Studio 3',
            guest: 'Paul Navarro',
            phone: '+63 927 610 8890',
            guests: 2,
            checkIn: DateTime(2026, 11, 20, 14),
            checkOut: DateTime(2026, 11, 23, 12),
            amount: 7500,
            deposit: 2500,
          ),
          Booking(
            id: 'B-8',
            unit: 'Studio 3',
            guest: 'Mia Santos',
            phone: '+63 916 402 7715',
            guests: 4,
            checkIn: DateTime(2026, 12, 24, 14),
            checkOut: DateTime(2026, 12, 27, 12),
            amount: 7500,
            deposit: 2500,
          ),
          // Condo 7A (₱14,000 a month, so about ₱467 a night)
          Booking(
            id: 'B-9',
            unit: 'Condo 7A',
            guest: 'Ken Villareal',
            phone: '+63 919 230 5561',
            guests: 2,
            checkIn: DateTime(2026, 9, 1, 14),
            checkOut: DateTime(2026, 9, 30, 12),
            amount: 13533,
            deposit: 14000,
          ),
          Booking(
            id: 'B-10',
            unit: 'Condo 7A',
            guest: 'Sarah Lopez',
            phone: '+63 917 845 0032',
            guests: 1,
            checkIn: DateTime(2026, 10, 10, 14),
            checkOut: DateTime(2026, 10, 17, 12),
            amount: 3267,
            deposit: 3000,
          ),
          Booking(
            id: 'B-11',
            unit: 'Condo 7A',
            guest: 'Joel Ramos',
            phone: '+63 922 118 6094',
            guests: 3,
            checkIn: DateTime(2026, 11, 5, 14),
            checkOut: DateTime(2026, 12, 5, 12),
            amount: 14000,
            deposit: 14000,
          ),
        ]
      : [];
  int _bookingSeq = 12;

  /// A unit's bookings, earliest first.
  List<Booking> bookingsFor(String unit) =>
      bookings.where((b) => b.unit == unit).toList()
        ..sort((a, b) => a.checkIn.compareTo(b.checkIn));

  /// The guest staying now, if any (the demo's "now" is appState.today).
  /// The calendar day of a moment (time of day dropped).
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The guest staying today: tonight is one of their nights (from the
  /// check-in day up to the night before check-out). Counted by day, so a
  /// guest arriving this afternoon is already "in" for the day.
  Booking? currentBooking(String unit) {
    final today = _day(appState.today);
    return bookingsFor(unit)
        .where(
          (b) =>
              !_day(b.checkIn).isAfter(today) &&
              _day(b.checkOut).isAfter(today),
        )
        .firstOrNull;
  }

  /// The next guest to arrive (from tomorrow on).
  Booking? nextBooking(String unit) =>
      bookingsFor(unit)
          .where((b) => _day(b.checkIn).isAfter(_day(appState.today)))
          .firstOrNull;

  /// A booking for this unit whose dates overlap [checkIn]-[checkOut].
  Booking? clashingBooking(
    String unit,
    DateTime checkIn,
    DateTime checkOut, {
    Booking? except,
  }) => bookingsFor(unit)
      .where(
        (b) =>
            b != except &&
            b.checkIn.isBefore(checkOut) &&
            checkIn.isBefore(b.checkOut),
      )
      .firstOrNull;

  /// Adds or edits a booking (pass [existing] to edit).
  void saveBooking(Booking? existing, Booking data) {
    _log(
      existing == null ? 'Booking added' : 'Booking edited',
      '${data.guest} (${data.unit}), ${formatDate(data.checkIn)} - ${formatDate(data.checkOut)}',
    );
    if (existing == null) {
      bookings.add(
        Booking(
          id: 'B-${_bookingSeq++}',
          unit: data.unit,
          guest: data.guest,
          phone: data.phone,
          guests: data.guests,
          checkIn: data.checkIn,
          checkOut: data.checkOut,
          amount: data.amount,
          deposit: data.deposit,
          files: [...data.files],
        ),
      );
    } else {
      existing
        ..guest = data.guest
        ..phone = data.phone
        ..guests = data.guests
        ..checkIn = data.checkIn
        ..checkOut = data.checkOut
        ..amount = data.amount
        ..deposit = data.deposit;
      existing.files
        ..clear()
        ..addAll(data.files);
    }
    refreshCondoStatuses();
    notifyListeners();
  }

  /// Deposit deductions on this unit's stays made in [month], newest first.
  List<({Booking stay, double amount, String reason, DateTime date})>
  deductionsIn(String unit, DateTime month) => [
    for (final b in bookingsFor(unit))
      for (final d in b.deductions)
        if (d.date.year == month.year && d.date.month == month.month)
          (stay: b, amount: d.amount, reason: d.reason, date: d.date),
  ]..sort((a, b) => b.date.compareTo(a.date));

  /// Takes [amount] off a stay's security deposit, with a reason.
  void deductDeposit(Booking b, double amount, String reason) {
    b.deductions.add((amount: amount, reason: reason, date: appState.today));
    _log(
      'Deposit deducted',
      '${b.guest} (${b.unit}): ${peso(amount)} for $reason',
    );
    notifyListeners();
  }

  void removeBooking(Booking b) {
    if (whyKeepBooking(b) != null) return;
    _log('Booking removed', '${b.guest} (${b.unit}), ${formatDate(b.checkIn)}');
    bookings.remove(b);
    refreshCondoStatuses();
    notifyListeners();
  }

  /// A condo's status follows its bookings: Occupied while a guest is
  /// inside their stay, Reserved when a stay is coming up, otherwise Vacant.
  UnitStatus condoStatus(UnitRec u) {
    if (currentBooking(u.name) != null) return UnitStatus.occupied;
    if (nextBooking(u.name) != null) return UnitStatus.reserved;
    return UnitStatus.vacant;
  }

  /// Sets every condo's status from its bookings. Runs when the app opens
  /// and whenever a booking changes (with a backend: also on a timer).
  void refreshCondoStatuses() {
    for (final u in units.where((u) => u.type == 'Condo')) {
      u.status = condoStatus(u);
    }
    // A finished stay keeps its full record (guest, contact, files); only the
    // unit moves on: its status and deposit card follow the next guest.
  }

  /// Operating costs by unit name.
  final Map<String, List<CostEntry>> unitCosts = demoData
      ? {
          'Studio 3': [
            CostEntry(
              title: 'Electricity',
              amount: 1100,
              date: DateTime(2026, 9, 5),
            ),
            CostEntry(
              title: 'Cleaning',
              amount: 500,
              date: DateTime(2026, 9, 14),
            ),
            CostEntry(
              title: 'Internet',
              amount: 1299,
              date: DateTime(2026, 9, 20),
            ),
            CostEntry(
              title: 'Electricity',
              amount: 1200,
              date: DateTime(2026, 10, 5),
            ),
            CostEntry(
              title: 'Cleaning',
              amount: 500,
              date: DateTime(2026, 10, 6),
            ),
            CostEntry(
              title: 'Internet',
              amount: 1299,
              date: DateTime(2026, 10, 20),
            ),
            CostEntry(
              title: 'Cleaning',
              amount: 500,
              date: DateTime(2026, 10, 22),
            ),
            CostEntry(
              title: 'Toiletries and linens',
              amount: 350,
              date: DateTime(2026, 10, 24),
            ),
          ],
          'Condo 7A': [
            CostEntry(title: 'Water', amount: 450, date: DateTime(2026, 9, 8)),
            CostEntry(
              title: 'Electricity',
              amount: 2300,
              date: DateTime(2026, 9, 30),
            ),
            CostEntry(
              title: 'Cleaning',
              amount: 800,
              date: DateTime(2026, 10, 1),
            ),
            CostEntry(
              title: 'Electricity',
              amount: 900,
              date: DateTime(2026, 10, 17),
            ),
            CostEntry(
              title: 'Repairs',
              amount: 1500,
              date: DateTime(2026, 10, 18),
            ),
            CostEntry(
              title: 'Cleaning',
              amount: 800,
              date: DateTime(2026, 10, 25),
            ),
          ],
        }
      : {};

  List<CostEntry> costsFor(String unit) =>
      (unitCosts[unit] ?? const <CostEntry>[]).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  /// Costs for a unit in the month of [month].
  double costsInMonth(String unit, DateTime month) => costsFor(unit)
      .where((c) => c.date.year == month.year && c.date.month == month.month)
      .fold(0.0, (n, c) => n + c.amount);

  /// What the unit's bookings brought in that month (by check-in date).
  double bookingIncomeInMonth(String unit, DateTime month) => bookingsFor(unit)
      .where(
        (b) => b.checkIn.year == month.year && b.checkIn.month == month.month,
      )
      .fold(0.0, (n, b) => n + b.amount);

  void addCost(String unit, CostEntry c) {
    unitCosts.putIfAbsent(unit, () => []).add(c);
    _log('Cost added', '$unit: ${c.title}, ${peso(c.amount)}');
    notifyListeners();
  }

  // ---- monthly expenses (recurring, per unit)

  /// Each unit's recurring monthly expenses, by unit name.
  final Map<String, List<MonthlyExpense>> monthlyExpenses = demoData
      ? {
          'Unit 402': [
            MonthlyExpense(
              name: 'Internet',
              amount: 1299,
              since: DateTime(2026, 1),
            ),
            MonthlyExpense(
              name: 'Netflix',
              amount: 549,
              since: DateTime(2026, 3),
            ),
          ],
          'Unit 101': [
            MonthlyExpense(
              name: 'Internet',
              amount: 1299,
              since: DateTime(2026, 8),
            ),
          ],
          'Studio 3': [
            MonthlyExpense(
              name: 'Netflix',
              amount: 549,
              since: DateTime(2026, 6),
            ),
          ],
          'Condo 7A': [
            MonthlyExpense(
              name: 'Association dues',
              amount: 2500,
              since: DateTime(2026, 1),
            ),
          ],
        }
      : {};

  /// Saved monthly expenses to add quickly, per unit type.
  final List<ExpenseTemplate> expenseTemplates = demoData
      ? [
          ExpenseTemplate(
            name: 'Internet',
            amount: 1299,
            unitType: 'Apartment',
          ),
          ExpenseTemplate(name: 'Netflix', amount: 549, unitType: 'Apartment'),
          ExpenseTemplate(name: 'Netflix', amount: 549, unitType: 'Condo'),
          ExpenseTemplate(
            name: 'Association dues',
            amount: 2500,
            unitType: 'Condo',
          ),
          ExpenseTemplate(name: 'Cable TV', amount: 699, unitType: 'Condo'),
        ]
      : [];

  /// The templates for one unit type ("Apartment" or "Condo").
  List<ExpenseTemplate> expenseTemplatesFor(String unitType) =>
      expenseTemplates.where((t) => t.unitType == unitType).toList();

  /// Saves a template for [unitType]; one with the same name (any capitals)
  /// is updated instead of added twice.
  void saveExpenseTemplate(String unitType, String name, double amount) {
    final n = name.trim();
    final existing = expenseTemplates
        .where(
          (t) =>
              t.unitType == unitType && t.name.toLowerCase() == n.toLowerCase(),
        )
        .firstOrNull;
    if (existing != null) {
      existing
        ..name = n
        ..amount = amount;
    } else {
      expenseTemplates.add(
        ExpenseTemplate(name: n, amount: amount, unitType: unitType),
      );
    }
    notifyListeners();
  }

  void deleteExpenseTemplate(ExpenseTemplate t) {
    expenseTemplates.remove(t);
    notifyListeners();
  }

  List<MonthlyExpense> monthlyExpensesFor(String unit) =>
      monthlyExpenses[unit] ?? const [];

  /// What a unit's running monthly expenses add up to each month now.
  double monthlyTotal(String unit) {
    final now = DateTime(appState.today.year, appState.today.month);
    return monthlyExpensesFor(unit)
        .where(
          (e) =>
              !DateTime(e.since.year, e.since.month).isAfter(now) &&
              (e.until == null ||
                  !DateTime(e.until!.year, e.until!.month).isBefore(now)),
        )
        .fold(0.0, (n, e) => n + e.amount);
  }

  void addMonthlyExpense(String unit, MonthlyExpense e) {
    monthlyExpenses.putIfAbsent(unit, () => []).add(e);
    _log(
      'Monthly expense added',
      '$unit: ${e.name}, ${peso(e.amount, dhs: isVillaUnit(unit))} a month',
    );
    notifyListeners();
  }

  /// Stops an expense from this month on (past months stay counted).
  void stopMonthlyExpense(String unit, MonthlyExpense e) {
    final now = DateTime(appState.today.year, appState.today.month);
    final last = DateTime(now.year, now.month - 1);
    if (last.isBefore(DateTime(e.since.year, e.since.month))) {
      // Never charged yet: just remove it.
      monthlyExpenses[unit]?.remove(e);
    } else {
      e.until = last;
    }
    _log('Monthly expense stopped', '$unit: ${e.name}');
    notifyListeners();
  }

  /// Monthly expenses from [from] to [to], counting part months by their days
  /// (October = one month's worth, Oct 16-31 = about half). Villas in AED
  /// ([villas] true), the rest in pesos.
  double monthlyExpensesIn(DateTime from, DateTime to, {required bool villas}) {
    var total = 0.0;
    for (final entry in monthlyExpenses.entries) {
      if (isVillaUnit(entry.key) != villas) continue;
      for (final e in entry.value) {
        final first = DateTime(e.since.year, e.since.month);
        final lastMonth = e.until == null
            ? null
            : DateTime(e.until!.year, e.until!.month + 1, 0);
        var m = DateTime(from.year, from.month);
        while (!m.isAfter(to)) {
          final monthEnd = DateTime(m.year, m.month + 1, 0);
          final a = from.isAfter(m) ? from : m;
          final b = to.isBefore(monthEnd) ? to : monthEnd;
          if (!m.isBefore(first) &&
              (lastMonth == null || !m.isAfter(lastMonth))) {
            total += e.amount * (b.difference(a).inDays + 1) / monthEnd.day;
          }
          m = DateTime(m.year, m.month + 1);
        }
      }
    }
    return total;
  }

  void removeCost(String unit, CostEntry c) {
    unitCosts[unit]?.remove(c);
    notifyListeners();
  }

  /// A complaint filed by a tenant from their app.
  void fileComplaint(String tenant, String category, String body) {
    final unit = tenants.where((t) => t.name == tenant).firstOrNull?.unit ?? '';
    complaints.insert(
      0,
      ComplaintRec(
        tenant: tenant,
        unit: unit.isEmpty ? 'No unit' : unit,
        category: category,
        body: body,
        date: formatDate(appState.today),
      ),
    );
    notifyListeners();
  }

  /// A damage report the tenant submitted in their app: it joins the admin's
  /// list to review. (The tenant's own copy shares the same id.)
  void _reportFromTicket(Ticket t) {
    final tenant = appState.currentTenant;
    final unit = tenants.where((x) => x.name == tenant).firstOrNull?.unit ?? '';
    reports.insert(
      0,
      DamageReport(
        id: t.id,
        tenant: tenant,
        unit: unit.isEmpty ? 'No unit' : unit,
        issue: t.title,
        description: t.description,
        date: t.date,
        attachments: t.attachments,
        type: t.type,
      )..photoFiles.addAll(t.photos),
    );
    notifyListeners();
  }

  int _manualReportSeq = 1;

  /// A report the admin enters by hand (condo stays have no tenant app):
  /// for [guest] if it happened during a stay, otherwise for the unit.
  DamageReport addManualReport({
    required String unit,
    required String issue,
    required String description,
    required ReportType type,
    String guest = '',
    int photos = 0,
    List<Uint8List> files = const [],
  }) {
    final r = DamageReport(
      id: demoData ? 'MR-${_manualReportSeq++}' : 'MR-${uniqueCode()}',
      tenant: guest.isEmpty ? 'Management' : guest,
      unit: unit,
      issue: issue,
      description: description,
      date: formatDate(appState.today),
      attachments: files.isNotEmpty ? files.length : photos,
      type: type,
    );
    r.photoFiles.addAll(files);
    reports.insert(0, r);
    _log('Report added', '$unit: $issue');
    notifyListeners();
    return r;
  }

  /// A progress note management posts on a damage report.
  void postReportUpdate(DamageReport r, String text) {
    r.updates.insert(0, ReportUpdate(text, formatDate(appState.today)));
    notifyListeners();
  }

  /// The tenant added more photos to a report they already sent.
  void addReportPhotos(String id, int n, {List<Uint8List> photos = const []}) {
    final r = reports.where((x) => x.id == id).firstOrNull;
    if (r == null) return;
    r.attachments += n;
    r.photoFiles.addAll(photos);
    notifyListeners();
  }

  int get openComplaints =>
      complaints.where((c) => c.status != ComplaintStatus.resolved).length;

  void updateComplaint(
    ComplaintRec c,
    ComplaintStatus status,
    String response,
  ) {
    c.status = status;
    c.response = response.isEmpty ? null : response;
    notifyListeners();
  }

  final List<LeaseRequest> requests = demoData
      ? [
          LeaseRequest(
            tenant: 'Paolo Garcia',
            unit: 'Villa 2',
            kind: 'Renewal (1 year, same terms)',
            date: 'Oct 25',
            note: 'Would like to add a parking slot.',
          ),
          LeaseRequest(
            tenant: 'Juan Dela Cruz',
            unit: 'Unit 402',
            kind: 'Move-out notice',
            date: 'Oct 24',
            note: 'Moving abroad for work.',
          ),
        ]
      : [];

  // ---- calendar (everything across all properties)

  /// Scheduled work and stays that are not derived from other data.
  /// Stays and other dated items that are not repair or maintenance work.
  final List<AdminEvent> _scheduled = [];

  /// Repairs and maintenance the admin has scheduled.
  final List<WorkItem> workItems = demoData
      ? [
          WorkItem(
            date: DateTime(2026, 10, 28),
            time: '2:00 PM',
            title: 'Window glass replacement',
            where: 'Unit 101',
            kind: AdminEventKind.repair,
          ),
          WorkItem(
            date: DateTime(2026, 10, 29),
            time: '9:00 AM',
            title: 'Bathroom faucet repair',
            where: 'Unit 402',
            kind: AdminEventKind.repair,
          ),
          WorkItem(
            date: DateTime(2026, 10, 30),
            time: '1:00 PM - 5:00 PM',
            title: 'Water tank cleaning',
            where: 'Ayan Tower B',
            kind: AdminEventKind.maintenance,
          ),
          WorkItem(
            date: DateTime(2026, 10, 25),
            endDate: DateTime(2026, 10, 27),
            time: '10:00 AM',
            title: 'Deep cleaning',
            where: 'Condo 7A',
            kind: AdminEventKind.maintenance,
          ),
          WorkItem(
            date: DateTime(2026, 11, 2),
            time: '10:00 AM - 12:00 PM',
            title: 'Elevator 2 inspection',
            where: 'Ayan Tower B',
            kind: AdminEventKind.maintenance,
          ),
          WorkItem(
            date: DateTime(2026, 11, 3),
            time: '9:00 AM - 4:00 PM',
            title: 'Rooftop waterproofing',
            where: 'Ayan Tower B',
            kind: AdminEventKind.maintenance,
          ),
          WorkItem(
            date: DateTime(2026, 11, 4),
            time: '11:00 AM',
            title: 'Gate lock inspection',
            where: 'Villa 2',
            kind: AdminEventKind.repair,
          ),
          WorkItem(
            date: DateTime(2026, 10, 24),
            endDate: DateTime(2026, 10, 28),
            time: '9:00 AM - 5:00 PM',
            title: 'Bathroom tiles regrouting',
            where: 'Villa 2',
            kind: AdminEventKind.repair,
          ),
        ]
      : [];

  List<WorkItem> get upcomingWork =>
      (workItems.where((w) => !w.done).toList()
        ..sort((a, b) => a.date.compareTo(b.date)));

  /// The tenant living in [unit] (who can be charged for work there), if any.
  /// Condo guests have no account, so a condo never has one.
  TenantRec? tenantOfUnit(String unit) =>
      tenants.where((t) => t.unit == unit && t.unit.isNotEmpty).firstOrNull;

  void scheduleWork(WorkItem w) {
    workItems.add(w);
    _log(
      'Work scheduled',
      '${w.title} at ${w.where}, ${formatDate(w.date)}'
          '${w.cost > 0 ? ', cost ${w.cost.toStringAsFixed(0)}' : ''}'
          '${w.tenantPays ? ', tenant pays ${w.charge.toStringAsFixed(0)}' : ''}',
    );
    // The tenant pays: send them a payment request, due on the job's day.
    final t = w.tenantPays ? tenantOfUnit(w.where) : null;
    if (t != null && w.charge > 0) {
      final kind = switch (w.kind) {
        AdminEventKind.repair => 'Repair',
        AdminEventKind.inspection => 'Inspection',
        AdminEventKind.modification => 'Modification',
        _ => 'Maintenance',
      };
      addCharge(
        t.name,
        '$kind: ${w.title}',
        w.charge,
        formatDate(w.date),
        notify: false,
      );
      w
        ..chargedTenant = t.name
        ..chargeRec = charges.first;
      notifyTenant(
        t,
        'Payment request: ${w.title}',
        '$kind scheduled for ${formatDate(w.date)}. As it is the tenant\'s responsibility, '
            'please pay ${_sign(t.name)}${w.charge.toStringAsFixed(2)}. You can pay under Payments.',
      );
    }
    // Let the tenants it affects know: the tenant of the unit, or everyone
    // in the building for building-wide work. (A tenant who pays for it
    // was already sent the payment request above.)
    final affected = tenants.where((x) {
      if (x.unit.isEmpty || x == t) return false;
      return x.unit == w.where || _unit(x.unit)?.property == w.where;
    });
    final kindLabel = switch (w.kind) {
      AdminEventKind.repair => 'Repair',
      AdminEventKind.inspection => 'Inspection',
      AdminEventKind.modification => 'Modification',
      _ => 'Maintenance',
    };
    final when = w.days.length > 1
        ? '${formatDate(w.date)} - ${formatDate(w.endDate)}'
        : formatDate(w.date);
    for (final x in affected) {
      notifyTenant(
        x,
        '$kindLabel scheduled: ${w.title}',
        '${w.where == x.unit ? 'In your unit' : 'In your building'} on $when, ${w.time}.'
            '${w.notes.isEmpty ? '' : ' ${w.notes}'}',
      );
    }
    refreshConditions();
    // The demo tenant lives in Unit 402, Ayan Tower B: show it on their calendar.
    if (w.where == 'Unit 402' || w.where == 'Ayan Tower B') {
      for (final d in w.days) {
        appState.addEvent(
          CalendarEvent(
            date: d,
            time: w.time,
            title: w.title,
            subtitle: w.notes.isEmpty ? 'Scheduled by management' : w.notes,
            kind:
                w.kind == AdminEventKind.repair ||
                    w.kind == AdminEventKind.modification
                ? EventKind.repair
                : EventKind.maintenance,
          ),
        );
      }
    }
    notifyListeners();
  }

  void setWorkDone(WorkItem w, bool done) {
    w.done = done;
    refreshConditions();
    notifyListeners();
  }

  void removeWork(WorkItem w) {
    if (whyKeepWork(w) != null) return;
    workItems.remove(w);
    // An unpaid payment request for the job is withdrawn with it.
    final c = w.chargeRec;
    if (c != null && !c.paid && c.paidAmount == 0) charges.remove(c);
    _log('Work removed', '${w.title} at ${w.where}');
    refreshConditions();
    notifyListeners();
  }

  /// Work scheduled in this unit that is going on today (not marked done).
  /// Repairs come first, then maintenance; inspections don't change the
  /// condition. Work for the whole property (e.g. "Ayan Tower B") counts for
  /// every unit in it.
  WorkItem? activeWork(UnitRec u) {
    final today = DateTime(
      appState.today.year,
      appState.today.month,
      appState.today.day,
    );
    bool on(WorkItem w) =>
        !w.done &&
        (w.where == u.name || w.where == u.property) &&
        !DateTime(w.date.year, w.date.month, w.date.day).isAfter(today) &&
        !DateTime(
          w.endDate.year,
          w.endDate.month,
          w.endDate.day,
        ).isBefore(today);
    final jobs = workItems.where(on).toList();
    return jobs.where((w) => w.kind == AdminEventKind.repair).firstOrNull ??
        jobs.where((w) => w.kind == AdminEventKind.modification).firstOrNull ??
        jobs.where((w) => w.kind == AdminEventKind.maintenance).firstOrNull;
  }

  /// A unit's condition follows its schedule: Under repair or Under
  /// maintenance while that work is on, Ready for occupancy otherwise.
  UnitCondition conditionFor(UnitRec u) => switch (activeWork(u)?.kind) {
    AdminEventKind.repair => UnitCondition.underRepair,
    AdminEventKind.maintenance => UnitCondition.underMaintenance,
    AdminEventKind.modification => UnitCondition.underModification,
    _ => UnitCondition.good,
  };

  /// Sets every unit's condition from the schedule. Runs when the app opens
  /// and whenever work is scheduled, finished or removed (with a backend:
  /// also each day).
  void refreshConditions() {
    for (final u in units) {
      u.condition = conditionFor(u);
    }
  }

  String _typeOf(String unitOrProperty) {
    for (final u in units) {
      if (u.name == unitOrProperty || u.property == unitOrProperty) {
        return u.type;
      }
    }
    return 'Apartment';
  }

  /// Every event across all properties: scheduled work, rent due dates and
  /// lease end dates.
  List<AdminEvent> get calendarEvents {
    final out = <AdminEvent>[
      ..._scheduled,
      for (final w in workItems.where((w) => !w.done))
        // A multi-day job shows on every day it runs.
        for (final d in w.days)
          AdminEvent(
            date: d,
            time: w.time,
            title: w.title,
            unit: w.where,
            kind: w.kind,
            detail: w.notes.isEmpty ? null : w.notes,
          ),
      // Condo guests: arrival and departure.
      for (final b in bookings) ...[
        AdminEvent(
          date: DateTime(b.checkIn.year, b.checkIn.month, b.checkIn.day),
          time: clockTime(b.checkIn),
          title: 'Check-in · ${b.guest.isEmpty ? 'guest' : b.guest}',
          unit: b.unit,
          kind: AdminEventKind.stay,
          detail:
              '${b.guests} ${b.guests == 1 ? 'guest' : 'guests'} · ${b.nights} ${b.nights == 1 ? 'night' : 'nights'}',
        ),
        AdminEvent(
          date: DateTime(b.checkOut.year, b.checkOut.month, b.checkOut.day),
          time: clockTime(b.checkOut),
          title: 'Check-out · ${b.guest.isEmpty ? 'guest' : b.guest}',
          unit: b.unit,
          kind: AdminEventKind.stay,
        ),
      ],
    ];
    for (final c in charges.where((c) => !c.paid)) {
      final d = parseDate(c.due);
      if (d == null) continue;
      final t = tenants.where((t) => t.name == c.tenant).firstOrNull;
      out.add(
        AdminEvent(
          date: d,
          time: 'All day',
          title: '${c.title} due · ${c.tenant}',
          unit: t?.unit ?? '-',
          kind: AdminEventKind.rent,
          detail:
              '${_sign(c.tenant)}${c.amount.toStringAsFixed(0)}${c.overdue ? ' · overdue' : ''}',
        ),
      );
    }
    for (final t in tenants) {
      // Lease dates are whatever the admin set on the Contract & lease screen.
      final start = parseDate(t.leaseStart);
      if (start != null) {
        out.add(
          AdminEvent(
            date: start,
            time: 'All day',
            title: 'Move-in · ${t.name}',
            unit: t.unit,
            kind: AdminEventKind.lease,
          ),
        );
      }
      final end = parseDate(t.leaseEnd);
      if (end == null) continue;
      out.add(
        AdminEvent(
          date: end,
          time: 'All day',
          title: 'Lease ends · ${t.name}',
          unit: t.unit,
          kind: AdminEventKind.lease,
          detail: 'Move-out day unless renewed',
        ),
      );
    }
    return out;
  }

  /// Property type (Apartment, Condo, Villa) an event belongs to.
  String typeOfEvent(AdminEvent e) => _typeOf(e.unit);

  // ---- derived counts

  int get toVerify =>
      payments.where((p) => p.status == PayStatus.submitted).length;
  int get openReports =>
      reports.where((r) => r.status != ReportStatus.approved).length;
  int get pendingRequests =>
      requests.where((r) => r.status == RequestStatus.pending).length;
  int get overdueCount => charges.where((c) => c.overdue && !c.paid).length;
  int get missingLeases =>
      tenants.where((t) => !t.hasSignedLease && !t.hasContract).length;

  /// Assigns (or replaces) the contract PDF a tenant can open in their app.
  void assignContract(TenantRec t, String name, Uint8List bytes) {
    t
      ..contractName = name
      ..contractPdf = bytes
      ..contractAssignedAt = DateTime.now();
    notifyTenant(
      t,
      'Your contract is ready',
      'Management added your contract ($name). Open My Contract to view or download it.',
    );
  }

  /// Villa tenants pay no security deposit.
  bool hasDeposit(String tenantName) => !isVilla(tenantName);

  /// Villas are priced in dirhams; everything else in pesos.
  bool isVillaUnit(String unitName) => _unit(unitName)?.type == 'Villa';

  /// "AED " for a villa tenant, "₱" for everyone else.
  String _sign(String tenant) => isVilla(tenant) ? 'AED ' : '₱';

  bool isVilla(String tenantName) {
    final t = tenants.where((x) => x.name == tenantName).firstOrNull;
    return t != null && _unit(t.unit)?.type == 'Villa';
  }

  /// The documents this tenant has to provide: passport, visa, Emirates ID
  /// and Ejari for a villa, the Philippine ID and clearances for everyone else.
  List<String> requiredDocs(TenantRec t) =>
      _unit(t.unit)?.type == 'Villa' ? villaDocs : tenantDocs;

  /// The tenant uploads (or replaces) one of the required documents.
  void uploadDocument(
    String tenant,
    String doc,
    String fileName,
    Uint8List bytes,
  ) {
    final t = tenants.where((x) => x.name == tenant).firstOrNull;
    if (t == null) return;
    t.docs[doc] = true;
    t.docFiles[doc] = (name: fileName, bytes: bytes);
    // A new file needs checking again.
    t.docVerified.remove(doc);
    t.docRejected.remove(doc);
    notifyListeners();
  }

  /// Where a tenant's document stands, for both sides.
  DocState docState(TenantRec t, String doc) {
    if (t.docs[doc] == true) {
      return t.docVerified.contains(doc)
          ? DocState.verified
          : DocState.toReview;
    }
    return t.docRejected.containsKey(doc)
        ? DocState.rejected
        : DocState.missing;
  }

  /// Uploaded documents management has not checked yet, across all tenants.
  int get docsToReview => tenants.fold(
    0,
    (n, t) =>
        n +
        requiredDocs(t)
            .where((d) => docState(t, d) == DocState.toReview)
            .length,
  );

  /// Management checked the document and it is valid.
  void verifyDocument(TenantRec t, String doc) {
    _log('Document approved', '${t.name}: $doc');
    t.docVerified.add(doc);
    t.docRejected.remove(doc);
    notifyTenant(
      t,
      '$doc verified',
      'Management checked your $doc. Thank you.',
    );
    notifyListeners();
  }

  /// Management found the document not valid (blurred, expired, wrong file):
  /// it is cleared and the tenant is asked to upload a new one.
  void rejectDocument(TenantRec t, String doc, String reason) {
    _log('Document rejected', '${t.name}: $doc ($reason)');
    t.docs[doc] = false;
    t.docFiles.remove(doc);
    t.docVerified.remove(doc);
    t.docRejected[doc] = reason;
    notifyTenant(
      t,
      'Please upload your $doc again',
      'Open Account → My Documents to see why and upload a new one.',
    );
    notifyListeners();
  }

  /// Edits the lease terms the tenant sees under My Contract.
  void updateLease(
    TenantRec t, {
    required DateTime start,
    required DateTime end,
    required double rent,
    required int dueDay,
    required double deposit,
    int? chequesPerYear,
  }) {
    t
      ..leaseStart = formatDate(start)
      ..leaseEnd = formatDate(end)
      ..rent = rent
      ..dueDay = dueDay
      ..deposit = deposit;
    if (chequesPerYear != null) t.chequesPerYear = chequesPerYear;
    generateRentCharges();
    refreshLeaseStatuses();
    if (t.name == appState.currentTenant) _syncTenantLeaseEvents();
    _log(
      'Lease edited',
      '${t.name}: ${t.leaseStart} - ${t.leaseEnd}, ${_sign(t.name)}${rent.toStringAsFixed(0)}, due day $dueDay',
    );
    notifyListeners();
  }

  void removeContract(TenantRec t) {
    t
      ..contractName = null
      ..contractPdf = null
      ..contractOnServer = false
      ..contractAssignedAt = null;
    notifyListeners();
  }

  int get occupied =>
      units.where((u) => u.status == UnitStatus.occupied).length;
  int get unreadMessages => messages.where((m) => m.reply == null).length;

  /// Totals are kept per currency: villas are paid in dirhams ([dhs] true),
  /// everything else in pesos. Adding the two together would be meaningless.
  double collected({required bool dhs}) => payments
      .where((p) => p.status == PayStatus.verified && isVilla(p.tenant) == dhs)
      .fold(0.0, (a, p) => a + p.amount);
  double outstanding({required bool dhs}) => charges
      .where((c) => !c.paid && isVilla(c.tenant) == dhs)
      .fold(0.0, (a, c) => a + c.remaining);

  // ---- accounts (tenant logins)

  bool usernameTaken(String username, {TenantRec? except}) {
    final u = username.trim().toLowerCase();
    return u == adminUsername ||
        u == SupabaseConfig.adminUsername.toLowerCase() ||
        tenants.any((t) => t != except && t.username.toLowerCase() == u);
  }

  UnitRec? _unit(String name) =>
      units.where((u) => u.name == name).firstOrNull ??
      archivedUnits.where((u) => u.name == name).firstOrNull;

  /// Units the admin deleted: kept (archived) so their history still counts.
  final List<UnitRec> archivedUnits = [];

  /// Villa, Condo or Apartment for the unit a tenant lives in.
  String unitTypeOf(TenantRec t) => _unit(t.unit)?.type ?? '';

  /// An apartment's or villa's status follows its tenant's lease, like a
  /// condo's follows its bookings: Occupied once the lease has started
  /// (until the tenant moves out), Reserved when it starts later, Vacant
  /// with no tenant. Never set by hand.
  UnitStatus leaseStatus(UnitRec u) {
    final today = _day(appState.today);
    var reserved = false;
    for (final t in tenants.where((t) => t.unit == u.name)) {
      final start = parseDate(t.leaseStart);
      if (start == null || !start.isAfter(today)) return UnitStatus.occupied;
      reserved = true;
    }
    return reserved ? UnitStatus.reserved : UnitStatus.vacant;
  }

  static const _sampleReservations = {'Mark Villanueva', 'Liza Fernandez'};

  /// Sets every apartment's and villa's status (and its tenant) from the
  /// leases. Runs whenever a tenant or lease changes, and when data loads.
  void refreshLeaseStatuses() {
    for (final u in units.where((u) => u.type != 'Condo')) {
      final ts = tenants.where((t) => t.unit == u.name).toList();
      // The demo's two sample reservations have no tenant record; keep them.
      if (demoData && ts.isEmpty && _sampleReservations.contains(u.tenant)) {
        continue;
      }
      u.status = leaseStatus(u);
      u.tenant = ts.isEmpty ? null : ts.first.name;
    }
  }

  void createAccount(TenantRec t) {
    _log('Account created', '${t.name} (${t.unitLabel})');
    tenants.add(t);
    refreshLeaseStatuses();
    notifyListeners();
  }

  /// Applies edits. Moving to another unit frees the old one.
  void updateAccount(
    TenantRec t, {
    required String name,
    required String unit,
    required double deposit,
    required String username,
    required String password,
  }) {
    final u = _unit(unit);
    t
      ..name = name
      ..unit = unit
      ..deposit = deposit
      ..username = username
      ..password = password;
    // Rent and stay type follow the unit the tenant is assigned to.
    if (u != null) {
      t
        ..rent = u.rate
        ..stayType = stayTypeFor(u.type);
    } else {
      t
        ..rent = 0
        ..stayType = 'Not assigned';
    }
    refreshLeaseStatuses();
    notifyListeners();
  }

  /// Gives a tenant a new password (their login changes on the server).
  void setTenantPassword(TenantRec t, String password) {
    t.password = password;
    _log('Password reset', t.name);
    notifyListeners();
  }

  /// Accounts the admin deleted on purpose. Only these may have their
  /// records wiped from the server; a tenant missing from the list for any
  /// other reason is never deleted there.
  final Set<TenantRec> deletedAccounts = Set.identity();

  void deleteAccount(TenantRec t) {
    if (whyKeepAccount(t) != null) return;
    _log('Account deleted', '${t.name} (${t.unitLabel})');
    deletedAccounts.add(t);
    tenants.remove(t);
    refreshLeaseStatuses();
    notifyListeners();
  }

  /// The signed lease photo, provided by the admin.
  void setSignedLease(TenantRec t, Uint8List? bytes) {
    t.signedLease = bytes;
    notifyListeners();
  }

  String generateUsername(String name, String unit) {
    final first = name
        .trim()
        .split(' ')
        .first
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z]'), '');
    final digits = unit.replaceAll(RegExp(r'[^0-9]'), '');
    return '${first.isEmpty ? 'tenant' : first}$digits';
  }

  String generatePassword() =>
      'ayan${1000 + DateTime.now().microsecondsSinceEpoch % 9000}';

  // ---- payments

  /// A payment made in the app through the gateway. The gateway confirms it,
  /// so it is recorded as verified straight away (no admin check needed).
  void recordOnlinePayment(
    String tenant,
    String title,
    double amount,
    String method,
    String reference,
    String date,
  ) {
    final t = tenants.where((x) => x.name == tenant).firstOrNull;
    final p = PaymentRec(
      id: 'P-${payments.length + 30}',
      tenant: tenant,
      unit: t?.unit ?? '',
      title: title,
      amount: amount,
      method: method,
      reference: reference,
      date: date,
    );
    payments.insert(0, p);
    verifyPayment(p);
  }

  /// The admin records a payment that did not come through the app (cash, or
  /// a GCash/bank transfer whose proof arrived another way). It is verified at
  /// once. [charge] is the charge it pays; null for an advance or other
  /// payment that is not tied to a charge. The tenant is told it was received.
  void recordPayment(
    TenantRec t, {
    ChargeRec? charge,
    String title = 'Payment',
    required double amount,
    required String method,
    required String reference,
    required String date,
  }) {
    final p = PaymentRec(
      id: 'P-${payments.length + 30}',
      tenant: t.name,
      unit: t.unit,
      title: charge?.title ?? title,
      amount: amount,
      method: method,
      reference: reference.isEmpty ? '-' : reference,
      date: date,
      recordedByAdmin: true,
    );
    payments.insert(0, p);
    // A payment that falls short is a part-payment: the charge stays open
    // with the rest still owed.
    final clears = charge != null && amount >= charge.remaining - .009;
    if (charge != null && !clears) charge.paidAmount += amount;
    verifyPayment(p, covers: clears ? charge : null);
    _log(
      'Payment recorded',
      '${t.name}: ${_sign(t.name)}${amount.toStringAsFixed(2)} by $method'
          '${charge == null
              ? ''
              : clears
              ? ' (clears ${charge.title})'
              : ' (part of ${charge.title}, ${_sign(t.name)}${charge.remaining.toStringAsFixed(2)} left)'}',
    );
    // Keep the tenant app in step (demo: it shares this phone's memory).
    if (t.name == appState.currentTenant) {
      appState.recordManualPayment(
        title: '${charge?.title ?? title} payment',
        method: method,
        amount: amount,
        reference: p.reference,
        date: date,
        clearsRent: clears && charge.title.toLowerCase().contains('rent'),
      );
    }
    notifyTenant(
      t,
      'Payment received',
      '${charge?.title ?? title}: ${_sign(t.name)}${amount.toStringAsFixed(2)} received by $method on $date. '
          'Thank you!',
    );
  }

  /// Marks a payment verified. It clears [covers], or the tenant's oldest
  /// unpaid charge when none is given.
  void verifyPayment(PaymentRec p, {ChargeRec? covers}) {
    p.status = PayStatus.verified;
    if (covers != null) {
      covers
        ..paid = true
        ..overdue = false;
    } else if (!p.recordedByAdmin) {
      // The charges the tenant chose are paid in full first.
      var left = p.amount;
      for (final c in p.covers.where((c) => !c.paid)) {
        left -= c.remaining;
        c
          ..paidAmount = c.amount
          ..paid = true
          ..overdue = false;
      }
      // The rest pays the tenant's open charges, oldest due first (only rent
      // when they chose charges). What doesn't cover a whole charge is kept
      // as a part-payment on it.
      final open =
          charges
              .where(
                (c) =>
                    c.tenant == p.tenant &&
                    !c.paid &&
                    (p.covers.isEmpty || isRentCharge(c)),
              )
              .toList()
            ..sort(
              (a, b) => (parseDate(a.due) ?? DateTime(0)).compareTo(
                parseDate(b.due) ?? DateTime(0),
              ),
            );
      for (final c in open) {
        if (left <= .009) break;
        final take = left < c.remaining ? left : c.remaining;
        c.paidAmount += take;
        left -= take;
        if (c.amount - c.paidAmount <= .009) {
          c
            ..paid = true
            ..overdue = false;
        }
      }
    }
    if (p.status == PayStatus.verified && !p.recordedByAdmin) {
      _log(
        'Payment verified',
        '${p.tenant}: ${_sign(p.tenant)}${p.amount.toStringAsFixed(2)} (${p.title})',
      );
    }
    for (final t in tenants) {
      if (t.name == p.tenant) {
        t.balance = (t.balance - p.amount).clamp(0, double.infinity);
        // A verified rent payment extends the paid stay by the months paid.
        final until = t.paidUntil;
        if (until != null &&
            p.months > 0 &&
            p.title.toLowerCase().contains('rent')) {
          t.paidUntil = p.coversTo ?? addMonthsToPaidUntil(until, p.months);
        }
      }
    }
    notifyListeners();
  }

  /// A proof of payment a tenant submitted in their app, with the months they
  /// say they are paying for. It waits in the admin's "To verify" list.
  void _paymentFromProof(
    String tenant,
    String method,
    String reference,
    int months,
    DateTime? from,
    DateTime? to,
    double amount,
    String date,
    Uint8List? proof,
    List<Object> chosen,
  ) {
    final covers = chosen.whereType<ChargeRec>().toList();
    final rent = months == 0
        ? ''
        : (months == 1 ? 'Rent · 1 month' : 'Rent · $months months');
    final title = covers.isEmpty
        ? rent
        : rent.isEmpty
        ? (covers.length == 1
              ? covers.first.title
              : '${covers.length} charges: ${covers.map((c) => c.title).join(', ')}')
        : '$rent + ${covers.length == 1 ? covers.first.title : '${covers.length} charges'}';
    final t = tenants.where((x) => x.name == tenant).firstOrNull;
    payments.insert(
      0,
      PaymentRec(
          id: 'P-${payments.length + 30}',
          tenant: tenant,
          unit: t?.unit ?? '',
          title: title,
          amount: amount,
          method: method,
          reference: reference,
          date: date,
          months: months,
          coversFrom: from,
          coversTo: to,
        )
        ..proof = proof
        ..covers.addAll(covers),
    );
    notifyListeners();
  }

  void rejectPayment(PaymentRec p, String reason) {
    p.status = PayStatus.rejected;
    p.reason = reason;
    _log('Payment rejected', '${p.tenant}: ${p.title} ($reason)');
    notifyListeners();
  }

  /// What a manually added charge can be for. The admin can add more.
  final List<String> chargeTypes = [
    'Maintenance',
    'Repairs',
    'Utilities',
    'Misc',
  ];

  /// Taxes the admin keeps up to date (rates change often). Each takes a
  /// percentage of the period's income: peso income, or villa income (AED).
  final List<TaxRate> taxes = demoData
      ? [
          TaxRate(name: 'Percentage tax', percent: 3),
          TaxRate(name: 'Withholding tax on rent', percent: 5),
        ]
      : [];

  void saveTax(TaxRate? existing, TaxRate data) {
    if (existing == null) {
      taxes.add(data);
    } else {
      existing
        ..name = data.name
        ..percent = data.percent
        ..onVillas = data.onVillas
        ..fixedMonthly = data.fixedMonthly;
    }
    _log(
      'Tax saved',
      data.isFixed
          ? '${data.name}: ${data.onVillas ? 'AED ' : '₱'}${data.fixedMonthly.toStringAsFixed(2)} a month'
          : '${data.name}: ${data.percent}% of ${data.onVillas ? 'villa' : 'peso'} revenue',
    );
    notifyListeners();
  }

  void removeTax(TaxRate t) {
    taxes.remove(t);
    notifyListeners();
  }

  /// Kinds of operational cost for a condo; the admin can add more.
  final List<String> costTypes = [
    'Electricity',
    'Water',
    'Cleaning',
    'Toiletries and linens',
    'Internet',
    'Repairs',
  ];

  /// Adds a cost type and returns it (the existing spelling if already there).
  String addCostType(String name) {
    final n = name.trim();
    final existing = costTypes
        .where((t) => t.toLowerCase() == n.toLowerCase())
        .firstOrNull;
    if (existing != null) return existing;
    costTypes.add(n);
    notifyListeners();
    return n;
  }

  /// Adds a charge type and returns it (the existing spelling if it was
  /// already there, ignoring capitals).
  String addChargeType(String name) {
    final n = name.trim();
    final existing = chargeTypes
        .where((t) => t.toLowerCase() == n.toLowerCase())
        .firstOrNull;
    if (existing != null) return existing;
    chargeTypes.add(n);
    notifyListeners();
    return n;
  }

  /// True for a monthly rent charge ("October 2026 rent"), which the tenant
  /// pays by choosing months, not as a charge.
  bool isRentCharge(ChargeRec c) =>
      RegExp(r'^\w+ \d{4} rent$').hasMatch(c.title);

  /// How far a tenant's rent is paid, worked out from what is actually paid
  /// (so it is always right, and moves as soon as a payment is verified):
  /// - apartments: the end of the latest rent month that is fully paid
  ///   (months follow the lease: one starting Nov 15 runs to Dec 14);
  /// - villas: the lease start plus the months of the cleared post-dated
  ///   cheques.
  /// Null when no rent is paid yet.
  /// A paid-until date already kept on the lease (set by a verified payment
  /// that covered months) counts too: the later of the two wins.
  DateTime? rentPaidUntil(TenantRec t) {
    final worked = _paidFromRecords(t), kept = t.paidUntil;
    if (worked == null) return kept;
    if (kept == null) return worked;
    return kept.isAfter(worked) ? kept : worked;
  }

  DateTime? _paidFromRecords(TenantRec t) {
    final start = parseDate(t.leaseStart);
    if (_unit(t.unit)?.type == 'Villa') {
      final months = cheques
          .where(
            (c) =>
                c.tenant == t.name &&
                c.kind == ChequeKind.postDated &&
                c.status == ChequeStatus.cleared,
          )
          .fold<int>(0, (a, c) => a + c.months);
      if (start == null || months <= 0) return null;
      return addMonthsToPaidUntil(
        start.subtract(const Duration(days: 1)),
        months,
      );
    }
    DateTime? last;
    for (final c in charges) {
      if (c.tenant != t.name || !c.paid || !isRentCharge(c)) continue;
      // "November 2026 rent"
      final parts = c.title.split(' ');
      final month = _monthNames.indexOf(parts[0]) + 1;
      final year = int.tryParse(parts[1]);
      if (month < 1 || year == null) continue;
      final end = start == null
          ? DateTime(year, month + 1, 0)
          : addMonthsToPaidUntil(
              start.subtract(const Duration(days: 1)),
              (year - start.year) * 12 + month - start.month + 1,
            );
      if (last == null || end.isAfter(last)) last = end;
    }
    return last;
  }

  void addCharge(
    String tenant,
    String title,
    double amount,
    String due, {
    bool notify = true,
  }) {
    charges.insert(
      0,
      ChargeRec(tenant: tenant, title: title, amount: amount, due: due),
    );
    _log(
      'Charge added',
      '$tenant: $title, ${_sign(tenant)}${amount.toStringAsFixed(2)} due $due',
    );
    for (final t in tenants) {
      if (t.name == tenant) {
        t.balance += amount;
        // They hear about it straight away (a phone notification too).
        if (notify) {
          notifyTenant(
            t,
            'New charge: $title',
            '${_sign(tenant)}${amount.toStringAsFixed(2)}, due $due. You can pay it under Pay Rent.',
          );
        }
      }
    }
    notifyListeners();
  }

  // ---- reports

  void saveReport(
    DamageReport r,
    ReportStatus s,
    DamageKind? k,
    double deduction,
    String note,
  ) {
    r.status = s;
    r.kind = k;
    r.deduction = deduction;
    r.note = note;
    _log(
      'Report ${s.name}',
      '${r.unit}: ${r.issue}${deduction > 0 ? ', deduction ${deduction.toStringAsFixed(0)}' : ''}',
    );
    notifyListeners();
  }

  // ---- notices & messages

  /// Announcements go to apartment and villa tenants only. Condo is day-to-day
  /// rental that the owner tracks here, so those guests are not on the app.
  List<TenantRec> get noticeAudience => tenants
      .where((t) => _unit(t.unit) != null && _unit(t.unit)!.type != 'Condo')
      .toList();

  /// Tenants living in a unit of one of [types] ("Apartment", "Villa", "Condo").
  List<TenantRec> tenantsOfTypes(Set<String> types) =>
      tenants.where((t) => types.contains(_unit(t.unit)?.type)).toList();

  /// Publishes an announcement to the tenants in [types] of unit (by default
  /// apartments and villas, as before).
  void publishNotice(
    String title,
    String body,
    NoticeKind kind, {
    Set<String> types = const {'Apartment', 'Villa'},
  }) {
    final id = 'n${DateTime.now().millisecondsSinceEpoch}-${_noticeSeq++}';
    final to = [for (final t in tenantsOfTypes(types)) t.name];
    notices.insert(
      0,
      AdminNotice(
        id: id,
        title: title,
        body: body,
        kind: kind,
        date: 'Today',
        recipients: to,
        unitTypes: types.toList(),
      ),
    );
    appState.addNotice(
      Notice(
        id: id,
        kind: kind,
        title: title,
        body: body,
        date: 'Today',
        audience: to,
      ),
    );
    _log('Announcement sent', '$title (to ${to.length})');
    notifyListeners();
  }

  /// A notice for one tenant only (their unit). It pops up on their phone and
  /// shows in their Notices like any announcement.
  int _noticeSeq = 0;

  void notifyTenant(
    TenantRec t,
    String title,
    String body, {
    bool automatic = true,
  }) {
    final id = 'n${DateTime.now().millisecondsSinceEpoch}-${_noticeSeq++}';
    notices.insert(
      0,
      AdminNotice(
        id: id,
        title: title,
        body: body,
        kind: NoticeKind.general,
        date: 'Today',
        recipients: [t.name],
        to: t.name,
        automatic: automatic,
      ),
    );
    appState.addNotice(
      Notice(
        id: id,
        kind: NoticeKind.general,
        title: title,
        body: body,
        date: 'Today',
        to: t.name,
      ),
    );
    notifyListeners();
  }

  /// Unpaid charges for a tenant, latest due date first.
  List<ChargeRec> unpaidFor(String tenant) {
    final list = charges.where((c) => c.tenant == tenant && !c.paid).toList();
    list.sort(
      (a, b) => (parseDate(b.due) ?? DateTime(0)).compareTo(
        parseDate(a.due) ?? DateTime(0),
      ),
    );
    return list;
  }

  void markNoticeRead(String id, String tenant) {
    for (final n in notices) {
      if (n.id == id && n.recipients.contains(tenant)) {
        n.readBy.add(tenant);
        notifyListeners();
      }
    }
  }

  void reply(AdminMessage m, String text) {
    m.reply = text;
    notifyListeners();
  }

  // ---- lease requests, deposit, units

  void decide(LeaseRequest r, bool approve) {
    r.status = approve ? RequestStatus.approved : RequestStatus.declined;
    final t = tenants.where((x) => x.name == r.tenant).firstOrNull;
    if (t != null && !approve) {
      notifyTenant(
        t,
        'About your request',
        'Management could not approve your request (${r.kind}). Please message management to talk it over.',
      );
    }
    notifyListeners();
  }

  // ---- lease renewal

  /// Leases ending within [days] days (and not already over), soonest first.
  List<TenantRec> leasesEndingWithin(int days) =>
      tenants
          // Short condo stays are not leases to renew.
          // Already renewed (a renewal is waiting to start): nothing to decide.
          .where(
            (t) =>
                t.unit.isNotEmpty &&
                _unit(t.unit)?.type != 'Condo' &&
                t.nextLease == null &&
                t.daysLeft >= 0 &&
                t.daysLeft <= days,
          )
          .toList()
        ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));

  /// A pending renewal request from this tenant, if any.
  LeaseRequest? renewalRequestOf(TenantRec t) => requests
      .where(
        (r) =>
            r.tenant == t.name &&
            r.status == RequestStatus.pending &&
            r.kind.toLowerCase().contains('renewal'),
      )
      .firstOrNull;

  /// How many days before a lease ends the tenant is asked about renewal
  /// (and admin sees it under Needs your attention).
  int renewalNoticeDays = 90;

  /// Tells tenants, once, that their lease ends within [renewalNoticeDays] and asks them
  /// to say whether they will renew. Run when the app opens.
  void sendLeaseEndReminders() {
    for (final t in leasesEndingWithin(renewalNoticeDays)) {
      if (t.endReminded) continue;
      t.endReminded = true;
      notifyTenant(
        t,
        'Your lease ends ${t.leaseEnd}',
        'Your lease ends in ${t.daysLeft} days. Open My Contract to request a renewal or tell us you are moving out.',
      );
    }
  }

  /// Renews a lease: the current terms move to [TenantRec.pastLeases], the
  /// new dates, rent and (for villas) cheques per year take effect, and the
  /// new contract replaces the old one. For a villa, [planNewCheques] sets up
  /// the first year's cheques. Any pending renewal request is approved and
  /// the tenant is told.
  ///
  /// A renewal that starts after today while the current lease is still
  /// running is kept as [TenantRec.nextLease] and takes over on its start
  /// date, so the current rent, charges and contract stay as they are until
  /// then.
  void renewLease(
    TenantRec t, {
    required DateTime start,
    required DateTime end,
    required double rent,
    int? chequesPerYear,
    String? contractName,
    Uint8List? contractPdf,
    bool planNewCheques = false,
  }) {
    final term = LeaseTerm(
      start: formatDate(start),
      end: formatDate(end),
      rent: rent,
      chequesPerYear: chequesPerYear ?? t.chequesPerYear,
      contractName: contractName,
      contractPdf: contractPdf,
    );
    final today = _day(appState.today);
    final currentEnd = parseDate(t.leaseEnd);
    final later =
        start.isAfter(today) &&
        currentEnd != null &&
        !currentEnd.isBefore(today);
    renewalRequestOf(t)?.status = RequestStatus.approved;
    final money = peso(rent, dhs: isVilla(t.name));
    if (later) {
      t
        ..nextLease = term
        ..endReminded = true; // no more "lease ending" reminders
      notifyTenant(
        t,
        'Lease renewal confirmed',
        'Your new lease runs ${term.start} to ${term.end} at $money a month. '
            'It starts after your current lease ends on ${t.leaseEnd}.',
      );
      _log(
        'Renewal scheduled',
        '${t.name}: ${term.start} - ${term.end}, $money',
      );
    } else {
      _applyLease(t, term);
      notifyTenant(
        t,
        'Lease renewed',
        'Your lease is renewed from ${t.leaseStart} to ${t.leaseEnd}. Rent: $money a month.'
            '${contractPdf == null ? '' : ' The new contract is under My Contract.'}',
      );
      _log('Lease renewed', '${t.name}: ${term.start} - ${term.end}, $money');
    }
    if (planNewCheques && isVilla(t.name)) {
      planCheques(t, term.chequesPerYear, yearStart: start, rent: rent);
    }
    notifyListeners();
  }

  /// Puts [term] in place as the tenant's current lease; the old one moves
  /// to [TenantRec.pastLeases].
  void _applyLease(TenantRec t, LeaseTerm term) {
    t.pastLeases.insert(
      0,
      LeaseTerm(
        start: t.leaseStart,
        end: t.leaseEnd,
        rent: t.rent,
        chequesPerYear: t.chequesPerYear,
        contractName: t.contractName,
        contractPdf: t.contractPdf,
      ),
    );
    t
      ..leaseStart = term.start
      ..leaseEnd = term.end
      ..rent = term.rent
      ..chequesPerYear = term.chequesPerYear
      ..endReminded = false
      ..nextLease = null
      // The old contract belongs to the old lease.
      ..contractName = term.contractName
      ..contractPdf = term.contractPdf
      ..contractOnServer = false
      ..contractAssignedAt = term.contractPdf == null ? null : DateTime.now();
    generateRentCharges();
    refreshLeaseStatuses();
    if (t.name == appState.currentTenant) _syncTenantLeaseEvents();
  }

  /// Starts any scheduled renewal whose start date has come. Runs when the
  /// app opens (with a backend: once a day).
  /// [on] is the day to check (today when left out).
  void applyDueRenewals({DateTime? on}) {
    final today = _day(on ?? appState.today);
    for (final t in tenants) {
      final next = t.nextLease;
      final start = next == null ? null : parseDate(next.start);
      if (next == null || start == null || start.isAfter(today)) continue;
      _applyLease(t, next);
      _log('Renewal started', '${t.name}: ${next.start} - ${next.end}');
    }
  }

  /// Drops a renewal that has not started yet.
  void cancelScheduledRenewal(TenantRec t) {
    if (t.nextLease == null) return;
    _log(
      'Renewal cancelled',
      '${t.name}: ${t.nextLease!.start} - ${t.nextLease!.end}',
    );
    t
      ..nextLease = null
      ..endReminded = false;
    notifyTenant(
      t,
      'Lease renewal cancelled',
      'The renewal that was to start after ${t.leaseEnd} has been cancelled. Please message management if you have questions.',
    );
    notifyListeners();
  }

  // ---- move-out

  /// Tenants who have moved out, newest first.
  final List<FormerTenant> formerTenants = [];

  /// Ends a tenancy: the deposit is settled (less [deduction] for damage
  /// found at the move-out inspection), cheques not yet banked and the
  /// deposit cheque go back to a villa tenant, rent charges after
  /// [date] are dropped, the unit is freed and the account is closed. The
  /// tenant is kept under [formerTenants] with what was still owed.
  void moveOut(
    TenantRec t, {
    required DateTime date,
    required double deduction,
    required String reason,
    required String inspection,
  }) {
    final villa = isVilla(t.name);
    final unitType = unitTypeOf(t);
    notifyTenant(
      t,
      'Move-out confirmed',
      'Your move-out on ${formatDate(date)} is recorded. Thank you for staying with Ayan Residences.',
    );
    // Deposit.
    String depositNote;
    if (villa) {
      final returned = <String>[];
      for (final c in cheques.where(
        (c) =>
            c.tenant == t.name &&
            c.status == ChequeStatus.held &&
            c.returnedOn == null,
      )) {
        if (c.kind == ChequeKind.deposit || !c.date.isBefore(date)) {
          c.returnedOn = formatDate(appState.today);
          returned.add(
            c.kind == ChequeKind.deposit
                ? 'deposit cheque'
                : 'cheque dated ${formatDate(c.date)}',
          );
        }
      }
      depositNote = returned.isEmpty
          ? 'No cheques to return'
          : 'Returned: ${returned.join(', ')}';
      if (deduction > 0) {
        depositNote +=
            '. Damage charged: ${peso(deduction, dhs: true)} ($reason)';
      }
    } else {
      final refund = (t.deposit - deduction)
          .clamp(0, double.infinity)
          .toDouble();
      depositNote = deduction > 0
          ? 'Refunded ${peso(refund)} after ${peso(deduction)} deduction ($reason)'
          : 'Refunded in full (${peso(t.deposit)})';
    }
    // Charges for months after the move-out are not owed.
    charges.removeWhere((c) {
      final d = parseDate(c.due);
      return c.tenant == t.name && !c.paid && d != null && d.isAfter(date);
    });
    // Still owed: unpaid charges, plus damage the deposit doesn't cover
    // (all of it for a villa, which has a cheque instead of cash).
    final uncovered = villa
        ? deduction
        : (deduction - t.deposit).clamp(0, double.infinity).toDouble();
    final owed =
        charges
            .where((c) => c.tenant == t.name && !c.paid)
            .fold(0.0, (n, c) => n + c.remaining) +
        uncovered;
    for (final r in requests.where(
      (r) =>
          r.tenant == t.name &&
          r.status == RequestStatus.pending &&
          r.kind.toLowerCase().contains('move'),
    )) {
      r.status = RequestStatus.approved;
    }
    formerTenants.insert(
      0,
      FormerTenant(
        name: t.name,
        unit: t.unit,
        unitType: unitType,
        phone: t.phone,
        email: t.email,
        leaseStart: t.leaseStart,
        leaseEnd: t.leaseEnd,
        movedOut: date,
        depositNote: depositNote,
        inspection: inspection,
        owedAtMoveOut: owed,
        pastLeases: [...t.pastLeases],
      ),
    );
    _log(
      'Moved out',
      '${t.name} left ${t.unit} on ${formatDate(date)}. $depositNote',
    );
    tenants.remove(t);
    refreshLeaseStatuses();
    notifyListeners();
  }

  // ---- activity log

  /// Everything the admin changed, newest first (kept while the app is open;
  /// with a backend, stored with who did it).
  final List<LogEntry> activityLog = [];

  void _log(String action, String detail) {
    final now = DateTime.now();
    final t = appState.today;
    activityLog.insert(
      0,
      LogEntry(
        DateTime(t.year, t.month, t.day, now.hour, now.minute),
        action,
        detail,
      ),
    );
  }

  // ---- settings

  /// Which items the admin wants flagged (dashboard list and dots).
  final Map<String, bool> alertPrefs = {
    'Payment proofs to verify': true,
    'Cheques to bank or confirm': true,
    'Damage and maintenance reports': true,
    'Tenant documents to check': true,
    'Lease requests and endings': true,
    'Overdue rent': true,
    'Complaints': true,
    'Messages from tenants': true,
  };

  bool wants(String alert) => alertPrefs[alert] ?? true;

  void setAlert(String alert, bool on) {
    alertPrefs[alert] = on;
    notifyListeners();
  }

  /// The payment gateway's fee, in percent of online payments.
  double gatewayFeePercent = 2.5;

  /// Charged to a villa tenant when a cheque bounces (AED); 0 for none.
  double bouncedChequeFee = 500;

  void setFees({double? gateway, double? bounced}) {
    if (gateway != null) gatewayFeePercent = gateway;
    if (bounced != null) bouncedChequeFee = bounced;
    _log(
      'Fees changed',
      'Gateway ${gatewayFeePercent.toStringAsFixed(1)}%, bounced cheque AED ${bouncedChequeFee.toStringAsFixed(0)}',
    );
    notifyListeners();
  }

  /// Repair and maintenance costs entered on scheduled work from [from] to
  /// [to] (by the job's first day): villas in AED ([villas] true), the rest
  /// in pesos. A job for a whole property counts with that property's type.
  double workCostIn(DateTime from, DateTime to, {required bool villas}) =>
      workItems
          .where(
            (w) =>
                w.cost > 0 &&
                !_day(w.date).isBefore(_day(from)) &&
                !_day(w.date).isAfter(_day(to)) &&
                (_typeOf(w.where) == 'Villa') == villas,
          )
          .fold(0.0, (n, w) => n + w.cost);

  /// Hands back what is left of a condo guest's deposit.
  void returnDeposit(Booking b) {
    _depositReturned[b.id] = appState.today;
    _log('Deposit returned', '${b.guest} (${b.unit}): ${peso(b.depositLeft)}');
    notifyListeners();
  }

  void settleDeposit(TenantRec t, double deduction, String reason) {
    final refund = t.deposit - deduction;
    t.depositNote = deduction > 0
        ? 'Refunded ${_sign(t.name)}${refund.toStringAsFixed(0)} after ${_sign(t.name)}${deduction.toStringAsFixed(0)} deduction ($reason)'
        : 'Refunded in full (${_sign(t.name)}${t.deposit.toStringAsFixed(0)})';
    t.deposit = 0;
    notifyListeners();
  }

  void addUnit(
    String property,
    String type,
    String name,
    double rate,
    String rateUnit, {
    Uint8List? photo,
    int bedrooms = 1,
  }) {
    final u = UnitRec(
      property: property,
      type: type,
      name: name,
      rate: rate,
      rateUnit: ratePeriodFor(type),
      photo: photo,
      bedrooms: bedrooms,
    );
    units.add(u);
    notifyListeners();
  }

  // ------------------------------------------------- keeping the records
  //
  // Money and history must stay for Finance and the PDF reports, so a
  // delete that would erase them is refused, with the reason to show.

  /// Why this unit can't be deleted yet, or null when it can.
  String? whyKeepUnit(UnitRec u) {
    if (tenants.any((t) => t.unit == u.name)) {
      return 'A tenant is assigned to ${u.name}. Move them out first.';
    }
    final now = appState.today;
    if (bookings.any((b) => b.unit == u.name && b.checkOut.isAfter(now))) {
      return '${u.name} has a current or upcoming stay. Finish or remove it first.';
    }
    return null;
  }

  /// Deletes a unit from the lists. It is archived, never erased: its
  /// payments, stays, reports and costs stay on record.
  void deleteUnit(UnitRec u) {
    if (whyKeepUnit(u) != null) return;
    _log('Unit deleted', '${u.name} (${u.type}, ${u.property})');
    units.remove(u);
    u.archivedAt = DateTime.now();
    archivedUnits.add(u);
    notifyListeners();
  }

  /// Why this account can't be deleted, or null when it can. One with
  /// payment records is moved out instead, so the records stay.
  String? whyKeepAccount(TenantRec t) {
    final hasMoney =
        payments.any(
          (p) => p.tenant == t.name && p.status == PayStatus.verified,
        ) ||
        charges.any(
          (c) => c.tenant == t.name && (c.paid || c.paidAmount > 0),
        ) ||
        cheques.any((c) => c.tenant == t.name && c.status != ChequeStatus.held);
    return hasMoney
        ? '${t.name} has payment records. Use Move out instead, so the records stay for your reports.'
        : null;
  }

  /// Why this stay can't be removed: once it has started it counts in
  /// revenue.
  String? whyKeepBooking(Booking b) => b.checkIn.isAfter(appState.today)
      ? null
      : 'This stay has started, so it counts in your revenue. Edit it instead of removing it.';

  /// Why this job can't be removed: once done (or paid for) it counts in
  /// your costs.
  String? whyKeepWork(WorkItem w) {
    final c = w.chargeRec;
    if (w.done || (c != null && (c.paid || c.paidAmount > 0))) {
      return 'This work is done or paid, so it counts in your costs and can\'t be removed.';
    }
    return null;
  }

  /// Why this cheque can't be removed: once banked it is part of the records.
  String? whyKeepCheque(ChequeRec c) => c.status == ChequeStatus.held
      ? null
      : 'This cheque is already banked, so it stays in your records.';

  /// True when another unit already has this name (any capitals).
  bool unitNameTaken(String name, {UnitRec? except}) {
    final n = name.trim().toLowerCase();
    return [
      ...units,
      ...archivedUnits,
    ].any((u) => u != except && u.name.toLowerCase() == n);
  }

  /// Redraws the screens (e.g. after files finished downloading).
  void refreshViews() => notifyListeners();

  /// When what was left of a condo deposit was handed back (from the
  /// database).
  void setDepositReturned(Booking b, DateTime on) =>
      _depositReturned[b.id] = on;

  /// Where a tenant's rent stands, for their app: a proof is waiting to be
  /// checked, something is due, or nothing is owed. Worked out from their
  /// payments and charges (the demo keeps its own flags).
  RentState rentStateOf(String tenant) {
    if (demoData) {
      return appState.currentRentPaid
          ? RentState.paid
          : appState.currentRentSubmitted
          ? RentState.awaiting
          : RentState.due;
    }
    if (payments.any(
      (p) => p.tenant == tenant && p.status == PayStatus.submitted,
    )) {
      return RentState.awaiting;
    }
    return unpaidFor(tenant).isEmpty ? RentState.paid : RentState.due;
  }

  /// The tenant's latest request (renewal, move-out...) still waiting for
  /// management's answer.
  LeaseRequest? pendingRequestOf(String tenant) => requests
      .where((r) => r.tenant == tenant && r.status == RequestStatus.pending)
      .firstOrNull;

  /// The tenant's calendar from what is on record: repairs and maintenance
  /// at their unit or building, rent due dates and cheque dates. (Lease
  /// start and end are added by the tenant app itself.)
  List<CalendarEvent> tenantEvents(String tenant) {
    final t = tenants.where((x) => x.name == tenant).firstOrNull;
    if (t == null) return const [];
    final u = _unit(t.unit);
    final villa = u?.type == 'Villa';
    return [
      for (final w in workItems)
        if (!w.done &&
            (w.where == t.unit || (u != null && w.where == u.property)))
          for (final d in w.days)
            CalendarEvent(
              date: d,
              time: w.time,
              title: w.title,
              subtitle: w.where == t.unit
                  ? 'In your unit'
                  : 'Building: ${w.where}',
              kind: w.kind == AdminEventKind.repair
                  ? EventKind.repair
                  : EventKind.maintenance,
            ),
      for (final c in charges)
        if (c.tenant == tenant && !c.paid && parseDate(c.due) != null)
          CalendarEvent(
            date: parseDate(c.due)!,
            time: 'Due',
            title: c.title,
            subtitle: '${peso(c.remaining, dhs: villa)} to pay',
            kind: EventKind.rent,
          ),
      for (final c in cheques)
        if (c.tenant == tenant &&
            c.kind == ChequeKind.postDated &&
            (c.status == ChequeStatus.held ||
                c.status == ChequeStatus.deposited))
          CalendarEvent(
            date: c.date,
            time: 'All day',
            title: 'Cheque date',
            subtitle:
                '${peso(c.amount, dhs: true)} cheque${c.chequeNo.isEmpty ? '' : ' #${c.chequeNo}'}',
            kind: EventKind.rent,
          ),
    ];
  }

  static void _put<T>(List<T> list, List<T> loaded) => list
    ..clear()
    ..addAll(loaded);

  /// Puts in everything loaded from the database (replacing what was
  /// there), then works out statuses, conditions and rent again. On the
  /// admin's phone the daily jobs also run: renewals that start today, rent
  /// charges coming due, cheque and lease-end reminders.
  void loadFromServer({
    required List<UnitRec> units,
    required List<UnitTemplate> templates,
    required List<TenantRec> tenants,
    required List<FormerTenant> formerTenants,
    required List<ChargeRec> charges,
    required List<PaymentRec> payments,
    required List<ChequeRec> cheques,
    required List<TaxRate> taxes,
    required Map<String, List<MonthlyExpense>> monthlyExpenses,
    required List<ExpenseTemplate> expenseTemplates,
    required Map<String, List<CostEntry>> unitCosts,
    required List<String> costTypes,
    required List<String> chargeTypes,
    required List<Booking> bookings,
    required List<DamageReport> reports,
    required List<WorkItem> workItems,
    required List<ComplaintRec> complaints,
    required List<LeaseRequest> requests,
    required List<AdminNotice> notices,
    required List<AdminMessage> messages,
    required List<LogEntry> activityLog,
    required Map<String, bool> alertPrefs,
    double? gatewayFeePercent,
    double? bouncedChequeFee,
    int? rentChargeLeadDays,
    bool runDailyJobs = true,
  }) {
    _put(this.units, units);
    _put(unitTemplates, templates);
    _put(this.tenants, tenants);
    _put(this.formerTenants, formerTenants);
    _put(this.charges, charges);
    _put(this.payments, payments);
    _put(this.cheques, cheques);
    _put(this.taxes, taxes);
    this.monthlyExpenses
      ..clear()
      ..addAll(monthlyExpenses);
    _put(this.expenseTemplates, expenseTemplates);
    this.unitCosts
      ..clear()
      ..addAll(unitCosts);
    // An empty list in the database keeps the built-in choices.
    if (costTypes.isNotEmpty) _put(this.costTypes, costTypes);
    if (chargeTypes.isNotEmpty) _put(this.chargeTypes, chargeTypes);
    _put(this.bookings, bookings);
    _put(this.reports, reports);
    _put(this.workItems, workItems);
    _put(this.complaints, complaints);
    _put(this.requests, requests);
    _put(this.notices, notices);
    _put(this.messages, messages);
    _put(this.activityLog, activityLog);
    this.alertPrefs.addAll(alertPrefs);
    if (gatewayFeePercent != null) this.gatewayFeePercent = gatewayFeePercent;
    if (bouncedChequeFee != null) this.bouncedChequeFee = bouncedChequeFee;
    if (rentChargeLeadDays != null) {
      this.rentChargeLeadDays = rentChargeLeadDays;
    }
    refreshCondoStatuses();
    refreshConditions();
    if (runDailyJobs) {
      applyDueRenewals();
      generateRentCharges();
      sendChequeReminders();
      sendLeaseEndReminders();
    }
    refreshLeaseStatuses();
    notifyListeners();
  }

  final List<UnitTemplate> unitTemplates = demoData
      ? [
          UnitTemplate(
            name: 'Tower B · 1 bedroom',
            property: 'Ayan Tower B',
            type: 'Apartment',
            bedrooms: 1,
            rate: 8000,
            rateUnit: 'month',
          ),
          UnitTemplate(
            name: 'Villa · 3 bedrooms',
            property: 'Ayan Villas',
            type: 'Villa',
            bedrooms: 3,
            rate: 22000,
            rateUnit: 'month',
          ),
          UnitTemplate(
            name: 'Condo studio · nightly',
            property: 'Ayan Stays',
            type: 'Condo',
            bedrooms: 0,
            rate: 2500,
            rateUnit: 'night',
          ),
        ]
      : [];

  /// Saves a template at the front of the list (so its chip is visible); one
  /// with the same name is replaced.
  void saveTemplate(UnitTemplate t) {
    unitTemplates
      ..removeWhere((x) => x.name.toLowerCase() == t.name.toLowerCase())
      ..insert(0, t);
    notifyListeners();
  }

  void deleteTemplate(UnitTemplate t) {
    unitTemplates.remove(t);
    notifyListeners();
  }

  /// Edits a unit. Tenants living in it follow the new name, rate and stay type.
  void updateUnit(
    UnitRec u, {
    required String name,
    required String type,
    required int bedrooms,
    required double rate,
    required String rateUnit,
    required double deposit,
  }) {
    final old = u.name;
    // Scheduled work and condo stays follow the unit's new name.
    for (final w in workItems.where((w) => w.where == old)) {
      w.where = name;
    }
    for (final b in bookings.where((b) => b.unit == old)) {
      b.unit = name;
    }
    if (unitCosts.containsKey(old) && old != name) {
      unitCosts[name] = unitCosts.remove(old)!;
    }
    u.name = name;
    u.type = type;
    u.bedrooms = bedrooms;
    u.rate = rate;
    u.rateUnit = ratePeriodFor(type);
    u.depositAmount = deposit;
    for (final t in tenants) {
      if (t.unit == old) {
        t.unit = name;
        t.rent = rate;
        t.stayType = stayTypeFor(type);
      }
    }
    notifyListeners();
  }
}

final adminState = AdminState();
