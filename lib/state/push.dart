import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'backend.dart';
import 'sync.dart' show messengerKey;

/// Phone notifications (Android for now). After logging in, this phone is
/// registered for the user, so the server can notify it about notices, chat
/// messages, payments, reports and so on, even while the app is closed.
abstract final class Push {
  static bool _firebaseReady = false;
  static String? _token, _forUser;

  static bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Registers this phone for the logged-in user (asks for permission the
  /// first time). Safe to call again: it only does the work once per login.
  static Future<void> start() async {
    if (!_supported || !backendOn) return;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null || uid == _forUser) return;
    try {
      if (!_firebaseReady) {
        await Firebase.initializeApp();
        _firebaseReady = true;
        // The registration token is what the server sends to (the newer
        // installation-ID API is not used yet).
        // ignore: deprecated_member_use
        FirebaseMessaging.instance.onTokenRefresh.listen(_save);
        // With the app open, the phone shows nothing by itself: show it
        // at the bottom of the screen instead.
        FirebaseMessaging.onMessage.listen((m) {
          final n = m.notification;
          if (n == null) return;
          // The app is open: buzz the phone too (the system does it when closed).
          HapticFeedback.vibrate();
          Future.delayed(const Duration(milliseconds: 250), HapticFeedback.heavyImpact);
          messengerKey.currentState?.showSnackBar(SnackBar(
            // Just the headline: the details are in the app (Notices, or the
            // screen it is about), and a long text here is hard to read.
            content: Text(n.title ?? n.body ?? ''),
          ));
        });
      }
      await FirebaseMessaging.instance.requestPermission();
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _save(token);
      _forUser = uid;
    } catch (e) {
      debugPrint('Push: $e');
    }
  }

  static Future<void> _save(String token) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    _token = token;
    try {
      await supabase.from('push_tokens').upsert({
        'profile_id': uid,
        'token': token,
        'platform': 'android',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
    } catch (e) {
      debugPrint('Push token: $e');
    }
  }

  /// Before logging out: this phone stops getting this user's notifications.
  static Future<void> stop() async {
    final token = _token;
    _forUser = null;
    if (!_supported || !backendOn || token == null) return;
    try {
      await supabase.from('push_tokens').delete().eq('token', token);
    } catch (_) {}
  }
}
