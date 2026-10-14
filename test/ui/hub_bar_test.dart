import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/hub_bar.dart';
import 'package:uzapay_pos/ui/tokens.dart';
import 'package:uzapay_pos/ui/top_bar.dart';

/// Mounts [bar] as the app bar of a page, at a tablet's width unless [size]
/// says otherwise, over [body].
Future<void> _pump(
  WidgetTester tester,
  HubTopBar bar, {
  Size size = const Size(1232, 800),
  Widget body = const SizedBox(),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(appBar: bar, body: body),
    ),
  );
  await tester.pump();
}

const _phone = Size(390, 844);

String _deviceSentence(WidgetTester tester) => tester
    .widget<Semantics>(find.byKey(const ValueKey('hub-status')))
    .properties
    .label!;

/// The colour the bar's surface is painted this frame.
Color _surface(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(TopBarSurface),
            matching: find.byType(ColoredBox),
          )
          .first,
    )
    .color;

void main() {
  group('the person\'s names', () {
    test('short: the first name and the last name\'s initial', () {
      expect(HubTopBar.shortName('Boniface Masota'), 'Boniface M.');
      expect(HubTopBar.shortName('  Amina  Wanjiru Otieno '), 'Amina O.');
      expect(HubTopBar.shortName('mziza'), 'mziza');
    });

    test('initials: the first name\'s and the last name\'s', () {
      expect(HubTopBar.initials('Amina Wanjiru'), 'AW');
      expect(HubTopBar.initials(' amina  wanjiru otieno '), 'AO');
      expect(HubTopBar.initials('mziza'), 'M');
      expect(HubTopBar.initials(null), '');
      expect(HubTopBar.initials('  '), '');
    });
  });

  group('the device\'s state', () {
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
      expect(_deviceSentence(tester), 'Terminal CT-7F2');

      readings.complete(true);
      await tester.pumpAndSettle();
      expect(_deviceSentence(tester), 'Online · Terminal CT-7F2');
      expect(find.text('Online · Terminal CT-7F2'), findsOneWidget);
    });

    testWidgets('follows the network, and says offline in words', (
      tester,
    ) async {
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
      expect(_deviceSentence(tester), 'Online · Terminal CT-7F2');

      changes.add(false);
      await tester.pumpAndSettle();
      expect(_deviceSentence(tester), 'Offline · Terminal CT-7F2');
      expect(find.text('Offline · Terminal CT-7F2'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });

    testWidgets('is not drawn without a terminal', (tester) async {
      await _pump(tester, const HubTopBar(title: 'Smartcom'));
      expect(find.byKey(const ValueKey('hub-status')), findsNothing);
    });

    testWidgets('on a phone, says nothing online and *Offline* offline', (
      tester,
    ) async {
      final changes = StreamController<bool>.broadcast();
      addTearDown(changes.close);
      await _pump(
        tester,
        HubTopBar(
          compact: true,
          title: 'Smartcom',
          terminalLabel: 'CT-7F2',
          onlineCheck: () async => true,
          onlineChanges: changes.stream,
        ),
        size: _phone,
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('hub-status')), findsNothing);

      changes.add(false);
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsOneWidget);
      // The whole sentence is still what a screen reader hears.
      expect(_deviceSentence(tester), 'Offline · Terminal CT-7F2');
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

  group('the person', () {
    testWidgets('is one control, with the short name from 768 up', (
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
      final account = find.byKey(const ValueKey('hub-account'));
      expect(
        find.descendant(of: account, matching: find.text('John D.')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: account, matching: find.text('JD')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('John Doe, Owner. Account'), findsOneWidget);
      // **The role is in the menu, not the bar.**
      expect(find.text('OWNER'), findsNothing);
    });

    testWidgets('is the circle alone on a phone', (tester) async {
      await _pump(
        tester,
        const HubTopBar(
          compact: true,
          title: 'Smartcom',
          memberName: 'John Doe',
          memberRole: 'Owner',
        ),
        size: _phone,
      );
      expect(find.text('JD'), findsOneWidget);
      expect(find.text('John D.'), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('hub-account'))),
        const Size(48, 48),
      );
    });

    testWidgets('opens the account menu: who, where, settings, the way out', (
      tester,
    ) async {
      var settings = 0;
      var signOut = 0;
      await _pump(
        tester,
        HubTopBar(
          title: 'Smartcom',
          terminalLabel: 'CT-7F2',
          onlineCheck: () async => true,
          memberName: 'John Doe',
          memberRole: 'Owner',
          onSettings: () => settings++,
          onSignOut: () => signOut++,
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('sign-out')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('hub-account')));
      await tester.pumpAndSettle();
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('Owner · Smartcom'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('hub-account-device')),
          matching: find.text('Online · Terminal CT-7F2'),
        ),
        findsOneWidget,
      );
      // Under the button, their trailing edges lined up.
      final menu = tester.getRect(find.byKey(const ValueKey('sign-out')));
      final button = tester.getRect(find.byKey(const ValueKey('hub-account')));
      expect(menu.top, greaterThan(button.bottom));
      expect(tester.getSize(find.byKey(const ValueKey('sign-out'))).height, 48);

      await tester.tap(find.byKey(const ValueKey('hub-settings')));
      await tester.pumpAndSettle();
      expect(settings, 1);
      // A row that was chosen closes the menu behind it.
      expect(find.byKey(const ValueKey('hub-settings')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('hub-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sign-out')));
      await tester.pumpAndSettle();
      expect(signOut, 1);
    });

    testWidgets('offers settings only to those it is given for', (
      tester,
    ) async {
      await _pump(
        tester,
        HubTopBar(
          title: 'Smartcom',
          memberName: 'Brian Kimani',
          memberRole: 'Cashier',
          onSignOut: () {},
        ),
      );
      await tester.tap(find.byKey(const ValueKey('hub-account')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hub-settings')), findsNothing);
      expect(find.byKey(const ValueKey('sign-out')), findsOneWidget);
    });

    testWidgets('a second press closes the menu, and so does Escape', (
      tester,
    ) async {
      await _pump(
        tester,
        HubTopBar(title: 'Smartcom', memberName: 'John Doe', onSignOut: () {}),
      );
      final account = find.byKey(const ValueKey('hub-account'));
      await tester.tap(account);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sign-out')), findsOneWidget);
      await tester.tap(account);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sign-out')), findsNothing);

      await tester.tap(account);
      await tester.pumpAndSettle();
      // From the button itself, where a keyboard user who opened it is.
      Focus.of(
        tester.element(find.descendant(of: account, matching: find.text('JD'))),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sign-out')), findsNothing);
    });
  });

  group('the bar\'s height', () {
    testWidgets('is 64 from 768 up', (tester) async {
      await _pump(tester, const HubTopBar(title: 'Smartcom'));
      expect(tester.getSize(find.byType(HubTopBar)).height, 64);
    });

    testWidgets('is 56 on a phone, with no mark', (tester) async {
      await _pump(
        tester,
        const HubTopBar(compact: true, title: 'Smartcom'),
        size: _phone,
      );
      expect(tester.getSize(find.byType(HubTopBar)).height, 56);
      // The name starts on the phone's 16 inset.
      expect(tester.getTopLeft(find.text('Smartcom')).dx, 16);
    });

    testWidgets('puts the name after the mark on the given inset', (
      tester,
    ) async {
      await _pump(
        tester,
        const HubTopBar(title: 'Smartcom', horizontalInset: 32),
      );
      // 32, the 24 mark, then 12.
      expect(tester.getTopLeft(find.text('Smartcom')).dx, 32 + 24 + 12);
    });
  });

  testWidgets('stands on the page, and lifts once content is under it', (
    tester,
  ) async {
    await _pump(
      tester,
      const HubTopBar(title: 'Smartcom'),
      body: ListView(
        children: <Widget>[for (var i = 0; i < 40; i++) Text('Row $i')],
      ),
    );
    final surface = AppTokens.componentOf(
      tester.element(find.byType(HubTopBar)),
    ).colors.surface;
    expect(_surface(tester), surface.base);

    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(_surface(tester), surface.raised);

    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(_surface(tester), surface.base);
  });
}
