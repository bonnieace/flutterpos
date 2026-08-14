import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/stats.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

const _tokens = AppTokens.dark;

/// Mounts [child] under the app's own theme, at a stated surface width.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 1200,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Padding(padding: const EdgeInsets.all(20), child: child),
        ),
      ),
    ),
  );
}

TextStyle _styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

StatTile _tile(String label, String value, {AppStatus? status}) => StatTile(
  key: ValueKey(label),
  label: label,
  value: value,
  icon: Icons.payments_outlined,
  status: status,
  statusLabel: status == null ? null : 'Below zero',
);

void main() {
  group('a tile is a caption, a figure, and nothing invented', () {
    testWidgets('the figure is `numeric.hero` and the caption is `label.md`', (
      tester,
    ) async {
      // §2.2 gives `numeric.hero` one use in the whole document - "the one
      // figure a stat tile exists for" - so this is the assertion that says the
      // component is the thing the row was written for.
      await _pump(tester, _tile('Recorded stock', 'KES 1250.50'));

      final figure = _styleOf(tester, 'KES 1250.50');
      expect(figure.fontSize, _tokens.typography.numericHero.fontSize);
      expect(figure.fontWeight, _tokens.typography.numericHero.fontWeight);
      expect(figure.fontFeatures, _tokens.typography.numericHero.fontFeatures);
      expect(figure.color, _tokens.colors.text.primary);

      final caption = _styleOf(tester, 'Recorded stock');
      expect(caption.fontSize, _tokens.typography.labelMedium.fontSize);
      expect(caption.color, _tokens.colors.text.secondary);
    });

    testWidgets('the caption is drawn in the case the caller wrote', (
      tester,
    ) async {
      // `TenantStatCard` uppercased it. §2.2 permits uppercase on
      // `label.eyebrow` only, and permits `label.eyebrow` on field group labels
      // only, so both halves of that rule point away from a stat caption.
      await _pump(tester, _tile('Owners & admins', '2'));

      expect(find.text('Owners & admins'), findsOne);
      expect(find.text('OWNERS & ADMINS'), findsNothing);
    });

    testWidgets('a figure with something to say wears a badge, not a colour', (
      tester,
    ) async {
      // The repair: an `emphasis` colour on the number was §9's "out of stock
      // signalled by red text alone" in another place. §2.1 wants a container,
      // an icon and a word.
      await _pump(
        tester,
        _tile('Recorded stock', '-3', status: AppStatus.problem),
      );

      expect(find.byType(StatusBadge), findsOne);
      expect(find.text('Below zero'), findsOne);
      // The figure itself stays in the text colour every other figure uses.
      expect(_styleOf(tester, '-3').color, _tokens.colors.text.primary);
    });

    testWidgets('an ordinary figure wears no badge at all', (tester) async {
      await _pump(tester, _tile('Ledger entries', '12'));

      expect(find.byType(StatusBadge), findsNothing);
    });

    test('a status without its word is refused at the call site', () {
      // Half of §2.1's triple is not a status. The assertion is the component
      // refusing to be given one.
      expect(
        () => StatTile(
          label: 'Recorded stock',
          value: '-3',
          status: AppStatus.problem,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => StatTile(
          label: 'Recorded stock',
          value: '-3',
          statusLabel: 'Below zero',
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('a row measures what it holds', () {
    test('the minimum tile width is the widest figure plus the padding', () {
      final narrow = StatRow.minimumTileWidth(
        figures: const <String>['12'],
        tokens: _tokens,
        textScaleFactor: 1,
      );
      final wide = StatRow.minimumTileWidth(
        figures: const <String>['12', 'KES 1234567.89'],
        tokens: _tokens,
        textScaleFactor: 1,
      );

      // Every tile in a row is as wide as the row's widest figure needs, which
      // is the whole reason this is measured rather than a constant: the 168 it
      // replaces was set when every figure in this app was two digits.
      expect(wide, greaterThan(narrow));
      expect(narrow, greaterThan(_tokens.spacing.s16 * 2));
    });

    test('a larger text scale asks for a wider tile', () {
      // §9 requires 200% to stay legible, and a fixed minimum cannot honour it.
      expect(
        StatRow.minimumTileWidth(
          figures: const <String>['KES 1250.50'],
          tokens: _tokens,
          textScaleFactor: 2,
        ),
        greaterThan(
          StatRow.minimumTileWidth(
            figures: const <String>['KES 1250.50'],
            tokens: _tokens,
            textScaleFactor: 1,
          ),
        ),
      );
    });

    test('a row never takes fewer than one column, however narrow', () {
      expect(
        StatRow.columnsFor(
          available: 60,
          minimumTileWidth: 220,
          gap: 12,
          tiles: 4,
        ),
        1,
      );
      expect(
        StatRow.columnsFor(
          available: 1200,
          minimumTileWidth: 220,
          gap: 12,
          tiles: 4,
        ),
        4,
      );
      // Never more columns than there are tiles to put in them.
      expect(
        StatRow.columnsFor(
          available: 1200,
          minimumTileWidth: 100,
          gap: 12,
          tiles: 2,
        ),
        2,
      );
    });

    testWidgets('money on a phone is not truncated', (tester) async {
      // The defect this replaces, measured rather than described: at
      // `TenantStatStrip`'s 168 minimum, a 411-wide phone put two money tiles
      // side by side and ellipsised both.
      await _pump(
        tester,
        StatRow(
          tiles: <StatTile>[
            _tile('Sales', 'KES 4820.75'),
            _tile('Sales count', '37'),
          ],
        ),
        width: 411,
      );

      final figure = tester.renderObject<RenderBox>(
        find.text('KES 4820.75'),
      );
      final tile = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('Sales')),
      );
      // **Font-independent, which is what makes it worth asserting here.** A
      // plain `flutter test` renders in a fallback face whose advance widths
      // are not Roboto's - the trap `Disclosure.summaryCharacterBudget` records
      // - but the row measures the figure in *whatever* face is mounted and
      // sizes the tile from that, so the relationship holds in both. What a
      // fixed 168 could not do is hold in either.
      expect(figure.size.width, lessThanOrEqualTo(tile.size.width));
      expect(find.byType(StatTile), findsExactly(2));
    });

    testWidgets('an empty row draws nothing', (tester) async {
      await _pump(tester, const StatRow(tiles: <StatTile>[]));

      expect(find.byType(StatTile), findsNothing);
    });
  });

  group('a line is money in flow', () {
    testWidgets('the figure is `numeric.body`, tabular, and right-aligned', (
      tester,
    ) async {
      await _pump(
        tester,
        const StatLine(label: 'Cash', detail: '20 sales', value: 'KES 2000.25'),
      );

      final figure = tester.widget<Text>(find.text('KES 2000.25'));
      expect(figure.style!.fontSize, _tokens.typography.numericBody.fontSize);
      expect(
        figure.style!.fontFeatures,
        _tokens.typography.numericBody.fontFeatures,
      );
      expect(figure.textAlign, TextAlign.right);
      expect(_styleOf(tester, 'Cash').color, _tokens.colors.text.secondary);
      expect(_styleOf(tester, '20 sales').color, _tokens.colors.text.tertiary);
    });

    testWidgets('two lines put their figures at the same right edge', (
      tester,
    ) async {
      // The point of the whole component: `Cash: KES 2000.25 over 20 sales`
      // started its amount at a different column on every row.
      await _pump(
        tester,
        const Column(
          children: <Widget>[
            StatLine(label: 'Cash', value: 'KES 2000.25'),
            StatLine(label: 'M-Pesa', value: 'KES 900.00'),
          ],
        ),
      );

      double rightEdgeOf(String text) {
        final box = tester.renderObject<RenderBox>(find.text(text));
        return box.localToGlobal(Offset(box.size.width, 0)).dx;
      }

      expect(rightEdgeOf('KES 2000.25'), rightEdgeOf('KES 900.00'));
    });

    testWidgets('a total reads as the answer rather than as another entry', (
      tester,
    ) async {
      await _pump(
        tester,
        const StatLine(label: 'Sales', value: 'KES 1250.50', emphasis: true),
      );

      expect(_styleOf(tester, 'Sales').color, _tokens.colors.text.primary);
    });
  });
}
