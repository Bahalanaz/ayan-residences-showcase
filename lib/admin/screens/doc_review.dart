import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../state/sync.dart' show Sync;
import '../../theme.dart';
import '../../widgets/signed_document.dart' show showPdf;
import '../../widgets/common.dart';
import '../admin_state.dart';

String docStateLabel(DocState s) => switch (s) {
  DocState.missing => 'Not uploaded',
  DocState.toReview => 'Check this',
  DocState.verified => 'Verified',
  DocState.rejected => 'Asked again',
};

Color docStateColor(DocState s) => switch (s) {
  DocState.missing => AppColors.red,
  DocState.toReview => AppColors.gold600,
  DocState.verified => AppColors.emerald,
  DocState.rejected => AppColors.amber,
};

/// One of a tenant's required documents on the admin side. Tap it to look
/// at the file and accept it, or ask the tenant for a new one.
class DocReviewRow extends StatelessWidget {
  const DocReviewRow(this.t, this.doc, {super.key});
  final TenantRec t;
  final String doc;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final s = adminState.docState(t, doc);
        final color = docStateColor(s);
        return InkWell(
          onTap: () => showAppSheet(
            context,
            title: doc,
            builder: (_) => _ReviewSheet(t, doc),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.slate100)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    doc,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.green800,
                    ),
                  ),
                ),
                Text(
                  docStateLabel(s),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: .35),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.slate400,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet(this.t, this.doc);
  final TenantRec t;
  final String doc;
  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  static const _reasons = [
    'The photo is blurred',
    'Part of it is cut off',
    'It has expired',
    'It is the wrong document',
    'Other',
  ];
  String _reason = _reasons.first;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The file downloads the first time it is opened.
    Sync.fetch([widget.t]).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t, doc = widget.doc;
    final s = adminState.docState(t, doc);
    final file = t.docFiles[doc];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${t.name} · ${t.unitLabel}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.slate500),
            ),
            const Spacer(),
            Text(
              docStateLabel(s),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: docStateColor(s),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // The file the tenant sent.
        if (s == DocState.missing || s == DocState.rejected)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.slate50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              s == DocState.rejected
                  ? 'You asked for a new one: ${t.docRejected[doc]}. Waiting for the tenant to upload it.'
                  : 'The tenant has not uploaded this yet.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.slate600,
              ),
            ),
          )
        else if (file == null)
          Sync.waiting(t, 'doc:$doc')
              ? Container(
                  height: 200,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.slate50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.gold600,
                  ),
                )
              // Demo records marked uploaded have no real file attached.
              : _FileBox(icon: Icons.description_outlined, text: '$doc on file')
        else
          GestureDetector(
            onTap: () => _isPdf(file.bytes)
                ? showPdf(context, file.bytes, file.name)
                : showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      backgroundColor: Colors.black,
                      insetPadding: const EdgeInsets.all(12),
                      child: InteractiveViewer(
                        maxScale: 5,
                        child: Image.memory(
                          file.bytes,
                          errorBuilder: (_, _, _) => _FileBox(
                            icon: Icons.picture_as_pdf_outlined,
                            text: file.name,
                          ),
                        ),
                      ),
                    ),
                  ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                file.bytes,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _FileBox(
                  icon: Icons.picture_as_pdf_outlined,
                  text: file.name,
                ),
              ),
            ),
          ),

        if (s == DocState.toReview || s == DocState.verified) ...[
          const SizedBox(height: 16),
          if (s == DocState.toReview)
            GoldButton(
              label: 'Valid, approve it',
              icon: Icons.verified_outlined,
              onPressed: () {
                adminState.verifyDocument(t, doc);
                popOnce(context);
                toast(context, '$doc approved. ${t.name} has been told.');
              },
            ),
          const SizedBox(height: 16),
          const FieldLabel('Not valid? Ask for a new one'),
          DropdownField(
            value: _reason,
            items: _reasons,
            onChanged: (v) => setState(() => _reason = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Add a note for the tenant (optional)',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.red,
              side: const BorderSide(color: AppColors.red),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () {
              final note = _note.text.trim();
              final reason = _reason == 'Other' && note.isNotEmpty
                  ? note
                  : note.isEmpty
                  ? _reason.toLowerCase()
                  : '${_reason.toLowerCase()} ($note)';
              adminState.rejectDocument(t, doc, reason);
              popOnce(context);
              toast(context, '${t.name} was asked to upload a new $doc.');
            },
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text(
              'Request a new one',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _FileBox extends StatelessWidget {
  const _FileBox({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    height: 120,
    width: double.infinity,
    decoration: BoxDecoration(
      color: AppColors.slate50,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 36, color: AppColors.gold600),
        const SizedBox(height: 6),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.green800,
          ),
        ),
      ],
    ),
  );
}

/// True for a PDF (its first bytes are "%PDF").
bool _isPdf(Uint8List b) =>
    b.length > 4 &&
    b[0] == 0x25 &&
    b[1] == 0x50 &&
    b[2] == 0x44 &&
    b[3] == 0x46;
