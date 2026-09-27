import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:uzapay_pos/main.dart' as app;

const String _phase = String.fromEnvironment(
  'OFFLINE_ACCEPTANCE_PHASE',
  defaultValue: 'verify',
);
const String _email = String.fromEnvironment('OFFLINE_ACCEPTANCE_EMAIL');
const String _password = String.fromEnvironment('OFFLINE_ACCEPTANCE_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('authenticated Android process starts from device state', (
    tester,
  ) async {
    final started = DateTime.now();
    app.main();
    await _waitFor(tester, () => Firebase.apps.isNotEmpty);

    if (_phase == 'prime') {
      if (_email.isEmpty || _password.isEmpty) {
        fail('Prime phase requires OFFLINE_ACCEPTANCE_EMAIL and password.');
      }
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email,
          password: _password,
        );
      }
      await _waitForFinder(
        tester,
        find.byKey(const ValueKey('start-checkout')),
      );
      // Opening the register primes catalog, configuration, and shift reads.
      await tester.tap(find.byKey(const ValueKey('start-checkout')));
      await tester.pump();
      await _waitForAny(tester, _registerArrived);
      return;
    }

    await _waitForFinder(
      tester,
      find.byKey(const ValueKey('start-checkout')),
      timeout: const Duration(seconds: 2),
    );
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(seconds: 2)),
    );
    expect(
      find.byKey(const ValueKey('offline-bootstrap-banner')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('start-checkout')));
    await tester.pump();
    await _waitForAny(
      tester,
      _registerArrived,
      timeout: const Duration(seconds: 2),
    );

    // When the seeded catalog and open shift make a product directly usable,
    // prove the durable checkout path too. A seed without one still proves the
    // cold-process startup and till acceptance above.
    final products = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'checkout-product-',
          ),
    );
    if (products.evaluate().isNotEmpty) {
      await tester.tap(products.first);
      await tester.pump();
      final cash = find.byKey(const ValueKey('checkout-tender-cash'));
      if (cash.evaluate().isNotEmpty) await tester.tap(cash);
      final save = find.byKey(const ValueKey('checkout-save'));
      if (save.evaluate().isNotEmpty) {
        await tester.tap(save);
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('checkout-refusal')), findsNothing);
      }
    }
  });
}

/// Reaching the register, by any of the surfaces that count as having reached
/// it.
///
/// **This test primes caches; it does not assert that a till may sell.** The
/// register opens onto the shift gate, and the gate has every right to refuse -
/// no shift open, a shift past the 24-hour cap, one that belongs to yesterday.
/// Each of those is the register reached, and the catalog, configuration and
/// shift reads this test exists to warm have all happened by then.
///
/// **`tenant-shift-panel` was in this list and has not existed since the gate
/// replaced that panel**, so the only accepted outcomes were the three till
/// layouts - and the test passed anyway, because a freshly seeded shift is
/// always sellable *on the day it was seeded*. It took a shift left open across
/// midnight to show that the list had gone stale.
final List<Finder> _registerArrived = <Finder>[
  find.byKey(const ValueKey('checkout-cart')),
  find.byKey(const ValueKey('checkout-wide')),
  find.byKey(const ValueKey('checkout-compact')),
  find.byKey(const ValueKey('shift-gate-blocked')),
  find.byKey(const ValueKey('shift-gate-expired')),
  find.byKey(const ValueKey('shift-gate-day-ended')),
  find.byKey(const ValueKey('shift-gate-closed-pending')),
  find.byKey(const ValueKey('shift-gate-unavailable')),
  find.byKey(const ValueKey('shift-gate-error')),
];

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue);
}

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) => _waitFor(tester, () => finder.evaluate().isNotEmpty, timeout: timeout);

Future<void> _waitForAny(
  WidgetTester tester,
  List<Finder> finders, {
  Duration timeout = const Duration(seconds: 30),
}) => _waitFor(
  tester,
  () => finders.any((finder) => finder.evaluate().isNotEmpty),
  timeout: timeout,
);
