/// The typefaces a generated document is set in.
///
/// **The brand's own faces, because the app already ships them.** `pubspec.yaml`
/// bundles Hanken Grotesk in four weights and JetBrains Mono in two, and the
/// `pdf` package embeds a TTF directly. So a report is set in the same faces as
/// the screen it was generated from rather than in the viewer's default, which
/// is most of the difference between a document that looks like the business
/// and one that looks like a database dump.
///
/// **Loading is I/O, so it is injected.** `CheckoutReceiptBody` takes a loaded
/// `CapabilityProfile` rather than loading one, for the reason this does the
/// same: a renderer that reached for an asset bundle could not be exercised
/// without a Flutter binding, and the point of building documents out of pure
/// `pw.Widget`s is that they can be.
library;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// The faces a document draws with.
final class TenantReportFonts {
  const TenantReportFonts({
    required this.regular,
    required this.medium,
    required this.semiBold,
    required this.bold,
    required this.mono,
    required this.monoMedium,
  });

  /// The bundled faces, loaded once and held.
  ///
  /// **Held, because a report should not re-parse 900KB of TrueType.** The six
  /// faces are the same for every report this process ever renders, and the
  /// parse is the slowest part of generating a short one. The future is cached
  /// rather than the value so two reports asked for at once share one read.
  ///
  /// Pass [bundle] to force a fresh load against a particular bundle; that
  /// path is uncached, because a test supplying its own bundle wants its own
  /// answer.
  static Future<TenantReportFonts> bundled({AssetBundle? bundle}) {
    if (bundle != null) return load(bundle: bundle);
    return _held ??= load();
  }

  static Future<TenantReportFonts>? _held;

  /// The bundled brand faces.
  ///
  /// [bundle] defaults to the app's own. A failure to read any one of them
  /// falls back to [standard] whole rather than to a document set half in one
  /// family and half in another - a mixed document looks like a bug, and a
  /// wholly Helvetica one merely looks plain.
  static Future<TenantReportFonts> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    try {
      final faces = await Future.wait(<Future<pw.Font>>[
        _face(assets, 'fonts/HankenGrotesk-Regular.ttf'),
        _face(assets, 'fonts/HankenGrotesk-Medium.ttf'),
        _face(assets, 'fonts/HankenGrotesk-SemiBold.ttf'),
        _face(assets, 'fonts/HankenGrotesk-Bold.ttf'),
        _face(assets, 'fonts/JetBrainsMono-Regular.ttf'),
        _face(assets, 'fonts/JetBrainsMono-Medium.ttf'),
      ]);
      return TenantReportFonts(
        regular: faces[0],
        medium: faces[1],
        semiBold: faces[2],
        bold: faces[3],
        mono: faces[4],
        monoMedium: faces[5],
      );
    } on Object {
      return TenantReportFonts.standard();
    }
  }

  /// The `pdf` package's built-in faces.
  ///
  /// Every PDF viewer has these without embedding, so this always works. It is
  /// what a test uses, and what a device falls back to if an asset read fails.
  factory TenantReportFonts.standard() => TenantReportFonts(
    regular: pw.Font.helvetica(),
    medium: pw.Font.helvetica(),
    semiBold: pw.Font.helveticaBold(),
    bold: pw.Font.helveticaBold(),
    mono: pw.Font.courier(),
    monoMedium: pw.Font.courierBold(),
  );

  final pw.Font regular;
  final pw.Font medium;
  final pw.Font semiBold;
  final pw.Font bold;

  /// Figures are set in the monospace face, as they are on screen.
  ///
  /// The app's numeric type roles are all tabular for a reason: a column of
  /// money whose digits do not line up cannot be scanned, and a report is
  /// mostly columns of money.
  final pw.Font mono;
  final pw.Font monoMedium;

  /// The theme these faces make, handed to the document once.
  pw.ThemeData theme() => pw.ThemeData.withFont(
    base: regular,
    bold: bold,
    italic: regular,
    boldItalic: bold,
  );

  static Future<pw.Font> _face(AssetBundle bundle, String path) async =>
      pw.Font.ttf(await bundle.load(path));
}
