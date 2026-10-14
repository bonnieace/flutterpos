import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/ui/record_list.dart';
import 'package:uzapay_pos/ui/record_sheet.dart';
import 'package:uzapay_pos/ui/scaffold.dart';
import 'package:uzapay_pos/ui/states.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:uzapay_pos/ui/tokens.dart';

/// `SheetLayout`'s arithmetic, and the sheet's own drawing.
///
/// **Widths are asserted as relations, never as pixels.** A widget test's font
/// draws every glyph a full em wide, so what a column needs here is not what it
/// needs in the app; that it is equal to its neighbour, or fits the room, is
/// true in both. The pixels belong to the screenshot harness.
void main() {
  const tokens = AppTokens.uzapay;

  const columns = <SheetColumn>[
    SheetColumn(label: 'Name', kind: SheetColumnKind.identity),
    SheetColumn(label: 'Hours', kind: SheetColumnKind.time),
    SheetColumn(label: 'Sales', kind: SheetColumnKind.figure),
    SheetColumn(label: 'Total', kind: SheetColumnKind.figure, unit: 'KES'),
    SheetColumn(label: 'Standing', kind: SheetColumnKind.status),
  ];

  SheetRow row(String id, String name, String total) => SheetRow(
    id: id,
    cells: <SheetCell?>[
      SheetText(name),
      const SheetText('06:00–18:00'),
      const SheetFigure('3'),
      SheetFigure(total),
      const SheetStatus(status: AppStatus.problem, label: 'Short'),
    ],
  );

  final rows = <SheetRow>[
    row('a', 'Amina Hassan', '1,250'),
    row('b', 'Brian Kimani', '987.50'),
  ];

  double sum(SheetLayout layout) =>
      layout.columns.fold<double>(0, (total, width) => total + width) +
      (layout.leading ?? 0) +
      (layout.trailing ?? 0) +
      layout.gap * (layout.columns.length - 1);

  testWidgets('with room to spare every column is the same width', (
    tester,
  ) async {
    final layout = SheetLayout.resolve(
      tokens: tokens,
      columns: columns,
      rows: rows,
      available: 4000,
    );

    final first = layout.columns.first;
    for (final width in layout.columns) {
      expect(width, closeTo(first, 0.001));
    }
    expect(sum(layout), closeTo(4000, 0.5));
  });

  testWidgets('a name column takes its share by flex', (tester) async {
    final layout = SheetLayout.resolve(
      tokens: tokens,
      columns: const <SheetColumn>[
        SheetColumn(label: 'Name', kind: SheetColumnKind.identity, flex: 2),
        SheetColumn(label: 'Sales', kind: SheetColumnKind.figure),
      ],
      rows: const <SheetRow>[
        SheetRow(
          id: 'a',
          cells: <SheetCell?>[SheetText('A'), SheetFigure('1')],
        ),
      ],
      available: 4000,
    );

    expect(layout.columns[0], closeTo(layout.columns[1] * 2, 0.001));
  });

  testWidgets('narrower, the figure columns stay equal to one another', (
    tester,
  ) async {
    // A name too long to share one width with the figures: it takes what it
    // needs, and the figures keep one width between them.
    final long = <SheetRow>[
      ...rows,
      row('c', 'Wanjiku Mwangi-Otieno of Westlands', '45,000'),
    ];
    final layout = SheetLayout.resolve(
      tokens: tokens,
      columns: columns,
      rows: long,
      available: 1600,
    );

    final figures = layout.columns.sublist(1);
    for (final width in figures) {
      expect(width, closeTo(figures.first, 0.001));
    }
    expect(layout.columns.first, greaterThan(figures.first));
    expect(sum(layout), lessThanOrEqualTo(1600 + 0.5));
  });

  testWidgets('at any width the row fits the room it was given', (
    tester,
  ) async {
    for (final available in <double>[200, 600, 900, 1200, 2000]) {
      final layout = SheetLayout.resolve(
        tokens: tokens,
        columns: columns,
        rows: rows,
        available: available,
      );
      expect(
        sum(layout),
        lessThanOrEqualTo(available + 0.5),
        reason: '$available',
      );
      for (final width in layout.columns) {
        expect(width, greaterThanOrEqualTo(0), reason: '$available');
      }
    }
  });

  testWidgets('a disclosure and a menu each take a 48 column of their own', (
    tester,
  ) async {
    final layout = SheetLayout.resolve(
      tokens: tokens,
      columns: const <SheetColumn>[
        SheetColumn(label: 'Name', kind: SheetColumnKind.identity),
      ],
      rows: <SheetRow>[
        SheetRow(
          id: 'a',
          cells: const <SheetCell?>[SheetText('A')],
          fold: const SheetFold(note: 'Why'),
          actions: <RecordAction>[
            RecordAction(label: 'Open', onPressed: () {}),
          ],
        ),
      ],
      available: 1000,
    );

    expect(layout.leading, tokens.density.minimumTapTarget.width);
    expect(layout.trailing, tokens.density.minimumTapTarget.width);
  });

  testWidgets('no band names a group and no sentence sits at the foot', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[tokens]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecordSheet(columns: columns, rows: rows),
          ),
        ),
      ),
    );

    // The header and two rows, and nothing between or after them.
    expect(find.text('NAME', findRichText: true), findsOne);
    expect(find.text('Amina Hassan'), findsOne);
    expect(find.text('Brian Kimani'), findsOne);
    expect(tester.takeException(), isNull);
  });

  // **The developer's choice on 2026-10-13**, narrowed on 2026-10-14: an empty
  // sheet is one panel to the foot of the window, and a sheet with rows stops
  // at its last row rather than leaving empty panel under it.
  group('only an empty sheet reaches the foot of the window', () {
    testWidgets('page margins stay equal through desktop window resizes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[tokens]),
          home: Builder(
            builder: (context) => AppScaffold(
              title: 'Records',
              contentWidth: RecordSheet.contentWidth(context),
              body: ListView(
                padding: RecordSheet.pagePadding(
                  context,
                  fallback: const EdgeInsets.all(20),
                ),
                children: <Widget>[
                  RecordSheet(
                    key: const ValueKey('sheet'),
                    columns: columns,
                    rows: const <SheetRow>[],
                    body: const EmptyState(title: 'Nothing here'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      for (final width in <double>[1440, 1920, 1024, 1023]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        final sheet = tester.getRect(find.byKey(const ValueKey('sheet')));
        final bar = tester.getRect(find.byType(AppBar));
        final margin = width >= 1024 ? 24.0 : 20.0;
        expect(sheet.left, closeTo(margin, 0.5));
        expect(width - sheet.right, closeTo(margin, 0.5));
        expect(900 - sheet.bottom, closeTo(margin, 0.5));
        expect(
          sheet.top - bar.bottom,
          closeTo(width >= 1024 ? margin : margin + 8, 0.5),
        );
        expect(tester.takeException(), isNull);
      }
    });

    Future<void> pump(
      WidgetTester tester, {
      required Widget Function(Widget sheet) scroll,
      List<SheetRow>? sheetRows,
      Widget? body,
    }) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[tokens]),
          home: Scaffold(
            body: scroll(
              RecordSheet(
                key: const ValueKey('sheet'),
                columns: columns,
                rows: sheetRows ?? rows,
                body: body,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    double bottom(WidgetTester tester) =>
        tester.getBottomLeft(find.byKey(const ValueKey('sheet'))).dy;

    const empty = EmptyState(title: 'Nothing here');

    testWidgets('in a list, an empty sheet stretches to the bottom padding', (
      tester,
    ) async {
      await pump(
        tester,
        body: empty,
        scroll: (sheet) => ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[const SizedBox(height: 100), sheet],
        ),
      );

      expect(bottom(tester), closeTo(800 - 20, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('in a single-child scroll view, an empty sheet does the same', (
      tester,
    ) async {
      await pump(
        tester,
        body: empty,
        // Held to the full height, as `AppScaffold`'s `Expanded` holds every
        // screen's body.
        scroll: (sheet) => SizedBox.expand(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[sheet, const SizedBox(height: 60)],
            ),
          ),
        ),
      );

      // What follows the sheet keeps its place at the foot.
      expect(bottom(tester), closeTo(800 - 20 - 60, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short table with rows stops at its last row', (
      tester,
    ) async {
      await pump(
        tester,
        scroll: (sheet) => ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[sheet],
        ),
      );

      expect(bottom(tester), lessThan(800 - 20 - 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a table long enough to scroll is not stretched', (
      tester,
    ) async {
      await pump(
        tester,
        scroll: (sheet) => ListView(children: <Widget>[sheet]),
        sheetRows: <SheetRow>[
          for (var index = 0; index < 30; index++)
            row('r$index', 'Person $index', '1,000'),
        ],
      );

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final natural = tester.getSize(find.byKey(const ValueKey('sheet')));
      // As tall as its rows make it, so the list scrolls exactly that far.
      expect(
        scrollable.position.maxScrollExtent,
        closeTo(natural.height - 800, 0.5),
      );
    });
  });
}
