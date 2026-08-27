/// `Pagination`: `design.md` §5.1's priority-3 row for "low-contrast Previous /
/// Page N / Next", and the one §5.1 component with a §9 finding attached to it
/// by name.
///
/// **§9's "known current failures" list says `Previous` / `Next` pagination**,
/// and by the time this was built the *target* half of that was already fixed —
/// step 3 made every one of the twenty-six controls an `AppButton`, which is 48
/// high. What was left is the part a component fixes and a sweep does not:
/// **thirteen screens, two different shapes, two different tiers and two
/// different label sets**, each of which had made the same four decisions
/// separately.
///
/// **The bar always draws both controls, and that is the one behavioural-looking
/// decision here that is not one.** Eleven of the thirteen *hid* `Previous`
/// on the first page and `Next` on the last, so the bar moved under a person's
/// thumb as they paged - the control they were about to press slid sideways
/// when the other one vanished. §5's state matrix has a `disabled` row for
/// exactly this. The callbacks are untouched; a disabled control does what an
/// absent one did, which is nothing.
///
/// **`secondary`, and the tree had already decided.** `stock_adjustment_panel`
/// records the reasoning in its own comment - *"§2.1 permits exactly one primary
/// per screen region and on this route that is `Adjust stock`; 'Next page'
/// competing with it for the eye is the tier system not being applied rather
/// than a taste call. The same repoint is made on every paginated feed"* - and
/// eleven of the thirteen already drew it. The catalog and the bulk route drew
/// `tertiary` and move to match.
///
/// **The page statement is in §5.1's own row.** That row is "Previous / **Page
/// N** / Next", so a bar with only two buttons was never the component this
/// document describes; eleven of the thirteen never told a person which page
/// they were on at all.
///
/// **⚠ The two labels are noun phrases and §5.2 asks for verb phrases** -
/// *"label is `label.lg`, sentence case, always a verb phrase naming the
/// effect"*. `Previous page` and `Next page` name the destination rather than
/// the effect. This component keeps them, because the alternative is copy
/// invented here rather than decided by the product owner, and it is recorded
/// in `PLAN.md` as an open decision rather than fixed quietly.
library;

import 'package:flutter/widgets.dart';

import 'buttons.dart';
import 'measure.dart';
import 'tokens.dart';

/// The bar that moves a record list between pages.
final class Pagination extends StatelessWidget {
  const Pagination({
    super.key,
    required this.pageNumber,
    required this.onPrevious,
    required this.onNext,
    this.previousKey,
    this.nextKey,
    this.pageKey,
  });

  /// Which page is shown, counting from **1**.
  ///
  /// Every call site holds a zero-based `pageIndex`; the `+ 1` is the caller's,
  /// because this component states what a person reads and does not know that
  /// there is an index underneath it.
  final int pageNumber;

  /// Null when there is no previous page — which draws the control disabled
  /// rather than removing it. See the library note.
  final VoidCallback? onPrevious;

  /// Null when the read reported no more records, or while a write is in
  /// flight and paging would discard it.
  final VoidCallback? onNext;

  /// Keys on the three parts, for the call sites whose tests already address
  /// them. Same reasoning as `ConfirmDialog`'s: a key is the call site's
  /// identity rather than the component's, and renaming thirteen screens' keys
  /// to centralise them is churn in the suite for no assertion gained.
  final Key? previousKey;
  final Key? nextKey;
  final Key? pageKey;

  /// The labels at their full length, and the short forms a narrow bar takes.
  ///
  /// **Two words become one, and the page statement never shortens**: which
  /// page a person is on is the thing §5.1 put in the middle of this row, and
  /// dropping it to fit two buttons would be fitting the row by removing what
  /// it is for.
  static const String _previousLong = 'Previous page';
  static const String _nextLong = 'Next page';
  static const String _previousShort = 'Previous';
  static const String _nextShort = 'Next';

  /// Whether [width] can hold the long labels, the page statement and the gaps
  /// between them on one line.
  ///
  /// **Measured rather than looked up in §4.1's bands**, which is the move
  /// `PosKeyboard.minimumWidth` makes and for the same reason: how much room
  /// two buttons and a sentence need is arithmetic this component can do,
  /// where a breakpoint is a guess about a page. Exposed so a test can ask the
  /// question the widget asks instead of asserting a pixel width.
  static bool fitsOneRow(
    double width,
    AppTokens tokens, {
    int pageNumber = 1,
    TextScaler textScaler = TextScaler.noScaling,
  }) => width >= _rowWidth(tokens, pageNumber, textScaler, long: true);

  static double _rowWidth(
    AppTokens tokens,
    int pageNumber,
    TextScaler textScaler, {
    required bool long,
  }) =>
      AppButton.measureWidth(
        tokens,
        long ? _previousLong : _previousShort,
        textScaler: textScaler,
      ) +
      AppButton.measureWidth(
        tokens,
        long ? _nextLong : _nextShort,
        textScaler: textScaler,
      ) +
      measureTextWidth(
        'Page $pageNumber',
        tokens.typography.labelMedium,
        textScaler: textScaler,
      ) +
      tokens.spacing.s12 * 2;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    // **The screen's width, not the bar's own constraint.** A `LayoutBuilder`
    // would measure the box this bar was actually given, which is the better
    // question - and it cannot be asked here: `AlertDialog` sizes its content
    // by intrinsic height, `LayoutBuilder` refuses to answer an intrinsic
    // query, and every paginated list inside a dialog threw
    // *"LayoutBuilder does not support returning intrinsic dimensions"*. The
    // category dialogs are three of them.
    final width = MediaQuery.sizeOf(context).width;
    final long = fitsOneRow(
      width,
      tokens,
      pageNumber: pageNumber,
      textScaler: textScaler,
    );
    // The controls always remain on one row. Each button owns one flexible side
    // of the bar, so its existing ellipsis is the final narrow-width fallback
    // instead of moving either action below the page number.
    return Row(
      children: <Widget>[
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
              key: previousKey,
              label: long ? _previousLong : _previousShort,
              onPressed: onPrevious,
            ),
          ),
        ),
        SizedBox(width: tokens.spacing.s12),
        Text(
          'Page $pageNumber',
          key: pageKey,
          // `label.md` at `text.secondary`, which is §9's 4.5:1 row rather
          // than the `caption` this would otherwise reach for - that role is
          // named in §9's own failure list at 3.4:1.
          style: tokens.typography.labelMedium.copyWith(
            color: tokens.colors.text.secondary,
          ),
        ),
        SizedBox(width: tokens.spacing.s12),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton(
              key: nextKey,
              label: long ? _nextLong : _nextShort,
              onPressed: onNext,
            ),
          ),
        ),
      ],
    );
  }
}
