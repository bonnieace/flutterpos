/// `RecordList`: `design.md` §11 step **6, second half** - §4.3's responsive
/// contract.
///
/// **This is not a rename of `lib/ui/records.dart`, and the difference is the
/// whole step.** `TenantRecordCard` takes a title, a subtitle, chips, actions
/// and details; `TenantRecordTable` takes columns and cells; **there is no
/// shared model between them**, and the one screen that chooses calls two
/// separate builders that present different information. §4.3 requires the
/// opposite: one component that *declares what it becomes* at each band, so a
/// screen states its records once and gets the right form for free.
///
/// So the model comes first and the renderings are three ways of laying it out.
/// §5.2's five rows are the model, exactly:
///
/// - **Identity** - `title.md`, `text.primary`, never truncated below two lines.
/// - **Attributes** - `body.md` / `text.secondary`, key-value.
/// - **Status** - a [StatusBadge], leading position.
/// - **Provenance** - `caption` / `text.tertiary`. "Recorded {ts} by {actor}".
/// - **Actions** - a [RecordActionSet]. On compact, an overflow menu; never
///   bare text links.
///
/// **Two readings of that specification are decisions rather than lookups**, and
/// both are now written into §5.2 as well so the code and the document agree.
/// *"Leading position"* is read as first **in the record**: the badge sits above
/// the identity on a card and in the first column of a table, because it is what
/// a person scans a list for. *"Never truncated below two lines"* is read as a
/// floor rather than a ban: an identity gets two lines before it ellipsises,
/// where every other line on a record gets one.
///
/// **The caller decides what the narrow form loses, and nothing else.**
/// `DESIGN-AUDIT.md` §6 decision 2, taken 2026-08-11 and applied to `design.md`
/// with this chunk. §4.3 said outright that a screen cannot opt out; the audit
/// found `records.dart` arguing the opposite in its own comments - *"the caller
/// knows which of its columns survive the loss"* - and the concession went to
/// the caller, because a table has room for six columns and a stacked card does
/// not. Here that is one flag, [RecordAttribute.inNarrowForm], so the loss is
/// visible in the call site rather than in a layout rule nobody can find. **The
/// form itself is still not the caller's**: there is no argument for a screen
/// drawing a table on a phone, and none for dropping an identity, a status, a
/// provenance line or an action at any width.
///
/// **It scrolls nothing.** Every screen in step 6's list already sits inside its
/// own `ListView` under an `AppScaffold`, and a scrollable inside a scrollable
/// is either an assertion or a scroll trap. This lays records out and the page
/// scrolls them.
///
/// **It resolves no density**, for the same reason `AppScaffold` does not: §3
/// gives `density.compact` to exactly the screens this component covers - and
/// only "at >=1024", and only on a pointer device, which nothing in Flutter can
/// honestly answer. Every rendering here is therefore comfortable, which is the
/// stricter setting on every dimension §9 measures. `PLAN.md` carries it as a
/// question for the product owner rather than a gap.
///
/// **One slot §5.2 does not name is deliberately absent**: somewhere to put a
/// form a record opens. `TenantRecordCard` and `TenantRecordTable` both have one
/// and the staff directory and the catalog both use it, so the sweep that
/// migrates them is where it gets added, with the screen that needs it and a
/// reason. Adding it here would be a slot with no consumer and no row in the
/// specification.
library;

import 'package:flutter/material.dart';

import 'buttons.dart';
import 'status.dart';
import 'tokens.dart';

/// One of §4.3's three renderings of a record list.
///
/// **A property of the screen's width, never of a call site.** §4.3 states the
/// row as what the component *becomes*, so the resolution is
/// [RecordList.formFor] and there is no argument that overrides it.
enum RecordForm {
  /// `compact`, below 768. One card per record, stacked.
  stackedCards,

  /// `medium`, 768 to 1023. The same card, two to a row.
  twoColumnCards,

  /// `expanded`, 1024 and above. A data table.
  table,
}

/// One key-value fact about a record. §5.2's "Attributes" row.
@immutable
final class RecordAttribute {
  const RecordAttribute({
    required this.label,
    required this.value,
    this.valueKey,
    this.inNarrowForm = true,
    this.flex = 1,
  });

  /// The key. Also the column header this attribute becomes in
  /// [RecordForm.table], which is why it is the caller's own word rather than
  /// something this file derives: §8's copy rules reach a column header.
  final String label;

  /// The value, already formatted by the caller. This component decides nothing
  /// about what a record may say.
  final String value;

  /// Key on the value's own `Text`, for a caller whose tests read the string
  /// rather than the row around it.
  final Key? valueKey;

  /// **Whether this attribute survives a card.** `DESIGN-AUDIT.md` §6 decision
  /// 2, and the only opt-out §4.3 concedes.
  ///
  /// True keeps it on every rendering. False draws it in [RecordForm.table]
  /// only, where there is a column for it - which is the honest shape of the
  /// concession, because the thing a narrow form is short of is *width*, not
  /// bands.
  final bool inNarrowForm;

  /// This attribute's share of a table row. Ignored by both card forms, which
  /// stack.
  final int flex;
}

/// A record's standing, as one of §2.1's five statuses. §5.2's "Status" row.
///
/// **Optional, and an absent status is not a neutral one.** Each of the five
/// means exactly one thing, and "this record exists" is not among them; a list
/// where every row wears a badge is a list with no signal in it. A record that
/// has nothing to say about its own standing says nothing.
@immutable
final class RecordStatus {
  const RecordStatus({
    required this.status,
    required this.label,
    this.icon,
    this.semanticLabel,
    this.badgeKey,
  });

  final AppStatus status;

  /// The word. Sentence case, §8.
  final String label;

  /// Overrides [AppStatus.defaultIcon]. See [StatusBadge.icon].
  final IconData? icon;

  /// See [StatusBadge.semanticLabel].
  final String? semanticLabel;

  final Key? badgeKey;

  StatusBadge _badge() => StatusBadge(
    key: badgeKey,
    status: status,
    label: label,
    icon: icon,
    semanticLabel: semanticLabel,
  );
}

/// One thing a person can do to a record. §5.2's "Actions" row.
@immutable
final class RecordAction {
  const RecordAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.destructive = false,
    this.actionKey,
  });

  /// Sentence case, a verb phrase naming the effect. §8.
  final String label;

  /// Null disables it, exactly as on [AppButton].
  final VoidCallback? onPressed;

  final IconData? icon;

  /// **Removes or reverses something.** Takes §2.1's destructive tier instead of
  /// looking like its neighbour, which is half of what §5.2 says the catalog's
  /// `Correct` / `Retire` pair gets wrong. The other half is the tap target, and
  /// that is [RecordActionSet]'s.
  final bool destructive;

  final Key? actionKey;
}

/// One record, as the five rows of §5.2 and nothing else.
@immutable
final class RecordItem {
  const RecordItem({
    required this.id,
    required this.title,
    this.recordKey,
    this.titleKey,
    this.subtitle,
    this.subtitleKey,
    this.status,
    this.attributes = const <RecordAttribute>[],
    this.provenance,
    this.provenanceKey,
    this.actions = const <RecordAction>[],
  });

  /// What makes this record itself - a document ID, a UID, a SKU.
  ///
  /// Never displayed. It identifies the record to the framework and to an
  /// assertion message, so a list that is rebuilt keeps each record's state on
  /// the record rather than on its position.
  final String id;

  /// The widget key of whichever form this record is drawn in.
  ///
  /// **A caller's key rather than one derived from [id], so a test written
  /// against a screen keeps working across the form change.** A record is a
  /// card at one width and a table row at another; a test that can only address
  /// the card is a test of the phone layout. Null falls back to a key built
  /// from [id].
  final Key? recordKey;

  /// §5.2's identity. `title.md`, `text.primary`, two lines before it
  /// ellipsises.
  final String title;

  final Key? titleKey;

  /// A second identifying line - an address, a code, a category.
  final String? subtitle;

  final Key? subtitleKey;

  final RecordStatus? status;

  /// In the order they should be read, which in [RecordForm.table] is the
  /// column order.
  ///
  /// **A record need not carry every attribute the list has a column for.** An
  /// audit event either changed a status or did not; a product either has a
  /// recorded cost or has none. The columns are a property of the *list* - see
  /// [RecordList.columnsOf] - and a record that is silent about one gets an
  /// empty cell, which is what a table is for. What is a defect, and is
  /// asserted, is one record carrying the same label twice: there is no cell for
  /// the second one to go in.
  final List<RecordAttribute> attributes;

  /// §5.2's provenance line. "Recorded {ts} by {actor}", in the caller's words.
  final String? provenance;

  final Key? provenanceKey;

  final List<RecordAction> actions;

  /// The attributes a narrow rendering keeps. See
  /// [RecordAttribute.inNarrowForm].
  List<RecordAttribute> get _narrowAttributes =>
      attributes.where((attribute) => attribute.inNarrowForm).toList();
}

/// A record's actions, laid out per §4.3's `ActionSet` row.
///
/// | | compact | medium | expanded |
/// | --- | --- | --- | --- |
/// | `ActionSet` (>3) | overflow menu | overflow after 3 | all inline |
///
/// **The `(>3)` in that row's own name is load-bearing and is honoured rather
/// than ignored.** Three or fewer actions are inline at every band; the row
/// describes what happens past three. It is also the only reading that lets
/// §5.2's "on compact, an overflow menu" and §4.3's "overflow after 3" both be
/// true, because otherwise a record with a single action would hide it behind a
/// menu on a phone.
///
/// **Every action is 48 high in every form**, which is the half of §5.2's
/// catalog complaint that is a §9 pass/fail: *"20px targets on a touch
/// surface"*. [AppButtonSize.sm] exists for a pointer at compact density, this
/// component resolves no density, and a 1024-wide surface may well be a
/// touchscreen till - so the size that is right whatever the hardware is the
/// only one used here.
///
/// **The menu is Material's.** §5.1's inventory has no menu component at all -
/// `AppSheet` is a bottom sheet and is unbuilt - so `PopupMenuButton` is used
/// and coloured from the token layer, rather than a menu being invented inside
/// a list component.
final class RecordActionSet extends StatelessWidget {
  const RecordActionSet({
    super.key,
    required this.actions,
    required this.form,
    this.alignment = WrapAlignment.start,
  });

  final List<RecordAction> actions;

  /// Which of §4.3's renderings this set is being laid into. Passed in rather
  /// than resolved here, so one record cannot disagree with the list it is in.
  final RecordForm form;

  final WrapAlignment alignment;

  /// §4.3's threshold. Past this many actions the row's overflow rule applies.
  static const int inlineLimit = 3;

  /// The overflow control's glyph, and the glyph on a menu item.
  ///
  /// §5.2 names exactly two icon sizes anywhere - `AppButton`'s leading icon at
  /// 18 and `StatusBadge`'s at 14 - and names none for a menu. 18 is applied as
  /// the nearest named row rather than a third size being invented, which is the
  /// same borrowing `Callout` and `Disclosure` recorded in step 4 and the same
  /// entry it is carried under in `PLAN.md`.
  static const double glyphSize = 18;

  /// How many of [actions] are drawn as buttons in [form].
  static int inlineCountFor(RecordForm form, int actionCount) {
    if (actionCount <= inlineLimit) return actionCount;
    return switch (form) {
      RecordForm.stackedCards => 0,
      RecordForm.twoColumnCards => inlineLimit,
      RecordForm.table => actionCount,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final tokens = AppTokens.componentOf(context);
    final inline = inlineCountFor(form, actions.length);
    final overflow = actions.sublist(inline);
    return Wrap(
      alignment: alignment,
      spacing: tokens.spacing.s8,
      runSpacing: tokens.spacing.s8,
      children: <Widget>[
        for (final action in actions.take(inline))
          AppButton(
            key: action.actionKey,
            label: action.label,
            icon: action.icon,
            onPressed: action.onPressed,
            tier: action.destructive
                ? AppButtonTier.destructive
                : AppButtonTier.secondary,
          ),
        if (overflow.isNotEmpty) _RecordOverflowMenu(actions: overflow),
      ],
    );
  }
}

final class _RecordOverflowMenu extends StatelessWidget {
  const _RecordOverflowMenu({required this.actions});

  final List<RecordAction> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return PopupMenuButton<RecordAction>(
      tooltip: 'More actions',
      icon: Icon(Icons.more_vert, color: tokens.colors.text.secondary),
      // §9's target, and the same figure `AppButton` keeps whatever it paints.
      iconSize: RecordActionSet.glyphSize,
      constraints: BoxConstraints(minHeight: tokens.density.minimumTapTarget.height),
      color: tokens.colors.surface.overlay,
      onSelected: (action) => action.onPressed?.call(),
      itemBuilder: (context) => <PopupMenuEntry<RecordAction>>[
        for (final action in actions)
          PopupMenuItem<RecordAction>(
            key: action.actionKey,
            value: action,
            enabled: action.onPressed != null,
            height: tokens.density.minimumTapTarget.height,
            child: Row(
              children: <Widget>[
                if (action.icon case final glyph?) ...<Widget>[
                  Icon(
                    glyph,
                    size: RecordActionSet.glyphSize,
                    color: _labelColor(tokens, action),
                  ),
                  SizedBox(width: tokens.spacing.s12),
                ],
                Flexible(
                  child: Text(
                    action.label,
                    style: tokens.typography.labelLarge.copyWith(
                      color: _labelColor(tokens, action),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// The same three-way choice `AppButton` makes, so an action reads the same
  /// whether it landed inline or in the menu.
  Color _labelColor(AppTokens tokens, RecordAction action) {
    if (action.onPressed == null) return tokens.colors.action.disabledLabel;
    return action.destructive
        ? tokens.colors.action.destructive.label
        : tokens.colors.text.primary;
  }
}

/// A list of records, in whichever of §4.3's three forms the screen is wide
/// enough for.
final class RecordList extends StatelessWidget {
  const RecordList({
    super.key,
    required this.identityLabel,
    required this.items,
    this.empty,
  });

  /// What one record's identity *is*, in the caller's word - "Event", "Member",
  /// "Product".
  ///
  /// **Required, because a table needs a header for its first column and this
  /// file cannot supply one.** "Identity" is a specification word, not a
  /// shopkeeper's. It is unused by both card forms, which is not a reason to
  /// make it optional: a list that gains a table at 1024 with a blank column
  /// header is worse than one that had to say what it lists.
  final String identityLabel;

  final List<RecordItem> items;

  /// What stands in for the rows when there are none.
  ///
  /// **A slot, not an `EmptyState`.** §5.1 has that as its own component at
  /// priority 2 and it does not exist; inventing it inside a list component is
  /// how a second one gets built later. This component owns where the words go
  /// and the caller owns the words, the same split [Callout.action] and
  /// `PageHeader.primaryAction` already use. Null draws nothing at all.
  final Widget? empty;

  /// Which of §4.3's forms a [screenWidth] gets.
  ///
  /// **The screen's width, not this widget's own box.** A `RecordList` is always
  /// inside a padded, capped column - §4.2 puts 1200 and two lots of `space.20`
  /// between the window and these rows - so resolving §4.1's bands against a
  /// `LayoutBuilder` here would put the card-to-table switch at 1064 of screen,
  /// a fourth boundary produced by arithmetic that nobody declared. This is the
  /// rule step 6a made load-bearing and §4.3 is where it earns its keep.
  ///
  /// Exposed so a test can ask the same question the widget asks.
  static RecordForm formFor(double screenWidth) =>
      switch (AppLayout.contract.breakpointOf(screenWidth)) {
        AppBreakpoint.compact => RecordForm.stackedCards,
        AppBreakpoint.medium => RecordForm.twoColumnCards,
        AppBreakpoint.expanded => RecordForm.table,
      };

  /// The attribute columns [RecordForm.table] draws, in the order it draws
  /// them.
  ///
  /// **Every label any record carries, first-appearance order.** Columns belong
  /// to the list rather than to its first row: taking the first record's
  /// attributes would let one unusual record at the top decide what the other
  /// nineteen are allowed to say, and would drop a column outright whenever the
  /// first record happened to be the silent one.
  ///
  /// The full row of §4.3's table is status, identity, these, then actions.
  /// **Status and actions appear only where some record has them**, so a
  /// read-only list carries no empty trailing column and a list where nothing
  /// has a standing carries no empty leading one.
  ///
  /// Exposed so a caller's test can assert the shape of its own table without
  /// counting pixels.
  static List<RecordAttribute> columnsOf(List<RecordItem> items) {
    final columns = <String, RecordAttribute>{};
    for (final item in items) {
      for (final attribute in item.attributes) {
        columns.putIfAbsent(attribute.label, () => attribute);
      }
    }
    return columns.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return empty ?? const SizedBox.shrink();
    final form = formFor(MediaQuery.sizeOf(context).width);
    return switch (form) {
      RecordForm.stackedCards => _StackedCards(items: items, form: form),
      RecordForm.twoColumnCards => _TwoColumnCards(items: items, form: form),
      RecordForm.table => _RecordTable(
        identityLabel: identityLabel,
        columns: columnsOf(items),
        items: items,
      ),
    };
  }
}

final class _StackedCards extends StatelessWidget {
  const _StackedCards({required this.items, required this.form});

  final List<RecordItem> items;
  final RecordForm form;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final (index, item) in items.indexed) ...<Widget>[
          if (index > 0) SizedBox(height: tokens.spacing.s12),
          _RecordCard(item: item, form: form),
        ],
      ],
    );
  }
}

/// The same card, two to a row. §4.3's `medium` cell.
///
/// **Records alternate left, right, left**, rather than the first half going
/// down one column and the second half down the other. A list is read in order,
/// and a person scanning a page for the third record should find it where the
/// third record goes.
final class _TwoColumnCards extends StatelessWidget {
  const _TwoColumnCards({required this.items, required this.form});

  final List<RecordItem> items;
  final RecordForm form;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final gap = tokens.spacing.s12;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var row = 0; row * 2 < items.length; row++) ...<Widget>[
          if (row > 0) SizedBox(height: gap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: _RecordCard(item: items[row * 2], form: form)),
                SizedBox(width: gap),
                Expanded(
                  child: row * 2 + 1 < items.length
                      ? _RecordCard(item: items[row * 2 + 1], form: form)
                      // An odd count leaves the last row half empty rather than
                      // letting one card stretch to twice its neighbours'
                      // width, which would read as a record that matters more.
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One record as a card: §4.3's `compact` and `medium` cells.
final class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.item, required this.form});

  final RecordItem item;
  final RecordForm form;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final body = tokens.density.body(tokens.typography);
    final attributes = item._narrowAttributes;
    return DecoratedBox(
      key: item.recordKey ?? ValueKey<String>('record-${item.id}'),
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        border: Border.all(color: tokens.colors.surface.borderSubtle),
        // §2.3's row for "cards, rows, sheets".
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (item.status case final standing?) ...<Widget>[
              Align(alignment: Alignment.centerLeft, child: standing._badge()),
              SizedBox(height: tokens.spacing.s8),
            ],
            Text(
              item.title,
              key: item.titleKey,
              // §5.2's "never truncated below two lines", read as a floor.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tokens.typography.titleMedium.copyWith(
                color: tokens.colors.text.primary,
              ),
            ),
            if (item.subtitle case final line?) ...<Widget>[
              SizedBox(height: tokens.spacing.s4),
              Text(
                line,
                key: item.subtitleKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: body.copyWith(color: tokens.colors.text.secondary),
              ),
            ],
            if (attributes.isNotEmpty) ...<Widget>[
              SizedBox(height: tokens.spacing.s12),
              for (final (index, attribute) in attributes.indexed) ...<Widget>[
                if (index > 0) SizedBox(height: tokens.spacing.s4),
                _CardAttribute(attribute: attribute),
              ],
            ],
            if (item.provenance case final line?) ...<Widget>[
              SizedBox(height: tokens.spacing.s12),
              Text(
                line,
                key: item.provenanceKey,
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
            ],
            if (item.actions.isNotEmpty) ...<Widget>[
              SizedBox(height: tokens.spacing.s12),
              RecordActionSet(actions: item.actions, form: form),
            ],
          ],
        ),
      ),
    );
  }
}

/// One attribute on a card: §5.2's "key-value", laid out as a line.
final class _CardAttribute extends StatelessWidget {
  const _CardAttribute({required this.attribute});

  final RecordAttribute attribute;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final body = tokens.density.body(tokens.typography);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          attribute.label,
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
        SizedBox(width: tokens.spacing.s8),
        Expanded(
          child: Text(
            attribute.value,
            key: attribute.valueKey,
            textAlign: TextAlign.end,
            style: body.copyWith(color: tokens.colors.text.secondary),
          ),
        ),
      ],
    );
  }
}

/// §4.3's `expanded` cell: a data table.
///
/// **The header is sentence case in `label.md`.** §2.2 gives that role "chips,
/// tabs, table headers" in as many words, and permits uppercase on
/// `label.eyebrow` alone - which is the conformance item `DESIGN-AUDIT.md` §4.9
/// raises against `TenantRecordTable`'s uppercased headers, closed here for the
/// component that replaces it.
final class _RecordTable extends StatelessWidget {
  const _RecordTable({
    required this.identityLabel,
    required this.columns,
    required this.items,
  });

  final String identityLabel;
  final List<RecordAttribute> columns;
  final List<RecordItem> items;

  /// The identity column carries a title, a subtitle and a provenance line, so
  /// it is given three times an attribute's share rather than an equal one.
  static const int _identityFlex = 3;

  /// The actions column takes the same share as the identity, and the reason is
  /// arithmetic rather than symmetry.
  ///
  /// An action is a 48-high pill with a verb phrase on it - §5.2's own
  /// requirement - and two of them side by side is the ordinary case. At any
  /// smaller share the set wraps to a second line, which does not shorten the
  /// column: it makes **every row in the table** as tall as its actions instead
  /// of as tall as its identity. Measured at 1200, which is §4.2's maximum for
  /// this surface and therefore the widest a table ever gets.
  static const int _actionsFlex = 3;

  /// The status column takes twice an attribute's share.
  ///
  /// A badge is an icon, a gap and a word inside a bordered container, so it is
  /// wider than the value of an ordinary attribute at the same word length -
  /// and the words §2.1's statuses attract are phrases: "Out of stock",
  /// "Awaiting verification". At an equal share those ellipsise, and a status
  /// abbreviated to "Out of st…" fails the one thing §5.2 says a badge is for.
  static const int _statusFlex = 2;

  bool get _hasStatus => items.any((item) => item.status != null);
  bool get _hasActions => items.any((item) => item.actions.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final headerStyle = tokens.typography.labelMedium.copyWith(
      color: tokens.colors.text.secondary,
    );
    final inset = EdgeInsets.symmetric(
      horizontal: tokens.spacing.s16,
      vertical: tokens.spacing.s12,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        border: Border.all(color: tokens.colors.surface.borderSubtle),
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: inset,
            child: Row(
              children: <Widget>[
                if (_hasStatus)
                  Expanded(
                    flex: _statusFlex,
                    child: Text('Status', style: headerStyle),
                  ),
                Expanded(
                  flex: _identityFlex,
                  child: Text(identityLabel, style: headerStyle),
                ),
                for (final column in columns)
                  Expanded(
                    flex: column.flex,
                    child: Text(column.label, style: headerStyle),
                  ),
                if (_hasActions)
                  const Expanded(
                    flex: _RecordTable._actionsFlex,
                    child: SizedBox.shrink(),
                  ),
              ],
            ),
          ),
          for (final item in items)
            _RecordTableRow(
              item: item,
              columns: columns,
              identityFlex: _identityFlex,
              hasStatus: _hasStatus,
              hasActions: _hasActions,
              inset: inset,
            ),
        ],
      ),
    );
  }
}

final class _RecordTableRow extends StatelessWidget {
  const _RecordTableRow({
    required this.item,
    required this.columns,
    required this.identityFlex,
    required this.hasStatus,
    required this.hasActions,
    required this.inset,
  });

  final RecordItem item;
  final List<RecordAttribute> columns;
  final int identityFlex;
  final bool hasStatus;
  final bool hasActions;
  final EdgeInsets inset;

  @override
  Widget build(BuildContext context) {
    final cells = <String, RecordAttribute>{};
    for (final attribute in item.attributes) {
      assert(
        !cells.containsKey(attribute.label),
        'Record "${item.id}" carries the attribute "${attribute.label}" twice. '
        'A table has one column per label, so there is no cell for the second '
        'one to go in, and a row that quietly drops it would be a fact missing '
        'from a screen nobody could see was missing it.',
      );
      cells[attribute.label] = attribute;
    }
    final tokens = AppTokens.componentOf(context);
    final body = tokens.density.body(tokens.typography);
    return Container(
      key: item.recordKey ?? ValueKey<String>('record-${item.id}'),
      constraints: BoxConstraints(minHeight: tokens.density.minimumRowHeight),
      padding: inset,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: tokens.colors.surface.borderSubtle),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (hasStatus)
            Expanded(
              flex: _RecordTable._statusFlex,
              child: Align(
                alignment: Alignment.centerLeft,
                child: item.status?._badge() ?? const SizedBox.shrink(),
              ),
            ),
          Expanded(
            flex: identityFlex,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  item.title,
                  key: item.titleKey,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.titleMedium.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                ),
                if (item.subtitle case final line?)
                  Text(
                    line,
                    key: item.subtitleKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: body.copyWith(color: tokens.colors.text.secondary),
                  ),
                // Provenance rides under the identity rather than taking a
                // column of its own: it is the same sentence on every row, and
                // a column of near-identical timestamps is width spent on
                // nothing.
                if (item.provenance case final line?)
                  Text(
                    line,
                    key: item.provenanceKey,
                    style: tokens.typography.caption.copyWith(
                      color: tokens.colors.text.tertiary,
                    ),
                  ),
              ],
            ),
          ),
          for (final column in columns)
            Expanded(
              flex: column.flex,
              // A record silent about this column gets an empty cell rather
              // than a dash: a dash is a value, and "no status change was
              // recorded" is not the same claim as "the status changed to
              // nothing".
              child: switch (cells[column.label]) {
                final attribute? => Text(
                  attribute.value,
                  key: attribute.valueKey,
                  style: body.copyWith(color: tokens.colors.text.secondary),
                ),
                null => const SizedBox.shrink(),
              },
            ),
          if (hasActions)
            Expanded(
              flex: _RecordTable._actionsFlex,
              child: RecordActionSet(
                actions: item.actions,
                form: RecordForm.table,
                alignment: WrapAlignment.end,
              ),
            ),
        ],
      ),
    );
  }
}
