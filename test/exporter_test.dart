import 'package:bastak_leads/services/exporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const headers = ['Name', 'Score', 'Note'];
  final rows = [
    ['Acme Mills, Ltd', '9', 'has, comma'],
    ['Beta "Grain"', '7', 'quote test'],
  ];

  test('CSV escapes commas and quotes', () {
    final bytes = Exporter.csv(headers, rows);
    final text = String.fromCharCodes(bytes);
    expect(text, contains('"Acme Mills, Ltd"'));
    expect(text, contains('"Beta ""Grain"""'));
    expect(text.trim().split('\n').length, 3); // header + 2 rows
  });

  test('XLSX produces a non-empty workbook', () {
    final bytes = Exporter.xlsx('Leads', headers, rows);
    expect(bytes.length, greaterThan(0));
    // XLSX is a ZIP archive — starts with 'PK'.
    expect(bytes[0], 0x50);
    expect(bytes[1], 0x4B);
  });
}
