/// The on-screen keypad beside the sign-in form. `design.md` §11 step 9.
///
/// **A key is a control and it is not an `AppButton`, and the reason is §5.2's
/// own arithmetic rather than taste.** §5.2 gives `AppButton` a minimum
/// horizontal padding of `space.20` — 40 logical pixels before a glyph is
/// drawn — and §9 makes a key 48 wide at the narrowest. A one-character key at
/// 48 has 8 pixels left for the character after the padding, and none at all
/// after `PressSurface`'s reserved focus-ring gutter. A component cannot be used
/// at a size its own specification forbids, so the key draws itself out of the
/// same §2 rows `AppButton` reads: [AppActionRoles.secondary] for the container,
/// label and border, `radius.pill` for the shape because §2.3 restricts the pill
/// to buttons and a key is one, `label.lg` for the character, and [PressSurface]
/// for the press, the hover, the focus ring and the tap target. Nothing here
/// invents a token.
///
/// **The pane's width is a measurement this component takes, not a breakpoint
/// anyone declared.** [minimumWidth] is the widest row's key count at §9's tap
/// target, plus §9's own "≥ 8dp apart", plus the card's inset and the pane's
/// margin — and sign-in asks it whether there is room rather than asking §4.1.
/// That is the same move
/// `AppButton.measureWidth` and `StatusBadge.measureWidth` make: the thing that
/// knows how wide it needs to be is the thing that draws it.
///
/// **What it replaced, and why none of it survived.** The keypad was 56-high
/// keys at radius 28 in `mutedGreen` with white labels, inside a `GlassCard` —
/// a radius-32 gradient with a 30-blur black `BoxShadow` and a `BackdropFilter`.
/// §2.1 says depth is a surface step and never a drop shadow, §2.3 has no
/// radius 28 or 32, and the blur was rastering the scaffold behind it to no
/// visible end. The card is `surface.raised` at `radius.md` with a
/// `border.subtle` edge, which is §2.1's own way of saying "a distinct surface".
///
/// **`Enter` is drawn disabled because it does nothing**, and that is the honest
/// rendering rather than a new defect: its handler has been an empty branch
/// since the file was written. `AppButton`'s own note applies — a disabled
/// rendering is what "no callback" looks like, and there is no way to have a
/// working control that looks disabled or a dead one that looks alive. Wiring it
/// to submit is a behaviour change and `claude.md` hard rule 1 keeps that out of
/// a visual step; dropping the key is a product decision. Both are recorded in
/// `PLAN.md`.
library;

import 'package:flutter/material.dart';

import '../keyboard_controller.dart';
import '../keyboard_scope.dart';
import '../ui/buttons.dart';
import '../ui/press.dart';
import '../ui/tokens.dart';

/// A QWERTY keypad that types into whichever field the [KeyboardScope]'s
/// controller is attached to.
final class PosKeyboard extends StatelessWidget {
  const PosKeyboard({super.key});

  /// The keys, in the order they are drawn.
  ///
  /// Unchanged from the widget this replaces: the layout is what a person
  /// already using this till knows, and rearranging it inside a restyling step
  /// would be a change nobody asked for.
  static const List<List<String>> rows = <List<String>>[
    <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    <String>['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
    <String>['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
    <String>['Z', 'X', 'C', 'V', 'B', 'N', 'M', backspace],
    <String>['@', '.com', space, enter],
  ];

  /// The key that removes a character.
  ///
  /// **The label is the identifier and the face is an icon**, because the
  /// character this key used to wear — `⌫`, U+232B ERASE TO THE LEFT — is not in
  /// Roboto, and the first rendering of this keypad showed it as a tofu box.
  /// That is the same defect `PLAN.md` records against the bulk report's
  /// before/after arrow, one step worse: an arrow inside a sentence is a missing
  /// mark, and a key whose entire face is a box is a control nobody can name.
  /// [_faceOf] gives it `Icons.backspace_outlined` and [_announcement] gives a
  /// screen reader the word, which is §9's icon-only row.
  static const String backspace = 'Backspace';

  static const String space = 'Space';

  static const String enter = 'Enter';

  /// The widest row's key count, which is what a pane has to fit.
  ///
  /// The other rows carry fewer keys and therefore wider ones, because each row
  /// divides the width it is given by its own flex total. This row is the one
  /// that decides whether the keypad fits at all.
  static const int columns = 10;

  /// The keypad's own inset inside its card, and the gap between keys.
  ///
  /// The inset is `AppScaffold.horizontalInset`'s figure, read off §2.3's scale
  /// rather than imported, so this widget does not depend on the page frame it
  /// happens to sit beside. The gap is §9's "≥ 8dp apart".
  static double _inset(AppTokens tokens) => tokens.spacing.s20;

  /// The space between the card and the edge of the pane it is given.
  ///
  /// **Drawn here rather than by the caller**, which is unusual and deliberate:
  /// it is in [minimumWidth]'s sum, and a margin the caller added would be a
  /// term this component's own answer did not know about. That is not
  /// hypothetical — the first draft of §11 step 9 padded the pane *and* the
  /// card, and every key came out 44 wide against a component that had promised
  /// 48.
  static double _margin(AppTokens tokens) => tokens.spacing.s20;

  static double _gap(AppTokens tokens) => tokens.spacing.s8;

  /// The narrowest pane this keypad can be drawn in at §9's tap target.
  ///
  /// **The component answers for its own geometry**, for the reason
  /// `StatusBadge.measureWidth` gives: the alternative is the screen
  /// reassembling `10 × 48 + 9 × 8 + 20 × 4` out of numbers it read here, which
  /// is a second copy of this arithmetic that goes stale the first time this one
  /// changes.
  ///
  /// It is 632 at the comfortable density §3 gives sign-in by name. It is not
  /// measured against the glyphs, and does not need to be: every key is at least
  /// as wide as §9's target, and one character at `label.lg` is far narrower
  /// than 48.
  static double minimumWidth(AppTokens tokens) =>
      columns * tokens.density.minimumTapTarget.width +
      (columns - 1) * _gap(tokens) +
      _inset(tokens) * 2 +
      _margin(tokens) * 2;

  /// How many columns a key claims. Everything is one but the two words.
  static int _flexOf(String key) => switch (key) {
    space => 4,
    enter => 2,
    backspace => 2,
    _ => 1,
  };

  /// The icon a key wears instead of its label, where it has one.
  ///
  /// **At `AppButton.iconSize`**, which is 18 and is one of the two icon sizes
  /// §5.2 names. A key has no §5.2 row of its own, so a size is borrowed from a
  /// named one rather than invented — the same move `Callout.glyphSize` and
  /// `Disclosure.glyphSize` make, and the same gap in §5.2 they record.
  static IconData? _faceOf(String key) =>
      key == backspace ? Icons.backspace_outlined : null;

  /// What a screen reader says. §9's icon-only row, for the one key whose face
  /// is not its own name.
  static String? _announcement(String key) => key == backspace ? key : null;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final keyboard = KeyboardScope.of(context);
    final gap = _gap(tokens);

    return Padding(
      padding: EdgeInsets.all(_margin(tokens)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface.raised,
          borderRadius: BorderRadius.circular(tokens.radius.md),
          border: Border.all(color: colors.surface.borderSubtle),
        ),
        child: Padding(
          padding: EdgeInsets.all(_inset(tokens)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final (index, row) in rows.indexed) ...<Widget>[
                if (index > 0) SizedBox(height: gap),
                Row(
                  children: <Widget>[
                    for (final (position, key) in row.indexed) ...<Widget>[
                      if (position > 0) SizedBox(width: gap),
                      Expanded(
                        flex: _flexOf(key),
                        child: _Key(
                          label: key,
                          face: _faceOf(key),
                          announcement: _announcement(key),
                          // `Enter` submits nothing, so it offers nothing.
                          onPressed: key == enter
                              ? null
                              : () => _press(keyboard, key),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static void _press(KeyboardController keyboard, String key) {
    if (key == backspace) {
      keyboard.backspace();
      return;
    }
    keyboard.insert(key == space ? ' ' : key);
  }
}

/// One key.
///
/// Drawn as §2.1's `secondary` action tier — transparent container, sage label,
/// `border.strong` edge — which is the tier §2.1 calls "the ordinary case", and
/// a key is as ordinary as a control gets. Its disabled rendering is §2.1's own
/// row for an overlay tier: the container stays transparent and the label and
/// border go to the disabled pair.
final class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.onPressed,
    this.face,
    this.announcement,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Drawn instead of [label]. See [PosKeyboard._faceOf].
  final IconData? face;

  /// See [PosKeyboard._announcement].
  final String? announcement;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final actions = tokens.colors.action;
    final role = actions.secondary;
    final disabled = onPressed == null;
    final labelColor = disabled ? actions.disabledLabel : role.label;
    final borderColor = disabled ? actions.disabledBorder : role.border!;
    final radius = BorderRadius.circular(tokens.radius.pill);

    return PressSurface(
      borderRadius: radius,
      onPressed: onPressed,
      hoverOverlay: role.hoverFill(),
      pressedOverlay: role.pressedFill(),
      semanticLabel: announcement ?? label,
      // A key fills the column it was given; without this the tap-target box
      // shrink-wraps and ten keys sit in a huddle on the left of the row.
      fillWidth: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: role.container,
          borderRadius: radius,
          border: Border.all(color: borderColor),
        ),
        child: ConstrainedBox(
          // §9's target is the height as well as the width, and a key has no
          // §5.2 size row to read one from.
          constraints: BoxConstraints(
            minHeight: tokens.density.minimumTapTarget.height,
          ),
          child: Center(
            heightFactor: 1,
            child: face == null
                ? Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.labelLarge.copyWith(
                      color: labelColor,
                    ),
                  )
                : Icon(face, size: AppButton.iconSize, color: labelColor),
          ),
        ),
      ),
    );
  }
}
