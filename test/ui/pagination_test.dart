import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/fields.dart';
import 'package:flutter_application_1/ui/pagination.dart';
import 'package:flutter_application_1/ui/press.dart';
import 'package:flutter_application_1/ui/rolling_number.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/wcag.dart';

const ValueKey<String> _previous = ValueKey<String>('previous');
const ValueKey<String> _next = ValueKey<String>('next');
const ValueKey<String> _page = ValueKey<String>('page');

void main() {
  final tokens = spiritTheme.extension<AppTokens>()!;

  group('Pagination', () {
    testWidgets('draws one pager: the way back, where you are, the way on', (
      tester,
    ) async {
      await _pump(tester, pageNumber: 3);

      expect(find.text('Previous'), findsOne);
      expect(find.text('Page'), findsOne);
      expect(_figure(tester), '3');
      expect(find.text('Next'), findsOne);
      // The two words sit either side of the position, on one row.
      final previous = tester.getCenter(find.text('Previous'));
      final page = tester.getCenter(find.text('Page'));
      final next = tester.getCenter(find.text('Next'));
      expect(previous.dx, lessThan(page.dx));
      expect(page.dx, lessThan(next.dx));
      expect((previous.dy - next.dy).abs(), lessThan(1));
    });

    testWidgets('the figure is the one role that rolls', (tester) async {
      await _pump(tester, pageNumber: 3);

      final figure = tester.widget<RollingNumber>(find.byType(RollingNumber));
      expect(figure.value, '3');
      expect(figure.spring, RollingNumberSpring.snappy);
      expect(figure.style.fontFamily, tokens.typography.numericBody.fontFamily);
      expect(figure.style.color, tokens.colors.text.primary);
    });

    testWidgets('disables rather than hides, at either end', (tester) async {
      // The bar moving under a thumb as a person pages is the defect. §5's
      // matrix has a `disabled` row for it.
      await _pump(tester, pageNumber: 1, previous: null);
      expect(find.text('Previous'), findsOne);
      expect(_surface(tester, _previous).onPressed, isNull);
      expect(_surface(tester, _next).onPressed, isNotNull);

      await _pump(tester, pageNumber: 9, next: null);
      expect(find.text('Next'), findsOne);
      expect(_surface(tester, _next).onPressed, isNull);
      expect(_surface(tester, _previous).onPressed, isNotNull);
    });

    testWidgets('a disabled segment steps its ink down and keeps its '
        'container', (tester) async {
      await _pump(tester, pageNumber: 1, previous: null);

      final disabled = tester.widget<Text>(find.text('Previous'));
      final enabled = tester.widget<Text>(find.text('Next'));
      expect(disabled.style?.color, tokens.colors.action.disabledLabel);
      expect(enabled.style?.color, tokens.colors.action.secondary.label);
      // No slab: the disabled segment has no container of its own, so it
      // cannot out-paint the live one beside it, which is what the old
      // `disabledContainer` buttons did.
      expect(
        find.descendant(
          of: find.byKey(_previous),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).color ==
                    tokens.colors.action.disabledContainer,
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('pages through its callbacks', (tester) async {
      var previous = 0;
      var next = 0;
      await _pump(
        tester,
        pageNumber: 4,
        previous: () => previous++,
        next: () => next++,
      );

      await tester.tap(find.byKey(_next));
      await tester.tap(find.byKey(_previous));
      expect(next, 1);
      expect(previous, 1);
    });

    testWidgets('answers §9s 48dp target on both segments, glyphs included', (
      tester,
    ) async {
      for (final scale in <double>[1, 2]) {
        await _pump(tester, pageNumber: 4, textScale: scale);
        for (final key in <Key>[_previous, _next]) {
          final size = tester.getSize(find.byKey(key));
          expect(size.height, greaterThanOrEqualTo(48), reason: '$key $scale');
          expect(size.width, greaterThanOrEqualTo(48), reason: '$key $scale');
        }
      }
    });

    testWidgets('states the page above §9s 4.5:1, not in caption', (
      tester,
    ) async {
      // §9's own failure list opens with "caption text at 3.4:1 and 3.7:1", so
      // the word takes `label.md` at `text.secondary` instead.
      expect(
        contrastRatio(
          tokens.colors.text.secondary,
          tokens.colors.action.secondary.container,
        ),
        greaterThanOrEqualTo(4.5),
      );

      await _pump(tester, pageNumber: 3);
      final word = tester.widget<Text>(find.text('Page'));
      expect(word.style?.color, tokens.colors.text.secondary);
      expect(word.style?.fontSize, tokens.typography.labelMedium.fontSize);
    });

    testWidgets('takes the row on a phone and its own width on a monitor', (
      tester,
    ) async {
      _screen(tester, const Size(411, 891));
      await _pump(tester, pageNumber: 4);
      final phone = tester.getRect(find.byType(Pagination));
      final phoneNext = tester.getRect(find.byKey(_next));
      // Both nav segments split what the position leaves.
      expect(
        tester.getSize(find.byKey(_previous)).width,
        moreOrLessEquals(phoneNext.width, epsilon: 1),
      );
      expect(phoneNext.right, greaterThan(phone.right - 8));

      _screen(tester, const Size(1440, 900));
      await _pump(tester, pageNumber: 4);
      final desk = tester.getRect(find.byType(Pagination));
      final prev = tester.getRect(find.byKey(_previous));
      final next = tester.getRect(find.byKey(_next));
      // At its own width, at the end of the row: the two controls are a
      // thumb's width apart, not the window's.
      expect(next.right, greaterThan(desk.right - 8));
      expect(next.left - prev.right, lessThan(200));
    });

    testWidgets('keeps the words at 100% and gives them up at 200% on a '
        'phone', (tester) async {
      // Compact, and wider than a handset: the test font draws every glyph a
      // full em wide, so its words need the room real ones find at 411. The
      // harness's `95-pagination-states` is the picture at 411 itself.
      _screen(tester, const Size(600, 891));
      await _pump(tester, pageNumber: 4);
      expect(find.text('Previous'), findsOne);
      expect(find.text('Next'), findsOne);

      await _pump(tester, pageNumber: 4, textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.text('Previous'), findsNothing);
      expect(find.text('Next'), findsNothing);
      // The position is the part that never gives up its room.
      expect(find.text('Page'), findsOne);
      expect(_figure(tester), '4');
      // And the words move to semantics rather than disappearing.
      expect(find.bySemanticsLabel('Previous page'), findsOne);
      expect(find.bySemanticsLabel('Next page'), findsOne);
    });

    testWidgets('names both segments in full at every width', (tester) async {
      await _pump(tester, pageNumber: 4);

      expect(find.bySemanticsLabel('Previous page'), findsOne);
      expect(find.bySemanticsLabel('Next page'), findsOne);
      expect(find.bySemanticsLabel('Page 4'), findsOne);
    });

    testWidgets('loading: the pressed way works, the other way waits', (
      tester,
    ) async {
      var presses = 0;
      await _pump(
        tester,
        pageNumber: 4,
        next: () => presses++,
        loading: PaginationDirection.next,
        settle: false,
      );

      // The spinner sits where the chevron was, in the chevron's box, and the
      // word stays in the label colour: working is not disabled.
      expect(
        find.descendant(
          of: find.byKey(_next),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOne,
      );
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(
        tester.widget<Text>(find.text('Next')).style?.color,
        tokens.colors.action.secondary.label,
      );
      expect(find.bySemanticsLabel('Next page, working'), findsOne);
      // Neither segment answers while the page is read.
      expect(_surface(tester, _next).onPressed, isNull);
      expect(_surface(tester, _previous).onPressed, isNull);
      await tester.tap(find.byKey(_next), warnIfMissed: false);
      expect(presses, 0);
      expect(
        tester.widget<Text>(find.text('Previous')).style?.color,
        tokens.colors.action.disabledLabel,
      );
    });

    testWidgets('loading does not resize the segment it is in', (tester) async {
      _screen(tester, const Size(1440, 900));
      await _pump(tester, pageNumber: 4);
      final idle = tester.getSize(find.byKey(_next));

      await _pump(
        tester,
        pageNumber: 4,
        loading: PaginationDirection.next,
        settle: false,
      );
      expect(tester.getSize(find.byKey(_next)), idle);
    });

    testWidgets('the range says which records these are', (tester) async {
      await _pump(tester, pageNumber: 4, range: (first: 61, last: 80));

      expect(find.textContaining('Showing'), findsOne);
      expect(find.textContaining('61–80'), findsOne);
      expect(find.bySemanticsLabel('Showing 61 to 80'), findsOne);

      // A page of one record names it rather than spanning it to itself.
      await _pump(tester, pageNumber: 3, range: (first: 41, last: 41));
      expect(find.textContaining('41–41'), findsNothing);
      expect(find.bySemanticsLabel('Showing 41'), findsOne);
    });

    testWidgets('told the list ended, the last page says so in words', (
      tester,
    ) async {
      await _pump(tester, pageNumber: 9, next: null, endOfList: true);

      expect(find.text('· last'), findsOne);
      expect(find.bySemanticsLabel('Page 9, the last'), findsOne);
      expect(_surface(tester, _next).onPressed, isNull);
    });

    testWidgets('told the list ended, a single page draws no bar at all', (
      tester,
    ) async {
      await _pump(tester, pageNumber: 1, previous: null, endOfList: true);

      expect(find.byKey(_previous), findsNothing);
      expect(find.byKey(_next), findsNothing);
      expect(find.text('Page'), findsNothing);
      const single = Pagination(
        pageNumber: 1,
        onPrevious: null,
        onNext: null,
        endOfList: true,
      );
      expect(single.draws, isFalse);
      expect(single.withGapAbove(16), isEmpty);
      // Not told it ended, the same page draws, with its gap.
      const unknown = Pagination(pageNumber: 1, onPrevious: null, onNext: null);
      expect(unknown.draws, isTrue);
      expect(unknown.withGapAbove(16), hasLength(2));
      // A later last page draws too: it has a way back.
      const later = Pagination(
        pageNumber: 2,
        onPrevious: null,
        onNext: null,
        endOfList: true,
      );
      expect(later.draws, isTrue);
    });

    testWidgets('keys the figure, so a test reads the page it is on', (
      tester,
    ) async {
      await _pump(tester, pageNumber: 12);
      expect(tester.widget<Text>(find.byKey(_page)).data, '12');
    });

    testWidgets('reserves three digits, so page 100 does not move Previous', (
      tester,
    ) async {
      _screen(tester, const Size(1440, 900));
      await _pump(tester, pageNumber: 9);
      final nine = tester.getRect(find.byKey(_previous));
      await _pump(tester, pageNumber: 100);
      final hundred = tester.getRect(find.byKey(_previous));
      expect(hundred, nine);
    });

    testWidgets('focus reaches Previous, then Next, and draws a ring', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      await _pump(tester, pageNumber: 4);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_ringAround(tester, _previous), findsOne);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_ringAround(tester, _next), findsOne);
      expect(_ringAround(tester, _previous), findsNothing);
    });

    testWidgets('does not throw where the row is narrower than the screen '
        'says', (tester) async {
      // A pager in a dialog on a phone: the screen says 411, the box is far
      // less, and the words ellipsize rather than overflow.
      _screen(tester, const Size(411, 891));
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: Pagination(
                  pageNumber: 3,
                  onPrevious: _noop,
                  onNext: _noop,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  _pagedListTests();
}

void _pagedListTests() {
  group('PagedListView', () {
    Future<void> pumpList(
      WidgetTester tester, {
      required Pagination? pagination,
      int rows = 40,
      Widget? leading,
    }) async {
      tester.view.physicalSize = const Size(411, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Scaffold(
            body: PagedListView(
              listKey: const ValueKey('list'),
              padding: const EdgeInsets.all(16),
              pagination: pagination,
              children: <Widget>[
                if (leading != null) leading,
                for (var row = 0; row < rows; row++)
                  SizedBox(
                    key: ValueKey('row-$row'),
                    height: 64,
                    child: Text('Row $row'),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('holds the bar at the bottom of the screen from the first '
        'row', (tester) async {
      await pumpList(
        tester,
        pagination: const Pagination(
          pageNumber: 1,
          nextKey: _next,
          onPrevious: null,
          onNext: _noop,
        ),
      );

      // On screen before anything has been scrolled, at the foot of the view.
      final bar = tester.getRect(find.byKey(_next));
      expect(bar.bottom, lessThanOrEqualTo(700));
      expect(bar.bottom, greaterThan(700 - 80));
      expect(tester.getTopLeft(find.byKey(const ValueKey('row-0'))).dy, 16);

      // And it stays there while the rows scroll.
      await tester.drag(
        find.byKey(const ValueKey('list')),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_next)), bar);
      // Nothing scrolls beneath it: the list stops where the footer starts.
      expect(
        tester.getRect(find.byKey(const ValueKey('list'))).bottom,
        lessThanOrEqualTo(bar.top),
      );
    });

    testWidgets('a list that fits one page is a list and nothing else', (
      tester,
    ) async {
      await pumpList(
        tester,
        rows: 3,
        pagination: const Pagination(
          pageNumber: 1,
          nextKey: _next,
          onPrevious: null,
          onNext: null,
          endOfList: true,
        ),
      );

      expect(find.byKey(_next), findsNothing);
      expect(find.byType(Pagination), findsNothing);
      expect(tester.getSize(find.byKey(const ValueKey('list'))).height, 700);
    });

    testWidgets('no pager asked for, no footer drawn', (tester) async {
      await pumpList(tester, pagination: null);

      expect(find.byType(Pagination), findsNothing);
      expect(tester.getSize(find.byKey(const ValueKey('list'))).height, 700);
    });

    testWidgets('puts the bar away while the keyboard is open', (tester) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await pumpList(
        tester,
        pagination: const Pagination(
          pageNumber: 1,
          nextKey: _next,
          onPrevious: null,
          onNext: _noop,
        ),
      );

      expect(find.byKey(_next), findsNothing);
    });

    // Found in review on 2026-09-22, and the sheet's 2026-09-03 defect again:
    // this returned a bare list without a bar and a column with one, so every
    // crossing re-inflated the list and every field in it. The catalog and the
    // staff directory keep their search field in these rows - so on a list
    // longer than a page, the keyboard's arrival took the field it had come up
    // for, and with it the keyboard.
    //
    // Each of these holds the field's `State` and `FocusNode` across the change,
    // which a re-inflated field fails however much it looks like the old one.
    testWidgets('keeps the field a person is typing into while the keyboard '
        'opens', (tester) async {
      final search = TextEditingController();
      addTearDown(search.dispose);
      await pumpList(
        tester,
        leading: AppTextField(label: 'Search', controller: search),
        pagination: const Pagination(
          pageNumber: 1,
          nextKey: _next,
          onPrevious: null,
          onNext: _noop,
        ),
      );
      await tester.tap(find.byType(EditableText));
      await tester.pumpAndSettle();
      final field = tester.state(find.byType(EditableText));
      final focus = tester
          .widget<EditableText>(find.byType(EditableText))
          .focusNode;
      expect(focus.hasFocus, isTrue);
      expect(find.byKey(_next), findsOne);

      // Nothing else is rebuilt: the keyboard arriving has to be enough.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(find.byKey(_next), findsNothing);
      expect(
        tester.state(find.byType(EditableText)),
        same(field),
        reason: 'the list was re-inflated, taking the field with it',
      );
      expect(focus.hasFocus, isTrue);

      await tester.enterText(find.byType(EditableText), 'bread');
      await tester.pump();
      expect(search.text, 'bread');
    });

    testWidgets('puts the bar back when the keyboard closes', (tester) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await pumpList(
        tester,
        pagination: const Pagination(
          pageNumber: 1,
          nextKey: _next,
          onPrevious: null,
          onNext: _noop,
        ),
      );
      expect(find.byKey(_next), findsNothing);

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();

      expect(find.byKey(_next), findsOne);
    });

    testWidgets('keeps the field when the bar comes and goes with the '
        'results', (tester) async {
      // A search that narrows to one page stops the bar drawing, and a re-read
      // passes no bar at all while it runs. Neither may cost the field.
      final search = TextEditingController();
      addTearDown(search.dispose);
      final field = AppTextField(label: 'Search', controller: search);
      await pumpList(tester, leading: field, pagination: null);
      await tester.tap(find.byType(EditableText));
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(EditableText));
      final focus = tester
          .widget<EditableText>(find.byType(EditableText))
          .focusNode;

      await pumpList(
        tester,
        leading: field,
        pagination: const Pagination(
          pageNumber: 1,
          nextKey: _next,
          onPrevious: null,
          onNext: _noop,
        ),
      );
      expect(find.byKey(_next), findsOne);
      expect(tester.state(find.byType(EditableText)), same(state));
      expect(focus.hasFocus, isTrue);

      await pumpList(
        tester,
        leading: field,
        rows: 3,
        pagination: const Pagination(
          pageNumber: 1,
          nextKey: _next,
          onPrevious: null,
          onNext: null,
          endOfList: true,
        ),
      );
      expect(find.byKey(_next), findsNothing);
      expect(tester.state(find.byType(EditableText)), same(state));
      expect(focus.hasFocus, isTrue);
    });
  });
}

/// A focus ring in `action.focusRing` drawn round the segment with [key].
Finder _ringAround(WidgetTester tester, Key key) {
  final tokens = spiritTheme.extension<AppTokens>()!;
  final ring = tokens.colors.action.focusRing;
  return find.descendant(
    of: find.byKey(key),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          switch ((widget.decoration as BoxDecoration).border) {
            final Border border => border.top.color == ring.color,
            _ => false,
          },
    ),
  );
}

PressSurface _surface(WidgetTester tester, Key key) =>
    tester.widget<PressSurface>(find.byKey(key));

String _figure(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_page)).data!;

void _screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pump(
  WidgetTester tester, {
  required int pageNumber,
  VoidCallback? previous = _noop,
  VoidCallback? next = _noop,
  PaginationDirection? loading,
  PaginationRange? range,
  bool endOfList = false,
  double textScale = 1,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Pagination(
                pageNumber: pageNumber,
                previousKey: _previous,
                nextKey: _next,
                pageKey: _page,
                onPrevious: previous,
                onNext: next,
                loading: loading,
                range: range,
                endOfList: endOfList,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void _noop() {}
