import 'package:shared_preferences/shared_preferences.dart';

/// Remembers who is logged in so the app skips the login screen next launch.
/// Swap this for a real auth token once a backend exists.
class Session {
  static const _key = 'logged_in_user';

  static Future<String?> load() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String username) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, username);
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {}
  }
}
