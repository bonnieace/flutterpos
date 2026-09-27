/// `Pagination`'s state matrix, per `claude.md` hard rule 5 and §10.
///
/// **Drawn from `docs/design/pagination/`**: the joined pager, every state it
/// can be in, at the two widths it spends its life at. The phone is the one
/// that matters - there the group takes the row and each nav segment is a wide
/// target under a thumb; on a monitor it sits at its own width at the end of
/// the row.
///
/// `95-pagination-states` is the whole matrix on one board: where the list is
/// (first, middle, last, paused, the only page), the three inputs a call site
/// may add (loading, the range, the end of the list), and 200% text, where the
/// words give way to glyphs. The segment's own interaction states - hover,
/// pressed, focus-visible - are one capture each, because each needs a pointer
/// or a keyboard the others would disturb.
///
/// **The figure's roll is not here and cannot be.** §10: the harness
/// rasterises a frame, and a spring has no frame that stands for it.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uzapay_pos/ui/pagination.dart';
import 'package:uzapay_pos/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const ValueKey<String> _next = ValueKey<String>('pagination-next');

void main() {
  screenshotCase(
    '95-pagination-first-page',
    build: () => const _Host(pageNumber: 1, hasPrevious: false),
    fullPage: false,
  );

  screenshotCase(
    '95-pagination-middle',
    build: () => const _Host(pageNumber: 4),
    fullPage: false,
  );

  screenshotCase(
    '95-pagination-last-page',
    build: () => const _Host(pageNumber: 9, hasNext: false),
    fullPage: false,
  );

  screenshotCase(
    '95-pagination-states',
    build: () => const _StateBoard(),
    fullPage: false,
    // The loading row's spinner never settles, which is the point of it. A
    // few hundred milliseconds in, it has an arc to photograph rather than
    // the dot it starts from.
    settle: false,
    afterPump: (tester) => tester.pump(const Duration(milliseconds: 400)),
  );

  screenshotCase(
    '95-pagination-hover',
    build: () => const _Host(pageNumber: 4),
    fullPage: false,
    afterPump: (tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(_next)));
      await tester.pumpAndSettle();
    },
  );

  screenshotCase(
    '95-pagination-pressed',
    build: () => const _Host(pageNumber: 4),
    fullPage: false,
    afterPump: (tester) async {
      final press = await tester.startGesture(
        tester.getCenter(find.byKey(_next)),
      );
      // The settled press, not a spring mid-flight - see `90-appbutton-*`.
      await tester.pump(const Duration(milliseconds: 400));
      addTearDown(press.up);
    },
  );

  screenshotCase(
    '95-pagination-focus',
    build: () => const _Host(pageNumber: 4),
    fullPage: false,
    afterPump: (tester) async {
      // A test binding reports a touch platform, where the ring is correctly
      // suppressed; the keyboard is what this capture is of.
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      // Tab reaches Previous, then Next. The position is not a stop.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    },
  );
}

/// One bar, on the page, where the list above it would end.
final class _Host extends StatelessWidget {
  const _Host({
    required this.pageNumber,
    this.hasPrevious = true,
    this.hasNext = true,
  });

  final int pageNumber;
  final bool hasPrevious;
  final bool hasNext;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Scaffold(
      backgroundColor: tokens.colors.surface.base,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s16),
          child: Pagination(
            pageNumber: pageNumber,
            nextKey: _next,
            onPrevious: hasPrevious ? () {} : null,
            onNext: hasNext ? () {} : null,
          ),
        ),
      ),
    );
  }
}

/// Every state, one labelled row each.
final class _StateBoard extends StatelessWidget {
  const _StateBoard();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    void noop() {}
    final rows = <(String, Widget)>[
      ('First page', Pagination(pageNumber: 1, onPrevious: null, onNext: noop)),
      (
        'A middle page',
        Pagination(pageNumber: 4, onPrevious: noop, onNext: noop),
      ),
      (
        'The last page',
        Pagination(pageNumber: 9, onPrevious: noop, onNext: null),
      ),
      (
        'Paused while a write is in flight',
        const Pagination(pageNumber: 2, onPrevious: null, onNext: null),
      ),
      (
        'The only page, not told it is the end',
        const Pagination(pageNumber: 1, onPrevious: null, onNext: null),
      ),
      (
        'Loading the next page',
        const Pagination(
          pageNumber: 4,
          onPrevious: null,
          onNext: null,
          loading: PaginationDirection.next,
        ),
      ),
      (
        'With the range',
        Pagination(
          pageNumber: 4,
          onPrevious: noop,
          onNext: noop,
          range: (first: 61, last: 80),
        ),
      ),
      (
        'The last page, told it is the end',
        Pagination(
          pageNumber: 9,
          onPrevious: noop,
          onNext: null,
          endOfList: true,
        ),
      ),
      (
        '200% text',
        MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: Pagination(pageNumber: 4, onPrevious: noop, onNext: noop),
        ),
      ),
    ];
    return Scaffold(
      backgroundColor: tokens.colors.surface.base,
      body: ListView(
        padding: EdgeInsets.all(tokens.spacing.s16),
        children: <Widget>[
          for (final (label, bar) in rows) ...<Widget>[
            Text(
              label,
              style: tokens.typography.caption.copyWith(
                color: tokens.colors.text.tertiary,
              ),
            ),
            SizedBox(height: tokens.spacing.s4),
            bar,
            SizedBox(height: tokens.spacing.s16),
          ],
        ],
      ),
    );
  }
}
