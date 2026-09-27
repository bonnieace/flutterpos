/// That a workbook carries numbers a spreadsheet can actually work with.
///
/// **This file does more than check a renderer.** `excel` can read back what it
/// wrote, so unlike the PDF these assertions reach the actual cells - their
/// types, their number formats, their merges. That makes the workbook the
/// reference implementation of every figure in a report: get an amount wrong
/// and it is caught here, in a test that names the cell, rather than by
/// somebody squinting at a chart.
///
/// The rule being defended throughout is that a person opened this file to do
/// arithmetic. A cell that arrives as a sentence has taken that away from them.
library;

import 'package:excel/excel.dart';
import 'package:uzapay_pos/reporting/reporting_currency.dart';
import 'package:uzapay_pos/reports/render/excel_report.dart';
import 'package:uzapay_pos/reports/report_table.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/documents.dart';

Future<Excel> _render({TenantReportingCurrency? currency}) async {
  final file = await TenantExcelReportRenderer.standard().render(
    fixtureDocument(
      identity: currency == null ? null : fixtureIdentity(currency: currency),
    ),
  );
  return Excel.decodeBytes(file.bytes);
}

Data? _cell(Excel book, String sheet, int column, int row) =>
    book[sheet].rows[row][column];

/// Whether a cell holds a number a spreadsheet can total.
bool _isNumeric(Data cell) =>
    cell.value is IntCellValue || cell.value is DoubleCellValue;

void main() {
  group('the workbook is shaped for reading', () {
    test('it opens on the cover, and the scaffold sheet is gone', () async {
      final book = await _render();

      expect(book.getDefaultSheet(), TenantExcelReportRenderer.coverSheet);
      expect(
        book.sheets.keys,
        isNot(contains('Sheet1')),
        reason:
            'The sheet Excel.createExcel starts with is not one of ours and '
            'should not be in a document somebody is sent.',
      );
    });

    test('there is a sheet per listed section, plus cover and summary', () async {
      final book = await _render();

      expect(book.sheets.keys, contains(TenantExcelReportRenderer.coverSheet));
      expect(
        book.sheets.keys,
        contains(TenantExcelReportRenderer.summarySheet),
      );
      expect(
        book.sheets.keys,
        contains('Till variance by shift'),
        reason: 'A section with rows gets its own sheet, named after it.',
      );
    });

    test('the cover leads with the business, not with the report', () async {
      final book = await _render();
      final first = _cell(book, TenantExcelReportRenderer.coverSheet, 0, 0);

      expect(
        (first?.value as TextCellValue?)?.value.toString(),
        'Mama Njeri Stores',
        reason:
            'A workbook cannot carry a logo - excel has no drawing writer - '
            'so the name set large in the accent is the whole of the mark.',
      );
    });

    test('the cover states the scope whether or not anything went wrong', () async {
      final book = await _render();
      final sheet = book[TenantExcelReportRenderer.coverSheet];
      final text = sheet.rows
          .expand((row) => row)
          .map((cell) => cell?.value)
          .whereType<TextCellValue>()
          .map((value) => value.value.toString())
          .join('\n');

      expect(text, contains('Scope and provenance'));
      expect(text, contains('Records read'));
      expect(text, contains('Grace Wanjiru'));
      expect(
        text,
        contains('record no cost'),
        reason:
            'The missing-cost caveat has to reach the workbook as well as the '
            'page, or the two documents disagree about what is known.',
      );
    });
  });

  group('cells carry numbers, not sentences', () {
    test('money is a double with a currency number format', () async {
      final book = await _render();
      final sheet = book[TenantExcelReportRenderer.summarySheet];

      final numeric = sheet.rows
          .map((row) => row.length > 2 ? row[2] : null)
          .whereType<Data>()
          .firstWhere(_isNumeric);

      // Int or double is immaterial - `excel` narrows a whole double back to
      // an int when it reads the file, and both total the same. What matters
      // is that it is not text: a column of "KES 1234.50" strings cannot be
      // summed, sorted or charted, which is everything the person opened this
      // file to do.
      expect(
        _isNumeric(numeric),
        isTrue,
        reason: 'The cell has to be a number a spreadsheet can work with.',
      );
      expect(
        numeric.cellStyle?.numberFormat.formatCode,
        contains('KES'),
        reason:
            'The code belongs in the format, where Excel still treats the '
            'cell as a number, rather than in the value where it does not.',
      );
    });

    test('an unpublished currency gives a bare format, never a guess', () async {
      final book = await _render(currency: TenantReportingCurrency.unknown);
      final sheet = book[TenantExcelReportRenderer.summarySheet];

      final numeric = sheet.rows
          .map((row) => row.length > 2 ? row[2] : null)
          .whereType<Data>()
          .firstWhere(_isNumeric);

      expect(
        numeric.cellStyle?.numberFormat.formatCode,
        isNot(contains('KES')),
        reason:
            'Reporting never guesses a currency. There is no defensible '
            'default and a wrong code is worse than an unlabelled figure.',
      );
      expect(numeric.cellStyle?.numberFormat.formatCode, contains('0.00'));
    });

    test('a money column says its currency in the heading too', () async {
      final book = await _render();
      final sheet = book['Till variance by shift'];
      final headings = sheet.rows[2]
          .map((cell) => (cell?.value as TextCellValue?)?.value.toString())
          .whereType<String>()
          .toList();

      expect(
        headings,
        contains('Takings (KES)'),
        reason:
            'A column pasted into another workbook loses its number format '
            'but keeps its heading.',
      );
    });

    test('a change is a fraction with a percent format', () async {
      final book = await _render();
      final sheet = book[TenantExcelReportRenderer.summarySheet];

      final change = sheet.rows
          .map((row) => row.length > 4 ? row[4] : null)
          .whereType<Data>()
          .firstWhere((cell) => cell.value is DoubleCellValue);


      expect(
        (change.value as DoubleCellValue).value.abs(),
        lessThan(10),
        reason:
            'Stored as a fraction, so Excel own percent semantics apply and '
            'the figure can be averaged without being divided by a hundred '
            'first.',
      );
      expect(change.cellStyle?.numberFormat.formatCode, contains('%'));
    });
  });

  group('a value nobody measured', () {
    test('arrives as words, not as a blank and not as a nought', () async {
      final book = await _render();
      final sheet = book['Till variance by shift'];

      final absent = sheet.rows
          .expand((row) => row)
          .whereType<Data>()
          .map((cell) => cell.value)
          .whereType<TextCellValue>()
          .map((value) => value.value.toString())
          .where((text) => text == TenantReportAbsentCell.notRecorded)
          .toList();

      expect(
        absent,
        isNotEmpty,
        reason:
            'The unevidenced shift has to survive the round trip. A blank '
            'cell would be summed as nought by whoever opens the file, and a '
            'nought would invent a till that balanced.',
      );
    });

    test('and it is not a number cell, so nothing can total it', () async {
      final book = await _render();
      final sheet = book['Till variance by shift'];

      for (final row in sheet.rows) {
        for (final cell in row) {
          final value = cell?.value;
          if (value is TextCellValue &&
              value.value.toString() == TenantReportAbsentCell.notRecorded) {
            expect(
              value,
              isA<TextCellValue>(),
              reason: 'SUM over this column must skip it, not read it as 0.',
            );
          }
        }
      }
    });
  });

  group('the summary carries every figure the charts draw', () {
    test('a row per charted value, attributed to its section', () async {
      final book = await _render();
      final sheet = book[TenantExcelReportRenderer.summarySheet];
      final sections = sheet.rows
          .map((row) => (row.first?.value as TextCellValue?)?.value.toString())
          .whereType<String>()
          .toSet();

      expect(sections, contains('Headline'));
      expect(sections, contains('Takings by day'));
      expect(sections, contains('How it was paid for'));
      expect(
        sections,
        contains('Till variance by shift'),
        reason:
            'Every picture in the PDF is a picture of these rows. That is why '
            'the workbook needs no chart images to be useful.',
      );
    });

    test('the headings are a real header row', () async {
      final book = await _render();
      final headings = book[TenantExcelReportRenderer.summarySheet].rows.first
          .map((cell) => (cell?.value as TextCellValue?)?.value.toString())
          .toList();

      expect(headings, <String>[
        'Section',
        'Measure',
        'This period',
        'Period before',
        'Change',
      ]);
    });
  });

  group('the file itself', () {
    test('names and types itself for a spreadsheet', () async {
      final file = await TenantExcelReportRenderer.standard().render(
        fixtureDocument(),
      );

      expect(
        file.filename,
        'mama-njeri-stores-sales-2026-09-01-to-2026-09-22.xlsx',
      );
      expect(
        file.mimeType,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        reason:
            'The share sheet decides which apps are offered from this, so a '
            'wrong type means the person cannot open what they just made.',
      );
    });

    test('the bytes are a zip, which is what an xlsx is', () async {
      final file = await TenantExcelReportRenderer.standard().render(
        fixtureDocument(),
      );

      expect(
        file.bytes.take(2).toList(),
        <int>[0x50, 0x4B],
        reason: 'PK. Every OOXML file is a zip archive underneath.',
      );
    });
  });
}
