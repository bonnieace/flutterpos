/// The wording and the affordances, tested without pumping a widget.
///
/// **This is where the feature lives.** A notification page is its vocabulary
/// and its honesty about what can be done; the screen above it is a layout.
library;

import 'package:uzapay_pos/checkout/checkout_notification_sources.dart';
import 'package:uzapay_pos/shift/abandoned_shift.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

AbandonedShift _shift({
  String shiftId = 'shift-a',
  String? staffName = 'Asha',
  String businessDate = '2026-09-15',
}) => AbandonedShift(
  shiftId: shiftId,
  staffId: 'user-a',
  staffName: staffName,
  businessDate: businessDate,
);

void main() {
  group('abandoned shift notifications', () {
    test('names the person, because an id recognises nobody', () {
      final items = abandonedShiftNotifications(<AbandonedShift>[_shift()]);

      expect(items, hasLength(1));
      expect(items.single.title, startsWith('Asha'));
      expect(items.single.summary, '2026-09-15');
      expect(items.single.status, AppStatus.problem);
    });

    test('falls back to a person rather than printing a uid', () {
      final items = abandonedShiftNotifications(<AbandonedShift>[
        _shift(staffName: null),
      ]);

      expect(items.single.title, startsWith('A cashier'));
      expect(items.single.title, isNot(contains('user-a')));
    });

    test('says the close records no takings, before it is pressed', () {
      // The one thing an owner must understand before ending somebody else's
      // shift: this states nothing about the drawer, and reconciliation will
      // report it as unverifiable rather than as a shift that took nothing.
      final items = abandonedShiftNotifications(<AbandonedShift>[_shift()]);

      expect(items.single.detail, contains('records no takings'));
      expect(items.single.detail, contains('unverifiable'));
    });

    test('offers no control where the session may not close one', () {
      // A button that cannot work is worse than none: the row stays a
      // statement.
      final items = abandonedShiftNotifications(<AbandonedShift>[_shift()]);

      expect(items.single.actions, isEmpty);
    });

    test('the close is destructive and carries the shift it would end', () {
      AbandonedShift? closed;
      final items = abandonedShiftNotifications(<AbandonedShift>[
        _shift(),
      ], onClose: (shift) => closed = shift);

      final action = items.single.actions.single;
      expect(action.destructive, isTrue);
      action.onPressed!();
      expect(closed!.shiftId, 'shift-a');
    });

    test('only the shift being closed is busy', () {
      final items = abandonedShiftNotifications(
        <AbandonedShift>[_shift(), _shift(shiftId: 'shift-b')],
        onClose: (_) {},
        busyShiftId: 'shift-b',
      );

      expect(items.first.busy, isFalse);
      expect(items.last.busy, isTrue);
    });
  });
}
