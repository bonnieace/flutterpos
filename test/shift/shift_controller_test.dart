import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uzapay_pos/shift/shift.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const String _deviceA = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-07-31';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late HiveTenantShiftState state;
  late TenantSessionController sessions;
  late _Server server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shift-controller-test-');
    Hive.init(directory.path);
    box = await _openBox();
    state = HiveTenantShiftState.fromBox(
      box,
      clock: () => DateTime.utc(2026, 7, 31, 9),
    );
    server = _Server();
    sessions = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
  });

  tearDown(() async {
    sessions.dispose();
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  group('opening a shift', () {
    test(
      'writes one canonical shift and confirms it by reading back',
      () async {
        final controller = _controller(sessions, state, server);

        final result = await controller.openShift();

        expect(result.phase, TenantShiftPhase.open);
        expect(result.errorCode, isNull);
        expect(server.created.single.$1, 'tenants/tenant-a/shifts/shift-1');
        expect(server.created.single.$2['staffId'], 'user-a');
        expect(server.created.single.$2['status'], 'open');
        expect(server.created.single.$2['deviceId'], _deviceA);
        expect(server.created.single.$2['businessDate'], _businessDate);
        final record = await state.read(uid: 'user-a', tenantId: 'tenant-a');
        expect(record!.shiftId, 'shift-1');
        expect(record.serverConfirmedOpen, isTrue);
        expect(record.closeInProgress, isFalse);
      },
    );

    test('refuses a second shift while one is already open', () async {
      final controller = _controller(sessions, state, server);
      await controller.openShift();

      final second = await controller.openShift();

      expect(second.errorCode, 'shift_already_open');
      expect(second.phase, TenantShiftPhase.open);
      expect(server.created.length, 1);
    });

    test('opens offline and sends nothing', () async {
      final controller = _controller(sessions, state, server, online: false);

      final result = await controller.openShift();

      // **The till sells.** The product owner allowed opening offline on
      // 2026-08-26; a cashier with no signal is exactly who needs the offline
      // outbox this app already has.
      expect(result.phase, TenantShiftPhase.open);
      expect(result.errorCode, 'offline');
      expect(server.created, isEmpty);
      // The intent is durable and unconfirmed, which is what tells the next
      // connected settle to replay it rather than read it as a closed shift.
      final record = await state.read(uid: 'user-a', tenantId: 'tenant-a');
      expect(record, isNotNull);
      expect(record!.serverConfirmedOpen, isFalse);
    });

    test('refuses a second shift on this device while offline', () async {
      final controller = _controller(sessions, state, server, online: false);
      await controller.openShift();

      final second = await controller.openShift();

      // The duplicate guard reads only this device, which is what makes
      // opening offline safe to allow at all.
      expect(second.errorCode, 'shift_already_open');
      expect(server.created, isEmpty);
    });

    test('replays an offline open on the next connected restore', () async {
      final offline = _controller(sessions, state, server, online: false);
      await offline.openShift();
      final shiftId = (await state.read(
        uid: 'user-a',
        tenantId: 'tenant-a',
      ))!.shiftId;

      final controller = _controller(sessions, state, server);
      final restored = await controller.restore(sessions.requireSession());

      // **The shift reaches the server under its own id**, because the sales
      // already in the outbox name it. It is emphatically not cleared.
      expect(server.created.single.$1, 'tenants/tenant-a/shifts/$shiftId');
      expect(restored.phase, TenantShiftPhase.open);
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNotNull);
    });

    test('records the opening float the cashier entered', () async {
      final controller = _controller(sessions, state, server);
      await controller.openShift(openingFloatMinor: 200000);

      expect(server.created.single.$2['openingFloatMinor'], 200000);
    });

    test('writes no float field for a till that was given no change', () async {
      final controller = _controller(sessions, state, server);
      await controller.openShift();

      // Absent rather than zero: the two mean the same thing to every reader,
      // and a shop that keeps no change should not carry a field about one on
      // every shift it ever opens.
      expect(
        server.created.single.$2.containsKey('openingFloatMinor'),
        isFalse,
      );
    });

    test('replays an offline open with the float it was opened on', () async {
      // **The case the float is most likely to be lost in.** A shift opened
      // with no network is rebuilt later from the durable record, so a float
      // held only by the dialog that collected it would survive every open
      // except the ones that go through this path - and the shift would then
      // be marked against its sales alone and read as over by the float.
      final offline = _controller(sessions, state, server, online: false);
      await offline.openShift(openingFloatMinor: 150000);

      final controller = _controller(sessions, state, server);
      await controller.restore(sessions.requireSession());

      expect(server.created.single.$2['openingFloatMinor'], 150000);
    });

    test('keeps an unsent offline shift when the replay fails', () async {
      final offline = _controller(sessions, state, server, online: false);
      await offline.openShift();
      server.failCreateWith = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );

      final controller = _controller(sessions, state, server);
      final restored = await controller.restore(sessions.requireSession());

      // The one guarantee that stops a trading day being deleted: a shift the
      // server has never acknowledged is never cleared by a failed replay.
      expect(restored.phase, TenantShiftPhase.open);
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNotNull);
    });

    test('settles an unacknowledged create by canonical read', () async {
      server.failCreateWith = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      // Only a successful canonical read may decide that nothing was written.
      expect(result.phase, TenantShiftPhase.none);
      expect(result.errorCode, 'unavailable');
      expect(server.reads, <String>['tenants/tenant-a/shifts/shift-1']);
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
    });

    test('keeps evidence when the create outcome cannot be settled', () async {
      server.failCreateWith = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      server.failReadWith = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      // The server may still hold the shift, so the durable intent survives
      // for the next canonical settlement.
      expect(result.phase, TenantShiftPhase.unavailable);
      final record = await state.read(uid: 'user-a', tenantId: 'tenant-a');
      expect(record!.shiftId, 'shift-1');
      expect(record.serverConfirmedOpen, isFalse);
    });

    test('discards a result after the session changed mid-write', () async {
      final controller = _controller(
        sessions,
        state,
        server,
        beforeCreate: () =>
            sessions.open(uid: 'user-a', membership: _membership('tenant-b')),
      );

      final result = await controller.openShift();

      expect(result.errorCode, 'session_changed');
      expect(controller.state.phase, TenantShiftPhase.unknown);
    });
  });

  group('restoring a shift', () {
    test(
      're-reads the canonical shift instead of trusting local state',
      () async {
        await state.save(_record());
        server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
        final controller = _controller(sessions, state, server);

        final restored = await controller.restore(sessions.requireSession());

        expect(restored.phase, TenantShiftPhase.open);
        expect(restored.shift!.id, 'shift-a');
        expect(server.reads, <String>['tenants/tenant-a/shifts/shift-a']);
      },
    );

    test(
      'clears local state when the server already closed the shift',
      () async {
        await state.save(
          _record(closeInProgress: true, declaration: _declared(5000)),
        );
        server.shifts['tenants/tenant-a/shifts/shift-a'] = _document(
          overrides: <String, Object?>{'status': 'closed'},
        );
        final controller = _controller(sessions, state, server);

        final restored = await controller.restore(sessions.requireSession());

        expect(restored.phase, TenantShiftPhase.none);
        expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
      },
    );

    test('clears local state when no canonical shift exists', () async {
      await state.save(_record());
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.none);
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
    });

    test('an unsent write does not confirm the shift it looks like', () async {
      // **H2.** The create timed out and is sitting in the local mutation
      // queue. A `Source.serverAndCache` read falls back to local storage, so
      // the shift reads back looking perfectly open - but the server has never
      // seen it, and promoting on that is what later destroys the record.
      final pending = _Server()
        ..shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      await state.save(_record(serverConfirmedOpen: false));
      final controller = _controllerWithReader(
        sessions,
        state,
        server,
        _PendingWriteReader(pending, server),
      );

      final restored = await controller.restore(sessions.requireSession());

      // The till still sells - an unconfirmed shift binds sales by design.
      expect(restored.phase, TenantShiftPhase.open);
      final record = await state.read(uid: 'user-a', tenantId: 'tenant-a');
      expect(
        record!.serverConfirmedOpen,
        isFalse,
        reason:
            'Only the server may confirm. Local storage answering with this '
            'device own write is not the server answering.',
      );
    });

    test('a rejected write replays the shift rather than destroying it', () async {
      // The other half of H2, and the half that costs a trading day. The queued
      // create is refused - a deactivated cashier is the ordinary way - so
      // Firestore reverts it and local storage no longer has it either. With
      // the record wrongly marked confirmed this cleared it, stranding every
      // outbox sale stamped with the shift id behind a `validSaleShift` that
      // would deny them for ever. Left unconfirmed, it replays instead.
      await state.save(_record(serverConfirmedOpen: false));
      final controller = _controllerWithReader(
        sessions,
        state,
        server,
        // Nothing anywhere: the revert has happened and the server never had it.
        _PendingWriteReader(_Server(), server),
      );

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.open);
      expect(
        server.created.single.$1,
        'tenants/tenant-a/shifts/shift-a',
        reason: 'The same shift id, so the outbox sales still name something.',
      );
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNotNull);
    });

    test('refuses a shift that belongs to another cashier', () async {
      await state.save(_record());
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document(
        overrides: <String, Object?>{'staffId': 'user-b'},
      );
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.unavailable);
      expect(restored.errorCode, 'foreign_shift');
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNotNull);
    });

    test('reports only local facts while offline', () async {
      await state.save(
        _record(closeInProgress: true, declaration: _declared(900)),
      );
      final controller = _controller(sessions, state, server, online: false);

      final restored = await controller.restore(sessions.requireSession());

      // A restart discards the count itself, so this is `open` rather than
      // `closing`. It is no longer `unknown`: the durable record *is* this
      // device's belief that a shift is open, and reporting otherwise is what
      // used to strand the till behind a spinner it could never leave. The
      // counted figure survives on purpose - reopening the sheet still shows
      // what was typed.
      expect(restored.phase, TenantShiftPhase.open);
      expect(restored.errorCode, 'offline');
      expect(restored.declaration?.cashMinor, 900);
      expect(server.reads, isEmpty);
      final record = await state.read(uid: 'user-a', tenantId: 'tenant-a');
      expect(record, isNotNull);
      expect(record!.closeInProgress, isFalse);
      expect(record.declaration?.cashMinor, 900);
    });

    test('a cash count does not survive a restart', () async {
      await state.save(
        _record(closeInProgress: true, declaration: _declared(900)),
      );
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());

      // The till is back in service rather than refusing sales for a count
      // nobody can see, which is the whole point of making the count live only
      // as long as the sheet it is taken in.
      expect(restored.phase, TenantShiftPhase.open);
      final record = await state.read(uid: 'user-a', tenantId: 'tenant-a');
      expect(record!.closeInProgress, isFalse);
      expect(record.declaration?.cashMinor, 900);
    });

    test('discards a canonical read that finished after a switch', () async {
      await state.save(_record());
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      final controller = _controller(
        sessions,
        state,
        server,
        beforeRead: () =>
            sessions.open(uid: 'user-a', membership: _membership('tenant-b')),
      );
      final captured = TenantSession.active(
        uid: 'user-a',
        tenantId: 'tenant-a',
        role: TenantRole.cashier,
      );

      final restored = await controller.restore(captured);

      expect(restored.errorCode, 'session_changed');
      expect(controller.state.phase, TenantShiftPhase.unknown);
    });
  });

  group('cash count and closing', () {
    test(
      'an unfinished cash count blocks switching until it settles',
      () async {
        final controller = _controller(sessions, state, server);
        await controller.openShift();
        final source = TenantShiftSwitchStateSource(state);

        expect(
          (await source.inspect(sessions.requireSession()))!.blocker,
          isNull,
        );

        final counting = await controller.startCashCount();
        expect(counting.phase, TenantShiftPhase.closing);
        expect(counting.blocksTenantSwitch, isTrue);
        expect(
          (await source.inspect(sessions.requireSession()))!.blocker,
          TenantSwitchBlocker.unfinishedCashCountOrShiftClose,
        );

        final closed = await controller.closeShift(
          declaration: _declared(125000),
        );
        expect(closed.phase, TenantShiftPhase.none);
        expect(server.updated.single.$2['status'], 'closed');
        expect(server.updated.single.$2['closingCashMinor'], 125000);
        expect(
          (await source.inspect(sessions.requireSession()))!.blocker,
          isNull,
        );
      },
    );

    test('cancelling a cash count restores the open shift', () async {
      final controller = _controller(sessions, state, server);
      await controller.openShift();
      await controller.startCashCount();

      final cancelled = await controller.cancelCashCount();

      expect(cancelled.phase, TenantShiftPhase.open);
      expect(
        (await TenantShiftSwitchStateSource(
          state,
        ).inspect(sessions.requireSession()))!.blocker,
        isNull,
      );
    });

    test('refuses a close before the cash count started', () async {
      final controller = _controller(sessions, state, server);
      await controller.openShift();

      final result = await controller.closeShift(declaration: _declared(100));

      expect(result.errorCode, 'cash_count_not_started');
      expect(server.updated, isEmpty);
    });

    test('an unusable amount cannot become a declaration at all', () {
      // **The refusal moved from the controller into the type.** A close used
      // to take a bare integer and answer `invalid_closing_cash` for a figure
      // out of range; it now takes a declaration, which cannot be built from
      // one. The check is the same check, made earlier and in one place.
      expect(
        ShiftTenderDeclaration.tryParse(cash: -1, mpesa: 0, card: 0),
        isNull,
      );
      expect(
        ShiftTenderDeclaration.tryParse(
          cash: maximumShiftCashMinor + 1,
          mpesa: 0,
          card: 0,
        ),
        isNull,
      );
      // Three figures each inside the bound whose sum is not.
      expect(
        ShiftTenderDeclaration.tryParse(
          cash: maximumShiftCashMinor,
          mpesa: 1,
          card: 0,
        ),
        isNull,
      );
    });

    test('a declaration of nothing is a real answer, not a refusal', () async {
      final controller = _controller(sessions, state, server);
      await controller.openShift();
      await controller.startCashCount();

      // A shift that took nothing still has to be closable, and an empty box
      // on the sheet reaches here as a zero rather than as a fault.
      final result = await controller.closeShift(
        declaration: ShiftTenderDeclaration.zero,
      );

      expect(result.phase, TenantShiftPhase.none);
      expect(result.errorCode, isNull);
      expect(server.updated.single.$2['declaredCashMinor'], 0);
      expect(server.updated.single.$2['declaredMpesaMinor'], 0);
      expect(server.updated.single.$2['declaredCardMinor'], 0);
    });

    test('the close carries all three declared figures', () async {
      final controller = _controller(sessions, state, server);
      await controller.openShift();
      await controller.startCashCount();

      final result = await controller.closeShift(
        declaration: _declared(4200, mpesa: 15000, card: 900),
      );

      expect(result.phase, TenantShiftPhase.none);
      final written = server.updated.single.$2;
      expect(written['declaredCashMinor'], 4200);
      expect(written['declaredMpesaMinor'], 15000);
      expect(written['declaredCardMinor'], 900);
      // The same money under the name every existing surface reads, so no
      // reader can be shown two cash figures that disagree.
      expect(written['closingCashMinor'], 4200);
      expect(written['closingCash'], 42.0);
      // Nothing on this path claims to have compared anything.
      expect(written.containsKey('closedWithoutEvidence'), isFalse);
    });

    test('an unacknowledged close keeps blocking the switch', () async {
      final controller = _controller(sessions, state, server);
      await controller.openShift();
      await controller.startCashCount();
      server.failUpdateWith = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );

      final result = await controller.closeShift(declaration: _declared(4200));

      // **Recorded as closed rather than left mid-count.** The write may have
      // landed; replaying it is a second `update` of the same fields, which
      // changes nothing if it did. What must not happen is the till going on
      // selling against a shift whose drawer has been counted.
      expect(result.phase, TenantShiftPhase.closedPending);
      expect(result.declaration?.cashMinor, 4200);
      expect(
        (await state.read(uid: 'user-a', tenantId: 'tenant-a'))!.closedAt,
        isNotNull,
      );
      expect(
        (await TenantShiftSwitchStateSource(
          state,
        ).inspect(sessions.requireSession()))!.blocker,
        TenantSwitchBlocker.unfinishedCashCountOrShiftClose,
      );
    });
  });

  group('closing summary', () {
    test(
      'writes the sale-derived aggregates reconciliation verifies',
      () async {
        final ledger = _Ledger()
          ..summary = const ShiftSalesSummary(
            transactionCount: 3,
            totalMinor: 98750,
            unsettledCount: 0,
          );
        final controller = _controller(
          sessions,
          state,
          server,
          salesLedger: ledger,
        );
        await controller.openShift();
        await controller.startCashCount();

        final closed = await controller.closeShift(
          declaration: _declared(125000),
        );

        expect(closed.phase, TenantShiftPhase.none);
        expect(ledger.requested, contains('shift-1'));
        final update = server.updated.single.$2;
        expect(update['transactionCount'], 3);
        expect(update['totalSalesMinor'], 98750);
        expect(update['totalSales'], 987.5);
        expect(update['closingCashMinor'], 125000);
      },
    );

    test("states every phone's sales where the server can count them", () async {
      // This phone rang one sale; the cashier's other phone rang two more into
      // the same shift. The close states all three, so reconciliation has only
      // what arrives afterwards left to report.
      final ledger = _Ledger()
        ..summary = const ShiftSalesSummary(
          transactionCount: 1,
          totalMinor: 1000,
          unsettledCount: 0,
        );
      final totals = _Totals(
        const ShiftServerTotals(transactionCount: 3, totalMinor: 4500),
      );
      final controller = _controller(
        sessions,
        state,
        server,
        salesLedger: ledger,
        serverTotals: totals,
      );
      await controller.openShift();
      await controller.startCashCount();

      await controller.closeShift(declaration: _declared(4500));

      expect(totals.requested, <String>['shift-1']);
      final update = server.updated.single.$2;
      expect(update['transactionCount'], 3);
      expect(update['totalSalesMinor'], 4500);
    });

    test('states what the shift lent and took back, as the server counts it', () async {
      final ledger = _Ledger()
        ..summary = const ShiftSalesSummary(
          transactionCount: 1,
          totalMinor: 1000,
          unsettledCount: 0,
          creditOwedMinor: 600,
        );
      final controller = _controller(
        sessions,
        state,
        server,
        salesLedger: ledger,
        serverTotals: _Totals(
          const ShiftServerTotals(
            transactionCount: 1,
            totalMinor: 1000,
            creditOwedMinor: 600,
            repaidMinor: 600,
          ),
        ),
      );
      await controller.openShift();
      await controller.startCashCount();

      await controller.closeShift(declaration: _declared(1000));

      final update = server.updated.single.$2;
      expect(update['creditOwedMinor'], 600);
      expect(update['repaidMinor'], 600);
    });

    // **A credit figure the server cannot count is not zero.** On SIT the
    // sum needs its own index; a phone that cannot read it states what it
    // proved itself rather than closing as though nothing was lent.
    test('a credit figure the server cannot count falls back to the phone', () async {
      final ledger = _Ledger()
        ..summary = const ShiftSalesSummary(
          transactionCount: 1,
          totalMinor: 1000,
          unsettledCount: 0,
          creditOwedMinor: 600,
        );
      final controller = _controller(
        sessions,
        state,
        server,
        salesLedger: ledger,
        serverTotals: _Totals(
          const ShiftServerTotals(transactionCount: 1, totalMinor: 1000),
        ),
      );
      await controller.openShift();
      await controller.startCashCount();

      await controller.closeShift(declaration: _declared(400));

      final update = server.updated.single.$2;
      expect(update['totalSalesMinor'], 1000);
      expect(update['creditOwedMinor'], 600);
      expect(update.containsKey('repaidMinor'), isFalse);
    });

    for (final (name, counted) in <(String, ShiftServerTotals?)>[
      ('cannot be read', null),
      (
        'is below what this phone proves',
        const ShiftServerTotals(transactionCount: 0, totalMinor: 0),
      ),
    ]) {
      test(
        "states this phone's own sales where the server count $name",
        () async {
          final ledger = _Ledger()
            ..summary = const ShiftSalesSummary(
              transactionCount: 2,
              totalMinor: 3000,
              unsettledCount: 0,
            );
          final controller = _controller(
            sessions,
            state,
            server,
            salesLedger: ledger,
            serverTotals: _Totals(counted),
          );
          await controller.openShift();
          await controller.startCashCount();

          await controller.closeShift(declaration: _declared(3000));

          final update = server.updated.single.$2;
          expect(update['transactionCount'], 2);
          expect(update['totalSalesMinor'], 3000);
        },
      );
    }

    test('refuses to close while a sale is still unsynchronized', () async {
      final ledger = _Ledger()
        ..summary = const ShiftSalesSummary(
          transactionCount: 1,
          totalMinor: 500,
          unsettledCount: 1,
        );
      final controller = _controller(
        sessions,
        state,
        server,
        salesLedger: ledger,
      );
      await controller.openShift();
      await controller.startCashCount();

      final result = await controller.closeShift(declaration: _declared(500));

      // The device cannot describe the shift completely, so it keeps the
      // counted cash and the switch blocker instead of publishing a wrong sum.
      expect(result.errorCode, 'unsynchronized_shift_sales');
      expect(result.phase, TenantShiftPhase.closing);
      expect(result.declaration?.cashMinor, 500);
      expect(server.updated, isEmpty);
      expect(
        (await TenantShiftSwitchStateSource(
          state,
        ).inspect(sessions.requireSession()))!.blocker,
        TenantSwitchBlocker.unfinishedCashCountOrShiftClose,
      );
    });

    test('unreadable sale evidence never closes the shift', () async {
      final ledger = _Ledger()
        ..failure = const ShiftSalesLedgerException('malformed_local_sale');
      final controller = _controller(
        sessions,
        state,
        server,
        salesLedger: ledger,
      );
      await controller.openShift();
      await controller.startCashCount();

      final result = await controller.closeShift(declaration: _declared(500));

      expect(result.phase, TenantShiftPhase.unavailable);
      expect(result.errorCode, 'malformed_local_sale');
      expect(server.updated, isEmpty);
    });

    test('shows the confirmed summary for any open shift', () async {
      final ledger = _Ledger()
        ..summary = const ShiftSalesSummary(
          transactionCount: 2,
          totalMinor: 4200,
          unsettledCount: 0,
        );
      final controller = _controller(
        sessions,
        state,
        server,
        salesLedger: ledger,
      );
      final open = await controller.openShift();

      // **Readable without starting a count, as of 2026-08-23.** This used to
      // assert `isNull` here: the takings were computed only while closing, so
      // the one figure a cashier wants mid-shift was behind a count they then
      // had to cancel out of.
      expect(open.sales!.transactionCount, 2);
      expect(open.sales!.totalMinor, 4200);

      final counting = await controller.startCashCount();

      expect(counting.sales!.transactionCount, 2);
      expect(counting.sales!.totalMinor, 4200);
    });
  });

  group('canonical open-shift discovery', () {
    test('adopts the canonical shift after local state is lost', () async {
      server.shifts['tenants/tenant-a/shifts/shift-restored'] = _document(
        overrides: <String, Object?>{'shiftId': 'shift-restored'},
      );
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.open);
      expect(restored.shift!.id, 'shift-restored');
      final record = await state.read(uid: 'user-a', tenantId: 'tenant-a');
      expect(record!.shiftId, 'shift-restored');
      expect(record.serverConfirmedOpen, isTrue);
      expect(server.queries, <String>['tenants/tenant-a/shifts']);
    });

    test('opens no duplicate when a canonical shift already exists', () async {
      server.shifts['tenants/tenant-a/shifts/shift-existing'] = _document(
        overrides: <String, Object?>{'shiftId': 'shift-existing'},
      );
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      expect(result.phase, TenantShiftPhase.open);
      expect(result.errorCode, 'shift_already_open');
      expect(result.shift!.id, 'shift-existing');
      expect(server.created, isEmpty);
    });

    // **A shift belongs to its cashier on any phone, since 2026-09-29.** Every
    // case below used to be a refusal - "open on another register", "opened by
    // an earlier installation" - with at most a way to close the shift. They
    // are joins now.
    test('joins a shift opened on another phone', () async {
      server.shifts['tenants/tenant-a/shifts/shift-elsewhere'] = _document(
        overrides: <String, Object?>{
          'shiftId': 'shift-elsewhere',
          'deviceId': 'dev-fedcba9876543210fedcba9876543210',
          'openingFloatMinor': 2000,
        },
      );
      final controller = _controller(sessions, state, server);

      final result = await controller.restore(sessions.requireSession());

      expect(result.phase, TenantShiftPhase.open);
      expect(result.errorCode, isNull);
      expect(result.otherDeviceShiftOpen, isFalse);
      expect(result.shift!.id, 'shift-elsewhere');
      expect(server.created, isEmpty);
      final record = await state.read(uid: 'user-a', tenantId: 'tenant-a');
      expect(record!.shiftId, 'shift-elsewhere');
      // **This phone's id, not the opener's**: every sale bound to the record
      // is stamped with it, and the checkout refuses a record naming another.
      expect(record.deviceId, _deviceA);
      expect(record.serverConfirmedOpen, isTrue);
      expect(record.openingFloatMinor, 2000);
      // Exactly as old here as on the phone that opened it.
      expect(record.openedAt, DateTime.utc(2026, 7, 31, 6));
    });

    test(
      'opening joins a shift open elsewhere instead of standing beside it',
      () async {
        server.shifts['tenants/tenant-a/shifts/shift-elsewhere'] = _document(
          overrides: <String, Object?>{
            'shiftId': 'shift-elsewhere',
            'deviceId': 'dev-fedcba9876543210fedcba9876543210',
          },
        );
        final controller = _controller(sessions, state, server);

        final result = await controller.openShift();

        // Joining is simply the till opening, so it reports no refusal - unlike
        // adopting this installation's own, which answers "already open".
        expect(result.phase, TenantShiftPhase.open);
        expect(result.errorCode, isNull);
        expect(result.shift!.id, 'shift-elsewhere');
        expect(server.created, isEmpty);
      },
    );

    test(
      'joins the shift an earlier install of this phone left open',
      () async {
        server.shifts['tenants/tenant-a/shifts/shift-before'] = _document(
          overrides: <String, Object?>{
            'shiftId': 'shift-before',
            // The durable half of `_deviceA`, under a different installation
            // half: this device, before the app was reinstalled on it.
            'deviceId': 'dev-0123456789abcdef01234567deadbeef',
          },
        );
        final controller = _controller(sessions, state, server);

        final result = await controller.restore(sessions.requireSession());

        // The case that started this: it used to be refused, and could only be
        // closed from here.
        expect(result.phase, TenantShiftPhase.open);
        expect(result.errorCode, isNull);
        expect(result.shift!.id, 'shift-before');
        expect(server.created, isEmpty);
      },
    );

    test(
      "prefers this installation's own shift, and says there is another",
      () async {
        // Its outbox may still hold unsent sales stamped with it.
        server.shifts['tenants/tenant-a/shifts/shift-mine'] = _document(
          overrides: <String, Object?>{'shiftId': 'shift-mine'},
        );
        server.shifts['tenants/tenant-a/shifts/shift-elsewhere'] = _document(
          overrides: <String, Object?>{
            'shiftId': 'shift-elsewhere',
            'deviceId': 'dev-fedcba9876543210fedcba9876543210',
            'startTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 8)),
          },
        );
        final controller = _controller(sessions, state, server);

        final result = await controller.restore(sessions.requireSession());

        expect(result.shift!.id, 'shift-mine');
        expect(result.otherDeviceShiftOpen, isTrue);
      },
    );

    test('joins the newest shift that can still take sales', () async {
      // Yesterday's, left open past the cap, and two from today. The cashier is
      // trading in the newest of today's; the others are for the count to sweep.
      server.shifts['tenants/tenant-a/shifts/shift-yesterday'] = _document(
        overrides: <String, Object?>{
          'shiftId': 'shift-yesterday',
          'deviceId': 'dev-fedcba9876543210fedcba9876543210',
          'businessDate': '2026-07-30',
          'startTime': Timestamp.fromDate(DateTime.utc(2026, 7, 30, 8)),
        },
      );
      server.shifts['tenants/tenant-a/shifts/shift-early'] = _document(
        overrides: <String, Object?>{
          'shiftId': 'shift-early',
          'deviceId': 'dev-ffffffffffffffffffffffffffffffff',
          'startTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 5)),
        },
      );
      server.shifts['tenants/tenant-a/shifts/shift-late'] = _document(
        overrides: <String, Object?>{
          'shiftId': 'shift-late',
          'deviceId': 'dev-eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
          'startTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 7)),
        },
      );
      final controller = _controller(sessions, state, server);

      final result = await controller.restore(sessions.requireSession());

      expect(result.phase, TenantShiftPhase.open);
      expect(result.shift!.id, 'shift-late');
      expect(result.otherDeviceShiftOpen, isTrue);
    });

    test(
      'joins an expired shift as expired where nothing else is open',
      () async {
        // Exactly what the phone that opened it would show: count it off before
        // another opens.
        server.shifts['tenants/tenant-a/shifts/shift-yesterday'] = _document(
          overrides: <String, Object?>{
            'shiftId': 'shift-yesterday',
            'deviceId': 'dev-fedcba9876543210fedcba9876543210',
            'businessDate': '2026-07-30',
            'startTime': Timestamp.fromDate(DateTime.utc(2026, 7, 30, 8)),
          },
        );
        final controller = _controller(sessions, state, server);

        final result = await controller.restore(sessions.requireSession());

        expect(result.phase, TenantShiftPhase.expired);
        expect(result.shiftExpired, isTrue);
        expect(result.shift!.id, 'shift-yesterday');
        expect(server.created, isEmpty);
      },
    );

    test('fails closed on two open shifts for one device', () async {
      for (final id in <String>['shift-one', 'shift-two']) {
        server.shifts['tenants/tenant-a/shifts/$id'] = _document(
          overrides: <String, Object?>{'shiftId': id},
        );
      }
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      expect(result.phase, TenantShiftPhase.unavailable);
      expect(result.errorCode, 'ambiguous_open_shift');
      expect(server.created, isEmpty);
    });

    test('an unavailable discovery query never opens a shift', () async {
      server.failQueryWith = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      expect(result.phase, TenantShiftPhase.unavailable);
      expect(server.created, isEmpty);
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
    });

    test('a known local shift needs no discovery query', () async {
      await state.save(_record());
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      final controller = _controller(sessions, state, server);

      await controller.restore(sessions.requireSession());

      expect(server.queries, isEmpty);
    });
  });

  group("sweeping up a cashier's other open shifts", () {
    test('names every shift this installation is not holding', () async {
      // One on another phone, one left by an earlier install of this phone, and
      // this device's own. The sweep takes the first two and never the third:
      // the cashier is about to count the drawer onto that one.
      server.shifts['tenants/tenant-a/shifts/shift-other-phone'] = _document(
        overrides: <String, Object?>{
          'shiftId': 'shift-other-phone',
          'deviceId': 'dev-fedcba9876543210fedcba9876543210',
        },
      );
      server.shifts['tenants/tenant-a/shifts/shift-earlier-install'] =
          _document(
            overrides: <String, Object?>{
              'shiftId': 'shift-earlier-install',
              'deviceId': 'dev-0123456789abcdef01234567deadbeef',
            },
          );
      server.shifts['tenants/tenant-a/shifts/shift-mine'] = _document(
        overrides: <String, Object?>{'shiftId': 'shift-mine'},
      );
      final controller = _controller(sessions, state, server);

      final ids = await controller.otherOpenShiftIds();

      expect(
        ids,
        unorderedEquals(<String>['shift-other-phone', 'shift-earlier-install']),
      );
    });

    test('never names the shift this phone joined', () async {
      // Joined shifts carry another device's id, so excluding by device alone
      // would offer the very shift this phone sells into as one to close
      // without evidence. Same opening instant, so the tie goes by id.
      for (final install in <String>['deadbeef', 'feedface']) {
        server.shifts['tenants/tenant-a/shifts/shift-$install'] = _document(
          overrides: <String, Object?>{
            'shiftId': 'shift-$install',
            'deviceId': 'dev-0123456789abcdef01234567$install',
          },
        );
      }
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());
      final ids = await controller.otherOpenShiftIds();

      expect(restored.shift!.id, 'shift-feedface');
      expect(ids, <String>['shift-deadbeef']);
    });

    test('names nothing rather than guessing when offline', () async {
      server.shifts['tenants/tenant-a/shifts/shift-elsewhere'] = _document(
        overrides: <String, Object?>{
          'shiftId': 'shift-elsewhere',
          'deviceId': 'dev-fedcba9876543210fedcba9876543210',
        },
      );
      final offline = _controller(sessions, state, server, online: false);

      // A list read off the cache would name shifts closed elsewhere since, and
      // the close it feeds is online-only anyway. The next sweep asks again.
      expect(await offline.otherOpenShiftIds(), isEmpty);
    });

    test('names nothing where the cashier holds only this one', () async {
      server.shifts['tenants/tenant-a/shifts/shift-mine'] = _document(
        overrides: <String, Object?>{'shiftId': 'shift-mine'},
      );
      final controller = _controller(sessions, state, server);

      expect(await controller.otherOpenShiftIds(), isEmpty);
    });
  });

  group('cashier cross-business restriction', () {
    test('a cashier cannot open a shift in a second business', () async {
      await state.save(_record(tenantId: 'tenant-b', shiftId: 'shift-b'));
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      expect(result.errorCode, 'other_tenant_shift_open');
      expect(result.otherTenantShiftOpen, isTrue);
      expect(server.created, isEmpty);
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
    });

    test('a manager may still open a shift elsewhere', () async {
      await state.save(_record(tenantId: 'tenant-b', shiftId: 'shift-b'));
      sessions.open(
        uid: 'user-a',
        membership: _membership('tenant-a', role: TenantRole.manager),
      );
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      expect(result.phase, TenantShiftPhase.open);
      expect(result.otherTenantShiftOpen, isTrue);
      expect(server.created.length, 1);
    });

    test('another identity on the device never blocks this cashier', () async {
      await state.save(
        _record(uid: 'user-b', tenantId: 'tenant-b', shiftId: 'shift-b'),
      );
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      expect(result.phase, TenantShiftPhase.open);
      expect(result.otherTenantShiftOpen, isFalse);
    });
  });

  group('the twenty-four hour cap', () {
    // The harness clock is 2026-07-31 09:00, so this opened 25 hours ago.
    final long = DateTime.utc(2026, 7, 30, 8);

    test('a shift past the cap stops selling', () async {
      await state.save(_record(openedAt: long));
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.expired);
      expect(restored.shiftExpired, isTrue);
      // The shift is emphatically still there: it owns this device's sales.
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNotNull);
    });

    test('a shift filed under a day that has not arrived stops selling', () async {
      // **The clock was wrong when this opened and has since been corrected.**
      // `CheckoutDraft` takes a sale's business date from its shift, so this
      // one would go on stamping sales two days ahead - onto a day the shop has
      // not traded, which is not the day the home, the daily summary or
      // reconciliation are reading. The figures would never move and nothing
      // would say why.
      //
      // The age rule cannot catch it: `difference` is signed, so an `openedAt`
      // in the future reads as a negative age and never reaches the cap.
      await state.save(
        _record(
          businessDate: '2026-08-02',
          openedAt: DateTime.utc(2026, 8, 2, 9),
        ),
      );
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.expired);
      expect(restored.shiftExpired, isTrue);
      // Still this device's to finish, exactly as a shift past the cap is.
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNotNull);
    });

    test('yesterday is not the future, and keeps selling', () async {
      // The guard is about a day the shop has not reached, never about a shift
      // that legitimately owns an earlier day - which is the whole point of
      // letting a till trade past midnight.
      await state.save(
        _record(
          businessDate: '2026-07-30',
          openedAt: DateTime.utc(2026, 7, 31, 2),
        ),
      );
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.open);
      expect(restored.shiftExpired, isFalse);
    });

    test('a shift within the cap is untouched', () async {
      await state.save(_record(openedAt: DateTime.utc(2026, 7, 30, 10)));
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.open);
      expect(restored.shiftExpired, isFalse);
    });

    test('the cap applies offline, where it cannot be closed', () async {
      await state.save(_record(openedAt: long));
      final controller = _controller(sessions, state, server, online: false);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.expired);
      // Naming the expiry rather than the connection: what the person must do
      // is close it, and being offline is only why they cannot yet.
      expect(restored.errorCode, 'shift_expired_offline');
    });

    test('a cash count cannot hand an expired shift back its till', () async {
      await state.save(_record(openedAt: long));
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      final controller = _controller(sessions, state, server);
      await controller.restore(sessions.requireSession());

      final counting = await controller.startCashCount();

      // The phase moves to `closing`, which is what the close sheet needs -
      // but `shiftExpired` is what the gate reads, and it does not move.
      expect(counting.phase, TenantShiftPhase.closing);
      expect(counting.shiftExpired, isTrue);
    });

    test('adoption dates a shift from when it was opened', () async {
      // Canonical `startTime` is 2026-07-31 06:00 - three hours old, not new.
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      final controller = _controller(sessions, state, server);

      await controller.restore(sessions.requireSession());

      final record = await state.read(uid: 'user-a', tenantId: 'tenant-a');
      expect(record!.openedAt, DateTime.utc(2026, 7, 31, 6));
    });
  });

  group('closing with no connection', () {
    test('an offline close is recorded and stops the till selling', () async {
      await state.save(
        _record(closeInProgress: true, declaration: _declared(900)),
      );
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      final controller = _controller(sessions, state, server, online: false);

      final closed = await controller.closeShift(declaration: _declared(900));

      // **Refused outright until 2026-09-05**, which left a shop that had
      // counted its cash holding an open shift it could not finish - and the
      // till still selling against it. What makes this safe is the
      // `sales.isComplete` check above it, which reads this device's own
      // outbox: a shift with any unsent sale still cannot close.
      expect(closed.phase, TenantShiftPhase.closedPending);
      expect(closed.declaration?.cashMinor, 900);
      final record = await state.read(uid: 'user-a', tenantId: 'tenant-a');
      expect(record!.closedAt, isNotNull);
      // Nothing was sent, so the shift is still open on the server.
      expect(server.updated, isEmpty);
    });

    test('the close sends itself on the next restore', () async {
      await state.save(
        _record(closeInProgress: true, declaration: _declared(900)),
      );
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      await _controller(
        sessions,
        state,
        server,
        online: false,
      ).closeShift(declaration: _declared(900));

      final restored = await _controller(
        sessions,
        state,
        server,
      ).restore(sessions.requireSession());

      expect(server.updated, hasLength(1));
      expect(server.updated.single.$2['closingCashMinor'], 900);
      // Confirmed, so the record goes and a new shift may be opened.
      expect(restored.phase, TenantShiftPhase.none);
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
    });

    test("the replay counts the server's sales as the close lands", () async {
      // The cashier's other phone sent its sales while this one was offline;
      // the replay is the first moment this phone can see them.
      await state.save(
        _record(closeInProgress: true, declaration: _declared(900)),
      );
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      final offline = _controller(
        sessions,
        state,
        server,
        online: false,
        serverTotals: _Totals(
          const ShiftServerTotals(transactionCount: 9, totalMinor: 9999),
        ),
      );
      await offline.closeShift(declaration: _declared(900));

      await _controller(
        sessions,
        state,
        server,
        serverTotals: _Totals(
          const ShiftServerTotals(transactionCount: 4, totalMinor: 5200),
        ),
      ).restore(sessions.requireSession());

      final update = server.updated.single.$2;
      expect(update['transactionCount'], 4);
      expect(update['totalSalesMinor'], 5200);
      expect(update['closingCashMinor'], 900);
    });

    test('a close that still cannot be sent stays closed here', () async {
      await state.save(
        _record(closeInProgress: true, declaration: _declared(900)),
      );
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      await _controller(
        sessions,
        state,
        server,
        online: false,
      ).closeShift(declaration: _declared(900));
      server.failUpdateWith = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );

      final restored = await _controller(
        sessions,
        state,
        server,
      ).restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.closedPending);
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNotNull);
    });
  });

  group('fail-closed reporting', () {
    test('malformed durable state never claims a clean device', () async {
      await box.put('user-a:tenant-a', <String, Object?>{'schemaVersion': 99});
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.unavailable);
      expect(restored.errorCode, 'malformed_shift_state');
    });

    test('a cross-tenant reader response fails closed', () async {
      await state.save(_record());
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      server.responsePath = 'tenants/tenant-b/shifts/shift-a';
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.unavailable);
      expect(restored.errorCode, 'cross_tenant_shift');
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNotNull);
    });

    test('no selected session performs no local or remote work', () async {
      sessions.clear();
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      expect(result.errorCode, 'no_selected_session');
      expect(server.created, isEmpty);
      expect(server.reads, isEmpty);
    });
  });
}

/// [_controller] with the reader named, for the two H2 cases that need local
/// storage and the server to disagree.
TenantShiftController _controllerWithReader(
  TenantSessionController sessions,
  HiveTenantShiftState state,
  _Server server,
  TenantDataReader reader,
) => _controller(sessions, state, server, reader: reader);

TenantShiftController _controller(
  TenantSessionController sessions,
  HiveTenantShiftState state,
  _Server server, {
  bool online = true,
  VoidCallback? beforeCreate,
  VoidCallback? beforeRead,
  ShiftSalesLedger? salesLedger,
  ShiftServerSalesTotals? serverTotals,
  TenantDataReader? reader,
}) {
  var nextShift = 0;
  return TenantShiftController(
    sessionController: sessions,
    localState: state,
    salesLedger: salesLedger ?? _Ledger(),
    serverTotals: serverTotals,
    reader: reader ?? _Reader(server, beforeRead: beforeRead),
    writer: FirebaseTenantShiftWriter.forTesting(
      isOnline: () async => online,
      create: (path, data) async {
        beforeCreate?.call();
        await server.create(path, data);
      },
      update: server.update,
    ),
    deviceId: _deviceA,
    isOnline: () async => online,
    shiftIdFactory: () => 'shift-${++nextShift}',
    clock: () => DateTime.utc(2026, 7, 31, 9),
  );
}

Future<Box<dynamic>> _openBox() => Hive.openBox<dynamic>(
  HiveTenantShiftState.boxName,
  encryptionCipher: HiveAesCipher(_encryptionKey),
  crashRecovery: false,
);

final List<int> _encryptionKey = List<int>.generate(
  HiveTenantShiftState.encryptionKeyBytes,
  (index) => (index * 13) % 256,
);

Map<String, Object?> _document({Map<String, Object?>? overrides}) {
  final data = <String, Object?>{
    'shiftId': 'shift-a',
    'tenantId': 'tenant-a',
    'staffId': 'user-a',
    'deviceId': _deviceA,
    'businessDate': _businessDate,
    'status': 'open',
    'startTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 6)),
  };
  if (overrides != null) data.addAll(overrides);
  return data;
}

/// A declaration carrying one figure, for the tests whose subject is the cash.
ShiftTenderDeclaration _declared(int cash, {int mpesa = 0, int card = 0}) =>
    ShiftTenderDeclaration.tryParse(cash: cash, mpesa: mpesa, card: card)!;

TenantShiftLocalRecord _record({
  String uid = 'user-a',
  String tenantId = 'tenant-a',
  String shiftId = 'shift-a',
  bool serverConfirmedOpen = true,
  bool closeInProgress = false,
  ShiftTenderDeclaration? declaration,
  DateTime? openedAt,
  String businessDate = _businessDate,
}) => TenantShiftLocalRecord(
  uid: uid,
  tenantId: tenantId,
  shiftId: shiftId,
  businessDate: businessDate,
  deviceId: _deviceA,
  serverConfirmedOpen: serverConfirmedOpen,
  closeInProgress: closeInProgress,
  declaration: declaration,
  updatedAt: DateTime.utc(2026, 7, 31, 9),
  openedAt: openedAt ?? DateTime.utc(2026, 7, 31, 9),
);

/// A minimal in-memory stand-in for the canonical shift documents.
final class _Server {
  final Map<String, Map<String, Object?>> shifts =
      <String, Map<String, Object?>>{};
  final List<String> reads = <String>[];
  final List<String> queries = <String>[];
  final List<(String, Map<String, Object?>)> created =
      <(String, Map<String, Object?>)>[];
  final List<(String, Map<String, Object?>)> updated =
      <(String, Map<String, Object?>)>[];
  Object? failCreateWith;
  Object? failUpdateWith;
  Object? failReadWith;
  Object? failQueryWith;
  String? responsePath;

  Future<void> create(String path, Map<String, Object?> data) async {
    final failure = failCreateWith;
    if (failure != null) throw failure;
    created.add((path, data));
    shifts[path] = <String, Object?>{
      ...data,
      'startTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 6)),
    };
  }

  Future<void> update(String path, Map<String, Object?> data) async {
    final failure = failUpdateWith;
    if (failure != null) throw failure;
    updated.add((path, data));
    final current = shifts[path];
    if (current == null) throw StateError('No shift at $path.');
    shifts[path] = <String, Object?>{
      ...current,
      ...data,
      'endTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 18)),
    };
  }
}

/// The reader H2 describes: local storage has the write, the server does not.
///
/// **This is the one shape the ordinary fakes cannot express.** `_Reader` reads
/// a single map, so its two modes agree by construction; the defect needs them
/// to disagree - an ordinary read answered out of the device's own unsent `set`
/// while a server-backed read correctly says there is nothing there. Confirmed
/// against the real SDK in `integration_test/shift_pending_write_test.dart`.
final class _PendingWriteReader
    implements TenantDataReader, TenantServerReadable {
  _PendingWriteReader(this._pending, this._server);

  /// What local storage answers with, standing in for the queued write.
  final _Server _pending;

  /// What the server answers with, which is nothing until the write lands.
  final _Server _server;

  @override
  TenantDataReader get serverOnly => _Reader(_server);

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) =>
      _Reader(_pending).getDocument(path);

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) => _Reader(_pending).getCollectionPage(query);
}

/// A reader over `_Server`, which is a server and holds no local copy.
///
/// **[serverOnly] is itself, because every read here is already a server read.**
/// `_Server` has no cache for an answer to come out of, so the two modes are
/// one read - and a fake that declined the mode would leave
/// `TenantShiftController._settle` unable to confirm any shift at all, which is
/// H2's fix failing closed rather than working.
final class _Reader implements TenantDataReader, TenantServerReadable {
  _Reader(this._server, {this.beforeRead});

  final _Server _server;
  final VoidCallback? beforeRead;

  @override
  TenantDataReader get serverOnly => this;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    beforeRead?.call();
    _server.reads.add(path);
    final failure = _server.failReadWith;
    if (failure != null) throw failure;
    final data = _server.shifts[path];
    if (data == null) return null;
    return TenantDocumentSnapshot(
      path: _server.responsePath ?? path,
      data: data,
    );
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    _server.queries.add(query.collectionPath);
    final failure = _server.failQueryWith;
    if (failure != null) throw failure;
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final path in _server.shifts.keys.toList()..sort()) {
      if (!path.startsWith('${query.collectionPath}/')) continue;
      final data = _server.shifts[path]!;
      if (!query.equalityFilters.entries.every(
        (filter) => data[filter.key] == filter.value,
      )) {
        continue;
      }
      matches.add(TenantQueryDocumentSnapshot(path: path, data: data));
      if (matches.length >= query.limit) break;
    }
    return matches;
  }
}

/// A configurable stand-in for the local sale evidence of one shift.
final class _Ledger implements ShiftSalesLedger {
  ShiftSalesSummary summary = ShiftSalesSummary.empty;
  Object? failure;
  final List<String> requested = <String>[];

  @override
  Future<ShiftSalesSummary> summarize({
    required String uid,
    required String tenantId,
    required String shiftId,
  }) async {
    requested.add(shiftId);
    final error = failure;
    if (error != null) throw error;
    return summary;
  }
}

/// What the server would count for a shift, whichever phones sold into it.
final class _Totals implements ShiftServerSalesTotals {
  _Totals(this.totals);

  /// Null answers as a failed or impossible count does.
  ShiftServerTotals? totals;
  final List<String> requested = <String>[];

  @override
  Future<ShiftServerTotals?> read({
    required String tenantId,
    required String uid,
    required String shiftId,
  }) async {
    requested.add(shiftId);
    return totals;
  }
}

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.cashier,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
