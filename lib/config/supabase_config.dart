/// Where the app's backend lives. This public copy has no backend: it runs
/// in demo mode with fictional sample data. To connect your own Supabase
/// project, fill these in and run with --dart-define=DEMO_DATA=false.
///
/// The publishable key is meant to be inside the app: what each user can see
/// is decided by the database's row-level security rules, not by this key.
/// NEVER put the secret / service_role key or any password here.
abstract final class SupabaseConfig {
  static const url = 'https://YOUR-PROJECT.supabase.co';
  static const publishableKey = 'YOUR-PUBLISHABLE-KEY';

  /// The admin can log in with this username or the email.
  static const adminUsername = 'Ayan-Admin';
  static const adminEmail = 'admin@example.com';

  /// Tenants log in with a username; behind the scenes their login is
  /// `username@` this private domain (no mail is ever sent there).
  static const tenantEmailDomain = 'accounts.example.app';
}