import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Turns rows into CSV text (Excel and Google Sheets open it). Values with
/// commas, quotes or line breaks are quoted.
String toCsv(List<List<Object?>> rows) {
  String cell(Object? v) {
    final s = v?.toString() ?? '';
    return s.contains(RegExp(r'[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  return rows.map((r) => r.map(cell).join(',')).join('\r\n');
}

/// Opens the phone's share sheet with a CSV file (save to Files, send by
/// email or WhatsApp). A byte-order mark makes Excel read ₱ correctly.
Future<void> shareCsv(String fileName, List<List<Object?>> rows) async {
  final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(toCsv(rows))]);
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(bytes, mimeType: 'text/csv', name: fileName)],
    fileNameOverrides: [fileName],
    subject: fileName,
  ));
}

/// Money for a receipt: "PHP 1,234.00" or "AED 1,234.00" (the PDF fonts have
/// no peso sign).
String _money(double v, bool aed) {
  final s = v.toStringAsFixed(2).split('.');
  final whole = s[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return '${aed ? 'AED' : 'PHP'} $whole.${s[1]}';
}

const _green = PdfColor.fromInt(0xFF123C32);
const _gold = PdfColor.fromInt(0xFFB3934F);
const _grey = PdfColor.fromInt(0xFF6B7280);

/// An official-looking receipt for one verified payment, as a PDF.
Future<Uint8List> buildReceiptPdf({
  required String receiptNo,
  required String tenant,
  required String unit,
  required String title,
  required String method,
  required String reference,
  required String date,
  required double amount,
  required bool aed,
}) async {
  final doc = pw.Document(title: 'Receipt $receiptNo', author: 'Ayan Residences');
  pw.Widget row(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(k, style: const pw.TextStyle(fontSize: 10.5, color: _grey)),
          pw.Text(v, style: pw.TextStyle(fontSize: 10.5, color: _green, fontWeight: pw.FontWeight.bold)),
        ]),
      );
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    margin: const pw.EdgeInsets.all(32),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('AYAN RESIDENCES',
          style: pw.TextStyle(fontSize: 10, letterSpacing: 2, color: _gold, fontWeight: pw.FontWeight.bold)),
      pw.Text('Official receipt', style: pw.TextStyle(fontSize: 20, color: _green, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Text('No. $receiptNo', style: const pw.TextStyle(fontSize: 10, color: _grey)),
      pw.Divider(color: _gold, thickness: 1.2, height: 24),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(color: _green, borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('AMOUNT RECEIVED',
              style: pw.TextStyle(fontSize: 8.5, letterSpacing: 1.5, color: _gold, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(_money(amount, aed),
              style: pw.TextStyle(fontSize: 22, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
        ]),
      ),
      pw.SizedBox(height: 14),
      row('Received from', tenant),
      row('Unit', unit),
      row('For', title),
      row('Paid by', method),
      row('Reference', reference),
      row('Date', date),
      pw.Spacer(),
      pw.Text('This receipt was issued by Ayan Residences after the payment was verified.',
          style: const pw.TextStyle(fontSize: 8.5, color: _grey)),
    ]),
  ));
  return doc.save();
}

/// Builds the receipt and opens the share sheet (save, print or send).
Future<void> shareReceipt({
  required String receiptNo,
  required String tenant,
  required String unit,
  required String title,
  required String method,
  required String reference,
  required String date,
  required double amount,
  required bool aed,
}) async {
  final bytes = await buildReceiptPdf(
      receiptNo: receiptNo,
      tenant: tenant,
      unit: unit,
      title: title,
      method: method,
      reference: reference,
      date: date,
      amount: amount,
      aed: aed);
  await Printing.sharePdf(bytes: bytes, filename: 'Receipt $receiptNo.pdf');
}
