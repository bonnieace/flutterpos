/// Why the Sales report opened on a day that is still trading, drawn as the
/// night it describes.
///
/// **Built to `docs/design/still-trading/` on 2026-10-12**, replacing an info
/// `Callout` inside a stock dialog. The report has already moved to the day; this
/// says why in one sentence and draws the night that day is part of - when its
/// shift opened, where midnight fell, where we are now, and when it stops - so
/// "why Sunday?" is answered by looking rather than reading.
///
/// A sheet below `layout.mediumFloor`, where both answers sit under the thumb;
/// a dialog of `layout.explanationDialog` from there up.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../checkout/checkout_draft.dart';
import '../reports/analysis/report_prose.dart';
import '../shift/open_trading_day.dart';
import '../shift/shift_controller.dart';
import '../ui/buttons.dart';
import '../ui/meter.dart';
import '../ui/sheet.dart';
import '../ui/tokens.dart';

/// Which day the person chose to look at.
enum TradingDayAnswer {
  /// The day still trading, which the report is already on.
  stay,

  /// Today, which nothing has been filed under yet.
  today,
}

/// What a person answered, and whether they asked not to be told again.
///
/// **[silence] rides on either answer**, and on a dismissal: the checkbox is a
/// preference about the explanation, not a third way out of it.
typedef TradingDayReply = ({TradingDayAnswer answer, bool silence});

/// Everything the explanation says and draws, worked out from the day and the
/// moment it is shown.
///
/// **A value, not a widget**, so the wording and the geometry are tested
/// without pumping anything - and so "now" is fixed once: the night is a picture
/// of the moment the report opened, exactly as the report's choice of day is.
final class TradingDayExplanation {
  const TradingDayExplanation._({
    required this.weekday,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.night,
  });

  factory TradingDayExplanation.of(
    TenantOpenTradingDay day, {
    required DateTime now,
  }) {
    final date = DateTime.parse(day.businessDate);
    final weekday = DateFormat('EEEE').format(date);
    final ends = shopClock(day.sellingEndsAt);
    final many = day.shiftCount > 1;
    final yours = !many && day.isOwn;
    final atTheCap = !many && day.endsAtTheCap;
    final until = atTheCap
        ? 'or $ends, when it reaches 24 hours'
        : 'or $ends at the latest';
    final body = yours
        ? 'Your shift from $weekday is still open, so your sales since '
              'midnight count toward $weekday until you close it, $until.'
        : many
        ? '${_count(day.shiftCount)} shifts from $weekday are still open, so '
              'sales made since midnight count toward $weekday until they are '
              'closed, $until.'
        : 'Sales made since midnight count toward $weekday until the shift is '
              'closed, $until.';
    return TradingDayExplanation._(
      weekday: weekday,
      eyebrow:
          '${DateFormat('EEE').format(date)} ${reportShortDate(day.businessDate)} '
                  '· business day'
              .toUpperCase(),
      title: 'Still trading on $weekday',
      body: body,
      night: TradingNight._of(
        day,
        now: now.toUtc(),
        weekday: weekday,
        yours: yours,
        many: many,
        atTheCap: atTheCap,
      ),
    );
  }

  /// The day still trading, as a person says it at 01:30: *Sunday*.
  final String weekday;

  /// `SUN 11 OCT · BUSINESS DAY` - the date the weekday stands for.
  final String eyebrow;
  final String title;
  final String body;

  /// Null where no shift has a known start, so there is no night to draw -
  /// the sentence still says everything.
  final TradingNight? night;

  /// A time of day in the shop's own clock, which is the clock the 06:00
  /// cutoff and every business date are kept in - not this device's.
  static String shopClock(DateTime instant) =>
      _clock.format(instant.toUtc().add(checkoutBusinessDayOffset));

  static final DateFormat _clock = DateFormat('HH:mm');

  static String _count(int count) => switch (count) {
    2 => 'Two',
    3 => 'Three',
    4 => 'Four',
    5 => 'Five',
    6 => 'Six',
    7 => 'Seven',
    8 => 'Eight',
    9 => 'Nine',
    _ => '$count',
  };
}

/// Where a shift-span label sits against its mark.
enum TradingNightAnchor {
  /// Starts at the mark, near the left end.
  start,

  /// Centred on the mark.
  centre,

  /// Ends at the mark, near the right end.
  end,
}

/// The night the explanation draws: a track from the first shift's opening to
/// the moment selling stops, a notch at midnight, and the fill up to now.
final class TradingNight {
  const TradingNight._({
    required this.opened,
    required this.openedWord,
    required this.ends,
    required this.endsWord,
    required this.now,
    required this.nowAt,
    required this.midnightAt,
    required this.showsMidnight,
    required this.semanticsLabel,
  });

  static TradingNight? _of(
    TenantOpenTradingDay day, {
    required DateTime now,
    required String weekday,
    required bool yours,
    required bool many,
    required bool atTheCap,
  }) {
    final start = day.firstOpenedAt;
    final end = day.sellingEndsAt;
    if (start == null || !end.isAfter(start)) return null;
    final span = end.difference(start).inMicroseconds;
    double at(DateTime instant) =>
        (instant.difference(start).inMicroseconds / span).clamp(0.0, 1.0);
    final midnight = TenantShiftController.tradingDayEndsAt(
      day.businessDate,
    ).subtract(TenantShiftController.tradingDayCutoff);
    final midnightAt = at(midnight);
    final opened = TradingDayExplanation.shopClock(start);
    final ends = TradingDayExplanation.shopClock(end);
    final nowClock = TradingDayExplanation.shopClock(now);
    final who = yours
        ? 'Your shift opened'
        : many
        ? 'The first shift opened'
        : 'Shift opened';
    return TradingNight._(
      opened: opened,
      openedWord: many ? 'first opened' : 'opened',
      ends: ends,
      endsWord: atTheCap ? '24 h' : 'stops',
      now: nowClock,
      nowAt: at(now),
      midnightAt: midnightAt,
      showsMidnight:
          midnightAt >= _clearOfTheEnds && midnightAt <= 1 - _clearOfTheEnds,
      semanticsLabel:
          '$who $opened on $weekday. It is now $nowClock. It stops selling at '
          '$ends.',
    );
  }

  /// How far from either end the midnight label must be to keep its place.
  /// Nearer, it would sit on the opening or the stopping time; the notch stays.
  static const double _clearOfTheEnds = 0.2;

  final String opened;
  final String openedWord;
  final String ends;
  final String endsWord;
  final String now;

  /// Where now falls, from 0 at the opening to 1 at the stop.
  final double nowAt;

  /// Where midnight falls on the same scale.
  final double midnightAt;
  final bool showsMidnight;

  /// The whole picture as one sentence, for a screen reader: nothing here is
  /// said by colour or position alone.
  final String semanticsLabel;

  /// Where the *Now* label sits, so it never runs off either end.
  TradingNightAnchor get nowAnchor => nowAt > 1 - _clearOfTheEnds
      ? TradingNightAnchor.end
      : nowAt < _clearOfTheEnds
      ? TradingNightAnchor.start
      : TradingNightAnchor.centre;
}

/// Shows [explanation] and answers with the day chosen and the checkbox.
///
/// **Every way out that is not a button is [TradingDayAnswer.stay]** - the
/// scrim, the system back, a drag down - because staying is what the report has
/// already done; leaving it alone changes nothing.
///
/// [canSilence] is false where this device cannot remember the answer, and the
/// checkbox is then not offered rather than offered and forgotten.
Future<TradingDayReply> showTradingDayExplanation(
  BuildContext context, {
  required TradingDayExplanation explanation,
  required bool canSilence,
}) async {
  final tokens = AppTokens.componentOf(context);
  var silence = false;
  void remember(bool value) => silence = value;
  final wide = MediaQuery.sizeOf(context).width >= tokens.layout.mediumFloor;
  final TradingDayAnswer? answer;
  if (wide) {
    answer = await showDialog<TradingDayAnswer>(
      context: context,
      barrierColor: tokens.colors.surface.scrim,
      builder: (context) => _ExplanationDialog(
        child: TradingDayExplanationBody(
          explanation: explanation,
          canSilence: canSilence,
          stacked: false,
          onAnswer: (answer) => Navigator.of(context).pop(answer),
          onSilenceChanged: remember,
        ),
      ),
    );
  } else {
    answer = await showAppFittedSheet<TradingDayAnswer>(
      context,
      builder: (context) => TradingDayExplanationBody(
        explanation: explanation,
        canSilence: canSilence,
        stacked: true,
        onAnswer: (answer) => Navigator.of(context).pop(answer),
        onSilenceChanged: remember,
      ),
    );
  }
  return (answer: answer ?? TradingDayAnswer.stay, silence: silence);
}

/// The dialog the explanation sits in from `layout.mediumFloor` up.
///
/// **A `Dialog`, not `AppDialog`**, for the reason the night gives: it measures
/// itself with a `LayoutBuilder`, which `AlertDialog`'s intrinsic sizing cannot
/// ask, and its heading is an eyebrow over a `titleLarge` rather than
/// `AppDialog`'s one `titleMedium` line. The surface, the corners, the inset and
/// the scrim are the same `design.md` rows `AppDialog` reads.
final class _ExplanationDialog extends StatelessWidget {
  const _ExplanationDialog({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Dialog(
      backgroundColor: tokens.colors.surface.overlay,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius.lg),
      ),
      insetPadding: EdgeInsets.all(tokens.spacing.s24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: tokens.layout.explanationDialog),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(tokens.spacing.s24),
          child: child,
        ),
      ),
    );
  }
}

/// The explanation itself, inside whichever surface holds it.
///
/// [stacked] lays the answers out for a phone: the primary full width first,
/// then today, then the checkbox. Otherwise they share one line, the checkbox
/// on the left where a desktop puts it.
final class TradingDayExplanationBody extends StatefulWidget {
  const TradingDayExplanationBody({
    super.key = const ValueKey('sales-report-trading-day'),
    required this.explanation,
    required this.canSilence,
    required this.stacked,
    required this.onAnswer,
    required this.onSilenceChanged,
  });

  final TradingDayExplanation explanation;
  final bool canSilence;
  final bool stacked;
  final ValueChanged<TradingDayAnswer> onAnswer;
  final ValueChanged<bool> onSilenceChanged;

  @override
  State<TradingDayExplanationBody> createState() =>
      _TradingDayExplanationBodyState();
}

final class _TradingDayExplanationBodyState
    extends State<TradingDayExplanationBody> {
  bool _silence = false;

  void _setSilence(bool? value) {
    final next = value ?? false;
    setState(() => _silence = next);
    widget.onSilenceChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final explanation = widget.explanation;
    final night = explanation.night;
    final stay = AppButton(
      key: const ValueKey('sales-report-trading-day-stay'),
      label: 'Show ${explanation.weekday}',
      tier: AppButtonTier.primary,
      expand: widget.stacked,
      autofocus: true,
      onPressed: () => widget.onAnswer(TradingDayAnswer.stay),
    );
    final today = AppButton(
      key: const ValueKey('sales-report-show-today'),
      label: 'Show today',
      tier: AppButtonTier.secondary,
      expand: widget.stacked,
      onPressed: () => widget.onAnswer(TradingDayAnswer.today),
    );
    // **The till's own words for the same choice**, and short enough to stay on
    // one line beside two buttons in the dialog: *Don't show this again*
    // wrapped there. The gap is the design's 12 rather than `ListTile`'s 16.
    final silence = widget.canSilence
        ? ListTileTheme.merge(
            horizontalTitleGap: tokens.spacing.s12,
            child: CheckboxListTile(
              key: const ValueKey('sales-report-trading-day-silence'),
              value: _silence,
              onChanged: _setSilence,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Don’t show again',
                maxLines: 1,
                style: tokens.typography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
          )
        : null;
    return Padding(
      // The sheet's handle sits 12 above; the dialog pads itself.
      padding: widget.stacked
          ? EdgeInsets.fromLTRB(
              tokens.spacing.s24,
              tokens.spacing.s20,
              tokens.spacing.s24,
              tokens.spacing.s8,
            )
          : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            explanation.eyebrow,
            style: tokens.typography.labelEyebrow.copyWith(
              color: colors.text.tertiary,
            ),
          ),
          SizedBox(height: tokens.spacing.s8),
          Text(
            explanation.title,
            style: tokens.typography.titleLarge.copyWith(
              color: colors.text.primary,
            ),
          ),
          SizedBox(height: tokens.spacing.s8),
          Text(
            explanation.body,
            style: tokens.typography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          if (night != null) ...<Widget>[
            SizedBox(height: tokens.spacing.s24),
            TradingNightTrack(night: night),
          ],
          SizedBox(height: tokens.spacing.s32),
          if (widget.stacked) ...<Widget>[
            stay,
            SizedBox(height: tokens.spacing.s8),
            today,
            if (silence != null) ...<Widget>[
              SizedBox(height: tokens.spacing.s8),
              silence,
            ],
          ] else
            Row(
              children: <Widget>[
                Expanded(child: silence ?? const SizedBox.shrink()),
                SizedBox(width: tokens.spacing.s8),
                today,
                SizedBox(width: tokens.spacing.s8),
                stay,
              ],
            ),
        ],
      ),
    );
  }
}

/// The night as a track: `AppMeter`'s, with a notch at midnight and a mark at
/// now, labelled above and below.
///
/// **`AppMeter`'s geometry, not a new one** - an [AppMeter.trackOf] track at
/// `radius.pill`, filled with `status.ok`. Two departures, both recorded in
/// `docs/design/still-trading/README.md`: the unfilled track is
/// `border.strong`, because the meter's `border.subtle` measures 1.09:1 on
/// `surface.overlay` and vanishes; and the notch and the mark are new.
final class TradingNightTrack extends StatelessWidget {
  const TradingNightTrack({super.key, required this.night});

  final TradingNight night;

  /// The notch's width: midnight is a cut through the fill, two pixels wide.
  ///
  /// **Named here rather than tokenised, for the reason the sales report's
  /// `_hairline` gives**: this app has no stroke-width token to read it from.
  static const double notchWidth = 2;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final ok = colors.status.ok.fg;
    final ring = colors.surface.overlay;
    final track = AppMeter.trackOf(tokens);
    final mark = tokens.spacing.s16;
    final caption = tokens.typography.caption;
    final line = caption.fontSize! * caption.height!;
    final timeStyle = tokens.typography.monoCaption.copyWith(
      color: colors.text.secondary,
    );
    final wordStyle = caption.copyWith(color: colors.text.tertiary);
    Widget tick(String time, String? word) => Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(text: time, style: timeStyle),
          if (word != null) TextSpan(text: ' $word', style: wordStyle),
        ],
      ),
      maxLines: 1,
    );
    double shift(TradingNightAnchor anchor) => switch (anchor) {
      TradingNightAnchor.start => 0,
      TradingNightAnchor.centre => -0.5,
      TradingNightAnchor.end => -1,
    };

    return Semantics(
      image: true,
      label: night.semanticsLabel,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final nowX = night.nowAt * width;
          final midnightX = night.midnightAt * width;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                height: line,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      left: nowX,
                      top: 0,
                      child: FractionalTranslation(
                        translation: Offset(shift(night.nowAnchor), 0),
                        child: Text(
                          'Now ${night.now}',
                          key: const ValueKey('trading-night-now'),
                          maxLines: 1,
                          style: caption.copyWith(color: ok),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: tokens.spacing.s4),
              SizedBox(
                height: mark,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      left: 0,
                      right: 0,
                      top: (mark - track) / 2,
                      height: track,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surface.borderStrong,
                          borderRadius: BorderRadius.circular(
                            tokens.radius.pill,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      width: nowX,
                      top: (mark - track) / 2,
                      height: track,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: ok,
                          borderRadius: BorderRadius.circular(
                            tokens.radius.pill,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: midnightX - notchWidth / 2,
                      width: notchWidth,
                      top: 0,
                      height: mark,
                      child: ColoredBox(color: ring),
                    ),
                    Positioned(
                      left: nowX - mark / 2,
                      top: 0,
                      width: mark,
                      height: mark,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: ok,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: ring,
                            width: tokens.spacing.s4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: tokens.spacing.s4),
              SizedBox(
                height: line,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      left: 0,
                      top: 0,
                      child: tick(night.opened, night.openedWord),
                    ),
                    if (night.showsMidnight)
                      Positioned(
                        left: midnightX,
                        top: 0,
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, 0),
                          child: tick('00:00', null),
                        ),
                      ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: tick(night.ends, night.endsWord),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
