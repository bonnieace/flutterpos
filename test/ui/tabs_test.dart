import 'package:flutter/material.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/tabs.dart';
import 'package:uzapay_pos/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTabs', () {
    testWidgets('answers §9s 48dp target, which Material misses by two', (
      tester,
    ) async {
      // `_kTabHeight` in the SDK is 46. §9's touch-target row is pass/fail at
      // 48, and the four tabs on the platform route had been two short since
      // they were written.
      await _pump(tester);

      expect(AppTabs.height, AppDensity.comfortable.minimumTapTarget.height);
      expect(AppTabs.height, 48);
      for (final label in const <String>['First', 'Second']) {
        expect(
          tester.getSize(find.widgetWithText(Tab, label)).height,
          greaterThanOrEqualTo(48),
          reason: label,
        );
      }
    });

    testWidgets('says which tab is selected twice, not in hue alone', (
      tester,
    ) async {
      // §9: "status conveyed by container + icon + label. Never hue alone."
      // The label changes role *and* the indicator appears under it.
      await _pump(tester);

      final bar = tester.widget<TabBar>(find.byType(TabBar));
      final tokens = spiritTheme.extension<AppTokens>()!;
      expect(bar.labelColor, tokens.colors.text.primary);
      expect(bar.unselectedLabelColor, tokens.colors.text.secondary);
      expect(bar.indicatorColor, tokens.colors.action.primary.container);
    });

    testWidgets('takes its indicator weight from the one stroke §2.1 names', (
      tester,
    ) async {
      // The focus ring is the only width in the document. A literal 2 would not
      // move if that ring ever did.
      await _pump(tester);

      expect(
        tester.widget<TabBar>(find.byType(TabBar)).indicatorWeight,
        AppTokens.dark.colors.action.focusRing.width,
      );
    });

    testWidgets('sets both labels in §2.2s label.lg', (tester) async {
      await _pump(tester);

      final bar = tester.widget<TabBar>(find.byType(TabBar));
      expect(bar.labelStyle, AppTypeRoles.standard.labelLarge);
      expect(bar.unselectedLabelStyle, AppTypeRoles.standard.labelLarge);
    });
  });
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: const DefaultTabController(
        length: 2,
        child: Scaffold(
          body: AppTabs(tabs: <String>['First', 'Second']),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
