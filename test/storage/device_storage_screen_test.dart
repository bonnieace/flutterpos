import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/storage/device_storage.dart';
import 'package:uzapay_pos/storage/device_storage_screen.dart';
import 'package:uzapay_pos/theme.dart';

void main() {
  Future<List<DeviceStorageChoice>> pump(
    WidgetTester tester, {
    bool canContinue = true,
  }) async {
    final choices = <DeviceStorageChoice>[];
    await tester.pumpWidget(
      DeviceStorageProblemApp(
        theme: spiritTheme,
        store: DeviceStore.checkoutOutbox,
        canContinue: canContinue,
        onChoice: choices.add,
        attempt: 0,
      ),
    );
    await tester.pumpAndSettle();
    return choices;
  }

  const retry = ValueKey<String>('device-storage-retry');
  const carryOn = ValueKey<String>('device-storage-continue');
  const confirm = ValueKey<String>('device-storage-confirm');

  testWidgets('names the store and what continuing would lose', (tester) async {
    await pump(tester);
    expect(find.text(DeviceStore.checkoutOutbox.title), findsOneWidget);
    expect(
      find.textContaining('have not reached the server yet'),
      findsOneWidget,
    );
    expect(find.byKey(retry), findsOneWidget);
    expect(find.byKey(carryOn), findsOneWidget);
  });

  testWidgets('trying again answers once and holds both buttons', (
    tester,
  ) async {
    final choices = await pump(tester);
    await tester.tap(find.byKey(retry));
    await tester.pump();
    await tester.tap(find.byKey(retry), warnIfMissed: false);
    await tester.tap(find.byKey(carryOn), warnIfMissed: false);
    await tester.pump();
    expect(choices, <DeviceStorageChoice>[DeviceStorageChoice.retry]);
  });

  testWidgets('continuing asks first, and going back changes nothing', (
    tester,
  ) async {
    final choices = await pump(tester);
    await tester.tap(find.byKey(carryOn));
    await tester.pumpAndSettle();
    expect(find.byKey(confirm), findsOneWidget);
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(choices, isEmpty);

    await tester.tap(find.byKey(carryOn));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(confirm));
    // The button stays busy until the real app replaces this one, so the
    // spinner never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(choices, <DeviceStorageChoice>[DeviceStorageChoice.continueWithout]);
  });

  testWidgets('a key store that did not answer offers only a retry', (
    tester,
  ) async {
    await pump(tester, canContinue: false);
    expect(find.byKey(retry), findsOneWidget);
    expect(find.byKey(carryOn), findsNothing);
    expect(find.textContaining('restart the phone'), findsOneWidget);
  });

  testWidgets('both actions meet the 48dp target', (tester) async {
    await pump(tester);
    for (final key in <Key>[retry, carryOn]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.height, greaterThanOrEqualTo(48), reason: '$key');
    }
  });
}
