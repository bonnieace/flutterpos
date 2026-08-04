import 'dart:async';

/// One step of the automatic checkout pipeline.
typedef CheckoutSyncStep = Future<void> Function();

/// One pass of the automatic checkout pipeline, in the order that settles
/// evidence.
///
/// The order is the entire content of this class, which is why it is a tested
/// unit rather than a closure in the composition root:
///
/// 1. **Recover first.** An uncertain prior attempt must be settled before any
///    new batch is committed, so a sale is never submitted twice.
/// 2. **Submit.** A durable `saved_offline` record is committed.
/// 3. **Recover again.** A commit leaves the record `awaiting_confirmation`, and
///    only a confirmation read against the server may conclude that the sale is
///    there. Without this second pass the record stays unconfirmed until some
///    later trigger - a reconnect, or an app restart - and a shift **cannot be
///    closed while any sale is unsettled**. That was observed on a real device:
///    a sale reached Firestore immediately and the till still refused to close
///    its shift until the app was restarted.
/// 4. **Refresh derived data last.** The catalog cache never gates evidence, and
///    a sale saved at the till does not need the whole product list re-read.
///
/// Running recovery twice is safe and cheap: it is a bounded scan of the local
/// outbox, it confirms only what the server can be read to hold, and a record it
/// cannot settle is left exactly as it was for the next pass.
final class CheckoutSyncPass {
  CheckoutSyncPass({
    required CheckoutSyncStep recover,
    required CheckoutSyncStep submit,
    required CheckoutSyncStep refreshCatalog,
    required void Function() reportEvidenceChanged,
  }) : _recover = recover,
       _submit = submit,
       _refreshCatalog = refreshCatalog,
       _reportEvidenceChanged = reportEvidenceChanged;

  final CheckoutSyncStep _recover;
  final CheckoutSyncStep _submit;
  final CheckoutSyncStep _refreshCatalog;
  final void Function() _reportEvidenceChanged;

  /// Runs one pass.
  ///
  /// [refreshDerivedData] is false for a pass a saved sale asked for: refreshing
  /// the catalog there would make a till pay for every product in the business
  /// on every customer.
  Future<void> run({required bool refreshDerivedData}) async {
    try {
      await _recover();
      await _submit();
      // The confirmation half of the pipeline. See the ordering note above: a
      // committed sale is not a settled one.
      await _recover();
      if (refreshDerivedData) await _refreshCatalog();
    } finally {
      // Whatever the pass settled - or got part-way through before failing - is
      // now worth re-reading. This is deliberately not a second sync request: a
      // pass must never ask for another pass.
      _reportEvidenceChanged();
    }
  }
}
