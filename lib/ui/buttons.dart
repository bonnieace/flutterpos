/// `AppButton`: `design.md` §5.1's first component and §5.2's first
/// specification, built on [PressSurface].
///
/// **Four tiers, and one of them has never existed in this app.** §2.1 calls the
/// action roles "the single biggest change in this document": exactly one
/// `primary` per screen region, `secondary` for the ordinary case, `tertiary`
/// inline, and `destructive` for anything that removes or reverses. There is no
/// Material button theme a destructive tier could have attached to, which is why
/// step 2 could paint the other three at the theme and had to leave this one
/// until a component existed to carry it.
///
/// **Three sizes, and the tap target is not one of them.** §5.2 gives `sm` 32h,
/// `md` 40h and `lg` 48h; §9 makes 48 x 48 pass/fail on a touch device and
/// `claude.md` hard rule 6 makes §9 pass/fail full stop. Both hold at once
/// because the painted height and the hit area are different things: this widget
/// paints §5.2's height and [PressSurface] expands the area that answers a tap
/// to the density's own minimum. A `sm` button is 32 high and still 48 to a
/// thumb.
///
/// **The state matrix is six rows, not §5's nine, and the missing three are
/// missing on purpose.** `enabled`, `hover`, `focus-visible`, `pressed`,
/// `disabled` and `loading` all apply. `error`, `read-only` and `empty` do not:
/// §5.2 gives `error` to `AppTextField`, where it replaces helper text; a button
/// that may not be used is `disabled` rather than read-only, and there is no
/// such thing as an empty button. All six appear in the screenshot harness, per
/// §10 and `claude.md` hard rule 5.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'measure.dart';
import 'press.dart';
import 'tokens.dart';

/// One of `design.md` §2.1's four action tiers.
enum AppButtonTier {
  /// `#45F28D` container, `#0A0F0C` label, no border. **Exactly one per screen
  /// region** - a screen with three primary buttons has no primary button.
  primary,

  /// Transparent container, `#B8D6C5` label, `#2C5340` border. The ordinary
  /// case, and the tier §2.1 is most insistent about: a secondary action is
  /// **not** mint.
  secondary,

  /// Transparent, mint label, no border. Inline and low-commitment.
  tertiary,

  /// Transparent, `#FF5C6C` label and border. Removes or reverses.
  destructive;

  /// This tier's colours.
  AppActionRole of(AppActionRoles roles) => switch (this) {
    AppButtonTier.primary => roles.primary,
    AppButtonTier.secondary => roles.secondary,
    AppButtonTier.tertiary => roles.tertiary,
    AppButtonTier.destructive => roles.destructive,
  };
}

/// One of `design.md` §5.2's three button sizes.
///
/// **Touch surfaces use [lg] only**, which §5.2 says in as many words. [sm] and
/// [md] are for a pointer at compact density; they keep a 48dp *hit* area
/// regardless, because §9 does not have an exception for a small button.
enum AppButtonSize {
  /// 32 high.
  sm(height: 32),

  /// 40 high.
  md(height: 40),

  /// 48 high. The only size a touch surface uses.
  lg(height: 48);

  const AppButtonSize({required this.height});

  /// The painted height. Not the tap target - see [AppButton].
  final double height;

  /// §5.2: "Minimum horizontal padding `space.20`, `space.16` when an icon is
  /// present."
  double horizontalPadding(AppSpacing spacing, {required bool hasIcon}) =>
      hasIcon ? spacing.s16 : spacing.s20;
}

/// A button, in one of four tiers and three sizes.
///
/// The label is `label.lg` in every size (§5.2 names one role, not three) and
/// should be sentence case and a verb phrase naming the effect - §8's copy
/// rules, which this widget cannot enforce and its callers must.
final class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tier = AppButtonTier.secondary,
    this.size = AppButtonSize.lg,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.focusNode,
    this.autofocus = false,
  });

  /// The text on the button.
  final String label;

  /// Null disables it. §2.1's disabled row is a *rendering*, not a separate
  /// flag: there is no way to have a disabled-looking button that still works,
  /// or a working button that looks disabled.
  final VoidCallback? onPressed;

  final AppButtonTier tier;

  final AppButtonSize size;

  /// §5.2: leading icon, 18px, optional. A trailing icon is reserved for
  /// disclosure and is not offered here.
  final IconData? icon;

  /// §2.1's loading row: the container is held, the label is replaced by a
  /// 16px spinner in the label colour, **and the width is frozen** so a button
  /// does not resize mid-press.
  ///
  /// The width is frozen by leaving the label in the layout and not painting
  /// it, rather than by measuring it and pinning a number. A measured width is
  /// a second source of truth that goes stale when the text scale changes.
  final bool loading;

  /// Fills the width it is given, for a button that is the only thing on its
  /// row. Off by default: a button that is as wide as its label is what §5.2's
  /// padding figures describe.
  final bool expand;

  final FocusNode? focusNode;

  final bool autofocus;

  /// §5.2's leading icon size. One figure, read by the widget that paints it
  /// and by [measureWidth], so a button cannot be measured at a size it is not
  /// drawn at.
  static const double iconSize = 18;

  /// How wide this button wants to be, with its label on one line.
  ///
  /// **The component answers for its own geometry**, for the reason
  /// `StatusBadge.measureWidth` gives: `RecordList`'s table sizes its action
  /// column to the widest set of buttons in the list, and a call site that
  /// reassembled §5.2's padding rule itself would be a second copy of it.
  ///
  /// **Two things that are not §5.2's and are in the sum anyway**, both of them
  /// [PressSurface]'s and both found by a set of four that wrapped after being
  /// given exactly the width its labels needed. The focus ring is drawn in a
  /// gutter reserved whether it is visible or not, so it costs every button
  /// `width + offset` on each side; and §9's tap target is a minimum width as
  /// well as a minimum height, so a two-letter button is 48 wide however short
  /// its label is. The label is `label.lg` in every size - §5.2 names one role,
  /// not three - and the border is painted rather than laid out, so that one
  /// costs nothing.
  static double measureWidth(
    AppTokens tokens,
    String label, {
    AppButtonSize size = AppButtonSize.lg,
    bool hasIcon = false,
    TextScaler textScaler = TextScaler.noScaling,
    TextStyle? ambient,
  }) {
    final ring = tokens.colors.action.focusRing;
    final painted =
        size.horizontalPadding(tokens.spacing, hasIcon: hasIcon) * 2 +
        (hasIcon ? iconSize + tokens.spacing.s8 : 0) +
        measureTextWidth(
          label,
          tokens.typography.labelLarge,
          textScaler: textScaler,
          ambient: ambient,
        );
    return math.max(
      painted + (ring.width + ring.offset) * 2,
      tokens.density.minimumTapTarget.width,
    );
  }

  /// Whether this button can be pressed. Loading is not disabled - it is a
  /// press that has already been accepted - but it must not be pressed twice.
  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    // `componentOf`, not `of`: a button is reached from trees that are not this
    // app's `MaterialApp` - widget tests with their own `ThemeData`, dialogs
    // given a fresh theme, previews - and crashing in all of them buys nothing.
    // See the accessor's own note for why the fallback cannot shrink a tap
    // target.
    final tokens = AppTokens.componentOf(context);
    final actions = tokens.colors.action;
    final role = tier.of(actions);
    final disabled = onPressed == null;

    // §2.1's disabled row states two different things for two kinds of tier:
    // the primary tier takes a container, and the three overlay tiers keep a
    // transparent one and change only their label and border. `container` is
    // already transparent on those three, so reading the tier's own container
    // is what keeps the rule in one place.
    final container = disabled
        ? (tier == AppButtonTier.primary
              ? actions.disabledContainer
              : role.container)
        : role.container;
    final labelColor = disabled ? actions.disabledLabel : role.label;
    final borderColor = role.border == null
        ? null
        : (disabled ? actions.disabledBorder : role.border);

    final hasIcon = icon != null;
    final padding = size.horizontalPadding(tokens.spacing, hasIcon: hasIcon);
    // **`radius.md`, not `radius.pill`, since 2026-08-22.** Profound Verdant's
    // own CSS gives `.btn-primary` `border-radius: theme('borderRadius.xl')`,
    // and its rendered buttons are square-cornered. Its prose calls one
    // element pill-shaped and its render disagrees; the render wins.
    final radius = BorderRadius.circular(tokens.radius.md);

    final labelStyle = tokens.typography.labelLarge.copyWith(color: labelColor);

    final text = Text(
      label,
      style: labelStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );

    // **The label flexes, so a narrow slot ellipsizes it rather than
    // overflowing the button.** This is what Material's own
    // `ButtonStyleButton.icon` does, and matching it is not imitation - it is
    // the only arrangement that survives all three places a button is put.
    //
    // A `Row` hands a *non-flexible* child an **unbounded** main axis, so a
    // button in an `AppBar`'s actions is offered infinite width. `RenderFlex`
    // permits flex under unbounded constraints when `mainAxisSize` is `min`
    // and rejects it only when `max` - and `max` here means [expand], where
    // the width is bounded by construction because the button is filling a
    // slot that has one.
    Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (hasIcon) ...<Widget>[
          Icon(icon, size: iconSize, color: labelColor),
          SizedBox(width: tokens.spacing.s8),
        ],
        Flexible(child: text),
      ],
    );

    if (loading) {
      content = Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // Laid out, measured, and not painted. This is the frozen width.
          Opacity(opacity: 0, child: content),
          SizedBox(
            width: actions.loadingIndicatorSize,
            height: actions.loadingIndicatorSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              // §2.1: "a 16px spinner in label colour". Not the accent - a
              // spinner on a destructive button is red, or the button changes
              // tier while it is working.
              valueColor: AlwaysStoppedAnimation<Color>(labelColor),
            ),
          ),
        ],
      );
    }

    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: container,
        borderRadius: radius,
        border: borderColor == null
            ? null
            : Border.all(color: borderColor, width: 1),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: size.height),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: Center(
            widthFactor: expand ? null : 1,
            heightFactor: 1,
            child: content,
          ),
        ),
      ),
    );

    return Semantics(
      container: true,
      button: true,
      enabled: _enabled,
      // A person using a screen reader is told the button is busy rather than
      // left to wonder why it stopped answering.
      label: loading ? '$label, working' : label,
      onTap: _enabled ? onPressed : null,
      // One node, not two. Without this the gesture detector inside
      // `PressSurface` contributes a second tappable node underneath this one
      // and the button is announced twice.
      excludeSemantics: true,
      child: PressSurface(
        borderRadius: radius,
        onPressed: _enabled ? onPressed : null,
        hoverOverlay: role.hoverFill(),
        pressedOverlay: role.pressedFill(),
        focusNode: focusNode,
        autofocus: autofocus,
        excludeSemantics: true,
        fillWidth: expand,
        child: surface,
      ),
    );
  }
}
