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
          stockCountsBuilder: (_) => const Text('Stock count schedule'),
          agreedPricesBuilder: (_) => const Text('Who can agree a price'),
        ),
      ),
    );

    await tester.enterText(find.byKey(const ValueKey('currency-edit')), 'KES');
    await tester.tap(find.text('Stock counts'));
    await tester.pumpAndSettle();
    expect(find.text('Stock count schedule'), findsOneWidget);

    await tester.tap(find.text('Agreed prices'));
    await tester.pumpAndSettle();
    expect(find.text('Who can agree a price'), findsOneWidget);

    await tester.tap(find.text('Currency'));
    await tester.pumpAndSettle();
    expect(find.text('KES'), findsOneWidget);
  });

  testWidgets('three tabs share the width evenly where their labels fit', (
    tester,
  ) async {
    // **Not 411, and that is the test font.** Every glyph in it is a full
    // square, so *Agreed prices* measures about 214 here and about 127 in the
    // shipped face. The fit is real at 411 on a phone; this proves the rule.
    await _pumpAt(tester, const Size(1024, 800));

    expect(tester.takeException(), isNull);
    expect(_strip(tester).isScrollable, isFalse);
  });

  testWidgets('a small phone scrolls the tabs rather than cutting a word', (
    tester,
  ) async {
    // 320 wide cut *Stock counts* and *Agreed prices* off mid-word on an
    // emulator on 2026-09-29, when the strip was three fixed shares.
    await _pumpAt(tester, const Size(320, 640));

    expect(tester.takeException(), isNull);
    expect(_strip(tester).isScrollable, isTrue);
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
        stockCountsBuilder: (_) => const SizedBox(),
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
