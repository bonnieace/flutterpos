/// Getting a spreadsheet of products off a person's device and into the import.
///
/// **This is the journey the pre-multitenancy app had, rebuilt.** That app
/// offered two things and nothing else: *Download Template* wrote a header row
/// and handed it to the share sheet, and *Upload* opened a file picker, read the
/// file, and showed what it was about to do before doing it. Both are here. What
/// replaced them on this backend - a text area you paste four hundred rows into -
/// asks a shopkeeper to do something no shopkeeper does.
///
/// **The template is a CSV, and the picker takes either.** A CSV is what the old
/// system produced, it opens and edits in Excel like any other sheet, and it is
/// already what the import parser reads. But somebody who opens a template in
/// Excel and presses Save As will often hand back an `.xlsx`, and refusing that
/// would be a rule about file formats rather than about products - so a workbook
/// is decoded into the same delimited text a CSV already is.
///
/// **The platform halves are interfaces.** Picking a file and handing one to the
/// share sheet are the two things a widget test cannot do, and they are the two
/// things this file keeps behind a seam, exactly as the branding logo store and
/// the printer transport are. Everything else here is pure and tested as such.
library;

import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' as xlsx;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../platform/browser_file.dart';

/// A file the person chose, as bytes and under the name their device gave it.
///
/// **Bytes rather than a path.** A picked file on Android may be a content URI
/// with no readable path, and on the web there is no path at all; every caller
/// here wants the contents, so the contents are what the seam carries.
final class TenantPickedSheet {
  const TenantPickedSheet({required this.name, required this.bytes});

  /// The file's own name, used only to decide how to read it and to say which
  /// file a refusal is about.
  final String name;

  final Uint8List bytes;

  /// Whether this names a workbook rather than delimited text.
  ///
  /// The extension and nothing else. Sniffing the bytes would be more certain
  /// and would also mean this file decides what a zip archive is.
  bool get isWorkbook {
    final lower = name.toLowerCase();
    return lower.endsWith('.xlsx') || lower.endsWith('.xlsm');
  }
}

/// Choosing a spreadsheet off the device.
abstract interface class TenantProductSheetPicker {
  /// The chosen file, or null where the person backed out of the picker.
  Future<TenantPickedSheet?> pick();
}

/// What became of a template the person asked for.
enum TenantSheetSaveOutcome {
  /// It reached somewhere - a mail draft, Drive, the downloads folder.
  saved,

  /// The person dismissed the sheet without sending it anywhere.
  dismissed,

  /// The device offered nowhere to send it.
  unavailable,
}

/// Handing a generated template to wherever the person keeps files.
abstract interface class TenantProductSheetSaver {
  Future<TenantSheetSaveOutcome> save({
    required String filename,
    required String contents,
  });
}

/// A sheet that could not be read at all, as opposed to one whose rows are wrong.
///
/// **Separate from a row refusal on purpose.** A row this import will not take
/// is reported beside the row, with the line number the person's own editor
/// shows. A file that is not a spreadsheet has no rows to report against, and
/// saying "line 1 is malformed" about a PDF helps nobody.
final class TenantProductSheetFormatException implements Exception {
  const TenantProductSheetFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The columns a downloaded template carries, in the order it writes them.
///
/// **The name, the size, and the price, then the three the server also
/// accepts.** These are the
/// `_SheetColumn` labels the import parser matches against; a template naming a
/// column the parser does not read would be refused by the import that produced
/// it, which is the one refusal this feature must never produce.
const List<String> productImportTemplateColumns = <String>[
  'name',
  'size',
  'price',
  'cost',
  'quantity',
  'category',
];

/// The template, as the text of a CSV file.
///
/// One example row under the header, because a header alone does not say whether
/// the price is written `1,200` or `1200`, and the first thing anybody does with
/// a template is overwrite its first row.
///
/// [includeCost] is false for a role that may not record what a product costs.
/// The import refuses a cost column from such a person rather than ignoring it,
/// so handing them a template carrying one would hand them a sheet the import
/// will not take.
///
/// [categoryName] is a category this business actually has, so the example row
/// is one the import would accept. A category that does not exist refuses its
/// row, and an example nobody can import teaches the wrong thing.
String productImportTemplateCsv({
  required bool includeCost,
  String? categoryName,
}) {
  final columns = <String>[
    for (final column in productImportTemplateColumns)
      if (includeCost || column != 'cost') column,
  ];
  final example = <String, String>{
    'name': 'White bread loaf',
    'size': '400g',
    'price': '65',
    'cost': '48',
    'quantity': '40',
    'category': categoryName ?? '',
  };
  return <String>[
    columns.join(','),
    <String>[
      for (final column in columns) _csvCell(example[column]!),
    ].join(','),
  ].join('\r\n');
}

/// What the template file is called.
///
/// Stamped with the date rather than a counter, because a person downloads one
/// of these a handful of times and wants to know which is the recent one.
String productImportTemplateFilename(DateTime at) {
  final year = at.year.toString().padLeft(4, '0');
  final month = at.month.toString().padLeft(2, '0');
  final day = at.day.toString().padLeft(2, '0');
  return 'product_import_template_$year-$month-$day.csv';
}

/// Reads a picked file into the delimited text the import parser takes.
///
/// A CSV is returned as its own text. A workbook is flattened to CSV: the import
/// parser is the one authority on what a header and a row mean, and giving a
/// workbook its own parallel parser would be two places to disagree about it.
///
/// Throws [TenantProductSheetFormatException] where the file is not a
/// spreadsheet at all.
String decodeProductSheet(TenantPickedSheet sheet) {
  if (sheet.isWorkbook) return _decodeWorkbook(sheet);
  return _decodeDelimitedText(sheet);
}

String _decodeDelimitedText(TenantPickedSheet sheet) {
  // **A spreadsheet saved as CSV on Windows is very often not UTF-8.** Excel
  // writes the system code page unless asked otherwise, so a strict decode would
  // refuse a file over one accented product name. Falling back to Latin-1 keeps
  // the row and mangles at worst one character of it, which the person can see
  // and fix in the field below; refusing loses the whole sheet.
  try {
    return utf8.decode(sheet.bytes);
  } on FormatException {
    return latin1.decode(sheet.bytes);
  }
}

String _decodeWorkbook(TenantPickedSheet sheet) {
  final xlsx.Excel workbook;
  try {
    workbook = xlsx.Excel.decodeBytes(sheet.bytes);
  } catch (_) {
    throw TenantProductSheetFormatException(
      '${sheet.name} could not be read as a spreadsheet. Save it again as CSV '
      'or as .xlsx and choose it once more.',
    );
  }

  // **The first sheet, and only the first.** A workbook's other tabs are the
  // person's own working notes as often as they are more products, and importing
  // a tab nobody pointed at is how a sheet of suppliers becomes a sheet of
  // products. The old system read one file with one table in it.
  final tableName = workbook.tables.keys.firstOrNull;
  final table = tableName == null ? null : workbook.tables[tableName];
  if (table == null) {
    throw TenantProductSheetFormatException('${sheet.name} holds no sheets.');
  }

  final lines = <String>[];
  for (final row in table.rows) {
    final cells = <String>[for (final cell in row) _cellText(cell?.value)];
    // Excel pads a sheet with blank rows to the last cell anybody ever touched,
    // so a file with twelve products routinely carries a thousand empty rows.
    if (cells.every((cell) => cell.trim().isEmpty)) continue;
    lines.add(<String>[for (final cell in cells) _csvCell(cell)].join(','));
  }
  if (lines.isEmpty) {
    throw TenantProductSheetFormatException('${sheet.name} is empty.');
  }
  return lines.join('\r\n');
}

/// One cell as the text a person typed into it.
///
/// **Every case is spelled out because `toString` is wrong for most of them.**
/// A text cell's value is a rich-text span, a date's is eight separate fields,
/// and a whole number typed into a money column comes back as a double that
/// would otherwise be written `65.0` into a price the parser then has to read
/// back. A formula is worth its computed nothing: the workbook stores the
/// expression, and importing `=B2*1.3` as a price would be worse than refusing.
String _cellText(xlsx.CellValue? value) => switch (value) {
  null => '',
  xlsx.TextCellValue() => value.value.text ?? '',
  xlsx.IntCellValue() => value.value.toString(),
  xlsx.DoubleCellValue() => _number(value.value),
  xlsx.BoolCellValue() => value.value ? 'true' : 'false',
  xlsx.DateCellValue() => value.asDateTimeLocal().toIso8601String(),
  xlsx.DateTimeCellValue() => value.asDateTimeLocal().toIso8601String(),
  xlsx.TimeCellValue() => value.asDuration().toString(),
  // The expression, not a guess at what it evaluates to. The import refuses it
  // as a price, which is the right answer and a legible one.
  xlsx.FormulaCellValue() => value.formula,
};

/// A double as somebody would have typed it: `65` rather than `65.0`.
String _number(double value) =>
    value == value.roundToDouble() && value.abs() < 1e15
    ? value.toInt().toString()
    : value.toString();

/// One CSV cell, quoted only where it has to be.
///
/// The import parser reads comma, tab and semicolon as separators and unwraps
/// double quotes, so a cell holding any of those - or a quote, or a line break -
/// is wrapped and its quotes doubled, which is the ordinary CSV rule.
String _csvCell(String value) {
  final needsQuotes =
      value.contains(',') ||
      value.contains(';') ||
      value.contains('\t') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuotes) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// The file picker this app ships with.
final class FilePickerTenantProductSheetPicker
    implements TenantProductSheetPicker {
  const FilePickerTenantProductSheetPicker();

  @override
  Future<TenantPickedSheet?> pick() async {
    // **`withData`, because the path is not dependable.** A file chosen out of
    // Drive or Downloads on Android arrives as a content URI, and on the web
    // there is never a path; asking the picker for the bytes is the one request
    // that is answered the same way everywhere.
    final result = await FilePicker.platform.pickFiles(
      // **`FileType.any`, deliberately.** A custom-extension filter asks Android
      // to resolve `csv` to a MIME type, and a good number of devices resolve it
      // to nothing and then show a picker with every file greyed out - the exact
      // failure the pre-multitenancy app had on the phones it shipped to. The
      // extension is checked after the fact instead, where a wrong choice can be
      // explained rather than silently unpickable.
      type: FileType.any,
      withData: true,
      dialogTitle: 'Choose a product spreadsheet',
    );
    final file = result?.files.singleOrNull;
    if (file == null) return null;

    final bytes = file.bytes ?? await _readPath(file.path);
    if (bytes == null) {
      throw TenantProductSheetFormatException(
        '${file.name} could not be read off this device.',
      );
    }
    return TenantPickedSheet(name: file.name, bytes: bytes);
  }

  Future<Uint8List?> _readPath(String? path) async {
    if (path == null || kIsWeb) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }
}

/// Writes the template beside the app's own files and offers it to the share
/// sheet, which is where the pre-multitenancy app put it.
///
/// **The share sheet rather than a save dialog**, because that is what puts the
/// file somewhere a person can find it on a phone: mail it to themselves, drop
/// it in Drive, or save it to Downloads, all from one control and none of them
/// needing a storage permission.
final class SharedFileTenantProductSheetSaver
    implements TenantProductSheetSaver {
  const SharedFileTenantProductSheetSaver();

  @override
  Future<TenantSheetSaveOutcome> save({
    required String filename,
    required String contents,
  }) async {
    // **A download, not a share sheet, in a browser.** The control says
    // "Download template", and a browser's downloads folder is where somebody
    // at a computer looks for a file - the reason the share sheet won on a
    // phone does not carry over. The same byte-order mark as below.
    if (kIsWeb) {
      await downloadFromBrowser(
        bytes: utf8.encode('﻿$contents'),
        filename: filename,
      );
      return TenantSheetSaveOutcome.saved;
    }
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$filename');
    // **A byte-order mark, and it earns its three bytes.** Excel opens a UTF-8
    // CSV as the system code page unless one is present, which turns every
    // accented product name into mojibake the moment the person opens the
    // template they were just handed.
    await file.writeAsString('﻿$contents', encoding: utf8);

    final result = await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'text/csv')],
        subject: 'Product import template',
        text: 'Fill this in and upload it back to add products.',
      ),
    );
    return switch (result.status) {
      ShareResultStatus.success => TenantSheetSaveOutcome.saved,
      ShareResultStatus.dismissed => TenantSheetSaveOutcome.dismissed,
      ShareResultStatus.unavailable => TenantSheetSaveOutcome.unavailable,
    };
  }
}
