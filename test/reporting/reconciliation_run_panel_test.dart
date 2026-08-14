import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('one run is read by its own exact path, not searched for', (
    tester,
  ) async {
    // A difference names the run that found it and carries no business date, so
    // the day page cannot be reached from one. This route is the only way in, and
    // it addresses the run rather than querying for it: a query cannot tell "no
    // such run" apart from "a run this session may not read".
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{_jobPath: _job()},
    );

    await _pump(tester, _controller(), reader);

    expect(reader.documentPaths, <String>[_jobPath]);
    expect(reader.queries, isEmpty);
    expect(_text(tester, 'reconciliation-run-title'), 'Run rj_abc');
    // The state left the title line for a `StatusBadge`; what is left of the
    // line is what the record is about.
    expect(
      _text(tester, 'reconciliation-status-run-state-rj_abc'),
      'Nightly sweep',
    );
    // **The attempt count left this line in step 8** and is a figure of its own
    // below. What is left is the two facts no figure can state - which mode ran,
    // and how far it reached - and the singular the sentence needed went with
    // the number, exactly as it did on the daily summary.
    expect(
      _text(tester, 'reconciliation-status-run-progress-rj_abc'),
      'Incremental • reached ${TenantReconciliationRunPhase.finalize.label}',
    );
    expect(_text(tester, 'reconciliation-status-run-attempts-rj_abc'), '1');
    expect(
      _text(tester, 'reconciliation-status-run-instants-rj_abc'),
      'Completed 2026-08-01 02:31 UTC • Last updated 2026-08-01 02:31 UTC',
    );
  });

  testWidgets('a run that never failed shows no failure count at all', (
    tester,
  ) async {
    // A `0` on every run that has never failed is a column of zeroes carrying no
    // signal, which is the argument the tender split already makes for leaving
    // out an empty bucket.
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{_jobPath: _job()},
    );

    await _pump(tester, _controller(), reader);

    expect(
      find.byKey(const ValueKey('reconciliation-status-run-failures-rj_abc')),
      findsNothing,
    );
    expect(_text(tester, 'reconciliation-status-run-attempts-rj_abc'), '1');
  });

  testWidgets('the run states its day without claiming the difference is one', (
    tester,
  ) async {
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{_jobPath: _job()},
    );

    await _pump(tester, _controller(), reader);

    // What is left beside the record once the page-invariant half of this
    // paragraph moved into the page's own explanation: a fact about this run.
    expect(
      _text(tester, 'reconciliation-run-day'),
      'This run covered 2026-07-31.',
    );
    expect(
      find.textContaining('stays listed until it is resolved'),
      findsNothing,
    );
  });

  testWidgets('a completed run wears the reconciled badge and states no more', (
    tester,
  ) async {
    // §2.1 gives "reconciled" to `ok`. Four of the six run states are the badge's
    // own word, so restating them beside it would be the duplication the
    // container exists to avoid.
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{_jobPath: _job()},
    );

    await _pump(tester, _controller(), reader);

    final badge = tester.widget<StatusBadge>(
      find.byKey(const ValueKey('reconciliation-status-run-badge-rj_abc')),
    );
    expect(badge.status, AppStatus.ok);
    expect(badge.label, 'Completed');
    expect(
      find.byKey(
        const ValueKey('reconciliation-status-run-state-detail-rj_abc'),
      ),
      findsNothing,
    );
  });

  testWidgets('a run the server gave up on is a problem, and says why', (
    tester,
  ) async {
    // `failed` and `quarantined` are both `problem` - §2.1 has no row for
    // "failed, but a retry is scheduled" - so the word and the detail line are
    // what separate them, never the colour.
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{
        _jobPath: _job(
          overrides: <String, Object?>{
            'status': 'quarantined',
            'consecutiveFailureCount': 3,
            // The retry sweep records why it gave up, and the model refuses a
            // quarantined run that does not.
            'lastErrorCode': 'repeated_failure',
          },
        ),
      },
    );

    await _pump(tester, _controller(), reader);

    final badge = tester.widget<StatusBadge>(
      find.byKey(const ValueKey('reconciliation-status-run-badge-rj_abc')),
    );
    expect(badge.status, AppStatus.problem);
    expect(badge.label, 'Stopped');
    expect(
      _text(tester, 'reconciliation-status-run-state-detail-rj_abc'),
      'Stopped after repeated failures',
    );
  });

  testWidgets('a queued run is awaiting rather than wrong', (tester) async {
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{
        _jobPath: _job(
          overrides: <String, Object?>{
            'status': 'queued',
            'phase': 'intake',
            'attemptCount': 0,
            'completedAt': null,
          },
        ),
      },
    );

    await _pump(tester, _controller(), reader);

    final badge = tester.widget<StatusBadge>(
      find.byKey(const ValueKey('reconciliation-status-run-badge-rj_abc')),
    );
    expect(badge.status, AppStatus.attention);
    expect(badge.label, 'Queued');
  });

  testWidgets('a scheduled run names the server and reads no staff record', (
    tester,
  ) async {
    // `system:nightly` is not a member of the business and not a document ID.
    // Offering it to the name resolver would read a path that cannot exist.
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{_jobPath: _job()},
    );

    await _pump(tester, _controller(), reader);

    expect(
      _text(tester, 'reconciliation-status-run-requested-rj_abc'),
      'Requested by the server (system:nightly)',
    );
    expect(
      reader.documentPaths.where((path) => path.contains('/staff/')),
      isEmpty,
    );
  });

  testWidgets('a run a member asked for resolves that member by name', (
    tester,
  ) async {
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{
        _jobPath: _job(
          overrides: <String, Object?>{
            'source': 'manual',
            'requestedBy': 'owner-a',
          },
        ),
      },
      staffNames: <String, String>{'owner-a': 'Juma'},
    );

    await _pump(tester, _controller(), reader);

    // The UID stays visible beside the name: it is the identity every other
    // record attributes work by.
    expect(
      _text(tester, 'reconciliation-status-run-requested-rj_abc'),
      'Requested by Juma (owner-a)',
    );
    expect(reader.documentPaths, contains('tenants/tenant-a/staff/owner-a'));
  });

  testWidgets('a run this session asked for says so', (tester) async {
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{
        _jobPath: _job(
          overrides: <String, Object?>{
            'source': 'manual',
            'requestedBy': 'manager-a',
          },
        ),
      },
      staffNames: <String, String>{'manager-a': 'Amina'},
    );

    await _pump(tester, _controller(), reader);

    expect(
      _text(tester, 'reconciliation-status-run-requested-rj_abc'),
      'Requested by You (Amina)',
    );
  });

  testWidgets('an unresolved member degrades to the authoritative UID', (
    tester,
  ) async {
    // A display name is a convenience label. The staff record may be outside what
    // this role may read, and inventing a name for a UID would be worse than
    // showing the UID the server actually recorded.
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{
        _jobPath: _job(
          overrides: <String, Object?>{
            'source': 'manual',
            'requestedBy': 'owner-a',
          },
        ),
      },
    );

    await _pump(tester, _controller(), reader);

    expect(
      _text(tester, 'reconciliation-status-run-requested-rj_abc'),
      'Requested by owner-a',
    );
  });

  testWidgets('a failed run states its server code and its failures', (
    tester,
  ) async {
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{
        _jobPath: _job(
          overrides: <String, Object?>{
            'status': 'failed',
            'phase': 'shifts',
            'attemptCount': 3,
            'consecutiveFailureCount': 2,
            'lastErrorCode': 'lease_lost',
            'completedAt': null,
            'lastFailedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 3, 5)),
          },
        ),
      },
    );

    await _pump(tester, _controller(), reader);

    // The code is the server's own, and is shown as a code rather than dressed
    // up as a sentence this app would be inventing.
    expect(
      _text(tester, 'reconciliation-status-run-error-rj_abc'),
      'Server code: lease_lost',
    );
    // Both counts are figures now, so neither needs the other's grammar: `3
    // attempts, 2 in a row failed` was two numbers at the end of one clause.
    expect(_text(tester, 'reconciliation-status-run-attempts-rj_abc'), '3');
    expect(_text(tester, 'reconciliation-status-run-failures-rj_abc'), '2');
    expect(
      _text(tester, 'reconciliation-status-run-instants-rj_abc'),
      'Last failed 2026-08-01 03:05 UTC • Last updated 2026-08-01 02:31 UTC',
    );
  });

  testWidgets('the differences a run found are counted', (tester) async {
    // The count is why a difference opens its run at all: whether this one is
    // the whole of a problem or one symptom of several. **Both kinds are stated
    // even where one of them is zero**, because which of the two is zero is
    // itself the answer to where the run went wrong.
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{_jobPath: _job()},
    );

    await _pump(tester, _controller(), reader);

    expect(
      _text(tester, 'reconciliation-status-run-stock-differences-rj_abc'),
      '0',
    );
    expect(
      _text(tester, 'reconciliation-status-run-shift-differences-rj_abc'),
      '1',
    );
  });

  testWidgets('a run that found nothing claims no differences', (tester) async {
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{
        _jobPath: _job(overrides: <String, Object?>{'shiftVarianceCount': 0}),
      },
    );

    await _pump(tester, _controller(), reader);

    expect(
      find.byKey(
        const ValueKey('reconciliation-status-run-stock-differences-rj_abc'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('reconciliation-status-run-shift-differences-rj_abc'),
      ),
      findsNothing,
    );
    // The run itself still rendered, so the missing line is the absence of
    // differences rather than the absence of a run.
    expect(
      find.byKey(const ValueKey('reconciliation-status-run-rj_abc')),
      findsOne,
    );
  });

  testWidgets('a run the server will repeat says so', (tester) async {
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{
        _jobPath: _job(overrides: <String, Object?>{'rerunRequested': true}),
      },
    );

    await _pump(tester, _controller(), reader);

    expect(
      _text(tester, 'reconciliation-status-run-rerun-rj_abc'),
      'A change arrived while this run was working, so it will run again.',
    );
  });

  testWidgets('an unmodelled status, source, and phase are shown verbatim', (
    tester,
  ) async {
    // A server deploy that introduces one is not evidence of anything wrong, and
    // renaming it to the nearest state this app knows would be a fiction.
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{
        _jobPath: _job(
          overrides: <String, Object?>{
            'status': 'archived',
            'source': 'webhook',
            'phase': 'audit',
            'mode': 'sampled',
          },
        ),
      },
    );

    await _pump(tester, _controller(), reader);

    // The unmodelled state is `info` and the stored value is the detail line, so
    // nothing about it is renamed or hidden.
    final badge = tester.widget<StatusBadge>(
      find.byKey(const ValueKey('reconciliation-status-run-badge-rj_abc')),
    );
    expect(badge.status, AppStatus.info);
    expect(badge.label, 'Unrecognised');
    expect(
      _text(tester, 'reconciliation-status-run-state-detail-rj_abc'),
      'archived',
    );
    expect(_text(tester, 'reconciliation-status-run-state-rj_abc'), 'webhook');
    expect(
      _text(tester, 'reconciliation-status-run-progress-rj_abc'),
      'sampled • reached audit',
    );
    expect(_text(tester, 'reconciliation-status-run-attempts-rj_abc'), '1');
  });

  testWidgets('a run with no recorded instant states that rather than a time', (
    tester,
  ) async {
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{
        _jobPath: _job(
          overrides: <String, Object?>{
            'status': 'queued',
            'phase': 'intake',
            'attemptCount': 0,
            'completedAt': null,
            'updatedAt': null,
          },
        ),
      },
    );

    await _pump(tester, _controller(), reader);

    expect(
      _text(tester, 'reconciliation-status-run-instants-rj_abc'),
      'No instant was recorded for this run.',
    );
  });

  testWidgets('no run at that ID is an ordinary answer, not a fault', (
    tester,
  ) async {
    // A difference outlives the run that found it. What the difference itself
    // records still stands, so this page says so instead of failing.
    await _pump(tester, _controller(), _Reader());

    // A notice rather than a folded explanation, and `info` rather than
    // `problem`: the sentence's own point is that this is an ordinary answer.
    final callout = tester.widget<Callout>(
      find.byKey(const ValueKey('reconciliation-run-missing')),
    );
    expect(callout.status, AppStatus.info);
    expect(
      callout.message,
      startsWith('No run is recorded at this ID any more.'),
    );
    expect(
      find.byKey(const ValueKey('reconciliation-status-run-rj_abc')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('reconciliation-run-failure')),
      findsNothing,
    );
    // The page still says what it is and what it cannot do.
    expect(
      find.byKey(const ValueKey('reconciliation-run-scope-disclosure')),
      findsOne,
    );
  });

  testWidgets('the page explanation starts collapsed and opens on a tap', (
    tester,
  ) async {
    // §5.2's argument for `Disclosure`: the writing is kept and the screen is
    // returned. Both paragraphs are this app's own words, and the second used to
    // be repeated under the record as though it were a fact about that run.
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{_jobPath: _job()},
    );

    await _pump(tester, _controller(), reader);

    expect(
      find.byKey(const ValueKey('reconciliation-run-scope')),
      findsNothing,
    );
    await tester.tap(
      find.text('What this page cannot do'),
    );
    await tester.pumpAndSettle();
    expect(
      _text(tester, 'reconciliation-run-scope'),
      startsWith('The server does the work'),
    );
    expect(
      _text(tester, 'reconciliation-run-outlives'),
      contains('stays listed until it is resolved'),
    );
  });

  testWidgets('a run that contradicts itself fails the page closed', (
    tester,
  ) async {
    // `finalizeReconciliationJob` writes the terminal status, the finishing
    // phase, and the completion instant in one transaction, so this run
    // contradicts its only writer and none of it can be trusted.
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{
        _jobPath: _job(overrides: <String, Object?>{'phase': 'stock'}),
      },
    );

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('reconciliation-run-failure')), findsOne);
    expect(find.byKey(const ValueKey('reconciliation-run')), findsNothing);
    expect(find.textContaining('inconsistent_run_record'), findsNothing);
  });

  testWidgets('an unusable run ID is refused before any read is issued', (
    tester,
  ) async {
    // A job ID arrives from a difference row rather than from a decoded run, so
    // it is validated before it can become a path.
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{_jobPath: _job()},
    );

    await _pump(
      tester,
      _controller(),
      reader,
      jobId: 'reconciliation_jobs/rj_abc',
    );

    expect(find.byKey(const ValueKey('reconciliation-run-failure')), findsOne);
    expect(reader.documentPaths, isEmpty);
    expect(find.textContaining('invalid_run_id'), findsNothing);
  });

  testWidgets('a cashier is refused the run and no read is issued', (
    tester,
  ) async {
    // The same roles that read the day this run belongs to, for the same reason:
    // a cashier does not read business-wide revenue or why it is what it is.
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{_jobPath: _job()},
    );

    await _pump(tester, _controller(role: TenantRole.cashier), reader);

    expect(find.byKey(const ValueKey('reconciliation-run-denied')), findsOne);
    expect(reader.documentPaths, isEmpty);
  });

  testWidgets('every role that reads a day reads a run', (tester) async {
    for (final role in TenantReconciliationStatusRepository.allowedRoles) {
      // Torn down between roles: the guard reloads on a session change rather
      // than on a rebuild, so a reused tree would keep the previous role's card
      // and prove nothing about this one.
      await tester.pumpWidget(const SizedBox.shrink());
      final reader = _Reader(
        documents: <String, Map<String, Object?>>{_jobPath: _job()},
      );
      await _pump(tester, _controller(role: role), reader);
      expect(reader.documentPaths, <String>[_jobPath], reason: role.wireValue);
      expect(
        find.byKey(const ValueKey('reconciliation-status-run-rj_abc')),
        findsOne,
        reason: role.wireValue,
      );
    }
  });

  testWidgets('nothing on this route can start, stop, or repeat a run', (
    tester,
  ) async {
    // Asking for a run is done from the day it belongs to, where the cooldown
    // the request spends is explained. This page only describes one.
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{_jobPath: _job()},
    );

    await _pump(tester, _controller(role: TenantRole.owner), reader);

    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(DropdownButtonFormField<Object?>), findsNothing);
  });

  testWidgets('a tenant switch discards the outstanding run', (tester) async {
    final controller = _controller();
    final reader = _Reader.deferred();

    await _pump(tester, controller, reader, settle: false);
    await tester.pump();

    controller.open(uid: 'manager-a', membership: _membership('tenant-b'));
    await tester.pump();

    // The switch was observed: the guard captured the new session and asked for
    // the same run under the new business rather than reusing the old answer.
    expect(reader.documentPaths, <String>[
      _jobPath,
      'tenants/tenant-b/reconciliation_jobs/rj_abc',
    ]);

    reader.completeFirstDocument(_job());
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('reconciliation-status-run-rj_abc')),
      findsNothing,
    );
  });

  testWidgets('the route opens under the caller\'s own session scope', (
    tester,
  ) async {
    // A tenant switch has to invalidate the opened route rather than leave a
    // detached screen describing another business\'s run behind.
    final controller = _controller();
    final reader = _Reader(
      documents: <String, Map<String, Object?>>{_jobPath: _job()},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TenantSessionScope(
          controller: controller,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openTenantReconciliationRun(
                  context,
                  reader: reader,
                  jobId: 'rj_abc',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Reconciliation run'), findsOne);
    expect(
      TenantSessionScope.of(
        tester.element(find.byType(TenantReconciliationRunPanel)),
      ),
      same(controller),
    );
  });
}

const String _jobPath = 'tenants/tenant-a/reconciliation_jobs/rj_abc';

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  String jobId = 'rj_abc',
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantReconciliationRunPanel(reader: reader, jobId: jobId),
        ),
      ),
    ),
  );
  if (!settle) return;
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

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

/// One `reconciliation_jobs` record in the shape `jobs.ts` writes it.
Map<String, Object?> _job({Map<String, Object?>? overrides}) {
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
  return data;
}

/// Answers the run document and staff labels by exact path.
///
/// It implements the collection boundary as well, and refuses it: this route
/// addresses one run and must never search for one, and the refusal is what makes
/// that hold if the panel ever changes.
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

  final List<String> documentPaths = <String>[];
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];
  final List<(String, Completer<TenantDocumentSnapshot?>)> _pending =
      <(String, Completer<TenantDocumentSnapshot?>)>[];

  /// Answers the oldest outstanding read at its own exact path, so the
  /// repository's path proof sees what it really asked for.
  void completeFirstDocument(Map<String, Object?>? data) {
    if (_pending.isEmpty) return;
    final (path, completer) = _pending.removeAt(0);
    completer.complete(
      data == null ? null : TenantDocumentSnapshot(path: path, data: data),
    );
  }

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) {
    documentPaths.add(path);
    if (_defer) {
      final completer = Completer<TenantDocumentSnapshot?>();
      _pending.add((path, completer));
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
  ) async {
    queries.add(query);
    throw StateError('This route must address one run, not search for one.');
  }
}
