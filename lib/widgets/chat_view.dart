import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../admin/admin_state.dart' show adminState;
import '../state/backend.dart';
import '../state/sync.dart' show Sync;
import '../state/chat_state.dart';
import '../theme.dart';
import 'common.dart';
import 'signed_document.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _time(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
}

/// When a message was sent: "3:42 PM" today, "Yesterday 3:42 PM", and
/// from 2 days back the date too: "Nov 16, 3:42 PM" (with the year when
/// it is not this year: "Dec 28, 2025, 3:42 PM").
String _stampLabel(DateTime d) {
  final label = _dayLabel(d);
  if (label == 'Today') return _time(d);
  if (label == 'Yesterday') return 'Yesterday ${_time(d)}';
  final day = d.year == DateTime.now().year
      ? '${_months[d.month - 1]} ${d.day}'
      : label;
  return '$day, ${_time(d)}';
}

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  bool same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  if (same(d, now)) return 'Today';
  if (same(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

/// One tenant's private chat with management. Used by the tenant app (me =
/// tenant) and by the admin app (me = admin), so both look the same.
class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.tenant,
    required this.me,
    this.active = true,
  });

  /// Whose thread this is.
  final String tenant;
  final ChatSender me;

  /// False while the chat is on a hidden tab, so messages stay unread.
  final bool active;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    // This chat's photos and files download now (not at login).
    Sync.fetchChat(widget.tenant);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _markRead() {
    if (!widget.active) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) chatState.markRead(widget.me, widget.tenant);
    });
  }

  void _send() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    chatState.send(widget.tenant, widget.me, text: t);
    _text.clear();
  }

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _SheetTile(
              Icons.photo_camera_outlined,
              'Take a photo',
              () => popOnce(ctx, 'camera'),
            ),
            _SheetTile(
              Icons.photo_library_outlined,
              'Choose from gallery',
              () => popOnce(ctx, 'gallery'),
            ),
            _SheetTile(
              Icons.attach_file_rounded,
              'Send a PDF file',
              () => popOnce(ctx, 'file'),
            ),
            if (widget.me == ChatSender.admin)
              _SheetTile(
                Icons.draw_outlined,
                'Request a signature',
                () => popOnce(ctx, 'sign'),
              )
            else
              _SheetTile(
                Icons.picture_as_pdf_outlined,
                'Sign a PDF',
                () => popOnce(ctx, 'pdf'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'sign') {
      showAppSheet(
        context,
        title: 'Request a signature',
        builder: (_) => _SignRequestForm(widget.tenant),
      );
      return;
    }
    if (choice == 'file') {
      final pdf = await pickPdf(context);
      if (pdf == null || !mounted) return;
      chatState.send(
        widget.tenant,
        widget.me,
        fileName: pdf.$1,
        fileBytes: pdf.$2,
      );
      return;
    }
    if (choice == 'pdf') {
      final pdf = await pickPdf(context);
      if (pdf == null || !mounted) return;
      final draft = chatState.draftPdf(pdf.$1, pdf.$2);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SignScreen(draft, tenant: widget.tenant),
        ),
      );
      return;
    }
    final bytes = await pickPhoto(
      context,
      choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
    );
    if (bytes != null) chatState.send(widget.tenant, widget.me, image: bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: LoadingSwitch(
            skeleton: const SkeletonChat(),
            child: ListenableBuilder(
              listenable: chatState,
              builder: (context, _) {
                _markRead();
                final list = chatState.messages(widget.tenant);
                if (list.isEmpty) {
                  return Center(
                    child: SingleChildScrollView(
                      child: EmptyState(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'No messages yet',
                        message: widget.me == ChatSender.tenant
                            ? 'Say hello to management. Questions, photos and documents all go here.'
                            : 'Start the conversation with ${widget.tenant}.',
                      ),
                    ),
                  );
                }
                final rows = <Widget>[];
                // "Sent" shows under my latest message only, like Messenger.
                final latestMine = list.lastIndexWhere(
                  (m) => !m.isSignRequest && m.from == widget.me,
                );
                // Messages from the same person within 5 minutes read as one
                // group: tighter spacing, and only the last one shows the time
                // and the bubble tail.
                bool sameDay(DateTime a, DateTime b) =>
                    a.year == b.year && a.month == b.month && a.day == b.day;
                bool grouped(ChatMessage a, ChatMessage b) =>
                    !a.isSignRequest &&
                    !b.isSignRequest &&
                    a.from == b.from &&
                    sameDay(a.time, b.time) &&
                    b.time.difference(a.time).inMinutes < 5;
                for (var i = 0; i < list.length; i++) {
                  final m = list[i];
                  final before = i > 0 ? list[i - 1] : null;
                  final after = i < list.length - 1 ? list[i + 1] : null;
                  // Like Messenger: a time label above the first message, and
                  // again whenever 10 minutes or more have passed since the
                  // message before (or a new day starts).
                  if (before == null ||
                      !sameDay(before.time, m.time) ||
                      m.time.difference(before.time).inMinutes >= 10) {
                    rows.add(_DayChip(_stampLabel(m.time)));
                  }
                  rows.add(
                    m.isSignRequest
                        ? _SignCard(m, widget.me, widget.tenant)
                        : _Bubble(
                            m,
                            mine: m.from == widget.me,
                            first:
                                before == null ||
                                !grouped(before, m) ||
                                !sameDay(before.time, m.time),
                            last: after == null || !grouped(m, after),
                            status: m.from != widget.me
                                ? null
                                : m.delivery != Delivery.sent
                                ? m.delivery
                                : i == latestMine
                                ? Delivery.sent
                                : null,
                          ),
                  );
                }
                // Older messages load on request (the latest ones come first).
                if (Sync.hasOlder(widget.tenant)) {
                  rows.insert(0, _LoadEarlier(widget.tenant));
                }
                return ListView(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  children: rows.reversed.toList(),
                );
              },
            ),
          ),
        ),
        _Composer(controller: _text, onSend: _send, onAttach: _attach),
      ],
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: IconBadge(icon, size: 34),
    title: Text(
      label,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        color: AppColors.green800,
      ),
    ),
    onTap: onTap,
  );
}

/// Asks "Take a photo or choose from gallery?" and returns the picked photo,
/// or null if cancelled.
Future<Uint8List?> choosePhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          _SheetTile(
            Icons.photo_camera_outlined,
            'Take a photo',
            () => popOnce(ctx, ImageSource.camera),
          ),
          _SheetTile(
            Icons.photo_library_outlined,
            'Choose from gallery',
            () => popOnce(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;
  return pickPhoto(context, source);
}

/// For uploading a document: take a photo, choose one from the gallery, or
/// pick a PDF. Returns (file name, bytes), or null if cancelled.
Future<(String, Uint8List)?> chooseDocument(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          _SheetTile(
            Icons.photo_camera_outlined,
            'Take a photo',
            () => popOnce(ctx, 'camera'),
          ),
          _SheetTile(
            Icons.photo_library_outlined,
            'Choose from gallery',
            () => popOnce(ctx, 'gallery'),
          ),
          _SheetTile(
            Icons.picture_as_pdf_outlined,
            'Choose a PDF',
            () => popOnce(ctx, 'pdf'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return null;
  if (choice == 'pdf') return pickPdf(context);
  final bytes = await pickPhoto(
    context,
    choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
  );
  return bytes == null ? null : ('Photo.jpg', bytes);
}

/// Picks one PDF from the phone. Returns (file name, bytes), or null.
Future<(String, Uint8List)?> pickPdf(BuildContext context) async {
  try {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (files.isEmpty) return null;
    final f = files.first;
    final bytes = await f.xFile.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      if (context.mounted) {
        toast(context, 'That PDF is over 10 MB. Please pick a smaller file.');
      }
      return null;
    }
    return (f.name, bytes);
  } catch (_) {
    if (context.mounted) toast(context, 'Could not open the file picker.');
    return null;
  }
}

String fileSizeLabel(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).ceil()} KB';

/// A PDF attachment: red PDF badge, file name and size.
class PdfTile extends StatelessWidget {
  const PdfTile({
    super.key,
    required this.name,
    required this.size,
    this.trailing,
  });
  final String name;
  final int size;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'PDF',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: AppColors.red,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.green800,
                  ),
                ),
                Text(
                  'PDF · ${fileSizeLabel(size)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.slate500,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Takes a photo or picks one from the gallery. Returns null if cancelled.
Future<Uint8List?> pickPhoto(BuildContext context, ImageSource source) async {
  try {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 80,
    );
    return file == null ? null : await file.readAsBytes();
  } catch (_) {
    if (context.mounted) toast(context, 'Could not open the photo picker.');
    return null;
  }
}

// ---------------------------------------------------------------- Composer

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onAttach,
  });
  final TextEditingController controller;
  final VoidCallback onSend, onAttach;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.greenDeep,
        border: Border(
          top: BorderSide(color: AppColors.gold500.withValues(alpha: .3)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          PressScale(
            scale: .86,
            child: IconButton(
              tooltip: 'Attach',
              onPressed: onAttach,
              icon: const Icon(
                Icons.add_circle_outline_rounded,
                color: AppColors.gold400,
                size: 28,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 14.5, color: AppColors.green800),
              decoration: InputDecoration(
                hintText: 'Message',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PressScale(
            scale: .88,
            child: GestureDetector(
              onTap: onSend,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  gradient: goldGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.send_rounded,
                  size: 21,
                  color: AppColors.green900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Bubbles

class _DayChip extends StatelessWidget {
  const _DayChip(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.slate300,
        ),
      ),
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble(
    this.m, {
    required this.mine,
    this.first = true,
    this.last = true,
    this.status,
  });
  final ChatMessage m;
  final bool mine;

  /// "Sending…", "Sent" or "Not sent" under my message; null for none.
  final Delivery? status;

  /// First / last bubble of a run from the same person.
  final bool first, last;

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width * .78;
    final fg = mine ? AppColors.green900 : AppColors.green800;
    final s = status;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: EdgeInsets.only(top: first ? 10 : 2),
            constraints: BoxConstraints(maxWidth: maxW.clamp(0, 420)),
            padding: EdgeInsets.all(
              m.image != null || Sync.waiting(m, 'image') ? 4 : 0,
            ),
            decoration: BoxDecoration(
              gradient: mine ? goldGradient : null,
              color: mine ? null : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(mine || !last ? 18 : 4),
                bottomRight: Radius.circular(mine && last ? 4 : 18),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Still downloading: a grey box where the photo goes.
                if (m.image == null && Sync.waiting(m, 'image'))
                  Container(
                    width: 240,
                    height: 220,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.slate100,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.gold600,
                      ),
                    ),
                  ),
                if (m.image != null)
                  GestureDetector(
                    onTap: () => showImageViewer(context, m.image!),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(
                        m.image!,
                        fit: BoxFit.cover,
                        width: 240,
                        height: 220,
                      ),
                    ),
                  ),
                if (m.isFile)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      // Downloaded the first time it is opened.
                      if (m.fileBytes == null) await Sync.fetch([m]);
                      if (!context.mounted) return;
                      if (m.fileBytes == null) {
                        toast(
                          context,
                          'Could not open the file. Check your internet connection.',
                        );
                        return;
                      }
                      showPdf(context, m.fileBytes!, m.fileName ?? 'File');
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 14, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: mine
                                  ? Colors.white.withValues(alpha: .45)
                                  : AppColors.amberBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.picture_as_pdf_rounded,
                              color: Color(0xFFD9534F),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  m.fileName ?? 'File.pdf',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: fg,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${fileSizeLabel(m.fileSize)} · Tap to open',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: fg.withValues(alpha: .7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (m.text != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _LinkText(
                        m.text!,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.35,
                          color: fg,
                        ),
                        linkColor: mine
                            ? AppColors.green900
                            : AppColors.emerald,
                      ),
                    ),
                  ),
                if (last)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      3,
                      m.image != null && m.text == null ? 10 : 14,
                      m.image != null ? 4 : 8,
                    ),
                    child: Text(
                      _stampLabel(m.time),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: fg.withValues(alpha: .65),
                      ),
                    ),
                  )
                else if (m.text != null || m.isFile)
                  const SizedBox(height: 10),
              ],
            ),
          ),
          if (s != null)
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 4),
              child: s == Delivery.failed
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => chatState.retry(m),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 13,
                            color: Color(0xFFEF8A80),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Not sent · Tap to retry',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFEF8A80),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Text(
                      s == Delivery.sending ? 'Sending…' : 'Sent',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.slate300,
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Text where web links can be tapped.
class _LinkText extends StatefulWidget {
  const _LinkText(this.text, {required this.style, required this.linkColor});
  final String text;
  final TextStyle style;
  final Color linkColor;
  @override
  State<_LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<_LinkText> {
  static final _url = RegExp(
    r'(https?://[^\s]+|www\.[^\s]+)',
    caseSensitive: false,
  );
  final _taps = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(
      url.toLowerCase().startsWith('http') ? url : 'https://$url',
    );
    var ok = false;
    if (uri != null) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (!ok && mounted) toast(context, 'Could not open the link.');
  }

  @override
  Widget build(BuildContext context) {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final spans = <InlineSpan>[];
    var at = 0;
    for (final match in _url.allMatches(widget.text)) {
      var link = match.group(0)!;
      // Punctuation at the end of a sentence is not part of the link.
      final trimmed = link.replaceFirst(RegExp(r'[.,;:!?)]+$'), '');
      final end = match.start + trimmed.length;
      link = trimmed;
      if (match.start > at) {
        spans.add(TextSpan(text: widget.text.substring(at, match.start)));
      }
      final tap = TapGestureRecognizer()..onTap = () => _open(link);
      _taps.add(tap);
      spans.add(
        TextSpan(
          text: link,
          recognizer: tap,
          style: TextStyle(
            color: widget.linkColor,
            decoration: TextDecoration.underline,
            decorationColor: widget.linkColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      at = end;
    }
    if (at < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(at)));
    }
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}

void showImageViewer(BuildContext context, Uint8List bytes) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(child: InteractiveViewer(child: Image.memory(bytes))),
      ),
    ),
  );
}

// -------------------------------------------------------------- Sign request

class _SignCard extends StatelessWidget {
  const _SignCard(this.m, this.me, this.tenant);
  final ChatMessage m;
  final ChatSender me;
  final String tenant;

  @override
  Widget build(BuildContext context) {
    final mine = m.from == me;
    final isTenant = me == ChatSender.tenant;
    final maxW = (MediaQuery.sizeOf(context).width * .86).clamp(0.0, 440.0);
    final status = m.sign!;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: maxW),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.gold500.withValues(alpha: .6)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconBadge(Icons.draw_outlined, size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.from == ChatSender.tenant
                            ? 'SIGNED BY TENANT'
                            : 'DOCUMENT TO SIGN',
                        style: const TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                          color: AppColors.gold700,
                        ),
                      ),
                      Text(
                        m.docTitle!,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.green800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (m.fileName != null) ...[
              const SizedBox(height: 10),
              PdfTile(name: m.fileName!, size: m.fileSize),
            ],
            if (m.image != null) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => showImageViewer(context, m.image!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    m.image!,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
            if (m.revision > 0 &&
                m.note != null &&
                status == SignStatus.awaiting) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.amberBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Please sign again: ${m.note}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.amber,
                  ),
                ),
              ),
            ],
            if (m.signature != null) ...[
              const SizedBox(height: 10),
              Container(
                height: 64,
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.slate50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Image.memory(m.signature!, fit: BoxFit.contain),
              ),
            ],
            // The signed copy: the document with the signature on its page.
            if (m.signedPdf != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  foregroundColor: AppColors.green800,
                  side: const BorderSide(color: AppColors.gold500),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () =>
                    showPdf(context, m.signedPdf!, '${m.docTitle} (signed)'),
                icon: const Icon(
                  Icons.picture_as_pdf_rounded,
                  size: 18,
                  color: AppColors.gold700,
                ),
                label: const Text(
                  'Open signed PDF',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
            // Proof of signing, and whether the signed file is still exactly
            // as it was signed (its fingerprint matches the one on record).
            if (m.audit case final a? when status != SignStatus.awaiting) ...[
              const SizedBox(height: 8),
              _AuditBox(m, a, locked: status == SignStatus.completed),
            ],
            // Admin: keep a copy on this device, and once accepted, make it
            // the tenant's contract (what they see under My Contract).
            if (!isTenant &&
                m.signedPdf != null &&
                status != SignStatus.awaiting) ...[
              const SizedBox(height: 8),
              _AdminDocActions(
                m,
                tenant,
                accepted: status == SignStatus.completed,
              ),
            ],
            const SizedBox(height: 10),
            if (isTenant && status == SignStatus.awaiting)
              GoldButton(
                label: m.revision > 0 ? 'Sign again' : 'Review & sign',
                icon: Icons.draw_outlined,
                compact: true,
                onPressed: () async {
                  // The document must be here before signing.
                  if (m.fileBytes == null && m.image == null) {
                    await Sync.fetch([m]);
                  }
                  if (!context.mounted) return;
                  if (m.fileBytes == null && m.image == null) {
                    toast(
                      context,
                      'Could not open the document. Check your internet connection.',
                    );
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SignScreen(m, tenant: tenant),
                    ),
                  );
                },
              )
            else if (!isTenant && status == SignStatus.signed)
              Row(
                children: [
                  Expanded(
                    child: GoldButton(
                      label: 'Accept',
                      icon: Icons.check_rounded,
                      compact: true,
                      onPressed: () {
                        chatState.complete(m);
                        toast(context, 'Marked as signed and accepted');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.green800,
                        side: const BorderSide(color: AppColors.gold600),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => showAppSheet(
                        context,
                        title: 'Ask to sign again',
                        builder: (_) => _AgainForm(tenant, m),
                      ),
                      child: const Text(
                        'Sign again',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: switch (status) {
                  SignStatus.awaiting => Pill.pending(
                    m.revision > 0
                        ? 'WAITING FOR NEW SIGNATURE'
                        : 'WAITING FOR SIGNATURE',
                  ),
                  SignStatus.signed => Pill.info('SIGNED, WAITING FOR REVIEW'),
                  SignStatus.completed => Pill.verified('SIGNED AND ACCEPTED'),
                },
              ),
            const SizedBox(height: 6),
            Text(
              m.signedAt != null && status != SignStatus.awaiting
                  ? 'Signed ${_dayLabel(m.signedAt!)}, ${_time(m.signedAt!)}'
                  : _stampLabel(m.time),
              style: const TextStyle(fontSize: 10.5, color: AppColors.slate400),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgainForm extends StatefulWidget {
  const _AgainForm(this.tenant, this.m);
  final String tenant;
  final ChatMessage m;
  @override
  State<_AgainForm> createState() => _AgainFormState();
}

class _AgainFormState extends State<_AgainForm> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('What should they fix? (optional)'),
        TextField(
          controller: _note,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'e.g. Please sign inside the box',
          ),
        ),
        const SizedBox(height: 16),
        GoldButton(
          label: 'Send request',
          onPressed: () {
            chatState.requestAgain(widget.tenant, widget.m, _note.text);
            popOnce(context);
            toast(context, 'Asked the tenant to sign again');
          },
        ),
      ],
    );
  }
}

class _SignRequestForm extends StatefulWidget {
  const _SignRequestForm(this.tenant);
  final String tenant;
  @override
  State<_SignRequestForm> createState() => _SignRequestFormState();
}

class _SignRequestFormState extends State<_SignRequestForm> {
  final _title = TextEditingController();
  Uint8List? _photo;
  Uint8List? _pdf;
  String? _pdfName;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource s) async {
    final b = await pickPhoto(context, s);
    if (b != null && mounted) setState(() => _photo = b);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Document name'),
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Lease agreement'),
        ),
        const SizedBox(height: 12),
        const FieldLabel('The document (PDF or photo)'),
        if (_pdfName != null)
          PdfTile(
            name: _pdfName!,
            size: _pdf!.length,
            trailing: IconButton(
              tooltip: 'Remove',
              onPressed: () => setState(() {
                _pdf = null;
                _pdfName = null;
              }),
              icon: const Icon(
                Icons.close,
                size: 18,
                color: AppColors.slate500,
              ),
            ),
          )
        else if (_photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(
              _photo!,
              height: 150,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        Wrap(
          children: [
            TextButton.icon(
              onPressed: () async {
                final pdf = await pickPdf(context);
                if (pdf != null && mounted) {
                  setState(() {
                    _pdfName = pdf.$1;
                    _pdf = pdf.$2;
                    if (_title.text.trim().isEmpty) {
                      _title.text = pdf.$1.replaceFirst(
                        RegExp(r'\.pdf$', caseSensitive: false),
                        '',
                      );
                    }
                  });
                }
              },
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('PDF file'),
            ),
            TextButton.icon(
              onPressed: () => _pick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('Take photo'),
            ),
            TextButton.icon(
              onPressed: () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Gallery'),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.red, fontSize: 12.5),
            ),
          ),
        GoldButton(
          label: 'Send to tenant',
          icon: Icons.send_rounded,
          onPressed: () {
            final t = _title.text.trim();
            if (t.isEmpty) {
              setState(() => _error = 'Enter a document name');
              return;
            }
            chatState.requestSignature(
              widget.tenant,
              t,
              image: _pdf == null ? _photo : null,
              fileName: _pdfName,
              fileBytes: _pdf,
            );
            popOnce(context);
            toast(context, 'Signature request sent');
          },
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- Sign screen

/// Where the document is signed: its real pages are shown, the signer draws
/// a signature, places it on the page (drag it, or tap another spot or page),
/// and a signed PDF of the whole document is made and sent to the chat.
class SignScreen extends StatefulWidget {
  const SignScreen(this.message, {super.key, required this.tenant});
  final ChatMessage message;

  /// Whose chat the signed document goes to (also the signer's name).
  final String tenant;
  @override
  State<SignScreen> createState() => _SignScreenState();
}

class _SignScreenState extends State<SignScreen> {
  final _pad = SignatureController();
  late final Future<List<Uint8List>> _pages = documentPages(
    pdf: widget.message.fileBytes,
    photo: widget.message.image,
  );

  /// The drawn signature (PNG) once the signer taps Done, and its shape.
  Uint8List? _sig;
  double _sigAspect = 2;

  /// Every spot the signature goes (one per page that needs signing, or
  /// several), and the one being moved or resized.
  final List<SignaturePlacement> _spots = [];
  int _sel = 0;
  SignaturePlacement? get _at =>
      _spots.isEmpty ? null : _spots[_sel.clamp(0, _spots.length - 1)];

  /// Puts the signature on every page that doesn't have it yet, in the same
  /// spot and size as the selected one.
  void _signEveryPage(int pageCount) {
    final at = _at;
    if (at == null) return;
    setState(() {
      for (var p = 0; p < pageCount; p++) {
        if (_spots.any((s) => s.page == p)) continue;
        _spots.add(
          SignaturePlacement(
            page: p,
            left: at.left,
            top: at.top,
            width: at.width,
          ),
        );
      }
    });
  }

  /// Each page decoded once (for its shape), so dragging doesn't flicker.
  final Map<int, Future<ui.Image>> _decoded = {};

  bool _agree = false;
  bool _dragging = false;
  bool _busy = false;

  @override
  void dispose() {
    _pad.dispose();
    super.dispose();
  }

  /// Opens the pad; the signature lands on the last page, bottom right,
  /// unless the signer already placed it somewhere.
  Future<void> _draw(int pageCount) async {
    _pad.clear();
    final ok = await showAppSheet<bool>(
      context,
      title: 'Draw your signature',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SignaturePad(controller: _pad),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton(onPressed: _pad.clear, child: const Text('Clear')),
              const Spacer(),
              ListenableBuilder(
                listenable: _pad,
                builder: (_, _) => GoldButton(
                  label: 'Done',
                  icon: Icons.check_rounded,
                  expand: false,
                  onPressed: _pad.isEmpty ? null : () => popOnce(ctx, true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (ok != true) return;
    final png = await _pad.export();
    if (png == null || !mounted) return;
    setState(() {
      _sig = png;
      _sigAspect = _pad.size.width / _pad.size.height;
      if (_spots.isEmpty) {
        _spots.add(
          SignaturePlacement(
            page: (pageCount - 1).clamp(0, 999),
            left: .56,
            top: .80,
          ),
        );
        _sel = 0;
      }
    });
  }

  /// Asks the signer for their password again, so only the account owner
  /// can sign (not whoever is holding the phone). True when it matches.
  Future<bool> _confirmIdentity() async {
    final account = adminState.tenants
        .where((t) => t.name == widget.tenant)
        .firstOrNull;
    if (account == null) return true; // no account on record (demo data)
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _PasswordDialog(
        username: account.username,
        password: account.password,
      ),
    );
    // Close the keyboard cleanly before the next screen.
    FocusManager.instance.primaryFocus?.unfocus();
    return ok ?? false;
  }

  Future<void> _submit(List<Uint8List> pages) async {
    final sig = _sig;
    if (sig == null || _spots.isEmpty) return;
    if (!await _confirmIdentity() || !mounted) return;
    setState(() => _busy = true);
    // The time on the document comes from the server, never the phone.
    final DateTime now;
    try {
      now = await trustedNow();
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        toast(
          context,
          'Could not reach the server to time-stamp your signature. Check your internet connection and try again.',
        );
      }
      return;
    }
    try {
      final m = widget.message;
      final account =
          adminState.tenants
              .where((t) => t.name == widget.tenant)
              .firstOrNull
              ?.username ??
          '';
      final device = signingDevice();
      // Fingerprint of the document exactly as it was sent.
      final original = m.fileBytes ?? m.image;
      final originalHash = original == null ? '' : fingerprint(original);
      final pdf = pages.isEmpty
          ? null
          : await buildSignedPdf(
              pages: pages,
              signature: sig,
              signatureAspect: _sigAspect,
              spots: _spots,
              signer: widget.tenant,
              when: now,
              title: m.docTitle ?? 'Document',
              account: account,
              device: device,
              originalHash: originalHash,
            );
      if (!mounted) return;
      // The signed file's own fingerprint is kept on record (with the
      // backend: on the server), so any later edit to it shows.
      final audit = SignatureAudit(
        signer: widget.tenant,
        account: account,
        signedAt: now,
        device: device,
        originalHash: originalHash,
        signedHash: pdf == null ? '' : fingerprint(pdf),
      );
      chatState.sign(widget.tenant, m, sig, signedPdf: pdf, audit: audit);
      popOnce(context);
      toast(context, 'Signed document sent');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, "Couldn't make the signed copy. Please try again.");
      }
    }
  }

  /// One page, with the signature on it when it is placed there. Tapping
  /// the page moves the signature to that spot.
  Widget _page(Uint8List png, int index) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return FutureBuilder<ui.Image>(
          future: _decoded.putIfAbsent(index, () => decodeImageFromList(png)),
          builder: (context, snap) {
            final img = snap.data;
            final h = img == null ? w * 1.414 : w * img.height / img.width;
            // The signature spots on this page.
            final mine = [
              for (var j = 0; j < _spots.length; j++)
                if (_spots[j].page == index) j,
            ];
            final here = _sig != null && mine.isNotEmpty;
            return GestureDetector(
              // Tap a page: move this page's signature there, or add one
              // to a page that has none yet.
              onTapUp: _sig == null
                  ? null
                  : (d) => setState(() {
                      final size = _at?.width ?? .34;
                      final sw = size * w;
                      final left = ((d.localPosition.dx - sw / 2) / w).clamp(
                        0.0,
                        1 - size,
                      );
                      final top =
                          ((d.localPosition.dy - sw / _sigAspect / 2) / h)
                              .clamp(0.0, .97);
                      if (mine.isNotEmpty) {
                        _sel = mine.first;
                        _spots[_sel]
                          ..left = left
                          ..top = top;
                      } else {
                        _spots.add(
                          SignaturePlacement(
                            page: index,
                            left: left,
                            top: top,
                            width: size,
                          ),
                        );
                        _sel = _spots.length - 1;
                      }
                    }),
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: here ? AppColors.gold500 : AppColors.slate200,
                    width: here ? 2 : 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Image.memory(
                        png,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                      ),
                    ),
                    for (final j in mine) _spot(_spots[j], j, w, h),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// One placed signature: drag it to move it (the list stops scrolling
  /// meanwhile), tap it to pick it for resizing, × to take it off this page
  /// (when it is on more than one).
  Widget _spot(SignaturePlacement at, int j, double w, double h) {
    final selected = j == _sel;
    return Positioned(
      left: at.left * w,
      top: at.top * h,
      child: Listener(
        onPointerDown: (_) => setState(() {
          _dragging = true;
          _sel = j;
        }),
        onPointerUp: (_) => setState(() => _dragging = false),
        onPointerCancel: (_) => setState(() => _dragging = false),
        onPointerMove: (e) => setState(() {
          at.left = (at.left + e.delta.dx / w).clamp(0.0, 1 - at.width);
          at.top = (at.top + e.delta.dy / h).clamp(0.0, .97);
        }),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: at.width * w,
              height: at.width * w / _sigAspect,
              decoration: BoxDecoration(
                color: AppColors.gold400.withValues(
                  alpha: selected ? .18 : .08,
                ),
                border: Border.all(
                  color: AppColors.gold600,
                  width: selected ? 1.8 : 1,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Image.memory(_sig!, fit: BoxFit.contain),
            ),
            if (_spots.length > 1)
              Positioned(
                right: -10,
                top: -10,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _spots.removeAt(j);
                    if (_sel >= _spots.length) {
                      _sel = _spots.length - 1;
                    }
                  }),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: AppColors.green800,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.green800,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          m.docTitle ?? 'Sign document',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<List<Uint8List>>(
          future: _pages,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
                      'Opening the document...',
                      style: TextStyle(color: AppColors.slate300),
                    ),
                  ],
                ),
              );
            }
            final pages = snap.data ?? const <Uint8List>[];
            return Column(
              children: [
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: ListView(
                        physics: _dragging
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        children: [
                          if (m.revision > 0 && m.note != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.amberBg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Management asked: ${m.note}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.amber,
                                  ),
                                ),
                              ),
                            ),
                          Text(
                            _sig == null
                                ? 'Read the document, then tap Sign to draw your signature.'
                                : pages.length > 1
                                ? 'Drag your signature to where it goes. Tap another page to sign it there too, or use Sign every page. × removes one.'
                                : 'Drag your signature to where it goes, or tap a spot on the page to move it there.',
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: AppColors.slate300,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (pages.isEmpty)
                            AppCard(
                              child: const Text(
                                'This document could not be shown. You can still sign it.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.slate500,
                                ),
                              ),
                            ),
                          for (var i = 0; i < pages.length; i++) ...[
                            _page(pages[i], i),
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 6,
                                bottom: 14,
                              ),
                              child: Text(
                                'Page ${i + 1} of ${pages.length}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.slate300,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                // Signing controls stay at the bottom.
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 12,
                        offset: Offset(0, -3),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_sig != null && _at != null)
                            Row(
                              children: [
                                const Icon(
                                  Icons.photo_size_select_small_rounded,
                                  size: 18,
                                  color: AppColors.slate500,
                                ),
                                Expanded(
                                  child: Slider(
                                    value: _at!.width,
                                    min: .16,
                                    max: .6,
                                    activeColor: AppColors.gold600,
                                    onChanged: (v) => setState(() {
                                      _at!.width = v;
                                      if (_at!.left > 1 - v) _at!.left = 1 - v;
                                    }),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _draw(pages.length),
                                  child: const Text(
                                    'Redraw',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          // Several pages: show where it is signed, and sign
                          // all of them in one tap.
                          if (_sig != null && pages.length > 1)
                            Row(
                              children: [
                                const Icon(
                                  Icons.layers_outlined,
                                  size: 17,
                                  color: AppColors.slate500,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Signed on ${_spots.map((s) => s.page).toSet().length} of ${pages.length} pages',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.slate600,
                                    ),
                                  ),
                                ),
                                if (_spots.map((s) => s.page).toSet().length <
                                    pages.length)
                                  TextButton(
                                    onPressed: () =>
                                        _signEveryPage(pages.length),
                                    child: const Text(
                                      'Sign every page',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          InkWell(
                            onTap: () => setState(() => _agree = !_agree),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _agree,
                                  activeColor: AppColors.gold600,
                                  onChanged: (v) =>
                                      setState(() => _agree = v ?? false),
                                ),
                                const Expanded(
                                  child: Text(
                                    'I have read this document and agree to sign it.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.slate600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          _sig == null
                              ? GoldButton(
                                  label: 'Sign',
                                  icon: Icons.draw_outlined,
                                  onPressed: () => _draw(pages.length),
                                )
                              : GoldButton(
                                  label: _busy
                                      ? 'Making the signed copy...'
                                      : 'Submit signed document',
                                  icon: Icons.send_rounded,
                                  onPressed: (_agree && !_busy)
                                      ? () => _submit(pages)
                                      : null,
                                ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Strokes drawn on the signature pad.
class SignatureController extends ChangeNotifier {
  final List<List<Offset>> strokes = [];
  Size size = const Size(300, 180);

  bool get isEmpty => strokes.isEmpty;

  void start(Offset p) {
    strokes.add([p]);
    notifyListeners();
  }

  void add(Offset p) {
    if (strokes.isEmpty) return;
    strokes.last.add(p);
    notifyListeners();
  }

  void clear() {
    strokes.clear();
    notifyListeners();
  }

  /// PNG of the signature on a transparent background, or null if empty.
  Future<Uint8List?> export() async {
    if (isEmpty) return null;
    const scale = 2.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    paintStrokes(canvas, strokes);
    final image = await recorder.endRecording().toImage(
      (size.width * scale).round(),
      (size.height * scale).round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }
}

void paintStrokes(Canvas canvas, List<List<Offset>> strokes) {
  final paint = Paint()
    ..color = AppColors.green900
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  for (final s in strokes) {
    if (s.length == 1) {
      canvas.drawCircle(s.first, 1.5, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
      continue;
    }
    final path = Path()..moveTo(s.first.dx, s.first.dy);
    for (final p in s.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }
}

class SignaturePad extends StatelessWidget {
  const SignaturePad({super.key, required this.controller, this.onDrawing});
  final SignatureController controller;
  final ValueChanged<bool>? onDrawing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        controller.size = Size(c.maxWidth, 180);
        // The empty drag handlers claim every drag that starts on the pad, so
        // a stroke never pulls the sheet down or scrolls the page. The Listener
        // below still gets every finger movement to draw.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {},
          onPanUpdate: (_) {},
          onPanEnd: (_) {},
          child: Listener(
            onPointerDown: (e) {
              onDrawing?.call(true);
              controller.start(e.localPosition);
            },
            onPointerMove: (e) => controller.add(e.localPosition),
            onPointerUp: (_) => onDrawing?.call(false),
            onPointerCancel: (_) => onDrawing?.call(false),
            child: Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.slate200),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (_, _) => CustomPaint(
                    painter: _PadPainter(controller),
                    child: controller.isEmpty
                        ? const Center(
                            child: Text(
                              'Sign here',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.slate400,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.c);
  final SignatureController c;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = AppColors.slate200
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(16, size.height - 36),
      Offset(size.width - 16, size.height - 36),
      base,
    );
    paintStrokes(canvas, c.strokes);
  }

  @override
  bool shouldRepaint(_PadPainter old) => true;
}

/// The signing proof under a signed document: whether the signed file is
/// unchanged (its fingerprint matches the record), who signed from which
/// account and device, and a lock once management accepted it.
class _AuditBox extends StatelessWidget {
  const _AuditBox(this.m, this.a, {required this.locked});
  final ChatMessage m;
  final SignatureAudit a;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final intact =
        m.signedPdf == null || fingerprint(m.signedPdf!) == a.signedHash;
    final fg = intact ? AppColors.emerald : AppColors.red;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: intact ? AppColors.emeraldBg : AppColors.redBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                intact ? Icons.verified_rounded : Icons.gpp_bad_rounded,
                size: 16,
                color: fg,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  intact
                      ? 'Unchanged since signing'
                      : 'File changed after signing',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
              if (locked) ...[
                const Icon(
                  Icons.lock_rounded,
                  size: 14,
                  color: AppColors.slate500,
                ),
                const SizedBox(width: 3),
                const Text(
                  'Locked',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate500,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${a.signer}${a.account.isEmpty ? '' : ' (${a.account})'} · ${a.device}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.slate600),
          ),
          if (a.signedHash.isNotEmpty)
            Text(
              'Fingerprint ${shortFingerprint(a.signedHash)}',
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppColors.slate500,
              ),
            ),
        ],
      ),
    );
  }
}

/// "Confirm it's you" before signing. It owns its text field, so the field is
/// only cleaned up after the box has fully closed (not while it is still
/// fading out, which crashed the screen for a moment).
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.username, required this.password});
  final String username, password;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _busy = false;

  Future<void> _check() async {
    if (_busy) return;
    // The demo checks the password it keeps; the real app asks the server
    // (passwords are never kept on the phone).
    if (!backendOn) {
      if (_ctrl.text == widget.password) {
        popOnce(context, true);
      } else {
        setState(() => _error = 'Wrong password');
      }
      return;
    }
    if (_ctrl.text.isEmpty) {
      setState(() => _error = 'Enter your password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final problem = await backendSignIn(widget.username, _ctrl.text);
    if (!mounted) return;
    if (problem == null) {
      popOnce(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = problem.startsWith('Incorrect') ? 'Wrong password' : problem;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm it\'s you'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter the password of ${widget.username} to sign.',
            style: const TextStyle(fontSize: 13, color: AppColors.slate600),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            obscureText: true,
            autofocus: true,
            onSubmitted: (_) => _check(),
            decoration: InputDecoration(
              hintText: 'Password',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => popOnce(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold500,
            foregroundColor: AppColors.green900,
          ),
          onPressed: _busy ? null : _check,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.green900,
                  ),
                )
              : const Text(
                  'Sign',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
        ),
      ],
    );
  }
}

/// Admin buttons under a signed document: save the signed PDF onto this
/// device, and (once accepted) set it as the tenant's contract.
class _AdminDocActions extends StatelessWidget {
  const _AdminDocActions(this.m, this.tenant, {required this.accepted});
  final ChatMessage m;
  final String tenant;
  final bool accepted;

  String get _fileName => '${m.docTitle ?? 'Document'} - $tenant (signed).pdf';

  @override
  Widget build(BuildContext context) {
    final pdf = m.signedPdf!;
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final t = adminState.tenants.where((x) => x.name == tenant).firstOrNull;
        // Already their contract: the same signed file is assigned.
        final isContract =
            t?.contractPdf != null && identical(t!.contractPdf, pdf);
        ButtonStyle style(bool primary) => OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(42),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          backgroundColor: primary ? AppColors.gold500 : null,
          foregroundColor: AppColors.green800,
          side: const BorderSide(color: AppColors.gold500),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: style(false),
                    onPressed: () async {
                      final ok = await savePdfToDevice(context, pdf, _fileName);
                      if (ok && context.mounted) {
                        toast(context, 'Saved to your device');
                      }
                    },
                    icon: const Icon(
                      Icons.download_rounded,
                      size: 18,
                      color: AppColors.gold700,
                    ),
                    label: const Text(
                      'Download',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                if (accepted && t != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: isContract
                        ? Container(
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.emeraldBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 16,
                                  color: AppColors.emerald,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Their contract',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.emerald,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : OutlinedButton.icon(
                            style: style(true),
                            onPressed: () async {
                              final replace = t.hasContract;
                              final ok = await confirmAction(
                                context,
                                title: 'Set as ${t.name}\'s contract?',
                                message: replace
                                    ? 'It replaces their current contract (${t.contractName}). They will see the signed copy under My Contract.'
                                    : 'They will see the signed copy under My Contract.',
                                action: 'Set as contract',
                                danger: false,
                              );
                              if (!ok) return;
                              adminState.assignContract(t, _fileName, pdf);
                              if (context.mounted) {
                                toast(context, 'Set as ${t.name}\'s contract');
                              }
                            },
                            icon: const Icon(
                              Icons.assignment_turned_in_rounded,
                              size: 18,
                              color: AppColors.green900,
                            ),
                            label: const Text(
                              'Set as contract',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.green900,
                              ),
                            ),
                          ),
                  ),
                ],
              ],
            ),
            if (!accepted)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Accept it to set it as their contract.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.slate500),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// "Load earlier messages" at the top of a chat with older history.
class _LoadEarlier extends StatefulWidget {
  const _LoadEarlier(this.tenant);
  final String tenant;
  @override
  State<_LoadEarlier> createState() => _LoadEarlierState();
}

class _LoadEarlierState extends State<_LoadEarlier> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.gold400,
              ),
            )
          : TextButton.icon(
              onPressed: () async {
                setState(() => _busy = true);
                await Sync.loadOlderChat(widget.tenant);
                if (mounted) setState(() => _busy = false);
              },
              icon: const Icon(
                Icons.history_rounded,
                size: 16,
                color: AppColors.gold400,
              ),
              label: const Text(
                'Load earlier messages',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.gold400,
                ),
              ),
            ),
    ),
  );
}
