/// Picking a span of days: one day, a run of days, or a whole month, from one
/// calendar.
///
/// **One control for three questions**, at the developer's direction on
/// 2026-09-23. Material ships a day picker and a range picker as two different
/// routes, and neither picks a month, so a screen that wanted all three had to
/// put a chooser in front of a chooser. Here the calendar answers all of them:
///
/// - **A tap picks that day.** It is already a complete answer - *Done* works.
/// - **A second tap makes it a range** from the first day to this one, in
///   whichever order they were tapped.
/// - **The month's name opens the months**, and a tap on one picks all of it.
///
/// [AppPeriodShortcut]s are the spans a person picks without reaching for the
/// calendar at all, and a caller supplies them because what counts as a sensible
/// span belongs to the records, not to the calendar.
///
/// **States:** each day is enabled, hover, pressed, focus-visible (through
/// [PressSurface]), selected, in-range, today and disabled - a day outside
/// [showAppPeriodPicker]'s bounds is drawn but cannot be picked. A selection is
/// never shown by colour alone: an end is a filled disc, the run between is a
/// band, today is a ring, and a screen reader is told each in words.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'buttons.dart';
import 'chips.dart';
import 'press.dart';
import 'sheet.dart';
import 'tokens.dart';

/// A named span offered above the calendar.
@immutable
final class AppPeriodShortcut {
  const AppPeriodShortcut({required this.label, required this.range, this.key});

  final String label;

  /// Whole days, start and end inclusive.
  final DateTimeRange range;

  final Key? key;
}

/// Opens the calendar on [initial] and answers what was picked, or null if the
/// person backed out.
///
/// The answer is whole local days, start and end inclusive; a single day comes
/// back with the two equal. [firstDate] and [lastDate] bound what may be picked,
/// and a month picked where it runs past either is cut to them - this month
/// picked on the 23rd is the 1st to the 23rd, not a period that reaches into
/// days nobody has traded yet.
///
/// [allowRange] false keeps every answer to one day, for records that can only
/// be read a day at a time. The month view is not offered there either, because
/// picking a month would be picking a range.
Future<DateTimeRange?> showAppPeriodPicker(
  BuildContext context, {
  required DateTimeRange initial,
  required DateTime firstDate,
  required DateTime lastDate,
  bool allowRange = true,
  DateTime? currentDate,
  List<AppPeriodShortcut> shortcuts = const <AppPeriodShortcut>[],
  String title = 'Choose a period',
}) => showAppSheet<DateTimeRange>(
  context,
  // All of it on screen at once: six weeks of 48dp days, the chips over them
  // and the footer under them are taller than the half detent.
  initialDetent: AppSheetDetent.full,
  builder: (sheetContext, controller) => AppPeriodPicker(
    initial: initial,
    firstDate: firstDate,
    lastDate: lastDate,
    currentDate: currentDate,
    allowRange: allowRange,
    shortcuts: shortcuts,
    title: title,
    controller: controller,
    onDone: (range) => Navigator.of(sheetContext).pop(range),
    onCancel: () => Navigator.of(sheetContext).pop(),
  ),
);

/// The sheet's contents. Public so the screenshot harness and a test can pump
/// it without a route.
final class AppPeriodPicker extends StatefulWidget {
  const AppPeriodPicker({
    super.key,
    required this.initial,
    required this.firstDate,
    required this.lastDate,
    required this.onDone,
    required this.onCancel,
    this.currentDate,
    this.allowRange = true,
    this.shortcuts = const <AppPeriodShortcut>[],
    this.title = 'Choose a period',
    this.controller,
  });

  final DateTimeRange initial;
  final DateTime firstDate;
  final DateTime lastDate;

  /// The day ringed as today. Defaults to [lastDate], which is what every
  /// caller so far passes as today - nothing after today can be reported on.
  final DateTime? currentDate;

  final bool allowRange;
  final List<AppPeriodShortcut> shortcuts;
  final String title;
  final ScrollController? controller;
  final ValueChanged<DateTimeRange> onDone;
  final VoidCallback onCancel;

  /// One day's square, and one month's height in the month view.
  ///
  /// **The touch target, not a size of its own.** §9 makes 48 x 48 pass/fail,
  /// and seven of them are 336 - which fits a 360 handset only inside a sheet's
  /// own width, and is the reason this is a sheet rather than a dialog.
  static double get cellExtent => AppButtonSize.lg.height;

  @override
  State<AppPeriodPicker> createState() => _AppPeriodPickerState();
}

final class _AppPeriodPickerState extends State<AppPeriodPicker> {
  late DateTime _start = _dayOf(widget.initial.start);
  late DateTime _end = _dayOf(widget.initial.end);

  /// A day has been tapped and the next tap makes a range from it.
  bool _awaitingEnd = false;

  /// The month on screen, as its first day.
  late DateTime _visibleMonth = DateTime(_end.year, _end.month);

  /// Whether the months of [_visibleMonth]'s year are showing instead of its
  /// days.
  bool _showingMonths = false;

  DateTime get _first => _dayOf(widget.firstDate);
  DateTime get _last => _dayOf(widget.lastDate);

  static DateTime _dayOf(DateTime at) => DateTime(at.year, at.month, at.day);

  bool _selectable(DateTime day) =>
      !day.isBefore(_first) && !day.isAfter(_last);

  void _tapDay(DateTime day) {
    setState(() {
      if (!widget.allowRange || !_awaitingEnd) {
        _start = day;
        _end = day;
        _awaitingEnd = widget.allowRange;
        return;
      }
      if (day.isBefore(_start)) {
        _end = _start;
        _start = day;
      } else {
        _end = day;
      }
      _awaitingEnd = false;
    });
  }

  void _pickMonth(DateTime month) {
    final start = DateTime(month.year, month.month);
    // Day 0 of the next month is the last day of this one.
    final end = DateTime(month.year, month.month + 1, 0);
    setState(() {
      _start = start.isBefore(_first) ? _first : start;
      _end = end.isAfter(_last) ? _last : end;
      _awaitingEnd = false;
      _visibleMonth = start;
      _showingMonths = false;
    });
  }

  void _pickShortcut(AppPeriodShortcut shortcut) {
    setState(() {
      _start = _dayOf(shortcut.range.start);
      _end = _dayOf(shortcut.range.end);
      _awaitingEnd = false;
      _visibleMonth = DateTime(_end.year, _end.month);
      _showingMonths = false;
    });
  }

  AppPeriodShortcut? get _matchingShortcut {
    for (final shortcut in widget.shortcuts) {
      if (_dayOf(shortcut.range.start) == _start &&
          _dayOf(shortcut.range.end) == _end) {
        return shortcut;
      }
    }
    return null;
  }

  void _step(int by) => setState(() {
    _visibleMonth = _showingMonths
        ? DateTime(_visibleMonth.year + by, _visibleMonth.month)
        : DateTime(_visibleMonth.year, _visibleMonth.month + by);
  });

  bool get _canStepBack => _showingMonths
      ? _visibleMonth.year > _first.year
      : DateTime(
          _visibleMonth.year,
          _visibleMonth.month,
        ).isAfter(DateTime(_first.year, _first.month));

  bool get _canStepForward => _showingMonths
      ? _visibleMonth.year < _last.year
      : DateTime(
          _visibleMonth.year,
          _visibleMonth.month,
        ).isBefore(DateTime(_last.year, _last.month));

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            controller: widget.controller,
            // `s12` at the sides rather than the sheets' usual `s20`, and
            // [AppPeriodPicker.cellExtent] says why: seven 48s need 336.
            padding: EdgeInsets.fromLTRB(
              tokens.spacing.s12,
              tokens.spacing.s20,
              tokens.spacing.s12,
              tokens.spacing.s16,
            ),
            children: <Widget>[
              Padding(
                padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s8),
                child: _Summary(
                  title: widget.title,
                  start: _start,
                  end: _end,
                  hint: _hint,
                ),
              ),
              if (widget.shortcuts.isNotEmpty) ...<Widget>[
                SizedBox(height: tokens.spacing.s16),
                FilterChipBar<AppPeriodShortcut>(
                  key: const ValueKey('period-picker-shortcuts'),
                  semanticLabel: 'Common periods',
                  selected: _matchingShortcut,
                  options: <FilterChipOption<AppPeriodShortcut>>[
                    for (final shortcut in widget.shortcuts)
                      FilterChipOption<AppPeriodShortcut>(
                        value: shortcut,
                        label: shortcut.label,
                        key: shortcut.key,
                      ),
                  ],
                  onSelected: (shortcut) {
                    if (shortcut != null) _pickShortcut(shortcut);
                  },
                ),
              ],
              SizedBox(height: tokens.spacing.s16),
              _header(context, tokens),
              SizedBox(height: tokens.spacing.s8),
              if (_showingMonths)
                _MonthGrid(
                  year: _visibleMonth.year,
                  first: _first,
                  last: _last,
                  start: _start,
                  end: _end,
                  onPicked: _pickMonth,
                )
              else
                _DayGrid(
                  month: _visibleMonth,
                  start: _start,
                  end: _end,
                  today: _dayOf(widget.currentDate ?? widget.lastDate),
                  selectable: _selectable,
                  onPicked: _tapDay,
                ),
            ],
          ),
        ),
        _footer(context, tokens),
      ],
    );
  }

  /// What the next tap will do, so the two-tap range is never a secret.
  String get _hint {
    if (_showingMonths) return 'Tap a month to take all of it.';
    if (!widget.allowRange) return 'Tap the day to report on.';
    if (_awaitingEnd) return 'Tap another day to make it a range.';
    return 'Tap a day, then another for a range. Tap the month for a whole one.';
  }

  Widget _header(BuildContext context, AppTokens tokens) {
    final localizations = MaterialLocalizations.of(context);
    final heading = _showingMonths
        ? localizations.formatYear(_visibleMonth)
        : localizations.formatMonthYear(_visibleMonth);
    return Row(
      children: <Widget>[
        AppIconButton(
          key: const ValueKey('period-picker-previous'),
          icon: Icons.chevron_left,
          semanticLabel: _showingMonths ? 'Previous year' : 'Previous month',
          bordered: false,
          tier: AppButtonTier.tertiary,
          onPressed: _canStepBack ? () => _step(-1) : null,
        ),
        Expanded(
          child: Center(
            // The month's name is the door to the months, so it looks like a
            // control and says so; where months cannot be picked it is only a
            // heading.
            child: widget.allowRange
                ? AppButton(
                    key: const ValueKey('period-picker-heading'),
                    label: heading,
                    icon: _showingMonths
                        ? Icons.expand_less
                        : Icons.expand_more,
                    tier: AppButtonTier.tertiary,
                    onPressed: () =>
                        setState(() => _showingMonths = !_showingMonths),
                  )
                : Text(
                    heading,
                    key: const ValueKey('period-picker-heading'),
                    style: tokens.typography.titleMedium.copyWith(
                      color: tokens.colors.text.primary,
                    ),
                  ),
          ),
        ),
        AppIconButton(
          key: const ValueKey('period-picker-next'),
          icon: Icons.chevron_right,
          semanticLabel: _showingMonths ? 'Next year' : 'Next month',
          bordered: false,
          tier: AppButtonTier.tertiary,
          onPressed: _canStepForward ? () => _step(1) : null,
        ),
      ],
    );
  }

  /// Pinned under the scrolling part, for the reason the report sheet gives:
  /// a footer inside the list is below the fold on a short phone.
  Widget _footer(BuildContext context, AppTokens tokens) => DecoratedBox(
    decoration: BoxDecoration(
      color: tokens.colors.surface.overlay,
      border: Border(
        top: BorderSide(color: tokens.colors.surface.borderSubtle),
      ),
    ),
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.s20,
        tokens.spacing.s16,
        tokens.spacing.s20,
        tokens.spacing.s16 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: AppActionRow(
        expandActions: true,
        actions: <Widget>[
          AppButton(
            key: const ValueKey('period-picker-cancel'),
            label: 'Cancel',
            tier: AppButtonTier.secondary,
            onPressed: widget.onCancel,
          ),
          AppButton(
            key: const ValueKey('period-picker-done'),
            label: 'Done',
            tier: AppButtonTier.primary,
            // Always a whole answer: a first tap is already a day.
            onPressed: () =>
                widget.onDone(DateTimeRange(start: _start, end: _end)),
          ),
        ],
      ),
    ),
  );
}

/// The title, the span as it stands, and what the next tap does.
final class _Summary extends StatelessWidget {
  const _Summary({
    required this.title,
    required this.start,
    required this.end,
    required this.hint,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final localizations = MaterialLocalizations.of(context);
    final days = end.difference(start).inDays + 1;
    final span = start == end
        ? localizations.formatMediumDate(start)
        : '${localizations.formatMediumDate(start)} – '
              '${localizations.formatMediumDate(end)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: tokens.typography.titleLarge.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
        SizedBox(height: tokens.spacing.s8),
        Semantics(
          liveRegion: true,
          child: Text(
            days == 1 ? span : '$span · $days days',
            key: const ValueKey('period-picker-summary'),
            style: tokens.typography.bodyLarge.copyWith(
              color: tokens.colors.text.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(height: tokens.spacing.s4),
        Text(
          hint,
          key: const ValueKey('period-picker-hint'),
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.secondary,
          ),
        ),
      ],
    );
  }
}

/// Six weeks of one month, starting on the locale's first day of the week.
final class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.month,
    required this.start,
    required this.end,
    required this.today,
    required this.selectable,
    required this.onPicked,
  });

  final DateTime month;
  final DateTime start;
  final DateTime end;
  final DateTime today;
  final bool Function(DateTime day) selectable;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final localizations = MaterialLocalizations.of(context);
    final firstWeekday = localizations.firstDayOfWeekIndex; // 0 is Sunday.
    // `DateTime.weekday` is 1 for Monday through 7 for Sunday.
    final leading = (month.weekday % 7 - firstWeekday) % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final weeks = ((leading + daysInMonth) / 7).ceil();
    final extent = AppPeriodPicker.cellExtent;

    final header = Row(
      children: <Widget>[
        for (var i = 0; i < 7; i++)
          Expanded(
            child: ExcludeSemantics(
              child: Text(
                localizations.narrowWeekdays[(firstWeekday + i) % 7],
                textAlign: TextAlign.center,
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
            ),
          ),
      ],
    );

    return Column(
      key: ValueKey('period-picker-days-${month.year}-${month.month}'),
      children: <Widget>[
        header,
        SizedBox(height: tokens.spacing.s4),
        for (var week = 0; week < weeks; week++)
          Row(
            children: <Widget>[
              for (var column = 0; column < 7; column++)
                Expanded(
                  child: SizedBox(
                    height: extent,
                    child: switch (week * 7 + column - leading + 1) {
                      final date when date >= 1 && date <= daysInMonth =>
                        _DayCell(
                          day: DateTime(month.year, month.month, date),
                          start: start,
                          end: end,
                          today: today,
                          enabled: selectable(
                            DateTime(month.year, month.month, date),
                          ),
                          onPicked: onPicked,
                        ),
                      _ => const SizedBox.shrink(),
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

final class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.start,
    required this.end,
    required this.today,
    required this.enabled,
    required this.onPicked,
  });

  final DateTime day;
  final DateTime start;
  final DateTime end;
  final DateTime today;
  final bool enabled;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final ring = colors.action.focusRing;
    final gutter = ring.width + ring.offset;
    final disc = AppPeriodPicker.cellExtent - gutter * 2;

    final isEnd = day == start || day == end;
    final isRange = start != end;
    final inside = isRange && day.isAfter(start) && day.isBefore(end);
    final isToday = day == today;

    // **The band runs edge to edge**, so a range reads as one strip rather
    // than a row of beads; at an end it covers only the half facing inward.
    final band = colors.status.ok.bg;
    final Widget backdrop = !isRange || !(inside || isEnd)
        ? const SizedBox.expand()
        : Row(
            children: <Widget>[
              Expanded(
                child: ColoredBox(
                  color: inside || day == end ? band : Colors.transparent,
                  child: const SizedBox.expand(),
                ),
              ),
              Expanded(
                child: ColoredBox(
                  color: inside || day == start ? band : Colors.transparent,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          );
    // The band sits in the ring's gutter band only, so it lines up with the
    // discs rather than with the cell's full height.
    final bandInset = EdgeInsets.symmetric(vertical: gutter);

    final label = Text(
      '${day.day}',
      style: tokens.typography.bodyMedium.copyWith(
        color: !enabled
            ? colors.text.disabled
            : isEnd
            ? colors.action.primary.label
            : colors.text.primary,
        fontWeight: isEnd || isToday ? FontWeight.w700 : FontWeight.w400,
      ),
    );

    final radius = BorderRadius.circular(tokens.radius.pill);
    final face = Container(
      width: disc,
      height: disc,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isEnd && enabled ? colors.action.primary.container : null,
        borderRadius: radius,
        // Today is a ring, never a fill, so it cannot be mistaken for a pick.
        border: isToday && !isEnd
            ? Border.all(color: colors.text.secondary)
            : null,
      ),
      child: label,
    );

    final localizations = MaterialLocalizations.of(context);
    final spoken = <String>[
      localizations.formatFullDate(day),
      if (isToday) 'today',
      if (isEnd && !isRange) 'selected',
      if (isEnd && isRange) day == start ? 'start of range' : 'end of range',
      if (inside) 'in range',
    ].join(', ');

    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Padding(padding: bandInset, child: backdrop),
        Semantics(
          button: true,
          enabled: enabled,
          selected: isEnd || inside,
          label: spoken,
          excludeSemantics: true,
          onTap: enabled ? () => onPicked(day) : null,
          child: PressSurface(
            key: ValueKey(
              'period-picker-day-${DateFormat('yyyy-MM-dd').format(day)}',
            ),
            borderRadius: radius,
            onPressed: enabled ? () => onPicked(day) : null,
            excludeSemantics: true,
            hoverOverlay: colors.action.secondary.hoverWash(),
            pressedOverlay: colors.action.secondary.pressedWash(),
            child: face,
          ),
        ),
      ],
    );
  }
}

/// The twelve months of one year, three to a row.
final class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.year,
    required this.first,
    required this.last,
    required this.start,
    required this.end,
    required this.onPicked,
  });

  final int year;
  final DateTime first;
  final DateTime last;
  final DateTime start;
  final DateTime end;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final localizations = MaterialLocalizations.of(context);
    // The app's own default locale, the way every other `DateFormat` here is
    // built - a locale string from the widget tree would need its data loaded.
    final short = DateFormat.MMM();
    final radius = BorderRadius.circular(tokens.radius.md);

    Widget cell(int month) {
      final opens = DateTime(year, month);
      final closes = DateTime(year, month + 1, 0);
      final enabled = !closes.isBefore(first) && !opens.isAfter(last);
      // Picked means the selection is this month, as far as the bounds allow
      // - so *this month* reads as picked on the 23rd.
      final clampedStart = opens.isBefore(first) ? first : opens;
      final clampedEnd = closes.isAfter(last) ? last : closes;
      final picked = enabled && start == clampedStart && end == clampedEnd;

      final face = Container(
        height: AppPeriodPicker.cellExtent,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: picked
              ? colors.action.primary.container
              : colors.surface.raised,
          borderRadius: radius,
          border: picked
              ? null
              : Border.all(color: colors.surface.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // A mark as well as a fill: hard rule 4.
            if (picked) ...<Widget>[
              Icon(
                Icons.check,
                size: AppButton.iconSize,
                color: colors.action.primary.label,
              ),
              SizedBox(width: tokens.spacing.s4),
            ],
            Text(
              short.format(opens),
              style: tokens.typography.bodyMedium.copyWith(
                color: !enabled
                    ? colors.text.disabled
                    : picked
                    ? colors.action.primary.label
                    : colors.text.primary,
                fontWeight: picked ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      );

      return Semantics(
        button: true,
        enabled: enabled,
        selected: picked,
        label: localizations.formatMonthYear(opens),
        excludeSemantics: true,
        onTap: enabled ? () => onPicked(opens) : null,
        child: PressSurface(
          key: ValueKey('period-picker-month-$year-$month'),
          borderRadius: radius,
          onPressed: enabled ? () => onPicked(opens) : null,
          excludeSemantics: true,
          fillWidth: true,
          hoverOverlay: colors.action.secondary.hoverWash(),
          pressedOverlay: colors.action.secondary.pressedWash(),
          child: face,
        ),
      );
    }

    return Column(
      key: ValueKey('period-picker-months-$year'),
      children: <Widget>[
        for (var row = 0; row < 4; row++)
          Row(
            children: <Widget>[
              for (var column = 0; column < 3; column++)
                Expanded(child: cell(row * 3 + column + 1)),
            ],
          ),
      ],
    );
  }
}
