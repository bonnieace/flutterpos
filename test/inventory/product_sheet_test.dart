import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xlsx;
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_test/flutter_test.dart';

/// The template a person takes away, and the file they bring back.
///
/// **The template's header is a contract with the import parser**, and the first
/// test is that contract: a template whose columns that parser refuses would be
/// this feature failing at the only thing it does.
void main() {
  group('the template', () {
    test('names only columns the import reads, in a fixed order', () {
      final csv = productImportTemplateCsv(includeCost: true);

      expect(csv.split('\r\n').first, 'name,sku,price,cost,quantity,category');
    });

    test('carries one example row, so the shape of a value is shown', () {
      final lines = productImportTemplateCsv(
        includeCost: true,
        categoryName: 'Bakery',
      ).split('\r\n');

      expect(lines, hasLength(2));
      expect(lines.last, 'White bread loaf,BR-001,65,48,40,Bakery');
    });

    test('omits cost where the person may not record one', () {
      // The import refuses a cost column from a manager rather than ignoring
      // it, so a template carrying one would be a template they cannot use.
      final csv = productImportTemplateCsv(includeCost: false);

      expect(csv.split('\r\n').first, 'name,sku,price,quantity,category');
      expect(csv, isNot(contains('48')));
    });

    test('quotes a category whose name holds the separator', () {
      final csv = productImportTemplateCsv(
        includeCost: false,
        categoryName: 'Tea, coffee',
      );

      expect(csv.split('\r\n').last, endsWith('"Tea, coffee"'));
    });

    test('leaves the category blank rather than inventing one', () {
      // A category that does not exist refuses its row. With none to name, an
      // empty cell is the only honest example.
      final csv = productImportTemplateCsv(includeCost: false);

      expect(csv.split('\r\n').last, endsWith(','));
    });

    test('is named for the day it was taken', () {
      expect(
        productImportTemplateFilename(DateTime(2026, 9, 14)),
        'product_import_template_2026-09-14.csv',
      );
      expect(
        productImportTemplateFilename(DateTime(2026, 1, 5)),
        'product_import_template_2026-01-05.csv',
      );
    });
  });

  group('reading a chosen file', () {
    test('a CSV is its own text', () {
      final sheet = _sheet('products.csv', utf8.encode('name,sku\nA,1'));

      expect(decodeProductSheet(sheet), 'name,sku\nA,1');
    });

    test('a CSV Excel wrote in the system code page is still read', () {
      // Excel writes the system code page unless asked otherwise. Refusing the
      // file over one accented name would lose every row in it.
      final sheet = _sheet('products.csv', <int>[
        ...utf8.encode('name,sku\nCaf'),
        0xE9, // é in Latin-1, invalid on its own in UTF-8
        ...utf8.encode(',C-1'),
      ]);

      expect(decodeProductSheet(sheet), 'name,sku\nCafé,C-1');
    });

    test('a workbook is flattened to the same delimited text', () {
      final bytes = _workbook(<List<Object?>>[
        <Object?>['name', 'sku', 'price', 'quantity'],
        <Object?>['Mandazi', 'M-1', 20, 12],
      ]);

      expect(
        decodeProductSheet(_sheet('products.xlsx', bytes)),
        'name,sku,price,quantity\r\nMandazi,M-1,20,12',
      );
    });

    test('a whole number in a money column is not written 20.0', () {
      // A price typed as 20 comes back as a double. Writing it `20.0` would
      // hand the parser a figure nobody typed.
      final bytes = _workbook(<List<Object?>>[
        <Object?>['name', 'price'],
        <Object?>['Mandazi', 20.0],
        <Object?>['Samosa', 25.5],
      ]);

      final lines = decodeProductSheet(_sheet('p.xlsx', bytes)).split('\r\n');
      expect(lines[1], 'Mandazi,20');
      expect(lines[2], 'Samosa,25.5');
    });

    test('the blank rows Excel pads a sheet with are dropped', () {
      // A file with two products routinely carries hundreds of empty rows out
      // to the last cell anybody ever touched.
      final bytes = _workbook(<List<Object?>>[
        <Object?>['name', 'sku'],
        <Object?>['Mandazi', 'M-1'],
        <Object?>[null, null],
        <Object?>['', ''],
      ]);

      expect(
        decodeProductSheet(_sheet('p.xlsx', bytes)).split('\r\n'),
        hasLength(2),
      );
    });

    test('a cell holding a comma is quoted, so it stays one cell', () {
      final bytes = _workbook(<List<Object?>>[
        <Object?>['name', 'category'],
        <Object?>['Tea', 'Tea, coffee'],
      ]);

      expect(
        decodeProductSheet(_sheet('p.xlsx', bytes)),
        'name,category\r\nTea,"Tea, coffee"',
      );
    });

    test('a file that is not a spreadsheet is refused as a whole', () {
      // It has no rows to report a refusal against, so it is refused by name
      // rather than by line.
      expect(
        () => decodeProductSheet(
          _sheet('notes.xlsx', Uint8List.fromList(<int>[1, 2, 3, 4])),
        ),
        throwsA(
          isA<TenantProductSheetFormatException>().having(
            (error) => error.message,
            'message',
            contains('notes.xlsx'),
          ),
        ),
      );
    });

    test('an empty workbook is refused rather than imported as nothing', () {
      final bytes = _workbook(<List<Object?>>[]);

      expect(
        () => decodeProductSheet(_sheet('p.xlsx', bytes)),
        throwsA(isA<TenantProductSheetFormatException>()),
      );
    });

    test('an .xlsm is read as a workbook too', () {
      expect(_sheet('p.xlsm', Uint8List(0)).isWorkbook, isTrue);
      expect(_sheet('P.XLSX', Uint8List(0)).isWorkbook, isTrue);
      expect(_sheet('p.csv', Uint8List(0)).isWorkbook, isFalse);
      // No extension at all reads as delimited text, which is what a file
      // exported by a till or a supplier most often is.
      expect(_sheet('export', Uint8List(0)).isWorkbook, isFalse);
    });
  });
}

TenantPickedSheet _sheet(String name, List<int> bytes) =>
    TenantPickedSheet(name: name, bytes: Uint8List.fromList(bytes));

/// A real `.xlsx` built by the same package that reads it, so the test exercises
/// the decoder rather than a fixture somebody hand-rolled.
Uint8List _workbook(List<List<Object?>> rows) {
  final book = xlsx.Excel.createExcel();
  final sheet = book[book.getDefaultSheet()!];
  for (var row = 0; row < rows.length; row++) {
    for (var column = 0; column < rows[row].length; column++) {
      final value = rows[row][column];
      sheet
          .cell(
            xlsx.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
          )
          .value = switch (value) {
        null => null,
        final String text => xlsx.TextCellValue(text),
        final int number => xlsx.IntCellValue(number),
        final double number => xlsx.DoubleCellValue(number),
        _ => xlsx.TextCellValue(value.toString()),
      };
    }
  }
  return Uint8List.fromList(book.encode()!);
}
