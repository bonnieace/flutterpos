/// The token layer, carried across into a spreadsheet.
///
/// The sibling of `report_palette.dart`, and separate from it for the reason
/// that file gives: each renderer crosses the boundary into its own output
/// library and neither should drag in the other's. A workbook has no use for a
/// `PdfColor` and a document has none for an `ExcelColor`.
///
/// **The branding here is typographic, and that is a limitation rather than a
/// taste.** The `excel` package writes fonts, fills, borders, merges and column
/// widths, but it cannot embed an image at all - there is no drawing writer in
/// it - so a business's logo cannot be placed in a sheet the way it can on a
/// page. The workbook therefore leads with the business's name set large in the
/// brand accent rather than with its mark. The PDF carries the full lockup.
library;

import 'package:excel/excel.dart';
import 'package:flutter/painting.dart' show Color;

import '../../ui/tokens.dart';

/// `AppReportRoles`, in the colour type a workbook understands.
final class TenantReportWorkbookPalette {
  const TenantReportWorkbookPalette({
    required this.paper,
    required this.wash,
    required this.ink,
    required this.mutedInk,
    required this.rule,
    required this.accent,
    required this.onAccent,
  });

  factory TenantReportWorkbookPalette.of(AppReportRoles roles) =>
      TenantReportWorkbookPalette(
        paper: _convert(roles.paper),
        wash: _convert(roles.wash),
        ink: _convert(roles.ink),
        mutedInk: _convert(roles.mutedInk),
        rule: _convert(roles.rule),
        accent: _convert(roles.accent),
        onAccent: _convert(roles.onAccent),
      );

  static final TenantReportWorkbookPalette standard =
      TenantReportWorkbookPalette.of(AppReportRoles.dark);

  final ExcelColor paper;
  final ExcelColor wash;
  final ExcelColor ink;
  final ExcelColor mutedInk;
  final ExcelColor rule;
  final ExcelColor accent;
  final ExcelColor onAccent;
}

/// `excel` wants `AARRGGBB`, and it wants the alpha.
ExcelColor _convert(Color color) {
  String channel(double value) =>
      (value * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return ExcelColor.fromHexString(
    '${channel(color.a)}${channel(color.r)}${channel(color.g)}'
            '${channel(color.b)}'
        .toUpperCase(),
  );
}
