import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_application_1/ui/snackbar.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/notices.dart';
import '../support/text.dart';

void main() {
  testWidgets('a regenerated day states the verdict and its runs', (
    tester,
  ) async {
    final reader =
        _Reader(
          documents: <String, Map<String, Object?>>{
            'tenants/tenant-a/reconciliation_dirty_days/2026-07-31': _intake(),
          },
          staffNames: <String, String>{'owner-a': 'Juma'},
        )..respond(<TenantQueryDocumentSnapshot>[
          _run('dirty_1785540000000'),
          _run(
            'rj_abc',
            overrides: <String, Object?>{
              'source': 'manual',
              'mode': 'full',
              'requestedBy': 'owner-a',
            },
          ),
        ]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('reconciliation-status-verdict')),
          )
          .data,
      'The published totals cover every sale the server holds for this day.',
    );
    // **The count reads the figure, not the sentence around it.** It was `12
    // sale receipts registered for this day.` at body size, needing its own
    // singular; it is a `StatTile` at `numeric.hero` now, and the key addresses
    // that tile's own figure.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('reconciliation-status-receipts')),
          )
          .data,
      '12',
    );
    // A day with nothing wrong states no unusable-line figure at all, which is
    // the same rule the run card's failure count follows.
    expect(
      find.byKey(const ValueKey('reconciliation-status-invalid-lines')),
      findsNothing,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('reconciliation-status-published')),
          )
          .data,
      'The published totals were generated from change 3.',
    );
    expect(
      textAt(tester, 'reconciliation-status-instants'),
      'Last sale received 2026-07-31 18:00 UTC • '
      'Last regenerated 2026-08-01 02:30 UTC',
    );
    // A sale trigger names no member of the business, so the row says so
    // rather than attributing the work to a colleague.
    expect(
      textAt(tester, 'reconciliation-status-run-requested-dirty_1785540000000'),
      'Requested by the server (system:sale_trigger)',
    );
    expect(
      textAt(tester, 'reconciliation-status-run-requested-rj_abc'),
      'Requested by Juma (owner-a)',
    );
    // The state left this line for a `StatusBadge`, and the same shared card
    // draws it on the one-run route.
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('reconciliation-status-run-state-rj_abc'),
            ),
          )
          .data,
      'Requested by a person',
    );
    expect(
      tester
          .widget<StatusBadge>(
            find.byKey(
              const ValueKey('reconciliation-status-run-badge-rj_abc'),
            ),
          )
          .status,
      AppStatus.ok,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('reconciliation-status-run-progress-rj_abc'),
            ),
          )
          .data,
      'Full check • reached Finishing',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('reconciliation-status-run-attempts-rj_abc'),
            ),
          )
          .data,
      '1',
    );
    // The page is ordered by document ID, and a run ID carries no time, so each
    // run states its own instants rather than implying one from its position.
    expect(
      textAt(tester, 'reconciliation-status-run-instants-rj_abc'),
      'Completed 2026-08-01 02:31 UTC • Last updated 2026-08-01 02:31 UTC',
    );
    expect(reader.queries.single.equalityFilters, <String, Object?>{
      'localDate': '2026-07-31',
    });
  });

  testWidgets('a day the server never saw says exactly that', (tester) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('reconciliation-status-verdict')),
          )
          .data,
      'No sale has reached the server for this day, so there is nothing to '
      'reconcile.',
    );
    expect(
      find.byKey(const ValueKey('reconciliation-status-receipts')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('reconciliation-status-runs-empty')),
      findsOne,
    );
  });

  testWidgets('a failed run explains a day that is still waiting', (
    tester,
  ) async {
    final reader =
        _Reader(
          documents: <String, Map<String, Object?>>{
            'tenants/tenant-a/reconciliation_dirty_days/2026-07-31': _intake(
              overrides: <String, Object?>{
                'status': 'dirty',
                'processedRevision': 2,
                'invalidLineCount': 4,
              },
            ),
          },
        )..respond(<TenantQueryDocumentSnapshot>[
          _run(
            'rj_abc',
            overrides: <String, Object?>{
              'status': 'failed',
              'phase': 'metrics',
              'completedAt': null,
              'consecutiveFailureCount': 3,
              'lastErrorCode': 'resource-exhausted',
              'stockVarianceCount': 2,
              'rerunRequested': true,
            },
          ),
        ]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('reconciliation-status-verdict')),
          )
          .data,
      'Sales are recorded for this day that the published totals do not cover '
      'yet.',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('reconciliation-status-published')),
          )
          .data,
      'The published totals were generated from change 2; the day has since '
      'reached change 3.',
    );
    // **The figure and its consequence are two things now.** The count is the
    // second tile in the day's `StatRow`; what those lines mean stays a sentence
    // under the row, because a tile caption that ellipsises on a phone is worse
    // than a caption and a sentence.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('reconciliation-status-invalid-lines')),
          )
          .data,
      '4',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('reconciliation-status-invalid-lines-note'),
            ),
          )
          .data,
      'Those lines moved no stock and count towards no profit.',
    );
    // The server's code is shown as the server code it is, never rewritten
    // into a sentence this app would be inventing.
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('reconciliation-status-run-error-rj_abc'),
            ),
          )
          .data,
      'Server code: resource-exhausted',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('reconciliation-status-run-progress-rj_abc'),
            ),
          )
          .data,
      'Incremental • reached Daily totals',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('reconciliation-status-run-failures-rj_abc'),
            ),
          )
          .data,
      '3',
    );
    // A run that found two stock differences and no shift one states both, so
    // which of the two is zero is readable rather than inferred.
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey(
                'reconciliation-status-run-stock-differences-rj_abc',
              ),
            ),
          )
          .data,
      '2',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey(
                'reconciliation-status-run-shift-differences-rj_abc',
              ),
            ),
          )
          .data,
      '0',
    );
    expect(
      find.byKey(const ValueKey('reconciliation-status-run-rerun-rj_abc')),
      findsOne,
    );
  });

  testWidgets('a blocked day names the code the server recorded', (
    tester,
  ) async {
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{
        'tenants/tenant-a/reconciliation_dirty_days/2026-07-31': _intake(
          overrides: <String, Object?>{
            'status': 'quarantined',
            'processedRevision': null,
            'processedAt': null,
            'lastErrorCode': 'invalid_dirty_revision',
          },
        ),
      },
    )..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('reconciliation-status-verdict')),
          )
          .data,
      'The server stopped reconciling this day and recorded why.',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('reconciliation-status-error')),
          )
          .data,
      'Server code: invalid_dirty_revision',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('reconciliation-status-published')),
          )
          .data,
      'The published totals have never been generated for this day.',
    );
  });

  testWidgets('a regenerated day wears the ok badge beside its sentence', (
    tester,
  ) async {
    // Step 4: the day's standing is a `StatusBadge` as well as a sentence. The
    // sentence stays because it names *why*; the badge is what makes the
    // standing legible without reading it.
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{
        'tenants/tenant-a/reconciliation_dirty_days/2026-07-31': _intake(),
      },
    )..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    final badge = tester.widget<StatusBadge>(
      find.byKey(const ValueKey('reconciliation-status-badge')),
    );
    expect(badge.status, AppStatus.ok);
    expect(badge.label, 'Reconciled');
  });

  testWidgets('a day the server stopped on wears the problem badge', (
    tester,
  ) async {
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{
        'tenants/tenant-a/reconciliation_dirty_days/2026-07-31': _intake(
          overrides: <String, Object?>{
            'status': 'quarantined',
            'lastErrorCode': 'invalid_dirty_revision',
          },
        ),
      },
    )..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    final badge = tester.widget<StatusBadge>(
      find.byKey(const ValueKey('reconciliation-status-badge')),
    );
    expect(badge.status, AppStatus.problem);
    expect(badge.label, 'Stopped');
  });

  testWidgets('a day with no sales is neutral, not a problem', (tester) async {
    // §2.1 gives "closed" to `neutral`. A day nothing was sold on is not a
    // difference found, and painting it red would be the one-green failure in
    // the other direction.
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    final badge = tester.widget<StatusBadge>(
      find.byKey(const ValueKey('reconciliation-status-badge')),
    );
    expect(badge.status, AppStatus.neutral);
    expect(badge.label, 'No sales');
  });

  testWidgets('the two explanations start collapsed and open on a tap', (
    tester,
  ) async {
    // §5.2's argument for `Disclosure`: the writing is kept and the screen is
    // returned. Both paragraphs are this app's own words, unchanged.
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(
      find.textContaining('Nothing here can retry, cancel, or re-order a run.'),
      findsNothing,
    );
    await tester.tap(find.text('What this page can and cannot do'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Nothing here can retry, cancel, or re-order a run.'),
      findsOneWidget,
    );
  });

  testWidgets('a manager is told about the one request in a callout', (
    tester,
  ) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);
    final callable = _Callable(_queued());

    await _pump(
      tester,
      _controller(role: TenantRole.manager),
      reader,
      callable: callable,
    );

    final callout = tester.widget<Callout>(
      find.byKey(const ValueKey('reconciliation-request-forbidden')),
    );
    // `info`, not `problem`: nothing failed and nothing is hidden.
    expect(callout.status, AppStatus.info);
    expect(
      callout.message,
      startsWith('Only an owner or administrator can ask the server'),
    );
  });

  testWidgets('a cashier is denied and issues no read at all', (tester) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(role: TenantRole.cashier), reader);

    expect(
      find.byKey(const ValueKey('reconciliation-status-denied')),
      findsOne,
    );
    expect(reader.queries, isEmpty);
    expect(reader.documentPaths, isEmpty);
  });

  testWidgets('the runs page moves forward and back', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _run('rj_1'),
        _run('rj_2'),
        _run('rj_3'),
      ]);

    await _pump(tester, _controller(), reader, pageSize: 2);

    expect(
      find.byKey(const ValueKey('reconciliation-status-run-rj_1')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('reconciliation-status-run-rj_3')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('reconciliation-status-next')));
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('reconciliation-status-run-rj_3')),
      findsOne,
    );
    expect(reader.queries.last.startAfterDocumentId, 'rj_2');

    await tester.tap(
      find.byKey(const ValueKey('reconciliation-status-previous')),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('reconciliation-status-run-rj_1')),
      findsOne,
    );
  });

  testWidgets('opening another day starts its page again', (tester) async {
    final controller = _controller();
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _run('rj_1'),
        _run('rj_2'),
        _run('rj_3'),
      ]);

    await _pump(tester, controller, reader, pageSize: 2);
    await tester.tap(find.byKey(const ValueKey('reconciliation-status-next')));
    await tester.pump();
    await tester.pump();
    expect(reader.queries.last.startAfterDocumentId, 'rj_2');

    // A cursor is a position inside one exact query, so the second day must be
    // paged from its own beginning rather than from the first day's position.
    await _pump(
      tester,
      controller,
      reader,
      pageSize: 2,
      businessDate: '2026-07-30',
    );

    expect(reader.queries.last.startAfterDocumentId, isNull);
    expect(reader.queries.last.equalityFilters, <String, Object?>{
      'localDate': '2026-07-30',
    });
    expect(
      reader.documentPaths.last,
      'tenants/tenant-a/reconciliation_dirty_days/2026-07-30',
    );
  });

  testWidgets('a run that contradicts itself hides the page', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _run('rj_abc', overrides: <String, Object?>{'phase': 'stock'}),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      find.byKey(const ValueKey('reconciliation-status-failure')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('reconciliation-status-run-rj_abc')),
      findsNothing,
    );
  });

  testWidgets('opens the differences behind the counts a run reports', (
    tester,
  ) async {
    // A run says how many differences it found; this is the only route to
    // which ones, and it opens under the same session scope as every other.
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);
    await tester.tap(
      find.byKey(const ValueKey('reconciliation-status-anomalies')),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byType(TenantReconciliationAnomalyScreen), findsOneWidget);
    expect(
      reader.queries.last.collectionPath,
      'tenants/tenant-a/reconciliation_anomalies',
    );
  });

  testWidgets('the shift correction travels with that route', (tester) async {
    // The route is the only way to reach a shift difference, so a capability
    // that did not travel with it would be a callable nothing could ever call.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[])
      ..respondAnomalies(<TenantQueryDocumentSnapshot>[
        TenantQueryDocumentSnapshot(
          path: 'tenants/tenant-a/reconciliation_anomalies/shift_b',
          data: <String, Object?>{
            'tenantId': 'tenant-a',
            'shiftId': 'shift-a',
            'anomalyType': 'shift_variance',
            'salesVariance': -12.5,
            'transactionVariance': 2,
          },
        ),
      ]);

    await _pump(
      tester,
      _controller(role: TenantRole.owner),
      reader,
      amendCallable: _AmendCallable(),
    );
    await _tap(tester, 'reconciliation-status-anomalies');

    expect(
      find.byKey(const ValueKey('reconciliation-anomaly-amend-shift_b')),
      findsOneWidget,
    );
  });

  group('asking the server to reconcile', () {
    testWidgets('is not offered when no callable was injected', (tester) async {
      final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

      await _pump(tester, _controller(role: TenantRole.owner), reader);

      expect(
        find.byKey(const ValueKey('reconciliation-request-form')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('reconciliation-request-forbidden')),
        findsNothing,
      );
    });

    testWidgets('a manager is told who can ask rather than shown nothing', (
      tester,
    ) async {
      final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);
      final callable = _Callable(_queued());

      // The server's request roles are narrower than the roles that read this
      // page, which is surprising enough to state.
      await _pump(tester, _controller(), reader, callable: callable);

      expect(
        find.byKey(const ValueKey('reconciliation-request-form')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('reconciliation-request-forbidden')),
        findsOne,
      );
      expect(callable.payloads, isEmpty);
    });

    testWidgets('says the request covers the business, not the day shown', (
      tester,
    ) async {
      final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

      await _pump(
        tester,
        _controller(role: TenantRole.owner),
        reader,
        callable: _Callable(_queued()),
      );

      // The handler files a manual job under today's business date and the
      // runners take the oldest outstanding day first, so promising this day
      // would be a promise the server never made.
      //
      // A `Callout` rather than a `Disclosure`, unlike the two helper paragraphs
      // above it on the same page: this is the sentence that decides whether the
      // button below does what the person thinks it does, and a sentence you
      // have to open is a sentence nobody reads.
      final callout = tester.widget<Callout>(
        find.byKey(const ValueKey('reconciliation-request-scope')),
      );
      expect(callout.status, AppStatus.info);
      expect(
        callout.message,
        'A request covers the whole business, not the day above. The server '
        'files it under today and works through the outstanding days oldest '
        'first, so it may regenerate a different day before this one.',
      );
    });

    testWidgets('a confirmed request sends the mode and reports the job', (
      tester,
    ) async {
      final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);
      final callable = _Callable(_queued(mode: 'full'));

      await _pump(
        tester,
        _controller(role: TenantRole.admin),
        reader,
        callable: callable,
      );
      final readsBefore = reader.queries.length;

      await _choose(tester, 'Full check');
      await _tap(tester, 'reconciliation-request-submit');
      await _tap(tester, 'reconciliation-request-confirm');

      expect(callable.payloads.single, <String, Object?>{
        'tenantId': 'tenant-a',
        'mode': 'full',
        'requestId': 'reconcile-fixed-1',
      });
      expect(
        snackNotice(tester).message,
        startsWith('Queued as rj_abc.'),
      );
      // **The notice says which kind of answer it is**, which a bare sentence in
      // this position never did: "Queued as rj_abc" and "Only an owner can ask
      // for a check" were the same black paragraph until read.
      expect(
        snackNotice(tester).status,
        AppStatus.ok,
      );
      // The page is re-read so what is shown is the server's own record.
      expect(reader.queries.length, greaterThan(readsBefore));
    });

    testWidgets('a cancelled confirmation sends nothing', (tester) async {
      final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);
      final callable = _Callable(_queued());

      await _pump(
        tester,
        _controller(role: TenantRole.owner),
        reader,
        callable: callable,
      );

      await _tap(tester, 'reconciliation-request-submit');
      await _tap(tester, 'reconciliation-request-cancel');

      expect(callable.payloads, isEmpty);
      expect(
        find.byKey(const ValueKey('reconciliation-request-notice')),
        findsNothing,
      );
    });

    testWidgets('a cooldown refusal names both allowances', (tester) async {
      final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

      await _pump(
        tester,
        _controller(role: TenantRole.owner),
        reader,
        callable: _Callable.failing(
          FirebaseFunctionsException(
            code: 'resource-exhausted',
            message: 'too soon',
          ),
        ),
      );

      await _tap(tester, 'reconciliation-request-submit');
      await _tap(tester, 'reconciliation-request-confirm');

      expect(
        noticeMessage(tester, 'reconciliation-request-notice'),
        'A check of this kind was asked for too recently, so nothing was '
        'queued. The server allows one catch-up every 5 minutes and one full '
        'check every 24 hours.',
      );
      expect(
        noticeStatus(tester, 'reconciliation-request-notice'),
        AppStatus.problem,
      );
    });

    testWidgets('an unknown outcome reloads and keeps its request ID', (
      tester,
    ) async {
      final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);
      final callable = _Callable.failing(
        FirebaseFunctionsException(code: 'unavailable', message: 'down'),
      );

      await _pump(
        tester,
        _controller(role: TenantRole.owner),
        reader,
        callable: callable,
        requestIds: <String>['reconcile-first11', 'reconcile-second2'],
      );
      final readsBefore = reader.queries.length;

      await _tap(tester, 'reconciliation-request-submit');
      await _tap(tester, 'reconciliation-request-confirm');
      await _tap(tester, 'reconciliation-request-submit');
      await _tap(tester, 'reconciliation-request-confirm');

      // The job may already exist, so a second attempt must address the same
      // idempotency record rather than spend the cooldown again.
      expect(callable.payloads.map((payload) => payload['requestId']), <String>[
        'reconcile-first11',
        'reconcile-first11',
      ]);
      expect(
        noticeMessage(tester, 'reconciliation-request-notice'),
        startsWith('The result is unknown.'),
      );
      // **Not `problem`.** A job may well have been queued and the sentence's own
      // instruction is to go and look, which is what §2.1 gives `attention`.
      // Painting it red would report a failure the app has no evidence of.
      expect(
        noticeStatus(tester, 'reconciliation-request-notice'),
        AppStatus.attention,
      );
      expect(reader.queries.length, greaterThan(readsBefore));
    });

    testWidgets('a settled refusal starts the next attempt fresh', (
      tester,
    ) async {
      final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);
      final callable = _Callable.failing(
        FirebaseFunctionsException(
          code: 'resource-exhausted',
          message: 'too soon',
        ),
      );

      await _pump(
        tester,
        _controller(role: TenantRole.owner),
        reader,
        callable: callable,
        requestIds: <String>['reconcile-first11', 'reconcile-second2'],
      );

      await _tap(tester, 'reconciliation-request-submit');
      await _tap(tester, 'reconciliation-request-confirm');
      await _tap(tester, 'reconciliation-request-submit');
      await _tap(tester, 'reconciliation-request-confirm');

      // Nothing was queued, so reusing the first ID would make the retry fail
      // as a duplicate of an attempt that changed nothing.
      expect(callable.payloads.map((payload) => payload['requestId']), <String>[
        'reconcile-first11',
        'reconcile-second2',
      ]);
    });

    testWidgets('an untrustworthy answer reloads rather than claiming a job', (
      tester,
    ) async {
      final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

      await _pump(
        tester,
        _controller(role: TenantRole.owner),
        reader,
        // The handler only ever answers `queued`; anything else is refused.
        callable: _Callable(_queued(overrides: {'status': 'running'})),
      );
      final readsBefore = reader.queries.length;

      await _tap(tester, 'reconciliation-request-submit');
      await _tap(tester, 'reconciliation-request-confirm');

      expect(
        noticeMessage(tester, 'reconciliation-request-notice'),
        startsWith('The server answer could not be trusted.'),
      );
      expect(reader.queries.length, greaterThan(readsBefore));
    });
  });

  testWidgets('a tenant switch discards an outstanding load', (tester) async {
    final controller = _controller();
    final reader = _Reader.deferred();

    await _pump(tester, controller, reader, settle: false);
    expect(
      reader.documentPaths.single,
      'tenants/tenant-a/reconciliation_dirty_days/2026-07-31',
    );

    controller.open(uid: 'manager-a', membership: _membership('tenant-b'));
    await tester.pump();

    // The first business answers after the switch, so its load is discarded
    // before it can label another business's screen.
    reader.completeFirstDocument(_intake());
    await tester.pump();
    await tester.pump();
    reader.completeFirstPage(<TenantQueryDocumentSnapshot>[_run('rj_abc')]);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('reconciliation-status-run-rj_abc')),
      findsNothing,
    );

    reader.completeFirstDocument(null);
    await tester.pump();
    await tester.pump();
    reader.completeFirstPage(<TenantQueryDocumentSnapshot>[
      _run('rj_xyz', tenantId: 'tenant-b'),
    ]);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('reconciliation-status-run-rj_xyz')),
      findsOne,
    );
  });
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  int pageSize = 20,
  String businessDate = '2026-07-31',
  bool settle = true,
  _Callable? callable,
  AmendShiftSummaryCallable? amendCallable,
  List<String> requestIds = const <String>['reconcile-fixed-1'],
}) async {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var index = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantReconciliationStatusPanel(
            reader: reader,
            businessDate: businessDate,
            pageSize: pageSize,
            actions: callable == null && amendCallable == null
                ? null
                : TenantReconciliationActions(
                    requestCallable: callable,
                    amendShiftSummaryCallable: amendCallable,
                  ),
            requestIdFactory: () =>
                requestIds[index++ < requestIds.length
                    ? index - 1
                    : requestIds.length - 1],
          ),
        ),
      ),
    ),
  );
  if (!settle) return;
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// Selects one labelled segment of the mode chooser.
Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey('reconciliation-request-mode')),
      matching: find.text(label),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Map<String, Object?> _queued({
  String mode = 'incremental',
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'tenantId': 'tenant-a',
    'jobId': 'rj_abc',
    'mode': mode,
    'status': 'queued',
  };
  if (overrides != null) data.addAll(overrides);
  return data;
}

final class _Callable implements RequestReconciliationCallable {
  _Callable(this._response) : _error = null;
  _Callable.failing(Object error) : _response = null, _error = error;

  final Object? _response;
  final Object? _error;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(payload);
    final error = _error;
    if (error != null) throw error;
    return _response;
  }
}

TenantSessionController _controller({TenantRole role = TenantRole.manager}) =>
    TenantSessionController()..open(
      uid: 'manager-a',
      membership: _membership('tenant-a', role: role),
    );

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.manager,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

Map<String, Object?> _intake({
  String tenantId = 'tenant-a',
  String businessDate = '2026-07-31',
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'tenantId': tenantId,
    'businessDate': businessDate,
    'status': 'clean',
    'revision': 3,
    'processedRevision': 3,
    'saleReceiptCount': 12,
    'invalidLineCount': 0,
    'metricGeneration': 'gen-1',
    'lastReceiptAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 18)),
    'processedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
  };
  if (overrides != null) data.addAll(overrides);
  data.removeWhere((key, value) => value == null);
  return data;
}

TenantQueryDocumentSnapshot _run(
  String jobId, {
  String tenantId = 'tenant-a',
  String localDate = '2026-07-31',
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'tenantId': tenantId,
    'source': 'sale_trigger',
    'sourceKey': '1785540000000',
    'mode': 'incremental',
    'localDate': localDate,
    'requestedBy': 'system:sale_trigger',
    'status': 'completed',
    'phase': 'finalize',
    'attemptCount': 1,
    'consecutiveFailureCount': 0,
    'rerunRequested': false,
    'metricsProcessed': 1,
    'productsProcessed': 0,
    'stockVarianceCount': 0,
    'shiftsProcessed': 2,
    'shiftVarianceCount': 0,
    'completedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 31)),
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 31)),
  };
  if (overrides != null) data.addAll(overrides);
  data.removeWhere((key, value) => value == null);
  return TenantQueryDocumentSnapshot(
    path: 'tenants/$tenantId/reconciliation_jobs/$jobId',
    data: data,
  );
}

/// Granted only to prove the capability reaches the differences route; nothing
/// in this suite calls it.
final class _AmendCallable implements AmendShiftSummaryCallable {
  @override
  Future<Object?> call(Map<String, Object?> payload) async =>
      throw StateError('The status route must not correct a shift itself.');
}

final class _Reader implements TenantDataReader {
  _Reader({
    Map<String, Map<String, Object?>> documents =
        const <String, Map<String, Object?>>{},
    this.staffNames = const <String, String>{},
  }) : documents = Map<String, Map<String, Object?>>.of(documents),
       _defer = false;

  _Reader.deferred()
    : documents = <String, Map<String, Object?>>{},
      staffNames = const <String, String>{},
      _defer = true;

  final Map<String, Map<String, Object?>> documents;
  final Map<String, String> staffNames;
  final bool _defer;
  List<TenantQueryDocumentSnapshot> _page =
      const <TenantQueryDocumentSnapshot>[];
  List<TenantQueryDocumentSnapshot> _anomalyPage =
      const <TenantQueryDocumentSnapshot>[];
  final List<Completer<List<TenantQueryDocumentSnapshot>>> _pendingPages =
      <Completer<List<TenantQueryDocumentSnapshot>>>[];
  final List<(String, Completer<TenantDocumentSnapshot?>)> _pendingDocuments =
      <(String, Completer<TenantDocumentSnapshot?>)>[];
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];
  final List<String> documentPaths = <String>[];

  void respond(List<TenantQueryDocumentSnapshot> page) => _page = page;

  /// The differences list is a second collection reached from this route, so it
  /// answers separately: one shared page would let a run answer as a difference.
  void respondAnomalies(List<TenantQueryDocumentSnapshot> page) =>
      _anomalyPage = page;

  void completeFirstPage(List<TenantQueryDocumentSnapshot> page) {
    if (_pendingPages.isEmpty) return;
    _pendingPages.removeAt(0).complete(page);
  }

  /// Answers the oldest outstanding document read with its own exact path, so
  /// the repository's path proof sees what it really asked for.
  void completeFirstDocument(Map<String, Object?>? data) {
    if (_pendingDocuments.isEmpty) return;
    final (path, completer) = _pendingDocuments.removeAt(0);
    completer.complete(
      data == null ? null : TenantDocumentSnapshot(path: path, data: data),
    );
  }

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) {
    documentPaths.add(path);
    if (_defer) {
      final completer = Completer<TenantDocumentSnapshot?>();
      _pendingDocuments.add((path, completer));
      return completer.future;
    }
    final segments = path.split('/');
    if (segments.length == 4 && segments[2] == 'staff') {
      final uid = segments[3];
      final name = staffNames[uid];
      return Future<TenantDocumentSnapshot?>.value(
        name == null
            ? null
            : TenantDocumentSnapshot(
                path: path,
                data: <String, Object?>{'uid': uid, 'name': name},
              ),
      );
    }
    final data = documents[path];
    return Future<TenantDocumentSnapshot?>.value(
      data == null ? null : TenantDocumentSnapshot(path: path, data: data),
    );
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) {
    queries.add(query);
    if (_defer) {
      final completer = Completer<List<TenantQueryDocumentSnapshot>>();
      _pendingPages.add(completer);
      return completer.future;
    }
    final cursor = query.startAfterDocumentId;
    final matches = <TenantQueryDocumentSnapshot>[];
    final source = query.collectionPath.endsWith('/reconciliation_anomalies')
        ? _anomalyPage
        : _page;
    for (final snapshot in source) {
      final id = snapshot.path.split('/').last;
      if (cursor != null && id.compareTo(cursor) <= 0) continue;
      // The fake models the repository's filter contract in both directions:
      // ignoring it would let a narrowed page silently answer with another
      // day's run and prove nothing about the check that refuses one.
      final matchesFilters = query.equalityFilters.entries.every(
        (filter) => snapshot.data[filter.key] == filter.value,
      );
      if (!matchesFilters) continue;
      matches.add(snapshot);
      if (matches.length >= query.limit) break;
    }
    return Future<List<TenantQueryDocumentSnapshot>>.value(matches);
  }
}
