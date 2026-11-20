import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/admin_state.dart';
import 'app_state.dart';
import 'backend.dart';
import 'chat_state.dart';
import 'friendly_error.dart';
import 'push.dart';

/// Shows messages (like "Could not save") wherever the user is in the app.
final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// The app's navigator, to tell whether a form or detail screen is open.
final navigatorKey = GlobalKey<NavigatorState>();

/// Counts the dialogs and bottom sheets that are open (forms often are
/// one), so a live update never swaps the data out from under them.
class PopupWatcher extends NavigatorObserver {
  int open = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) open++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute && open > 0) open--;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute && open > 0) open--;
  }
}

final routeWatcher = PopupWatcher();

/// Put on a full-screen form: while it is open, live updates wait (what is
/// being typed would otherwise be saved to a record that was replaced).
mixin EditingGuard<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    Sync._editing++;
  }

  @override
  void dispose() {
    Sync._editing--;
    super.dispose();
  }
}

/// Keeps the app's data and the Supabase database in step.
///
/// The screens keep working on the app's own lists, so they stay fast. A
/// moment after anything changes, the lists are compared with what was last
/// saved and only the differences are written: new things are added,
/// changed ones updated, removed ones deleted. Each list is one table (see
/// [_buildSteps]), saved in an order where a row always exists before the
/// rows that point to it.
///
/// On a tenant's phone only what a tenant may change is written (their
/// contact details, payment proofs, reports, requests, messages, documents,
/// cheque photos, signing, read receipts); the database's rules allow
/// nothing else. Nothing here runs in the demo.
abstract final class Sync {
  // ------------------------------------------------------------ state

  static bool _tenantMode = false;

  /// True after signing out, until the next login loads.
  static bool _stopped = false;

  /// Goes up at every sign-out. A save still running from an earlier login
  /// (it carries its number) then knows to stop and stay quiet.
  static int _gen = 0;
  static bool get _stale {
    final g = Zone.current[#syncGen];
    if (g is! int) return false;
    // Signed out since, or now someone else is logged in.
    return g != _gen ||
        Zone.current[#syncWho] != (supabase.auth.currentUser?.id ?? '');
  }

  static bool _listening = false;
  static bool _paused = true;
  static bool _again = false;
  static Timer? _timer;
  static Future<void>? _running;
  static bool _dirty = false;
  static List<_Step> _steps = const [];

  /// The signed-in tenant's row id (tenant phones only).
  static int? _myTenantId;

  /// Tenant and unit ids by name, for rows that point to them.
  static final Map<String, int> _tenantIds = {};
  static final Map<String, int> _propertyIds = {};

  // ------------------------------------------------------------ public

  /// Loads everything this login may see, then keeps saving changes.
  /// Called after logging in, when the app opens with a saved login, and
  /// when the user pulls down to refresh.
  ///
  /// Loads never overlap: one that starts while another is running waits
  /// for it first. (Two at once used to mix their copies of the data, and
  /// the save step then deleted rows that were still there.)
  static Future<void> load() {
    final before = _loading;
    late final Future<void> mine;
    mine =
        () async {
          if (before != null) {
            try {
              await before;
            } catch (_) {}
          }
          await _loadOnce();
        }().whenComplete(() {
          if (identical(_loading, mine)) _loading = null;
        });
    _loading = mine;
    return mine;
  }

  static Future<void>? _loading;

  static Future<void> _loadOnce() async {
    if (!backendOn) return;
    _stopped = false;
    _paused = true;
    _timer?.cancel();
    _stopLive();
    while (_running != null) {
      await _running;
    }
    try {
      _tenantMode = !signedInAsAdmin;
      _steps = _buildSteps();
      await _loadEverything();
      // A tenant whose login was never linked to their record (the link
      // step failed when it was created): link it now, then load again.
      if (_tenantMode && _myTenantId == null) {
        try {
          final linked = await supabase.rpc('link_my_tenant');
          if (linked != null) {
            _steps = _buildSteps();
            await _loadEverything();
          }
        } catch (e) {
          debugPrint('Link: $e');
        }
      }
      for (final s in _steps) {
        await s.prime();
      }
    } finally {
      _paused = false;
    }
    if (!_listening) {
      _listening = true;
      adminState.addListener(_changed);
      appState.addListener(_changed);
      chatState.addListener(_changed);
      chatState.addListener(_sendChat);
    }
    // Save anything the app added while loading (e.g. this month's rent).
    _changed();
    _listenLive();
    // This phone gets notifications for whoever is logged in.
    unawaited(Push.start());
    // Daily cleanup and the storage meter (admin, in the background).
    if (!_tenantMode) unawaited(_dailyUpkeep());
    // Files that were open before this reload come back by themselves.
    if (!_tenantMode) _refetchOpened();
    // A tenant has only a few files of their own: bring them in the
    // background, after the text is already on screen.
    if (_tenantMode) {
      unawaited(
        fetch([
          for (final t in adminState.tenants) ...[
            t,
            ...t.pastLeases,
            t.nextLease,
          ],
          ...adminState.cheques,
          ...adminState.payments,
          ...adminState.reports,
          for (final c in _allChat) c.m,
        ]),
      );
    }
  }

  /// On a tenant's phone: true when the login found its tenant record.
  static bool get hasTenantRecord => _myTenantId != null;

  /// Stops saving (after logging out).
  static void stop() {
    _paused = true;
    _stopped = true;
    _gen++;
    _timer?.cancel();
    _stopLive();
  }

  /// Waits until every change made so far has been saved.
  static Future<void> flush() async {
    if (_timer?.isActive ?? false) {
      _timer!.cancel();
      _kick();
    }
    while (_running != null) {
      await _running;
    }
  }

  /// Creates or updates a tenant's login (server function; the app never
  /// holds the secret key). Returns null when it worked, or what went wrong.
  static Future<String?> saveLogin(
    int tenantId,
    String username,
    String password,
  ) => _callAccounts({
    'action': 'upsert',
    'tenant_id': tenantId,
    'username': username,
    if (password.isNotEmpty) 'password': password,
  });

  // ------------------------------------------------------------ upkeep

  /// The storage meter's latest reading (admin only; null until read).
  static final storage = ValueNotifier<StorageReport?>(null);

  /// Reads how much file storage is used, per area, and the plan's limit.
  static Future<StorageReport?> readStorage() async {
    if (!backendOn || _tenantMode) return null;
    final rows = await supabase.rpc('storage_usage') as List;
    final s = await supabase
        .from('settings')
        .select('storage_limit_mb, last_cleanup_at')
        .maybeSingle();
    final report = StorageReport(
      byArea: {
        for (final r in rows)
          (r as Map)['bucket'] as String: (
            (r['bytes'] as num).toInt(),
            (r['files'] as num).toInt(),
          ),
      },
      limitBytes: ((s?['storage_limit_mb'] as int?) ?? 1024) * 1024 * 1024,
      lastCleanup: _time(s?['last_cleanup_at']),
    );
    storage.value = report;
    return report;
  }

  /// Full-screen forms open now (see [EditingGuard]).
  static int _editing = 0;

  static bool _upkeepRunning = false;
  static DateTime? _warnedAt;

  /// Once a day on the admin's phone: the cleanup, then the storage meter
  /// (with a warning from 80% full). Runs in the background after loading.
  static Future<void> _dailyUpkeep() async {
    if (_upkeepRunning || _tenantMode || !backendOn) return;
    _upkeepRunning = true;
    try {
      final removed = await cleanUp();
      final report = await readStorage();
      if (report != null && report.fraction >= .8) {
        final now = DateTime.now();
        if (_warnedAt == null || now.difference(_warnedAt!).inHours >= 12) {
          _warnedAt = now;
          messengerKey.currentState?.showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 6),
              content: Text(
                'File storage is ${(report.fraction * 100).round()}% full. '
                'See More → Storage & cleanup.',
              ),
            ),
          );
        }
      }
      // Files were removed: show the lists without them.
      if (removed > 0) await load();
    } catch (e) {
      debugPrint('Upkeep: $e');
    } finally {
      _upkeepRunning = false;
    }
  }

  /// Removes what is no longer needed, at most once a day unless [force]:
  /// - condo guest files 90 days after check-out,
  /// - chat photos older than 1 year (the text stays),
  /// - a former tenant's documents, cheque photos and payment receipts 2
  ///   years after they moved out (contracts and signed papers are kept),
  /// - activity log entries older than 2 years.
  /// Returns how many files and log entries were removed.
  static Future<int> cleanUp({bool force = false}) async {
    if (!backendOn || _tenantMode) return 0;
    final db = supabase;
    final now = DateTime.now().toUtc();
    if (!force) {
      final s = await db
          .from('settings')
          .select('last_cleanup_at')
          .maybeSingle();
      final last = _time(s?['last_cleanup_at']);
      if (last != null && now.difference(last.toUtc()).inHours < 20) return 0;
    }
    var removed = 0;

    Future<void> drop(String bucket, Iterable<Object?> paths) async {
      final list = [
        for (final p in paths)
          if (p is String && p.isNotEmpty) p,
      ];
      for (var i = 0; i < list.length; i += 100) {
        final chunk = list.sublist(
          i,
          i + 100 > list.length ? list.length : i + 100,
        );
        await db.storage.from(bucket).remove(chunk);
        removed += chunk.length;
      }
    }

    // 1. Condo guest files, 90 days after check-out.
    final oldStays = [
      for (final r
          in await db
              .from('bookings')
              .select('id')
              .lt('check_out', _ts(now.subtract(const Duration(days: 90)))))
        r['id'] as int,
    ];
    if (oldStays.isNotEmpty) {
      final files = await db
          .from('booking_files')
          .select('id, file_path')
          .inFilter('booking_id', oldStays);
      if (files.isNotEmpty) {
        await drop('guest-files', files.map((f) => f['file_path']));
        await db.from('booking_files').delete().inFilter('id', [
          for (final f in files) f['id'] as int,
        ]);
      }
    }

    // 2. Chat photos older than a year (the message text stays).
    final oldPhotos = await db
        .from('chat_messages')
        .select('id, body, image_path')
        .not('image_path', 'is', null)
        .lt('created_at', _ts(now.subtract(const Duration(days: 365))));
    if (oldPhotos.isNotEmpty) {
      await drop('chat-files', oldPhotos.map((r) => r['image_path']));
      for (final r in oldPhotos) {
        await db
            .from('chat_messages')
            .update({
              'image_path': null,
              'body': r['body'] ?? 'Photo removed after 1 year',
            })
            .eq('id', r['id'] as Object);
      }
    }

    // 3. Former tenants, 2 years after moving out.
    final oldMoves = await db
        .from('move_outs')
        .select('leases(tenant_id)')
        .lt('moved_out_on', _d(now.subtract(const Duration(days: 730))));
    final formerIds = {
      for (final m in oldMoves)
        if ((m['leases'] as Map?)?['tenant_id'] != null)
          (m['leases'] as Map)['tenant_id'] as int,
    }.toList();
    if (formerIds.isNotEmpty) {
      final docs = await db
          .from('tenant_documents')
          .select('id, file_path')
          .inFilter('tenant_id', formerIds);
      if (docs.isNotEmpty) {
        await drop('tenant-documents', docs.map((d) => d['file_path']));
        await db.from('tenant_documents').delete().inFilter('id', [
          for (final d in docs) d['id'] as int,
        ]);
      }
      final leaseIds = [
        for (final l
            in await db
                .from('leases')
                .select('id')
                .inFilter('tenant_id', formerIds))
          l['id'] as int,
      ];
      if (leaseIds.isNotEmpty || formerIds.isNotEmpty) {
        final photos = await db
            .from('cheques')
            .select('id, photo_path')
            .inFilter('tenant_id', formerIds)
            .not('photo_path', 'is', null);
        if (photos.isNotEmpty) {
          await drop('cheque-photos', photos.map((c) => c['photo_path']));
          await db.from('cheques').update({'photo_path': null}).inFilter('id', [
            for (final c in photos) c['id'] as int,
          ]);
        }
      }
      final receipts = await db
          .from('payments')
          .select('id, proof_path')
          .inFilter('tenant_id', formerIds)
          .not('proof_path', 'is', null);
      if (receipts.isNotEmpty) {
        await drop('payment-proofs', receipts.map((p) => p['proof_path']));
        await db.from('payments').update({'proof_path': null}).inFilter('id', [
          for (final p in receipts) p['id'] as int,
        ]);
      }
    }

    // 4. Files nothing points to any more (a removed or replaced file).
    try {
      final orphans = <String, List<String>>{};
      for (final r in await db.rpc('orphan_files') as List) {
        (orphans[(r as Map)['bucket'] as String] ??= []).add(
          r['path'] as String,
        );
      }
      // Safety: day to day only a few files are left over. Many at once
      // means records went missing (they may be restored from a backup),
      // so nothing is deleted.
      final count = orphans.values.fold<int>(0, (n, l) => n + l.length);
      if (count > 20) {
        debugPrint('Leftover files: $count found; too many, none removed.');
      } else {
        for (final e in orphans.entries) {
          await drop(e.key, e.value);
        }
      }
    } catch (e) {
      debugPrint('Leftover files: $e'); // the sweep function is not set up yet
    }

    // 4. The activity log keeps 2 years.
    removed += ((await db.rpc('trim_activity_log')) as num?)?.toInt() ?? 0;

    await db
        .from('settings')
        .update({'last_cleanup_at': _ts(now)})
        .eq('id', true);
    return removed;
  }

  // ------------------------------------------------------------ live chat

  static RealtimeChannel? _live;

  static void _stopLive() {
    final ch = _live;
    _live = null;
    if (ch != null) supabase.removeChannel(ch);
  }

  /// New chat messages and signing updates arrive the moment they are saved
  /// on the other phone, without refreshing. (The database's rules decide
  /// what each login receives, as for everything else.)
  static void _listenLive() {
    _stopLive();
    _live = supabase
        .channel('ayan-live-${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          callback: (p) => _liveMessage(p.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'documents_to_sign',
          callback: (p) {
            if (p.newRecord.isNotEmpty) _liveDocument(p.newRecord);
          },
        )
        // Anything else (a lease, rent, notice, payment, report...) changed
        // on the other phone: load it again in the background.
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          callback: (p) {
            if (const {
              'chat_messages',
              'documents_to_sign',
              'chat_reads',
            }.contains(p.table)) {
              return;
            }
            _remoteChanged();
          },
        )
        .subscribe((status, _) {
          // Also after the connection drops and comes back.
          if (status == RealtimeSubscribeStatus.subscribed) _catchUp();
        });
    // Back in the app after a while: fetch what came in meanwhile.
    _life ??= AppLifecycleListener(
      onResume: () {
        _catchUp();
        _remoteChanged();
      },
    );
  }

  static AppLifecycleListener? _life;

  /// When this phone last finished saving. Changes arriving just after are
  /// its own saves coming back, not news.
  static DateTime _savedAt = DateTime(2000);
  static Timer? _refreshTimer;

  /// Something changed on the server: reload in a moment (changes often
  /// come several at once).
  static void _remoteChanged() {
    if (!backendOn || _paused) return;
    if (_running != null ||
        DateTime.now().difference(_savedAt).inMilliseconds < 2500) {
      return;
    }
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 1500), _refreshNow);
  }

  static Future<void> _refreshNow() async {
    if (!backendOn || _paused) return;
    // Never under an open form, sheet or detail screen: what is being
    // edited there would be swapped out. Try again once back on the main
    // screen.
    if (routeWatcher.open > 0 || _editing > 0) {
      _refreshTimer = Timer(const Duration(seconds: 3), _refreshNow);
      return;
    }
    try {
      await flush();
      await load();
    } catch (e) {
      debugPrint('Live refresh: $e');
    }
  }

  /// The newest chat message time seen (the server's clock).
  static DateTime? _chatSince;

  /// Fetches chat messages and signing updates that arrived while this
  /// phone was offline or the app was in the background.
  static Future<void> _catchUp() async {
    if (!backendOn || _paused) return;
    try {
      final since = _chatSince;
      final rows = since == null
          ? await supabase
                .from('chat_messages')
                .select()
                .order('created_at', ascending: true)
          : await supabase
                .from('chat_messages')
                .select()
                .gte(
                  'created_at',
                  _ts(since.subtract(const Duration(minutes: 2))),
                )
                .order('created_at', ascending: true);
      for (final r in rows) {
        await _liveMessage(r);
      }
      for (final d in await supabase.from('documents_to_sign').select()) {
        await _liveDocument(d);
      }
    } catch (e) {
      debugPrint('Catch-up: $e');
    }
  }

  static bool _chatBusy = false, _chatAgain = false;

  /// Chat is sent straight away, not after the usual short wait.
  static Future<void> _sendChat() async {
    if (!backendOn || _paused) return;
    if (_chatBusy) {
      _chatAgain = true;
      return;
    }
    _chatBusy = true;
    try {
      do {
        _chatAgain = false;
        await _chat.save();
        await _signing.save();
      } while (_chatAgain);
    } finally {
      _chatBusy = false;
    }
  }

  /// Signing rows that arrived before their chat message, by message id.
  static final Map<String, Map<String, dynamic>> _waitingDocs = {};

  static ChatMessage? _messageById(String id) {
    for (final c in _allChat) {
      if (_chat.idOf(c.m) == id) return c.m;
    }
    return null;
  }

  static Future<void> _liveMessage(Map<String, dynamic> r) async {
    try {
      final id = r['id'] as String?;
      if (id == null || _messageById(id) != null) return;
      final name = _tenantName(r['tenant_id']);
      if (name.isEmpty) return;
      final from = r['sender'] == 'admin'
          ? ChatSender.admin
          : ChatSender.tenant;
      final time = _time(r['created_at'])!;
      if (_chatSince == null || time.isAfter(_chatSince!)) _chatSince = time;
      // This phone's own message, saved a moment ago: just note its id.
      final own = chatState
          .messages(name)
          .where(
            (m) =>
                _chat.idOf(m) == null &&
                m.from == from &&
                (m.text ?? m.docTitle ?? m.fileName) == r['body'],
          )
          .firstOrNull;
      if (own != null) {
        await _chat.markSaved(own, id);
        chatState.setDelivery(own, Delivery.sent);
        return;
      }
      final image = await _get('chat-files', r['image_path']);
      if (_messageById(id) != null) return;
      final m = ChatMessage(
        id: id,
        from: from,
        time: time,
        text: r['file_path'] == null ? r['body'] as String? : null,
        image: image,
        fileName: r['file_name'] as String?,
        fileBytes: await _get('chat-files', r['file_path']),
      );
      await _chat.markSaved(m, id);
      chatState.receive(name, m);
      final doc = _waitingDocs.remove(id);
      if (doc != null) await _liveDocument(doc);
    } catch (e) {
      debugPrint('Live chat: $e');
    }
  }

  static String _signStatusOf(ChatMessage m) => switch (m.sign) {
    SignStatus.signed => 'signed',
    SignStatus.completed => 'accepted',
    _ => 'awaiting',
  };

  static Future<void> _liveDocument(Map<String, dynamic> d) async {
    try {
      final messageId = d['message_id'] as String?;
      if (messageId == null) return;
      final m = _messageById(messageId);
      if (m == null) {
        _waitingDocs[messageId] = d;
        return;
      }
      // Nothing new (e.g. this phone's own change coming back).
      if (m.isSignRequest &&
          _signing.idOf(m) != null &&
          _signStatusOf(m) == d['status'] &&
          m.revision == (d['revision'] as int? ?? 0) &&
          m.audit?.signedHash == d['signed_hash']) {
        return;
      }
      final name = _chatTenant[m] ?? _tenantName(d['tenant_id']);
      var target = m;
      if (!m.isSignRequest) {
        // The request's message arrived first as plain text: show it as a
        // document to sign.
        target = ChatMessage(
          id: m.id,
          from: m.from,
          time: m.time,
          image: m.image,
          docTitle: d['title'] as String,
          fileName: d['original_name'] as String?,
          fileBytes: await _get('chat-files', d['original_path']),
        );
        await _chat.markSaved(target, messageId);
        chatState.swap(name, m, target);
      }
      final signedAt = _time(d['signed_at']);
      target
        ..sign = switch (d['status']) {
          'signed' => SignStatus.signed,
          'accepted' => SignStatus.completed,
          _ => SignStatus.awaiting,
        }
        ..signature = await _get('chat-files', d['signature_path'])
        ..signedPdf = await _get('chat-files', d['signed_path'])
        ..signedAt = signedAt
        ..revision = d['revision'] as int? ?? 0
        ..note = d['return_note'] as String?
        ..audit = signedAt == null || d['signed_hash'] == null
            ? null
            : SignatureAudit(
                signer: name,
                account:
                    adminState.tenants
                        .where((t) => t.name == name)
                        .firstOrNull
                        ?.username ??
                    '',
                signedAt: signedAt,
                device: d['signed_device'] as String? ?? '',
                originalHash: d['original_hash'] as String? ?? '',
                signedHash: d['signed_hash'] as String,
              );
      await _signing.markSaved(target, d['id'] as Object);
      chatState.touch();
    } catch (e) {
      debugPrint('Live signing: $e');
    }
  }

  // ------------------------------------------------------------ engine

  static void _changed() {
    if (!backendOn || _paused) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 700), _kick);
  }

  static void _kick() {
    if (_running != null) {
      _dirty = true;
      return;
    }
    _running = _pass().whenComplete(() {
      _running = null;
      if (_dirty) {
        _dirty = false;
        _kick();
      }
    });
  }

  /// Runs one step, but never lets a slow or lost connection hold up the
  /// rest: after a while the next step goes ahead (the slow one keeps
  /// trying in the background, and anything left is saved on the next pass).
  static Future<void> _guarded(Future<void> Function() step) async {
    try {
      await step().timeout(const Duration(seconds: 25));
    } on TimeoutException {
      debugPrint('Sync: a step took too long; moving on.');
    } catch (e) {
      debugPrint('Sync: $e');
    }
  }

  static Future<void> _pass() {
    final who = supabase.auth.currentUser?.id;
    // Nobody logged in, saving stopped (signing out), or a login is still
    // loading (it may not know yet whose data this is): nothing to save.
    if (who == null || _stopped || _paused) return Future.value();
    return runZoned(_passBody, zoneValues: {#syncGen: _gen, #syncWho: who});
  }

  static Future<void> _passBody() async {
    // A pass belongs to the login that started it: once that login signs
    // out, it stops (the next login must not write the last one's changes).
    final who = supabase.auth.currentUser?.id;
    bool gone() => _stopped || supabase.auth.currentUser?.id != who;
    for (var i = 0; i < 3; i++) {
      _again = false;
      // Removals first, children before parents; then adds and changes,
      // parents before children.
      for (final s in _steps.reversed) {
        if (gone()) return;
        await _guarded(s.remove);
      }
      for (final s in _steps) {
        if (gone()) return;
        await _guarded(s.save);
      }
      if (!_again) break;
    }
    _savedAt = DateTime.now();
  }

  static String? _lastError;
  static DateTime _lastErrorAt = DateTime(2000);

  static void _failed(String what, Object e) {
    // Signed out (or another login) meanwhile: not this person's problem.
    if (_stopped || _stale) return;
    debugPrint('Sync: could not save $what: $e');
    // Something this login may not do: nobody using the app can fix that,
    // so nothing is shown (the log keeps it).
    if (isPermissionError(e)) return;
    // Already saved by another phone on the same account (two admins at
    // once): nothing is wrong, just fetch what the other phone saved.
    if (isDuplicate(e)) {
      _refreshTimer?.cancel();
      _refreshTimer = Timer(const Duration(seconds: 4), _refreshNow);
      return;
    }
    final String text;
    if (_tenantMode) {
      // Tenants get one plain line, never the app's internal names.
      text = isOffline(e)
          ? "Your changes couldn't be saved. Check your internet connection and try again."
          : "Your changes couldn't be saved. Please try again.";
    } else {
      text = what.startsWith('the removal of ')
          ? "Couldn't remove ${what.substring(15)}. ${friendlyError(e)}"
          : "Couldn't save $what. ${friendlyError(e)}";
    }
    final now = DateTime.now();
    // The same problem is shown once a minute at most.
    if (text == _lastError && now.difference(_lastErrorAt).inSeconds < 60) {
      return;
    }
    _lastError = text;
    _lastErrorAt = now;
    debugPrint(text);
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  static Future<String?> _callAccounts(Map<String, Object?> body) async {
    try {
      final res = await supabase.functions.invoke('tenant-account', body: body);
      final data = res.data;
      if (res.status >= 300) {
        return plainOr(data is Map ? data['error'] : null, 'Please try again.');
      }
      return null;
    } on FunctionException catch (e) {
      final d = e.details;
      return plainOr(d is Map ? d['error'] : null, 'Please try again.');
    } catch (e) {
      return friendlyError(e);
    }
  }

  // ------------------------------------------------------------ values

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// A day for a date column ("2026-11-05").
  static String _d(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  /// A moment for a timestamptz column.
  static String _ts(DateTime d) => d.toUtc().toIso8601String();

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.tryParse(v as String);
  static DateTime? _time(Object? v) =>
      v == null ? null : DateTime.tryParse(v as String)?.toLocal();

  static DateTime get _today =>
      DateTime(appState.today.year, appState.today.month, appState.today.day);

  /// The day a label like "Nov 5, 2026", "Today" or "Yesterday" stands for.
  static DateTime _labelDay(String label) =>
      switch (label.split(',').first.trim()) {
        'Today' => _today,
        'Yesterday' => _today.subtract(const Duration(days: 1)),
        _ => parseDate(label) ?? _today,
      };

  static double _money(Object? v) => (v as num?)?.toDouble() ?? 0;

  /// "Apartment" in the app is "apartment" in the database.
  static String _typeToDb(String t) => t.toLowerCase();
  static String _typeFromDb(String t) =>
      t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);

  static String _currencyFor(String type) => type == 'Villa' ? 'AED' : 'PHP';

  static UnitRec? _unit(String name) =>
      adminState.units.where((u) => u.name == name).firstOrNull;
  static int? _unitId(String name) => _unit(name)?.id;

  static int? _tenantId(String name) {
    final t = adminState.tenants.where((t) => t.name == name).firstOrNull;
    return t?.id ?? _tenantIds[name];
  }

  static String _tenantName(Object? id) =>
      _tenantIds.entries.where((e) => e.value == id).firstOrNull?.key ?? '';

  /// The currency of a tenant's unit (former tenants included).
  static String _currencyOfTenant(String name) {
    final t = adminState.tenants.where((t) => t.name == name).firstOrNull;
    final type = t != null
        ? _unit(t.unit)?.type
        : adminState.formerTenants
              .where((f) => f.name == name)
              .firstOrNull
              ?.unitType;
    return _currencyFor(type ?? '');
  }

  /// The id of the property called [name], adding it the first time.
  static Future<int> _propertyId(String name) async {
    final known = _propertyIds[name];
    if (known != null) return known;
    final row = await supabase
        .from('properties')
        .upsert({'name': name}, onConflict: 'name')
        .select('id')
        .single();
    return _propertyIds[name] = row['id'] as int;
  }

  // ------------------------------------------------------------ files

  /// Where each file is stored ("bucket:path"), so it is uploaded once.
  static final _stored = Expando<String>();

  static ({String type, String ext}) _kind(Uint8List b) {
    bool starts(List<int> sig) =>
        b.length > sig.length &&
        [for (var i = 0; i < sig.length; i++) b[i]].join(',') == sig.join(',');
    if (starts([0x25, 0x50, 0x44, 0x46])) {
      return (type: 'application/pdf', ext: 'pdf');
    }
    if (starts([0x89, 0x50, 0x4E, 0x47])) {
      return (type: 'image/png', ext: 'png');
    }
    if (starts([0x52, 0x49, 0x46, 0x46]) &&
        b.length > 12 &&
        String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') {
      return (type: 'image/webp', ext: 'webp');
    }
    return (type: 'image/jpeg', ext: 'jpg');
  }

  static int _fileSeq = 0;

  /// Uploads [bytes] into [folder] of [bucket] (once) and returns the path.
  static Future<String> _put(
    String bucket,
    String folder,
    Uint8List bytes,
  ) async {
    final known = _stored[bytes];
    if (known != null && known.startsWith('$bucket:')) {
      return known.substring(bucket.length + 1);
    }
    final k = _kind(bytes);
    final path =
        '$folder/${DateTime.now().microsecondsSinceEpoch}-${_fileSeq++}.${k.ext}';
    await supabase.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: k.type, upsert: true),
        );
    _stored[bytes] = '$bucket:$path';
    await _keep(bucket, path, bytes);
    return path;
  }

  static Future<String?> _putMaybe(
    String bucket,
    String folder,
    Uint8List? bytes,
  ) async => bytes == null ? null : _put(bucket, folder, bytes);

  /// Deletes a stored file (missing ones are fine).
  static Future<void> _dropFile(String bucket, Object? path) async {
    if (path is! String || path.isEmpty) return;
    try {
      await supabase.storage.from(bucket).remove([path]);
    } catch (_) {}
  }

  /// Files already on this phone, kept in the app's private folder. A
  /// stored file never changes (each upload gets a new name), so once it is
  /// here it is never downloaded again. (The web app has no such folder.)
  static Directory? _cacheDir;

  static Future<File?> _cacheFile(String bucket, String path) async {
    if (kIsWeb) return null;
    try {
      _cacheDir ??= await Directory(
        '${(await getApplicationSupportDirectory()).path}/files',
      ).create(recursive: true);
      final name = '$bucket/$path'.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      return File('${_cacheDir!.path}/$name');
    } catch (_) {
      return null;
    }
  }

  static Future<void> _keep(String bucket, String path, Uint8List bytes) async {
    try {
      await (await _cacheFile(bucket, path))?.writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  /// A stored file: from this phone if it was downloaded before, otherwise
  /// from the server (then kept). Null when it is missing.
  static Future<Uint8List?> _get(String bucket, Object? path) async {
    if (path is! String || path.isEmpty) return null;
    try {
      final cached = await _cacheFile(bucket, path);
      Uint8List? bytes;
      if (cached != null && await cached.exists()) {
        try {
          bytes = await cached.readAsBytes();
        } catch (_) {}
      }
      if (bytes == null) {
        bytes = await supabase.storage.from(bucket).download(path);
        await _keep(bucket, path, bytes);
      }
      _stored[bytes] = '$bucket:$path';
      return bytes;
    } catch (_) {
      return null; // a missing file just shows as not uploaded
    }
  }

  // ------------------------------------------------------------ files on demand

  /// Files that are on the server but not downloaded yet, per object and
  /// slot ("photo", "contract"...): where they are and where they go once
  /// they arrive. Screens call [fetch] for what they are about to show, so
  /// logging in only loads the text.
  static final _waiting = Expando<Map<String, _Pending>>();
  static final Set<_Pending> _fetching = Set.identity();

  static void _later(
    Object owner,
    String slot,
    String bucket,
    Object? path,
    void Function(Uint8List bytes) assign,
  ) {
    if (path is! String || path.isEmpty) return;
    (_waiting[owner] ??= {})[slot] = _Pending(bucket, path, assign);
  }

  /// True while [owner] has a file (in [slot], or any) not downloaded yet.
  static bool waiting(Object? owner, [String? slot]) {
    if (owner == null) return false;
    final m = _waiting[owner];
    if (m == null || m.isEmpty) return false;
    return slot == null || m.containsKey(slot);
  }

  /// Where a file of [owner] is stored: uploads [bytes] when the phone has
  /// them, otherwise the path of the copy not downloaded yet (so saving a
  /// change never drops a file this phone simply hasn't opened).
  static Future<String?> _fileOr(
    Object owner,
    String slot,
    String bucket,
    String folder,
    Uint8List? bytes,
  ) async {
    if (bytes != null) return _put(bucket, folder, bytes);
    return _waiting[owner]?[slot]?.path;
  }

  /// Downloads the waiting files of [owners] (from this phone's copies when
  /// it has them), then redraws the screens.
  static Future<void> fetch(Iterable<Object?> owners) async {
    if (!backendOn) return;
    final jobs = <Future<void>>[];
    for (final o in owners) {
      if (o == null) continue;
      final key = _keyOf(o);
      if (key != null) _opened.add(key);
      final m = _waiting[o];
      if (m == null) continue;
      for (final e in m.entries.toList()) {
        final p = e.value;
        if (!_fetching.add(p)) continue;
        jobs.add(() async {
          try {
            final bytes = await _get(p.bucket, p.path);
            if (bytes != null) p.assign(bytes);
            if (m[e.key] == p) m.remove(e.key);
          } finally {
            _fetching.remove(p);
          }
        }());
      }
    }
    if (jobs.isEmpty) return;
    await Future.wait(jobs);
    adminState.refreshViews();
    chatState.touch();
  }

  /// What was opened on this phone (by record), so its files come back
  /// by themselves after a live update reloads the data.
  static final Set<String> _opened = {};

  static String? _keyOf(Object o) {
    final id = switch (o) {
      TenantRec t => t.id == null ? null : 't${t.id}',
      ChequeRec c => _cheques.idOf(c) == null ? null : 'c${_cheques.idOf(c)}',
      PaymentRec p =>
        _payments.idOf(p) == null ? null : 'p${_payments.idOf(p)}',
      DamageReport r =>
        _reports.idOf(r) == null ? null : 'r${_reports.idOf(r)}',
      ChatMessage m => _chat.idOf(m) == null ? null : 'm${_chat.idOf(m)}',
      GuestFile g =>
        _guestFiles.idOf(g) == null ? null : 'g${_guestFiles.idOf(g)}',
      _ => null,
    };
    return id;
  }

  /// After a reload: fetch again the files of what was open before.
  static void _refetchOpened() {
    if (_opened.isEmpty) return;
    final again = <Object>[
      for (final t in adminState.tenants)
        if (_opened.contains(_keyOf(t))) ...[
          t,
          ...t.pastLeases,
          if (t.nextLease != null) t.nextLease!,
        ],
      for (final c in adminState.cheques)
        if (_opened.contains(_keyOf(c))) c,
      for (final p in adminState.payments)
        if (_opened.contains(_keyOf(p))) p,
      for (final r in adminState.reports)
        if (_opened.contains(_keyOf(r))) r,
      for (final b in adminState.bookings)
        for (final g in b.files)
          if (_opened.contains(_keyOf(g))) g,
      for (final c in _allChat)
        if (_opened.contains(_keyOf(c.m))) c.m,
    ];
    if (again.isNotEmpty) unawaited(fetch(again));
  }

  /// The files of one chat thread (photos, PDFs, documents to sign).
  static Future<void> fetchChat(String tenant) =>
      fetch(chatState.messages(tenant));

  /// A tenant's documents, contract and signed lease (and earlier leases).
  static Future<void> fetchTenant(TenantRec? t) =>
      t == null ? Future.value() : fetch([t, ...t.pastLeases, t.nextLease]);

  // ------------------------------------------------------------ chat pages

  /// Messages loaded per chat at first, and each time older ones are asked for.
  static const chatPage = 50;

  /// Chats that have older messages not loaded yet.
  static final Set<String> _olderChats = {};
  static bool hasOlder(String tenant) => _olderChats.contains(tenant);

  /// Signing records by message id (to show older messages that are
  /// documents to sign).
  static final Map<String, Map<String, dynamic>> _docRows = {};

  /// A chat message from its row; photos and files are fetched on demand.
  static ChatMessage _chatFromRow(
    Map<String, dynamic> r,
    List<TenantRec> tenants,
  ) {
    final name = _tenantName(r['tenant_id']);
    final doc = _docRows[r['id']];
    final from = r['sender'] == 'admin' ? ChatSender.admin : ChatSender.tenant;
    final ChatMessage m;
    if (doc == null) {
      m = ChatMessage(
        id: r['id'] as String,
        from: from,
        time: _time(r['created_at'])!,
        text: r['file_path'] == null ? r['body'] as String? : null,
        fileName: r['file_path'] == null
            ? null
            : (r['file_name'] as String? ?? 'File.pdf'),
      );
      _later(m, 'file', 'chat-files', r['file_path'], (b) => m.fileBytes = b);
    } else {
      m =
          ChatMessage(
              id: r['id'] as String,
              from: from,
              time: _time(r['created_at'])!,
              docTitle: doc['title'] as String,
              fileName: doc['original_name'] as String?,
            )
            ..sign = switch (doc['status']) {
              'signed' => SignStatus.signed,
              'accepted' => SignStatus.completed,
              _ => SignStatus.awaiting,
            }
            ..signedAt = _time(doc['signed_at'])
            ..revision = doc['revision'] as int? ?? 0
            ..note = doc['return_note'] as String?;
      _originalHash[m] = doc['original_hash'] as String?;
      _later(
        m,
        'original',
        'chat-files',
        doc['original_path'],
        (b) => m.fileBytes = b,
      );
      _later(
        m,
        'signature',
        'chat-files',
        doc['signature_path'],
        (b) => m.signature = b,
      );
      _later(
        m,
        'signed',
        'chat-files',
        doc['signed_path'],
        (b) => m.signedPdf = b,
      );
      final signedAt = _time(doc['signed_at']);
      if (signedAt != null && doc['signed_hash'] != null) {
        m.audit = SignatureAudit(
          signer: name,
          account:
              tenants.where((t) => t.name == name).firstOrNull?.username ?? '',
          signedAt: signedAt,
          device: doc['signed_device'] as String? ?? '',
          originalHash: doc['original_hash'] as String? ?? '',
          signedHash: doc['signed_hash'] as String,
        );
      }
      _signing.setIdTo(m, doc['id']);
    }
    _later(m, 'image', 'chat-files', r['image_path'], (b) => m.image = b);
    _chat.setIdTo(m, r['id']);
    return m;
  }

  /// The fingerprint of a document to sign as sent (kept while its file is
  /// not downloaded).
  static final _originalHash = Expando<String>();

  static final Set<String> _loadingOlder = {};

  /// Loads the next [chatPage] older messages of [tenant]'s chat.
  static Future<void> loadOlderChat(String tenant) async {
    if (!backendOn ||
        !_olderChats.contains(tenant) ||
        !_loadingOlder.add(tenant)) {
      return;
    }
    try {
      final tid = _tenantId(tenant);
      final list = chatState.messages(tenant);
      if (tid == null || list.isEmpty) return;
      final rows = await supabase
          .from('chat_messages')
          .select()
          .eq('tenant_id', tid)
          .lt('created_at', _ts(list.first.time))
          .order('created_at', ascending: false)
          .limit(chatPage);
      final ids = [for (final r in rows) r['id'] as String];
      if (ids.isNotEmpty) {
        for (final d
            in await supabase
                .from('documents_to_sign')
                .select()
                .inFilter('message_id', ids)) {
          _docRows[d['message_id'] as String] = d;
        }
      }
      final older = [
        for (final r in rows.reversed) _chatFromRow(r, adminState.tenants),
      ];
      for (final m in older) {
        _chat._known.add(m);
        if (m.isSignRequest) _signing._known.add(m);
      }
      if (rows.length < chatPage) _olderChats.remove(tenant);
      chatState.prependOlder(tenant, older);
      // Their photos come in a moment later.
      unawaited(fetch(older));
    } catch (e) {
      debugPrint('Older messages: $e');
    } finally {
      _loadingOlder.remove(tenant);
    }
  }

  // ------------------------------------------------------------ mappings

  static const _months = [
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

  /// The month a rent charge is for, from its title ("October 2026 rent").
  static DateTime? _rentMonth(String title) {
    final m = RegExp(r'^(\w+) (\d{4}) rent$').firstMatch(title);
    if (m == null) return null;
    final i = _months.indexOf(m.group(1)!);
    return i < 0 ? null : DateTime(int.parse(m.group(2)!), i + 1);
  }

  static String _chargeKind(String title) {
    final t = title.toLowerCase();
    if (_rentMonth(title) != null) return 'rent';
    if (t.contains('fee')) return 'fee';
    if (t.contains('repair') || t.contains('damage')) return 'repair';
    if (t.contains('water') ||
        t.contains('electric') ||
        t.contains('utilit') ||
        t.contains('internet')) {
      return 'utility';
    }
    return 'other';
  }

  static String _requestKind(String kind) {
    final k = kind.toLowerCase();
    if (k.contains('renew')) return 'renewal';
    if (k.contains('move')) return 'move_out';
    return 'other';
  }

  static Future<Map<String, Object?>> _termToJson(
    LeaseTerm l,
    int? tenantId,
  ) async => {
    'start': l.start,
    'end': l.end,
    'rent': l.rent,
    'cheques': l.chequesPerYear,
    'contract_name': l.contractName,
    'contract_path': tenantId == null
        ? null
        : await _fileOr(l, 'contract', 'contracts', '$tenantId', l.contractPdf),
  };

  static Future<LeaseTerm> _termFromJson(Map<String, dynamic> j) async {
    final term = LeaseTerm(
      start: j['start'] as String? ?? '',
      end: j['end'] as String? ?? '',
      rent: _money(j['rent']),
      chequesPerYear: j['cheques'] as int? ?? 4,
      contractName: j['contract_name'] as String?,
    );
    _later(
      term,
      'contract',
      'contracts',
      j['contract_path'],
      (b) => term.contractPdf = b,
    );
    return term;
  }

  // ------------------------------------------------------------ tables

  static late _Spec<UnitRec> _units;
  static late _Spec<UnitTemplate> _templates;
  static late _Spec<TenantRec> _tenants;
  static late _Spec<ChargeRec> _charges;
  static late _Spec<PaymentRec> _payments;
  static late _Spec<ChequeRec> _cheques;
  static late _Spec<PayAccount> _payAccounts;
  static late _Spec<TaxRate> _taxes;
  static late _Spec<MonthlyExpense> _expenses;
  static late _Spec<ExpenseTemplate> _expenseTemplates;
  static late _Spec<CostEntry> _costs;
  static late _Spec<Booking> _bookings;
  static late _Spec<GuestFile> _guestFiles;
  static late _Spec<DamageReport> _reports;
  static late _Spec<ReportUpdate> _reportUpdates;
  static late _Spec<Uint8List> _reportPhotos;
  static late _Spec<WorkItem> _work;
  static late _Spec<ComplaintRec> _complaints;
  static late _Spec<LeaseRequest> _requests;
  static late _Spec<AdminNotice> _notices;
  static late _Spec<HouseRule> _rules;
  static late _Spec<AdminMessage> _adminMessages;
  static late _Spec<Message> _myMessages;
  static late _Spec<ChatMessage> _chat;
  static late _Spec<ChatMessage> _signing;
  static late _Spec<LogEntry> _log;
  static late _Logins _logins;

  // Which unit / booking / report / thread a child row belongs to (set
  // while listing them).
  static final _expenseUnit = Expando<String>();
  static final _costUnit = Expando<String>();
  static final _fileBooking = Expando<Booking>();
  static final _updateReport = Expando<DamageReport>();
  static final _photoReport = Expando<DamageReport>();
  static final _chatTenant = Expando<String>();

  static Iterable<({String tenant, ChatMessage m})> get _allChat sync* {
    for (final e in chatState.threads.entries) {
      for (final m in e.value) {
        _chatTenant[m] = e.key;
        yield (tenant: e.key, m: m);
      }
    }
  }

  static List<_Step> _buildSteps() {
    _units = _Spec(
      'units',
      'a unit',
      files: {'photo_path': 'public-assets'},
      items: () => adminState.units,
      getId: (u) => u.id,
      setId: (u, id) => u.id = id as int?,
      // A deleted unit is archived, never erased: its payments, stays,
      // reports and costs keep pointing to it. Only a unit the admin
      // deleted on purpose is archived.
      keepFilesOnRemove: true,
      onRemoved: (u, id) async {
        if (!adminState.archivedUnits.contains(u)) return;
        await supabase
            .from('units')
            .update({'archived_at': _ts(u.archivedAt ?? DateTime.now())})
            .eq('id', id);
      },
      row: (u) async => {
        'property_id': await _propertyId(u.property),
        'name': u.name,
        'type': _typeToDb(u.type),
        'bedrooms': u.bedrooms,
        'rate': u.rate,
        'rate_unit': u.rateUnit,
        'currency': _currencyFor(u.type),
        'deposit_amount': u.depositAmount,
        'photo_path': u.photo == null
            ? u.photoPath
            : await _put('public-assets', 'units', u.photo!),
      },
    );

    _templates = _Spec(
      'unit_templates',
      'a unit template',
      files: {'photo_path': 'public-assets'},
      items: () => adminState.unitTemplates,
      row: (t) async => {
        'name': t.name,
        'property_id': t.property.trim().isEmpty
            ? null
            : await _propertyId(t.property.trim()),
        'type': _typeToDb(t.type),
        'bedrooms': t.bedrooms,
        'rate': t.rate,
        'rate_unit': t.rateUnit,
        'photo_path': t.photo == null
            ? t.photoPath
            : await _put('public-assets', 'templates', t.photo!),
      },
    );

    _tenants = _Spec(
      'tenants',
      'a tenant',
      items: () => adminState.tenants,
      getId: (t) => t.id,
      setId: (t, id) {
        t.id = id as int?;
        if (id != null) _tenantIds[t.name] = id;
      },
      row: (t) async => {
        'full_name': t.name,
        'username': t.username.trim().isEmpty ? null : t.username.trim(),
        'phone': t.phone,
        'email': t.email,
        'emergency_contact': t.emergencyContact,
        'occupants': t.occupants < 1 ? 1 : t.occupants,
        'status': 'active',
        'past_leases': [
          for (final l in t.pastLeases) await _termToJson(l, t.id),
        ],
        'next_lease': t.nextLease == null
            ? null
            : await _termToJson(t.nextLease!, t.id),
        'deposit_note': t.depositNote,
        'end_reminded': t.endReminded,
        'balance': t.balance,
        // The unit and terms they are given, kept even before lease dates
        // are set (the lease row only exists once it has dates).
        'unit_id': _unitId(t.unit),
        'rent': t.rent < 0 ? 0 : t.rent,
        'deposit': t.deposit < 0 ? 0 : t.deposit,
        'due_day': t.dueDay.clamp(1, 31),
        'cheques_per_year': t.chequesPerYear.clamp(1, 4),
      },
      // A tenant can change only their own contact details.
      tenantRow: (t) async => {
        'phone': t.phone,
        'email': t.email,
        'emergency_contact': t.emergencyContact,
        'occupants': t.occupants < 1 ? 1 : t.occupants,
      },
      onRemoved: _tenantRemoved,
    );

    _logins = _Logins();

    final leases = _Spec<TenantRec>(
      'leases',
      'a lease',
      items: () => adminState.tenants,
      getId: (t) => t.leaseId,
      setId: (t, id) => t.leaseId = id as int?,
      row: _leaseRow,
      // Ended with the tenant (see _tenantRemoved).
      onRemoved: (_, _) async {},
    );

    final requests = _requests = _Spec(
      'lease_requests',
      'a request',
      items: () => adminState.requests,
      tenantInsert: true,
      row: (r) async {
        final tid = _tenantId(r.tenant);
        if (tid == null) return null;
        return {
          'tenant_id': tid,
          'kind': _requestKind(r.kind),
          'details': r.kind,
          'note': r.note,
          'status': r.status.name,
          'created_at': _ts(_labelDay(r.date)),
        };
      },
    );

    _charges = _Spec(
      'charges',
      'a charge',
      items: () => adminState.charges,
      row: (c) async {
        final tid = _tenantId(c.tenant);
        if (tid == null || c.amount <= 0) return null;
        final t = adminState.tenants
            .where((t) => t.name == c.tenant)
            .firstOrNull;
        final month = _rentMonth(c.title);
        final paid = c.paid ? c.amount : c.paidAmount.clamp(0, c.amount);
        return {
          'tenant_id': tid,
          'lease_id': t?.leaseId,
          'title': c.title,
          'kind': _chargeKind(c.title),
          'amount': c.amount,
          'paid_amount': paid,
          'currency': _currencyOfTenant(c.tenant),
          'due_date': _d(_labelDay(c.due)),
          'period_month': month == null ? null : _d(month),
          'status': c.paid ? 'paid' : 'open',
        };
      },
      // Rent for a month already added on another phone: use that row.
      insert: (c, row) async {
        try {
          return (await supabase
              .from('charges')
              .insert(row)
              .select('id')
              .single())['id'];
        } on PostgrestException catch (e) {
          if (e.code != '23505' || row['period_month'] == null) rethrow;
          final existing = await supabase
              .from('charges')
              .select('id')
              .eq('lease_id', row['lease_id'] as Object)
              .eq('period_month', row['period_month'] as Object)
              .eq('kind', 'rent')
              .neq('status', 'cancelled')
              .single();
          await supabase
              .from('charges')
              .update(row)
              .eq('id', existing['id'] as Object);
          return existing['id'];
        }
      },
    );

    _payments = _Spec(
      'payments',
      'a payment',
      files: {'proof_path': 'payment-proofs'},
      items: () => adminState.payments,
      tenantInsert: true,
      row: (p) async {
        final tid = _tenantId(p.tenant);
        if (tid == null || p.amount <= 0) return null;
        return {
          'tenant_id': tid,
          'title': p.title,
          'amount': p.amount,
          'currency': _currencyOfTenant(p.tenant),
          'method': p.method,
          'reference': p.reference,
          'paid_on': _d(_labelDay(p.date)),
          'source': p.recordedByAdmin
              ? (p.method.startsWith('Cheque') ? 'cheque' : 'admin_recorded')
              : 'tenant_proof',
          'status': p.status.name,
          'reject_reason': p.reason,
          'months': p.months < 1 ? null : p.months,
          'covers_from': p.coversFrom == null ? null : _d(p.coversFrom!),
          'covers_to': p.coversTo == null ? null : _d(p.coversTo!),
          // The charges this proof pays (beside rent months).
          'charge_ids': [
            for (final c in p.covers)
              if (_charges.idOf(c) != null) _charges.idOf(c),
          ],
          // The receipt photo (left as it is when this phone does not have it).
          if (p.proof != null)
            'proof_path': await _put('payment-proofs', '$tid', p.proof!),
        };
      },
    );

    Future<Map<String, Object?>?> chequePhoto(ChequeRec c) async {
      final tid = _tenantId(c.tenant);
      if (tid == null) return null;
      return {
        'photo_path': await _fileOr(
          c,
          'photo',
          'cheque-photos',
          '$tid',
          c.photo,
        ),
        'photo_uploaded_at': c.uploadedOn == null
            ? null
            : _ts(_labelDay(c.uploadedOn!)),
        'photo_checked': c.photoChecked,
      };
    }

    _cheques = _Spec(
      'cheques',
      'a cheque',
      files: {'photo_path': 'cheque-photos'},
      items: () => adminState.cheques,
      row: (c) async {
        final t = adminState.tenants
            .where((t) => t.name == c.tenant)
            .firstOrNull;
        // A cheque belongs to the tenant (and their lease, once it has dates).
        final tid = _tenantId(c.tenant);
        if (tid == null || c.amount <= 0) return null;
        final leaseId = t?.leaseId;
        final replaced = c.replaces == null
            ? null
            : adminState.cheques.where((x) => x.id == c.replaces).firstOrNull;
        return {
          'tenant_id': tid,
          'lease_id': leaseId,
          'kind': c.kind == ChequeKind.deposit ? 'deposit' : 'post_dated',
          'amount': c.amount,
          'cheque_date': _d(c.date),
          'months': c.months,
          'cheque_no': c.chequeNo,
          'bank': c.bank,
          'status': c.status.name,
          'replaces_id': replaced == null ? null : _cheques.idOf(replaced),
          'reminded': c.reminded,
          'returned_on': c.returnedOn == null
              ? null
              : _d(_labelDay(c.returnedOn!)),
          ...?await chequePhoto(c),
        };
      },
      // A tenant only adds the photo.
      tenantRow: chequePhoto,
    );

    _payAccounts = _Spec(
      'pay_accounts',
      'a payment account',
      files: {'qr_path': 'public-assets'},
      items: () => appState.payAccounts,
      row: (a) async => {
        'type': a.type,
        'name': a.name,
        'account_name': a.accountName,
        'number': a.number,
        'qr_path': await _putMaybe('public-assets', 'qr', a.qr),
        'sort_order': appState.payAccounts.indexOf(a),
      },
    );

    _taxes = _Spec(
      'taxes',
      'a tax',
      items: () => adminState.taxes,
      row: (t) async => {
        'name': t.name,
        'percent': t.percent,
        'fixed_monthly': t.fixedMonthly,
        'on_villas': t.onVillas,
      },
    );

    _expenses = _Spec(
      'monthly_expenses',
      'a monthly expense',
      items: () sync* {
        for (final e in adminState.monthlyExpenses.entries) {
          for (final x in e.value) {
            _expenseUnit[x] = e.key;
            yield x;
          }
        }
      },
      row: (e) async {
        final unit = _unit(_expenseUnit[e] ?? '');
        if (unit?.id == null || e.amount <= 0) return null;
        return {
          'unit_id': unit!.id,
          'name': e.name,
          'amount': e.amount,
          'currency': _currencyFor(unit.type),
          'since_month': _d(DateTime(e.since.year, e.since.month)),
          'until_month': e.until == null
              ? null
              : _d(DateTime(e.until!.year, e.until!.month)),
        };
      },
    );

    _expenseTemplates = _Spec(
      'expense_templates',
      'an expense template',
      items: () => adminState.expenseTemplates,
      row: (t) async => t.amount <= 0
          ? null
          : {
              'name': t.name,
              'amount': t.amount,
              'unit_type': _typeToDb(t.unitType),
            },
    );

    _costs = _Spec(
      'unit_costs',
      'a cost',
      items: () sync* {
        for (final e in adminState.unitCosts.entries) {
          for (final x in e.value) {
            _costUnit[x] = e.key;
            yield x;
          }
        }
      },
      row: (c) async {
        final id = _unitId(_costUnit[c] ?? '');
        if (id == null || c.amount <= 0) return null;
        return {
          'unit_id': id,
          'title': c.title,
          'amount': c.amount,
          'spent_on': _d(c.date),
        };
      },
    );

    final costTypes = _Names('cost_types', () => adminState.costTypes);
    final chargeTypes = _Names('charge_types', () => adminState.chargeTypes);

    _bookings = _Spec(
      'bookings',
      'a condo stay',
      items: () => adminState.bookings,
      row: (b) async {
        final id = _unitId(b.unit);
        if (id == null || !b.checkOut.isAfter(b.checkIn)) return null;
        return {
          'unit_id': id,
          'guest_name': b.guest,
          'phone': b.phone,
          'guests': b.guests < 1 ? 1 : b.guests,
          'check_in': _ts(b.checkIn),
          'check_out': _ts(b.checkOut),
          'amount': b.amount,
          'deposit': b.deposit,
          'deposit_returned_on': b.depositReturnedOn == null
              ? null
              : _d(b.depositReturnedOn!),
          'status': 'booked',
        };
      },
      onRemoved: (b, id) async {
        for (final f
            in await supabase
                .from('booking_files')
                .select('file_path')
                .eq('booking_id', id)) {
          await Sync._dropFile('guest-files', f['file_path']);
        }
        await supabase.from('booking_deductions').delete().eq('booking_id', id);
        await supabase.from('booking_files').delete().eq('booking_id', id);
        await supabase.from('bookings').delete().eq('id', id);
      },
    );

    final deductions = _Deductions();

    _guestFiles = _Spec(
      'booking_files',
      'a guest file',
      files: {'file_path': 'guest-files'},
      items: () sync* {
        for (final b in adminState.bookings) {
          for (final f in b.files) {
            _fileBooking[f] = b;
            yield f;
          }
        }
      },
      row: (f) async {
        final b = _fileBooking[f];
        final bid = b == null ? null : _bookings.idOf(b);
        if (bid == null) return null;
        return {
          'booking_id': bid,
          'label': f.label,
          'file_name': f.fileName,
          'file_path': await _fileOr(
            f,
            'file',
            'guest-files',
            'bookings/$bid',
            f.bytes,
          ),
          'added_at': _ts(f.added),
        };
      },
    );

    _reports = _Spec(
      'reports',
      'a report',
      items: () => adminState.reports,
      tenantInsert: true,
      row: (r) async {
        final unitId = _unitId(r.unit);
        if (unitId == null) return null;
        final tid = _tenantId(r.tenant);
        return {
          'code': r.id,
          'tenant_id': tid,
          'reporter_name': tid == null ? r.tenant : null,
          'unit_id': unitId,
          'type': r.type.name,
          'issue': r.issue,
          'description': r.description,
          'status': switch (r.status) {
            ReportStatus.pending => 'pending',
            ReportStatus.underReview => 'under_review',
            ReportStatus.approved => 'approved',
          },
          'damage_kind': r.kind?.name,
          'tenant_amount': r.deduction,
          'attachments': r.attachments,
          'admin_note': r.note,
          'created_at': _ts(_labelDay(r.date)),
        };
      },
      onRemoved: (r, id) async {
        for (final p
            in await supabase
                .from('report_photos')
                .select('file_path')
                .eq('report_id', id)) {
          await Sync._dropFile('report-photos', p['file_path']);
        }
        await supabase.from('report_updates').delete().eq('report_id', id);
        await supabase.from('report_photos').delete().eq('report_id', id);
        await supabase
            .from('work_items')
            .update({'report_id': null})
            .eq('report_id', id);
        await supabase.from('reports').delete().eq('id', id);
      },
    );

    _reportUpdates = _Spec(
      'report_updates',
      'a report update',
      items: () sync* {
        for (final r in adminState.reports) {
          for (final u in r.updates) {
            _updateReport[u] = r;
            yield u;
          }
        }
      },
      row: (u) async {
        final r = _updateReport[u];
        final rid = r == null ? null : _reports.idOf(r);
        if (rid == null) return null;
        return {
          'report_id': rid,
          'body': u.text,
          'posted_at': _ts(_labelDay(u.date)),
        };
      },
    );

    _reportPhotos = _Spec(
      'report_photos',
      'a report photo',
      files: {'file_path': 'report-photos'},
      tenantInsert: true,
      items: () sync* {
        for (final r in adminState.reports) {
          for (final p in r.photoFiles) {
            _photoReport[p] = r;
            yield p;
          }
        }
      },
      row: (p) async {
        final r = _photoReport[p];
        final rid = r == null ? null : _reports.idOf(r);
        if (rid == null) return null;
        final tid = _tenantId(r!.tenant);
        return {
          'report_id': rid,
          'file_path': await _put(
            'report-photos',
            tid == null ? 'management' : '$tid',
            p,
          ),
        };
      },
    );

    _work = _Spec(
      'work_items',
      'scheduled work',
      items: () => adminState.workItems,
      row: (w) async {
        final unitId = _unitId(w.where);
        final propertyId = unitId != null
            ? null
            : adminState.units.any((u) => u.property == w.where)
            ? await _propertyId(w.where)
            : null;
        if (unitId == null && propertyId == null) return null;
        final charge = w.chargeRec;
        return {
          'unit_id': unitId,
          'property_id': propertyId,
          'kind': switch (w.kind) {
            AdminEventKind.repair => 'repair',
            AdminEventKind.inspection => 'inspection',
            AdminEventKind.modification => 'modification',
            _ => 'maintenance',
          },
          'title': w.title,
          'start_date': _d(w.date),
          'end_date': _d(w.endDate.isBefore(w.date) ? w.date : w.endDate),
          'time_label': w.time,
          'cost': w.cost < 0 ? 0 : w.cost,
          'tenant_pays': w.tenantPays,
          'charge_id': charge == null ? null : _charges.idOf(charge),
          'done': w.done,
          'notes': w.notes,
        };
      },
    );

    _complaints = _Spec(
      'complaints',
      'a complaint',
      items: () => adminState.complaints,
      tenantInsert: true,
      row: (c) async {
        final tid = _tenantId(c.tenant);
        if (tid == null) return null;
        return {
          'tenant_id': tid,
          'category': c.category,
          'body': c.body,
          'status': switch (c.status) {
            ComplaintStatus.open => 'open',
            ComplaintStatus.inProgress => 'in_progress',
            ComplaintStatus.resolved => 'resolved',
          },
          'response': c.response,
          'created_at': _ts(_labelDay(c.date)),
        };
      },
    );

    _notices = _Spec(
      'notices',
      'a notice',
      items: () => adminState.notices,
      row: (n) async => {
        'kind': n.kind.name,
        'title': n.title,
        'body': n.body,
        'automatic': n.automatic,
        'unit_types': n.unitTypes,
        'to_tenant_id': n.to == null ? null : _tenantId(n.to!),
      },
      onRemoved: (n, id) async {
        await supabase.from('notice_recipients').delete().eq('notice_id', id);
        await supabase.from('notices').delete().eq('id', id);
      },
    );

    final recipients = _Recipients();

    _rules = _Spec(
      'house_rules',
      'a house rule',
      items: () => appState.rules,
      row: (r) async => {
        'title': r.title,
        'body': r.body,
        'sort_order': appState.rules.indexOf(r),
      },
    );

    _adminMessages = _Spec(
      'tenant_messages',
      'a message',
      items: () => adminState.messages,
      row: (m) async {
        final tid = _tenantId(m.tenant);
        if (tid == null) return null;
        return {
          'tenant_id': tid,
          'category': m.category,
          'body': m.body,
          'reply': m.reply,
        };
      },
    );

    _myMessages = _Spec(
      'tenant_messages',
      'your message',
      items: () => appState.messages,
      tenantOnly: true,
      tenantInsert: true,
      insertOnly: true,
      row: (m) async => _myTenantId == null
          ? null
          : {'tenant_id': _myTenantId, 'category': m.category, 'body': m.body},
    );

    _chat = _Spec(
      'chat_messages',
      'a chat message',
      items: () => [for (final c in _allChat) c.m],
      tenantInsert: true,
      insertOnly: true,
      onInsert: (m, ok) =>
          chatState.setDelivery(m, ok ? Delivery.sent : Delivery.failed),
      row: (m) async {
        // A failed message waits until the user taps to retry.
        if (m.delivery == Delivery.failed) return null;
        final tid = _tenantId(_chatTenant[m] ?? '');
        if (tid == null) return null;
        // On a tenant's phone only their own messages are new.
        if (_tenantMode && m.from != ChatSender.tenant) return null;
        final image = await _fileOr(m, 'image', 'chat-files', '$tid', m.image);
        // A PDF sent in the chat (not one to sign, which is kept with the
        // signing record).
        final file = m.isFile
            ? await _fileOr(m, 'file', 'chat-files', '$tid', m.fileBytes)
            : null;
        final body =
            m.text ??
            m.docTitle ??
            (m.isFile ? m.fileName ?? 'File.pdf' : null);
        if (body == null && image == null) return null;
        return {
          'tenant_id': tid,
          'sender': m.from.name,
          'body': body,
          'image_path': image,
          'file_path': file,
          'file_name': file == null ? null : m.fileName,
          // The server's clock sets the time, so messages from two phones
          // (whose clocks may differ) stay in the order they were sent.
        };
      },
    );

    Future<Map<String, Object?>?> signed(ChatMessage m) async {
      final tid = _tenantId(_chatTenant[m] ?? '');
      if (tid == null) return null;
      final a = m.audit;
      return {
        'status': switch (m.sign) {
          SignStatus.signed => 'signed',
          SignStatus.completed => 'accepted',
          _ => 'awaiting',
        },
        // Waiting to be signed (again): no signature.
        'signature_path': m.sign == SignStatus.awaiting
            ? null
            : await _fileOr(m, 'signature', 'chat-files', '$tid', m.signature),
        'signed_path': m.sign == SignStatus.awaiting
            ? null
            : await _fileOr(m, 'signed', 'chat-files', '$tid', m.signedPdf),
        'signed_device': a?.device,
        'signed_hash': a?.signedHash,
        'signed_at': (a?.signedAt ?? m.signedAt) == null
            ? null
            : _ts(a?.signedAt ?? m.signedAt!),
      };
    }

    _signing = _Spec(
      'documents_to_sign',
      'a document to sign',
      items: () => [
        for (final c in _allChat)
          if (c.m.isSignRequest) c.m,
      ],
      tenantInsert: true,
      row: (m) async {
        final tid = _tenantId(_chatTenant[m] ?? '');
        final messageId = _chat.idOf(m);
        if (tid == null || messageId == null) return null;
        final file = m.fileBytes;
        return {
          'tenant_id': tid,
          'message_id': messageId,
          'title': m.docTitle,
          'original_name': m.fileName,
          'original_path': await _fileOr(
            m,
            'original',
            'chat-files',
            '$tid',
            file,
          ),
          'original_hash':
              m.audit?.originalHash ??
              (file == null ? _originalHash[m] : fingerprint(file)),
          'revision': m.revision,
          'return_note': m.note,
          'accepted_at': m.sign == SignStatus.completed
              ? _ts(m.signedAt ?? DateTime.now())
              : null,
          ...?await signed(m),
        };
      },
      // A tenant signs: only the signature, the signed copy and its proof.
      tenantRow: signed,
    );

    _log = _Spec(
      'activity_log',
      'the activity log',
      items: () => adminState.activityLog,
      insertOnly: true,
      row: (e) async => {
        'actor': supabase.auth.currentUser?.id,
        'action': e.action,
        'detail': e.detail,
        'created_at': _ts(e.at),
      },
    );

    return [
      _units,
      _templates,
      _tenants,
      _logins,
      leases,
      _TenantDocs(),
      requests,
      _charges,
      _payments,
      _cheques,
      _payAccounts,
      _taxes,
      _expenses,
      _expenseTemplates,
      _costs,
      costTypes,
      chargeTypes,
      _bookings,
      deductions,
      _guestFiles,
      _reports,
      _reportUpdates,
      _reportPhotos,
      _work,
      _complaints,
      _notices,
      recipients,
      _rules,
      _adminMessages,
      _myMessages,
      _chat,
      _signing,
      _ChatReads(),
      _log,
      _Settings(),
      _AlertPrefs(),
    ];
  }

  /// The lease row for a tenant's current lease. With no unit (or no
  /// usable dates) any lease they had is ended instead.
  static Future<Map<String, Object?>?> _leaseRow(TenantRec t) async {
    final tid = t.id;
    if (tid == null) return null;
    final unit = _unit(t.unit);
    final start = parseDate(t.leaseStart);
    final end = parseDate(t.leaseEnd);
    if (unit?.id == null ||
        start == null ||
        end == null ||
        !end.isAfter(start)) {
      final leaseId = t.leaseId;
      if (leaseId != null && !_tenantMode) {
        await supabase
            .from('leases')
            .update({'status': 'ended'})
            .eq('id', leaseId);
        t.leaseId = null;
      }
      return null;
    }
    return {
      'tenant_id': tid,
      'unit_id': unit!.id,
      'start_date': _d(start),
      'end_date': _d(end),
      'rent': t.rent,
      'currency': _currencyFor(unit.type),
      'due_day': t.dueDay,
      'deposit': t.deposit,
      'cheques_per_year': unit.type == 'Villa' ? t.chequesPerYear : null,
      'paid_from': t.paidFrom == null ? null : _d(t.paidFrom!),
      'paid_until': t.paidUntil == null ? null : _d(t.paidUntil!),
      'status': start.isAfter(_today) ? 'scheduled' : 'active',
      'contract_name': t.contractName,
      'contract_path': !t.hasContract
          ? null
          : await _fileOr(t, 'contract', 'contracts', '$tid', t.contractPdf),
      'contract_assigned_at': t.contractAssignedAt == null
          ? null
          : _ts(t.contractAssignedAt!),
      'signed_lease_path': !t.hasSignedLease
          ? null
          : await _fileOr(t, 'signedLease', 'contracts', '$tid', t.signedLease),
    };
  }

  /// A tenant left the list: they moved out (kept on record) or the account
  /// was deleted. Either way their login is removed.
  static Future<void> _tenantRemoved(TenantRec t, Object id) async {
    final movedOut = adminState.formerTenants.any((f) => f.name == t.name);
    final deleted = adminState.deletedAccounts.contains(t);
    // Safety: only a tenant the admin moved out or deleted on purpose is
    // touched on the server. Anything else (a list that changed for another
    // reason) leaves every record as it is.
    if (!movedOut && !deleted) {
      debugPrint(
        'Sync: ${t.name} left the list without a move-out or delete; kept.',
      );
      return;
    }
    adminState.deletedAccounts.remove(t);
    final problem = await _callAccounts({'action': 'delete', 'tenant_id': id});
    if (problem != null) debugPrint('Login removal: $problem');
    try {
      await supabase.rpc('forget_tenant_password', params: {'p_tenant_id': id});
    } catch (_) {}
    final former = adminState.formerTenants
        .where((f) => f.name == t.name)
        .firstOrNull;
    final leaseId = t.leaseId;
    if (former != null) {
      if (leaseId != null) {
        await supabase.from('move_outs').upsert({
          'lease_id': leaseId,
          'moved_out_on': _d(former.movedOut),
          'deposit_note': former.depositNote,
          'inspection': former.inspection,
          'owed_at_move_out': former.owedAtMoveOut,
        }, onConflict: 'lease_id');
        await supabase
            .from('leases')
            .update({'status': 'ended'})
            .eq('id', leaseId);
      }
      await supabase
          .from('tenants')
          .update({
            'status': 'moved_out',
            'profile_id': null,
            'deposit_note': former.depositNote,
            'past_leases': [
              for (final l in former.pastLeases)
                await _termToJson(l, id as int),
            ],
          })
          .eq('id', id);
      return;
    }
    // Deleted (added by mistake): remove everything that points to them.
    try {
      final leaseIds = [
        for (final r
            in await supabase.from('leases').select('id').eq('tenant_id', id))
          r['id'] as int,
      ];
      final paymentIds = [
        for (final r
            in await supabase.from('payments').select('id').eq('tenant_id', id))
          r['id'] as int,
      ];
      final chargeIds = [
        for (final r
            in await supabase.from('charges').select('id').eq('tenant_id', id))
          r['id'] as int,
      ];
      await supabase.from('documents_to_sign').delete().eq('tenant_id', id);
      await supabase.from('chat_messages').delete().eq('tenant_id', id);
      await supabase.from('chat_reads').delete().eq('tenant_id', id);
      await supabase.from('notice_recipients').delete().eq('tenant_id', id);
      await supabase
          .from('notices')
          .update({'to_tenant_id': null})
          .eq('to_tenant_id', id);
      await supabase.from('tenant_messages').delete().eq('tenant_id', id);
      await supabase.from('tenant_documents').delete().eq('tenant_id', id);
      await supabase.from('lease_requests').delete().eq('tenant_id', id);
      await supabase.from('complaints').delete().eq('tenant_id', id);
      if (paymentIds.isNotEmpty) {
        await supabase
            .from('payment_allocations')
            .delete()
            .inFilter('payment_id', paymentIds);
      }
      await supabase.from('payments').delete().eq('tenant_id', id);
      if (chargeIds.isNotEmpty) {
        await supabase
            .from('payment_allocations')
            .delete()
            .inFilter('charge_id', chargeIds);
        await supabase
            .from('work_items')
            .update({'charge_id': null})
            .inFilter('charge_id', chargeIds);
      }
      await supabase.from('charges').delete().eq('tenant_id', id);
      await supabase
          .from('reports')
          .update({'tenant_id': null, 'reporter_name': t.name})
          .eq('tenant_id', id);
      await supabase
          .from('cheques')
          .update({'replaces_id': null})
          .eq('tenant_id', id);
      await supabase.from('cheques').delete().eq('tenant_id', id);
      if (leaseIds.isNotEmpty) {
        await supabase
            .from('cheques')
            .update({'replaces_id': null})
            .inFilter('lease_id', leaseIds);
        await supabase.from('cheques').delete().inFilter('lease_id', leaseIds);
        await supabase
            .from('move_outs')
            .delete()
            .inFilter('lease_id', leaseIds);
        await supabase
            .from('leases')
            .update({'renewed_from': null})
            .inFilter('id', leaseIds);
        await supabase.from('leases').delete().inFilter('id', leaseIds);
      }
      await supabase.from('tenants').delete().eq('id', id);
      _tenantIds.remove(t.name);
    } on PostgrestException {
      // Something still points to them: keep the row, closed.
      await supabase
          .from('tenants')
          .update({'status': 'moved_out', 'profile_id': null})
          .eq('id', id);
    }
  }

  // ------------------------------------------------------------ load

  static List<Map<String, dynamic>> _rows(Object? v) => [
    for (final r in (v as List? ?? const [])) r as Map<String, dynamic>,
  ];

  /// Unit and template photos kept in memory, so a reload shows them at once.
  static final _photos = <Object?, Uint8List>{};

  /// Downloads the unit and template photos not yet in memory, after the
  /// screens are already showing, then shows them.
  static Future<void> _fillPhotos(
    List<UnitRec> units,
    List<UnitTemplate> templates,
  ) async {
    final missing = [
      for (final u in units)
        if (u.photo == null && u.photoPath != null)
          (u.photoPath!, (Uint8List b) => u.photo = b),
      for (final t in templates)
        if (t.photo == null && t.photoPath != null)
          (t.photoPath!, (Uint8List b) => t.photo = b),
    ];
    if (missing.isEmpty) return;
    await Future.wait([
      for (final (path, set) in missing)
        _get('public-assets', path).then((b) {
          if (b == null) return;
          _photos[path] = b;
          set(b);
        }),
    ]);
    adminState.refreshViews();
  }

  static Future<void> _loadEverything() async {
    final db = supabase;

    // Every request goes out at once (not one after another); each list
    // is then read in the same order as before.
    Future<T> go<T>(Future<T> f) {
      final r = f.then((v) => v);
      r.ignore(); // an error is still thrown where it is awaited
      return r;
    }

    final qProperties = go(db.from('properties').select('id, name'));
    final qUnits = go(
      db
          .from('units')
          .select('*, properties(name)')
          .order('id', ascending: true),
    );
    final qUnitTemplates = go(
      db
          .from('unit_templates')
          .select(
            'id, name, type, bedrooms, rate, rate_unit, photo_path, properties(name)',
          )
          .order('id', ascending: false),
    );
    final qTenants = go(
      db
          .from('tenants')
          .select('*, leases(*, move_outs(*)), tenant_documents(*)')
          .order('id', ascending: true),
    );
    final qCharges = go(
      db
          .from('charges')
          .select()
          .neq('status', 'cancelled')
          .order('due_date', ascending: true),
    );
    final qPayments = go(
      db.from('payments').select().order('created_at', ascending: false),
    );
    final qCheques = go(
      db
          .from('cheques')
          .select('*, leases(tenant_id)')
          .order('cheque_date', ascending: true),
    );
    final qPayAccounts = go(
      db.from('pay_accounts').select().order('sort_order', ascending: true),
    );
    final qHouseRules = go(
      db.from('house_rules').select().order('sort_order', ascending: true),
    );
    final qTaxes = go(db.from('taxes').select().order('id', ascending: true));
    final qMonthlyExpenses = go(
      db.from('monthly_expenses').select().order('id', ascending: true),
    );
    final qExpenseTemplates = go(
      db.from('expense_templates').select().order('id', ascending: true),
    );
    final qUnitCosts = go(
      db.from('unit_costs').select().order('spent_on', ascending: true),
    );
    final qCostTypes = go(
      db.from('cost_types').select('name').order('id', ascending: true),
    );
    final qChargeTypes = go(
      db.from('charge_types').select('name').order('id', ascending: true),
    );
    final qBookings = go(
      db
          .from('bookings')
          .select('*, booking_deductions(*), booking_files(*)')
          .eq('status', 'booked')
          .order('check_in', ascending: true),
    );
    final qReports = go(
      db
          .from('reports')
          .select('*, report_updates(*), report_photos(*)')
          .order('created_at', ascending: false),
    );
    final qWorkItems = go(
      db
          .from('work_items')
          .select('*, properties(name)')
          .order('start_date', ascending: true),
    );
    final qComplaints = go(
      db.from('complaints').select().order('created_at', ascending: false),
    );
    final qLeaseRequests = go(
      db.from('lease_requests').select().order('created_at', ascending: false),
    );
    final qNotices = go(
      db
          .from('notices')
          .select('*, notice_recipients(*)')
          .order('created_at', ascending: false),
    );
    final qTenantMessages = go(
      db.from('tenant_messages').select().order('created_at', ascending: false),
    );
    final qDocumentsToSign = go(db.from('documents_to_sign').select());
    final qChatReads = go(db.from('chat_reads').select());
    final qActivityLog = go(
      db
          .from('activity_log')
          .select()
          .order('created_at', ascending: false)
          .limit(300),
    );
    final qSettings = go(db.from('settings').select().maybeSingle());
    final qAlertPrefs = go(db.from('alert_prefs').select());
    final qPasswords = _tenantMode ? null : go(db.rpc('tenant_passwords'));
    final qRecentChat = go(
      db.rpc('recent_chat', params: {'p_limit': chatPage}),
    );

    // ---- units
    final props = await qProperties;
    _propertyIds
      ..clear()
      ..addEntries([
        for (final p in props) MapEntry(p['name'] as String, p['id'] as int),
      ]);
    final unitRows = await qUnits;
    final templateRows = await qUnitTemplates;
    final units = [
      for (var i = 0; i < unitRows.length; i++)
        UnitRec(
            property:
                (unitRows[i]['properties'] as Map?)?['name'] as String? ?? '',
            type: _typeFromDb(unitRows[i]['type'] as String),
            name: unitRows[i]['name'] as String,
            rate: _money(unitRows[i]['rate']),
            rateUnit: unitRows[i]['rate_unit'] as String,
            bedrooms: unitRows[i]['bedrooms'] as int,
            depositAmount: (unitRows[i]['deposit_amount'] as num?)?.toDouble(),
            photo: _photos[unitRows[i]['photo_path']],
          )
          ..id = unitRows[i]['id'] as int
          ..photoPath = unitRows[i]['photo_path'] as String?
          ..archivedAt = _time(unitRows[i]['archived_at']),
    ];
    // Deleted units are archived: kept for their history, not listed.
    final archivedUnits = units.where((u) => u.archivedAt != null).toList();
    units.removeWhere((u) => u.archivedAt != null);
    final templates = <UnitTemplate>[];
    for (var i = 0; i < templateRows.length; i++) {
      final r = templateRows[i];
      final t = UnitTemplate(
        name: r['name'] as String,
        property: (r['properties'] as Map?)?['name'] as String? ?? '',
        type: _typeFromDb(r['type'] as String),
        bedrooms: r['bedrooms'] as int,
        rate: (r['rate'] as num?)?.toDouble(),
        rateUnit: r['rate_unit'] as String,
        photo: _photos[r['photo_path']],
      )..photoPath = r['photo_path'] as String?;
      _templates.setIdTo(t, r['id']);
      templates.add(t);
    }
    String unitTypeById(Object? id) {
      final u = units.where((u) => u.id == id).firstOrNull;
      return u?.type ?? '';
    }

    String unitNameById(Object? id) =>
        units.where((u) => u.id == id).firstOrNull?.name ?? '';

    // ---- tenants, leases, move-outs, documents
    final tenantRows = await qTenants;
    _tenantIds
      ..clear()
      ..addEntries([
        for (final r in tenantRows)
          MapEntry(r['full_name'] as String, r['id'] as int),
      ]);
    final mine = tenantRows.where((r) => r['status'] == 'active').firstOrNull;
    final mineId = mine == null ? null : mine['id'] as int;
    _myTenantId = _tenantMode ? mineId : null;

    // Saved tenant passwords (admin only), so they can be shown again.
    final passwords = <int, String>{};
    if (!_tenantMode) {
      try {
        for (final r in await qPasswords! as List) {
          passwords[(r as Map)['tenant_id'] as int] =
              r['password'] as String? ?? '';
        }
      } catch (e) {
        debugPrint('Passwords: $e');
      }
    }
    final tenants = <TenantRec>[];
    final former = <FormerTenant>[];
    for (final r in tenantRows) {
      final leases = _rows(r['leases']);
      final pastLeases = [
        for (final j in (r['past_leases'] as List? ?? const []))
          await _termFromJson(j as Map<String, dynamic>),
      ];
      if (r['status'] == 'moved_out') {
        final l =
            (leases..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int)))
                .firstOrNull;
        final mo = _rows(l?['move_outs']).firstOrNull;
        former.add(
          FormerTenant(
            name: r['full_name'] as String,
            unit: unitNameById(l?['unit_id']),
            unitType: unitTypeById(l?['unit_id']),
            phone: r['phone'] as String? ?? '',
            email: r['email'] as String? ?? '',
            leaseStart: _date(l?['start_date']) == null
                ? ''
                : formatDate(_date(l?['start_date'])!),
            leaseEnd: _date(l?['end_date']) == null
                ? ''
                : formatDate(_date(l?['end_date'])!),
            movedOut:
                _date(mo?['moved_out_on']) ?? _date(l?['end_date']) ?? _today,
            depositNote:
                mo?['deposit_note'] as String? ??
                r['deposit_note'] as String? ??
                '',
            inspection: mo?['inspection'] as String? ?? '',
            owedAtMoveOut: _money(mo?['owed_at_move_out']),
            pastLeases: pastLeases,
          ),
        );
        continue;
      }
      // The lease in force, or else the next one (a reservation).
      final current =
          leases
              .where(
                (l) => l['status'] == 'active' || l['status'] == 'scheduled',
              )
              .toList()
            ..sort(
              (a, b) => (a['status'] == 'active' ? 0 : 1).compareTo(
                b['status'] == 'active' ? 0 : 1,
              ),
            );
      final l = current.firstOrNull;
      final start = _date(l?['start_date']);
      final end = _date(l?['end_date']);
      // With no lease yet, the unit and terms saved on the tenant.
      final unitId = l?['unit_id'] ?? r['unit_id'];
      final unitType = unitTypeById(unitId);
      final t =
          TenantRec(
              name: r['full_name'] as String,
              unit: unitId == null ? '' : unitNameById(unitId),
              phone: r['phone'] as String? ?? '',
              email: r['email'] as String? ?? '',
              stayType: unitId == null ? 'Not assigned' : stayTypeFor(unitType),
              rent: _money(l?['rent'] ?? r['rent']),
              leaseStart: start == null ? '' : formatDate(start),
              leaseEnd: end == null ? '' : formatDate(end),
              username: r['username'] as String? ?? '',
              // Passwords are never stored in the database tables.
              password: '',
              balance: _money(r['balance']),
              deposit: _money(l?['deposit'] ?? r['deposit']),
              depositNote: r['deposit_note'] as String?,
              paidFrom: _date(l?['paid_from']),
              paidUntil: _date(l?['paid_until']),
              emergencyContact: r['emergency_contact'] as String? ?? '',
              occupants: r['occupants'] as int? ?? 1,
            )
            ..id = r['id'] as int
            ..leaseId = l?['id'] as int?
            ..endReminded = r['end_reminded'] as bool? ?? false
            ..pastLeases.addAll(pastLeases)
            ..nextLease = r['next_lease'] == null
                ? null
                : await _termFromJson(r['next_lease'] as Map<String, dynamic>);
      t
        ..dueDay = (l?['due_day'] ?? r['due_day']) as int? ?? 5
        ..chequesPerYear =
            (l?['cheques_per_year'] ?? r['cheques_per_year']) as int? ?? 4;
      if (l != null) {
        t
          ..contractName = l['contract_name'] as String?
          ..contractAssignedAt = _time(l['contract_assigned_at']);
      }
      // The contract and signed lease are downloaded when opened.
      t
        ..contractOnServer = l?['contract_path'] != null
        ..signedLeaseOnServer = l?['signed_lease_path'] != null;
      _later(
        t,
        'contract',
        'contracts',
        l?['contract_path'],
        (b) => t.contractPdf = b,
      );
      _later(
        t,
        'signedLease',
        'contracts',
        l?['signed_lease_path'],
        (b) => t.signedLease = b,
      );
      for (final d in _rows(r['tenant_documents'])) {
        final kind = d['kind'] as String;
        _TenantDocs.paths['${t.id}|$kind'] = d['file_path'] as String;
        if (d['state'] == 'rejected') {
          t.docs[kind] = false;
          t.docRejected[kind] = d['reject_reason'] as String? ?? '';
          continue;
        }
        // The file itself is downloaded when the document is opened.
        t.docs[kind] = true;
        final fileName = d['file_name'] as String;
        _TenantDocs.names['${t.id}|$kind'] = fileName;
        _later(
          t,
          'doc:$kind',
          'tenant-documents',
          d['file_path'],
          (b) => t.docFiles[kind] = (name: fileName, bytes: b),
        );
        if (d['state'] == 'verified') t.docVerified.add(kind);
      }
      t.password = passwords[t.id] ?? '';
      _logins.sent[t] = '${t.username}|${t.password}';
      tenants.add(t);
    }

    // ---- money
    final chargeRows = await qCharges;
    final chargeById = <Object, ChargeRec>{};
    final charges = <ChargeRec>[];
    for (final r in chargeRows) {
      final c = ChargeRec(
        tenant: _tenantName(r['tenant_id']),
        title: r['title'] as String,
        amount: _money(r['amount']),
        due: formatDate(_date(r['due_date'])!),
        paid: r['status'] == 'paid',
      )..paidAmount = _money(r['paid_amount']);
      _charges.setIdTo(c, r['id']);
      chargeById[r['id'] as Object] = c;
      charges.add(c);
    }

    final paymentRows = await qPayments;
    final payments = <PaymentRec>[];
    for (final r in paymentRows) {
      final name = _tenantName(r['tenant_id']);
      final p = PaymentRec(
        id: 'P-db${r['id']}',
        tenant: name,
        unit:
            tenants.where((t) => t.name == name).firstOrNull?.unit ??
            former.where((f) => f.name == name).firstOrNull?.unit ??
            '',
        title: r['title'] as String,
        amount: _money(r['amount']),
        method: r['method'] as String,
        reference: r['reference'] as String? ?? '',
        date: formatDate(_date(r['paid_on'])!),
        status: PayStatus.values.byName(r['status'] as String),
        reason: r['reject_reason'] as String?,
        recordedByAdmin: r['source'] != 'tenant_proof',
        months: r['months'] as int? ?? 1,
        coversFrom: _date(r['covers_from']),
        coversTo: _date(r['covers_to']),
      );
      _payments.setIdTo(p, r['id']);
      // The receipt is only needed while it waits to be checked.
      _later(p, 'proof', 'payment-proofs', r['proof_path'], (b) => p.proof = b);
      for (final cid in (r['charge_ids'] as List? ?? const [])) {
        final c = chargeById[cid];
        if (c != null) p.covers.add(c);
      }
      payments.add(p);
    }

    final chequeRows = await qCheques;
    final cheques = <ChequeRec>[];
    for (var i = 0; i < chequeRows.length; i++) {
      final r = chequeRows[i];
      final c =
          ChequeRec(
              id: 'CH-db${r['id']}',
              tenant: _tenantName(
                r['tenant_id'] ?? (r['leases'] as Map?)?['tenant_id'],
              ),
              kind: r['kind'] == 'deposit'
                  ? ChequeKind.deposit
                  : ChequeKind.postDated,
              amount: _money(r['amount']),
              date: _date(r['cheque_date'])!,
              months: r['months'] as int? ?? 0,
              chequeNo: r['cheque_no'] as String? ?? '',
              bank: r['bank'] as String? ?? '',
              status: ChequeStatus.values.byName(r['status'] as String),
            )
            ..uploadedOn = _time(r['photo_uploaded_at']) == null
                ? null
                : formatDate(_time(r['photo_uploaded_at'])!)
            ..photoChecked = r['photo_checked'] as bool? ?? false
            ..reminded = r['reminded'] as bool? ?? false
            ..replaces = r['replaces_id'] == null
                ? null
                : 'CH-db${r['replaces_id']}'
            ..returnedOn = _date(r['returned_on']) == null
                ? null
                : formatDate(_date(r['returned_on'])!);
      // The photo is downloaded when the cheque is opened.
      _later(c, 'photo', 'cheque-photos', r['photo_path'], (b) => c.photo = b);
      _cheques.setIdTo(c, r['id']);
      cheques.add(c);
    }

    // ---- settings and lists the admin keeps
    final accountRows = await qPayAccounts;
    final qrs = await Future.wait([
      for (final r in accountRows) _get('public-assets', r['qr_path']),
    ]);
    final accounts = <PayAccount>[];
    for (final r in accountRows) {
      final a = PayAccount(
        type: r['type'] as String,
        name: r['name'] as String,
        accountName: r['account_name'] as String,
        number: r['number'] as String,
        qr: qrs[accountRows.indexOf(r)],
      );
      _payAccounts.setIdTo(a, r['id']);
      accounts.add(a);
    }

    final ruleRows = await qHouseRules;
    final rules = <HouseRule>[];
    for (final r in ruleRows) {
      final h = HouseRule(r['title'] as String, r['body'] as String);
      _rules.setIdTo(h, r['id']);
      rules.add(h);
    }

    final taxes = <TaxRate>[];
    for (final r in await qTaxes) {
      final t = TaxRate(
        name: r['name'] as String,
        percent: _money(r['percent']),
        onVillas: r['on_villas'] as bool? ?? false,
        fixedMonthly: _money(r['fixed_monthly']),
      );
      _taxes.setIdTo(t, r['id']);
      taxes.add(t);
    }

    final expenses = <String, List<MonthlyExpense>>{};
    for (final r in await qMonthlyExpenses) {
      final e = MonthlyExpense(
        name: r['name'] as String,
        amount: _money(r['amount']),
        since: _date(r['since_month'])!,
        until: _date(r['until_month']),
      );
      _expenses.setIdTo(e, r['id']);
      (expenses[unitNameById(r['unit_id'])] ??= []).add(e);
    }

    final expenseTemplates = <ExpenseTemplate>[];
    for (final r in await qExpenseTemplates) {
      final t = ExpenseTemplate(
        name: r['name'] as String,
        amount: _money(r['amount']),
        unitType: _typeFromDb(r['unit_type'] as String),
      );
      _expenseTemplates.setIdTo(t, r['id']);
      expenseTemplates.add(t);
    }

    final costs = <String, List<CostEntry>>{};
    for (final r in await qUnitCosts) {
      final c = CostEntry(
        title: r['title'] as String,
        amount: _money(r['amount']),
        date: _date(r['spent_on'])!,
      );
      _costs.setIdTo(c, r['id']);
      (costs[unitNameById(r['unit_id'])] ??= []).add(c);
    }
    final costTypes = [for (final r in await qCostTypes) r['name'] as String];
    final chargeTypes = [
      for (final r in await qChargeTypes) r['name'] as String,
    ];

    // ---- condo stays
    final bookingRows = await qBookings;
    final bookings = <Booking>[];
    for (final r in bookingRows) {
      final b = Booking(
        id: 'B-db${r['id']}',
        unit: unitNameById(r['unit_id']),
        guest: r['guest_name'] as String,
        phone: r['phone'] as String? ?? '',
        guests: r['guests'] as int? ?? 1,
        checkIn: _time(r['check_in'])!,
        checkOut: _time(r['check_out'])!,
        amount: _money(r['amount']),
        deposit: _money(r['deposit']),
      );
      _bookings.setIdTo(b, r['id']);
      for (final d in _rows(
        r['booking_deductions'],
      )..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int))) {
        b.deductions.add((
          amount: _money(d['amount']),
          reason: d['reason'] as String? ?? '',
          date: _date(d['deducted_on'])!,
        ));
      }
      for (final f in _rows(r['booking_files'])) {
        // The file is downloaded when the stay is opened.
        final g = GuestFile(
          label: f['label'] as String,
          fileName: f['file_name'] as String,
          bytes: null,
          added: _time(f['added_at'])!,
        );
        _later(g, 'file', 'guest-files', f['file_path'], (b) => g.bytes = b);
        _guestFiles.setIdTo(g, f['id']);
        b.files.add(g);
      }
      final returned = _date(r['deposit_returned_on']);
      if (returned != null) adminState.setDepositReturned(b, returned);
      bookings.add(b);
    }

    // ---- reports, work, complaints, requests
    final reportRows = await qReports;
    final reports = <DamageReport>[];
    final reportById = <Object, DamageReport>{};
    for (final r in reportRows) {
      final updates = <ReportUpdate>[];
      for (final u
          in _rows(r['report_updates'])..sort(
            (a, b) =>
                (b['posted_at'] as String).compareTo(a['posted_at'] as String),
          )) {
        final x = ReportUpdate(
          u['body'] as String,
          formatDate(_time(u['posted_at'])!),
        );
        _reportUpdates.setIdTo(x, u['id']);
        updates.add(x);
      }
      final rep =
          DamageReport(
              id: r['code'] as String,
              tenant: r['tenant_id'] == null
                  ? (r['reporter_name'] as String? ?? 'Management')
                  : _tenantName(r['tenant_id']),
              unit: unitNameById(r['unit_id']),
              issue: r['issue'] as String,
              description: r['description'] as String,
              date: formatDate(_time(r['created_at'])!),
              attachments: r['attachments'] as int? ?? 0,
              status: switch (r['status']) {
                'under_review' => ReportStatus.underReview,
                'approved' => ReportStatus.approved,
                _ => ReportStatus.pending,
              },
              type: ReportType.values.byName(r['type'] as String),
              updates: updates,
            )
            ..kind = r['damage_kind'] == null
                ? null
                : DamageKind.values.byName(r['damage_kind'] as String)
            ..deduction = _money(r['tenant_amount'])
            ..note = r['admin_note'] as String? ?? '';
      for (final p in _rows(r['report_photos'])) {
        // Photos are downloaded when the report is opened.
        final pid = p['id'];
        _later(rep, 'photo:$pid', 'report-photos', p['file_path'], (b) {
          _reportPhotos.setIdTo(b, pid);
          _reportPhotos._known.add(b);
          rep.photoFiles.add(b);
        });
      }
      _reports.setIdTo(rep, r['id']);
      reportById[r['id'] as Object] = rep;
      reports.add(rep);
    }

    final work = <WorkItem>[];
    for (final r in await qWorkItems) {
      final charge = r['charge_id'] == null ? null : chargeById[r['charge_id']];
      final w =
          WorkItem(
              date: _date(r['start_date'])!,
              endDate: _date(r['end_date']),
              time: r['time_label'] as String? ?? 'All day',
              title: r['title'] as String,
              where: r['unit_id'] != null
                  ? unitNameById(r['unit_id'])
                  : ((r['properties'] as Map?)?['name'] as String? ?? ''),
              kind: switch (r['kind']) {
                'repair' => AdminEventKind.repair,
                'inspection' => AdminEventKind.inspection,
                'modification' => AdminEventKind.modification,
                _ => AdminEventKind.maintenance,
              },
              notes: r['notes'] as String? ?? '',
              done: r['done'] as bool? ?? false,
              cost: _money(r['cost']),
            )
            ..tenantPays = r['tenant_pays'] as bool? ?? false
            ..chargeRec = charge
            ..chargedTenant = charge?.tenant
            ..charge = charge?.amount ?? 0;
      _work.setIdTo(w, r['id']);
      work.add(w);
    }

    final complaints = <ComplaintRec>[];
    for (final r in await qComplaints) {
      final name = _tenantName(r['tenant_id']);
      final c = ComplaintRec(
        tenant: name,
        unit: tenants.where((t) => t.name == name).firstOrNull?.unit ?? '',
        category: r['category'] as String,
        body: r['body'] as String,
        date: formatDate(_time(r['created_at'])!),
        status: switch (r['status']) {
          'in_progress' => ComplaintStatus.inProgress,
          'resolved' => ComplaintStatus.resolved,
          _ => ComplaintStatus.open,
        },
        response: r['response'] as String?,
      );
      _complaints.setIdTo(c, r['id']);
      complaints.add(c);
    }

    final requests = <LeaseRequest>[];
    for (final r in await qLeaseRequests) {
      final name = _tenantName(r['tenant_id']);
      final q = LeaseRequest(
        tenant: name,
        unit: tenants.where((t) => t.name == name).firstOrNull?.unit ?? '',
        kind: (r['details'] as String?)?.isNotEmpty == true
            ? r['details'] as String
            : r['kind'] as String,
        date: formatDate(_time(r['created_at'])!),
        note: r['note'] as String? ?? '',
        status: RequestStatus.values.byName(r['status'] as String),
      );
      _requests.setIdTo(q, r['id']);
      requests.add(q);
    }

    // ---- notices
    final noticeRows = await qNotices;
    final notices = <AdminNotice>[];
    final tenantNotices = <Notice>[];
    for (final r in noticeRows) {
      final rec = _rows(r['notice_recipients']);
      final to = r['to_tenant_id'] == null
          ? null
          : _tenantName(r['to_tenant_id']);
      final kind = NoticeKind.values.byName(r['kind'] as String);
      final created = _time(r['created_at'])!;
      final n = AdminNotice(
        id: 'ndb${r['id']}',
        title: r['title'] as String,
        body: r['body'] as String,
        kind: kind,
        date: formatDate(created),
        recipients: [for (final x in rec) _tenantName(x['tenant_id'])],
        readBy: {
          for (final x in rec)
            if (x['read_at'] != null) _tenantName(x['tenant_id']),
        },
        to: to,
        automatic: r['automatic'] as bool? ?? false,
        unitTypes: (r['unit_types'] as List?)?.cast<String>(),
      );
      _notices.setIdTo(n, r['id']);
      notices.add(n);
      if (_tenantMode) {
        tenantNotices.add(
          Notice(
            id: n.id,
            kind: kind,
            title: n.title,
            body: n.body,
            date: n.date,
            to: to,
          )..acknowledged = rec.any((x) => x['read_at'] != null),
        );
      }
    }

    // ---- messages and chat
    final adminMessages = <AdminMessage>[];
    final myMessages = <Message>[];
    for (final r in await qTenantMessages) {
      final name = _tenantName(r['tenant_id']);
      final created = _time(r['created_at'])!;
      if (_tenantMode) {
        final m = Message(
          category: r['category'] as String,
          body: r['body'] as String,
          date: formatDate(created),
          reply: r['reply'] as String?,
        );
        _myMessages.setIdTo(m, r['id']);
        myMessages.add(m);
      } else {
        final m = AdminMessage(
          tenant: name,
          unit: tenants.where((t) => t.name == name).firstOrNull?.unit ?? '',
          category: r['category'] as String,
          body: r['body'] as String,
          date: formatDate(created),
          reply: r['reply'] as String?,
        );
        _adminMessages.setIdTo(m, r['id']);
        adminMessages.add(m);
      }
    }

    final docRows = await qDocumentsToSign;
    final docByMessage = {
      for (final d in docRows)
        if (d['message_id'] != null) d['message_id'] as String: d,
    };
    // Only the latest messages of each chat; older ones load on request.
    final threads = <String, List<ChatMessage>>{};
    _docRows
      ..clear()
      ..addAll(docByMessage);
    List<dynamic> chatRows;
    try {
      chatRows = await qRecentChat as List;
    } catch (_) {
      // The paging function isn't set up yet: load the whole history.
      chatRows = await db
          .from('chat_messages')
          .select()
          .order('created_at', ascending: true);
    }
    for (final r in chatRows) {
      final row = r as Map<String, dynamic>;
      final m = _chatFromRow(row, tenants);
      (threads[_tenantName(row['tenant_id'])] ??= []).add(m);
    }
    _olderChats.clear();
    for (final e in threads.entries) {
      if (e.value.length >= chatPage) _olderChats.add(e.key);
    }
    final reads = <String, DateTime>{
      for (final r in await qChatReads)
        '${r['side']}|${_tenantName(r['tenant_id'])}': _time(r['read_at'])!,
    };

    // ---- activity log and settings
    final log = <LogEntry>[];
    for (final r in await qActivityLog) {
      final e = LogEntry(
        _time(r['created_at'])!,
        r['action'] as String,
        r['detail'] as String? ?? '',
      );
      _log.setIdTo(e, r['id']);
      log.add(e);
    }
    final settings = await qSettings;
    final prefs = await qAlertPrefs;

    // ---- put it all in
    // A renewal that starts today takes its new contract with it (and the
    // old one moves to the previous leases): have both here first.
    if (!_tenantMode) {
      await fetch([
        for (final t in tenants)
          if (t.nextLease != null &&
              !(parseDate(t.nextLease!.start) ?? DateTime(9999)).isAfter(
                _today,
              )) ...[
            t,
            t.nextLease,
          ],
      ]);
    }
    adminState.archivedUnits
      ..clear()
      ..addAll(archivedUnits);
    adminState.loadFromServer(
      units: units,
      templates: templates,
      tenants: tenants,
      formerTenants: former,
      charges: charges,
      payments: payments,
      cheques: cheques,
      taxes: taxes,
      monthlyExpenses: expenses,
      expenseTemplates: expenseTemplates,
      unitCosts: costs,
      costTypes: costTypes,
      chargeTypes: chargeTypes,
      bookings: bookings,
      reports: reports,
      workItems: work,
      complaints: complaints,
      requests: requests,
      notices: notices,
      messages: adminMessages,
      activityLog: log,
      alertPrefs: {
        for (final p in prefs) p['key'] as String: p['enabled'] as bool,
      },
      gatewayFeePercent: settings == null
          ? null
          : _money(settings['gateway_fee_percent']),
      bouncedChequeFee: settings == null
          ? null
          : _money(settings['bounced_cheque_fee']),
      rentChargeLeadDays: settings?['rent_charge_lead_days'] as int?,
      runDailyJobs: !_tenantMode,
    );
    _Names.loaded['cost_types'] = costTypes;
    _Names.loaded['charge_types'] = chargeTypes;
    appState.loadShared(payAccounts: accounts, rules: rules);
    chatState
      ..trackDelivery = true
      ..replaceAll(threads, reads);
    _chatSince = null;
    for (final list in threads.values) {
      for (final m in list) {
        if (_chatSince == null || m.time.isAfter(_chatSince!)) {
          _chatSince = m.time;
        }
      }
    }

    if (_tenantMode) {
      final me = tenants.firstOrNull;
      if (me != null) adminState.signInTenant(me.name);
      appState.loadTenantLists(notices: tenantNotices, messages: myMessages);
    }
    unawaited(_fillPhotos(units, templates));
  }
}

// ============================================================== steps

/// One table (or group of rows) the engine keeps in step.
abstract class _Step {
  /// Records what was loaded, so it is not written back.
  Future<void> prime();

  /// Deletes what was removed in the app.
  Future<void> remove() async {}

  /// Adds what is new and updates what changed.
  Future<void> save();
}

/// A list of app objects, each one row of [table].
class _Spec<T extends Object> extends _Step {
  _Spec(
    this.table,
    this.what, {
    required this.items,
    required this.row,
    this.tenantRow,
    this.tenantInsert = false,
    this.tenantOnly = false,
    this.insertOnly = false,
    this.getId,
    this.setId,
    this.onRemoved,
    this.insert,
    this.onInsert,
    this.files = const {},
    this.keepFilesOnRemove = false,
  });

  /// Removing keeps the row's files (an archived row still uses them).
  final bool keepFilesOnRemove;

  /// File columns of the row and their storage area: when the row is
  /// removed, its files are deleted too.
  final Map<String, String> files;

  final String table, what;
  final Iterable<T> Function() items;

  /// The row for an object; null to leave it for now (e.g. its unit is not
  /// saved yet, or an amount of 0 the database won't take).
  final Future<Map<String, Object?>?> Function(T o) row;

  /// What a tenant may update, when they may update at all.
  final Future<Map<String, Object?>?> Function(T o)? tenantRow;
  final bool tenantInsert, tenantOnly, insertOnly;

  /// Where the row id is kept, when the model has its own field for it.
  final Object? Function(T o)? getId;
  final void Function(T o, Object? id)? setId;

  final Future<void> Function(T o, Object id)? onRemoved;
  final Future<Object?> Function(T o, Map<String, Object?> row)? insert;

  /// Told whether adding a row worked (chat uses it for "Sent" / "Not sent").
  final void Function(T o, bool ok)? onInsert;
  final Set<T> _inFlight = Set.identity();

  final _ids = Expando<Object>();
  final _sent = Expando<String>();
  final Set<T> _known = Set.identity();

  bool get _runs =>
      Sync._tenantMode ? (tenantInsert || tenantRow != null) : !tenantOnly;

  Object? idOf(T o) => getId != null ? getId!(o) : _ids[o];

  void setIdTo(T o, Object? id) {
    if (setId != null) {
      setId!(o, id);
    } else {
      _ids[o] = id;
    }
  }

  Future<Map<String, Object?>?> _compareRow(T o) =>
      Sync._tenantMode && tenantRow != null ? tenantRow!(o) : row(o);

  /// Records [o] as saved with [id] (it came from the server), so it is
  /// not written back.
  Future<void> markSaved(T o, Object id) async {
    setIdTo(o, id);
    _known.add(o);
    if (insertOnly) return;
    final r = await _compareRow(o);
    if (r != null) _sent[o] = jsonEncode(r);
  }

  @override
  Future<void> prime() async {
    if (!_runs) return;
    for (final o in items().toList()) {
      if (Sync._stale) return;
      if (idOf(o) == null) continue;
      _known.add(o);
      if (insertOnly) continue;
      try {
        final r = await _compareRow(o);
        if (r != null) _sent[o] = jsonEncode(r);
      } catch (_) {}
    }
  }

  @override
  Future<void> remove() async {
    if (!_runs || Sync._tenantMode || insertOnly) return;
    final now = Set<T>.identity()..addAll(items());
    final gone = _known.where((o) => !now.contains(o)).toList();
    if (gone.isEmpty) return;
    // Safety: a row is only deleted when nothing on screen still has its id.
    // Two copies of the same row (e.g. from two loads) must never delete
    // each other's row on the server.
    final liveIds = {
      for (final o in now)
        if (idOf(o) case final id?) '$id',
    };
    // Safety: a list that suddenly emptied (a load that went wrong) is not
    // the admin deleting everything. Nothing is removed; the next load
    // puts things right.
    if (now.isEmpty && gone.length >= 3) {
      debugPrint('Sync: $table emptied unexpectedly; nothing removed.');
      _known.removeWhere((o) => !now.contains(o));
      return;
    }
    for (final o in gone) {
      if (Sync._stale) return;
      final idNow = idOf(o);
      if (idNow != null && liveIds.contains('$idNow')) {
        _known.remove(o); // another copy of the same row is still here
        continue;
      }
      try {
        final id = idOf(o);
        if (id != null) {
          // Note its files first, so they go with it.
          final before = files.isEmpty || keepFilesOnRemove
              ? null
              : await supabase
                    .from(table)
                    .select(files.keys.join(','))
                    .eq('id', id)
                    .maybeSingle();
          if (onRemoved != null) {
            await onRemoved!(o, id);
          } else {
            await supabase.from(table).delete().eq('id', id);
          }
          if (before != null) {
            for (final f in files.entries) {
              await Sync._dropFile(f.value, before[f.key]);
            }
          }
        }
        _known.remove(o);
      } catch (e) {
        Sync._failed('the removal of $what', e);
      }
    }
  }

  @override
  Future<void> save() async {
    if (!_runs) return;
    for (final o in items().toList()) {
      final id = idOf(o);
      if (id == null) {
        // Already being added (chat sends straight away, beside the usual
        // save): never add it twice.
        if (_inFlight.contains(o)) continue;
        if (Sync._tenantMode && !tenantInsert) continue;
        _inFlight.add(o);
        var ok = false;
        try {
          final r = await row(o);
          if (r == null) continue;
          if (Sync._stale) return;
          final newId = insert != null
              ? await insert!(o, r)
              : (await supabase
                    .from(table)
                    .insert(r)
                    .select('id')
                    .single())['id'];
          setIdTo(o, newId);
          _known.add(o);
          if (!insertOnly) {
            final c = Sync._tenantMode && tenantRow != null
                ? await tenantRow!(o)
                : r;
            _sent[o] = jsonEncode(c);
          }
          ok = true;
          // Rows that hang off this one can now be saved.
          Sync._again = true;
        } catch (e) {
          // A chat message shows "Not sent" instead of a message at the bottom.
          if (onInsert == null) Sync._failed(what, e);
        } finally {
          _inFlight.remove(o);
          onInsert?.call(o, ok);
        }
        continue;
      }
      try {
        _known.add(o);
        if (insertOnly) continue;
        if (Sync._tenantMode && tenantRow == null) continue;
        final r = await _compareRow(o);
        if (r == null) continue;
        final json = jsonEncode(r);
        final before = _sent[o];
        if (before == json) continue;
        if (before != null) await supabase.from(table).update(r).eq('id', id);
        _sent[o] = json;
      } catch (e) {
        Sync._failed(what, e);
      }
    }
  }
}

/// Tenant logins: created or changed through the server function whenever
/// the admin sets a username or password.
class _Logins extends _Step {
  final sent = Expando<String>();

  @override
  Future<void> prime() async {}

  @override
  Future<void> save() async {
    if (Sync._tenantMode) return;
    for (final t in adminState.tenants.toList()) {
      final id = t.id;
      final username = t.username.trim();
      if (id == null || username.isEmpty) continue;
      final key = '$username|${t.password}';
      if (sent[t] == key) continue;
      // A username change alone keeps the old password.
      if (sent[t] == '$username|' && t.password.isEmpty) continue;
      final problem = await Sync.saveLogin(id, username, t.password);
      // Keep a copy (encrypted, admin only) so the password can be shown again.
      if (problem == null && t.password.isNotEmpty) {
        try {
          await supabase.rpc(
            'save_tenant_password',
            params: {'p_tenant_id': id, 'p_password': t.password},
          );
        } catch (e) {
          debugPrint('Password copy: $e');
        }
      }
      if (problem != null) {
        messengerKey.currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text("Couldn't save ${t.name}'s login. $problem"),
            ),
          );
      }
      sent[t] = key;
    }
  }
}

/// Each tenant's documents: one row per kind (the latest file).
class _TenantDocs extends _Step {
  /// Where each document is stored, by "tenantId|kind".
  static final Map<String, String> paths = {};

  /// Document file names, by "tenantId|kind" (the file itself may not be
  /// downloaded yet).
  static final Map<String, String> names = {};
  final Map<String, String> _sent = {};

  Map<String, Map<String, Object?>> _rows(TenantRec t) => {
    for (final kind in {...t.docs.keys, ...t.docRejected.keys})
      if (t.docs[kind] == true &&
          (t.docFiles[kind] != null || names.containsKey('${t.id}|$kind')))
        kind: {
          'name': t.docFiles[kind]?.name ?? names['${t.id}|$kind'],
          'state': t.docVerified.contains(kind) ? 'verified' : 'to_review',
          'reason': null,
        }
      else if (t.docRejected.containsKey(kind))
        kind: {
          'name': null,
          'state': 'rejected',
          'reason': t.docRejected[kind],
        },
  };

  Iterable<TenantRec> get _tenants => adminState.tenants.where(
    (t) => t.id != null && (!Sync._tenantMode || t.id == Sync._myTenantId),
  );

  @override
  Future<void> prime() async {
    _sent.clear();
    for (final t in _tenants) {
      _rows(t).forEach((kind, r) => _sent['${t.id}|$kind'] = jsonEncode(r));
    }
  }

  @override
  Future<void> save() async {
    for (final t in _tenants.toList()) {
      final rows = _rows(t);
      for (final MapEntry(key: kind, value: r) in rows.entries) {
        final key = '${t.id}|$kind';
        final json = jsonEncode(r);
        if (_sent[key] == json) continue;
        // A tenant only uploads; checking is the admin's.
        if (Sync._tenantMode && r['state'] != 'to_review') continue;
        try {
          final file = t.docFiles[kind];
          if (file != null) {
            paths[key] = await Sync._put(
              'tenant-documents',
              '${t.id}',
              file.bytes,
            );
          }
          final path = paths[key];
          if (path == null) continue;
          await supabase.from('tenant_documents').upsert({
            'tenant_id': t.id,
            'kind': kind,
            'file_name': r['name'] ?? kind,
            'file_path': path,
            'state': r['state'],
            'reject_reason': r['reason'],
          }, onConflict: 'tenant_id,kind');
          _sent[key] = json;
        } catch (e) {
          Sync._failed('${t.name}\'s $kind', e);
        }
      }
      // Documents the admin removed.
      if (Sync._tenantMode) continue;
      for (final key
          in _sent.keys.where((k) => k.startsWith('${t.id}|')).toList()) {
        final kind = key.substring('${t.id}|'.length);
        if (rows.containsKey(kind)) continue;
        try {
          await supabase
              .from('tenant_documents')
              .delete()
              .eq('tenant_id', t.id!)
              .eq('kind', kind);
          _sent.remove(key);
          paths.remove(key);
        } catch (e) {
          Sync._failed('the removal of ${t.name}\'s $kind', e);
        }
      }
    }
  }
}

/// A list of names (cost types, charge types): saved as a whole.
class _Names extends _Step {
  _Names(this.table, this.names);
  final String table;
  final List<String> Function() names;

  /// What the database had at load.
  static final Map<String, List<String>> loaded = {};
  String? _sent;

  @override
  Future<void> prime() async => _sent = jsonEncode(loaded[table] ?? const []);

  @override
  Future<void> save() async {
    if (Sync._tenantMode) return;
    final now = jsonEncode(names());
    if (now == _sent) return;
    // Safety: an empty list replacing a filled one is never saved (the
    // whole list is rewritten, so it would wipe every name).
    if (names().isEmpty && (_sent ?? '[]') != '[]') {
      debugPrint('Sync: $table came up empty; not saved.');
      return;
    }
    try {
      await supabase.from(table).delete().neq('id', 0);
      await supabase.from(table).insert([
        for (final n in names().toSet()) {'name': n},
      ]);
      _sent = now;
    } catch (e) {
      Sync._failed('the list of ${table.replaceAll('_', ' ')}', e);
    }
  }
}

/// Amounts taken off a condo deposit, per stay.
class _Deductions extends _Step {
  final _sent = Expando<String>();

  String _json(Booking b) => jsonEncode([
    for (final d in b.deductions) [d.amount, d.reason, Sync._d(d.date)],
  ]);

  @override
  Future<void> prime() async {
    for (final b in adminState.bookings) {
      if (Sync._bookings.idOf(b) != null) _sent[b] = _json(b);
    }
  }

  @override
  Future<void> save() async {
    if (Sync._tenantMode) return;
    for (final b in adminState.bookings.toList()) {
      final id = Sync._bookings.idOf(b);
      if (id == null) continue;
      final json = _json(b);
      if (_sent[b] == json) continue;
      if (_sent[b] == null && b.deductions.isEmpty) {
        _sent[b] = json;
        continue;
      }
      try {
        await supabase.from('booking_deductions').delete().eq('booking_id', id);
        final rows = [
          for (final d in b.deductions)
            if (d.amount > 0)
              {
                'booking_id': id,
                'amount': d.amount,
                'reason': d.reason,
                'deducted_on': Sync._d(d.date),
              },
        ];
        if (rows.isNotEmpty) {
          await supabase.from('booking_deductions').insert(rows);
        }
        _sent[b] = json;
      } catch (e) {
        Sync._failed('${b.guest}\'s deposit deductions', e);
      }
    }
  }
}

/// Who a notice went to, and who has read it.
class _Recipients extends _Step {
  final _sent = Expando<String>();

  String _json(AdminNotice n) => Sync._tenantMode
      ? jsonEncode(n.readBy.contains(appState.currentTenant))
      : jsonEncode([...n.recipients]..sort());

  @override
  Future<void> prime() async {
    for (final n in adminState.notices) {
      if (Sync._notices.idOf(n) != null) _sent[n] = _json(n);
    }
  }

  @override
  Future<void> save() async {
    for (final n in adminState.notices.toList()) {
      final id = Sync._notices.idOf(n);
      if (id == null) continue;
      final json = _json(n);
      if (_sent[n] == json) continue;
      try {
        if (Sync._tenantMode) {
          final me = Sync._myTenantId;
          if (me != null && n.readBy.contains(appState.currentTenant)) {
            await supabase
                .from('notice_recipients')
                .update({'read_at': Sync._ts(DateTime.now())})
                .eq('notice_id', id)
                .eq('tenant_id', me);
          }
        } else {
          final rows = [
            for (final name in n.recipients.toSet())
              if (Sync._tenantId(name) != null)
                {'notice_id': id, 'tenant_id': Sync._tenantId(name)},
          ];
          if (rows.isNotEmpty) {
            await supabase
                .from('notice_recipients')
                .upsert(
                  rows,
                  onConflict: 'notice_id,tenant_id',
                  ignoreDuplicates: true,
                );
          }
        }
        _sent[n] = json;
      } catch (e) {
        Sync._failed('who "${n.title}" went to', e);
      }
    }
  }
}

/// When each side last opened a chat thread.
class _ChatReads extends _Step {
  final Map<String, String> _sent = {};

  Map<String, DateTime> get _mine => {
    for (final e in chatState.lastRead.entries)
      if (!Sync._tenantMode || e.key.startsWith('tenant|')) e.key: e.value,
  };

  @override
  Future<void> prime() async {
    _sent
      ..clear()
      ..addAll({
        for (final e in _mine.entries) e.key: e.value.toIso8601String(),
      });
  }

  @override
  Future<void> save() async {
    for (final e in _mine.entries) {
      final at = e.value.toIso8601String();
      if (_sent[e.key] == at) continue;
      final side = e.key.split('|').first;
      final tid = Sync._tenantId(e.key.substring(side.length + 1));
      if (tid == null) continue;
      try {
        await supabase.from('chat_reads').upsert({
          'tenant_id': tid,
          'side': side,
          'read_at': Sync._ts(e.value),
        }, onConflict: 'tenant_id,side');
        _sent[e.key] = at;
      } catch (e2) {
        Sync._failed('a read receipt', e2);
      }
    }
  }
}

/// The admin's fees and timing settings (one row).
class _Settings extends _Step {
  String? _sent;

  Map<String, Object?> get _row => {
    'gateway_fee_percent': adminState.gatewayFeePercent,
    'bounced_cheque_fee': adminState.bouncedChequeFee,
    'rent_charge_lead_days': adminState.rentChargeLeadDays,
  };

  @override
  Future<void> prime() async => _sent = jsonEncode(_row);

  @override
  Future<void> save() async {
    if (Sync._tenantMode) return;
    final json = jsonEncode(_row);
    if (json == _sent) return;
    try {
      await supabase.from('settings').update(_row).eq('id', true);
      _sent = json;
    } catch (e) {
      Sync._failed('the settings', e);
    }
  }
}

/// Which alerts the admin wants flagged.
class _AlertPrefs extends _Step {
  String? _sent;

  @override
  Future<void> prime() async => _sent = jsonEncode(adminState.alertPrefs);

  @override
  Future<void> save() async {
    if (Sync._tenantMode) return;
    final json = jsonEncode(adminState.alertPrefs);
    if (json == _sent) return;
    try {
      await supabase.from('alert_prefs').upsert([
        for (final e in adminState.alertPrefs.entries)
          {'key': e.key, 'enabled': e.value},
      ], onConflict: 'key');
      _sent = json;
    } catch (e) {
      Sync._failed('the notification settings', e);
    }
  }
}

/// How full the file storage is.
class StorageReport {
  StorageReport({
    required this.byArea,
    required this.limitBytes,
    this.lastCleanup,
  });

  /// Bytes and number of files per storage area (bucket).
  final Map<String, (int, int)> byArea;
  final int limitBytes;
  final DateTime? lastCleanup;

  int get usedBytes => byArea.values.fold(0, (n, v) => n + v.$1);
  double get fraction =>
      limitBytes <= 0 ? 0 : (usedBytes / limitBytes).clamp(0, 1).toDouble();
}

/// A file on the server not downloaded yet, and where it goes when it is.
class _Pending {
  _Pending(this.bucket, this.path, this.assign);
  final String bucket, path;
  final void Function(Uint8List bytes) assign;
}
