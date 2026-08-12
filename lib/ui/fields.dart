/// `AppTextField` and `AppSelect`: `design.md` §11 step 3's second half.
///
/// **One pattern, everywhere**, which is the first line of §5.2's field
/// specification and the thing this app had least of. Before this, a field was
/// one of three unrelated drawings: a bare `TextField` reading
/// `inputDecorationTheme` in the migrated tree, a `TextFormField` doing the same
/// with a validator attached, and `PillInput` on sign-in, which draws its own
/// well, its own label and its own focus glow while reading nothing from the
/// theme at all.
///
/// **The label is above the field and is always there.** §5.2 is explicit:
/// `label.md` in `text.secondary`, persistent. Not a floating label that becomes
/// a placeholder, and not a placeholder standing in for a label - both of which
/// this app currently does, on the same screen in one case. A placeholder is an
/// **example** and nothing else, which is why [AppTextField.placeholder] is
/// documented that way and why no call site passes the label into it.
///
/// **Error replaces helper text; it does not appear beside it.** §5.2 again, and
/// it decides the layout: one slot under the field holds either the helper line
/// or the error line, so a field never grows when it goes wrong and a form never
/// reflows under the finger that is typing into it.
///
/// **`AppSelect` has no specification of its own and that is recorded rather
/// than papered over.** §5.1 gives it a row - it replaces raw
/// `DropdownButtonFormField`, of which this app has five - and §5.2 specifies
/// only the "load-bearing five", which it is not among. So it is drawn as
/// [AppTextField]'s chrome around a menu: the same label, well, border, radius,
/// height, helper and error. That is the reading "one pattern, everywhere"
/// forces, and inventing a second field shape for it would contradict the
/// section it comes from.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// A single-line text input, drawn to `design.md` §5.2.
///
/// The label, the well, the helper line and the counter are this widget's; the
/// text editing itself is a plain [TextField] inside it, so every controller,
/// formatter and keyboard behaviour a call site already relies on is unchanged.
final class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.placeholder,
    this.helper,
    this.error,
    this.enabled = true,
    this.readOnly = false,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.obscureText = false,
    this.autovalidateMode,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.trailing,
    this.validator,
  });

  /// The persistent label above the field. §5.2 makes it `label.md` in
  /// `text.secondary`, and it is required because a field without one is what
  /// this component exists to remove.
  final String label;

  final TextEditingController? controller;

  /// An **example** of what goes in the field - never a restatement of
  /// [label]. §5.2 names the sign-in screen as the place this rule is currently
  /// broken in both directions at once.
  final String? placeholder;

  /// One line of `caption` / `text.tertiary` under the field. Anything longer
  /// belongs in a `Disclosure`, which is step 4's.
  final String? helper;

  /// The error message, which **replaces** [helper] rather than joining it.
  ///
  /// §5.2: never colour alone - "the message must state what to do". This
  /// widget cannot enforce that and its callers must; what it does enforce is
  /// that the message is real text a screen reader reads, rather than a red
  /// border and nothing else.
  final String? error;

  final bool enabled;

  /// Shown, readable, selectable, and not editable. §5's `read-only` state,
  /// which is a different thing from [enabled] being false: a disabled field is
  /// one a person may not use, and a read-only one holds a value they may not
  /// change.
  final bool readOnly;

  /// The limit. §5.2: the counter renders **only above 80% of it**, so a form
  /// is not carrying a dozen `0/120`s that mean nothing yet.
  final int? maxLength;

  final int maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool obscureText;

  /// When the [validator] runs on its own, rather than only on
  /// `Form.validate()`. Carried across from the call sites that set it.
  final AutovalidateMode? autovalidateMode;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;

  /// A control inside the well, at the trailing edge - a reveal toggle, a unit
  /// suffix. Painted inside the border so it reads as part of the field.
  final Widget? trailing;

  /// A `Form` validator, for the eight call sites that were `TextFormField`s.
  ///
  /// Passing one registers the field with the enclosing `Form`, so
  /// `Form.validate()` reaches it exactly as it did before, and the message it
  /// returns lands in the same slot [error] would - §5.2 has one error line and
  /// it does not matter which side produced it. Where both exist, [error] wins:
  /// a server's refusal is about the value that was *submitted* and a
  /// validator is about the value on screen.
  final FormFieldValidator<String>? validator;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  FocusNode? _ownedFocusNode;
  bool _focused = false;
  int _length = 0;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _length = widget.controller?.text.characters.length ?? 0;
    widget.controller?.addListener(_handleTextChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleTextChanged);
      widget.controller?.addListener(_handleTextChanged);
      _length = widget.controller?.text.characters.length ?? 0;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChanged);
      _focusNode.addListener(_handleFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleTextChanged);
    _focusNode.removeListener(_handleFocusChanged);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!mounted || _focused == _focusNode.hasFocus) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  /// The counter's input. Counted in **characters**, not code units, so an
  /// emoji or an accented letter counts once - the same unit `maxLength`
  /// enforces through `LengthLimitingTextInputFormatter`.
  void _handleTextChanged() {
    final length = widget.controller?.text.characters.length ?? 0;
    if (!mounted || length == _length) return;
    setState(() => _length = length);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.validator == null) return _well(context, error: widget.error);
    return FormField<String>(
      initialValue: widget.controller?.text ?? '',
      validator: widget.validator,
      enabled: widget.enabled,
      autovalidateMode: widget.autovalidateMode,
      builder: (field) => _well(
        field.context,
        // [AppTextField.error] wins: it describes the value that was submitted
        // and the validator describes the value on screen.
        error: widget.error ?? field.errorText,
        onChanged: field.didChange,
      ),
    );
  }

  Widget _well(
    BuildContext context, {
    String? error,
    ValueChanged<String>? onChanged,
  }) {
    final tokens = AppTokens.componentOf(context);
    return AppFieldWell(
      label: widget.label,
      helper: widget.helper,
      error: error,
      enabled: widget.enabled,
      focused: _focused,
      counter: _counterFor(tokens),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              readOnly: widget.readOnly,
              autofocus: widget.autofocus,
              maxLines: widget.maxLines,
              minLines: widget.minLines,
              // The counter is drawn by the well, so `TextField`'s own must be
              // suppressed rather than styled - two counters is worse than the
              // wrong one.
              maxLength: widget.maxLength,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              buildCounter: _noCounter,
              keyboardType: widget.keyboardType,
              textCapitalization: widget.textCapitalization,
              textInputAction: widget.textInputAction,
              autocorrect: widget.autocorrect,
              enableSuggestions: widget.enableSuggestions,
              obscureText: widget.obscureText,
              inputFormatters: widget.inputFormatters,
              onChanged: (value) {
                _handleTextChanged();
                onChanged?.call(value);
                widget.onChanged?.call(value);
              },
              onSubmitted: widget.onSubmitted,
              style: tokens.density
                  .body(tokens.typography)
                  .copyWith(
                    color: widget.enabled
                        ? tokens.colors.text.primary
                        : tokens.colors.action.disabledLabel,
                  ),
              cursorColor: tokens.colors.action.focusRing.color,
              // Every part of the well is drawn by `AppFieldWell`, so the
              // decoration here is stripped to nothing rather than restyled.
              // A `TextField` with a decoration inside a well is two wells.
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                isCollapsed: true,
                hintText: widget.placeholder,
                hintStyle: tokens.density
                    .body(tokens.typography)
                    .copyWith(color: tokens.colors.text.tertiary),
              ),
            ),
          ),
          if (widget.trailing case final trailing?) ...<Widget>[
            SizedBox(width: tokens.spacing.s8),
            trailing,
          ],
        ],
      ),
    );
  }

  /// §5.2: "Counters (`0/120`) render only above 80% of the limit."
  String? _counterFor(AppTokens tokens) {
    final limit = widget.maxLength;
    if (limit == null || limit <= 0) return null;
    if (_length / limit < 0.8) return null;
    return '$_length/$limit';
  }

  static Widget? _noCounter(
    BuildContext context, {
    required int currentLength,
    required int? maxLength,
    required bool isFocused,
  }) => null;
}

/// One choice out of a list, drawn in [AppTextField]'s well.
///
/// See the library note: §5.2 gives `AppSelect` no specification of its own, so
/// it borrows the field's entirely rather than inventing a second field shape.
final class AppSelect<T> extends StatefulWidget {
  const AppSelect({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.helper,
    this.error,
    this.enabled = true,
  });

  final String label;
  final T value;

  /// The options, in the order they are offered.
  final List<AppSelectItem<T>> items;

  /// Null disables the control, the same way it does on `AppButton`.
  final ValueChanged<T?>? onChanged;

  final String? helper;
  final String? error;
  final bool enabled;

  @override
  State<AppSelect<T>> createState() => _AppSelectState<T>();
}

/// One row of an [AppSelect].
@immutable
final class AppSelectItem<T> {
  const AppSelectItem({required this.value, required this.label});

  final T value;
  final String label;
}

class _AppSelectState<T> extends State<AppSelect<T>> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final enabled = widget.enabled && widget.onChanged != null;
    final labelColor = enabled
        ? tokens.colors.text.primary
        : tokens.colors.action.disabledLabel;
    return AppFieldWell(
      label: widget.label,
      helper: widget.helper,
      error: widget.error,
      enabled: enabled,
      focused: _focused,
      child: DropdownButtonHideUnderline(
        child: Focus(
          onFocusChange: (focused) {
            if (!mounted || _focused == focused) return;
            setState(() => _focused = focused);
          },
          child: DropdownButton<T>(
            value: widget.value,
            isExpanded: true,
            isDense: true,
            // The well already reserves the field's height, so the button must
            // not add its own 48 on top of it.
            itemHeight: null,
            focusColor: Colors.transparent,
            style: tokens.density
                .body(tokens.typography)
                .copyWith(color: labelColor),
            iconEnabledColor: tokens.colors.text.secondary,
            iconDisabledColor: tokens.colors.action.disabledLabel,
            // §2.1 puts a menu on `surface.overlay`. §2.3 does not name a menu
            // among its four radii; `radius.md` is the row for sheets, which is
            // the nearest thing a menu is, and it is applied rather than a
            // fifth radius being invented.
            dropdownColor: tokens.colors.surface.overlay,
            borderRadius: BorderRadius.circular(tokens.radius.md),
            onChanged: enabled ? widget.onChanged : null,
            items: <DropdownMenuItem<T>>[
              for (final item in widget.items)
                DropdownMenuItem<T>(
                  value: item.value,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chrome §5.2 specifies, without the control inside it.
///
/// Shared by [AppTextField] and [AppSelect] so the two cannot drift, and public
/// so a control this step does not cover - a date, a colour, whatever arrives -
/// can be put in the same well rather than draw a fourth one.
final class AppFieldWell extends StatelessWidget {
  const AppFieldWell({
    super.key,
    required this.label,
    required this.child,
    this.helper,
    this.error,
    this.counter,
    this.enabled = true,
    this.focused = false,
  });

  final String label;
  final Widget child;
  final String? helper;
  final String? error;
  final String? counter;
  final bool enabled;

  /// Whether the ring is painted.
  ///
  /// **A field shows focus however it was focused, and a button does not.**
  /// `PressSurface` paints §9's ring only under
  /// [FocusHighlightMode.traditional], because a ring that appears when a
  /// thumb lands on a button is noise. A focused field is not a highlight, it
  /// is *where the keys go* - and on a form with several of them, not saying
  /// which one is receiving the typing is the failure §9 is about.
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final ring = colors.action.focusRing;
    final failed = error != null;

    final borderColor = !enabled
        ? colors.action.disabledBorder
        : failed
        ? colors.status.problem.border
        : colors.surface.borderStrong;

    // §5.2: 48h at comfortable density. §3's own figure for the same surface is
    // its minimum tap target, so the height is read from there rather than
    // declared twice - and a compact back-office field is 32 for the same
    // reason its rows are.
    final height = tokens.density.minimumTapTarget.height;
    final radius = BorderRadius.circular(tokens.radius.sm);
    final gutter = ring.width + ring.offset;

    Widget well = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.sunken,
        borderRadius: radius,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s12),
          child: Center(heightFactor: 1, child: child),
        ),
      ),
    );

    // The ring's gutter is reserved whether or not it is painted, exactly as
    // `PressSurface` reserves it: a form that reflowed every time the focus
    // moved between two of its fields would be a worse §9 failure than the one
    // the ring fixes.
    //
    // **The `Stack` wraps the padded box rather than sitting inside it**, and
    // that ordering is the whole trick: `Positioned.fill` then covers the
    // gutter as well as the well, so an inset of `ring.offset` puts the ring
    // *outside* the well's outline. Inside, the only way to reach the same
    // place is a negative padding, which asserts.
    //
    // **The `Stack` is always here, and the ring appears by losing its
    // border rather than by being inserted.** `PressSurface` inserts its
    // `Stack` on focus, which is harmless for a button and is not harmless
    // here: a field that changed the shape of the tree above its `TextField`
    // the instant it was focused would re-parent that `TextField`, take its
    // `EditableText` state with it, and drop the platform input connection -
    // the field would take focus and then refuse every keystroke. Found by a
    // test that could not type into it.
    well = Stack(
      children: <Widget>[
        Padding(padding: EdgeInsets.all(gutter), child: well),
        Positioned.fill(
          child: IgnorePointer(
            child: Padding(
              padding: EdgeInsets.all(ring.offset),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: focused && enabled
                      ? Border.all(color: ring.color, width: ring.width)
                      : null,
                  borderRadius: radius + BorderRadius.circular(ring.offset),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    final footnote = error ?? helper;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          // The label sits over the well's own gutter, so the gap a person sees
          // between the two is `space.4` plus the ring's 4 rather than a
          // second, larger one.
          padding: EdgeInsets.only(
            left: gutter,
            right: gutter,
            bottom: tokens.spacing.s4,
          ),
          child: Text(
            label,
            style: tokens.typography.labelMedium.copyWith(
              color: enabled
                  ? colors.text.secondary
                  : colors.action.disabledLabel,
            ),
          ),
        ),
        well,
        if (footnote != null || counter != null)
          Padding(
            padding: EdgeInsets.only(
              left: gutter,
              right: gutter,
              top: tokens.spacing.s4,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (footnote != null)
                  Expanded(
                    child: Text(
                      footnote,
                      // §5.2: the error **replaces** the helper line, so this
                      // slot holds one or the other and the field's height does
                      // not change when it goes wrong.
                      style: tokens.typography.caption.copyWith(
                        color: failed
                            ? colors.status.problem.fg
                            : colors.text.tertiary,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (counter != null)
                  Padding(
                    padding: EdgeInsets.only(left: tokens.spacing.s8),
                    child: Text(
                      counter!,
                      style: tokens.typography.caption.copyWith(
                        color: colors.text.tertiary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
