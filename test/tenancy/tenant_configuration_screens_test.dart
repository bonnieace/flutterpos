import 'package:flutter/material.dart';
import 'package:uzapay_pos/tenancy/tenant_configuration_screens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('each configuration stays on its own persistent tab', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TenantConfigurationsScreen(
          currencyBuilder: (_) =>
              const TextField(key: ValueKey('currency-edit')),
          agreedPricesBuilder: (_) => const Text('Who can agree a price'),
        ),
      ),
    );

    await tester.enterText(find.byKey(const ValueKey('currency-edit')), 'KES');
    await tester.tap(find.text('Agreed prices'));
    await tester.pumpAndSettle();
    expect(find.text('Who can agree a price'), findsOneWidget);

    await tester.tap(find.text('Currency'));
    await tester.pumpAndSettle();
    expect(find.text('KES'), findsOneWidget);
  });

  testWidgets('the rota and loyalty are no longer tabs here', (tester) async {
    // Both moved on 2026-10-04 beside what they decide: the rota to the
    // *Stock counts* screen's *Settings* tab, loyalty to *Customers*.
    await _pumpAt(tester, const Size(1024, 800));

    expect(find.text('Stock counts'), findsNothing);
    expect(find.text('Loyalty'), findsNothing);
  });

  testWidgets('two tabs draw as a switch, in equal halves', (tester) async {
    await _pumpAt(tester, const Size(1024, 800));

    expect(tester.takeException(), isNull);
    expect(_strip(tester).isScrollable, isFalse);
    expect(find.byIcon(Icons.payments_outlined), findsNothing);
  });

  testWidgets('a small phone fits both words without cutting one', (
    tester,
  ) async {
    // 320 wide cut *Stock counts* and *Agreed prices* off mid-word on an
    // emulator on 2026-09-29, when the strip was three fixed shares.
    await _pumpAt(tester, const Size(320, 640));

    expect(tester.takeException(), isNull);
    expect(find.text('Agreed prices'), findsOneWidget);
  });
}

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantConfigurationsScreen(
        currencyBuilder: (_) => const SizedBox(),
        agreedPricesBuilder: (_) => const SizedBox(),
      ),
    ),
  );
}

TabBar _strip(WidgetTester tester) => tester.widget<TabBar>(
  find.descendant(
    of: find.byKey(const ValueKey('configurations-tabs')),
    matching: find.byType(TabBar),
  ),
);
