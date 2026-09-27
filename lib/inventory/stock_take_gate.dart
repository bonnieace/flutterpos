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
library;

import 'dart:async';

import 'package:flutter/material.dart';

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
    this.businessDate,
  });

  final TenantStockTakeScheduleLoader loadSchedule;
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
    if (!mounted) return;
    final businessDate = _businessDate;
    final schedule = published.schedule;
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
    setState(() {
      _outstanding = outstanding;
      _enforcement = schedule.enforcement;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _raiseIfNeeded());
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
      builder: (dialogContext) => _StockTakeGateDialog(
        scope: _outstanding.first,
        remaining: _outstanding.length,
        blocking: blocking,
        onCount: () => Navigator.of(dialogContext).pop(true),
        onLater: blocking ? null : () => Navigator.of(dialogContext).pop(false),
      ),
    );
    if (!mounted) {
      _gateUp = false;
      return;
    }
    _gateUp = false;
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
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (routeContext) => TenantSessionScope(
          controller: sessions,
          child: widget.countRoute(routeContext, scope),
        ),
      ),
    );
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
                Text(
                  'A stock count is due today and this register is waiting for it. '
                  'It takes as long as it takes to walk the shelf; nothing else '
                  'is held up once you have handed it in.',
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
        content: Text(
          remaining > 1
              ? 'You have $remaining counts to take today. Start with the '
                    'first; the others follow.'
              : blocking
              ? 'This register is waiting for it. Count the shelf and hand the '
                    'figures in, and the register opens.'
              : 'Count the shelf when you get a moment and hand the figures '
                    'in. Nothing is held up in the meantime.',
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
