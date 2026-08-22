import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum ExportFormat { csv, xlsx, pdf }

extension ExportFormatX on ExportFormat {
  String get ext => switch (this) {
        ExportFormat.csv => 'csv',
        ExportFormat.xlsx => 'xlsx',
        ExportFormat.pdf => 'pdf',
      };
  String get label => switch (this) {
        ExportFormat.csv => 'CSV',
        ExportFormat.xlsx => 'Excel (.xlsx)',
        ExportFormat.pdf => 'PDF',
      };
}

/// Builds branded export files from a simple headers + rows grid.
class Exporter {
  static const _brandHex = 'FF33A337';
  static const PdfColor _brand = PdfColor.fromInt(0xFF33A337);
  static const PdfColor _brandLight = PdfColor.fromInt(0xFFEAF5EA);

  // ---- CSV ----
  static List<int> csv(List<String> headers, List<List<String>> rows) {
    String esc(String v) {
      var s = v.replaceAll('"', '""');
      if (s.contains(',') || s.contains('\n') || s.contains('"')) s = '"$s"';
      return s;
    }

    final b = StringBuffer()..writeln(headers.map(esc).join(','));
    for (final r in rows) {
      b.writeln(r.map(esc).join(','));
    }
    return utf8.encode(b.toString());
  }

  // ---- XLSX (decorated) ----
  static List<int> xlsx(
      String sheetName, List<String> headers, List<List<String>> rows) {
    final excel = Excel.createExcel();
    final sheet = excel[sheetName];

    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString(_brandHex),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    sheet.appendRow([for (final h in headers) TextCellValue(h)]);
    for (var c = 0; c < headers.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .cellStyle = headerStyle;
      sheet.setColumnWidth(c, _colWidth(headers[c], rows, c));
    }

    for (var r = 0; r < rows.length; r++) {
      sheet.appendRow([for (final v in rows[r]) TextCellValue(v)]);
      if (r.isOdd) {
        final zebra = CellStyle(
            backgroundColorHex: ExcelColor.fromHexString('FFF3F8F3'));
        for (var c = 0; c < headers.length; c++) {
          sheet
              .cell(CellIndex.indexByColumnRow(
                  columnIndex: c, rowIndex: r + 1))
              .cellStyle = zebra;
        }
      }
    }

    // Freeze the header row and drop the default empty sheet.
    try {
      excel.setDefaultSheet(sheetName);
      if (excel.sheets.containsKey('Sheet1') && sheetName != 'Sheet1') {
        excel.delete('Sheet1');
      }
    } catch (_) {}
    return excel.encode() ?? const [];
  }

  static double _colWidth(String header, List<List<String>> rows, int c) {
    var max = header.length;
    for (final r in rows) {
      if (c < r.length && r[c].length > max) max = r[c].length;
    }
    return (max + 2).clamp(10, 60).toDouble();
  }

  // ---- PDF (branded) ----
  static Future<Uint8List> pdf({
    required String title,
    required String subtitle,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final logo = await _logo();
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => ctx.pageNumber == 1
            ? _pdfHeader(title, subtitle, logo)
            : pw.SizedBox(),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Bastak Leads · page ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (ctx) => [
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: _brand),
            headerHeight: 24,
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellHeight: 20,
            oddRowDecoration: const pw.BoxDecoration(color: _brandLight),
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignment: pw.Alignment.centerLeft,
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _pdfHeader(
      String title, String subtitle, pw.ImageProvider? logo) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            bottom: pw.BorderSide(color: _brand, width: 2)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logo != null) pw.Image(logo, width: 40, height: 40),
          if (logo != null) pw.SizedBox(width: 12),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: _brand)),
              pw.Text(subtitle,
                  style:
                      const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            ],
          ),
          pw.Spacer(),
          pw.Text('Bastak Instruments',
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey800)),
        ],
      ),
    );
  }

  static pw.MemoryImage? _cachedLogo;
  static Future<pw.MemoryImage?> _logo() async {
    if (_cachedLogo != null) return _cachedLogo;
    try {
      final data = await rootBundle.load('assets/icon/app_icon.png');
      _cachedLogo = pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      _cachedLogo = null;
    }
    return _cachedLogo;
  }
}
