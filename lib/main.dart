import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'admin/admin_shell.dart';
import 'admin/admin_state.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';
import 'state/backend.dart';
import 'state/demo.dart';
import 'state/session.dart';
import 'state/sync.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!demoData) {
    // The real app: Supabase restores the saved login itself, and the data
    // of whoever is logged in is loaded before the first screen.
    String? savedUser;
    try {
      await initBackend();
      if (supabase.auth.currentSession != null) {
        await Sync.load();
        if (signedInAsAdmin) {
          savedUser = adminUsername;
        } else if (Sync.hasTenantRecord) {
          savedUser = appState.currentTenant;
        } else {
          await backendSignOut();
        }
      }
    } catch (_) {
      // No connection at start-up: show the login screen, which explains.
    }
    runApp(AyanApp(savedUser: savedUser));
    return;
  }
  // Demo: restore the saved login only if that account still exists;
  // otherwise (e.g. an old demo login) start at the login screen.
  var user = await Session.load();
  if (user != null && user != adminUsername) {
    final t = adminState.tenants.where((t) => t.username.toLowerCase() == user!.toLowerCase());
    if (t.isNotEmpty) {
      adminState.signInTenant(t.first.name);
    } else if (!(demoData && user == '123')) {
      await Session.clear();
      user = null;
    }
  }
  runApp(AyanApp(savedUser: user));
}

class AyanApp extends StatelessWidget {
  const AyanApp({super.key, this.savedUser});

  /// Username of the saved session, if any. Skips the login screen.
  final String? savedUser;

  @override
  Widget build(BuildContext context) {
    final Widget home;
    if (savedUser == null) {
      home = const LoginScreen();
    } else if (savedUser == adminUsername) {
      home = const AdminShell();
    } else {
      home = const Shell();
    }
    return MaterialApp(
      title: 'Ayan Residences',
      scaffoldMessengerKey: messengerKey,
      navigatorKey: navigatorKey,
      navigatorObservers: [routeWatcher],
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Tapping anywhere outside a text field closes the keyboard, so it never
      // stays over what's underneath. (Taps on buttons still go to them.)
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: _PhoneFrame(child: child ?? const SizedBox()),
      ),
      home: home,
    );
  }
}

/// In a wide browser window (the web demo) the app is shown inside a phone-sized
/// frame instead of being stretched across the whole window.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});
  final Widget child;

  static const _width = 430.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      // Real phones and tablets always run full screen; the frame is only
      // for showing the demo in a desktop browser.
      if (!kIsWeb || box.maxWidth < 700) return child;
      final h = (box.maxHeight - 40).clamp(480.0, 960.0);
      final mq = MediaQuery.of(context);
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -.4),
            radius: 1.2,
            colors: [Color(0xFF1A4A3E), Color(0xFF061A15)],
          ),
        ),
        child: Center(
          child: Container(
            width: _width + 16,
            height: h + 16,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F0D),
              borderRadius: BorderRadius.circular(46),
              border: Border.all(color: const Color(0xFFC8A96B).withValues(alpha: .5), width: 1.5),
              boxShadow: const [
                BoxShadow(color: Colors.black87, blurRadius: 40, offset: Offset(0, 18)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(38),
              child: MediaQuery(
                data: mq.copyWith(size: Size(_width, h), padding: EdgeInsets.zero),
                child: child,
              ),
            ),
          ),
        ),
      );
    });
  }
}
