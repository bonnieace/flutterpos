/// The notification feed, in every state it can be in.
///
/// **A component ships with its states, and these are them**: a row that can be
/// acted on, one that cannot, one whose action is running, one that expands,
/// one that may be dismissed and one that may not, and a feed with nothing in
/// it at all. The severity cases are here for a harder reason than coverage -
/// status may never be carried by colour alone, and the only way to keep that
/// true is to assert the glyph and the words.
library;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/notification_feed.dart';
import 'package:uzapay_pos/ui/states.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:uzapay_pos/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

final _tokens = spiritTheme.extension<AppTokens>()!;

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppNotificationItem _item({
  String id = 'n1',
  AppStatus status = AppStatus.attention,
  String title = 'Receipt not printed',
  String? summary,
  String? detail,
  String? sourceLabel,
  String? timeLabel,
  List<AppNotificationAction> actions = const <AppNotificationAction>[],
  VoidCallback? onDismiss,
  bool busy = false,
}) => AppNotificationItem(
  id: id,
  status: status,
  title: title,
  summary: summary,
  detail: detail,
  sourceLabel: sourceLabel,
  timeLabel: timeLabel,
  actions: actions,
  onDismiss: onDismiss,
  busy: busy,
);

void main() {
  testWidgets('an empty feed draws the caller words, not a bare box', (
    tester,
  ) async {
    await _pump(
      tester,
      const AppNotificationFeed(
        items: <AppNotificationItem>[],
        empty: EmptyState(
          key: ValueKey('feed-empty'),
          title: 'Nothing is waiting',
          hint: 'Everything on this device has gone through.',
          illustration: 'approve.svg',
        ),
      ),
    );

    expect(find.byKey(const ValueKey('feed-empty')), findsOneWidget);
    expect(find.text('Nothing is waiting'), findsOneWidget);
  });

  testWidgets('a row states what happened and where it came from', (
    tester,
  ) async {
    await _pump(
      tester,
      AppNotificationFeed(
        items: <AppNotificationItem>[
          _item(
            summary: 'CT-A1B-20260915-0042',
            sourceLabel: 'Till 2',
            timeLabel: '20h ago',
          ),
        ],
      ),
    );

    expect(find.text('Receipt not printed'), findsOneWidget);
    expect(find.text('CT-A1B-20260915-0042'), findsOneWidget);
    expect(find.text('Till 2'), findsOneWidget);
    expect(find.text('20h ago'), findsOneWidget);
  });

  testWidgets('severity is a glyph and a word, never the tint alone', (
    tester,
  ) async {
    // **The accessibility rule, asserted rather than hoped for.** Each status
    // carries its own icon out of the token layer and names itself in the
    // row's semantics, so the list reads the same to somebody who cannot tell
    // the tints apart.
    const cases = <(AppStatus, String)>[
      (AppStatus.ok, 'Done'),
      (AppStatus.attention, 'Waiting'),
      (AppStatus.problem, 'Problem'),
      (AppStatus.info, 'Information'),
      (AppStatus.neutral, 'Closed'),
    ];
    for (final (status, word) in cases) {
      await _pump(
        tester,
        AppNotificationFeed(
          items: <AppNotificationItem>[_item(status: status, title: 'A thing')],
        ),
      );
      expect(
        find.byIcon(status.defaultIcon),
        findsOneWidget,
        reason: '$status must be distinguishable by shape.',
      );
      expect(
        find.bySemanticsLabel(RegExp('^$word\\. A thing')),
        findsOneWidget,
        reason: '$status must name itself in words.',
      );
    }
  });

  testWidgets('a row with no detail offers no way to expand', (tester) async {
    // An affordance that opens onto nothing is worse than no affordance.
    await _pump(
      tester,
      AppNotificationFeed(items: <AppNotificationItem>[_item()]),
    );

    expect(find.byKey(const ValueKey('notification-expand-n1')), findsNothing);
    expect(find.byKey(const ValueKey('notification-detail-n1')), findsNothing);
  });

  testWidgets('a row with detail reveals it and puts its actions with it', (
    tester,
  ) async {
    var reprinted = 0;
    await _pump(
      tester,
      AppNotificationFeed(
        items: <AppNotificationItem>[
          _item(
            detail: 'The printer refused the job: no route to the host.',
            actions: <AppNotificationAction>[
              AppNotificationAction(
                label: 'Reprint',
                actionKey: const ValueKey('reprint'),
                onPressed: () => reprinted++,
              ),
            ],
          ),
        ],
      ),
    );

    expect(find.byKey(const ValueKey('notification-detail-n1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('notification-expand-n1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('notification-detail-n1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('reprint')));
    await tester.pumpAndSettle();
    expect(reprinted, 1);
  });

  testWidgets('a busy row refuses a second press of the same thing', (
    tester,
  ) async {
    var reprinted = 0;
    await _pump(
      tester,
      AppNotificationFeed(
        items: <AppNotificationItem>[
          _item(
            busy: true,
            actions: <AppNotificationAction>[
              AppNotificationAction(
                label: 'Reprint',
                actionKey: const ValueKey('reprint'),
                onPressed: () => reprinted++,
              ),
            ],
          ),
        ],
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('reprint')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    // The words stay on screen; only the press is refused. A row that swapped
    // itself for a spinner would take the sentence away from whoever was
    // reading it.
    expect(find.text('Reprint'), findsOneWidget);
    expect(find.text('Receipt not printed'), findsOneWidget);
    expect(reprinted, 0);
  });

  testWidgets('dismissal is offered only where it is allowed', (tester) async {
    var dismissed = 0;
    await _pump(
      tester,
      AppNotificationFeed(
        items: <AppNotificationItem>[
          _item(id: 'keepable', onDismiss: () => dismissed++),
          _item(id: 'permanent'),
        ],
      ),
    );

    expect(
      find.byKey(const ValueKey('notification-dismiss-permanent')),
      findsNothing,
      reason:
          'A receipt that has not printed is not something a person may '
          'decide is no longer true.',
    );
    await tester.tap(
      find.byKey(const ValueKey('notification-dismiss-keepable')),
    );
    await tester.pumpAndSettle();
    expect(dismissed, 1);
  });

  testWidgets('every control keeps the density minimum tap target', (
    tester,
  ) async {
    await _pump(
      tester,
      AppNotificationFeed(
        items: <AppNotificationItem>[
          _item(detail: 'Something worth reading.', onDismiss: () {}),
        ],
      ),
    );

    final minimum = _tokens.density.minimumTapTarget;
    for (final key in <ValueKey<String>>[
      const ValueKey('notification-expand-n1'),
      const ValueKey('notification-dismiss-n1'),
    ]) {
      final size = tester.getSize(find.byKey(key));
      expect(
        size.width,
        greaterThanOrEqualTo(minimum.width),
        reason: '$key is too narrow to hit.',
      );
      expect(
        size.height,
        greaterThanOrEqualTo(minimum.height),
        reason: '$key is too short to hit.',
      );
    }
  });

  testWidgets('a footer rides under the rows rather than beside them', (
    tester,
  ) async {
    await _pump(
      tester,
      AppNotificationFeed(
        items: <AppNotificationItem>[_item()],
        footer: const Text('Mark all as read'),
      ),
    );

    expect(find.text('Mark all as read'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Mark all as read')).dy,
      greaterThan(tester.getTopLeft(find.text('Receipt not printed')).dy),
    );
  });
}
