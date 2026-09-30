/// The open shift, on the home: when it began, whose it is, and the way out.
///
/// **A cashier's, and only while the shift is open.** Added 2026-09-30 at the
/// developer's direction. Closing moved to the till on 2026-08-25 and is still
/// there; this is a second door to the same sheet, for a cashier standing on
/// the home who would otherwise enter the till only to leave it again.
///
/// **It holds no shift state of its own.** The controller is the one the till's
/// gate uses - `TenantShiftControllerFactory` hands both the same instance - so
/// a shift opened at the till is on the home when the till is left, and a shift
/// closed here is closed when the till is next entered.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../reporting/reporting_currency.dart';
import '../returns/return_actions.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_types.dart';
import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'shift_controller.dart';
import 'shift_panel.dart';

/// *Shift · Open*, *Opened 06:30 by Amina · 2h 14m*, and *Close shift*.
final class TenantHomeShiftCard extends StatefulWidget {
  const TenantHomeShiftCard({
    super.key,
    required this.controllerFactory,
    required this.currency,
    this.memberName,
    this.returnActions,
    this.clock = DateTime.now,
  });

  /// The till's own, so the two never hold different shifts for one session.
  final TenantShiftControllerFactory controllerFactory;

  /// Passed to the close sheet, which states the shift's figures in it.
  final TenantReportingCurrency currency;

  /// Whose shift it is. A shift document names its cashier by uid alone, and a
  /// cashier only ever sees their own, so this is the signed-in member's name.
  /// Null leaves the name out rather than printing an id.
  final String? memberName;

  /// Passed to the close sheet.
  final TenantReturnActions? returnActions;

  /// What *now* is, for how long the shift has run.
  final DateTime Function() clock;

  /// How often the running time is redrawn. It is stated to the minute, so a
  /// faster tick would repaint an unchanged line.
  static const Duration tick = Duration(minutes: 1);

  @override
  State<TenantHomeShiftCard> createState() => _TenantHomeShiftCardState();
}

final class _TenantHomeShiftCardState extends State<TenantHomeShiftCard> {
  TenantSessionController? _sessions;
  TenantShiftController? _shifts;

  /// The session the shift was last read for - the gate's `_readFor`, for the
  /// same reason: a role change or a new epoch is a different question.
  String? _readFor;

  Timer? _ticker;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sessions = TenantSessionScope.of(context);
    if (!identical(sessions, _sessions)) {
      // **Unsubscribed, not disposed.** The controller is the session's and
      // outlives this card; see `TenantShiftControllerFactory`.
      _shifts?.removeListener(_changed);
      _sessions = sessions;
      _shifts = widget.controllerFactory(sessions)..addListener(_changed);
      _readFor = null;
    }
    final session = sessions.session;
    final identity = session == null
        ? null
        : '${session.uid}:${session.tenantId}:${session.epoch}';
    if (identity == _readFor) return;
    _readFor = identity;
    // **Read only for a cashier, who is the only one it is drawn for.** Any
    // other role's home asks nothing of the shift it did not ask before.
    if (session != null && _isCashier(session)) {
      unawaited(_shifts!.restore(session));
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _shifts?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    _syncTicker();
    setState(() {});
  }

  /// Ticks only while there is a running time on screen to keep true.
  void _syncTicker() {
    final running = _shows && _shifts?.state.shift?.startedAt != null;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(TenantHomeShiftCard.tick, (_) {
        if (mounted) setState(() {});
      });
    } else if (!running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  static bool _isCashier(TenantSession session) =>
      session.role == TenantRole.cashier;

  /// Open, or open with its count under way - the sheet is over this card
  /// then, and the shift is not closed until the count is.
  bool get _shows {
    final session = _sessions?.session;
    final phase = _shifts?.state.phase;
    return session != null &&
        _isCashier(session) &&
        (phase == TenantShiftPhase.open || phase == TenantShiftPhase.closing);
  }

  Future<void> _close() async {
    final shifts = _shifts;
    final session = _sessions?.session;
    if (shifts == null || session == null) return;
    await showShiftCloseSheet(
      context,
      shifts: shifts,
      session: session,
      currency: widget.currency,
      returnActions: widget.returnActions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final shifts = _shifts;
    if (shifts == null || !_shows) return const SizedBox.shrink();
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    // **The button reserves its focus ring's gutter and the words do not**, so
    // the card pads by `space.16` and insets the words by that gutter: the
    // title, the line and the button's edge then share one left edge, at 20.
    final ring = colors.action.focusRing;
    final gutter = EdgeInsets.symmetric(horizontal: ring.width + ring.offset);
    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.s24),
      child: AppCard(
        key: const ValueKey('home-shift-card'),
        padding: EdgeInsets.all(tokens.spacing.s16),
        radius: tokens.radius.xl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: gutter,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Shift',
                      style: tokens.typography.titleMedium.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
                  ),
                  const StatusBadge(
                    key: ValueKey('home-shift-status'),
                    status: AppStatus.ok,
                    label: 'Open',
                  ),
                ],
              ),
            ),
            SizedBox(height: tokens.spacing.s16),
            Padding(
              padding: gutter,
              child: Text(
                homeShiftLine(
                  startedAt: shifts.state.shift?.startedAt,
                  memberName: widget.memberName,
                  now: widget.clock(),
                ),
                key: const ValueKey('home-shift-opened'),
                style: tokens.typography.mono.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
            SizedBox(height: tokens.spacing.s12),
            AppButton(
              key: const ValueKey('home-shift-close'),
              label: 'Close shift',
              // Under the sheet while the count runs; the sheet is the control
              // then, and a second one behind it would open a second count.
              onPressed: shifts.state.phase == TenantShiftPhase.open
                  ? () => unawaited(_close())
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// `Opened 06:30 by Amina · 2h 14m`, in the shop's own clock.
///
/// **Each part only where it is known.** A shift this device holds only a
/// local record of - opened offline, not yet confirmed - has no server start
/// time, and a start time of *now* would be a plausible wrong one; the line
/// then says only whose shift it is.
String homeShiftLine({
  required DateTime? startedAt,
  required String? memberName,
  required DateTime now,
}) {
  final name = memberName?.trim();
  final by = name == null || name.isEmpty ? '' : ' by $name';
  if (startedAt == null) return 'Opened$by';
  final clock = _clockFormat.format(startedAt.toLocal());
  return 'Opened $clock$by · ${homeShiftRunningTime(now.difference(startedAt))}';
}

/// `2h 14m`, or `14m` under the hour. Never negative: a device clock behind
/// the server's start time reads as a shift that has only just begun.
String homeShiftRunningTime(Duration span) {
  final minutes = span.isNegative ? 0 : span.inMinutes;
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return hours == 0 ? '${rest}m' : '${hours}h ${rest}m';
}

final DateFormat _clockFormat = DateFormat('HH:mm');
