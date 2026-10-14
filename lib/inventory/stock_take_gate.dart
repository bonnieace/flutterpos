/// The count a person owes before they sell, on the days they owe one.
///
/// **It sits inside the shift gate, not beside it.** `TenantShiftGate` renders
/// its child only once a shift is established, so wrapping the till in this and
/// that in the shift gate means the question about counting is asked *after* the
/// question about the shift - which is the order a person expects and costs no
/// change to the shift code.
///
/// **It fails open, deliberately and in three places.** A schedule that cannot
/// be read, a business date that cannot be parsed, and an enforcement setting
/// nobody recognises all mean "no count is due". Holding a shop out of its own
/// register because a configuration document was unreadable would be a far worse
/// failure than a missed count, and the till is the one screen in this app that
/// must always open.
///
/// **The obligation clears on handing in, not on approval or on drain.** See
/// `TenantStockTakeObligationSource`.
///
/// **This device's copy first, then the server's, since 2026-09-29.** The gate
/// used to read the schedule from this device alone, and nothing on a
/// cashier's path ever fetched it, so the schedule reached a phone only if an
/// owner or administrator had opened *Stock counts* on that same phone - and
/// then only as it stood that day. Two emulators signed in as one owner showed
/// it: the phone that saved the schedule was asked to count, the other was
/// not; and once the schedule was set back to *Nothing*, the other went on
/// asking. The copy still answers first, so the till opens with no signal; the
/// server's answer follows and corrects it without holding anything up.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import '../ui/states.dart';

import '../checkout/checkout_draft.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/routes.dart';
import '../ui/tokens.dart';
import 'stock_take.dart';
import 'stock_take_draft_store.dart';
import 'stock_take_schedule.dart';
import '../observability/app_telemetry.dart';

/// Builds the counting screen for one scope, so this file need not know how.
typedef TenantStockTakeRouteBuilder =
    Widget Function(BuildContext context, TenantStockTakeScope scope);

/// Reads the business's counting schedule for this session.
typedef TenantStockTakeScheduleLoader =
    Future<TenantPublishedStockTakeSchedule> Function(TenantSession session);

final class TenantStockTakeGate extends StatefulWidget {
  const TenantStockTakeGate({
    super.key,
    required this.loadSchedule,
    required this.obligations,
    required this.countRoute,
    required this.child,
    this.refreshSchedule,
    this.businessDate,
  });

  /// The schedule as this device holds it. Answers first, with no signal.
  final TenantStockTakeScheduleLoader loadSchedule;

  /// The schedule as the server holds it, read after [loadSchedule] has
  /// answered and never waited on. Absent, the device's copy is all there is.
  final TenantStockTakeScheduleLoader? refreshSchedule;
  final TenantStockTakeObligationSource obligations;
  final TenantStockTakeRouteBuilder countRoute;
  final String Function()? businessDate;

  /// The till.
  final Widget child;

  @override
  State<TenantStockTakeGate> createState() => _TenantStockTakeGateState();
}

class _TenantStockTakeGateState extends State<TenantStockTakeGate> {
  TenantSessionController? _sessions;

  /// What this person still owes today, nearest first. Empty until the schedule
  /// has been read, which is why nothing is ever blocked before then.
  List<TenantStockTakeScope> _outstanding = const <TenantStockTakeScope>[];
  TenantStockTakeEnforcement _enforcement = TenantStockTakeEnforcement.off;

  /// Whether the dialog is up, so a rebuild does not stack a second one.
  bool _gateUp = false;

  /// Set by *Not now*, and only for this visit to the till. A prompt that could
  /// be dismissed for good would be a setting, and the setting is `off`.
  bool _declined = false;

  /// The dialog's own context while it is up, so a newer schedule can take
  /// back a question the older one asked.
  BuildContext? _dialogContext;

  /// Set when the dialog is closed because the schedule changed under it,
  /// which is neither *Not now* nor a decision to leave.
  bool _withdrawn = false;

  /// Whether the counting screen is open over the till. The server's answer
  /// can land while it is, and must not raise a question over it.
  bool _counting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sessions = TenantSessionScope.of(context);
    if (identical(sessions, _sessions)) return;
    _sessions = sessions;
    unawaited(_refresh());
  }

  String get _businessDate =>
      widget.businessDate?.call() ??
      checkoutBusinessDate(DateTime.now().toUtc());

  /// Reads the schedule and works out what is still owed.
  ///
  /// This device's copy answers first; the server's answer, when there is one,
  /// is applied after it. See this file's header for why both.
  Future<void> _refresh() async {
    final session = _sessions?.session;
    if (session == null) return;
    TenantPublishedStockTakeSchedule published;
    try {
      published = await widget.loadSchedule(session);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'inventory.stock_take_schedule_read',
      );
      // Fail open. See this file's header: the till must always open.
      published = const TenantPublishedStockTakeSchedule.absent();
    }
    if (!mounted || !_isCurrent(session)) return;
    _apply(session, published.schedule);

    final refresh = widget.refreshSchedule;
    if (refresh == null) return;
    final TenantPublishedStockTakeSchedule fresh;
    try {
      fresh = await refresh(session);
    } catch (_) {
      // **Not reported.** With no signal this read fails every time, and that
      // is the ordinary state of a till rather than a fault: the answer this
      // device already had stands.
      return;
    }
    if (!mounted || !_isCurrent(session)) return;
    _apply(session, fresh.schedule);
  }

  /// Whether [session] is still the one this gate is guarding.
  bool _isCurrent(TenantSession session) {
    final current = _sessions?.session;
    return current != null &&
        current.uid == session.uid &&
        current.tenantId == session.tenantId &&
        current.epoch == session.epoch;
  }

  /// Works out what [schedule] still asks of this person, and acts on it.
  void _apply(TenantSession session, TenantStockTakeSchedule schedule) {
    final businessDate = _businessDate;
    final satisfied = widget.obligations.satisfiedScopes(
      uid: session.uid,
      tenantId: session.tenantId,
      businessDate: businessDate,
    );
    final outstanding = <TenantStockTakeScope>[
      for (final scope in schedule.scopesFor(
        uid: session.uid,
        businessDate: businessDate,
      ))
        if (!satisfied.contains(scope.scopeKey)) scope,
    ];
    final changed =
        schedule.enforcement != _enforcement ||
        !_sameScopes(outstanding, _outstanding);
    setState(() {
      _outstanding = outstanding;
      _enforcement = schedule.enforcement;
    });
    // **A question about a schedule that has since changed is taken back**
    // rather than left standing. The server can answer after this device's
    // copy has already asked - a count switched off, or turned from a prompt
    // into a hold - and a dialog that went on saying the old thing would be
    // the stale answer this read exists to correct. Its handler raises
    // whatever the new schedule asks for.
    if (changed && _gateUp) {
      _withdrawGate();
      return;
    }
    if (_counting) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _raiseIfNeeded());
  }

  static bool _sameScopes(
    List<TenantStockTakeScope> a,
    List<TenantStockTakeScope> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].scopeKey != b[i].scopeKey) return false;
    }
    return true;
  }

  void _withdrawGate() {
    final dialog = _dialogContext;
    if (dialog == null || !dialog.mounted) return;
    _withdrawn = true;
    Navigator.of(dialog).pop();
  }

  bool get _blocking =>
      _enforcement == TenantStockTakeEnforcement.block &&
      _outstanding.isNotEmpty;

  bool get _prompting =>
      _enforcement == TenantStockTakeEnforcement.prompt &&
      _outstanding.isNotEmpty &&
      !_declined;

  /// Raised from a callback rather than from `build`, because showing a route
  /// during a build is the one thing `Navigator` refuses outright.
  Future<void> _raiseIfNeeded() async {
    if (!mounted || _gateUp) return;
    if (!_blocking && !_prompting) return;
    _gateUp = true;
    final blocking = _blocking;
    final answer = await showAppDialog<bool>(
      context,
      builder: (dialogContext) {
        _dialogContext = dialogContext;
        return _StockTakeGateDialog(
          scope: _outstanding.first,
          remaining: _outstanding.length,
          blocking: blocking,
          onCount: () => Navigator.of(dialogContext).pop(true),
          onLater: blocking
              ? null
              : () => Navigator.of(dialogContext).pop(false),
        );
      },
    );
    _dialogContext = null;
    if (!mounted) {
      _gateUp = false;
      return;
    }
    _gateUp = false;
    if (_withdrawn) {
      _withdrawn = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _raiseIfNeeded());
      return;
    }
    if (answer == true) {
      await _count(_outstanding.first);
    } else if (!blocking) {
      setState(() => _declined = true);
    } else {
      // A blocking gate cannot be dismissed into the till, so a dismissal is a
      // decision to leave rather than to sell.
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  Future<void> _count(TenantStockTakeScope scope) async {
    final sessions = _sessions;
    if (sessions == null || !mounted) return;
    _counting = true;
    try {
      await Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (routeContext) => TenantSessionScope(
            controller: sessions,
            child: widget.countRoute(routeContext, scope),
          ),
        ),
      );
    } finally {
      _counting = false;
    }
    if (!mounted) return;
    // Back from the counting screen: whether they finished decides whether the
    // question comes again, and the obligation record is what says so.
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_blocking) return widget.child;
    // **The till is not drawn at all while a count is owed and enforced.**
    // Drawing it behind the modal would put a sellable screen one dismissal
    // away from the thing that is meant to be preventing the sale.
    return PopScope(
      canPop: true,
      child: _StockTakeHeld(
        scope: _outstanding.first,
        onCount: () => _count(_outstanding.first),
      ),
    );
  }
}

/// What a person sees when the till is held for a count.
final class _StockTakeHeld extends StatelessWidget {
  const _StockTakeHeld({required this.scope, required this.onCount});

  final TenantStockTakeScope scope;
  final VoidCallback onCount;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Scaffold(
      key: const ValueKey('stock-take-gate-held'),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing.s20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Count first, then sell',
                  style: tokens.typography.titleLarge,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: tokens.spacing.s12),
                IllustratedMessage(
                  illustration: 'stock-count.svg',
                  message:
                      'Count and submit the stock to unlock this register.',
                  style: tokens.typography.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: tokens.spacing.s20),
                AppButton(
                  key: const ValueKey('stock-take-gate-count'),
                  label: 'Start counting',
                  tier: AppButtonTier.primary,
                  onPressed: onCount,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _StockTakeGateDialog extends StatelessWidget {
  const _StockTakeGateDialog({
    required this.scope,
    required this.remaining,
    required this.blocking,
    required this.onCount,
    this.onLater,
  });

  final TenantStockTakeScope scope;
  final int remaining;
  final bool blocking;
  final VoidCallback onCount;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return PopScope(
      // A blocking gate has one way through it. A prompt may be waved away, and
      // the system back gesture is a perfectly good way to say *Not now*.
      canPop: !blocking,
      child: AppDialog(
        title: 'A stock count is due',
        centerTitle: true,
        content: IllustratedMessage(
          illustration: 'stock-count.svg',
          message: remaining > 1
              ? '$remaining counts due today. Start with the first.'
              : blocking
              ? 'Count and submit the stock to unlock this register.'
              : 'Count when ready. You can keep selling.',
          style: tokens.typography.bodyMedium,
        ),
        actions: <Widget>[
          if (onLater != null)
            AppButton(
              key: const ValueKey('stock-take-gate-later'),
              label: 'Not now',
              tier: AppButtonTier.tertiary,
              onPressed: onLater,
            ),
          AppButton(
            key: const ValueKey('stock-take-gate-start'),
            label: 'Start counting',
            tier: AppButtonTier.primary,
            onPressed: onCount,
          ),
        ],
      ),
    );
  }
}
