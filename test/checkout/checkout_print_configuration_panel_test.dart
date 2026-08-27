import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/checkout/checkout_print_configuration_panel.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/states.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/notices.dart';

const String _printerPath = 'tenants/tenant-a/configuration/printer';

Map<String, Object?> _stored({
  String host = '192.168.1.50',
  int port = 9100,
  String paperWidth = 'columns_32',
  bool hasCutter = true,
}) => <String, Object?>{
  'transport': 'direct_tcp',
  'host': host,
  'port': port,
  'paperWidth': paperWidth,
  'hasCutter': hasCutter,
};

void main() {
  testWidgets('a business with no printer is told receipts go nowhere', (
    tester,
  ) async {
    // **And that sales are unaffected**, which is §8 rule 6 and the whole
    // reason printing is allowed to fail: a printer that is not set up must
    // never read as a till that is broken.
    final reader = _Reader();

    await _pump(tester, _controller(), reader, writer: _Writer());

    // **A `Callout` since 2026-08-26, where this was a loose grey paragraph.**
    // Whether receipts are going anywhere is the screen's standing rather than
    // prose about it, and §2.1 wants a container, a glyph and a word for that.
    // `attention` is its "awaiting": a setup step nobody has taken.
    expect(
      noticeMessage(tester, 'printer-configuration-current'),
      'No printer is set up, so receipts are not sent anywhere. Sales are '
          'recorded as normal.',
    );
    expect(
      noticeStatus(tester, 'printer-configuration-current'),
      AppStatus.attention,
    );
    expect(reader.requested.single, _printerPath);
    // Nothing to replace, so the button says what it does rather than what it
    // changes.
    expect(_buttonLabel(tester, 'printer-configuration-submit'), 'Save printer');
  });

  testWidgets('a configured printer is stated with its address and roll', (
    tester,
  ) async {
    final reader = _Reader(stored: _stored(paperWidth: 'columns_48'));

    await _pump(tester, _controller(), reader, writer: _Writer());

    expect(
      noticeMessage(tester, 'printer-configuration-current'),
      'Receipts go to 192.168.1.50:9100 on 48-column paper.',
    );
    // Nothing is wrong and nothing is pending: §2.1's "informational".
    expect(
      noticeStatus(tester, 'printer-configuration-current'),
      AppStatus.info,
    );
    expect(
      _buttonLabel(tester, 'printer-configuration-submit'),
      'Change printer',
    );
  });

  testWidgets('a malformed document says so and offers to replace it', (
    tester,
  ) async {
    // The strict read model refuses it and printing stops, so the one person
    // who can correct it must see it rather than be shown the cashier's
    // refusal.
    final reader = _Reader(stored: _stored(host: 'http://printer'));

    await _pump(tester, _controller(), reader);

    expect(
      noticeMessage(tester, 'printer-configuration-current'),
      'The saved printer settings cannot be read, so receipts are not sent '
          'anywhere. Saving a printer here replaces them.',
    );
    // §2.1 gives `problem` the meaning "difference found, **unreadable**, out
    // of stock", and settings that cannot be read is exactly that.
    expect(
      noticeStatus(tester, 'printer-configuration-current'),
      AppStatus.problem,
    );
  });

  testWidgets('the form is prefilled from what is stored', (tester) async {
    await _pump(
      tester,
      _controller(),
      _Reader(stored: _stored(host: 'till.shop.local', port: 515)),
      writer: _Writer(),
    );

    expect(find.text('till.shop.local'), findsOne);
    expect(find.text('515'), findsOne);
  });

  testWidgets('an unconfigured form still defaults the port', (tester) async {
    // The port is the half of an address that is safe to guess; the host is
    // not, and is left empty.
    await _pump(tester, _controller(), _Reader(), writer: _Writer());

    expect(find.text('${PrinterEndpoint.rawEscPosPort}'), findsOne);
  });

  group('saving', () {
    testWidgets('writes exactly the printer keys, merged, and re-reads', (
      tester,
    ) async {
      final writer = _Writer();
      final reader = _Reader();

      await _pump(tester, _controller(), reader, writer: writer);
      await _save(tester, host: '192.168.1.50');

      expect(writer.merges.single.path, _printerPath);
      expect(writer.merges.single.data, <String, Object?>{
        'transport': 'direct_tcp',
        'host': '192.168.1.50',
        'port': 9100,
        'paperWidth': 'columns_32',
        'hasCutter': true,
        'updatedBy': 'owner-a',
      });
      expect(
        noticeStatus(tester, 'printer-configuration-notice'),
        AppStatus.ok,
      );
      // Re-read, because the document is what a receipt is dialled at rather
      // than the value that was typed.
      expect(reader.requested, hasLength(2));
    });

    testWidgets('refuses an address this app would not dial', (tester) async {
      // The same validation that guards the durable job record and the socket.
      // The refusal a person reads is the refusal the socket would have given.
      final writer = _Writer();

      await _pump(tester, _controller(), _Reader(), writer: writer);
      await _save(tester, host: 'http://printer', confirm: false);

      expect(writer.merges, isEmpty);
      expect(
        noticeMessage(tester, 'printer-configuration-notice'),
        startsWith('Enter the printer address as a name or an IP'),
      );
    });

    testWidgets('refuses a port that is not a number', (tester) async {
      final writer = _Writer();

      await _pump(tester, _controller(), _Reader(), writer: writer);
      await tester.enterText(
        find.byKey(const ValueKey('printer-configuration-port')),
        'nine thousand',
      );
      await _save(tester, host: '192.168.1.50', confirm: false);

      expect(writer.merges, isEmpty);
      expect(
        noticeMessage(tester, 'printer-configuration-notice'),
        startsWith('Enter the port as a number'),
      );
    });

    testWidgets('re-saving the identical printer is not a refusal', (
      tester,
    ) async {
      // The printer the operator wanted saved *is* what is saved, so the
      // intent is satisfied - `info`, not `problem`.
      final writer = _Writer();

      await _pump(
        tester,
        _controller(),
        _Reader(stored: _stored()),
        writer: writer,
      );
      await _save(tester, host: '192.168.1.50', confirm: false);

      expect(writer.merges, isEmpty);
      expect(
        noticeStatus(tester, 'printer-configuration-notice'),
        AppStatus.info,
      );
    });

    testWidgets('warns that queued receipts keep the old address', (
      tester,
    ) async {
      // §8 rule 6, and the one thing this change has to warn about: a job
      // carries its own address, so a receipt already waiting still goes where
      // it was queued to go.
      await _pump(
        tester,
        _controller(),
        _Reader(stored: _stored()),
        writer: _Writer(),
      );
      await tester.enterText(
        find.byKey(const ValueKey('printer-configuration-host')),
        '192.168.1.99',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('printer-configuration-submit')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Point receipts at a different printer?'), findsOne);
      expect(
        find.textContaining('still goes to 192.168.1.50:9100'),
        findsOne,
      );
    });

    testWidgets('an offline write says nothing was saved', (tester) async {
      final writer = _Writer(
        result: const TenantConfigurationWriteResult.unavailable(),
      );

      await _pump(tester, _controller(), _Reader(), writer: writer);
      await _save(tester, host: '192.168.1.50');

      expect(
        noticeStatus(tester, 'printer-configuration-notice'),
        AppStatus.info,
      );
    });

    testWidgets('a rejected write does not re-read', (tester) async {
      // Nothing changed, so re-reading would only discard the form.
      final reader = _Reader();
      final writer = _Writer(
        result: const TenantConfigurationWriteResult.rejected(
          'permission-denied',
        ),
      );

      await _pump(tester, _controller(), reader, writer: writer);
      await _save(tester, host: '192.168.1.50');

      expect(reader.requested, hasLength(1));
      expect(
        noticeStatus(tester, 'printer-configuration-notice'),
        AppStatus.problem,
      );
    });
  });

  group('testing a printer', () {
    testWidgets('probes what is typed, not what is stored', (tester) async {
      // The whole use is checking an address before committing to it.
      final probed = <PrinterEndpoint>[];

      await _pump(
        tester,
        _controller(),
        _Reader(stored: _stored()),
        writer: _Writer(),
        probe: (endpoint) async => probed.add(endpoint),
      );
      await tester.enterText(
        find.byKey(const ValueKey('printer-configuration-host')),
        '192.168.1.99',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('printer-configuration-test')));
      await tester.pumpAndSettle();

      expect(probed.single.host, '192.168.1.99');
      // **A snack bar since 2026-08-26.** A probe changes nothing, so its
      // answer is not the state of this page and no longer sits in the same
      // block as the record of a save.
      expect(
        snackNotice(tester).message,
        'The printer answered. Nothing was printed.',
      );
      expect(
        find.byKey(const ValueKey('printer-configuration-notice')),
        findsNothing,
      );
    });

    testWidgets('says nothing was printed, because nothing was', (
      tester,
    ) async {
      // `probe` connects and closes. Onboarding needs the answer without
      // wasting paper, and the sentence must not imply a test page came out.
      await _pump(
        tester,
        _controller(),
        _Reader(stored: _stored()),
        writer: _Writer(),
        probe: (_) async {},
      );
      await tester.tap(find.byKey(const ValueKey('printer-configuration-test')));
      await tester.pumpAndSettle();

      expect(snackNotice(tester).message, contains('Nothing was printed'));
      expect(snackNotice(tester).status, AppStatus.ok);
    });

    testWidgets('maps a failure through the transports own vocabulary', (
      tester,
    ) async {
      // This screen invents no sentence of its own; the eight codes are mapped
      // once, in `checkout_print_failures.dart`.
      await _pump(
        tester,
        _controller(),
        _Reader(stored: _stored()),
        writer: _Writer(),
        probe: (_) async => throw const PrinterTransportException(
          PrinterTransportCode.connectTimeout,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('printer-configuration-test')));
      await tester.pumpAndSettle();

      expect(
        snackNotice(tester).message,
        PrinterFailureNotice.of(PrinterTransportCode.connectTimeout).message,
      );
    });

    testWidgets('is not offered where there is no transport to probe with', (
      tester,
    ) async {
      // A control that cannot work is worse than a missing one.
      await _pump(tester, _controller(), _Reader(), writer: _Writer());

      expect(find.byKey(const ValueKey('printer-configuration-test')), findsNothing);
    });
  });

  group('who may change it', () {
    testWidgets('a manager is denied the whole route, not shown it read-only', (
      tester,
    ) async {
      // Every active member reads this document - a till cannot send a receipt
      // without it - but deciding what hardware the business owns is not an
      // operational act.
      for (final role in const <TenantRole>[
        TenantRole.manager,
        TenantRole.cashier,
      ]) {
        await _pump(
          tester,
          _controller(role: role),
          _Reader(stored: _stored()),
          writer: _Writer(),
        );

        expect(
          find.byKey(const ValueKey('printer-configuration-denied')),
          findsOne,
          reason: role.name,
        );
        // And it says what is still true, rather than only refusing.
        expect(
          find.textContaining('Receipts still print on whatever'),
          findsOne,
          reason: role.name,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('a build with no writer states it rather than pretending', (
      tester,
    ) async {
      await _pump(tester, _controller(), _Reader(stored: _stored()));

      expect(
        find.byKey(const ValueKey('printer-configuration-read-only')),
        findsOne,
      );
      expect(
        find.byKey(const ValueKey('printer-configuration-submit')),
        findsNothing,
      );
    });
  });

  testWidgets('a failed read is an ErrorState that says nothing changed', (
    tester,
  ) async {
    await _pump(tester, _controller(), _Reader.failing(), writer: _Writer());

    expect(find.byKey(const ValueKey('printer-configuration-failure')), findsOne);
    expect(find.byType(ErrorState), findsOne);
  });
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

String _buttonLabel(WidgetTester tester, String key) => tester
    .widget<AppButton>(find.byKey(ValueKey(key)))
    .label;

/// Types a host and saves, which is the only way anything is written.
Future<void> _save(
  WidgetTester tester, {
  required String host,
  bool confirm = true,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('printer-configuration-host')),
    host,
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('printer-configuration-submit')));
  await tester.pumpAndSettle();
  if (!confirm) return;
  await tester.tap(find.byKey(const ValueKey('printer-configuration-confirm')));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  TenantConfigurationDocumentWriter? writer,
  PrinterProbe? probe,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantPrinterConfigurationPanel(
            reader: reader,
            writer: writer,
            probe: probe,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

TenantSessionController _controller({TenantRole role = TenantRole.owner}) =>
    TenantSessionController()
      ..open(uid: 'owner-a', membership: _membership(role: role));

TenantMembership _membership({TenantRole role = TenantRole.owner}) =>
    TenantMembership(
      tenantId: 'tenant-a',
      tenantName: 'tenant-a',
      tenantSlug: 'tenant-a',
      role: role,
      membershipStatus: MembershipStatus.active,
      tenantStatus: TenantStatus.active,
      isOwner: role == TenantRole.owner,
      mirrorVersion: 1,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
      serverCanAccess: true,
      canonicalTenantExists: true,
      canonicalMembershipExists: true,
    );

final class _Merge {
  const _Merge(this.path, this.data);

  final String path;
  final Map<String, Object?> data;
}

final class _Writer implements TenantConfigurationDocumentWriter {
  _Writer({this.result = const TenantConfigurationWriteResult.committed()});

  final TenantConfigurationWriteResult result;
  final List<_Merge> merges = <_Merge>[];

  @override
  Future<TenantConfigurationWriteResult> merge({
    required String path,
    required Map<String, Object?> data,
  }) async {
    merges.add(_Merge(path, data));
    return result;
  }
}

final class _Reader implements TenantDataReader {
  _Reader({Map<String, Object?>? stored}) : _stored = stored, _fails = false;

  _Reader.failing() : _stored = null, _fails = true;

  final Map<String, Object?>? _stored;
  final bool _fails;
  final List<String> requested = <String>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    requested.add(path);
    if (_fails) throw StateError('unavailable');
    final stored = _stored;
    return stored == null
        ? null
        : TenantDocumentSnapshot(path: path, data: stored);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}
