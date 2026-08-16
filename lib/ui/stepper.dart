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

import 'fields.dart';
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

  /// How wide the whole control is: two buttons, two gaps and the well.
  ///
  /// Exposed because the error line under it is bounded to this rather than to
  /// its own sentence - see the note at that call site.
  static double controlWidth(AppSpacing spacing, {int? maximum}) =>
      height * 2 + spacing.s8 * 2 + wellWidth(spacing, maximum: maximum);

  /// How wide the number's well is drawn, given a [maximum].
  ///
  /// **Derived rather than picked**, which is the difference between this and
  /// the 132 the cart used: §5.2 gives a field `space.20` of padding on each
  /// side, and a digit at `numeric.body` is about 9 logical pixels wide, so the
  /// well is the padding plus room for the digits it is sized for. Sizing for a
  /// bound rather than for the current value is what stops the row reflowing
  /// when a quantity goes from 9 to 10.
  static double wellWidth(AppSpacing spacing, {int? maximum}) {
    final wanted = (maximum ?? 9999).toString().length;
    final digits = wanted < maximumSizedDigits ? wanted : maximumSizedDigits;
    return spacing.s20 * 2 + digits * 9.0;
  }

  @override
  State<QuantityStepper> createState() => _QuantityStepperState();
}

class _QuantityStepperState extends State<QuantityStepper> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.quantity.toString(),
  );

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
        Row(
          mainAxisSize: MainAxisSize.min,
          // The well is the tallest thing here and the buttons sit against its
          // top edge, so a helper or a counter under the number never drags the
          // two controls down with it.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _StepButton(
              key: const ValueKey('quantity-stepper-decrement'),
              icon: Icons.remove,
              semanticLabel: widget.decrementSemanticLabel,
              onPressed: widget.enabled ? widget.onDecrement : null,
            ),
            SizedBox(width: tokens.spacing.s8),
            Semantics(
              label: widget.semanticLabel,
              textField: true,
              child: SizedBox(
              width: QuantityStepper.wellWidth(
                tokens.spacing,
                maximum: widget.maximum,
              ),
              child: AppTextField(
                key: const ValueKey('quantity-stepper-field'),
                // The label is drawn above the whole control, so the field
                // inside carries none - two labels for one number is what a
                // stepper assembled from a field and two buttons looks like.
                label: '',
                controller: _controller,
                enabled: widget.enabled,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: widget.onChanged,
                // The outline and the announcement, not the words: the
                // sentence is drawn under the whole control below, because a
                // 76-pixel well wraps it to six lines and pushes the two
                // buttons out of alignment with the number they change.
                error: widget.error,
                showsErrorText: false,
              ),
              ),
            ),
            SizedBox(width: tokens.spacing.s8),
            _StepButton(
              key: const ValueKey('quantity-stepper-increment'),
              icon: Icons.add,
              semanticLabel: widget.incrementSemanticLabel,
              onPressed: widget.enabled ? widget.onIncrement : null,
            ),
          ],
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

/// One square control, in §2.1's `secondary` tier.
///
/// **An `AppButton` would be the obvious choice and is the wrong shape**: it
/// takes a `label` and centres it with §5.2's horizontal padding, so a
/// glyph-only button comes out label-width plus 40 and the two sides of a
/// stepper stop being square. This borrows the tier's colours and `PressSurface`
/// underneath, which is what `AppButton` is made of.
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
    final role = tokens.colors.action.secondary;
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
          foregroundColor: disabled
              ? tokens.colors.action.disabledLabel
              : role.label,
          side: BorderSide(
            color: disabled
                ? tokens.colors.action.disabledBorder
                : role.border!,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radius.pill),
          ),
        ),
      ),
    );
  }
}
