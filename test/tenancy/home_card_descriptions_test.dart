import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/home_navigation.dart';
import 'package:uzapay_pos/ui/tokens.dart';

/// **Every home card's sentence fits two lines on the narrowest card a tablet
/// or a desktop draws.**
///
/// The developer asked on 2026-10-10 for every card's description to be two
/// lines, so the cards in a row are one shape. The card reserves the two lines
/// and stops at them; what keeps a sentence from ending in an ellipsis is the
/// sentence itself, and this is what holds each one to that.
///
/// **Real Roboto, not the test font**, because the test font draws every glyph
/// a full em wide and would wrap everything. The sentences are read out of
/// `_destinations` in `tenant_routing_shell.dart` rather than copied, so a new
/// tile or a rewritten line is measured the day it is written.
void main() {
  testWidgets('every description wraps to two lines at most', (tester) async {
    await tester.runAsync(() async {
      final roboto = FontLoader(AppTypeRoles.interfaceFamily);
      for (final face in const <String>[
        'Roboto-Regular.ttf',
        'Roboto-Medium.ttf',
        'Roboto-SemiBold.ttf',
        'Roboto-Bold.ttf',
      ]) {
        final bytes = await File('fonts/roboto/$face').readAsBytes();
        roboto.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      }
      await roboto.load();
    });

    final tokens = spiritTheme.extension<AppTokens>()!;
    // The style a card's sentence is painted in: the role, over the
    // `DefaultTextStyle` it inherits its tracking from.
    final style = spiritTheme.textTheme.bodyMedium!.merge(
      tokens.typography.moduleBody,
    );

    // The narrowest sentence the grid ever gives, found by asking it at every
    // window a tablet or a desktop can be: the page less its 32 a side, the
    // 20 between cards, and the card's own 20 of padding a side.
    double sentenceWidth(double window) {
      final columns = HomeModuleGrid.columnsFor(window);
      return (window -
                  2 * tokens.spacing.s32 -
                  (columns - 1) * tokens.spacing.s20) /
              columns -
          2 * tokens.spacing.s20;
    }

    var narrowest = double.infinity;
    for (var window = tokens.layout.mediumFloor; window <= 3840; window += 1) {
      final width = sentenceWidth(window);
      if (width < narrowest) narrowest = width;
    }

    final source = File(
      'lib/tenancy/tenant_routing_shell.dart',
    ).readAsStringSync();
    final start = source.indexOf('List<HomeDestination> _destinations(');
    expect(start, isNot(-1), reason: '_destinations moved or was renamed');
    final body = source.substring(start, source.indexOf('\n  }\n', start));
    final sentences = <String>[
      for (final match in RegExp(r"description:\s*'([^']+)'").allMatches(body))
        match.group(1)!,
    ];
    // Every tile but *Logs* carries one; fewer means the pattern stopped
    // matching how they are written, not that they all went away.
    expect(sentences.length, greaterThanOrEqualTo(15));

    for (final sentence in sentences) {
      final painter = TextPainter(
        text: TextSpan(text: sentence, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: narrowest);
      expect(
        painter.computeLineMetrics().length,
        lessThanOrEqualTo(2),
        reason:
            '"$sentence" runs past two lines at $narrowest wide. Shorten it: '
            'the card shows two lines and no more.',
      );
      painter.dispose();
    }
  });
}
