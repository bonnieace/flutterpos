/// The till's shift gate, which had no test until the day it crashed a device.
///
/// **What every case here holds fixed is the ownership.** `main.dart` caches one
/// `TenantShiftController` per session and hands the same instance to the gate
/// and to the close sheet the gate opens, so `sharedShiftControllerFactory` is
/// what these tests build with. Under a factory that mints one per call - which
/// is what this suite's neighbours used to pass, and what the screenshot harness
/// passed - none of these tests can fail, and the crash of 2026-08-27 walks
/// straight through: the shift panel disposed the shared controller on the way
/// out, and the next `addListener` threw *A TenantShiftController was used
/// after being disposed* over the whole route.
///
/// **The close is one tap from the exit dialog since 2026-09-03.** It used to
/// push a page whose only content was a button that opened this sheet, so every
/// case below lost a `close-shift` tap and a `_pop`.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/reporting/reporting_currency.dart';
import 'package:flutter_application_1/shift/shift.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/routes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../support/shift_fakes.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late HiveTenantShiftState state;
  late ShiftServer server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shift-gate-test-');
    Hive.init(directory.path);
    box = await openShiftTestBox();
    state = HiveTenantShiftState.fromBox(
      box,
      clock: () => DateTime.utc(2026, 7, 31, 9),
    );
    server = ShiftServer();
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  testWidgets('draws the till for a shift this device already has open', (
    tester,
  ) async {
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
    await state.save(shiftRecord());

    await _pumpHome(tester, state, server);
    await _enterTill(tester);

    expect(find.byKey(_till), findsOneWidget);
    expect(find.byKey(const ValueKey('shift-gate-open')), findsNothing);
  });

  testWidgets('blocks the till with a modal when no shift is open', (
    tester,
  ) async {
    await _pumpHome(tester, state, server);
    await _enterTill(tester);

    expect(find.byKey(const ValueKey('shift-gate-blocked')), findsOneWidget);
    expect(find.byKey(const ValueKey('shift-gate-open')), findsOneWidget);
    expect(find.byKey(_till), findsNothing);
  });

  testWidgets('opening a shift from the modal reveals the till', (
    tester,
  ) async {
    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    await _tap(tester, const ValueKey('shift-gate-open'));

    expect(find.byKey(_till), findsOneWidget);
    expect(server.created, hasLength(1));
  });

  testWidgets('opening with a float records what was in the drawer', (
    tester,
  ) async {
    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    await tester.enterText(
      find.byKey(const ValueKey('shift-gate-opening-float')),
      '2000',
    );
    await _tap(tester, const ValueKey('shift-gate-open'));

    expect(find.byKey(_till), findsOneWidget);
    expect(server.created.single.$2['openingFloatMinor'], 200000);
  });

  testWidgets('an empty float box is no float, not a refusal', (tester) async {
    // Most shops keep no change in the drawer. Requiring all of them to type a
    // zero to open a till teaches every cashier to clear one more box without
    // reading it, which is the opposite of what asking is for.
    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    await _tap(tester, const ValueKey('shift-gate-open'));

    expect(find.byKey(_till), findsOneWidget);
    expect(server.created.single.$2.containsKey('openingFloatMinor'), isFalse);
  });

  testWidgets('a float that cannot be read refuses to open the shift', (
    tester,
  ) async {
    // **Refused rather than sent as a zero.** A figure that will not parse is
    // not a shift with no float: the cashier meant to record one, and opening
    // without it would quietly bill them for it at close.
    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    await tester.enterText(
      find.byKey(const ValueKey('shift-gate-opening-float')),
      '1.2.3',
    );
    await _tap(tester, const ValueKey('shift-gate-open'));

    expect(server.created, isEmpty);
    expect(find.byKey(_till), findsNothing);
    expect(find.text('Enter an amount, like 2000 or 1500.50.'), findsOneWidget);
  });

  testWidgets('leaving the modal leaves the till rather than selling', (
    tester,
  ) async {
    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    await _tap(tester, const ValueKey('shift-gate-leave'));

    // Back on the home: the till went with the refusal to open a shift.
    expect(find.byKey(_home), findsOneWidget);
    expect(find.byKey(_till), findsNothing);
    expect(server.created, isEmpty);
  });

  // **The regression.** Nothing about this journey is unusual - a cashier looks
  // at the close surface and goes back to selling - and before 2026-08-27 the
  // second entry threw during build, because popping the shift manager disposed
  // the controller the whole session shares.
  testWidgets('a till re-entered after the shift manager still opens', (
    tester,
  ) async {
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
    await state.save(shiftRecord());

    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    expect(find.byKey(_till), findsOneWidget);

    // Out through the exit dialog's *Close shift*, which opens the counting
    // sheet, then straight back out of it without closing anything.
    await _openCloseSheet(tester);
    await _tap(tester, const ValueKey('cancel-cash-count'));

    // Back at the till, and out to the home.
    expect(find.byKey(_till), findsOneWidget);
    await _leaveTill(tester);
    await _tap(tester, const ValueKey('shift-exit-step-away'));
    expect(find.byKey(_home), findsOneWidget);

    // The second entry builds a fresh gate against the same session, which is
    // where a disposed controller is first touched.
    await _enterTill(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(_till), findsOneWidget);
  });

  // The journey the product owner reported, end to end.
  testWidgets(
    'an expired shift closes, a replacement opens, and the till returns',
    (tester) async {
      server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
      // Twenty-five hours, against the controller's 24-hour cap.
      await state.save(shiftRecord(openedAt: DateTime.utc(2026, 7, 30, 8)));

      await _pumpHome(tester, state, server);
      await _enterTill(tester);

      // No till: an expired shift may be closed and nothing else.
      expect(find.byKey(const ValueKey('shift-gate-expired')), findsOneWidget);
      expect(find.byKey(_till), findsNothing);

      // The expired screen opens the sheet directly, with the count already
      // running - there is nothing else to do with an expired shift.
      await _tap(tester, const ValueKey('shift-gate-close'));
      await tester.enterText(find.byKey(const ValueKey('declared-cash')), '0');
      await _settle(tester);
      await _tap(tester, const ValueKey('close-shift-confirm'));

      // The close reports on the surface it was taken on, and is dismissed
      // deliberately rather than vanishing from under the person.
      expect(find.byKey(const ValueKey('shift-close-heading')), findsOneWidget);
      await _tap(tester, const ValueKey('shift-close-done'));

      // The gate notices there is no shift and raises its modal - this is the
      // "open a new shift" prompt in the same flow.
      expect(find.byKey(const ValueKey('shift-gate-open')), findsOneWidget);
      await _tap(tester, const ValueKey('shift-gate-open'));
      expect(tester.takeException(), isNull);
      expect(find.byKey(_till), findsOneWidget);
      expect(server.created, hasLength(1));
      expect(
        await state.read(uid: 'user-a', tenantId: 'tenant-a'),
        isNotNull,
        reason: 'The replacement shift is this device\'s durable record.',
      );
    },
  );

  testWidgets('an orphaned shift can be closed from the modal that refuses it', (
    tester,
  ) async {
    // **The dead end this removes.** A shift opened by an installation this
    // device no longer is cannot be adopted - the closing summary comes from
    // local sale evidence, which that install took with it - and until now the
    // refusal was all there was: `Open shift` repeated it, and the only remedy
    // was an edit to the database. The control that resolves it lives in the
    // close sheet, and this modal is the one surface that could open it.
    server.shifts['tenants/tenant-a/shifts/shift-elsewhere'] = shiftDocument(
      overrides: <String, Object?>{
        'shiftId': 'shift-elsewhere',
        'deviceId': _deviceEarlierInstall,
      },
    );

    await _pumpHome(tester, state, server);
    await _enterTill(tester);

    expect(
      find.text(shiftErrorMessage('shift_open_on_earlier_install')),
      findsOneWidget,
    );
    await _tap(tester, const ValueKey('shift-gate-close-orphan'));

    // The same three boxes an ordinary close asks for: a declaration needs no
    // sale evidence, and the server derives the other side of the comparison
    // itself - so a recovery close records more than the refusal it replaces.
    await tester.enterText(
      find.byKey(const ValueKey('declared-cash')),
      '250.00',
    );
    await _settle(tester);
    await _tap(tester, const ValueKey('close-orphan-shift'));

    // Zero totals under the marker, so reconciliation refuses the figures
    // rather than reading them as a shift that took nothing.
    final written = server.updated.single.$2;
    expect(server.updated.single.$1, 'tenants/tenant-a/shifts/shift-elsewhere');
    expect(written['closedWithoutEvidence'], isTrue);
    expect(written['totalSalesMinor'], 0);
    expect(written['transactionCount'], 0);
    expect(written['declaredCashMinor'], 25000);
  });

  testWidgets('a drawer the closer does not hold is closed without a count', (
    tester,
  ) async {
    // **The other half of the recovery close, and the one that was implicit.**
    // Leaving the boxes blank used to record *counted, and it held nothing* -
    // indistinguishable from a cashier who really had counted an empty till.
    // Now that the count is marked against the sales the server holds, that
    // silence would report the drawer's whole contents as missing, the opening
    // float included. The two answers are two controls.
    server.shifts['tenants/tenant-a/shifts/shift-elsewhere'] = shiftDocument(
      overrides: <String, Object?>{
        'shiftId': 'shift-elsewhere',
        'deviceId': _deviceEarlierInstall,
      },
    );
    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    await _tap(tester, const ValueKey('shift-gate-close-orphan'));
    await _settle(tester);
    await _tap(tester, const ValueKey('close-orphan-uncounted'));

    final written = server.updated.single.$2;
    expect(written['closedWithoutEvidence'], isTrue);
    // No declared keys at all: reconciliation reads their absence as nothing
    // to compare, which is exactly what this person is saying.
    expect(written.containsKey('declaredCashMinor'), isFalse);
    expect(written.containsKey('declaredMpesaMinor'), isFalse);
    expect(written.containsKey('declaredCardMinor'), isFalse);
    expect(written['closingCashMinor'], 0);
  });

  testWidgets('an untouched recovery form is refused rather than read as zero', (
    tester,
  ) async {
    // Everywhere else on this sheet an empty box is a legitimate zero, because
    // the cashier is holding the drawer. Here it is the one thing it must not
    // mean, so pressing the count control with nothing typed says so.
    server.shifts['tenants/tenant-a/shifts/shift-elsewhere'] = shiftDocument(
      overrides: <String, Object?>{
        'shiftId': 'shift-elsewhere',
        'deviceId': _deviceEarlierInstall,
      },
    );
    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    await _tap(tester, const ValueKey('shift-gate-close-orphan'));
    await _settle(tester);
    await _tap(tester, const ValueKey('close-orphan-shift'));

    expect(server.updated, isEmpty);
    expect(
      find.text('Enter what you counted, or close without counting.'),
      findsWidgets,
    );
  });

  testWidgets('one count closes both shifts when a second is open', (
    tester,
  ) async {
    // **One drawer answering to two shifts.** The guard that keeps a cashier to
    // one open shift reads only this device, so two tills can both pass it in
    // the same moment - and the cashier then meets one till that has to be
    // counted twice. Counting it twice cannot be done truthfully: the money is
    // already declared onto the shift they just closed.
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
    server.shifts['tenants/tenant-a/shifts/shift-elsewhere'] = shiftDocument(
      overrides: <String, Object?>{
        'shiftId': 'shift-elsewhere',
        'deviceId': _deviceEarlierInstall,
      },
    );
    await state.save(shiftRecord());

    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    await _openCloseSheet(tester);
    await tester.enterText(
      find.byKey(const ValueKey('declared-cash')),
      '250.00',
    );
    await _settle(tester);
    await _tap(tester, const ValueKey('close-shift-confirm'));
    await _settle(tester);

    expect(tester.takeException(), isNull);
    final byPath = <String, Map<String, Object?>>{
      for (final write in server.updated) write.$1: write.$2,
    };
    expect(byPath.keys, hasLength(2));

    // The shift that was counted carries the count, and its own sale evidence.
    final counted = byPath['tenants/tenant-a/shifts/shift-a']!;
    expect(counted['declaredCashMinor'], 25000);
    expect(counted.containsKey('closedWithoutEvidence'), isFalse);

    // The other one is closed and declares nothing. Zero is not a count here,
    // and the absent declared keys are what stop one drawer being recorded
    // twice - `compareShiftTenders` reads the marker and does not compare.
    final other = byPath['tenants/tenant-a/shifts/shift-elsewhere']!;
    expect(other['closedWithoutEvidence'], isTrue);
    expect(other['totalSalesMinor'], 0);
    expect(other['transactionCount'], 0);
    expect(other['closingCashMinor'], 0);
    expect(other.containsKey('declaredCashMinor'), isFalse);
    expect(other.containsKey('declaredMpesaMinor'), isFalse);
    expect(other.containsKey('declaredCardMinor'), isFalse);

    // And the person reads that it happened, because it is their name on it.
    expect(
      find.byKey(const ValueKey('shift-close-other-shift')),
      findsOneWidget,
    );
  });

  testWidgets('an ordinary close says nothing about a second shift', (
    tester,
  ) async {
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
    await state.save(shiftRecord());

    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    await _openCloseSheet(tester);
    await tester.enterText(find.byKey(const ValueKey('declared-cash')), '0');
    await _settle(tester);
    await _tap(tester, const ValueKey('close-shift-confirm'));
    await _settle(tester);

    expect(server.updated, hasLength(1));
    expect(
      find.byKey(const ValueKey('shift-close-other-shift')),
      findsNothing,
      reason: 'There was no second shift, so there is nothing to report.',
    );
  });

  testWidgets('the modal stops refusing once the orphan is gone', (
    tester,
  ) async {
    // The dialog used to read the controller once and keep whatever it drew, so
    // a refusal outlived the thing it refused: the shift was closed and the
    // modal still said it was open somewhere else.
    server.shifts['tenants/tenant-a/shifts/shift-elsewhere'] = shiftDocument(
      overrides: <String, Object?>{
        'shiftId': 'shift-elsewhere',
        'deviceId': _deviceEarlierInstall,
      },
    );

    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    expect(
      find.byKey(const ValueKey('shift-gate-close-orphan')),
      findsOneWidget,
    );

    await _tap(tester, const ValueKey('shift-gate-close-orphan'));
    await tester.enterText(find.byKey(const ValueKey('declared-cash')), '0');
    await _settle(tester);
    await _tap(tester, const ValueKey('close-orphan-shift'));
    await _tap(tester, const ValueKey('shift-close-done'));

    // The refusal and the control that answered it both go, and `Open shift`
    // is what is left - which is the whole point of the journey.
    expect(find.byKey(const ValueKey('shift-gate-close-orphan')), findsNothing);
    expect(find.byKey(const ValueKey('shift-gate-error')), findsNothing);
    expect(find.byKey(const ValueKey('shift-gate-open')), findsOneWidget);
  });

  testWidgets("another phone's shift is never offered for closing", (
    tester,
  ) async {
    // **The incident this exists for.** On 2026-09-17 this control closed a
    // shift on a phone that was not gone at all - it was offline, mid-count,
    // with one unsent sale left to send - and the count it had taken was
    // discarded with it. `otherDeviceShiftId` now names a shift only where the
    // durable half of the device id matches, so a shift like this one names
    // nothing and the button never appears.
    server.shifts['tenants/tenant-a/shifts/shift-elsewhere'] = shiftDocument(
      overrides: <String, Object?>{
        'shiftId': 'shift-elsewhere',
        'deviceId': _deviceOtherPhone,
      },
    );

    await _pumpHome(tester, state, server);
    await _enterTill(tester);

    expect(find.byKey(const ValueKey('shift-gate-close-orphan')), findsNothing);
  });

  testWidgets('a refused open keeps the modal up and states the reason', (
    tester,
  ) async {
    // A shift this cashier has open in another business: the controller
    // refuses rather than opening a second one on the same device.
    await state.save(shiftRecord(tenantId: 'tenant-b', shiftId: 'shift-b'));

    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    await _tap(tester, const ValueKey('shift-gate-open'));

    // **The words, not just the callout.** This assertion came from the shift
    // panel's suite on 2026-09-03: the card that used to carry it is gone, and
    // the gate's modal is the only surface that reports a refused open.
    expect(find.byKey(const ValueKey('shift-gate-error')), findsOneWidget);
    expect(
      find.text(shiftErrorMessage('other_tenant_shift_open')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('shift-gate-open')), findsOneWidget);
    expect(find.byKey(_till), findsNothing);
    expect(server.created, isEmpty);
  });

  testWidgets('reports unavailable shift state without internal details', (
    tester,
  ) async {
    // A record this build cannot read. Also from the panel's suite: the gate
    // draws the only surface a cashier meets when the state is unreadable.
    await box.put('user-a:tenant-a', <String, Object?>{'schemaVersion': 99});

    await _pumpHome(tester, state, server);
    await _enterTill(tester);

    expect(
      find.byKey(const ValueKey('shift-gate-unavailable')),
      findsOneWidget,
    );
    expect(find.byKey(_till), findsNothing);
    expect(find.textContaining('malformed_shift_state'), findsNothing);
  });

  testWidgets('two taps on the modal open one shift', (tester) async {
    await _pumpHome(tester, state, server);
    await _enterTill(tester);

    final open = find.byKey(const ValueKey('shift-gate-open'));
    await tester.tap(open);
    // Inside the same frame, before the first open has published anything.
    await tester.pump();
    if (open.evaluate().isNotEmpty) await tester.tap(open, warnIfMissed: false);
    await _settle(tester);

    expect(server.created, hasLength(1));
    expect(find.byKey(_till), findsOneWidget);
  });

  testWidgets('a cancelled cash count leaves the shift open', (tester) async {
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
    await state.save(shiftRecord());

    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    // Opening the sheet is what starts the count, so cancelling is the only
    // way back out of one without closing the shift.
    await _openCloseSheet(tester);
    await _tap(tester, const ValueKey('cancel-cash-count'));

    final record = await state.read(uid: 'user-a', tenantId: 'tenant-a');
    expect(record, isNotNull);
    expect(record!.closeInProgress, isFalse);
    expect(server.updated, isEmpty);

    // And the till is still in service behind the sheet that just closed.
    expect(find.byKey(_till), findsOneWidget);
  });

  testWidgets('a close with no connection is recorded rather than refused', (
    tester,
  ) async {
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
    await state.save(shiftRecord());

    // Online to read the shift, offline by the time the close is attempted.
    var online = true;
    await _pumpHome(tester, state, server, isOnline: () async => online);
    await _enterTill(tester);
    await _openCloseSheet(tester);
    await tester.enterText(find.byKey(const ValueKey('declared-cash')), '0');
    await _settle(tester);

    online = false;
    await _tap(tester, const ValueKey('close-shift-confirm'));
    await _settle(tester);

    expect(tester.takeException(), isNull);
    // **Refused outright until 2026-09-05.** A shop that had counted its cash
    // was left holding an open shift it could not finish, with the till still
    // selling against it. The count is kept here and sent on reconnect.
    expect(server.updated, isEmpty);
    final record = await state.read(uid: 'user-a', tenantId: 'tenant-a');
    expect(record, isNotNull);
    expect(
      record!.closedAt,
      isNotNull,
      reason: 'The close is a fact about this device now.',
    );
    // The declaration, not a bare cash figure: all three methods were asked
    // for and all three are what gets replayed.
    expect(record.declaration, ShiftTenderDeclaration.zero);
  });

  testWidgets('popping the close sheet while the close is in flight', (
    tester,
  ) async {
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
    await state.save(shiftRecord());

    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    await _openCloseSheet(tester);
    await tester.enterText(find.byKey(const ValueKey('declared-cash')), '0');
    await _settle(tester);

    // The write is held open, so the route can be torn down underneath it.
    // Scrolled to first, like `_tap` does, but tapped by hand: this case has to
    // pump exactly one frame and pop mid-flight, which settling would ruin.
    final confirm = find.byKey(const ValueKey('close-shift-confirm'));
    await tester.ensureVisible(confirm);
    await _settle(tester);
    server.updateGate = Completer<void>();
    await tester.tap(confirm);
    await tester.pump();
    await _pop(tester);
    server.updateGate!.complete();
    await _settle(tester);

    // The controller outlives the screen that started the close, so the answer
    // has somewhere to land rather than throwing into a disposed notifier.
    expect(tester.takeException(), isNull);
    expect(server.updated, hasLength(1));
    expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
  });

  testWidgets('a shift carried past midnight keeps selling', (tester) async {
    // **A night is one business day, and the shift is what says so.** A club
    // opens before midnight and trades past it; the sale takes the shift's
    // frozen business date, so the register goes on selling and the whole
    // night reconciles against the drawer that served it. The gate used to
    // replace the register with a *New business day* dead end here, which made
    // trading past midnight impossible. What still ends a shift left running
    // is the 24-hour cap, which has its own surface.
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
    // The suite's clock is 2026-07-31; this shift belongs to the day before.
    await state.save(shiftRecord(businessDate: '2026-07-30'));

    await _pumpHome(tester, state, server);
    await _enterTill(tester);

    expect(find.byKey(_till), findsOneWidget);
  });

  testWidgets('losing access takes the till away rather than leaving it drawn', (
    tester,
  ) async {
    // **N3, and the whole of M2.** The gate holds one session controller for
    // the life of the till, so every notification arrived as the *same* object
    // and was discarded - a deactivation reached this widget and changed
    // nothing. The till went on looking ready to sell, and the cashier only
    // learned otherwise when a sale was refused.
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
    await state.save(shiftRecord());

    final sessions = await _pumpHome(tester, state, server);
    await _enterTill(tester);
    expect(find.byKey(_till), findsOneWidget);

    sessions.clear();
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(_till),
      findsNothing,
      reason:
          'A till whose session has gone cannot record a sale, so it must not '
          'go on drawing one that looks like it can.',
    );
  });

  testWidgets('a session that moves under the till re-reads the shift', (
    tester,
  ) async {
    // The other half: access did not end, it *changed* - a new epoch from the
    // shell's own re-read. The shift has to be read again for the session that
    // now holds the till, rather than left as it was for the previous one.
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
    await state.save(shiftRecord());

    final sessions = await _pumpHome(tester, state, server);
    await _enterTill(tester);
    final readsBefore = server.reads.length;

    // Same person, same business, a fresh access decision.
    sessions.open(uid: 'user-a', membership: shiftMembership('tenant-a'));
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(
      server.reads.length,
      greaterThan(readsBefore),
      reason: 'The shift must be re-read for the session that now holds it.',
    );
    expect(find.byKey(_till), findsOneWidget);
  });

  testWidgets('switching business while a shift is being opened draws no till', (
    tester,
  ) async {
    final sessions = await _pumpHome(tester, state, server);
    await _enterTill(tester);

    server.createGate = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('shift-gate-open')));
    // **Settled, not pumped once.** An open reads local state, checks the
    // network and looks for a shift to adopt before it writes anything; a
    // single frame switches business during that preamble, which the controller
    // rejects long before the interesting check. This runs it up to the held
    // write, so the switch lands where it has to.
    await _settle(tester);

    // The business changes underneath the open. Every publish in the
    // controller re-checks uid, tenant and epoch before it lands.
    sessions.open(uid: 'user-a', membership: shiftMembership('tenant-b'));
    server.createGate!.complete();
    await _settle(tester);

    expect(tester.takeException(), isNull);
    // **The write did land**, which is what stops this being a test that could
    // not fail: without the ownership re-check in `_publish` the controller
    // would report that shift as open and the gate would draw a till for a
    // business that has none.
    expect(server.created, hasLength(1));
    expect(server.created.single.$1, contains('tenant-a'));
    expect(
      find.byKey(_till),
      findsNothing,
      reason: 'A shift opened for one business may not draw another a till.',
    );
  });
}

/// *Close shift* out of the till, which opens the counting sheet directly.
///
/// **One tap, and that is the 2026-09-03 change.** This used to land on a
/// pushed page titled *Close shift* holding a button also labelled *Close
/// shift*; the sheet it opened is now what the choice opens.
Future<void> _openCloseSheet(WidgetTester tester) async {
  await _leaveTill(tester);
  await _tap(tester, const ValueKey('shift-exit-end'));
  expect(find.byKey(const ValueKey('declared-cash')), findsOneWidget);
}

/// An earlier installation of *this* phone, for the shift this one cannot adopt.
///
/// **The durable half matches `shiftDeviceId` and the install half does not**,
/// which since 2026-09-17 is the only shape the close control is offered for.
/// A shift whose durable half differs belongs to another phone that may simply
/// be offline, and this device no longer offers to close it - see
/// `_deviceOtherPhone` and the test that proves the button stays away.
const String _deviceEarlierInstall = 'dev-0123456789abcdef01234567deadbeef';

/// Another phone entirely, which is never offered for closing from here.
const String _deviceOtherPhone = 'dev-ffffffffffffffffffffffffffffffff';

const Key _home = ValueKey('gate-test-home');
const Key _till = ValueKey('gate-test-till');

/// The home, composed the way `tenant_routing_shell.dart` composes it: a button
/// that pushes a fresh gate under the session scope on every tap.
///
/// **A fresh gate per entry is the point**, not incidental. The gate takes its
/// controller in `didChangeDependencies`, so a second entry is the first place
/// a controller disposed during the first one is touched.
Future<TenantSessionController> _pumpHome(
  WidgetTester tester,
  HiveTenantShiftState state,
  ShiftServer server, {
  TenantShiftOnlineCheck? isOnline,
}) async {
  final sessions = TenantSessionController()
    ..open(uid: 'user-a', membership: shiftMembership('tenant-a'));
  addTearDown(sessions.dispose);
  final controllerFactory = sharedShiftControllerFactory(
    state,
    server,
    isOnline: isOnline,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: sessions,
        child: Builder(
          builder: (context) => Scaffold(
            key: _home,
            body: Center(
              child: TextButton(
                key: const ValueKey('enter-till'),
                onPressed: () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    builder: (_) => TenantSessionScope(
                      controller: sessions,
                      child: TenantShiftGate(
                        controllerFactory: controllerFactory,
                        currency: TenantReportingCurrency.unknown,
                        child: const Scaffold(
                          key: _till,
                          body: Center(child: Text('Till')),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('New sale'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return sessions;
}

Future<void> _enterTill(WidgetTester tester) =>
    _tap(tester, const ValueKey('enter-till'));

/// The system back gesture, which is the only way out of the till and which
/// `PopScope` turns into the exit dialog.
Future<void> _leaveTill(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _settle(tester);
}

Future<void> _pop(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, Key key) async {
  // **Scrolled into view first, since the close sheet grew three fields.** The
  // declaration asks for cash, M-Pesa and card, which puts the sheet's own
  // controls below an 800x600 test viewport - so a bare `tap` derived an offset
  // outside the render tree and silently did nothing.
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
}

/// Enough frames for a durable write, a canonical read and a route transition.
Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
