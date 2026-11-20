import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../theme.dart';

/// The pages of a document as pictures: every page of a PDF, or the photo
/// itself. Empty when there is nothing to show.
Future<List<Uint8List>> documentPages({
  Uint8List? pdf,
  Uint8List? photo,
}) async {
  if (pdf != null) {
    final pages = <Uint8List>[];
    await for (final p in Printing.raster(pdf, dpi: 120)) {
      pages.add(await p.toPng());
    }
    return pages;
  }
  return photo == null ? const [] : [photo];
}

/// Where the signature sits on a page, as fractions of the page (0 to 1),
/// so it lands in the same spot whatever the screen or PDF size.
class SignaturePlacement {
  SignaturePlacement({
    required this.page,
    required this.left,
    required this.top,
    this.width = .34,
  });
  int page;
  double left, top;

  /// Signature width as a share of the page width.
  double width;
}

/// "page 3", "pages 1, 2 and 5".
String _pageList(List<SignaturePlacement> spots) {
  final p = (spots.map((s) => s.page + 1).toSet().toList()..sort())
      .map((n) => '$n')
      .toList();
  if (p.isEmpty) return '-';
  if (p.length == 1) return 'page ${p.first}';
  return 'pages ${p.sublist(0, p.length - 1).join(', ')} and ${p.last}';
}

/// Makes the signed copy: every page as it was, with the signature drawn at
/// each chosen spot (one or several pages) and a small "Signed
/// electronically" line under each.
Future<Uint8List> buildSignedPdf({
  required List<Uint8List> pages,
  required Uint8List signature,
  required double signatureAspect,
  required List<SignaturePlacement> spots,
  required String signer,
  required DateTime when,
  String title = 'Document',
  String account = '',
  String device = '',
  String originalHash = '',
}) async {
  final doc = pw.Document(title: 'Signed document', author: 'Ayan Residences');
  final sig = pw.MemoryImage(signature);
  const months = [
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
  final h12 = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final stamp =
      'Signed electronically by $signer · ${months[when.month - 1]} ${when.day}, ${when.year} '
      '$h12:${when.minute.toString().padLeft(2, '0')} ${when.hour < 12 ? 'AM' : 'PM'}';
  for (var i = 0; i < pages.length; i++) {
    final img = pw.MemoryImage(pages[i]);
    // Keep each page's shape, A4 wide.
    const w = 595.0;
    final h = w * (img.height ?? 842) / (img.width ?? 595);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(w, h),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          children: [
            pw.Positioned.fill(child: pw.Image(img, fit: pw.BoxFit.fill)),
            for (final at in spots.where((s) => s.page == i)) ...[
              pw.Positioned(
                left: at.left * w,
                top: at.top * h,
                child: pw.SizedBox(
                  width: at.width * w,
                  height: at.width * w / signatureAspect,
                  child: pw.Image(sig, fit: pw.BoxFit.contain),
                ),
              ),
              pw.Positioned(
                left: at.left * w,
                top: at.top * h + at.width * w / signatureAspect + 1,
                child: pw.Text(
                  stamp,
                  style: const pw.TextStyle(
                    fontSize: 6.5,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  // The audit page: who signed, from which account, when, on what device,
  // and the fingerprint of the document as it was sent.
  const green = PdfColor.fromInt(0xFF123C32),
      gold = PdfColor.fromInt(0xFFB3934F),
      grey = PdfColor.fromInt(0xFF6B7280);
  pw.Widget row(String k, String v, {bool mono = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 6),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 130,
          child: pw.Text(
            k,
            style: const pw.TextStyle(fontSize: 10, color: grey),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            v,
            style: pw.TextStyle(
              fontSize: mono ? 8.5 : 10.5,
              font: mono ? pw.Font.courier() : null,
              color: green,
              fontWeight: mono ? null : pw.FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'AYAN RESIDENCES',
            style: pw.TextStyle(
              fontSize: 10,
              letterSpacing: 2,
              color: gold,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            'Signature record',
            style: pw.TextStyle(
              fontSize: 22,
              color: green,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Divider(color: gold, thickness: 1.2, height: 24),
          row('Document', title),
          row('Pages', '${pages.length} (signed on ${_pageList(spots)})'),
          row('Signed by', signer),
          row('Account', account.isEmpty ? '-' : account),
          row(
            'Identity check',
            'Logged-in account and password re-entered before signing',
          ),
          row(
            'Signed on',
            stamp.replaceFirst('Signed electronically by $signer · ', ''),
          ),
          row('Device', device.isEmpty ? '-' : device),
          row(
            'Original document fingerprint (SHA-256)',
            originalHash.isEmpty ? '-' : originalHash,
            mono: true,
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Signature',
            style: const pw.TextStyle(fontSize: 10, color: grey),
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            height: 70,
            width: 220,
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Image(sig, fit: pw.BoxFit.contain),
          ),
          pw.Spacer(),
          pw.Text(
            'The fingerprint of this signed file is kept by Ayan Residences. If any page of this file is changed after '
            'signing, its fingerprint no longer matches the one on record. Signed electronically under the '
            'Electronic Commerce Act of 2000 (RA 8792).',
            style: const pw.TextStyle(fontSize: 8.5, color: grey),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Shows a PDF full screen with save, print and share.
void showPdf(BuildContext context, Uint8List bytes, String title) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.green800,
          foregroundColor: Colors.white,
          title: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        body: SafeArea(
          top: false,
          child: PdfPreview(
            build: (_) async => bytes,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            pdfFileName: '$title.pdf',
            // Print, download (in the middle) and share.
            allowPrinting: false,
            allowSharing: false,
            actions: [
              const PdfPrintAction(),
              PdfPreviewAction(
                icon: const Icon(Icons.download_rounded),
                onPressed: (context, _, _) async {
                  final ok = await savePdfToDevice(
                    context,
                    bytes,
                    title,
                    dialogTitle: 'Save the PDF',
                  );
                  if (ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Saved to your device')),
                    );
                  }
                },
              ),
              PdfShareAction(),
            ],
            pdfPreviewPageDecoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Saves a PDF onto the device: the phone's own "Save to" screen opens so the
/// admin picks the folder (Downloads, Drive...). True when it was saved.
Future<bool> savePdfToDevice(
  BuildContext context,
  Uint8List bytes,
  String fileName, {
  String dialogTitle = 'Save the signed PDF',
}) async {
  try {
    final uri = await FilePicker.saveFile(
      fileName: fileName.toLowerCase().endsWith('.pdf')
          ? fileName
          : '$fileName.pdf',
      bytes: bytes,
      mimeType: 'application/pdf',
      dialogTitle: dialogTitle,
    );
    return uri != null;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Couldn't save the file. Please try again.")));
    }
    return false;
  }
}
