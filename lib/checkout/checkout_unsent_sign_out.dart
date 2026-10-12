/// Signing out of a browser that still holds sales the server has not seen.
///
/// **A browser is the one place a sign-out puts unsent sales at risk.** The
/// outbox outlives a sign-out everywhere, and on a phone nothing else reaches
/// it. In a browser it lives in site data, which a person at a shared computer
/// clears as a matter of course once they have signed out - and with it every
/// sale this till could not yet send. So the browser asks first; a phone does
/// not.
library;

import 'package:flutter/widgets.dart';

import '../ui/dialogs.dart';
import 'checkout_outbox.dart';

/// How many of this person's sales, in this business, only this device holds.
///
/// The states the home's "not sent" figure counts, and for the same reason:
/// [CheckoutOutboxState.confirmed] is on the server already.
Future<int> unsentSalesFor(
  HiveCheckoutOutbox outbox, {
  required String uid,
  required String tenantId,
}) async {
  final records = await outbox.recordsForSession(uid: uid, tenantId: tenantId);
  return records.where((record) => _unsent.contains(record.state)).length;
}

const Set<CheckoutOutboxState> _unsent = <CheckoutOutboxState>{
  CheckoutOutboxState.savedOffline,
  CheckoutOutboxState.submitting,
  CheckoutOutboxState.awaitingConfirmation,
};

/// Asks whether to sign out anyway, and answers true only for a yes.
///
/// Staying is the safe answer, so a tap outside the dialog stays.
Future<bool> confirmSignOutWithUnsentSales(
  BuildContext context, {
  required int unsent,
}) {
  final one = unsent == 1;
  return showConfirmDialog(
    context,
    title: one
        ? 'Sign out with a sale not sent?'
        : 'Sign out with $unsent sales not sent?',
    consequence: one
        ? 'It has not reached the server yet. It is kept in this browser and '
              'sends the next time you sign in here while online. If this '
              'browser’s data is cleared before then, it is lost.'
        : 'They have not reached the server yet. They are kept in this '
              'browser and send the next time you sign in here while online. '
              'If this browser’s data is cleared before then, they are lost.',
    confirmLabel: 'Sign out anyway',
    cancelLabel: 'Stay signed in',
    confirmKey: const ValueKey('sign-out-unsent-confirm'),
    cancelKey: const ValueKey('sign-out-unsent-stay'),
  );
}
