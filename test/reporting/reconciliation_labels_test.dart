import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uzapay_pos/reporting/reporting.dart';
import 'package:uzapay_pos/ui/status.dart';
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
      expect(reconciliationRunStatusDetail(failed), 'Failed, retry scheduled');
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
        reconciliationDifferenceFigures(_stockShort()),
        'Its ledger expects 10, and the product records 7: 3 fewer than the '
        'ledger accounts for.',
      );
    });

    test('a variance the other way reads as more rather than fewer', () {
      final over = _anomaly(<String, Object?>{
        'productId': 'product-a',
        'anomalyType': 'stock_over_ledger',
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
        reconciliationDifferenceSubject(_stockShort()),
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

  group('one reading, two renderings', () {
    // `design.md` §11 step 8 takes the figures out of the prose, and the two
    // surfaces that draw a difference need different things: the differences
    // list wants a column of labelled numbers, and screen 21's exception report
    // draws a `Callout`, which has a `message` and no slot for a widget. Both
    // forms are declared in one `switch` for exactly the reason this module
    // exists; these are the tests that stop them drifting apart.

    test('every figure a record states also appears in its sentence', () {
      // The guard. A figure whose magnitude is nowhere in the prose form means
      // the two renderings have started describing different records. Zero is
      // excluded because the prose says "agrees" where a figure says `0`, which
      // is the one place they are deliberately not the same string.
      for (final anomaly in <TenantReconciliationAnomaly>[
        _stockShort(),
        _anomaly(<String, Object?>{
          'sourceId': 'checkout-a',
          'anomalyType': 'invalid_sale_lines',
          'invalidLineCount': 2,
        }),
        _anomaly(<String, Object?>{
          'productId': 'product-a',
          'anomalyType': 'checkpoint_chain_invalid',
          'expectedQuantity': 10,
          'observedQuantity': 10,
          'variance': 0,
        }),
        _anomaly(<String, Object?>{
          'productId': 'product-a',
          'anomalyType': 'invalid_stock_movement',
          'expectedQuantity': 10,
          'observedQuantity': 7,
          'variance': -3,
        }),
        _anomaly(<String, Object?>{
          'shiftId': 'shift-a',
          'anomalyType': 'shift_variance',
          'salesVariance': -12.5,
          'transactionVariance': 2,
        }),
      ]) {
        final sentence = reconciliationDifferenceFigures(anomaly);
        for (final figure in reconciliationDifferenceFigureLines(anomaly)) {
          final magnitude = figure.value.replaceFirst(RegExp(r'^[+-]'), '');
          if (magnitude == '0') continue;
          expect(
            sentence,
            contains(magnitude),
            reason:
                '${anomaly.kindValue}: the ${figure.slug} figure is $magnitude '
                'and the sentence does not state it',
          );
        }
      }
    });

    test('a stock variance is three figures and no prose at all', () {
      // Nothing is left over: "Its ledger expects 10, and the product records 7"
      // *is* the three figures, and a screen drawing both would report one
      // difference twice.
      final figures = reconciliationDifferenceFigureLines(_stockShort());

      expect(reconciliationDifferenceExplanation(_stockShort()), isNull);
      expect(figures.map((figure) => figure.slug), <String>[
        'expected',
        'observed',
        'variance',
      ]);
      expect(figures[0].value, '10');
      expect(figures[1].value, '7');
      // The sign is on the figure and the direction is a word beside it, so
      // neither carries the meaning on its own.
      expect(figures[2].value, '-3');
      expect(figures[2].detail, 'fewer than the ledger accounts for');
    });

    test('a variance the other way is signed the other way', () {
      final over = _anomaly(<String, Object?>{
        'productId': 'product-a',
        'anomalyType': 'stock_over_ledger',
        'expectedQuantity': 7,
        'observedQuantity': 10,
        'variance': 3,
      });

      final variance = reconciliationDifferenceFigureLines(
        over,
      ).firstWhere((figure) => figure.slug == 'variance');
      expect(variance.value, '+3');
      expect(variance.detail, 'more than the ledger accounts for');
    });

    test('a shift states both variances, including the one that agrees', () {
      // The prose said "its transaction count agrees", which is a word where the
      // other half of the same comparison was a number. Both are figures now and
      // the word moved to the line under the label.
      final shift = _anomaly(<String, Object?>{
        'shiftId': 'shift-a',
        'anomalyType': 'shift_variance',
        'salesVariance': -12.5,
        'transactionVariance': 0,
      });

      final figures = reconciliationDifferenceFigureLines(shift);
      expect(figures.map((figure) => figure.value), <String>['-12.5', '0']);
      expect(figures[0].detail, 'short of the sales recorded');
      expect(figures[1].detail, 'agrees with the sales recorded');
      expect(
        reconciliationDifferenceExplanation(shift),
        'Its closing totals disagree with the sales recorded during it.',
      );
    });

    test('a broken chain keeps its prose and states one figure', () {
      // The expected quantity is the thing that cannot be trusted, so it is
      // labelled as that rather than as half of a disagreement - and the
      // observed quantity the record also carries is deliberately not shown,
      // exactly as the sentence never mentioned it.
      final chain = _anomaly(<String, Object?>{
        'productId': 'product-a',
        'anomalyType': 'checkpoint_chain_invalid',
        'expectedQuantity': 10,
        'observedQuantity': 10,
        'variance': 0,
      });

      final figures = reconciliationDifferenceFigureLines(chain);
      expect(figures.single.slug, 'expected');
      expect(figures.single.value, '10');
      expect(figures.single.detail, 'not trustworthy as a starting point');
      expect(
        reconciliationDifferenceExplanation(chain),
        contains('This is not a quantity disagreement.'),
      );
      // The explanation drops the number the sentence carried, because the
      // figure beside it now states it.
      expect(reconciliationDifferenceExplanation(chain), isNot(contains('10')));
    });

    test('a kind that reports a refusal to read carries no figure', () {
      // Three of the eight are reports that something could not be read rather
      // than measurements, and for those the explanation is the whole sentence.
      for (final anomaly in <TenantReconciliationAnomaly>[
        _anomaly(<String, Object?>{
          'productId': 'product-a',
          'anomalyType': 'invalid_product_quantity',
        }),
        _anomaly(<String, Object?>{
          'shiftId': 'shift-a',
          'anomalyType': 'invalid_or_missing_shift',
        }),
        _anomaly(<String, Object?>{'anomalyType': 'price_drift'}),
      ]) {
        expect(reconciliationDifferenceFigureLines(anomaly), isEmpty);
        expect(
          reconciliationDifferenceExplanation(anomaly),
          reconciliationDifferenceFigures(anomaly),
        );
      }
    });

    test('a label is a column heading and is never inflected', () {
      // One unreadable line reads `Unreadable sale lines: 1`, which is the same
      // grammar the daily summary lost when its three counts stopped being a
      // sentence. The prose form still says "1 sale line", because there it is a
      // clause.
      final one = _anomaly(<String, Object?>{
        'sourceId': 'checkout-a',
        'anomalyType': 'invalid_sale_lines',
        'invalidLineCount': 1,
      });

      final figure = reconciliationDifferenceFigureLines(one).single;
      expect(figure.label, 'Unreadable sale lines');
      expect(figure.value, '1');
      expect(
        reconciliationDifferenceFigures(one),
        startsWith('1 sale line could not be read'),
      );
    });
  });

  group('provenance', () {
    test('the instant leads and the run follows, per §5.2', () {
      final dated = _anomaly(<String, Object?>{
        'productId': 'product-a',
        'jobId': 'rj_abc',
        'anomalyType': 'stock_short_of_ledger',
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

TenantReconciliationAnomaly _stockShort() => _anomaly(<String, Object?>{
  'productId': 'product-a',
  'anomalyType': 'stock_short_of_ledger',
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
