import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_application_1/ui/snackbar.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/notices.dart';

const String _configurationPath = 'tenants/tenant-a/configuration/checkout';

void main() {
  testWidgets('a business with no currency is told it cannot sell', (
    tester,
  ) async {
    final reader = _Reader();

    await _pump(tester, _controller(), reader, writer: _Writer());

    _expectText(
      tester,
      'checkout-configuration-current',
      'This business has published no currency, so no sale can be rung up on '
          'any device yet.',
    );
    expect(reader.requested.single, _configurationPath);
    // The first publication has nothing to replace, so the button says what it
    // does rather than what it changes.
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('checkout-configuration-submit')),
              matching: find.byType(Text),
            ),
          )
          .data,
      'Publish',
    );
  });

  testWidgets('a published currency is stated, and converts nothing', (
    tester,
  ) async {
    final reader = _Reader(currency: 'KES');

    await _pump(tester, _controller(), reader);

    _expectText(
      tester,
      'checkout-configuration-current',
      'This business trades in KES.',
    );
    expect(
      find.textContaining('It converts nothing'),
      findsOne,
      reason: 'no exchange rate exists anywhere in this app',
    );
  });

  testWidgets('settings the till cannot read are correctable here', (
    tester,
  ) async {
    // The strict read model refuses this document, so every device in the
    // business has stopped selling. Showing the cashier's refusal here would
    // leave the one person who can fix it with nothing to do.
    final reader = _Reader(stored: <String, Object?>{'currency': 42});
    final writer = _Writer();

    await _pump(tester, _controller(), reader, writer: writer);

    expect(
      _text(tester, 'checkout-configuration-current'),
      startsWith('The published checkout settings cannot be read'),
    );
    await _publish(tester, 'KES');

    expect(writer.published.single.currency, 'KES');
    // Nothing usable was replaced, so the confirmation had nothing to warn
    // about and the intent agrees.
    expect(writer.published.single.changesPublishedCurrency, isFalse);
  });

  testWidgets('a first publication writes the code and asks for a sync', (
    tester,
  ) async {
    final reader = _Reader();
    final writer = _Writer();
    var syncs = 0;

    await _pump(
      tester,
      _controller(),
      reader,
      writer: writer,
      onPublished: () => syncs++,
    );
    await _publish(tester, 'kes');

    // Typed in whatever case, published in the only one an ISO code has.
    expect(writer.published.single.currency, 'KES');
    expect(writer.published.single.documentData(), <String, Object?>{
      'currency': 'KES',
      'updatedBy': 'owner-a',
    });
    // Without the signal this device keeps pricing from the catalog snapshot it
    // already holds, which carries no currency at all yet.
    expect(syncs, 1);
    expect(
      snackNotice(tester).message,
      'Published. This device re-reads it on its next sync, and every other '
      'device picks it up when it syncs.',
    );
    // The notice carries what kind of answer it is, which is what a bare
    // sentence in this position never did.
    expect(
      snackNotice(tester).status,
      AppStatus.ok,
    );
    // The document is what a till prices with, so the page re-reads rather than
    // showing the value that was typed.
    expect(reader.requested.length, 2);
  });

  testWidgets('replacing a code warns that nothing is re-priced', (
    tester,
  ) async {
    final reader = _Reader(currency: 'KES');
    final writer = _Writer();

    await _pump(tester, _controller(), reader, writer: writer);
    await tester.enterText(
      find.byKey(const ValueKey('checkout-configuration-currency')),
      'UGX',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('checkout-configuration-submit')),
    );
    await tester.pumpAndSettle();

    // The three facts a change actually has: no conversion, recorded sales keep
    // their own code, and an unsynced device keeps using the old one.
    expect(find.textContaining('no amount is converted'), findsOne);
    expect(
      find.textContaining('Every sale already recorded keeps that code'),
      findsOne,
    );
    expect(find.textContaining('keeps pricing new sales in KES'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('checkout-configuration-cancel')),
    );
    await tester.pumpAndSettle();
    expect(writer.published, isEmpty);
  });

  testWidgets('the published code cannot be republished as itself', (
    tester,
  ) async {
    final reader = _Reader(currency: 'KES');
    final writer = _Writer();

    await _pump(tester, _controller(), reader, writer: writer);
    await tester.enterText(
      find.byKey(const ValueKey('checkout-configuration-currency')),
      'kes',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('checkout-configuration-submit')),
    );
    await tester.pumpAndSettle();

    // Refused before anything is confirmed: a dialog asking about a change that
    // changes nothing would be worse than the sentence.
    expect(
      find.byKey(const ValueKey('checkout-configuration-confirm')),
      findsNothing,
    );
    // **`info`, not `problem`, and this is the case the model was built for.**
    // The currency the operator wanted published *is* published; nothing failed
    // and nothing needs doing. Painting it the same red as a forbidden change
    // would report a fault where the intent is already satisfied.
    expect(
      snackNotice(tester).message,
      'That is already the published currency.',
    );
    expect(
      snackNotice(tester).status,
      AppStatus.info,
    );
    expect(writer.published, isEmpty);
  });

  testWidgets('a code that is not three letters never reaches the writer', (
    tester,
  ) async {
    final reader = _Reader();
    final writer = _Writer();

    await _pump(tester, _controller(), reader, writer: writer);
    await tester.enterText(
      find.byKey(const ValueKey('checkout-configuration-currency')),
      'K1S',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('checkout-configuration-submit')),
    );
    await tester.pumpAndSettle();

    expect(
      snackNotice(tester).message,
      'Enter a three-letter ISO 4217 currency code, such as KES or UGX.',
    );
    expect(
      snackNotice(tester).status,
      AppStatus.problem,
    );
    expect(writer.published, isEmpty);
  });

  testWidgets('an offline device is told nothing was published', (
    tester,
  ) async {
    final reader = _Reader();
    final writer = _Writer.answering(
      const TenantCheckoutConfigurationWriteResult.unavailable(),
    );
    var syncs = 0;

    await _pump(
      tester,
      _controller(),
      reader,
      writer: writer,
      onPublished: () => syncs++,
    );
    await _publish(tester, 'KES');

    expect(
      snackNotice(tester).message,
      startsWith('This device is offline'),
    );
    // Nothing was published, so nothing needs re-reading anywhere.
    expect(syncs, 0);
  });

  testWidgets('a refusal leaves the page as it was', (tester) async {
    final reader = _Reader(currency: 'KES');
    final writer = _Writer.answering(
      const TenantCheckoutConfigurationWriteResult.rejected(
        'permission-denied',
      ),
    );

    await _pump(tester, _controller(), reader, writer: writer);
    await _publish(tester, 'UGX');

    expect(
      snackNotice(tester).message,
      startsWith('The change was refused'),
    );
    // A proved refusal wrote nothing, so there is nothing new to read.
    expect(reader.requested.length, 1);
  });

  testWidgets('an unknown outcome re-reads and says a retry is safe', (
    tester,
  ) async {
    final reader = _Reader(currency: 'KES');
    final writer = _Writer.answering(
      const TenantCheckoutConfigurationWriteResult.ambiguous('write_timeout'),
    );
    var syncs = 0;

    await _pump(
      tester,
      _controller(),
      reader,
      writer: writer,
      onPublished: () => syncs++,
    );
    await _publish(tester, 'UGX');

    // This write names one document and one value, so unlike a return or an
    // adjustment it carries no request ID and a retry converges.
    expect(
      snackNotice(tester).message,
      contains('publishing the same code again is safe'),
    );
    expect(reader.requested.length, 2);
    // Only the server can say whether it landed, so the sync is not claimed.
    expect(syncs, 0);
  });

  testWidgets('a manager and a cashier are denied and read nothing', (
    tester,
  ) async {
    for (final role in <TenantRole>[TenantRole.manager, TenantRole.cashier]) {
      final reader = _Reader(currency: 'KES');

      await _pump(tester, _controller(role: role), reader, writer: _Writer());

      expect(
        find.byKey(const ValueKey('checkout-configuration-denied')),
        findsOne,
        reason: role.name,
      );
      expect(reader.requested, isEmpty, reason: role.name);
      // The guard reloads on a session change rather than on a rebuild, so the
      // tree is torn down between cases and the next role cannot inherit this
      // one's answer.
      await _tearDown(tester);
    }
  });

  testWidgets('an unreadable document leaves no form to publish from', (
    tester,
  ) async {
    // A read that failed is not the same as a business with no currency, and
    // offering the form here would let a transport fault look like the state it
    // is meant to report.
    final reader = _Reader.failing();

    await _pump(tester, _controller(), reader, writer: _Writer());

    expect(
      find.byKey(const ValueKey('checkout-configuration-failure')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('checkout-configuration-currency')),
      findsNothing,
    );
  });

  testWidgets('the form is absent without a writer', (tester) async {
    await _pump(tester, _controller(), _Reader(currency: 'KES'));

    expect(
      find.byKey(const ValueKey('checkout-configuration-currency')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('checkout-configuration-read-only')),
      findsOne,
    );
  });

  testWidgets('a business switch discards an outstanding change', (
    tester,
  ) async {
    final reader = _Reader(currency: 'KES');
    final writer = _Writer.deferred();
    final controller = _controller();

    await _pump(tester, controller, reader, writer: writer);
    await _publish(tester, 'UGX', settle: false);
    expect(writer.published.single.tenantId, 'tenant-a');

    controller.open(uid: 'owner-a', membership: _membership('tenant-b'));
    await tester.pump();
    writer.complete();
    await tester.pump();
    await tester.pump();

    // The result belonged to a session that is no longer selected.
    expect(
      find.byType(AppSnackBar),
      findsNothing,
    );
  });

  group('landing route', () {
    testWidgets('the settings route is offered to an owner and an admin', (
      tester,
    ) async {
      for (final role in <TenantRole>[TenantRole.owner, TenantRole.admin]) {
        await _pumpLanding(tester, role: role);
        expect(
          find.byKey(const ValueKey('checkout-configuration')),
          findsOne,
          reason: role.name,
        );
        await _tearDown(tester);
      }
    });

    testWidgets('a manager and a cashier are not offered it at all', (
      tester,
    ) async {
      for (final role in <TenantRole>[TenantRole.manager, TenantRole.cashier]) {
        await _pumpLanding(tester, role: role);
        expect(
          find.byKey(const ValueKey('checkout-configuration')),
          findsNothing,
          reason: role.name,
        );
        await _tearDown(tester);
      }
    });

    testWidgets('the route stays unreachable while none is supplied', (
      tester,
    ) async {
      await _pumpLanding(tester, role: TenantRole.owner, supplyRoute: false);

      expect(
        find.byKey(const ValueKey('checkout-configuration')),
        findsNothing,
      );
    });

    testWidgets('it opens under the landing route\'s own session scope', (
      tester,
    ) async {
      await _pumpLanding(tester, role: TenantRole.owner);
      await tester.tap(find.byKey(const ValueKey('checkout-configuration')));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOne);
      _expectText(
        tester,
        'checkout-configuration-current',
        'This business trades in KES.',
      );
    });
  });
}

/// Pumps the production safe landing route exactly as the composition root
/// configures it: tenancy owns routing and the checkout domain decides the roles.
Future<void> _pumpLanding(
  WidgetTester tester, {
  required TenantRole role,
  bool supplyRoute = true,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final reader = _Reader(currency: 'KES');
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: _controller(role: role),
        child: TenantSafeLandingScreen(
          membership: _membership('tenant-a', role: role),
          reader: reader,
          onSignOut: () async {},
          checkoutConfigurationRoute: supplyRoute
              ? (reader) => TenantCheckoutConfigurationScreen(reader: reader)
              : null,
          checkoutConfigurationRoles:
              TenantCheckoutConfigurationPublisher.allowedRoles,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  TenantCheckoutConfigurationWriter? writer,
  VoidCallback? onPublished,
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
          body: TenantCheckoutConfigurationPanel(
            reader: reader,
            writer: writer,
            onPublished: onPublished,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Types a code and confirms, which is the only way anything is published.
Future<void> _publish(
  WidgetTester tester,
  String currency, {
  bool settle = true,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('checkout-configuration-currency')),
    currency,
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('checkout-configuration-submit')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('checkout-configuration-confirm')),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Discards the whole tree between two cases of one test.
///
/// `TenantRouteGuard` reloads when its session changes, not when it rebuilds, so
/// a second `pumpWidget` into a live tree keeps the first answer - and a
/// role-by-role loop would then assert the first role's outcome twice.
Future<void> _tearDown(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

void _expectText(WidgetTester tester, String key, String value) {
  expect(_text(tester, key), value);
}

TenantSessionController _controller({TenantRole role = TenantRole.owner}) =>
    TenantSessionController()..open(
      uid: 'owner-a',
      membership: _membership('tenant-a', role: role),
    );

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.owner,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
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

final class _Writer implements TenantCheckoutConfigurationWriter {
  _Writer()
    : _answer = const TenantCheckoutConfigurationWriteResult.committed(),
      _defer = false;

  _Writer.answering(this._answer) : _defer = false;

  _Writer.deferred()
    : _answer = const TenantCheckoutConfigurationWriteResult.committed(),
      _defer = true;

  final TenantCheckoutConfigurationWriteResult _answer;
  final bool _defer;
  final List<TenantCheckoutConfigurationUpdateIntent> published =
      <TenantCheckoutConfigurationUpdateIntent>[];
  final List<Completer<TenantCheckoutConfigurationWriteResult>> _pending =
      <Completer<TenantCheckoutConfigurationWriteResult>>[];

  void complete() {
    if (_pending.isEmpty) return;
    _pending.removeAt(0).complete(_answer);
  }

  @override
  Future<TenantCheckoutConfigurationWriteResult> publish(
    TenantCheckoutConfigurationUpdateIntent intent,
  ) {
    published.add(intent);
    if (!_defer) {
      return Future<TenantCheckoutConfigurationWriteResult>.value(_answer);
    }
    final completer = Completer<TenantCheckoutConfigurationWriteResult>();
    _pending.add(completer);
    return completer.future;
  }
}

final class _Reader implements TenantDataReader {
  _Reader({String? currency, Map<String, Object?>? stored})
    : _stored =
          stored ??
          (currency == null ? null : <String, Object?>{'currency': currency}),
      _fails = false;

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
