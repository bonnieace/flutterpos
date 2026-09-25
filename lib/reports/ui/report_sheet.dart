/// Picking a period and a format for a report.
///
/// **The controls offered are the ones the records can honour.** A screen whose
/// records carry no time dimension at all - the catalog has none - gets no date
/// control, only a sentence saying the figures are as at now. A screen that can
/// answer for exactly one day gets a calendar that picks one day. Offering a
/// range over records that cannot express one would produce a document that
/// states a period it never read, which is the single failure this whole area
/// is built to avoid.
///
/// **Two questions, since 2026-09-23**, at the developer's direction: which
/// period, and in which format. The period is one button the width of the sheet
/// - the control expenses opens its own period with - onto a calendar that
/// picks a day, a range or a month. Where the file goes is no longer asked: a
/// copy is saved.
library;

import 'package:flutter/material.dart';

import '../../ui/buttons.dart';
import '../../ui/choice.dart';
import '../../ui/fields.dart';
import '../../ui/period_picker.dart';
import '../../ui/sheet.dart';
import '../../ui/states.dart';
import '../../ui/status.dart';
import '../../ui/tokens.dart';
import '../report_document.dart';
import '../report_file.dart';
import '../report_period.dart';
import '../report_run.dart';

/// The spans a person picks without reaching for the calendar, offered as
/// shortcuts above it.
///
/// **The one the sheet opens on comes first.** Month-to-date is the span most
/// people want from a business report, then the narrower ones.
enum TenantReportPreset {
  thisMonth('This month'),
  today('Today'),
  yesterday('Yesterday'),
  lastSeven('Last 7 days'),
  lastThirty('Last 30 days');

  const TenantReportPreset(this.label);

  final String label;

  /// The period this preset means at [nowUtc].
  TenantReportPeriod periodAt(DateTime nowUtc) => switch (this) {
    TenantReportPreset.today => TenantReportPeriod.today(nowUtc),
    TenantReportPreset.yesterday => TenantReportPeriod.day(
      TenantReportPeriod.lastDays(2, nowUtc).startDate,
    ),
    TenantReportPreset.lastSeven => TenantReportPeriod.lastDays(7, nowUtc),
    TenantReportPreset.lastThirty => TenantReportPeriod.lastDays(30, nowUtc),
    TenantReportPreset.thisMonth => TenantReportPeriod.monthOf(nowUtc),
  };

  /// The presets a given kind of records can honestly answer for.
  static List<TenantReportPreset> forSupport(
    TenantReportPeriodSupport support,
  ) => switch (support) {
    TenantReportPeriodSupport.range => TenantReportPreset.values,
    // One day at a time, so every multi-day preset is withheld rather than
    // quietly collapsed to a single day the person did not ask for.
    TenantReportPeriodSupport.dayOnly => <TenantReportPreset>[
      TenantReportPreset.today,
      TenantReportPreset.yesterday,
    ],
    TenantReportPeriodSupport.snapshot => const <TenantReportPreset>[],
  };
}

/// The glyph each format's card leads with.
IconData _formatIcon(TenantReportFormat format) => switch (format) {
  TenantReportFormat.pdf => Icons.picture_as_pdf_outlined,
  TenantReportFormat.excel => Icons.table_chart_outlined,
};

/// Opens the picker and answers what the person chose, or null if they backed
/// out.
Future<TenantReportRequest?> showTenantReportSheet(
  BuildContext context, {
  required TenantReportKind kind,
  required TenantReportPeriodSupport support,
  required DateTime Function() clock,
  TenantReportSubject? subject,
}) => showAppSheet<TenantReportRequest>(
  context,
  // **Only Cancel closes this one.** A tap on the scrim while reaching for a
  // card threw the choices away. The drag no longer dismisses any sheet in the
  // app; this is the other half of that.
  dismissible: false,
  builder: (sheetContext, controller) => _TenantReportSheet(
    kind: kind,
    support: support,
    subject: subject,
    clock: clock,
    controller: controller,
  ),
);

final class _TenantReportSheet extends StatefulWidget {
  const _TenantReportSheet({
    required this.kind,
    required this.support,
    required this.subject,
    required this.clock,
    required this.controller,
  });

  final TenantReportKind kind;
  final TenantReportPeriodSupport support;
  final TenantReportSubject? subject;
  final DateTime Function() clock;
  final ScrollController controller;

  @override
  State<_TenantReportSheet> createState() => _TenantReportSheetState();
}

final class _TenantReportSheetState extends State<_TenantReportSheet> {
  /// This month for a range report, today for anything read a day at a time -
  /// the default expenses opens on, so the page and its report agree about
  /// what a period means before anybody has touched either.
  late TenantReportPeriod _period = switch (widget.support) {
    TenantReportPeriodSupport.range => TenantReportPeriod.monthOf(
      widget.clock(),
    ),
    TenantReportPeriodSupport.dayOnly || TenantReportPeriodSupport.snapshot =>
      TenantReportPeriod.today(widget.clock()),
  };

  TenantReportFormat _format = TenantReportFormat.pdf;

  /// What the subject chooser offers, null while it is being read.
  List<TenantReportSubjectOption>? _options;
  bool _optionsFailed = false;

  /// The one thing chosen, or null for *all of them* - which is what the sheet
  /// opens on, so a report is never narrowed without somebody asking.
  TenantReportSubjectOption? _subject;

  @override
  void initState() {
    super.initState();
    final subject = widget.subject;
    if (subject != null) _readOptions(subject);
  }

  Future<void> _readOptions(TenantReportSubject subject) async {
    try {
      final options = await subject.loadOptions();
      if (!mounted) return;
      setState(() => _options = options);
    } catch (_) {
      // **The report is still offered, over everything.** A chooser that could
      // not be filled is not a reason to refuse a report that needs no choice.
      if (!mounted) return;
      setState(() {
        _options = const <TenantReportSubjectOption>[];
        _optionsFailed = true;
      });
    }
  }

  /// A business date read back as the local midnight the calendar speaks.
  static DateTime _day(String businessDate) => DateTime.parse(businessDate);

  /// The calendar answers a local `DateTime`; a report speaks business dates.
  static String _businessDate(DateTime at) {
    final month = at.month.toString().padLeft(2, '0');
    final day = at.day.toString().padLeft(2, '0');
    return '${at.year.toString().padLeft(4, '0')}-$month-$day';
  }

  /// **`firstDate` is a year back, not the beginning of time.** A range read is
  /// bounded, so a person who picks five years gets a total that is quietly
  /// short; a year is the longest stretch these reports chart anyway.
  Future<void> _pickPeriod() async {
    final now = widget.clock();
    final today = _day(TenantReportPeriod.today(now).startDate);
    final range = widget.support == TenantReportPeriodSupport.range;
    final picked = await showAppPeriodPicker(
      context,
      initial: DateTimeRange(
        start: _day(_period.startDate),
        end: _day(_period.endDate),
      ),
      firstDate: DateTime(today.year - 1, today.month, today.day),
      lastDate: today,
      currentDate: today,
      allowRange: range,
      title: range ? 'Period to report on' : 'Day to report on',
      shortcuts: <AppPeriodShortcut>[
        for (final preset in TenantReportPreset.forSupport(widget.support))
          AppPeriodShortcut(
            key: ValueKey('report-preset-${preset.name}'),
            label: preset.label,
            range: DateTimeRange(
              start: _day(preset.periodAt(now).startDate),
              end: _day(preset.periodAt(now).endDate),
            ),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(
      () => _period = TenantReportPeriod(
        startDate: _businessDate(picked.start),
        endDate: _businessDate(picked.end),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);

    // **The actions are pinned, not the last rows of the list.** Padding the
    // bottom of a scroll view does not help when the content is taller than
    // the sheet: the buttons are simply below the fold, and on a 720x1600
    // phone they were, where on a 1080x2400 emulator they were not. A footer
    // outside the scrollable cannot be scrolled away from, whatever the screen
    // or the text scale.
    return Column(
      children: <Widget>[
        Expanded(child: _choices(context, tokens)),
        _actions(context, tokens),
      ],
    );
  }

  /// Everything the person picks, in the part of the sheet that scrolls.
  Widget _choices(BuildContext context, AppTokens tokens) {
    final isSnapshot = widget.support == TenantReportPeriodSupport.snapshot;
    return ListView(
      controller: widget.controller,
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.s20,
        tokens.spacing.s20,
        tokens.spacing.s20,
        tokens.spacing.s16,
      ),
      children: <Widget>[
        Text(
          widget.kind.title,
          key: const ValueKey('report-sheet-title'),
          style: tokens.typography.titleLarge.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),

        // A snapshot report says its piece, because there it is not a
        // description of a control - it is the reason there is no control.
        if (isSnapshot) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          Text(
            'These records keep no history, so the report is as things '
            'stand now.',
            key: const ValueKey('report-sheet-explainer'),
            style: tokens.typography.bodyMedium.copyWith(
              color: tokens.colors.text.secondary,
            ),
          ),
        ],
        SizedBox(height: tokens.spacing.s24),

        if (widget.subject case final subject?)
          _periodAndSubject(context, tokens, subject, isSnapshot: isSnapshot)
        else if (!isSnapshot) ...<Widget>[
          _periodBlock(tokens),
          SizedBox(height: tokens.spacing.s24),
        ],

        _label(tokens, 'Format'),
        SizedBox(height: tokens.spacing.s8),
        ChoiceCardGroup<TenantReportFormat>(
          key: const ValueKey('report-sheet-formats'),
          semanticLabel: 'Format',
          selected: _format,
          options: <ChoiceCardOption<TenantReportFormat>>[
            for (final format in TenantReportFormat.values)
              ChoiceCardOption<TenantReportFormat>(
                key: ValueKey('report-format-${format.name}'),
                value: format,
                title: format.label,
                description: format.description,
                icon: _formatIcon(format),
              ),
          ],
          onSelected: (format) => setState(() => _format = format),
        ),
      ],
    );
  }

  /// The footer, which is always on screen.
  ///
  /// **Cancel is drawn rather than left to the scrim**: neither a drag nor a
  /// tap outside closes this sheet any more, and a sheet with no visible way
  /// back is a trap.
  ///
  /// `AppActionRow` with the primary last, which is the app's own footer order
  /// and the reason is the hand - see `stock_adjustment_panel.dart`. Side by
  /// side rather than stacked, because two full-width buttons take a fifth of
  /// a phone-sized sheet away from the choices above them.
  Widget _actions(BuildContext context, AppTokens tokens) => DecoratedBox(
    decoration: BoxDecoration(
      color: tokens.colors.surface.overlay,
      border: Border(
        top: BorderSide(color: tokens.colors.surface.borderSubtle),
      ),
    ),
    child: Padding(
      // **The phone's bottom edge, not the sheet's.** A sheet is anchored to
      // the bottom of the screen and the system's gesture bar is drawn over
      // that strip. `viewPadding` rather than `padding` because the sheet's
      // route has already consumed the latter.
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
            key: const ValueKey('report-sheet-cancel'),
            label: 'Cancel',
            tier: AppButtonTier.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          AppButton(
            key: const ValueKey('report-sheet-create'),
            label: 'Create report',
            tier: AppButtonTier.primary,
            onPressed: () => Navigator.of(context).pop(
              TenantReportRequest(
                period: _period,
                format: _format,
                subject: _subject,
                // **Saved, never asked**, at the developer's direction on
                // 2026-09-23. The share path stays in the saver for a caller
                // that wants it; this sheet no longer offers it.
                destination: TenantReportDestination.device,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  /// The period, as one button onto the calendar the width of its column.
  Widget _periodBlock(AppTokens tokens) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _label(tokens, 'Period'),
      SizedBox(height: tokens.spacing.s8),
      // **One button onto the calendar** - the control expenses opens its own
      // period with, so a period is picked the same way on the page and in its
      // report.
      AppButton(
        key: const ValueKey('report-sheet-period'),
        label: _period.label(widget.clock()),
        icon: Icons.calendar_today_outlined,
        tier: AppButtonTier.secondary,
        expand: true,
        onPressed: _pickPeriod,
      ),
    ],
  );

  /// What the report is narrowed to, *all* first.
  Widget _subjectBlock(AppTokens tokens, TenantReportSubject subject) {
    final options = _options;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _label(tokens, subject.label),
        SizedBox(height: tokens.spacing.s8),
        // Typed nullable, so *all of them* is a value rather than a sentinel.
        AppSelect<String?>(
          key: const ValueKey('report-sheet-subject'),
          label: subject.label,
          dense: true,
          leading: Icons.filter_alt_outlined,
          value: _subject?.id,
          enabled: options != null && options.isNotEmpty,
          items: <AppSelectItem<String?>>[
            AppSelectItem<String?>(
              key: const ValueKey('report-sheet-subject-all'),
              value: null,
              label: subject.allLabel,
            ),
            for (final option in options ?? const <TenantReportSubjectOption>[])
              AppSelectItem<String?>(
                key: ValueKey('report-sheet-subject-${option.id}'),
                value: option.id,
                label: option.note == null
                    ? option.label
                    : '${option.label} (${option.note})',
              ),
          ],
          onChanged: (id) => setState(() {
            _subject = id == null
                ? null
                : options?.firstWhere((option) => option.id == id);
          }),
        ),
        if (_optionsFailed) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          Text(
            key: const ValueKey('report-sheet-subject-unread'),
            'The list could not be read, so the report covers '
            '${subject.allLabel.toLowerCase()}.',
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        ],
      ],
    );
  }

  /// The period and the subject side by side where the sheet is wide enough,
  /// stacked on a phone - the two do not fit beside one another there.
  Widget _periodAndSubject(
    BuildContext context,
    AppTokens tokens,
    TenantReportSubject subject, {
    required bool isSnapshot,
  }) {
    final subjectBlock = _subjectBlock(tokens, subject);
    if (isSnapshot) {
      return Padding(
        padding: EdgeInsets.only(bottom: tokens.spacing.s24),
        child: subjectBlock,
      );
    }
    final wide = AppLayout.contract.isAtLeast(
      MediaQuery.sizeOf(context).width,
      AppBreakpoint.medium,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.s24),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: _periodBlock(tokens)),
                SizedBox(width: tokens.spacing.s12),
                Expanded(child: subjectBlock),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _periodBlock(tokens),
                SizedBox(height: tokens.spacing.s16),
                subjectBlock,
              ],
            ),
    );
  }

  Widget _label(AppTokens tokens, String text) => Text(
    text.toUpperCase(),
    style: tokens.typography.labelEyebrow.copyWith(
      color: tokens.colors.text.secondary,
    ),
  );
}

/// What to say back once a report has been handed over.
///
/// **The destination changes the sentence, because it changes what happened.**
/// Backing out of the file picker left nothing saved; backing out of the share
/// sheet sent nothing. Saying "not sent anywhere" to somebody who was saving a
/// copy would send them looking through their messages for a file that was
/// never going there.
AppNotice tenantReportNotice(
  TenantReportSaveOutcome outcome,
  TenantReportKind kind, {
  required TenantReportDestination destination,
}) => switch (outcome) {
  TenantReportSaveOutcome.saved => AppNotice.confirmed(switch (destination) {
    TenantReportDestination.device =>
      'The ${kind.title.toLowerCase()} is saved.',
    TenantReportDestination.share =>
      'The ${kind.title.toLowerCase()} is '
          'ready.',
  }),
  // Not a failure. The person opened the picker and changed their mind, and
  // telling them something went wrong would be untrue.
  TenantReportSaveOutcome.dismissed => AppNotice.offline(switch (destination) {
    TenantReportDestination.device =>
      'The report was built but not saved anywhere.',
    TenantReportDestination.share =>
      'The report was built but not sent anywhere.',
  }),
  TenantReportSaveOutcome.unavailable => AppNotice.refused(
    switch (destination) {
      TenantReportDestination.device =>
        'This phone has no file manager to save it with. Try sharing it '
            'instead.',
      TenantReportDestination.share =>
        'This device offered nowhere to send the report.',
    },
  ),
};

/// What to say when a report could not be read at all.
///
/// **It never names a period as covered.** A read that failed has no scope to
/// report, and a sentence implying a file exists somewhere would send somebody
/// looking for one. The refusal says what happened and what to do next.
AppNotice tenantReportFailureNotice(Object error) => switch (error) {
  // A tenant boundary refusing is not a network problem and must not be
  // softened into one - the person is being told they may not read this.
  _ when error.toString().contains('forbidden') => const AppNotice.refused(
    'This report is not yours to read.',
  ),
  _ => const AppNotice.unknown(
    'The records for that period could not be read, so no report was made. '
    'Check the connection and try again.',
  ),
};

/// The state a screen shows while a report is being built.
final class TenantReportProgress extends StatelessWidget {
  const TenantReportProgress({super.key, required this.stage});

  final TenantReportStage stage;

  @override
  Widget build(BuildContext context) => LoadingState(
    key: const ValueKey('report-progress'),
    message: stage.label,
  );
}
