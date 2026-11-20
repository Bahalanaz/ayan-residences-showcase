import 'package:flutter/foundation.dart';

import 'demo.dart';
import 'signing.dart';
export 'signing.dart';

enum ChatSender { tenant, admin }

/// Whether a message reached the server: being sent, sent, or failed (tap to
/// retry).
enum Delivery { sending, sent, failed }

/// A document the admin asks the tenant to sign inside the chat.
enum SignStatus { awaiting, signed, completed }

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.from,
    required this.time,
    this.text,
    this.image,
    this.docTitle,
    this.fileName,
    this.fileBytes,
  }) : sign = docTitle == null ? null : SignStatus.awaiting;

  /// A PDF attached to a signature request.
  final String? fileName;

  /// The PDF (null until downloaded when it came from the server).
  Uint8List? fileBytes;
  int get fileSize => fileBytes?.length ?? 0;

  final String id;
  final ChatSender from;
  final DateTime time;
  final String? text;

  /// A photo (null until downloaded when it came from the server).
  Uint8List? image;

  // ---- signature request (only when [docTitle] is set; the photo in [image]
  // is the document page)
  final String? docTitle;
  SignStatus? sign;
  Uint8List? signature;
  DateTime? signedAt;

  /// The whole document with the signature placed on it (PDF).
  Uint8List? signedPdf;

  /// Proof of the signing (who, account, when, device, fingerprints).
  SignatureAudit? audit;

  /// How many times the admin asked for another signature.
  int revision = 0;

  /// The admin's reason when asking to sign again.
  String? note;

  bool get isSignRequest => docTitle != null;

  /// A file sent in the chat (a PDF such as a contract), not for signing.
  bool get isFile => docTitle == null && (fileBytes != null || fileName != null);

  /// Whether it reached the server (always sent in the demo).
  Delivery delivery = Delivery.sent;
}

/// Private chat between each tenant and management. One thread per tenant,
/// keyed by tenant name. Kept in memory for now; the screens only use this
/// class, so a real backend can replace it later.
class ChatState extends ChangeNotifier {
  final Map<String, List<ChatMessage>> _threads = demoData
      ? {
          'Juan Dela Cruz': [
            ChatMessage(
              id: 'c1',
              from: ChatSender.tenant,
              time: DateTime(2026, 10, 18, 9, 12),
              text: 'Good morning! Is there an available parking slot for guests this weekend?',
            ),
            ChatMessage(
              id: 'c2',
              from: ChatSender.admin,
              time: DateTime(2026, 10, 18, 9, 40),
              text: 'Yes, Slot B-12 is reserved for Oct 24-25. Pass issued.',
            ),
          ],
          'Grace Santos': [
            ChatMessage(
              id: 'c3',
              from: ChatSender.tenant,
              time: DateTime(2026, 10, 25, 17, 5),
              text: 'Can we get a bike rack near the entrance?',
            ),
          ],
        }
      : {};

  /// Last time each side opened a thread: 'tenant|Name' or 'admin|Name'.
  final Map<String, DateTime> _lastRead = demoData
      ? {'tenant|Juan Dela Cruz': DateTime(2026, 10, 19)}
      : {};

  int _next = 100;

  /// Every thread, by tenant name (read only; for saving).
  Map<String, List<ChatMessage>> get threads => Map.unmodifiable(_threads);

  /// When each side last opened each thread (read only; for saving).
  Map<String, DateTime> get lastRead => Map.unmodifiable(_lastRead);

  /// Puts in the threads and read times loaded from the database.
  void replaceAll(
    Map<String, List<ChatMessage>> threads,
    Map<String, DateTime> reads,
  ) {
    _threads
      ..clear()
      ..addAll(threads);
    _lastRead
      ..clear()
      ..addAll(reads);
    notifyListeners();
  }

  List<ChatMessage> messages(String tenant) => _threads[tenant] ?? const [];

  ChatMessage? lastMessage(String tenant) {
    final m = messages(tenant);
    return m.isEmpty ? null : m.last;
  }

  /// Messages from the other side that [me] has not opened yet.
  int unread(ChatSender me, String tenant) {
    final read = _lastRead['${me.name}|$tenant'];
    return messages(tenant)
        .where((m) => m.from != me && (read == null || m.time.isAfter(read)))
        .length;
  }

  void markRead(ChatSender me, String tenant) {
    final last = lastMessage(tenant);
    if (last == null) return;
    final key = '${me.name}|$tenant';
    final prev = _lastRead[key];
    if (prev != null && !last.time.isAfter(prev)) return;
    _lastRead[key] = last.time;
    notifyListeners();
  }

  ChatMessage _add(String tenant, ChatMessage m) {
    (_threads[tenant] ??= []).add(m);
    notifyListeners();
    return m;
  }

  String get _id => 'c${_next++}';

  /// On when messages are saved to a server, so new ones start as
  /// "Sending…" until it confirms them.
  bool trackDelivery = false;

  /// Marks whether [m] reached the server.
  void setDelivery(ChatMessage m, Delivery d) {
    if (m.delivery == d) return;
    m.delivery = d;
    notifyListeners();
  }

  /// Tries a message that failed again.
  void retry(ChatMessage m) => setDelivery(m, Delivery.sending);

  /// A message that arrived from the server (sent on the other phone).
  void receive(String tenant, ChatMessage m) {
    _add(tenant, m);
  }

  /// Puts [replacement] where [old] was in [tenant]'s thread.
  void swap(String tenant, ChatMessage old, ChatMessage replacement) {
    final list = _threads[tenant];
    final i = list?.indexOf(old) ?? -1;
    if (i < 0) return;
    list![i] = replacement;
    notifyListeners();
  }

  /// Older messages of [tenant] loaded on request, placed before the rest.
  void prependOlder(String tenant, List<ChatMessage> older) {
    if (older.isEmpty) return;
    (_threads[tenant] ??= []).insertAll(0, older);
    notifyListeners();
  }

  /// Redraws after a message changed (e.g. signed on the other phone).
  void touch() => notifyListeners();

  void send(
    String tenant,
    ChatSender from, {
    String? text,
    Uint8List? image,
    String? fileName,
    Uint8List? fileBytes,
  }) {
    final t = text?.trim();
    if ((t == null || t.isEmpty) && image == null && fileBytes == null) return;
    _add(
      tenant,
      ChatMessage(
        id: _id,
        from: from,
        time: DateTime.now(),
        text: t?.isEmpty == true ? null : t,
        image: image,
        fileName: fileBytes == null ? null : fileName,
        fileBytes: fileBytes,
      )..delivery = trackDelivery ? Delivery.sending : Delivery.sent,
    );
  }

  /// Admin asks the tenant to sign a document.
  void requestSignature(
    String tenant,
    String title, {
    Uint8List? image,
    String? fileName,
    Uint8List? fileBytes,
  }) {
    _add(
      tenant,
      ChatMessage(
        id: _id,
        from: ChatSender.admin,
        time: DateTime.now(),
        docTitle: title,
        image: image,
        fileName: fileName,
        fileBytes: fileBytes,
      ),
    );
  }

  /// A PDF the tenant picked from their phone, ready to sign. It joins the
  /// chat only once it has been signed (see [sign]).
  ChatMessage draftPdf(String fileName, Uint8List bytes) => ChatMessage(
    id: _id,
    from: ChatSender.tenant,
    time: DateTime.now(),
    docTitle: fileName.replaceFirst(
      RegExp(r'\.pdf$', caseSensitive: false),
      '',
    ),
    fileName: fileName,
    fileBytes: bytes,
  );

  bool _inThread(String tenant, ChatMessage m) => messages(tenant).contains(m);

  /// Tenant signs (or signs again). A tenant's own PDF is sent to the chat now.
  void sign(
    String tenant,
    ChatMessage m,
    Uint8List signature, {
    Uint8List? signedPdf,
    SignatureAudit? audit,
  }) {
    if (m.sign == SignStatus.completed) return; // locked once accepted
    m
      ..signature = signature
      ..signedPdf = signedPdf
      ..audit = audit
      ..signedAt = DateTime.now()
      ..sign = SignStatus.signed;
    if (!_inThread(tenant, m)) {
      _add(tenant, m);
    } else {
      notifyListeners();
    }
  }

  /// Admin accepts the signed document.
  void complete(ChatMessage m) {
    m.sign = SignStatus.completed;
    notifyListeners();
  }

  /// Admin sends it back for another signature.
  ///
  /// Not possible once accepted: the signed copy is then locked.
  void requestAgain(String tenant, ChatMessage m, String note) {
    if (m.sign == SignStatus.completed) return;
    m
      ..audit = null
      ..sign = SignStatus.awaiting
      ..signature = null
      ..signedPdf = null
      ..signedAt = null
      ..revision += 1
      ..note = note.trim().isEmpty ? null : note.trim();
    notifyListeners();
  }
}

final chatState = ChatState();
