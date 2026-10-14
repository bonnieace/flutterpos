import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/illustration.dart';
import 'package:uzapay_pos/ui/states.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:uzapay_pos/ui/tokens.dart';

import '../support/wcag.dart';

void main() {
  final tokens = spiritTheme.extension<AppTokens>()!;

  testWidgets('centered artwork fits a narrow screen with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: spiritTheme,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: IllustratedMessage(
                  textKey: ValueKey('empty-stock-message'),
                  illustration: 'stock-movements.svg',
                  message: 'No stock movements yet.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('empty-stock-message')), findsOneWidget);
    final art = tester.getRect(find.byType(AppIllustration));
    final copy = tester.getRect(
      find.byKey(const ValueKey('empty-stock-message')),
    );
    expect(art.width, AppIllustration.sceneSize);
    expect(art.center.dx, closeTo(160, 0.5));
    expect(copy.center.dx, closeTo(art.center.dx, 0.5));
    expect(copy.top, greaterThan(art.bottom));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('empty-stock-message')))
          .textAlign,
      TextAlign.center,
    );
    expect(
      tester.widget<SvgPicture>(find.byType(SvgPicture)).excludeFromSemantics,
      isTrue,
    );
  });

  testWidgets('artwork in a notice preserves its status glyph and message', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: spiritTheme,
        home: const Scaffold(
          body: Callout(
            status: AppStatus.info,
            illustration: 'printer-connection.svg',
            message: 'Switch the printer on and search again.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(AppStatus.info.defaultIcon), findsOneWidget);
    expect(
      find.text('Switch the printer on and search again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    final art = tester.getRect(find.byType(AppIllustration));
    final copy = tester.getRect(
      find.text('Switch the printer on and search again.'),
    );
    final notice = tester.getRect(find.byType(Callout));
    expect(art.width, AppIllustration.sceneSize);
    expect(art.center.dx, closeTo(notice.center.dx, 0.5));
    expect(copy.center.dx, closeTo(notice.center.dx, 0.5));
    expect(copy.top, greaterThan(art.bottom));
  });

  test('artwork pigments separate from both page and dialog grounds', () {
    for (final paint in AppIllustrationPaint.values) {
      // Symbol ink is drawn inside light accents, never on the page ground.
      if (paint == AppIllustrationPaint.onAccent) continue;
      for (final ground in [
        tokens.colors.surface.base,
        tokens.colors.surface.raised,
      ]) {
        expect(
          contrastRatio(tokens.colors.illustration[paint], ground),
          greaterThanOrEqualTo(3),
          reason: '${paint.name} fades into an illustration background',
        );
      }
    }
  });

  test('symbol ink contrasts with every light accent', () {
    final palette = tokens.colors.illustration;
    for (final accent in [
      AppIllustrationPaint.jade,
      AppIllustrationPaint.teal,
      AppIllustrationPaint.sky,
      AppIllustrationPaint.violet,
      AppIllustrationPaint.coral,
      AppIllustrationPaint.amber,
    ]) {
      expect(
        contrastRatio(palette[AppIllustrationPaint.onAccent], palette[accent]),
        greaterThanOrEqualTo(3),
        reason: accent.name,
      );
    }
  });

  test('authored paint markers and gradient references resolve', () {
    final roles = AppIllustrationPaint.values.map((role) => role.name).toSet();
    for (final file in Directory('assets/illustrations').listSync()) {
      if (file is! File || !file.path.endsWith('.svg')) continue;
      final svg = file.readAsStringSync();
      final ids = RegExp(
        r'\bid="([^"]+)"',
      ).allMatches(svg).map((match) => match.group(1)!).toList();
      expect(ids.toSet().length, ids.length, reason: file.path);
      for (final id in ids.where((id) => id.contains('--paint-'))) {
        expect(roles, contains(id.split('--paint-').last), reason: file.path);
      }
      for (final reference in RegExp(r'url\(#([^\)]+)\)').allMatches(svg)) {
        expect(ids, contains(reference.group(1)), reason: file.path);
      }
    }
  });

  testWidgets(
    'paper and skin keep their materials; detail overrides keep alpha',
    (tester) async {
      final mapper = await _mapper(tester, 'approve.svg');
      final paper = mapper.substitute(
        null,
        'path',
        'fill',
        const Color(0xFFF2F2F2),
      );
      final skin = mapper.substitute(
        null,
        'path',
        'fill',
        const Color(0xFFED9DA0),
      );
      expect(paper.computeLuminance(), greaterThan(0.7));
      expect(skin.r, greaterThan(skin.g));
      expect(skin.g, greaterThan(skin.b));
      final sleeve = mapper.substitute(
        'art-sleeve--paint-coral',
        'path',
        'fill',
        const Color(0x80E6E6E6),
      );
      expect(
        sleeve.withValues(alpha: 1),
        tokens.colors.illustration[AppIllustrationPaint.coral],
      );
      expect(sleeve.a, closeTo(128 / 255, 0.001));
      expect(
        mapper.substitute(null, 'path', 'fill', Colors.transparent),
        Colors.transparent,
      );
    },
  );

  testWidgets(
    'unknown colors retain hue and scene accents use separate cache keys',
    (tester) async {
      final calendar = await _mapper(tester, 'calendar.svg');
      final wallet = await _mapper(tester, 'empty-wallet.svg');
      final original = HSLColor.fromColor(const Color(0xFF723C15));
      final painted = HSLColor.fromColor(
        calendar.substitute(null, 'path', 'fill', original.toColor()),
      );
      // SVG colors round-trip through 8-bit channels.
      expect(painted.hue, closeTo(original.hue, 0.1));
      expect(painted.lightness, closeTo(0.52, 1 / 255));
      expect(calendar, isNot(wallet));
      expect(
        calendar.substitute(null, 'path', 'fill', const Color(0xFF6C63FF)),
        isNot(wallet.substitute(null, 'path', 'fill', const Color(0xFF6C63FF))),
      );
    },
  );
}

Future<ColorMapper> _mapper(WidgetTester tester, String asset) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: AppIllustration(asset: asset, size: 168),
    ),
  );
  await tester.pumpAndSettle();
  final loader =
      tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader
          as SvgAssetLoader;
  return loader.colorMapper!;
}
