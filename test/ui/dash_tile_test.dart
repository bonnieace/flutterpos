import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/dash_tile.dart';

AppDashTile _tile(
  String key, {
  AppDashSpan span = AppDashSpan.one,
  bool tall = false,
  String? detail,
  VoidCallback? onPressed,
}) => AppDashTile(
  key: ValueKey(key),
  icon: Icons.storefront_outlined,
  accent: Colors.green,
  label: key,
  value: '1',
  detail: detail,
  span: span,
  tall: tall,
  visual: const SizedBox.expand(),
  footnote: 'footnote',
  onPressed: onPressed,
);

Future<void> _pump(
  WidgetTester tester,
  double width,
  List<AppDashTile> tiles,
) async {
  tester.view.physicalSize = Size(width, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: SingleChildScrollView(child: AppDashGrid(tiles: tiles)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('four small tiles share one row at expanded', (tester) async {
    await _pump(tester, 1440, <AppDashTile>[
      _tile('a'),
      _tile('b'),
      _tile('c'),
      _tile('d'),
      _tile('e', span: AppDashSpan.two, tall: true),
    ]);
    final a = tester.getRect(find.byKey(const ValueKey('a')));
    final d = tester.getRect(find.byKey(const ValueKey('d')));
    final e = tester.getRect(find.byKey(const ValueKey('e')));
    expect(d.top, a.top);
    expect(d.width, closeTo(a.width, 0.5));
    expect(e.top, greaterThan(a.bottom));
    expect(e.width, greaterThan(a.width * 2));
  });

  testWidgets('every tile in a row is the row’s height', (tester) async {
    await _pump(tester, 1440, <AppDashTile>[
      _tile('short'),
      _tile('long', detail: 'a context line that is long'),
      _tile('c'),
      _tile('d'),
    ]);
    expect(
      tester.getSize(find.byKey(const ValueKey('short'))).height,
      tester.getSize(find.byKey(const ValueKey('long'))).height,
    );
  });

  testWidgets('on a phone, two across, and a tall tile takes the row', (
    tester,
  ) async {
    await _pump(tester, 411, <AppDashTile>[
      _tile('a'),
      _tile('b'),
      _tile('tall', tall: true),
    ]);
    final a = tester.getRect(find.byKey(const ValueKey('a')));
    final b = tester.getRect(find.byKey(const ValueKey('b')));
    final tall = tester.getRect(find.byKey(const ValueKey('tall')));
    expect(b.top, a.top);
    expect(tall.top, greaterThan(a.bottom));
    expect(tall.width, greaterThan(a.width * 2));
  });

  testWidgets('the whole tile is the target', (tester) async {
    var pressed = 0;
    await _pump(tester, 1440, <AppDashTile>[
      _tile('a', onPressed: () => pressed++),
    ]);
    await tester.tap(find.text('footnote'));
    expect(pressed, 1);
  });
}
