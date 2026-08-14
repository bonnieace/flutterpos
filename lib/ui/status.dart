/// `StatusBadge`, `Callout` and `Disclosure`: `design.md` §11 step 4.
///
/// **The one green doing seven jobs is what this file is for.** §1 is blunt
/// about it and §2.1 gives the answer: five statuses, each with exactly one
/// meaning, each rendered as a **container plus an icon plus a word** and never
/// as a colour. Roughly one man in twelve cannot separate this red from this
/// green, and this app is about money.
///
/// **Only one of the three is specified in §5.2.** [Disclosure] has a
/// paragraph of its own - collapsed line, leading glyph, chevron, expanded
/// explanation - and [StatusBadge] has a one-line row. [Callout] has neither:
/// §5.1 gives it a row saying it replaces "permanent notice paragraphs" and
/// nothing else. So it is drawn the way `AppSelect` was in step 3, out of §2
/// rows that already exist, and every value it uses is named in the doc comment
/// on the class rather than chosen here and left unexplained. Nothing in this
/// file invents a token.
///
/// **The glyphs are this file's, and that is stated rather than smuggled.**
/// §5.2 requires an icon on a status - "it is what makes the status legible
/// without colour" - and names no glyph for any of the five. The alternative to
/// a default per status is every call site choosing, which is how one green
/// came to mean seven things in the first place. [AppStatus.defaultIcon] is
/// therefore a component decision, overridable per call site, and it is not a
/// token: it is not a colour, a size, a radius, a spacing, a duration or a
/// spring.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'press.dart';
import 'spring.dart';
import 'tokens.dart';

/// One of `design.md` §2.1's five statuses.
///
/// **Each has exactly one meaning**, and the meanings are the document's own
/// words rather than a paraphrase, because the whole failure this replaces is a
/// colour that came to mean whatever the screen using it needed.
enum AppStatus {
  /// Reconciled, confirmed, in stock.
  ok,

  /// Unreconciled, pending, awaiting.
  attention,

  /// Difference found, unreadable, out of stock.
  problem,

  /// Offline, read-only, informational.
  info,

  /// Archived, retired, closed.
  neutral;

  /// This status's colour triple, out of the token layer.
  AppStatusRole role(AppTokens tokens) =>
      switch (this) {
        AppStatus.ok => tokens.colors.status.ok,
        AppStatus.attention => tokens.colors.status.attention,
        AppStatus.problem => tokens.colors.status.problem,
        AppStatus.info => tokens.colors.status.info,
        AppStatus.neutral => tokens.colors.status.neutral,
      };

  /// The glyph this status wears when a call site does not name one.
  ///
  /// **A default rather than a required argument, and the reason is the defect
  /// this component exists to fix.** §5.2 makes the icon mandatory and names
  /// none; leaving the choice to every call site reproduces, in glyphs, exactly
  /// the drift §1 describes in colour. A call site may still override it -
  /// "pending invitation" is better served by an envelope than by a clock - but
  /// it overrides a system rather than filling a blank.
  IconData get defaultIcon =>
      switch (this) {
        AppStatus.ok => Icons.check_circle_outline,
        AppStatus.attention => Icons.schedule,
        AppStatus.problem => Icons.error_outline,
        AppStatus.info => Icons.info_outline,
        AppStatus.neutral => Icons.remove_circle_outline,
      };
}

/// A status, as a small bordered container with an icon and a word.
///
/// §5.2: `radius.sm`, `label.md`, 24h, icon 14px leading, `space.8` padding,
/// the full status triple.
///
/// **The container is not decoration and must not be tidied away.** §2.1 notes
/// that [AppStatus.ok] and the brand accent are deliberately the same mint, and
/// that what disambiguates them is precisely this container: an action never
/// draws one and a status always does.
final class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
    required this.label,
    this.icon,
    this.semanticLabel,
  });

  final AppStatus status;

  /// The word. Sentence case, per §8 - this widget does not case it, because a
  /// widget that uppercased its own label would put uppercase somewhere §2.2
  /// permits only `label.eyebrow`.
  final String label;

  /// Overrides [AppStatus.defaultIcon] where a call site has a better glyph for
  /// its own meaning. Null takes the status's own.
  final IconData? icon;

  /// What a screen reader announces, where [label] alone is not a sentence.
  ///
  /// A badge reading "pending" in a row of staff means "this membership is
  /// pending", and the row supplies the rest visually. Null announces [label].
  final String? semanticLabel;

  /// §5.2's height, as a constant so a caller laying a badge into a row can
  /// reserve it without measuring.
  static const double height = 24;

  /// §5.2's icon size.
  static const double iconSize = 14;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final role = status.role(tokens);
    return Semantics(
      label: semanticLabel ?? label,
      container: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: role.bg,
              border: Border.all(color: role.border),
              borderRadius: BorderRadius.circular(tokens.radius.sm),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon ?? status.defaultIcon, size: iconSize, color: role.fg),
                  SizedBox(width: tokens.spacing.s4),
                  // **`Flexible`, or the `maxLines` below never fires.** A
                  // `Row` at `MainAxisSize.min` offers its children unbounded
                  // width, so a badge in a box narrower than its own word
                  // overflowed rather than ellipsising - which is the yellow
                  // stripe, not a shortened word. Found 2026-08-13 by
                  // `RecordList`, whose table gives a status column a share of
                  // the row rather than whatever the word wants; before that
                  // every badge in this app sat in a `Wrap` and was never
                  // constrained.
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.typography.labelMedium.copyWith(
                        color: role.fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A status at page scale: the notice paragraph that used to be loose text.
///
/// **§5.2 does not specify this component and every value below is read from a
/// §2 row rather than chosen here.** §5.1 gives it one line - it replaces
/// "permanent notice paragraphs" - and the rows it is assembled from are: the
/// status triple from §2.1 for the container, border and glyph; `radius.md`
/// from §2.3, which is the row for "cards, rows, sheets" and is the nearest
/// thing a page-scale block is; `space.16` padding and `space.12` between the
/// glyph and the words, both on §2.3's scale; `title.md` for [title] and the
/// density's body role for [message], which is §2.2's pairing for a card title
/// and its body.
///
/// **The icon is required here for the same reason it is on a badge**, and the
/// text carries `text.primary` rather than the status foreground: a paragraph
/// set in status red is harder to read than a paragraph beside a red glyph, and
/// §2.1's rule is that the status is the container plus the icon plus the word,
/// not that every word is tinted.
final class Callout extends StatelessWidget {
  const Callout({
    super.key,
    required this.status,
    required this.message,
    this.title,
    this.icon,
    this.action,
  });

  final AppStatus status;

  /// The notice itself. Multi-line is expected; this is the component prose
  /// moves *into*.
  final String message;

  /// One line above [message], for a notice whose first sentence is a heading.
  final String? title;

  final IconData? icon;

  /// One control under the message - "Retry", "Open settings". Left to the
  /// caller so this component decides nothing about what an action does.
  final Widget? action;

  /// The leading glyph, at §5.2's only named leading-icon size.
  ///
  /// Same reasoning as [Disclosure.glyphSize] and the same recorded gap: §5.1
  /// gives this component a row and no measurements at all, so a size is
  /// borrowed from a named row rather than invented. A larger glyph would look
  /// better against a page-scale block and would be a number nobody wrote down.
  static const double glyphSize = 18;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final role = status.role(tokens);
    final body = tokens.density.body(tokens.typography);
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: role.bg,
          border: Border.all(color: role.border),
          borderRadius: BorderRadius.circular(tokens.radius.md),
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                icon ?? status.defaultIcon,
                size: Callout.glyphSize,
                color: role.fg,
              ),
              SizedBox(width: tokens.spacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (title case final heading?) ...<Widget>[
                      Text(
                        heading,
                        style: tokens.typography.titleMedium.copyWith(
                          color: tokens.colors.text.primary,
                        ),
                      ),
                      SizedBox(height: tokens.spacing.s4),
                    ],
                    Text(
                      message,
                      style: body.copyWith(color: tokens.colors.text.secondary),
                    ),
                    if (action case final control?) ...<Widget>[
                      SizedBox(height: tokens.spacing.s12),
                      control,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A one-line summary that opens into the full explanation.
///
/// §5.2 calls this "the single highest-value component here", and the reason is
/// this app specifically: its explanatory copy is unusually good and it is all
/// permanent body text, which is what makes the catalog form three times taller
/// than it needs to be. Moving the prose in here keeps the writing and returns
/// the screen.
///
/// **Collapsed:** one line, `body.md`, leading info glyph, trailing chevron.
/// **Expanded:** the full explanation, `body.md` / `text.secondary`.
///
/// **The transition is a spring, and it is interruptible from wherever it is.**
/// §2.4 makes anything spatial a spring and a height change is spatial;
/// `spring.smooth` is the row that names "expansion" among its uses. The drive
/// is a [SpringDrive], so a second tap arriving mid-open retargets from the
/// current position and velocity rather than restarting - `claude.md`'s motion
/// rule, and the reason this does not use `AnimatedCrossFade` or
/// `ExpansionTile`, both of which are a duration and a curve.
final class Disclosure extends StatefulWidget {
  const Disclosure({
    super.key,
    required this.summary,
    required this.child,
    this.initiallyExpanded = false,
    this.enabled = true,
    this.onExpansionChanged,
    this.focusNode,
    this.autofocus = false,
  });

  /// The one line shown when it is closed. §5.2: one line, and the copy rule is
  /// §8's - it says what is inside rather than "More information".
  ///
  /// **One line means about 32 characters at §4.1's `compact` band**, and that
  /// figure is [summaryCharacterBudget] below rather than only a note here. This
  /// widget will not wrap a summary - §5.2 says one line - so keeping it short is
  /// the call site's responsibility, and a long one silently becomes
  /// "What a run is, and what it does not pro...". Step 4 shipped exactly that
  /// on the reconciliation day page and nobody saw it for two days, because no
  /// capture had ever put a `Disclosure` on a phone.
  final String summary;

  /// The explanation. Usually a [Text]; anything is allowed, because some of
  /// the prose this replaces ends in a list.
  final Widget child;

  final bool initiallyExpanded;

  /// False makes the header inert and paints the disabled label colour.
  ///
  /// A disclosure with nothing to say is not this - that is a call site not
  /// rendering one. This is for a disclosure whose content is not available
  /// yet.
  final bool enabled;

  final ValueChanged<bool>? onExpansionChanged;

  /// The header's focus node. §9 requires a visible focus indicator on every
  /// interactive element, and a caller that manages its own traversal needs a
  /// node to put in the order.
  final FocusNode? focusNode;

  final bool autofocus;

  /// The leading info glyph and the chevron, both at §5.2's **only** named
  /// leading-icon size.
  ///
  /// **§5.2 names a glyph for this component and no size for it**, the way it
  /// names a menu for `AppSelect` and no radius. The two sizes the document
  /// does name are `AppButton`'s leading icon at 18 and `StatusBadge`'s at 14,
  /// and this is a leading icon on a line of body text rather than a badge, so
  /// the button's figure is applied as the nearest named row rather than a
  /// third size being invented. Recorded in `PLAN.md` as a §5.2 gap alongside
  /// the field-hover one.
  static const double glyphSize = 18;

  /// How many characters of [summary] survive one line at §4.1's `compact` band.
  ///
  /// **Measured in the screenshot harness rather than in a widget test, and the
  /// distinction is the point.** A plain `flutter test` renders without the
  /// Material fonts, so `RenderParagraph.didExceedMaxLines` there reports a
  /// fallback font's advance widths - 406 logical pixels for a 25-character
  /// summary that actually fits in 295. The harness loads the real fonts, so its
  /// 411-wide captures are the only honest measurement, and this constant is what
  /// they said on 2026-08-14: "What this page can and cannot do" fits with room
  /// and "What a run is, and what it does not prove" ellipsises.
  ///
  /// It is deliberately not enforced by this widget. Truncating a summary is a
  /// legitimate rendering at a width nobody planned for; what is not legitimate
  /// is a call site that has never been laid out narrow, and a `length` assertion
  /// beside the screen is what catches that without depending on font metrics.
  static const int summaryCharacterBudget = 32;

  @override
  State<Disclosure> createState() => _DisclosureState();
}

class _DisclosureState extends State<Disclosure>
    with SingleTickerProviderStateMixin {
  SpringDrive? _drive;
  late bool _expanded = widget.initiallyExpanded;

  /// The tokens and the reduced-motion flag, read during `build` and held.
  ///
  /// The same reason [PressSurface] holds them: a tap can arrive while the tree
  /// above this widget is being torn down, and a `Theme.of` in a callback would
  /// look up a deactivated element.
  late AppTokens _tokens;
  bool _reducedMotion = false;

  SpringDrive get _spring =>
      _drive ??= SpringDrive(
        vsync: this,
        spring: _tokens.motion.smooth,
        value: _expanded ? 1 : 0,
      );

  @override
  void dispose() {
    _drive?.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _spring.animateTo(_expanded ? 1 : 0, immediately: _reducedMotion);
    widget.onExpansionChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    _tokens = AppTokens.componentOf(context);
    _reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final tokens = _tokens;
    final body = tokens.density.body(tokens.typography);
    final labelColor = widget.enabled
        ? tokens.colors.text.primary
        : tokens.colors.action.disabledLabel;
    final glyphColor = widget.enabled
        ? tokens.colors.status.info.fg
        : tokens.colors.action.disabledLabel;
    final radius = BorderRadius.circular(tokens.radius.sm);

    // Read once so the header and the body agree about where the spring is,
    // and so the chevron and the reveal cannot drift apart.
    final drive = _spring;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // `expanded` is the property that makes an opened disclosure
        // distinguishable from a closed one without sight. No `label` here: the
        // summary `Text` inside already supplies one, and setting both merges
        // into a node that announces the same sentence twice.
        Semantics(
          button: true,
          expanded: _expanded,
          enabled: widget.enabled,
          child: PressSurface(
            borderRadius: radius,
            fillWidth: true,
            excludeSemantics: true,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            onPressed: widget.enabled ? _toggle : null,
            hoverOverlay: tokens.colors.action.tertiary.hoverFill(),
            pressedOverlay: tokens.colors.action.tertiary.pressedFill(),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tokens.spacing.s8,
                vertical: tokens.spacing.s8,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.info_outline,
                    size: Disclosure.glyphSize,
                    color: glyphColor,
                  ),
                  SizedBox(width: tokens.spacing.s8),
                  Expanded(
                    child: Text(
                      widget.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: body.copyWith(color: labelColor),
                    ),
                  ),
                  SizedBox(width: tokens.spacing.s8),
                  // The chevron rotates on the same spring the reveal runs on,
                  // rather than on a second animation that could disagree with
                  // it mid-flight.
                  AnimatedBuilder(
                    animation: drive.animation,
                    builder: (context, child) => Transform.rotate(
                      angle: drive.value * (math.pi / 2),
                      child: child,
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      size: Disclosure.glyphSize,
                      color: widget.enabled
                          ? tokens.colors.text.secondary
                          : tokens.colors.action.disabledLabel,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // The reveal itself. `Align` with a fractional height is the shape that
        // lets the child keep its own intrinsic height while the visible extent
        // follows the spring - a `SizeTransition` would do the same on a
        // `Animation<double>` clamped to 0..1, and this spring is unbounded
        // because a spring may overshoot. The clamp is here rather than in the
        // drive so the physics stay honest and only the paint is bounded.
        AnimatedBuilder(
          animation: drive.animation,
          builder: (context, child) {
            final extent = drive.value.clamp(0.0, 1.0);
            // **Closed means gone from the tree, not clipped to nothing**, so a
            // screen reader does not read out prose nobody can see.
            //
            // The test is the flag *and* the spring, and the epsilon is not a
            // fudge: `SpringSimulation` decides it is done against
            // [Tolerance], whose defaults are absolute, so a spring asked for
            // zero parks within `distance` of it and stays there. Comparing
            // against that same tolerance is asking the physics where "arrived"
            // is rather than guessing. See the note on
            // [SettlingSpringSimulation], which is the other way to solve this
            // and is deliberately not wired into [SpringDrive].
            if (!_expanded && extent <= Tolerance.defaultTolerance.distance) {
              return const SizedBox.shrink();
            }
            return ClipRect(
              child: Align(
                alignment: Alignment.topLeft,
                heightFactor: extent,
                child: child,
              ),
            );
          },
          child: Padding(
            // Indented to where the summary's own text starts, so the
            // explanation reads as belonging to the line that opened it rather
            // than as a second paragraph beside it. Composed of the header's
            // own padding and glyph rather than restated as one figure.
            padding: EdgeInsets.fromLTRB(
              tokens.spacing.s8 + Disclosure.glyphSize + tokens.spacing.s8,
              tokens.spacing.s4,
              tokens.spacing.s8,
              tokens.spacing.s8,
            ),
            child: DefaultTextStyle.merge(
              style: body.copyWith(color: tokens.colors.text.secondary),
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }
}
