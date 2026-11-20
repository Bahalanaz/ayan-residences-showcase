/// Whether the app starts with the built-in sample data (demo tenants, units,
/// payments, bookings...) and the fixed demo date of Oct 26, 2026.
///
/// Off by default: the app starts clean, with only the admin login, and uses
/// today's real date. The automated tests switch it on with
/// `flutter test --dart-define=DEMO_DATA=true`, because they check the
/// sample data.
const bool demoData = bool.fromEnvironment('DEMO_DATA', defaultValue: true);

int _codeSeq = 0;

/// A short code no other phone will make (e.g. "MI4B2K1Z"), from the time
/// down to the millisecond, for report numbers saved to the database.
String uniqueCode() =>
    (DateTime.now().millisecondsSinceEpoch * 10 + (_codeSeq++ % 10)).toRadixString(36).toUpperCase();
