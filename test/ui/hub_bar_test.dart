import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/hub_bar.dart';

/// Mounts [bar] as the app bar of a page at a tablet's width.
Future<void> _pump(WidgetTester tester, HubTopBar bar) async {
  tester.view.physicalSize = const Size(1232, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(appBar: bar, body: const SizedBox()),
    ),
  );
  await tester.pump();
}

String _pillText(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('hub-status-pill')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  group('the name in the user pill', () {
    test('is the first name and the last name\'s initial', () {
      expect(HubTopBar.shortName('Boniface Masota'), 'Boniface M.');
      expect(HubTopBar.shortName('  Amina  Wanjiru Otieno '), 'Amina O.');
    });

    test('is left as it is when there is one word', () {
      expect(HubTopBar.shortName('mziza'), 'mziza');
    });
  });

  group('the status pill', () {
    testWidgets('names the terminal before it knows the network', (
      tester,
    ) async {
      final readings = Completer<bool>();
      await _pump(
        tester,
        HubTopBar(
          title: 'Smartcom',
          terminalLabel: 'CT-7F2',
          onlineCheck: () => readings.future,
        ),
      );
      // Nothing is guessed while the first reading is out.
      expect(_pillText(tester), 'Terminal CT-7F2');

      readings.complete(true);
      await tester.pumpAndSettle();
      expect(_pillText(tester), 'Online · Terminal CT-7F2');
    });

    testWidgets('follows the network as it changes', (tester) async {
      final changes = StreamController<bool>.broadcast();
      addTearDown(changes.close);
      await _pump(
        tester,
        HubTopBar(
          title: 'Smartcom',
          terminalLabel: 'CT-7F2',
          onlineCheck: () async => true,
          onlineChanges: changes.stream,
        ),
      );
      await tester.pump();
      expect(_pillText(tester), 'Online · Terminal CT-7F2');

      changes.add(false);
      await tester.pumpAndSettle();
      expect(_pillText(tester), 'Offline · Terminal CT-7F2');
    });

    testWidgets('is not drawn without a terminal', (tester) async {
      await _pump(tester, const HubTopBar(title: 'Smartcom'));
      expect(find.byKey(const ValueKey('hub-status-pill')), findsNothing);
    });
  });

  group('the title', () {
    testWidgets('is the control it is in the toolbar, under the same key', (
      tester,
    ) async {
      var opened = 0;
      await _pump(
        tester,
        HubTopBar(
          title: 'Smartcom',
          onTitlePressed: () => opened++,
          titleActionLabel: 'My businesses',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('screen-title-action')));
      expect(opened, 1);
      expect(find.bySemanticsLabel('Smartcom. My businesses.'), findsOneWidget);
    });
  });

  testWidgets('the user pill says who is signed in, and in what role', (
    tester,
  ) async {
    await _pump(
      tester,
      const HubTopBar(
        title: 'Smartcom',
        memberName: 'John Doe',
        memberRole: 'Owner',
      ),
    );
    final pill = find.byKey(const ValueKey('hub-user-pill'));
    expect(
      find.descendant(of: pill, matching: find.text('John D.')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pill, matching: find.text('OWNER')),
      findsOneWidget,
    );
  });

  testWidgets('on a phone it is the old phone row, 56 high', (tester) async {
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: spiritTheme,
        home: Scaffold(
          appBar: const HubTopBar(
            compact: true,
            title: 'Smartcom',
            terminalLabel: 'CT-7F2',
            memberName: 'John Doe',
            memberRole: 'Owner',
          ),
          body: const SizedBox(),
        ),
      ),
    );
    expect(tester.getSize(find.byType(HubTopBar)).height, 56);
    // The person as a circle alone, and no pill - the old phone bar had room
    // for neither.
    expect(find.byKey(const ValueKey('hub-user-avatar')), findsOneWidget);
    expect(find.byKey(const ValueKey('hub-user-pill')), findsNothing);
    expect(find.byKey(const ValueKey('hub-status-pill')), findsNothing);
    expect(find.bySemanticsLabel('John Doe, Owner'), findsOneWidget);
  });

  testWidgets('the bar is the old hub\'s 70 high', (tester) async {
    await _pump(tester, const HubTopBar(title: 'Smartcom'));
    expect(tester.getSize(find.byType(HubTopBar)).height, 70);
  });
}
