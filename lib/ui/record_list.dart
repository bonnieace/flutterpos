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
/// **A table divides its row by measuring what the list holds**, which is
/// [RecordTableColumns] and is the one part of this component §4.3 does not
/// specify at all. It shipped in step 6b as three constants - identity 3, status
/// 2, actions 3, attributes 1 each - measured against a two-column activity log,
/// and the twelve screens that followed carry two to six columns. Every one of
/// the four observations `PLAN.md` collected about those constants was the same
/// defect from a different direction, and the answer is in that class rather
/// than in a retuned number.
///
/// **One slot is this component's own rather than §5.2's**: [RecordItem.details],
/// somewhere to put a form a record opens. It was deliberately absent in step
/// 6b, which shipped `RecordList` against a read-only list, and it arrived on
/// 2026-08-13 with the staff directory - the first consumer whose actions open
/// five inline forms and would otherwise have had nowhere to put them. It is
/// **not** a specification row and is not presented as one: §5.2 names five
/// rows and this is a sixth, added because a record's actions have to be able to
/// do something and the two widgets this component replaces both had one.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'buttons.dart';
import 'measure.dart';
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

  /// The most of a table row this attribute may claim, relative to its
  /// neighbours. Ignored by both card forms, which stack.
  ///
  /// **A ceiling rather than an allocation, since 2026-08-15.** The width a
  /// column actually gets is the smaller of this share and what its own longest
  /// value needs - see [RecordTableColumns] - so raising it lets a column of
  /// prose take more room and never forces a column of short values to keep it.
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
    this.details,
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

  /// A form one of this record's [actions] opened, laid out beneath the record.
  ///
  /// **The one slot here that §5.2 does not name.** It exists because a record's
  /// actions have to be able to do something: five of the staff directory's
  /// actions open a small form against that member, and both widgets this
  /// component replaces carried a `details` list for exactly that. §5.2 names
  /// five rows and this is a sixth, so it is described as the component's own
  /// addition rather than written into the document as a specification row.
  ///
  /// **It appears in every form, and that is a decision rather than an
  /// oversight.** A card has the whole card width for it and a table row draws
  /// it full width underneath, the way the superseded table did. Keeping it to
  /// the card forms would mean an action that opens a form on a phone does
  /// nothing visible on a desktop window - a behaviour that differs by band,
  /// which is the opposite of what §4.3 is for. The caller's concession is over
  /// *attributes*; nothing else a record carries drops out at a width.
  ///
  /// The caller owns what is in it, when it is shown, and how it is dismissed.
  /// This component owns only where it goes.
  final Widget? details;

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

  /// How wide this set wants to be, laid out on one line in [form].
  ///
  /// **The number that decides whether §4.3's "all inline" is true or only
  /// nominally true.** This set is a [Wrap], so a column narrower than this
  /// keeps every action visible and pays for it in *height*: four actions in a
  /// third of the width they ask for is three runs, and a run is 48 high, so one
  /// record makes its row three times as tall as its neighbours. That is what
  /// [RecordTableColumns] uses this for - the actions column asks for what it
  /// needs, instead of taking a share somebody chose.
  ///
  /// The overflow control is counted as one tap target where there is one. In
  /// [RecordForm.table] there never is, because that form draws every action
  /// inline.
  static double measureWidth(
    AppTokens tokens,
    List<RecordAction> actions,
    RecordForm form, {
    TextScaler textScaler = TextScaler.noScaling,
    TextStyle? ambient,
  }) {
    if (actions.isEmpty) return 0;
    final inline = inlineCountFor(form, actions.length);
    var width = 0.0;
    var pieces = 0;
    for (final action in actions.take(inline)) {
      width += AppButton.measureWidth(
        tokens,
        action.label,
        hasIcon: action.icon != null,
        textScaler: textScaler,
        ambient: ambient,
      );
      pieces++;
    }
    if (inline < actions.length) {
      width += tokens.density.minimumTapTarget.width;
      pieces++;
    }
    return width + tokens.spacing.s8 * (pieces - 1);
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
            // Beneath the actions rather than above them, because it is what
            // one of them opened: a form that appeared between a record and the
            // control that revealed it would push that control down the page as
            // it opened.
            if (item.details case final opened?) ...<Widget>[
              SizedBox(height: tokens.spacing.s12),
              opened,
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

/// How wide each column of one [RecordForm.table] is, measured from what the
/// list actually holds.
///
/// **This replaces three constants, and the reason is that a constant cannot
/// know how many columns it is sharing a row with.** Until 2026-08-15 the table
/// gave the identity three shares, the status two, the actions three and every
/// attribute one, and divided the row by the total. `PLAN.md` carried four
/// observations against that arithmetic, all four from real screens rather than
/// from review:
///
/// 1. A record with four actions wrapped its column to three runs and made that
///    row three times taller than its neighbours, while
/// 2. the status column - two shares whatever the badge says - read as a wide
///    left margin on a catalog where five of seven rows have no standing, and
/// 3. the identity, at three shares of a row with four attributes and an actions
///    column, kept about a quarter of 1200 and wrapped its provenance line on
///    every row, while
/// 4. no two cells had any gap between them at all, so at six columns a value
///    ended where the next began.
///
/// Every one of those is the same defect: **a share is a guess about content,
/// and the content is right there to be measured.** So each column states what
/// it needs - the widest badge, the widest action set, the longest value, the
/// header - and the row is divided by that instead.
///
/// **The old shares survive as ceilings rather than as answers**, which is what
/// makes this safe to apply to twelve screens at once. A column may claim up to
/// its share, never more, so no column can starve its neighbours by carrying one
/// long value; what changes is that a column claiming *less* than its share
/// releases the rest, and the release is offered to the columns that asked for
/// more than theirs. A table where every column wants at least its share lays
/// out exactly as it did before this class existed.
@immutable
final class RecordTableColumns {
  const RecordTableColumns._({
    required this.statusWidth,
    required this.identityWidth,
    required this.attributeWidths,
    required this.actionsWidth,
    required this.gap,
  });

  /// Null where no record in the list has a standing, which is the same
  /// condition under which the column is not drawn at all.
  final double? statusWidth;

  final double identityWidth;

  /// One per column of [RecordList.columnsOf], in that order.
  final List<double> attributeWidths;

  /// Null where no record in the list has an action.
  final double? actionsWidth;

  /// §2.3's `space.12`, between every pair of adjacent cells.
  ///
  /// **A table with no gutter is not a dense table, it is an unreadable one.**
  /// At six columns `web/30-shift-corrections` ran `A late sale arrived
  /// after|Corrected from expectation` together across the `Reason` / `Evidence`
  /// boundary, and `web/23-stock-movements` did the same in its header row. It
  /// costs the row five gaps at six columns, which is 60 of 1200, and it is the
  /// cheapest of the four repairs by a distance.
  final double gap;

  /// The header the status column draws, and the string its own width has to
  /// allow for.
  static const String statusHeader = 'Status';

  /// The identity's ceiling: three times an attribute's, because it carries a
  /// title, a subtitle and a provenance line where an attribute carries one
  /// value.
  ///
  /// **It is also where the table's leftover width goes.** Something has to
  /// absorb the difference when every column is satisfied, and the identity is
  /// §5.2's "never truncated below two lines" row - the one column where more
  /// room is always worth having and where a person's eye lands first.
  static const int identityShare = 3;

  /// The actions column's ceiling. An action is a 48-high pill with a verb
  /// phrase on it, and two side by side is the ordinary case.
  static const int actionsShare = 3;

  /// The status column's ceiling. A badge is an icon, a gap and a word inside a
  /// container, and §2.1's statuses attract phrases - "Awaiting verification" -
  /// rather than words.
  ///
  /// **It is a ceiling that is almost never reached**, which is the point of
  /// observation 2: the ceiling was right about the widest badge and wrong about
  /// every list whose badges are shorter than that.
  static const int statusShare = 2;

  /// Divides [available] - the row's width inside its own padding - between the
  /// columns this list needs.
  ///
  /// Exposed so a caller's test can assert the arithmetic without reading
  /// pixels off a rendering, the same reason [RecordList.columnsOf] and
  /// [RecordList.formFor] are.
  static RecordTableColumns resolve({
    required AppTokens tokens,
    required String identityLabel,
    required List<RecordAttribute> columns,
    required List<RecordItem> items,
    required double available,
    TextScaler textScaler = TextScaler.noScaling,
    TextStyle? ambient,
  }) {
    final hasStatus = items.any((item) => item.status != null);
    final hasActions = items.any((item) => item.actions.isNotEmpty);
    final headerStyle = tokens.typography.labelMedium;
    final body = tokens.density.body(tokens.typography);
    final demands = <double>[];
    final shares = <int>[];

    double text(String value, TextStyle style) => measureTextWidth(
      value,
      style,
      textScaler: textScaler,
      ambient: ambient,
    );

    if (hasStatus) {
      var demand = text(statusHeader, headerStyle);
      for (final item in items) {
        if (item.status case final standing?) {
          demand = math.max(
            demand,
            StatusBadge.measureWidth(
              tokens,
              standing.label,
              textScaler: textScaler,
              ambient: ambient,
            ),
          );
        }
      }
      demands.add(demand);
      shares.add(statusShare);
    }

    final identityIndex = demands.length;
    var identity = text(identityLabel, headerStyle);
    for (final item in items) {
      // **Halved, and it is the one place a demand is not the string's own
      // width.** §5.2 gives the identity two lines before it ellipsises, so a
      // title asking for the width it would need on one line would ask for
      // twice what it is entitled to and take it from a column with no second
      // line to fall back on. The subtitle and the provenance line are
      // `maxLines: 1` and ask for all of theirs.
      identity = math.max(
        identity,
        text(item.title, tokens.typography.titleMedium) / 2,
      );
      if (item.subtitle case final line?) {
        identity = math.max(identity, text(line, body));
      }
      if (item.provenance case final line?) {
        identity = math.max(
          identity,
          text(line, tokens.typography.caption),
        );
      }
    }
    demands.add(identity);
    shares.add(identityShare);

    for (final column in columns) {
      var demand = text(column.label, headerStyle);
      for (final item in items) {
        for (final attribute in item.attributes) {
          if (attribute.label != column.label) continue;
          demand = math.max(demand, text(attribute.value, body));
        }
      }
      demands.add(demand);
      shares.add(column.flex);
    }

    if (hasActions) {
      var demand = 0.0;
      for (final item in items) {
        demand = math.max(
          demand,
          RecordActionSet.measureWidth(
            tokens,
            item.actions,
            RecordForm.table,
            textScaler: textScaler,
            ambient: ambient,
          ),
        );
      }
      demands.add(demand);
      shares.add(actionsShare);
    }

    final gap = tokens.spacing.s12;
    final cells = available.isFinite
        ? math.max(0.0, available - gap * (demands.length - 1))
        : double.infinity;
    final widths = _allocate(
      demands: demands,
      shares: shares,
      cells: cells,
      identityIndex: identityIndex,
    );
    return RecordTableColumns._(
      statusWidth: hasStatus ? widths.first : null,
      identityWidth: widths[identityIndex],
      attributeWidths: widths.sublist(
        identityIndex + 1,
        identityIndex + 1 + columns.length,
      ),
      actionsWidth: hasActions ? widths.last : null,
      gap: gap,
    );
  }

  /// Every column takes the smaller of what it needs and what it may claim;
  /// what nobody claimed fills the shallowest remaining need first.
  ///
  /// **It cannot overflow.** Each width starts capped at a share of [cells] and
  /// the shares sum to [cells], so the first pass always fits; the two passes
  /// after it only ever hand out width that the first pass left over. That is
  /// the property that makes this safe on a 1024 window with six columns, where
  /// a demand-first allocation would have needed a cap somebody chose.
  ///
  /// **The pool is levelled rather than shared out in proportion, and that is a
  /// decision worth arguing with.** Proportion is the obvious rule and it is the
  /// wrong one here: a column that asked for 400 more and a column that asked
  /// for 6 more are not two claims of the same kind, because **satisfying the
  /// small one removes a wrapped line and part-satisfying the large one removes
  /// nothing**. A six-column ledger beside a four-action record is exactly that
  /// shape - the actions can never have what they want, and under proportion
  /// their unreachable claim takes the width that would have stopped `Source`
  /// wrapping `sale-000482` after nine characters. So the pool rises like water:
  /// every unmet column takes the same amount until it is satisfied and drops
  /// out, and the deepest need is served last with whatever is left.
  static List<double> _allocate({
    required List<double> demands,
    required List<int> shares,
    required double cells,
    required int identityIndex,
  }) {
    // An unbounded row - a table laid out inside something that measures its
    // intrinsic width - has nothing to divide, so every column takes what it
    // asked for.
    if (!cells.isFinite) return List<double>.of(demands);
    final totalShare = shares.fold<int>(0, (sum, share) => sum + share);
    final widths = <double>[];
    var taken = 0.0;
    for (var index = 0; index < demands.length; index++) {
      final ceiling = totalShare == 0
          ? cells
          : cells * shares[index] / totalShare;
      final width = math.min(demands[index], ceiling);
      widths.add(width);
      taken += width;
    }
    var pool = cells - taken;

    final wanting = <int>[
      for (var index = 0; index < widths.length; index++)
        if (demands[index] - widths[index] > 0) index,
    ]..sort((a, b) {
      final left = demands[a] - widths[a];
      final right = demands[b] - widths[b];
      return left.compareTo(right);
    });
    for (var served = 0; pool > 0 && served < wanting.length; served++) {
      final level = pool / (wanting.length - served);
      final index = wanting[served];
      final wanted = demands[index] - widths[index];
      final given = math.min(wanted, level);
      widths[index] += given;
      pool -= given;
    }

    if (pool > 0) widths[identityIndex] += pool;
    return widths;
  }

  /// One row's cells, each in its column's width, with [gap] between them.
  ///
  /// **The header and every row go through this**, which is what makes them line
  /// up: a table whose header computed its own widths would be a table with two
  /// answers to the same question.
  List<Widget> lay({
    Widget? status,
    required Widget identity,
    required List<Widget> attributes,
    Widget? actions,
  }) {
    assert(
      attributes.length == attributeWidths.length,
      'A row was laid out with ${attributes.length} attribute cells against '
      '${attributeWidths.length} columns.',
    );
    final cells = <Widget>[];
    void add(double width, Widget child) {
      if (cells.isNotEmpty) cells.add(SizedBox(width: gap));
      cells.add(SizedBox(width: width, child: child));
    }

    if (statusWidth case final width?) {
      add(width, status ?? const SizedBox.shrink());
    }
    add(identityWidth, identity);
    for (final (index, width) in attributeWidths.indexed) {
      add(width, attributes[index]);
    }
    if (actionsWidth case final width?) {
      add(width, actions ?? const SizedBox.shrink());
    }
    return cells;
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
    final textScaler = MediaQuery.textScalerOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        border: Border.all(color: tokens.colors.surface.borderSubtle),
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      // **The table's own box, not the screen's**, which is the distinction
      // `RecordList.formFor` is careful about in the other direction. A band is
      // resolved from the screen width, because §4.1 describes the surface a
      // person is looking at; a *column* is divided out of the width the table
      // was handed, because that is the width the columns have to fit in.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final widths = RecordTableColumns.resolve(
            tokens: tokens,
            identityLabel: identityLabel,
            columns: columns,
            items: items,
            available: constraints.hasBoundedWidth
                ? constraints.maxWidth - inset.horizontal
                : double.infinity,
            textScaler: textScaler,
            // The style every `Text` in this table will be merged onto. See
            // `measureTextWidth`: without it the measurement is short by
            // Material's own letter spacing, which is a quarter of a pixel per
            // character and enough to wrap the set of actions it just made room
            // for.
            ambient: DefaultTextStyle.of(context).style,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: inset,
                child: Row(
                  children: widths.lay(
                    status: Text(
                      RecordTableColumns.statusHeader,
                      style: headerStyle,
                    ),
                    identity: Text(identityLabel, style: headerStyle),
                    attributes: <Widget>[
                      for (final column in columns)
                        Text(column.label, style: headerStyle),
                    ],
                  ),
                ),
              ),
              for (final item in items)
                _RecordTableRow(
                  item: item,
                  columns: columns,
                  widths: widths,
                  inset: inset,
                ),
            ],
          );
        },
      ),
    );
  }
}

final class _RecordTableRow extends StatelessWidget {
  const _RecordTableRow({
    required this.item,
    required this.columns,
    required this.widths,
    required this.inset,
  });

  final RecordItem item;
  final List<RecordAttribute> columns;

  /// Resolved once for the whole table and handed to every row, which is what
  /// makes the columns line up.
  final RecordTableColumns widths;

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
    final cellRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: widths.lay(
        status: Align(
          alignment: Alignment.centerLeft,
          child: item.status?._badge() ?? const SizedBox.shrink(),
        ),
        identity: Column(
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
        attributes: <Widget>[
          for (final column in columns)
            // A record silent about this column gets an empty cell rather
            // than a dash: a dash is a value, and "no status change was
            // recorded" is not the same claim as "the status changed to
            // nothing".
            switch (cells[column.label]) {
              final attribute? => Text(
                attribute.value,
                key: attribute.valueKey,
                style: body.copyWith(color: tokens.colors.text.secondary),
              ),
              null => const SizedBox.shrink(),
            },
        ],
        actions: RecordActionSet(
          actions: item.actions,
          form: RecordForm.table,
          alignment: WrapAlignment.end,
        ),
      ),
    );
    return Container(
      key: item.recordKey ?? ValueKey<String>('record-${item.id}'),
      constraints: BoxConstraints(minHeight: tokens.density.minimumRowHeight),
      padding: inset,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: tokens.colors.surface.borderSubtle),
        ),
      ),
      // The row alone where there is nothing open, so a table of ordinary rows
      // lays out exactly as it did before this slot existed. A form takes the
      // whole width beneath the cells rather than a share of one of them: it is
      // a form, and a column of a table is not where a form goes.
      child: switch (item.details) {
        null => cellRow,
        final opened => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            cellRow,
            SizedBox(height: tokens.spacing.s12),
            opened,
          ],
        ),
      },
    );
  }
}
