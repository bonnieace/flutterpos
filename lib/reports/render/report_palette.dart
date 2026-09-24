/// The token layer, carried across the boundary into a document.
///
/// **The one file in `render/` that imports Flutter.** Everything else under
/// here builds `pw.Widget`s, and `package:pdf/widgets.dart` is standalone Dart
/// with no Flutter dependency at all - which is what lets a whole report be
/// rendered inside a plain `test` with no widget tree, no `View`, and no pumped
/// frame. That property is worth protecting, so the conversion from
/// `AppReportRoles` to the `pdf` package's own colour type happens once, here,
/// and the renderers take the result.
///
/// The colours themselves are not chosen here. They come from
/// `AppReportRoles`, which lives in `lib/ui/tokens.dart` because hard rule 2
/// says the token layer is where a colour is decided and a widget is where one
/// is read. This is the reading.
library;

import 'package:flutter/painting.dart' show Color;
import 'package:pdf/pdf.dart';

import '../../ui/tokens.dart';

/// `AppReportRoles`, in the colour type a PDF understands.
final class TenantReportPalette {
  const TenantReportPalette({
    required this.paper,
    required this.wash,
    required this.ink,
    required this.mutedInk,
    required this.rule,
    required this.accent,
    required this.onAccent,
    required this.bar,
    required this.barEmphasis,
    required this.gridLine,
    required this.axisLabel,
    required this.series,
  });

  /// Reads the palette out of the token layer.
  ///
  /// Takes the roles rather than a `BuildContext`, so a test can build a
  /// document without pumping a widget and the renderers stay reachable from
  /// pure Dart. The composition root passes `AppTokens.componentOf(context)
  /// .colors.report`.
  factory TenantReportPalette.of(AppReportRoles roles) => TenantReportPalette(
    paper: _convert(roles.paper),
    wash: _convert(roles.wash),
    ink: _convert(roles.ink),
    mutedInk: _convert(roles.mutedInk),
    rule: _convert(roles.rule),
    accent: _convert(roles.accent),
    onAccent: _convert(roles.onAccent),
    bar: _convert(roles.bar),
    barEmphasis: _convert(roles.barEmphasis),
    gridLine: _convert(roles.gridLine),
    axisLabel: _convert(roles.axisLabel),
    series: List<PdfColor>.unmodifiable(roles.series.map(_convert)),
  );

  /// The palette a renderer gets when nobody supplied one.
  ///
  /// The same values `AppReportRoles.dark` holds. It exists so a test, and the
  /// sample-rendering tool, can build a document without standing up a theme.
  static final TenantReportPalette standard = TenantReportPalette.of(
    AppReportRoles.dark,
  );

  final PdfColor paper;
  final PdfColor wash;
  final PdfColor ink;
  final PdfColor mutedInk;
  final PdfColor rule;
  final PdfColor accent;
  final PdfColor onAccent;
  final PdfColor bar;
  final PdfColor barEmphasis;
  final PdfColor gridLine;
  final PdfColor axisLabel;

  /// The categorical palette, in the order a chart should consume it.
  final List<PdfColor> series;

  /// The colour for the nth category, wrapping if a chart somehow has more
  /// categories than the palette has members.
  ///
  /// **Wrapping is a last resort, not a design.** The series holds eight
  /// because the expense categories are a closed enum of eight; anything that
  /// reaches a ninth is drawing something this palette was not sized for, and
  /// the repeat is better than a crash but it is still two headings wearing one
  /// colour. A chart in that position must lean on its labelled rows, which
  /// `TenantReportVisual` guarantees it has.
  PdfColor seriesAt(int index) => series[index % series.length];
}

/// Flutter's channels are already 0..1 doubles, and so are the `pdf` package's,
/// so this loses nothing.
PdfColor _convert(Color color) =>
    PdfColor(color.r, color.g, color.b, color.a);
