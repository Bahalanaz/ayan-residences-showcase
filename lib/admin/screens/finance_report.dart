import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Money for the PDF: "PHP 1,234.00" or "AED 1,234.00". (The standard PDF
/// fonts have no peso sign, so the currency code is written instead.)
String pdfMoney(double v, {bool aed = false}) =>
    '${aed ? 'AED' : 'PHP'} ${pdfNumber(v)}';

/// "1,234.00", "-1,234.00".
String pdfNumber(double v) {
  final s = v.abs().toStringAsFixed(2);
  final parts = s.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return '${v < 0 ? '-' : ''}$whole.${parts[1]}';
}

/// One line of an income statement: this period and the period before.
/// [kind]: a normal line, a "subtotal" (bold), a "total" (bold, shaded)
/// or a "heading" (a group name with no amounts).
typedef StatementLine = ({
  String label,
  double? now,
  double? before,
  String kind,
  bool cost,
});

/// One income statement (pesos, or dirhams for the villas).
typedef Statement = ({
  String title,
  String currency,
  List<StatementLine> lines,
});

/// A ratio or figure compared with the period before ("Expenses / income").
typedef Ratio = ({String label, String now, String before});

/// A plain table (occupancy, by unit, deposits...).
typedef InfoTable = ({
  String title,
  List<String> columns,
  List<List<String>> rows,
});

StatementLine line(
  String label,
  double now,
  double before, {
  bool cost = false,
}) => (label: label, now: now, before: before, kind: 'line', cost: cost);
StatementLine subtotal(
  String label,
  double now,
  double before, {
  bool cost = false,
}) => (label: label, now: now, before: before, kind: 'subtotal', cost: cost);
StatementLine total(String label, double now, double before) =>
    (label: label, now: now, before: before, kind: 'total', cost: false);
StatementLine heading(String label) =>
    (label: label, now: null, before: null, kind: 'heading', cost: false);

const _green = PdfColor.fromInt(0xFF123C32);
const _green2 = PdfColor.fromInt(0xFF1F4D3D);
const _gold = PdfColor.fromInt(0xFFB8975A);
const _goldLight = PdfColor.fromInt(0xFFF5EEDC);
const _cream = PdfColor.fromInt(0xFFFAF7F0);
const _line = PdfColor.fromInt(0xFFE5E0D5);
const _grey = PdfColor.fromInt(0xFF6B7280);
const _red = PdfColor.fromInt(0xFFB42318);
const _good = PdfColor.fromInt(0xFF1E7A4F);

/// "+12%", "-4%", or a dash when there is nothing to compare with.
String _change(double? now, double? before) {
  if (now == null || before == null || before == 0) return '-';
  final p = (now - before) / before.abs() * 100;
  return '${p >= 0 ? '+' : ''}${p.toStringAsFixed(0)}%';
}

/// Builds the finance report as an income statement: this period next to
/// the period before with the change, pesos and dirhams apart, then ratios
/// and the other tables.
Future<Uint8List> buildFinancePdf({
  required String period,
  required String previousPeriod,
  required String generatedOn,
  required String netPeso,
  required String netVillas,
  required String comparison,
  required List<Statement> statements,
  required List<Ratio> ratios,
  required List<InfoTable> tables,
}) async {
  final doc = pw.Document(
    title: 'Ayan Residences financial report · $period',
    author: 'Ayan Residences',
  );

  pw.Widget cell(
    String text, {
    bool right = false,
    bool bold = false,
    PdfColor? color,
    double size = 9.5,
    PdfColor? bg,
    double indent = 0,
  }) {
    return pw.Container(
      color: bg,
      padding: pw.EdgeInsets.fromLTRB(8 + indent, 5.5, 8, 5.5),
      alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: size,
          color: color ?? PdfColors.black,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  // Column headers like tabs: dark green, the current period gold.
  pw.Widget head(String text, {bool current = false, bool right = true}) =>
      pw.Container(
        margin: const pw.EdgeInsets.only(left: 3, bottom: 4),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: pw.BoxDecoration(
          color: current ? _gold : _green,
          borderRadius: const pw.BorderRadius.vertical(
            top: pw.Radius.circular(5),
          ),
        ),
        alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 9.5,
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );

  pw.Widget statement(Statement s) {
    const widths = {
      0: pw.FlexColumnWidth(3.2),
      1: pw.FlexColumnWidth(1.5),
      2: pw.FlexColumnWidth(1.5),
      3: pw.FlexColumnWidth(0.9),
    };
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          s.title,
          style: pw.TextStyle(
            fontSize: 13,
            color: _green,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          'Amounts in ${s.currency}',
          style: const pw.TextStyle(fontSize: 8.5, color: _grey),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          columnWidths: widths,
          children: [
            pw.TableRow(
              children: [
                pw.SizedBox(),
                head(period, current: true),
                head(previousPeriod),
                head('Change'),
              ],
            ),
          ],
        ),
        pw.Table(
          columnWidths: widths,
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(color: _line, width: .5),
            bottom: pw.BorderSide(color: _line, width: .5),
            top: pw.BorderSide(color: _line, width: .5),
          ),
          children: [
            for (final l in s.lines)
              if (l.kind == 'heading')
                pw.TableRow(
                  children: [
                    cell(l.label, bold: true, color: _green, size: 10),
                    cell(''),
                    cell(''),
                    cell(''),
                  ],
                )
              else
                pw.TableRow(
                  decoration: l.kind == 'total'
                      ? const pw.BoxDecoration(color: _cream)
                      : null,
                  children: [
                    cell(
                      l.label,
                      bold: l.kind != 'line',
                      color: l.kind == 'total' ? _green : null,
                      indent: l.kind == 'line' ? 8 : 0,
                    ),
                    cell(
                      l.now == null ? '' : pdfNumber(l.cost ? -l.now! : l.now!),
                      right: true,
                      bold: l.kind != 'line',
                      bg: _goldLight,
                      color: l.kind == 'total'
                          ? (l.now! < 0 ? _red : _green)
                          : (l.cost && l.now != 0 ? _red : null),
                    ),
                    cell(
                      l.before == null
                          ? ''
                          : pdfNumber(l.cost ? -l.before! : l.before!),
                      right: true,
                      bold: l.kind != 'line',
                      color: _grey,
                    ),
                    cell(
                      _change(l.now, l.before),
                      right: true,
                      bold: l.kind != 'line',
                      // More income is good, more cost is not.
                      color: _change(l.now, l.before) == '-'
                          ? _grey
                          : ((l.now! >= l.before!) != l.cost ? _good : _red),
                    ),
                  ],
                ),
          ],
        ),
      ],
    );
  }

  // The title sits in the table's header row, so it never ends up alone
  // at the bottom of a page.
  pw.Widget table(InfoTable t) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Table(
        border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _line, width: .5),
          bottom: pw.BorderSide(color: _line, width: .5),
        ),
        columnWidths: {
          0: const pw.FlexColumnWidth(2.6),
          for (var i = 1; i < t.columns.length; i++)
            i: const pw.FlexColumnWidth(1.2),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _green2),
            children: [
              for (var i = 0; i < t.columns.length; i++)
                cell(
                  i == 0 ? t.title : t.columns[i],
                  right: i > 0,
                  bold: true,
                  color: i == 0 ? _gold : PdfColors.white,
                  size: i == 0 ? 10.5 : 9,
                ),
            ],
          ),
          if (t.rows.isEmpty)
            pw.TableRow(
              children: [
                cell('Nothing in this period.', color: _grey),
                for (var i = 1; i < t.columns.length; i++) cell(''),
              ],
            )
          else
            for (var r = 0; r < t.rows.length; r++)
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: r.isOdd ? _cream : PdfColors.white,
                ),
                children: [
                  for (var i = 0; i < t.rows[r].length; i++)
                    cell(t.rows[r][i], right: i > 0),
                ],
              ),
        ],
      ),
    ],
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 36),
      header: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        margin: const pw.EdgeInsets.only(bottom: 12),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _gold, width: 1.5)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'AYAN RESIDENCES',
                  style: pw.TextStyle(
                    fontSize: 9,
                    letterSpacing: 2,
                    color: _gold,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Financial Report',
                  style: pw.TextStyle(
                    fontSize: 20,
                    color: _green,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  period,
                  style: pw.TextStyle(
                    fontSize: 12,
                    color: _green,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Compared with $previousPeriod',
                  style: const pw.TextStyle(fontSize: 8.5, color: _grey),
                ),
                pw.Text(
                  'Generated $generatedOn',
                  style: const pw.TextStyle(fontSize: 8.5, color: _grey),
                ),
              ],
            ),
          ],
        ),
      ),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Ayan Residences · Financial report · $period',
            style: const pw.TextStyle(fontSize: 8, color: _grey),
          ),
          pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _grey),
          ),
        ],
      ),
      build: (ctx) => [
        // Summary: net profit in each currency.
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: _green,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'NET PROFIT · PESOS',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        letterSpacing: 1.2,
                        color: _gold,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      netPeso,
                      style: pw.TextStyle(
                        fontSize: 18,
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      comparison,
                      style: const pw.TextStyle(
                        fontSize: 8.5,
                        color: PdfColors.grey300,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: _goldLight,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: _gold, width: .8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'NET PROFIT · VILLAS',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        letterSpacing: 1.2,
                        color: _gold,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      netVillas,
                      style: pw.TextStyle(
                        fontSize: 18,
                        color: _green,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Dirhams, kept apart from pesos',
                      style: const pw.TextStyle(fontSize: 8.5, color: _grey),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        for (final s in statements) ...[pw.SizedBox(height: 18), statement(s)],
        pw.SizedBox(height: 18),
        // Ratios, this period against the one before.
        table((
          title: 'Ratios',
          columns: ['', period, previousPeriod],
          rows: [
            for (final r in ratios) [r.label, r.now, r.before],
          ],
        )),
        for (final t in tables) ...[pw.SizedBox(height: 18), table(t)],
        pw.SizedBox(height: 16),
        pw.Text(
          'Revenue counts verified payments and cleared cheques only; condo stays count on check-in. '
          'Pesos (apartments, condos) and dirhams (villas) are never added together. Deposits are money '
          'held for tenants and guests, not revenue. Payment gateway fees are an estimate.',
          style: const pw.TextStyle(fontSize: 8, color: _grey),
        ),
      ],
    ),
  );
  return doc.save();
}
