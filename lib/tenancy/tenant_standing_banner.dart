/// What a business is told about its own standing.
///
/// **Only a self-serve request has anything to say here.** An approved business
/// draws nothing at all - a banner on every screen of every shop, saying the
/// unremarkable, is a banner nobody reads by the second day. The two states this
/// speaks for are the two a shopkeeper cannot otherwise find out about:
///
/// - **Trading on a deadline.** The window shuts by itself and nothing else in
///   the app would mention it until the moment a sale stopped working.
/// - **The deadline passed.** Every write is refused from here, and a screen
///   full of controls that quietly fail is worse than a screen that says why.
///
/// **It states the consequence, not just the state.** "Trial" on its own asks
/// the reader to guess what happens on Friday; the sentence says the records
/// survive and the trading stops, because that is the thing worth knowing
/// before deciding whether to keep ringing sales into it.
library;

import 'package:flutter/material.dart';

import '../ui/status.dart';
import '../ui/tokens.dart';
import 'tenant_access.dart';

/// The banner for [access]'s standing, or nothing where there is none to draw.
final class TenantStandingBanner extends StatelessWidget {
  const TenantStandingBanner({super.key, required this.access, this.clock});

  /// Taken as [TenantAccess] rather than as a session or a membership, because
  /// both of those carry one and neither is available on every surface that
  /// needs to draw this.
  final TenantAccess access;

  /// Injected so a test can stand at a chosen distance from the deadline.
  final DateTime Function()? clock;

  DateTime _now() => (clock ?? DateTime.now)().toUtc();

  @override
  Widget build(BuildContext context) {
    final now = _now();
    final standing = access.standingAt(now);
    final until = access.provisionalUntil;

    return switch (standing) {
      TenantStanding.approved || TenantStanding.closed => const SizedBox.shrink(),
      TenantStanding.provisional => Padding(
        padding: EdgeInsets.only(
          bottom: AppTokens.componentOf(context).spacing.s16,
        ),
        child: Callout(
          key: const ValueKey('tenant-standing-provisional'),
          // §2.1's `attention` is "unreconciled, pending, awaiting", which is
          // exactly what an unapproved business is. Not `problem`: nothing is
          // wrong, and nothing has been refused.
          status: AppStatus.attention,
          icon: Icons.schedule_outlined,
          title: 'This business has not been approved yet',
          message:
              '${_remaining(until, now)} left to trade. After that you will '
              'still see everything you recorded, but you will not be able to '
              'ring up a sale until the business is approved.',
        ),
      ),
      TenantStanding.lapsed => Padding(
        padding: EdgeInsets.only(
          bottom: AppTokens.componentOf(context).spacing.s16,
        ),
        child: const Callout(
          key: ValueKey('tenant-standing-lapsed'),
          status: AppStatus.problem,
          icon: Icons.lock_clock_outlined,
          title: 'Trading has stopped',
          message:
              'The trial period ran out before this business was approved. '
              'Everything it recorded is still here to read. Selling, stock '
              'and settings come back as soon as it is approved.',
        ),
      ),
    };
  }
}

/// `3 days`, `7 hours`, `20 minutes` - the largest unit that is still true.
///
/// **Rounded down, never up.** A window with 47 hours in it says two days
/// rather than three: a deadline a shopkeeper plans around must never arrive
/// earlier than the words led them to expect.
String tenantProvisionalRemaining(DateTime until, DateTime now) =>
    _remaining(until, now);

String _remaining(DateTime? until, DateTime now) {
  if (until == null) return 'No time';
  final left = until.toUtc().difference(now.toUtc());
  if (left.isNegative || left == Duration.zero) return 'No time';
  if (left.inDays >= 1) {
    return '${left.inDays} ${left.inDays == 1 ? 'day' : 'days'}';
  }
  if (left.inHours >= 1) {
    return '${left.inHours} ${left.inHours == 1 ? 'hour' : 'hours'}';
  }
  final minutes = left.inMinutes;
  // Under a minute still reads as one: "0 minutes left to trade" is a sentence
  // that has already stopped being true by the time it is read.
  final shown = minutes < 1 ? 1 : minutes;
  return '$shown ${shown == 1 ? 'minute' : 'minutes'}';
}
