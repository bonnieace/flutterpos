/// Choosing one thing out of a few, and switching things on and off.
///
/// **Two controls this app did not have, both first needed by the stock count
/// settings screen** (`docs/design/stock-counts/`). There was no radio
/// component in `lib/ui/` at all, and the only on/off control was an
/// [AppButton] whose tier changed - which says *on* with a fill and nothing
/// else, and says nothing to a screen reader.
///
/// - [ChoiceCardGroup] is for a choice whose options have different
///   consequences, so that every consequence is on screen before one is picked.
///   A `FilterChipBar` shows the words and hides what they mean, and at
///   `compact` it scrolls sideways, so an option can be off the edge of the
///   screen entirely.
/// - [AppToggleButton] is one of a row of independent on/off switches - the
///   days of a week. On carries a glyph as well as a fill (hard rule 4), and
///   `toggled` carries it to a screen reader.
///
/// **Every value is read from the token layer or from an existing component.**
/// Where a size had no row anywhere, it is named on the class with its reason,
/// the precedent `StatusBadge.iconSize` and `Callout.glyphSize` set.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'buttons.dart';
import 'chips.dart';
import 'measure.dart';
import 'press.dart';
import 'tokens.dart';

// ---------------------------------------------------------------------------
// ChoiceCardGroup
// ---------------------------------------------------------------------------

/// One run of text in a [ChoiceCardOption.detail] line.
///
/// **Emphasis is a role, not a colour.** A detail line quotes what another
/// screen says - *A stock count is due*, *Not now* - and the quotation is what
/// a reader's eye should catch. The caller marks which runs are quoted; the
/// card decides what emphasis looks like.
@immutable
final class ChoiceDetailRun {
  const ChoiceDetailRun(this.text, {this.emphasis = false});

  final String text;
  final bool emphasis;
}

/// One option in a [ChoiceCardGroup].
@immutable
final class ChoiceCardOption<T> {
  const ChoiceCardOption({
    required this.value,
    required this.title,
    this.description,
    this.detail = const <ChoiceDetailRun>[],
    this.detailIcon,
    this.icon,
    this.key,
  });

  final T value;

  /// A glyph naming what the option is - a PDF, a spreadsheet - drawn in a well
  /// at the card's leading edge.
  ///
  /// **With one, the radio moves to the trailing edge.** A radio, a glyph and
  /// then the words is three things before the reader reaches the title; the
  /// glyph is what identifies the option, so it leads, and the radio still
  /// states the choice - which is what keeps a selection from being colour
  /// alone.
  final IconData? icon;

  /// The option's name, in the words the rest of the app uses for it.
  final String title;

  /// What choosing it does, shown selected or not.
  ///
  /// **Optional since 2026-10-03**, at the developer's direction: where the
  /// titles say enough on their own - a PDF or the totals, automatically or by
  /// hand - the card is its title alone.
  final String? description;

  /// A quieter line under [description], for where the consequence shows up.
  final List<ChoiceDetailRun> detail;

  /// A glyph leading [detail]. Ignored when [detail] is empty.
  final IconData? detailIcon;

  /// This card's own key, so a screen's tests keep addressing an option rather
  /// than the group.
  final Key? key;
}

/// A single choice, drawn as a stack of cards that each state what they do.
///
/// **States:** enabled, hover, pressed, focus-visible and selected per card,
/// and read-only for the group. Pressed is [PressSurface]'s spring and scale,
/// so there is no motion here that is not already the app's.
///
/// **Read-only draws only the chosen card, with no radio.** Three cards with
/// one lit read as a control whether or not it answers, and on a device that
/// cannot change the choice the other two are options nobody here can take.
///
/// **Arrow keys move the selection**, as in any radio group, and focus follows
/// it. Tab moves into and out of the group through each card, which is what
/// [PressSurface] already does.
///
/// **[flat] draws the same group as rows on the page** - glyph, title, radio -
/// with no card around any of them, as a phone's own settings list does. The
/// semantics, the arrow keys and the read-only rule are this class's in both,
/// because the state is: only the drawing of one option differs.
final class ChoiceCardGroup<T> extends StatefulWidget {
  const ChoiceCardGroup({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.semanticLabel,
    this.flat = false,
  });

  final List<ChoiceCardOption<T>> options;
  final T selected;

  /// Null draws the group read-only. See the class note.
  final ValueChanged<T>? onSelected;

  /// What the group is a choice about, for a screen reader.
  final String semanticLabel;

  /// Rows on the page rather than cards, for a choice whose options are said
  /// by their titles alone - the WhatsApp receipts screen's, on 2026-10-04.
  ///
  /// **The chosen row's glyph takes the action green beside its filled
  /// radio**, and the row takes no wash of its own: with no card there is no
  /// container to fill, and the radio is what keeps the choice from being
  /// colour alone. A row stands in [PressSurface]'s ring gutter like every
  /// pressable here, so a stack of them is `density.minimumTapTarget` plus the
  /// gutter apart, with nothing between.
  final bool flat;

  /// The radio's outer diameter.
  ///
  /// **Named here rather than tokenised**, for the reason `Callout.glyphSize`
  /// gives: no source this app has states a radio, and 20 is the nearest the
  /// spacing scale comes to the glyph sizes beside it without being one of
  /// them - a radio that matched an 18 glyph would read as a glyph.
  static const double radioSize = 20;

  /// The filled dot inside a selected radio. Half the ring, so it reads as a
  /// dot and not as a filled circle with a hairline.
  static const double radioDotSize = radioSize / 2;

  /// The width of a selected card's edge. The focus ring's own width, so the
  /// two strongest edges in the app are the same weight.
  static double selectedEdgeWidth(AppTokens tokens) =>
      tokens.colors.action.focusRing.width;

  @override
  State<ChoiceCardGroup<T>> createState() => _ChoiceCardGroupState<T>();
}

class _ChoiceCardGroupState<T> extends State<ChoiceCardGroup<T>> {
  final List<FocusNode> _nodes = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    _syncNodes();
  }

  @override
  void didUpdateWidget(covariant ChoiceCardGroup<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncNodes();
  }

  void _syncNodes() {
    while (_nodes.length < widget.options.length) {
      _nodes.add(FocusNode(debugLabel: 'choice-card-${_nodes.length}'));
    }
    while (_nodes.length > widget.options.length) {
      _nodes.removeLast().dispose();
    }
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final onSelected = widget.onSelected;
    if (onSelected == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final step =
        key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowRight
        ? 1
        : key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowLeft
        ? -1
        : 0;
    if (step == 0) return KeyEventResult.ignored;
    final focused = _nodes.indexWhere((node) => node.hasFocus);
    final from = focused >= 0
        ? focused
        : widget.options.indexWhere((o) => o.value == widget.selected);
    if (from < 0) return KeyEventResult.ignored;
    final to = (from + step) % widget.options.length;
    onSelected(widget.options[to].value);
    _nodes[to].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final onSelected = widget.onSelected;
    if (onSelected == null) {
      final chosen = widget.options
          .where((option) => option.value == widget.selected)
          .firstOrNull;
      return Semantics(
        container: true,
        label: widget.semanticLabel,
        child: chosen == null
            ? const SizedBox.shrink()
            : widget.flat
            ? _ChoiceRow<T>(
                key: chosen.key,
                option: chosen,
                selected: true,
                readOnly: true,
                onPressed: null,
                focusNode: null,
              )
            : _ChoiceCard<T>(
                key: chosen.key,
                option: chosen,
                selected: true,
                readOnly: true,
                onPressed: null,
                focusNode: null,
              ),
      );
    }
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      explicitChildNodes: true,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final (index, option) in widget.options.indexed) ...<Widget>[
              if (widget.flat)
                _ChoiceRow<T>(
                  key: option.key,
                  option: option,
                  selected: option.value == widget.selected,
                  readOnly: false,
                  focusNode: _nodes[index],
                  onPressed: () => onSelected(option.value),
                )
              else ...<Widget>[
                if (index > 0) SizedBox(height: tokens.spacing.s4),
                _ChoiceCard<T>(
                  key: option.key,
                  option: option,
                  selected: option.value == widget.selected,
                  readOnly: false,
                  focusNode: _nodes[index],
                  onPressed: () => onSelected(option.value),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

final class _ChoiceCard<T> extends StatelessWidget {
  const _ChoiceCard({
    super.key,
    required this.option,
    required this.selected,
    required this.readOnly,
    required this.onPressed,
    required this.focusNode,
  });

  final ChoiceCardOption<T> option;
  final bool selected;
  final bool readOnly;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    // `radius.lg`: a card here is a panel holding three lines, the same shape
    // the settings index gives each of its rows.
    final radius = BorderRadius.circular(tokens.radius.lg);
    final edgeWidth = ChoiceCardGroup.selectedEdgeWidth(tokens);

    // **Selected wears the `ok` wash under the action edge.** The fill is the
    // one a selected filter chip takes, so a selection looks like a selection
    // everywhere; the edge is the action green at the focus ring's weight,
    // because a 30% edge around a card this size disappears.
    final Color container;
    final Color edge;
    final double width;
    if (readOnly) {
      container = Colors.transparent;
      edge = colors.surface.cardEdge;
      width = 1;
    } else if (selected) {
      container = colors.status.ok.bg;
      edge = colors.action.primary.container;
      width = edgeWidth;
    } else {
      container = colors.surface.raised;
      edge = colors.surface.cardEdge;
      width = 1;
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          option.title,
          style: tokens.typography.bodyLarge.copyWith(
            color: colors.text.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (option.description case final description?) ...<Widget>[
          SizedBox(height: tokens.spacing.s4),
          Text(
            description,
            style: tokens.typography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
        if (option.detail.isNotEmpty) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          _Detail(runs: option.detail, icon: option.detailIcon),
        ],
      ],
    );

    // A border on a `DecoratedBox` is painted, not laid out, so the thicker
    // selected edge costs no space and the text holds still when the
    // selection moves.
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: container,
        borderRadius: radius,
        border: Border.all(color: edge, width: width),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s16),
        child: readOnly
            ? body
            : option.icon != null
            ? Row(
                children: <Widget>[
                  _GlyphWell(icon: option.icon!, selected: selected),
                  SizedBox(width: tokens.spacing.s12),
                  Expanded(child: body),
                  SizedBox(width: tokens.spacing.s12),
                  _Radio(selected: selected),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    // Centres the radio on the title's first line rather than
                    // on the top of its line box.
                    padding: EdgeInsets.only(
                      top:
                          _titleLineHeight(tokens) / 2 -
                          ChoiceCardGroup.radioSize / 2,
                    ),
                    child: _Radio(selected: selected),
                  ),
                  SizedBox(width: tokens.spacing.s12),
                  Expanded(child: body),
                ],
              ),
      ),
    );

    if (readOnly) {
      return Semantics(
        container: true,
        label: option.title,
        value: option.description,
        child: ExcludeSemantics(child: card),
      );
    }
    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: option.title,
      hint: option.description,
      onTap: onPressed,
      excludeSemantics: true,
      child: PressSurface(
        borderRadius: radius,
        onPressed: onPressed,
        focusNode: focusNode,
        fillWidth: true,
        excludeSemantics: true,
        hoverOverlay: colors.action.secondary.hoverWash(),
        pressedOverlay: colors.action.secondary.pressedWash(),
        child: card,
      ),
    );
  }

  static double _titleLineHeight(AppTokens tokens) {
    final style = tokens.typography.bodyLarge;
    return (style.fontSize ?? 0) * (style.height ?? 1);
  }
}

/// One option of a [ChoiceCardGroup.flat] group: its glyph, its title and its
/// radio, on the page.
///
/// **States:** enabled, hover and pressed as the action green's 8% and 12%
/// wash over the row - [Disclosure]'s, so every flat row on a page answers a
/// pointer alike - focus-visible as [PressSurface]'s ring, selected as the lit
/// glyph and the filled radio, and read-only in the page's own ink with no
/// radio - a setting this person may not change is still the setting, and the
/// disabled ink would say it is not available.
final class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    super.key,
    required this.option,
    required this.selected,
    required this.readOnly,
    required this.onPressed,
    required this.focusNode,
  });

  final ChoiceCardOption<T> option;
  final bool selected;
  final bool readOnly;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final actions = colors.action;
    final radius = BorderRadius.circular(tokens.radius.md);
    final glyphColor = readOnly
        ? colors.text.secondary
        : selected
        ? actions.primary.container
        : colors.text.tertiary;

    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          option.title,
          style: tokens.typography.bodyLarge.copyWith(
            color: colors.text.primary,
          ),
        ),
        if (option.description case final description?)
          Text(
            description,
            style: tokens.typography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        if (option.detail.isNotEmpty) ...<Widget>[
          SizedBox(height: tokens.spacing.s4),
          _Detail(runs: option.detail, icon: option.detailIcon),
        ],
      ],
    );

    // At least a tap target high, so a row with one line of title is the same
    // height as a card's control and a row whose title wraps grows instead.
    final row = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: tokens.density.minimumTapTarget.height,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.s8,
          vertical: tokens.spacing.s4,
        ),
        child: Row(
          children: <Widget>[
            if (option.icon case final icon?) ...<Widget>[
              ExcludeSemantics(
                child: Icon(icon, size: tokens.spacing.s24, color: glyphColor),
              ),
              SizedBox(width: tokens.spacing.s16),
            ],
            Expanded(child: words),
            if (!readOnly) ...<Widget>[
              SizedBox(width: tokens.spacing.s16),
              _Radio(selected: selected),
            ],
          ],
        ),
      ),
    );

    if (readOnly) {
      // Not pressable, so it takes the ring's gutter itself: its glyph and
      // title then sit exactly where a pressable row's would.
      final ring = actions.focusRing;
      return Semantics(
        container: true,
        label: option.title,
        value: option.description,
        child: ExcludeSemantics(
          child: Padding(
            padding: EdgeInsets.all(ring.width + ring.offset),
            child: row,
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: option.title,
      hint: option.description,
      onTap: onPressed,
      excludeSemantics: true,
      child: PressSurface(
        borderRadius: radius,
        onPressed: onPressed,
        focusNode: focusNode,
        fillWidth: true,
        excludeSemantics: true,
        hoverOverlay: actions.tertiary.hoverWash(),
        pressedOverlay: actions.tertiary.pressedWash(),
        child: row,
      ),
    );
  }
}

/// The leading glyph of an option that has one.
///
/// **A sunken well in both states, and only the glyph changes.** The card's own
/// wash and edge already say which is chosen; a well that filled as well would
/// be a third fill on one card.
final class _GlyphWell extends StatelessWidget {
  const _GlyphWell({required this.icon, required this.selected});

  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    return ExcludeSemantics(
      child: Container(
        width: tokens.spacing.s48,
        height: tokens.spacing.s48,
        decoration: BoxDecoration(
          color: colors.surface.sunken,
          borderRadius: BorderRadius.circular(tokens.radius.md),
        ),
        child: Icon(
          icon,
          size: tokens.spacing.s24,
          color: selected
              ? colors.action.primary.container
              : colors.text.secondary,
        ),
      ),
    );
  }
}

final class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    // The unselected ring is `text.tertiary`, 5.43:1 on the card - above §9's
    // 3:1 for the boundary of a control.
    final ring = selected
        ? colors.action.primary.container
        : colors.text.tertiary;
    return Container(
      width: ChoiceCardGroup.radioSize,
      height: ChoiceCardGroup.radioSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: colors.action.focusRing.width),
      ),
      child: selected
          ? Container(
              width: ChoiceCardGroup.radioDotSize,
              height: ChoiceCardGroup.radioDotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.action.primary.container,
              ),
            )
          : null,
    );
  }
}

final class _Detail extends StatelessWidget {
  const _Detail({required this.runs, required this.icon});

  final List<ChoiceDetailRun> runs;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final style = tokens.typography.caption.copyWith(
      color: colors.text.tertiary,
    );
    final text = Text.rich(
      TextSpan(
        style: style,
        children: <InlineSpan>[
          for (final run in runs)
            TextSpan(
              text: run.text,
              style: run.emphasis
                  ? TextStyle(color: colors.text.secondary)
                  : null,
            ),
        ],
      ),
    );
    final glyph = icon;
    if (glyph == null) return text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(
            top: _lineHeight(style) / 2 - FilterChipBar.glyphSize / 2,
          ),
          child: Icon(
            glyph,
            size: FilterChipBar.glyphSize,
            color: colors.text.tertiary,
          ),
        ),
        SizedBox(width: tokens.spacing.s8),
        Expanded(child: text),
      ],
    );
  }

  static double _lineHeight(TextStyle style) =>
      (style.fontSize ?? 0) * (style.height ?? 1);
}

// ---------------------------------------------------------------------------
// AppToggleButton
// ---------------------------------------------------------------------------

/// One on/off switch in a row of them.
///
/// **An [AppButton] that remembers**, drawn from the same two tiers: on is
/// `action.primary`, off is `action.secondary`, at [AppButtonSize.lg]'s height
/// and `radius.md`. What it adds is the two things a tier change cannot say -
/// a check glyph when on, because a fill alone is hue alone (hard rule 4), and
/// `toggled` in the semantics tree, because a screen reader cannot see a fill.
///
/// **It fills the slot it is given and lays itself out to fit it.** With room
/// for the glyph beside the label it draws them in a row, the way an
/// [AppButton] with an icon does; in a slot too narrow for that - seven days
/// across a phone - the glyph goes above the label, so the label is never cut
/// to make room for the mark that says it is on.
///
/// **States:** off, on, hover, pressed and focus-visible from [PressSurface],
/// and disabled in both positions.
final class AppToggleButton extends StatelessWidget {
  const AppToggleButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onChanged,
    this.semanticLabel,
  });

  final String label;
  final bool selected;

  /// Called with the new value. Null disables the toggle.
  final ValueChanged<bool>? onChanged;

  /// What a screen reader announces instead of [label] - *Monday* for *Mon*.
  final String? semanticLabel;

  /// How wide a toggle needs to be to draw its glyph beside its label rather
  /// than above it, including [PressSurface]'s focus-ring gutter.
  static double measureRowWidth(
    AppTokens tokens,
    String label, {
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final ring = tokens.colors.action.focusRing;
    return tokens.spacing.s12 * 2 +
        FilterChipBar.glyphSize +
        tokens.spacing.s4 +
        measureTextWidth(
          label,
          tokens.typography.labelLarge,
          textScaler: textScaler,
        ) +
        (ring.width + ring.offset) * 2;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final actions = tokens.colors.action;
    final role = selected ? actions.primary : actions.secondary;
    final disabled = onChanged == null;
    final container = disabled ? actions.disabledContainer : role.container;
    final labelColor = disabled ? actions.disabledLabel : role.label;
    final borderColor = disabled
        ? actions.disabledBorder
        : (role.border ?? role.container);
    final radius = BorderRadius.circular(tokens.radius.md);
    final textScaler = MediaQuery.textScalerOf(context);

    Widget content(bool stacked) {
      final text = Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.clip,
        textAlign: TextAlign.center,
        style: tokens.typography.labelLarge.copyWith(color: labelColor),
      );
      if (!selected) return text;
      final glyph = Icon(
        Icons.check,
        size: FilterChipBar.glyphSize,
        color: labelColor,
      );
      return stacked
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[glyph, text],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                glyph,
                SizedBox(width: tokens.spacing.s4),
                Flexible(child: text),
              ],
            );
    }

    // The node is the outermost widget, so a key on this toggle addresses the
    // node that carries `toggled` rather than a layout box above it.
    return Semantics(
      container: true,
      button: true,
      toggled: selected,
      enabled: !disabled,
      label: semanticLabel ?? label,
      onTap: disabled ? null : () => onChanged!(!selected),
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth <
              measureRowWidth(tokens, label, textScaler: textScaler);
          return PressSurface(
            borderRadius: radius,
            onPressed: disabled ? null : () => onChanged!(!selected),
            fillWidth: true,
            excludeSemantics: true,
            hoverOverlay: role.hoverWash(),
            pressedOverlay: role.pressedWash(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: container,
                borderRadius: radius,
                border: Border.all(color: borderColor),
              ),
              child: SizedBox(
                height: AppButtonSize.lg.height,
                child: Center(child: content(stacked)),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AppSwitchRow
// ---------------------------------------------------------------------------

/// One setting that is either on or off, said as a row: what it is, what it
/// is set to, and a switch.
///
/// **Never the switch's hue alone**, because a thumb's side and a track's fill
/// are position and hue, and hard rule 4 says status is never conveyed by
/// colour alone. With [onText] and [offText] the words say it, as the line
/// under the label. Without them - a row that is its label alone, at the
/// developer's direction on 2026-10-03 - the thumb carries a check or a cross,
/// so the state is a glyph as well as a colour. The row is one tap target of
/// at least `density.minimumTapTarget`, so the whole row toggles, not only the
/// switch.
///
/// **States:** on, off, hover, pressed and focus-visible from Material's own
/// switch and list tile, and disabled in both positions when [onChanged] is
/// null.
///
/// **[flat] draws it as one of [ChoiceCardGroup.flat]'s rows**, so a switch
/// and the choices under it read as one list. Hover, pressed and focus-visible
/// are then the row's, from [PressSurface], and the switch itself is only the
/// picture of the state.
final class AppSwitchRow extends StatelessWidget {
  const AppSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onText,
    this.offText,
    this.icon,
    this.flat = false,
  }) : assert(
         (onText == null) == (offText == null),
         'Both words or neither: one alone says only half the state.',
       );

  final String label;
  final bool value;

  /// Called with the new value. Null disables the row.
  final ValueChanged<bool>? onChanged;

  /// What the setting means when on, and when off, in a short sentence. Both
  /// or neither; without them the thumb carries the state as a glyph.
  final String? onText;
  final String? offText;

  final IconData? icon;

  /// A flat row on the page, beside [ChoiceCardGroup.flat]'s. See the class
  /// note.
  ///
  /// **On is a check in the thumb, and off is the bare thumb at the start of
  /// the track**, as the WhatsApp receipts design draws it on 2026-10-03: the
  /// check and the thumb's side and size say it, so it is never the track's hue
  /// alone, and a cross on the off thumb was one mark more than it needed.
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final actions = tokens.colors.action;
    final disabled = onChanged == null;
    if (flat) return _flat(tokens);
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      minTileHeight: tokens.density.minimumTapTarget.height,
      secondary: icon == null
          ? null
          : Icon(
              icon,
              size: AppButton.iconSize,
              color: disabled
                  ? actions.disabledLabel
                  : tokens.colors.text.secondary,
            ),
      title: Text(
        label,
        style: tokens.typography.titleMedium.copyWith(
          color: disabled ? actions.disabledLabel : tokens.colors.text.primary,
        ),
      ),
      subtitle: switch (value ? onText : offText) {
        final words? => Text(
          words,
          style: tokens.density
              .body(tokens.typography)
              .copyWith(color: tokens.colors.text.secondary),
        ),
        null => null,
      },
      // Each glyph in the colour of the track beside it, so it reads against
      // the thumb it sits on in both positions.
      thumbIcon: onText == null
          ? WidgetStateProperty.resolveWith<Icon?>(
              (states) => states.contains(WidgetState.selected)
                  ? Icon(Icons.check, color: actions.primary.container)
                  : Icon(Icons.close, color: tokens.colors.surface.raised),
            )
          : null,
      activeThumbColor: actions.primary.label,
      activeTrackColor: actions.primary.container,
      inactiveThumbColor: tokens.colors.text.secondary,
      inactiveTrackColor: tokens.colors.surface.raised,
      trackOutlineColor: WidgetStatePropertyAll<Color>(
        tokens.colors.surface.borderStrong,
      ),
    );
  }

  Widget _flat(AppTokens tokens) {
    final colors = tokens.colors;
    final actions = colors.action;
    final onChanged = this.onChanged;
    final toggle = onChanged == null ? null : () => onChanged(!value);
    final disabled = toggle == null;
    final words = value ? onText : offText;

    // Material's switch, drawn and never touched: the row takes the tap, the
    // keys and the focus, so a pointer gets one wash and a keyboard one stop.
    // It keeps a handler so it draws enabled, and ignores the pointer so the
    // handler is never reached by any way but the row's.
    final picture = IgnorePointer(
      child: ExcludeFocus(
        child: Switch(
          value: value,
          onChanged: disabled ? null : (_) {},
          // The row's own inset is the margin, so the track ends where a
          // radio would.
          padding: EdgeInsets.zero,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          thumbColor: WidgetStateProperty.resolveWith<Color>(
            (states) => states.contains(WidgetState.disabled)
                ? actions.disabledLabel
                : states.contains(WidgetState.selected)
                ? actions.primary.label
                : colors.text.tertiary,
          ),
          trackColor: WidgetStateProperty.resolveWith<Color>(
            (states) => states.contains(WidgetState.disabled)
                ? actions.disabledContainer
                : states.contains(WidgetState.selected)
                ? actions.primary.container
                : actions.secondary.container,
          ),
          // The off edge is `text.tertiary`, the radio ring's colour: the
          // boundary of a control, at 3:1 or better on the page.
          trackOutlineColor: WidgetStateProperty.resolveWith<Color>(
            (states) => states.contains(WidgetState.disabled)
                ? actions.disabledBorder
                : states.contains(WidgetState.selected)
                ? actions.primary.container
                : colors.text.tertiary,
          ),
          thumbIcon: WidgetStateProperty.resolveWith<Icon?>(
            (states) => states.contains(WidgetState.selected)
                ? Icon(
                    Icons.check,
                    color: states.contains(WidgetState.disabled)
                        ? actions.disabledContainer
                        : actions.primary.container,
                  )
                : null,
          ),
          overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        ),
      ),
    );

    final row = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: tokens.density.minimumTapTarget.height,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.s8,
          vertical: tokens.spacing.s4,
        ),
        child: Row(
          children: <Widget>[
            if (icon case final glyph?) ...<Widget>[
              Icon(
                glyph,
                size: tokens.spacing.s24,
                color: disabled ? actions.disabledLabel : colors.text.tertiary,
              ),
              SizedBox(width: tokens.spacing.s16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    label,
                    style: tokens.typography.bodyLarge.copyWith(
                      color: disabled
                          ? actions.disabledLabel
                          : colors.text.primary,
                    ),
                  ),
                  if (words != null)
                    Text(
                      words,
                      style: tokens.typography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: tokens.spacing.s16),
            picture,
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      toggled: value,
      enabled: !disabled,
      label: label,
      value: words,
      onTap: toggle,
      excludeSemantics: true,
      child: PressSurface(
        borderRadius: BorderRadius.circular(tokens.radius.md),
        onPressed: toggle,
        fillWidth: true,
        excludeSemantics: true,
        hoverOverlay: actions.tertiary.hoverWash(),
        pressedOverlay: actions.tertiary.pressedWash(),
        child: row,
      ),
    );
  }
}
