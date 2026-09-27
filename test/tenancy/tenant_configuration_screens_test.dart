import 'package:flutter/material.dart';
import 'package:uzapay_pos/tenancy/tenant_configuration_screens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('currency and stock counts stay on separate persistent tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TenantConfigurationsScreen(
          currencyBuilder: (_) =>
              const TextField(key: ValueKey('currency-edit')),
          stockCountsBuilder: (_) => const Text('Stock count schedule'),
        ),
      ),
    );

    await tester.enterText(find.byKey(const ValueKey('currency-edit')), 'KES');
    await tester.tap(find.text('Stock counts'));
    await tester.pumpAndSettle();
    expect(find.text('Stock count schedule'), findsOneWidget);

    await tester.tap(find.text('Currency'));
    await tester.pumpAndSettle();
    expect(find.text('KES'), findsOneWidget);
  });
}
