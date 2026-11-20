import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'demo.dart';
import 'sync.dart';
import 'push.dart';

/// The Supabase client, once [initBackend] has run (not in the demo).
SupabaseClient get supabase => Supabase.instance.client;

/// True when the app talks to Supabase. The demo (and the tests) keep
/// everything in memory instead.
bool get backendOn => !demoData && _ready;
bool _ready = false;

/// Starts Supabase before the app shows. It also restores the saved login,
/// so a returning user goes straight in.
Future<void> initBackend() async {
  if (demoData || _ready) return;
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  _ready = true;
}

/// The address Supabase knows a login by. The admin can type the username
/// or the email; a tenant's username maps to a private address that never
/// receives mail.
String loginEmailFor(String input) {
  final v = input.trim();
  if (v.contains('@')) return v.toLowerCase();
  if (v.toLowerCase() == SupabaseConfig.adminUsername.toLowerCase()) return SupabaseConfig.adminEmail;
  return '${v.toLowerCase()}@${SupabaseConfig.tenantEmailDomain}';
}

/// "admin" or "tenant", from the role the server set on the login (never
/// from anything the user can edit).
String? roleOf(User? user) => user?.appMetadata['role'] as String?;

bool get signedInAsAdmin => backendOn && roleOf(supabase.auth.currentUser) == 'admin';

/// Logs in with a username or email. Returns null when it worked, or a
/// message to show.
Future<String?> backendSignIn(String usernameOrEmail, String password) async {
  try {
    await supabase.auth.signInWithPassword(email: loginEmailFor(usernameOrEmail), password: password);
    return null;
  } on AuthException catch (e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid') || m.contains('credentials')) {
      return 'Incorrect username or password. Please check the details given by management.';
    }
    return "Couldn't log in. Please try again.";
  } catch (_) {
    return 'Could not reach the server. Check your internet connection and try again.';
  }
}

/// The sign-out running now, so tapping Sign Out again joins it instead of
/// starting another one.
Future<void>? _signingOut;

Future<void> backendSignOut() =>
    _signingOut ??= _signOut().whenComplete(() => _signingOut = null);

Future<void> _signOut() async {
  if (!backendOn) return;
  // Save what is still waiting, then stop saving for this login.
  // (but never wait forever on a bad connection)
  try {
    await Sync.flush().timeout(const Duration(seconds: 20));
  } catch (_) {}
  Sync.stop();
  await Push.stop().timeout(const Duration(seconds: 5), onTimeout: () {});
  await supabase.auth.signOut();
}

/// Changes the logged-in user's password. Returns null when it worked.
Future<String?> backendChangePassword(String newPassword) async {
  try {
    await supabase.auth.updateUser(UserAttributes(password: newPassword));
    return null;
  } on AuthException catch (e) {
    final m = e.message.toLowerCase();
    if (m.contains('different')) {
      return 'Your new password must be different from the old one.';
    }
    if (m.contains('at least') || m.contains('weak') || m.contains('short')) {
      return 'That password is too short. Use at least 6 characters.';
    }
    return "Couldn't change the password. Please try again.";
  } catch (_) {
    return 'Could not reach the server. Check your internet connection and try again.';
  }
}
