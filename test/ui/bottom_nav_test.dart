import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/bottom_nav.dart';
import 'package:uzapay_pos/ui/tokens.dart';

const _destinations = <AppBottomDestination>[
  AppBottomDestination(
    label: 'Overview',
    icon: Icons.grid_view_outlined,
    destinationKey: ValueKey('nav-overview'),
  ),
  AppBottomDestination(
    label: 'Businesses',
    icon: Icons.storefront_outlined,
    destinationKey: ValueKey('nav-businesses'),
  ),
  AppBottomDestination(
    label: 'Alerts',
    icon: Icons.notifications_none,
    badgeCount: 2,
    destinationKey: ValueKey('nav-alerts'),
  ),
];

Future<List<int>> _pump(
  WidgetTester tester, {
  required double width,
  int current = 0,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final selected = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (context, setState) => AppBottomNav(
              destinations: _destinations,
              currentIndex: current,
              onSelected: (index) {
                selected.add(index);
                setState(() => current = index);
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return selected;
}

void main() {
  testWidgets('only the current destination shows its name', (tester) async {
    await _pump(tester, width: 1440);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Businesses'), findsNothing);
    expect(find.bySemanticsLabel('Businesses'), findsOneWidget);
    expect(find.bySemanticsLabel('Alerts, 2'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('a press selects, and the pill opens on a spring', (
    tester,
  ) async {
    final selected = await _pump(tester, width: 1440);
    expect(find.text('Businesses'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nav-businesses')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    double revealed() => tester
        .getSize(
          find
              .ancestor(
                of: find.text('Businesses'),
                matching: find.byType(ClipRect),
              )
              .first,
        )
        .width;
    final during = revealed();
    await tester.pumpAndSettle();
    expect(during, lessThan(revealed()));
    expect(during, greaterThan(0));
    expect(selected, <int>[1]);
    expect(find.text('Overview'), findsNothing);
  });

  testWidgets('pressing the current destination does nothing', (tester) async {
    final selected = await _pump(tester, width: 1440);
    await tester.tap(find.byKey(const ValueKey('nav-overview')));
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
  });

  testWidgets('circles are the launcher well wide, the 48 target on a phone', (
    tester,
  ) async {
    final tokens = AppTokens.profoundVerdant;
    // The bar is one circle tall plus its padding; its edge is painted, not
    // laid out.
    await _pump(tester, width: 1440);
    expect(
      tester.getSize(find.byType(AppBottomNav)).height,
      tokens.icons.launcherWell + tokens.spacing.s8 * 2,
    );
    await _pump(tester, width: 411);
    expect(
      tester.getSize(find.byType(AppBottomNav)).height,
      tokens.density.minimumTapTarget.height + tokens.spacing.s4 * 2,
    );
  });
}
