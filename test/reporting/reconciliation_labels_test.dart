import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

/// The vocabulary four reconciliation surfaces state their records with.
///
/// Tested directly rather than through the panels: it is the shared authority for
/// eight difference kinds and six run states, and asserting each of the fourteen
/// through a widget pump would be fourteen pumps to check a string. What the
/// panels assert is that they read *this*, which is the part a pump can see.
void main() {
  group('one instant format for the family', () {
    test('a difference and a run now state the same instant the same way', () {
      // The differences list used to render `toIso8601String()` and the run card
      // a UTC minute, on two pages that link to each other.
      final at = DateTime.utc(2026, 8, 1, 2, 30, 45, 123);

      expect(reconciliationInstant(at), '2026-08-01 02:30 UTC');
    });

    test('a local instant is stated in UTC, not in the device zone', () {
      // Every other instant in this app is UTC and a business is not necessarily
      // in the reader's zone.
      final at = DateTime.utc(2026, 8, 1, 23, 5).toLocal();

      expect(reconciliationInstant(at), '2026-08-01 23:05 UTC');
    });
  });

  group('a run has a standing', () {
    test('completed is reconciled and says nothing more than the word', () {
      final run = _run();

      expect(reconciliationRunStatus(run), AppStatus.ok);
      expect(reconciliationRunStatusWord(run), 'Completed');
      expect(reconciliationRunStatusDetail(run), isNull);
    });

    test('queued and running are awaiting rather than wrong', () {
      final queued = _run(
        overrides: <String, Object?>{
          'status': 'queued',
          'phase': 'intake',
          'attemptCount': 0,
          'completedAt': null,
        },
      );
      final running = _run(
        overrides: <String, Object?>{
          'status': 'running',
          'phase': 'stock',
          'completedAt': null,
        },
      );

      expect(reconciliationRunStatus(queued), AppStatus.attention);
      expect(reconciliationRunStatus(running), AppStatus.attention);
      expect(reconciliationRunStatusDetail(queued), isNull);
    });

    test('failed and quarantined share a colour and never a word', () {
      // §2.1 has no row for "failed, but a retry is scheduled", and §2.1's own
      // design is a container plus an icon plus a word: two states sharing a
      // colour while differing in the word is the system working.
      final failed = _run(
        overrides: <String, Object?>{
          'status': 'failed',
          'phase': 'stock',
          'consecutiveFailureCount': 1,
          'lastErrorCode': 'aborted',
          'completedAt': null,
        },
      );
      final quarantined = _run(
        overrides: <String, Object?>{
          'status': 'quarantined',
          'lastErrorCode': 'repeated_failure',
        },
      );

      expect(reconciliationRunStatus(failed), AppStatus.problem);
      expect(reconciliationRunStatus(quarantined), AppStatus.problem);
      expect(reconciliationRunStatusWord(failed), 'Failed');
      expect(reconciliationRunStatusWord(quarantined), 'Stopped');
      // The detail is the enum's own label, shown only where it says more than
      // the word. Nothing here is invented copy.
      expect(
        reconciliationRunStatusDetail(failed),
        'Failed, retry scheduled',
      );
      expect(
        reconciliationRunStatusDetail(quarantined),
        'Stopped after repeated failures',
      );
    });

    test('an unmodelled state is info, and the stored value is the detail', () {
      // The day page's own decision, applied here rather than §2.1's
      // "unreadable" row: a server deploy that records a state this app does not
      // model is not evidence of anything wrong.
      final run = _run(overrides: <String, Object?>{'status': 'archived'});

      expect(reconciliationRunStatus(run), AppStatus.info);
      expect(reconciliationRunStatusWord(run), 'Unrecognised');
      expect(reconciliationRunStatusDetail(run), 'archived');
    });
  });

  group('a difference has no standing', () {
    test('every difference is a problem, which is why none wears a badge', () {
      // The rule the `RecordList` sweep applied to four record families: a list
      // where every row wears a badge is a list with no signal in it. What the
      // status is for here is the container a notice is drawn in.
      expect(reconciliationDifferenceStatus, AppStatus.problem);
    });
  });

  group('one wording per kind', () {
    test('a broken chain is not described as a quantity disagreement', () {
      // **The divergence this module was written for.** The differences list
      // described all three stock kinds with the stock-variance sentence, so a
      // broken chain whose quantities agree read as "0 fewer than the ledger
      // accounts for" - a record that exists because there is a difference,
      // stating that there is none.
      final chain = _anomaly(<String, Object?>{
        'productId': 'product-a',
        'anomalyType': 'checkpoint_chain_invalid',
        'expectedQuantity': 10,
        'observedQuantity': 10,
        'variance': 0,
      });

      final figures = reconciliationDifferenceFigures(chain);
      expect(figures, contains('does not join up'));
      expect(figures, contains('This is not a quantity disagreement.'));
      expect(figures, isNot(contains('fewer')));
    });

    test('an unreadable ledger entry names the ledger, not the quantity', () {
      final movement = _anomaly(<String, Object?>{
        'productId': 'product-a',
        'anomalyType': 'invalid_stock_movement',
        'expectedQuantity': 10,
        'observedQuantity': 7,
        'variance': -3,
      });

      expect(
        reconciliationDifferenceFigures(movement),
        contains('does not account for everything that moved'),
      );
    });

    test('a stock variance states both figures and their difference', () {
      expect(
        reconciliationDifferenceFigures(_stockVariance()),
        'Its ledger expects 10, and the product records 7: 3 fewer than the '
        'ledger accounts for.',
      );
    });

    test('a variance the other way reads as more rather than fewer', () {
      final over = _anomaly(<String, Object?>{
        'productId': 'product-a',
        'anomalyType': 'stock_variance',
        'expectedQuantity': 7,
        'observedQuantity': 10,
        'variance': 3,
      });

      expect(
        reconciliationDifferenceFigures(over),
        contains('3 more than the ledger accounts for'),
      );
    });

    test('one unreadable sale line is singular', () {
      final one = _anomaly(<String, Object?>{
        'sourceId': 'checkout-a',
        'anomalyType': 'invalid_sale_lines',
        'invalidLineCount': 1,
      });

      expect(
        reconciliationDifferenceFigures(one),
        '1 sale line could not be read, so they moved no stock.',
      );
    });

    test('a shift that agrees on one figure and not the other says both', () {
      final shift = _anomaly(<String, Object?>{
        'shiftId': 'shift-a',
        'anomalyType': 'shift_variance',
        'salesVariance': -12.5,
        'transactionVariance': 0,
      });

      expect(
        reconciliationDifferenceFigures(shift),
        'Its sales total is 12.5 short and its transaction count agrees against '
        'the sales recorded during it.',
      );
    });

    test('an unmodelled kind is named, and says it cannot be explained', () {
      // Both halves matter: hiding a real difference would be far worse than
      // naming it, and the list used to state the kind and then say nothing at
      // all about the record.
      final other = _anomaly(<String, Object?>{'anomalyType': 'price_drift'});

      expect(
        reconciliationDifferenceKindLabel(other),
        'Unrecognised difference: price_drift',
      );
      expect(
        reconciliationDifferenceFigures(other),
        'What this difference means is not something this version of the app '
        'can explain.',
      );
    });

    test('the subject is the ID the rest of the app attributes by', () {
      expect(
        reconciliationDifferenceSubject(_stockVariance()),
        'Product product-a',
      );
      expect(
        reconciliationDifferenceSubject(
          _anomaly(<String, Object?>{
            'shiftId': 'shift-a',
            'anomalyType': 'invalid_or_missing_shift',
          }),
        ),
        'Shift shift-a',
      );
      expect(
        reconciliationDifferenceSubject(
          _anomaly(<String, Object?>{'anomalyType': 'price_drift'}),
        ),
        'This business',
      );
    });
  });

  group('provenance', () {
    test('the instant leads and the run follows, per §5.2', () {
      final dated = _anomaly(<String, Object?>{
        'productId': 'product-a',
        'jobId': 'rj_abc',
        'anomalyType': 'stock_variance',
        'expectedQuantity': 10,
        'observedQuantity': 7,
        'variance': -3,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 2, 2, 31)),
      });

      expect(
        reconciliationDifferenceProvenance(dated),
        'First recorded 2026-08-01 02:30 UTC, last seen 2026-08-02 02:31 UTC, '
        'found by run rj_abc.',
      );
    });

    test('a record with only a run still opens with a capital', () {
      // Found by a test: composing the sentence from a capitalised leading
      // fragment and lowercase followers made this read "found by run rj_abc."
      final runOnly = _anomaly(<String, Object?>{
        'productId': 'product-a',
        'jobId': 'rj_abc',
        'anomalyType': 'invalid_product_quantity',
      });

      expect(
        reconciliationDifferenceProvenance(runOnly),
        'Found by run rj_abc.',
      );
    });

    test('a record with neither states that rather than leaving a gap', () {
      final bare = _anomaly(<String, Object?>{
        'productId': 'product-a',
        'anomalyType': 'invalid_product_quantity',
      });

      expect(
        reconciliationDifferenceProvenance(bare),
        'No run or time was recorded for this difference.',
      );
    });
  });
}

TenantReconciliationAnomaly _stockVariance() => _anomaly(<String, Object?>{
  'productId': 'product-a',
  'anomalyType': 'stock_variance',
  'expectedQuantity': 10,
  'observedQuantity': 7,
  'variance': -3,
});

TenantReconciliationAnomaly _anomaly(Map<String, Object?> data) =>
    TenantReconciliationAnomaly.fromDocument(
      path: 'tenants/tenant-a/reconciliation_anomalies/an_abc',
      data: <String, Object?>{'tenantId': 'tenant-a', ...data},
    );

TenantReconciliationRun _run({Map<String, Object?>? overrides}) {
  final data = <String, Object?>{
    'tenantId': 'tenant-a',
    'source': 'nightly',
    'sourceKey': 'nightly:2026-07-31',
    'mode': 'incremental',
    'localDate': '2026-07-31',
    'requestedBy': 'system:nightly',
    'status': 'completed',
    'phase': 'finalize',
    'attemptCount': 1,
    'consecutiveFailureCount': 0,
    'rerunRequested': false,
    'metricsProcessed': 1,
    'productsProcessed': 0,
    'stockVarianceCount': 0,
    'shiftsProcessed': 2,
    'shiftVarianceCount': 1,
    'completedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 31)),
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 31)),
  };
  if (overrides != null) data.addAll(overrides);
  data.removeWhere((key, value) => value == null);
  return TenantReconciliationRun.fromDocument(
    path: 'tenants/tenant-a/reconciliation_jobs/rj_abc',
    data: data,
  );
}
