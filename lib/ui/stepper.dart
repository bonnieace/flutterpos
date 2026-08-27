/// `QuantityStepper`: `design.md` §5.1's **priority 1** row, whose "Replaces"
/// column is four words long and is the whole specification — *"minus + delete,
/// no plus"*.
///
/// **The defect is the missing plus.** A cashier who rang up one loaf and needs
/// two has to leave the cart, find the tile in the product grid and press it
/// again. The minus is there, the bin is there, and the one operation the
/// control is shaped like is the one it does not offer.
///
/// **What this deliberately does not change is what the minus does.**
/// `claude.md` hard rule 1 keeps state logic out of a visual change, so
/// decrementing past one still removes the line exactly as it did, and the bin
/// still removes it outright. §5.1's complaint is the absent plus and this
/// answers that; whether a stepper should *disable* at one rather than remove is
/// a behaviour question and is recorded in `PLAN.md` rather than taken here.
///
/// **The plus adds no operation that did not exist**, which is why it is inside
/// hard rule 1 rather than against it: adding one of something is what a product
/// tile already does, through the same callback. This surfaces it where a person
/// is already looking instead of sending them back across the screen.
///
/// **Typing survives.** The field is the same editable one, with the same rule
/// the cart already had - a half-typed number never becomes the sale, and the
/// line keeps its last usable value - because that rule is behaviour and this is
/// not the change that gets to touch it.
///
/// **The state matrix is five rows.** `enabled`, `disabled`, `error` - the typed
/// value is not usable - and the two bounds, where the minus or the plus is
/// individually unavailable because the quantity is at the floor or the ceiling.
/// `hover`, `focus-visible` and `pressed` belong to the two `AppButton`s and
/// arrive with them; `loading`, `read-only` and `empty` have no meaning for a
/// count.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// A count, with a control on each side of it.
final class QuantityStepper extends StatefulWidget {
  const QuantityStepper({
    super.key,
    this.label,
    required this.quantity,
    required this.onChanged,
    this.onIncrement,
    this.onDecrement,
    this.maximum,
    this.error,
    this.enabled = true,
    this.decrementSemanticLabel = 'One fewer',
    this.incrementSemanticLabel = 'One more',
    this.semanticLabel = 'Quantity',
  });

  /// A persistent label above the control, where one earns its place.
  ///
  /// **Optional, unlike `AppTextField`'s, and the difference is the component.**
  /// §5.2 makes a field's label required because a bare field is a box that
  /// says nothing about itself - that rule exists to kill placeholder-as-label.
  /// A stepper is not a bare field: a minus, a number and a plus is a shape that
  /// names itself, and §5.1 lists it as its own row rather than as a field
  /// variant.
  ///
  /// **It is null in a cart line and the reason is measurable.** Sixteen lines
  /// each carrying the word *Quantity* above a control that obviously is one
  /// added enough height to push the save button off a phone - which two tests
  /// caught by failing to find it. What replaces it for a person who cannot see
  /// the shape is [semanticLabel], which is announced either way.
  final String? label;

  /// The count as the *cart* holds it — which is not always what is typed. See
  /// [error].
  final int quantity;

  /// A directly typed value, raw. Parsing and refusing it is the caller's, for
  /// the reason the library note gives: that rule is behaviour.
  final ValueChanged<String> onChanged;

  /// Null disables the plus. A line whose product the cached catalog no longer
  /// holds cannot be incremented, because there is nothing to add.
  final VoidCallback? onIncrement;

  /// Null disables the minus.
  final VoidCallback? onDecrement;

  /// The ceiling, used to size the field so the row does not reflow as digits
  /// are added. Null sizes for four digits.
  final int? maximum;

  /// Set when what is typed is not a usable quantity. §5.2: the error replaces
  /// the helper line and never joins it, and the message must state what to do.
  final String? error;

  final bool enabled;

  /// §9: "icon-only controls — required semantic label".
  final String decrementSemanticLabel;
  final String incrementSemanticLabel;

  /// What a screen reader calls the number itself.
  ///
  /// Required in effect: [label] is what a sighted person reads and this is
  /// what everybody else does, so the control is never unnamed even when it
  /// draws no words.
  final String semanticLabel;

  /// §5.2's `lg` height, which is also §9's tap target. Both buttons and the
  /// well are this tall so the row has one baseline.
  static const double height = 48;

  /// The most digits the well is drawn wide, however high the ceiling goes.
  ///
  /// **Sizing for the ceiling starves the record beside it, and this is the
  /// figure that stops it.** The till's own bound is `1,000,000`, so deriving
  /// the width from it made the well seven digits and the whole stepper 215
  /// logical pixels; inside a 420-wide cart pane that left about **77** for the
  /// product name, and every line wrapped to four or five rows. Two tests
  /// caught it by failing to find the save button, which had been pushed off
  /// the end of a 4000-pixel pane.
  ///
  /// Four digits covers every quantity a shop counts by hand. A larger number
  /// still types and still totals - the field scrolls its own content, which is
  /// the ordinary behaviour of a field too small for what is in it, and is a
  /// better failure than a cart nobody can read.
  static const int maximumSizedDigits = 4;

  /// How wide the whole control is: two buttons and the number between them.
  ///
  /// **No gaps since 2026-08-23, because the three pieces are one control.**
  /// The design draws a stepper as
  /// `flex items-center bg-surface-elevated rounded-lg border` with the two
  /// buttons and the number inside a single bordered group; this app drew a
  /// bordered circle, a gap, a bordered well, a gap and a second circle, which
  /// is five shapes for one number and the widest thing on a cart line.
  ///
  /// Exposed because the error line under it is bounded to this rather than to
  /// its own sentence - see the note at that call site.
  static double controlWidth(AppSpacing spacing, {int? maximum}) =>
      height * 2 + wellWidth(spacing, maximum: maximum);

  /// How wide the number itself is drawn, given a [maximum].
  ///
  /// **Derived rather than picked.** A digit at `numeric.body` is about 9
  /// logical pixels wide and the number sits inside the group rather than in a
  /// well of its own, so it takes `space.8` of breathing room each side rather
  /// than a field's `space.20`. Sizing for a bound rather than for the current
  /// value is what stops the row reflowing when a quantity goes from 9 to 10.
  static double wellWidth(AppSpacing spacing, {int? maximum}) {
    final wanted = (maximum ?? 9999).toString().length;
    final digits = wanted < maximumSizedDigits ? wanted : maximumSizedDigits;
    return spacing.s8 * 2 + digits * 9.0;
  }

  @override
  State<QuantityStepper> createState() => _QuantityStepperState();
}

class _QuantityStepperState extends State<QuantityStepper> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.quantity.toString(),
  );

  /// Whether the number is taking the keys, so the group can show it.
  ///
  /// The group draws the outline now, so the focus signal has to live at the
  /// group rather than inside it - the same rule `AppFieldWell` follows, one
  /// level out.
  bool _focused = false;

  @override
  void didUpdateWidget(covariant QuantityStepper old) {
    super.didUpdateWidget(old);
    // **The field belongs to the person, not to the cart**, which is the rule
    // the cart's own field already carried and which is preserved verbatim: it
    // is overwritten only when the cart itself moved the number - a plus or a
    // minus - and never while an entry is merely unusable. Snapping a rejected
    // entry back to the last good value would leave a valid number on screen
    // beside a message saying the quantity is wrong, with nothing to correct.
    if (old.quantity != widget.quantity &&
        int.tryParse(_controller.text.trim()) != widget.quantity) {
      _controller.text = widget.quantity.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleFocus(bool focused) {
    if (!mounted || _focused == focused) return;
    setState(() => _focused = focused);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.label case final words?) ...<Widget>[
          Text(
            words,
            style: tokens.typography.labelMedium.copyWith(
              color: tokens.colors.text.secondary,
            ),
          ),
          SizedBox(height: tokens.spacing.s4),
        ],
        // **One bordered group holding all three, which is how the design
        // draws a stepper**: `flex items-center bg-surface-elevated rounded-lg
        // border border-surface-container-high`, two icon buttons and the
        // number between them. The outline is the group's, so the two buttons
        // carry none of their own and the number is a bare field rather than a
        // second well inside the first.
        DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.colors.surface.field,
            borderRadius: BorderRadius.circular(tokens.radius.md),
            border: Border.all(
              color: !widget.enabled
                  ? tokens.colors.action.disabledBorder
                  : widget.error != null
                  ? tokens.colors.status.problem.fg
                  : _focused
                  ? tokens.colors.action.focusRing.color
                  : tokens.colors.surface.borderSubtle,
              // The focused outline is the same 2px, painted outward, that
              // `AppFieldWell` settled on - see the note there.
              width: _focused && widget.enabled
                  ? tokens.colors.action.focusRing.width
                  : 1,
              strokeAlign: _focused && widget.enabled
                  ? BorderSide.strokeAlignOutside
                  : BorderSide.strokeAlignInside,
            ),
          ),
          child: SizedBox(
            height: QuantityStepper.height,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _StepButton(
                  key: const ValueKey('quantity-stepper-decrement'),
                  icon: Icons.remove,
                  semanticLabel: widget.decrementSemanticLabel,
                  onPressed: widget.enabled ? widget.onDecrement : null,
                ),
                Semantics(
                  label: widget.semanticLabel,
                  textField: true,
                  child: SizedBox(
                    width: QuantityStepper.wellWidth(
                      tokens.spacing,
                      maximum: widget.maximum,
                    ),
                    child: Focus(
                      onFocusChange: _handleFocus,
                      child: TextField(
                        key: const ValueKey('quantity-stepper-field'),
                        controller: _controller,
                        enabled: widget.enabled,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: widget.onChanged,
                        cursorColor: tokens.colors.action.focusRing.color,
                        // The design sets the number in `data-mono`, which is
                        // what makes a column of carts line up.
                        style: tokens.typography.mono.copyWith(
                          color: widget.enabled
                              ? tokens.colors.text.primary
                              : tokens.colors.action.disabledLabel,
                        ),
                        // Every part of the chrome is the group's, so the
                        // field contributes none. A decoration here would be a
                        // second box inside the first.
                        decoration: const InputDecoration(
                          isDense: true,
                          isCollapsed: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                ),
                _StepButton(
                  key: const ValueKey('quantity-stepper-increment'),
                  icon: Icons.add,
                  semanticLabel: widget.incrementSemanticLabel,
                  onPressed: widget.enabled ? widget.onIncrement : null,
                ),
              ],
            ),
          ),
        ),
        // §5.2's error line, at the width of the control rather than of the
        // well inside it - and **bounded to that width**, which is the second
        // half of the same fix. An unbounded `Text` here sized the whole
        // stepper to its own sentence, about 300 logical pixels, and the cart
        // line's `Row` overflowed at 356: the identity column is `Expanded` and
        // shrinks, so the only thing that could give was the product's name.
        if (widget.error case final message?) ...<Widget>[
          SizedBox(height: tokens.spacing.s4),
          SizedBox(
            width: QuantityStepper.controlWidth(
              tokens.spacing,
              maximum: widget.maximum,
            ),
            child: Text(
              message,
              style: tokens.typography.caption.copyWith(
                color: tokens.colors.status.problem.fg,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One square control inside the stepper's group.
///
/// **An `AppButton` would be the obvious choice and is the wrong shape**: it
/// takes a `label` and centres it with §5.2's horizontal padding, so a
/// glyph-only button comes out label-width plus 40 and the two sides of a
/// stepper stop being square.
///
/// **It draws no border and no container of its own since 2026-08-23.** The
/// group around it is the control's outline; a bordered circle inside a
/// bordered group is the five-shapes rendering this replaced. It keeps its 48
/// square, which is §9's target and the design's own `w-11 h-11` rounded up to
/// this app's floor.
final class _StepButton extends StatelessWidget {
  const _StepButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final disabled = onPressed == null;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: 18,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(QuantityStepper.height),
          backgroundColor: Colors.transparent,
          foregroundColor: disabled
              ? tokens.colors.action.disabledLabel
              : tokens.colors.text.secondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radius.md),
          ),
        ),
      ),
    );
  }
}
