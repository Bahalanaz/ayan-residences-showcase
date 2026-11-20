import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns any error into a short, plain sentence for a message box, like
/// everyday apps show. Technical details (database codes, server replies)
/// never reach the screen; they still go to the debug log where it is
/// caught.
String friendlyError(Object e) {
  if (isOffline(e)) return 'No internet connection. Please try again.';
  if (e is PostgrestException) {
    final m = e.message.toLowerCase();
    if (e.code == '42501' ||
        m.contains('row-level security') ||
        m.contains('permission denied')) {
      return "You don't have permission to do that.";
    }
    if (e.code == '23505' || m.contains('duplicate')) {
      return 'That already exists.';
    }
  }
  if (e is StorageException) {
    final m = e.message.toLowerCase();
    if (m.contains('size') ||
        m.contains('too large') ||
        e.statusCode == '413') {
      return 'That file is too large.';
    }
  }
  if (e is AuthException) return 'Please log in again.';
  return 'Something went wrong. Please try again.';
}

/// A message the server wrote for people (e.g. "That username is already
/// used by Ana"), kept as it is; anything that looks technical is swapped
/// for [fallback].
String plainOr(Object? message, String fallback) {
  final m = message is String ? message.trim() : '';
  if (m.isEmpty || _technical.hasMatch(m)) return fallback;
  return m;
}

final _technical = RegExp(
  r'violates|constraint|duplicate key|relation|column|jwt|null value|syntax|'
  r'pgrst|exception|json|post\b|tenant_id|unknown action|not linked|'
  r'\b\d{3,5}\b|[{}\[\]]',
  caseSensitive: false,
);

/// The server refused because this login may not do it. The person using
/// the app can't fix that, so it is never shown to them.
bool isPermissionError(Object e) {
  final m = switch (e) {
    PostgrestException(:final message, :final code) => '$code $message',
    StorageException(:final message, :final statusCode) =>
      '$statusCode $message',
    _ => '',
  }.toLowerCase();
  return m.contains('42501') ||
      m.contains('row-level security') ||
      m.contains('permission denied') ||
      m.startsWith('403') ||
      m.contains('unauthorized');
}

/// The row is already there (e.g. the same monthly rent charge, made by
/// the admin on another phone a moment earlier).
bool isDuplicate(Object e) =>
    e is PostgrestException &&
    (e.code == '23505' || e.message.toLowerCase().contains('duplicate'));

/// No connection, or the server took too long.
bool isOffline(Object e) {
  if (e is TimeoutException) return true;
  final s = '${e.runtimeType} $e'.toLowerCase();
  return s.contains('socket') ||
      s.contains('failed host lookup') ||
      s.contains('clientexception') ||
      s.contains('connection') ||
      s.contains('network');
}
