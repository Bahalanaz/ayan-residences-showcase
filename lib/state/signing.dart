import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'backend.dart';

/// The proof kept with a signed document: who signed, from which account,
/// when, on what device, and a fingerprint of the document before and after.
class SignatureAudit {
  SignatureAudit({
    required this.signer,
    required this.account,
    required this.signedAt,
    required this.device,
    required this.originalHash,
    required this.signedHash,
  });

  /// The signer's name and the username they were logged in with.
  final String signer, account;

  /// When it was signed, by the server's clock.
  final DateTime signedAt;

  /// The phone it was signed on ("Android", "iOS"...).
  final String device;

  /// SHA-256 fingerprints of the document as sent and as signed. Changing
  /// even one dot in a file changes its fingerprint completely.
  final String originalHash;
  String signedHash;
}

/// The SHA-256 fingerprint of [bytes], as 64 hex characters.
String fingerprint(List<int> bytes) => sha256.convert(bytes).toString();

/// A short form of a fingerprint for screens: first and last 8 characters.
String shortFingerprint(String hash) => hash.length <= 20
    ? hash
    : '${hash.substring(0, 8)}…${hash.substring(hash.length - 8)}';

/// The signing time, from the server's clock (the phone's clock can be
/// changed by whoever holds it), shown in the phone's time zone. Throws when
/// the server can't be reached: a document is never signed with the phone's
/// own time. Only the demo (no backend) uses the phone's time.
Future<DateTime> trustedNow() async {
  if (!backendOn) return DateTime.now();
  final v = await supabase
      .rpc('server_now')
      .timeout(const Duration(seconds: 15));
  final t = DateTime.tryParse('$v');
  if (t == null) throw StateError('The server did not send its time.');
  return t.toLocal();
}

/// The device the signature was made on.
String signingDevice() => kIsWeb
    ? 'Web browser'
    : switch (defaultTargetPlatform) {
        TargetPlatform.android => 'Android phone',
        TargetPlatform.iOS => 'iPhone',
        TargetPlatform.windows => 'Windows',
        TargetPlatform.macOS => 'Mac',
        _ => defaultTargetPlatform.name,
      };
