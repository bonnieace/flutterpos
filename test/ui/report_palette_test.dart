/// The paper palette, measured rather than asserted.
///
/// `AppReportRoles` makes two claims its doc comment cannot keep on its own:
/// that every colour a document draws with is legible on white, and that the
/// eight categorical members can be told apart from one another. Both are
/// arithmetic, so both are checked here.
///
/// The second is the one that matters and the one a screen palette fails. The
/// app's own `chart.series` separates its members by *lightness*, which is what
/// works against a near-black ground. Re-grounded for paper that axis collapses
/// and four of its eight members land on top of each other. This file is what
/// stops somebody noticing the two palettes look similar and quietly pointing
/// one at the other.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/wcag.dart';

/// CIE L*a*b*, for a distance that follows the eye rather than the byte.
///
/// Euclidean distance in RGB calls two dark colours similar and two light ones
/// different when the eye says the opposite, so a separation claim measured
/// that way is not a claim about legibility.
({double l, double a, double b}) _lab(Color color) {
  double linear(double channel) => channel <= 0.04045
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

  final r = linear(color.r);
  final g = linear(color.g);
  final b = linear(color.b);

  final x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047;
  final y = r * 0.2126 + g * 0.7152 + b * 0.0722;
  final z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883;

  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;

  final fx = f(x);
  final fy = f(y);
  final fz = f(z);
  return (l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz));
}

double _difference(Color first, Color second) {
  final a = _lab(first);
  final b = _lab(second);
  return math.sqrt(
    math.pow(a.l - b.l, 2) + math.pow(a.a - b.a, 2) + math.pow(a.b - b.b, 2),
  );
}

/// Below this two swatches beside each other start being argued about.
const double _distinguishable = 25;

void main() {
  const report = AppReportRoles.dark;

  group('a document is legible on the paper it prints on', () {
    test('body ink reaches the enhanced threshold, not merely the floor', () {
      // A report gets printed, photocopied and read on a phone in a shop. AAA
      // here costs nothing - the ink is nearly black either way - and buys the
      // third of those.
      expect(
        contrastRatio(report.ink, report.paper),
        greaterThanOrEqualTo(7),
        reason: 'Body figures are what the whole document is for.',
      );
    });

    test('a caption and an axis label still clear body text contrast', () {
      for (final MapEntry(key: role, value: colour)
          in <String, Color>{
            'mutedInk': report.mutedInk,
            'axisLabel': report.axisLabel,
          }.entries) {
        expect(
          contrastRatio(colour, report.paper),
          greaterThanOrEqualTo(bodyTextContrast),
          reason:
              '$role carries words. A provenance line nobody can read is a '
              'provenance line that is not there.',
        );
      }
    });

    test('a label on the accent band is legible against it', () {
      expect(
        contrastRatio(report.onAccent, report.accent),
        greaterThanOrEqualTo(bodyTextContrast),
        reason: 'The business name sits on this band.',
      );
    });

    test('every categorical colour clears the graphics threshold', () {
      for (var index = 0; index < report.series.length; index++) {
        expect(
          contrastRatio(report.series[index], report.paper),
          greaterThanOrEqualTo(largeTextContrast),
          reason:
              'series[$index] is a slice or a bar a reader has to see the '
              'edge of. WCAG 1.4.11 puts non-text graphics at 3:1.',
        );
      }
    });

    test('the bars clear it too', () {
      for (final MapEntry(key: role, value: colour)
          in <String, Color>{
            'bar': report.bar,
            'barEmphasis': report.barEmphasis,
          }.entries) {
        expect(
          contrastRatio(colour, report.paper),
          greaterThanOrEqualTo(largeTextContrast),
          reason: '$role is a shape whose height is the measurement.',
        );
      }
    });

    test('a rule and a grid line stay faint, which is their job', () {
      // The one place a low ratio is correct. A grid line that competed with
      // the bars would be a grid line drawn wrong, and it carries no fact - the
      // figures beside the chart do.
      for (final MapEntry(key: role, value: colour)
          in <String, Color>{
            'rule': report.rule,
            'gridLine': report.gridLine,
          }.entries) {
        expect(
          contrastRatio(colour, report.paper),
          lessThan(largeTextContrast),
          reason: '$role is furniture. Nothing is read off it.',
        );
      }
    });
  });

  group('the categorical palette can actually be told apart', () {
    test('no two members are within arguing distance', () {
      final series = report.series;
      for (var i = 0; i < series.length; i++) {
        for (var j = i + 1; j < series.length; j++) {
          expect(
            _difference(series[i], series[j]),
            greaterThanOrEqualTo(_distinguishable),
            reason:
                'series[$i] and series[$j] would be argued about on an '
                'eight-category ring, which is exactly the chart this palette '
                'exists to draw.',
          );
        }
      }
    });

    test('adjacent members are further apart still', () {
      // Adjacency is what a ring puts side by side, and two slices sharing an
      // edge are the hardest pair to separate.
      for (var index = 0; index < report.series.length - 1; index++) {
        expect(
          _difference(report.series[index], report.series[index + 1]),
          greaterThanOrEqualTo(_distinguishable),
          reason: 'series[$index] shares an edge with the next one.',
        );
      }
    });

    test('it holds eight, because the expense categories are eight', () {
      expect(
        report.series.length,
        8,
        reason:
            'TenantExpenseCategory is a closed enum of eight. A ring that ran '
            'out of colours would repeat one and claim two headings were the '
            'same heading.',
      );
    });

    test('no member lands in the status band', () {
      // Red means problem and amber means attention everywhere else in this
      // app. A slice for Transport must not read as a warning about transport.
      for (var index = 0; index < report.series.length; index++) {
        final hue = HSVColor.fromColor(report.series[index]).hue;
        final saturation = HSVColor.fromColor(report.series[index]).saturation;
        if (saturation < 0.15) continue;
        expect(
          hue > 60 || hue < 0,
          isTrue,
          reason:
              'series[$index] sits at hue $hue, inside the red-to-amber band '
              'the status roles own.',
        );
      }
    });
  });

  group('paper is not the screen', () {
    test('the report series is not the chart series', () {
      expect(
        report.series,
        isNot(AppChartRoles.dark.series),
        reason:
            'The screen palette separates by lightness against near-black. '
            'Re-grounded for white that axis collapses and four of its eight '
            'members merge. The two are different palettes on purpose.',
      );
    });

    test('the screen series would in fact fail on paper', () {
      // The claim the doc comment makes, held to. If a future palette change
      // ever made this pass, the argument for a separate role set is gone and
      // somebody should be told rather than left to find out on a printer.
      final screen = AppChartRoles.dark.series;
      final failures = <int>[
        for (var index = 0; index < screen.length; index++)
          if (contrastRatio(screen[index], report.paper) < largeTextContrast)
            index,
      ];
      expect(
        failures,
        isNotEmpty,
        reason:
            'AppChartRoles is tuned for a near-black ground, so some of it is '
            'expected to wash out on white. That is why AppReportRoles exists.',
      );
    });

    test('the page is lighter than any surface the app paints', () {
      expect(
        report.paper.computeLuminance(),
        greaterThan(AppSurfaceRoles.dark.raised.computeLuminance()),
        reason: 'Stating the obvious, so a copy-paste of a surface role here '
            'fails rather than ships.',
      );
    });
  });
}
