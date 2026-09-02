import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_application_1/main.dart' as app;

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
      await _waitForAny(tester, <Finder>[
        find.byKey(const ValueKey('checkout-cart')),
        find.byKey(const ValueKey('checkout-wide')),
        find.byKey(const ValueKey('checkout-compact')),
        find.byKey(const ValueKey('tenant-shift-panel')),
      ]);
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
    await _waitForAny(tester, <Finder>[
      find.byKey(const ValueKey('checkout-cart')),
      find.byKey(const ValueKey('checkout-wide')),
      find.byKey(const ValueKey('checkout-compact')),
      find.byKey(const ValueKey('tenant-shift-panel')),
    ], timeout: const Duration(seconds: 2));

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
