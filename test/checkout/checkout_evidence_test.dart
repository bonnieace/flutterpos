import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('outbox evidence counts', () {
    late Directory directory;
    late Box<dynamic> box;
    late HiveCheckoutOutbox outbox;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'checkout-evidence-test-',
      );
      Hive.init(directory.path);
      box = await Hive.openBox<dynamic>(
        HiveCheckoutOutbox.boxName,
        encryptionCipher: HiveAesCipher(_encryptionKey),
        crashRecovery: false,
      );
      outbox = HiveCheckoutOutbox.fromBox(box);
    });

    tearDown(() async {
      await Hive.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('counts only the exact session UID and tenant', () async {
      await _save(outbox, 'checkout-a');
      await _save(outbox, 'checkout-b');
      await _save(outbox, 'other-tenant', tenantId: 'tenant-b');
      await _save(outbox, 'other-user', uid: 'user-b');
      await outbox.beginSubmission(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: 'checkout-b',
        leaseOwner: 'worker-a',
        leaseDuration: const Duration(minutes: 2),
      );

      final counts = await CheckoutOutboxEvidenceSource(
        outbox,
      ).summarize(_session());

      expect(counts.savedOffline, 1);
      expect(counts.submitting, 1);
      expect(counts.awaitingConfirmation, 0);
      expect(counts.confirmed, 0);
      expect(counts.needsAttention, 0);
      expect(counts.total, 2);
      expect(counts.unsettled, 2);
    });
  });

  group('pending evidence panel', () {
    // **The counts and the badge are two widgets since 2026-09-03.** The badge
    // is the top bar's glyph and no longer drops a panel underneath itself; it
    // opens the notifications route, where the counts are one section and the
    // unprinted receipts are the other. So the cases about what is *read* pump
    // `CheckoutLocalWorkPanel` directly, and the ones about the glyph pump the
    // glyph.
    testWidgets('renders read-only counts for the live session', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        const _FakeSource(
          CheckoutEvidenceSummary(
            savedOffline: 2,
            submitting: 1,
            awaitingConfirmation: 3,
            needsAttention: 1,
            confirmed: 4,
          ),
        ),
      );

      expect(await _count(tester, 'Saved here, waiting to send'), 2);
      expect(await _count(tester, 'Sending now'), 1);
      expect(await _count(tester, 'Sent, waiting for the server'), 3);
      expect(await _count(tester, 'Sales that need you'), 1);
      // **Confirmed is not drawn at all.** Four sales that have gone through
      // are the absence of news, and this page is the news.
      expect(find.text('4'), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('states plainly when no checkout is stored', (tester) async {
      await _pumpPanel(tester, const _FakeSource(CheckoutEvidenceSummary()));

      // **Not five zeroes.** §5.1's rule is that a device holding nothing
      // draws no count at all, so the readout says it in a sentence.
      expect(find.text('0'), findsNothing);
      expect(
        find.text('Nothing on this device is waiting to be sent.'),
        findsOneWidget,
      );
    });

    testWidgets('renders nothing without an authorized session', (
      tester,
    ) async {
      final controller = TenantSessionController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: TenantSessionScope(
            controller: controller,
            child: const Scaffold(
              body: CheckoutPendingEvidencePanel(
                source: _FakeSource(CheckoutEvidenceSummary(savedOffline: 9)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Nothing at all: no button, so no count and nothing to open.
      expect(
        find.byKey(const ValueKey('pending-checkout-evidence')),
        findsNothing,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('reports unavailable local evidence without details', (
      tester,
    ) async {
      await _pumpPanel(tester, const _FailingSource());

      expect(find.text('Local work evidence is unavailable.'), findsOneWidget);
      expect(find.textContaining('malformed_record'), findsNothing);
    });

    testWidgets('re-reads when a sale is saved on this device', (tester) async {
      // The defect this closes: the counts were read once when the session
      // opened, so a cashier who rang up two sales was told none was stored
      // here until the app was restarted.
      final signals = StreamController<Object?>.broadcast();
      addTearDown(signals.close);
      final source = _CountingSource([
        const CheckoutEvidenceSummary(),
        const CheckoutEvidenceSummary(savedOffline: 2),
      ]);
      await _pumpPanel(tester, source, refreshSignals: signals.stream);

      // Nothing stored yet, so the sentence rather than a row of zeroes.
      expect(find.text('2'), findsNothing);
      expect(
        find.text('Nothing on this device is waiting to be sent.'),
        findsOneWidget,
      );

      signals.add(null);
      // One frame delivers the signal, one restarts the guarded read, and one
      // renders its answer.
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(source.calls, 2);
      expect(await _count(tester, 'Saved here, waiting to send'), 2);
    });

    testWidgets('an unrelated rebuild does not re-read', (tester) async {
      final signals = StreamController<Object?>.broadcast();
      addTearDown(signals.close);
      final source = _CountingSource([
        const CheckoutEvidenceSummary(savedOffline: 1),
      ]);
      await _pumpPanel(tester, source, refreshSignals: signals.stream);

      expect(source.calls, 1);
      await tester.pump();
      await tester.pump();

      expect(source.calls, 1);
      expect(await _count(tester, 'Saved here, waiting to send'), 1);
    });

    testWidgets('a record on its own is stated, and the zeroes are not', (
      tester,
    ) async {
      // A real run reported this panel showing "Saved offline: 0" and
      // seemingly nothing else while a record was present. The answer was to
      // draw all twelve states including the empty ones; **since 2026-09-04 it
      // is the opposite** - the empty ones are not drawn, so the one state
      // that holds something is the only thing on the band and cannot be lost
      // among noughts. Either way the failure that report describes is
      // impossible; this pins the current half of it.
      await _pumpPanel(
        tester,
        const _FakeSource(CheckoutEvidenceSummary(awaitingConfirmation: 1)),
      );

      expect(await _count(tester, 'Sent, waiting for the server'), 1);
      expect(find.text('0'), findsNothing);
      expect(find.text('Saved here, waiting to send'), findsNothing);
      expect(
        find.text('Nothing on this device is waiting to be sent.'),
        findsNothing,
      );
    });

    testWidgets('a refresh keeps the previous counts on screen', (
      tester,
    ) async {
      // The defect this closes: every refresh signal changes the loader's
      // identity, which puts the guard back into its loading state - and the
      // loading state was `SizedBox.shrink()`. `CheckoutSyncPass` reports a
      // change more than once per sale, so the panel vanished and reappeared
      // repeatedly while a cashier was watching for their sale.
      final signals = StreamController<Object?>.broadcast();
      addTearDown(signals.close);
      final source = _DeferredSource();
      await _pumpPanel(tester, source, refreshSignals: signals.stream);

      // One pump lets the completed read resume, the next renders its answer.
      source.complete(const CheckoutEvidenceSummary(savedOffline: 1));
      await tester.pump();
      await tester.pump();
      expect(await _count(tester, 'Saved here, waiting to send'), 1);

      signals.add(null);
      await tester.pump();
      await tester.pump();

      // Mid-refresh: the counts are still there, and the panel says they may be
      // stale rather than leaving that to be inferred.
      expect(source.calls, 2);
      expect(await _count(tester, 'Saved here, waiting to send'), 1);
      expect(
        find.byKey(const ValueKey('pending-checkout-evidence-rereading')),
        findsOne,
      );

      source.complete(const CheckoutEvidenceSummary(savedOffline: 3));
      await tester.pump();
      await tester.pump();

      expect(await _count(tester, 'Saved here, waiting to send'), 3);
      expect(
        find.byKey(const ValueKey('pending-checkout-evidence-rereading')),
        findsNothing,
      );
    });

    testWidgets('a business switch drops the other business\'s counts', (
      tester,
    ) async {
      // Retaining counts across a refresh must never retain them across a
      // session change: one business's local work shown under another
      // business's name would be a worse defect than the blanking it replaces.
      final controller = TenantSessionController()
        ..open(uid: 'user-a', membership: _membership('tenant-a'));
      addTearDown(controller.dispose);
      final source = _DeferredSource();
      await _pumpPanel(tester, source, controller: controller);

      source.complete(const CheckoutEvidenceSummary(savedOffline: 1));
      await tester.pump();
      await tester.pump();
      expect(await _count(tester, 'Saved here, waiting to send'), 1);

      controller.open(uid: 'user-a', membership: _membership('tenant-b'));
      await tester.pump();

      // The second read is outstanding, so nothing may be shown at all.
      expect(source.calls, 2);
      expect(
        find.byKey(const ValueKey('pending-checkout-evidence-panel')),
        findsNothing,
      );

      source.complete(const CheckoutEvidenceSummary(savedOffline: 7));
      await tester.pump();
      await tester.pump();
      expect(await _count(tester, 'Saved here, waiting to send'), 7);
    });

    testWidgets('the glyph counts the receipts that never printed too', (
      tester,
    ) async {
      // **The badge is about everything this device still owes.** Unprinted
      // receipts came off the home's grid on 2026-09-03, so the count that
      // carried them has to land somewhere - and this is the one place that
      // says how much has not gone through.
      final sessions = TenantSessionController()
        ..open(uid: 'user-a', membership: _membership('tenant-a'));
      addTearDown(sessions.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: TenantSessionScope(
            controller: sessions,
            child: Scaffold(
              body: CheckoutPendingEvidencePanel(
                source: const _FakeSource(
                  CheckoutEvidenceSummary(savedOffline: 2, confirmed: 9),
                ),
                // Asked for the signed-in business by name: the box it
                // counts is the device's and spans every business this device
                // has served.
                alsoWaiting: (tenantId) => tenantId == 'tenant-a' ? 3 : 0,
                notificationsRoute: (_) =>
                    const Scaffold(body: Text('Notifications')),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Two saved offline and three unprinted. The nine confirmed are not
      // news and are deliberately not in it.
      expect(find.text('5'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pending-checkout-evidence')));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
    });

    testWidgets('a signal after disposal reads nothing', (tester) async {
      final signals = StreamController<Object?>.broadcast();
      addTearDown(signals.close);
      final source = _CountingSource([
        const CheckoutEvidenceSummary(savedOffline: 1),
      ]);
      await _pumpPanel(tester, source, refreshSignals: signals.stream);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      signals.add(null);
      await tester.pump();

      expect(source.calls, 1);
    });
  });
}

Future<void> _pumpPanel(
  WidgetTester tester,
  CheckoutEvidenceSource source, {
  Stream<Object?>? refreshSignals,
  TenantSessionController? controller,
}) async {
  final sessions =
      controller ??
      (TenantSessionController()
        ..open(uid: 'user-a', membership: _membership('tenant-a')));
  if (controller == null) addTearDown(sessions.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: sessions,
        // **The scope reads and the panel draws, since 2026-09-04.** The
        // notifications page needs the same summary for its own headline, so
        // the read moved up and this pair is what it composes.
        child: Scaffold(
          body: CheckoutEvidenceScope(
            source: source,
            refreshSignals: refreshSignals,
            builder: (context, summary, {required rereading, onAcknowledge}) =>
                CheckoutLocalWorkPanel(
                  summary: summary,
                  rereading: rereading,
                  onAcknowledge: onAcknowledge,
                ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<CheckoutOutboxRecord> _save(
  HiveCheckoutOutbox outbox,
  String checkoutId, {
  String uid = 'user-a',
  String tenantId = 'tenant-a',
}) => outbox.saveOffline(
  uid: uid,
  tenantId: tenantId,
  checkoutId: checkoutId,
  payload: <String, Object?>{'checkoutId': checkoutId},
);

TenantSession _session() => TenantSession.fromMembership(
  uid: 'user-a',
  membership: _membership('tenant-a'),
);

final List<int> _encryptionKey = List<int>.generate(
  HiveCheckoutOutbox.encryptionKeyBytes,
  (index) => (index * 3) % 256,
);

final class _FakeSource implements CheckoutEvidenceSource {
  const _FakeSource(this._summary);

  final CheckoutEvidenceSummary _summary;

  @override
  Future<CheckoutEvidenceSummary> summarize(TenantSession session) async =>
      _summary;
}

/// Answers each read in turn, holding the last answer once they run out.
final class _CountingSource implements CheckoutEvidenceSource {
  _CountingSource(this._summaries);

  final List<CheckoutEvidenceSummary> _summaries;
  int calls = 0;

  @override
  Future<CheckoutEvidenceSummary> summarize(TenantSession session) async {
    final index = calls++;
    return _summaries[index < _summaries.length
        ? index
        : _summaries.length - 1];
  }
}

/// Hands out a future per read and lets the test decide when each answers, so a
/// loading frame can be observed rather than raced past.
final class _DeferredSource implements CheckoutEvidenceSource {
  final List<Completer<CheckoutEvidenceSummary>> _pending =
      <Completer<CheckoutEvidenceSummary>>[];
  int calls = 0;

  @override
  Future<CheckoutEvidenceSummary> summarize(TenantSession session) {
    calls++;
    final completer = Completer<CheckoutEvidenceSummary>();
    _pending.add(completer);
    return completer.future;
  }

  void complete(CheckoutEvidenceSummary summary) {
    if (_pending.isEmpty) return;
    _pending.removeAt(0).complete(summary);
  }
}

final class _FailingSource implements CheckoutEvidenceSource {
  const _FailingSource();

  @override
  Future<CheckoutEvidenceSummary> summarize(TenantSession session) async =>
      throw const CheckoutOutboxException('malformed_record');
}

TenantMembership _membership(String tenantId) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: TenantRole.cashier,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

/// Reads one count out of the readout.
///
/// **The counts moved behind the badge in §11 step 7 and out again on
/// 2026-09-03**, onto the notifications route the badge opens. They are on
/// screen as soon as this panel is, so there is nothing to open first.
Future<int> _count(WidgetTester tester, String label) async {
  // **The cell, not the row.** Each count is a figure over its own label in a
  // bordered box since 2026-09-04, where it used to be `label ....... 2` on one
  // line. The box is the smallest thing holding both, so it is what this reads
  // out of.
  // **The row, not a cell.** Each outstanding state is a glyph, a figure and
  // a sentence on one line since 2026-09-04, where it was briefly a figure
  // over a label in a bordered box. The `Row` is the smallest thing holding
  // both parts, so it is what this reads out of.
  final row = find.ancestor(of: find.text(label), matching: find.byType(Row));
  final counts = find
      .descendant(of: row.first, matching: find.byType(Text))
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .where((s) => int.tryParse(s) != null);
  return int.parse(counts.single);
}
