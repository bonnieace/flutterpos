import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/pagination.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/wcag.dart';

void main() {
  group('Pagination', () {
    testWidgets('draws §5.1s three parts', (tester) async {
      // §5.1's row is "low-contrast Previous / **Page N** / Next", and eleven of
      // the thirteen bars this replaces never told a person which page they
      // were on at all.
      await _pump(tester, pageNumber: 3);

      expect(find.text('Previous page'), findsOne);
      expect(find.text('Page 3'), findsOne);
      expect(find.text('Next page'), findsOne);
    });

    testWidgets('disables rather than hides, at either end', (tester) async {
      // The bar moving under a thumb as a person pages is the defect. §5's
      // matrix has a `disabled` row for it.
      await _pump(tester, pageNumber: 1, previous: null);
      expect(find.text('Previous page'), findsOne);
      expect(_button(tester, 'Previous page').onPressed, isNull);
      expect(_button(tester, 'Next page').onPressed, isNotNull);

      await _pump(tester, pageNumber: 9, next: null);
      expect(find.text('Next page'), findsOne);
      expect(_button(tester, 'Next page').onPressed, isNull);
    });

    testWidgets('both controls are secondary, which the tree had decided', (
      tester,
    ) async {
      // §2.1 permits one primary per screen region and on a records page that
      // is not "Next page". Eleven of the thirteen already drew it; the catalog
      // and the bulk route drew `tertiary` and moved to match.
      await _pump(tester, pageNumber: 2);

      expect(_button(tester, 'Previous page').tier, AppButtonTier.secondary);
      expect(_button(tester, 'Next page').tier, AppButtonTier.secondary);
    });

    testWidgets('answers §9s 48dp target at both ends', (tester) async {
      await _pump(tester, pageNumber: 1, previous: null);

      for (final label in const <String>['Previous page', 'Next page']) {
        final size = tester.getSize(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(AppButton),
          ),
        );
        expect(size.height, greaterThanOrEqualTo(48), reason: label);
      }
    });

    testWidgets('states the page above §9s 4.5:1, not in caption', (
      tester,
    ) async {
      // §9's own failure list opens with "caption text at 3.4:1 and 3.7:1", so
      // the page statement takes `label.md` at `text.secondary` instead.
      const tokens = AppTokens.dark;
      expect(
        contrastRatio(
          tokens.colors.text.secondary,
          tokens.colors.surface.base,
        ),
        greaterThanOrEqualTo(4.5),
      );

      await _pump(tester, pageNumber: 3);
      final label = tester.widget<Text>(find.text('Page 3'));
      expect(label.style?.color, tokens.colors.text.secondary);
      expect(label.style?.fontSize, tokens.typography.labelMedium.fontSize);
    });

    testWidgets('wraps rather than overflowing on a phone', (tester) async {
      // Two 48-high pills with two-word labels plus a statement do not fit 411
      // logical pixels beside each other, and a `Row` answers that by
      // overflowing - the defect `ConfirmDialog` and `ErrorState` both record.
      tester.view.physicalSize = const Size(411, 891);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _pump(tester, pageNumber: 3);

      expect(tester.takeException(), isNull);
      expect(find.byType(Wrap), findsOne);
    });
  });
}

AppButton _button(WidgetTester tester, String label) => tester.widget<AppButton>(
  find.ancestor(of: find.text(label), matching: find.byType(AppButton)),
);

Future<void> _pump(
  WidgetTester tester, {
  required int pageNumber,
  VoidCallback? previous = _noop,
  VoidCallback? next = _noop,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: Pagination(
          pageNumber: pageNumber,
          onPrevious: previous,
          onNext: next,
        ),
      ),
    ),
  );
  await tester.pump();
}

void _noop() {}
