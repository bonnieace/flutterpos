/// Evidence for the Email tile: both tabs of `TenantEmailReceiptsScreen`, in
/// the frames `docs/design/email-receipts/` draws - on, read-only and off; the
/// sent list, nothing sent yet, and reading.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/checkout/checkout_configuration_writer.dart';
import 'package:uzapay_pos/email_receipts/email_receipts.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';

import 'fakes.dart';
import 'harness.dart';

final class _ConfigurationWriter implements TenantConfigurationDocumentWriter {
  const _ConfigurationWriter();

  @override
  Future<TenantConfigurationWriteResult> merge({
    required String path,
    required Map<String, Object?> data,
  }) async => const TenantConfigurationWriteResult.committed();
}

/// The seeded business under the boards' name, with the email setting and the
/// receipts the sent tab lists.
final class _Business implements TenantCacheReadable {
  _Business({
    required this.settings,
    this.deliveries = const <Map<String, Object?>>[],
    this.held,
  }) : _business = FakeTenantReader.business();

  final FakeTenantReader _business;
  final Map<String, Object?> settings;

  /// Newest first.
  final List<Map<String, Object?>> deliveries;

  /// A server read of the receipts that has not come back. The device's copy
  /// answers none, which is what the reading state is drawn for.
  final Future<List<TenantQueryDocumentSnapshot>>? held;

  String get _root => 'tenants/$seedTenantId';

  @override
  TenantDataReader get cacheOnly => held == null
      ? this
      : _Business(settings: settings, deliveries: deliveries);

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (path == '$_root/configuration/email_receipts') {
      return TenantDocumentSnapshot(path: path, data: settings);
    }
    if (path == '$_root/configuration/branding') {
      return TenantDocumentSnapshot(
        path: path,
        data: const <String, Object?>{'companyName': 'Mwangi Hardware'},
      );
    }
    return _business.getDocument(path);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    if (query.collectionPath.endsWith('/email_receipt_deliveries')) {
      if (held case final held?) return held;
      return <TenantQueryDocumentSnapshot>[
        for (final (index, data) in deliveries.indexed)
          TenantQueryDocumentSnapshot(
            path: '${query.collectionPath}/ed_${index + 1}',
            data: data,
          ),
      ];
    }
    return _business.getCollectionPage(query);
  }
}

Widget _email({
  bool enabled = true,
  String mode = 'automatic',
  bool readOnly = false,
  List<Map<String, Object?>> deliveries = const <Map<String, Object?>>[],
  Future<List<TenantQueryDocumentSnapshot>>? held,
}) => inSession(
  TenantEmailReceiptsScreen(
    reader: _Business(
      settings: <String, Object?>{'emailEnabled': enabled, 'mode': mode},
      deliveries: deliveries,
      held: held,
    ),
    writer: readOnly ? null : const _ConfigurationWriter(),
    clock: () => _sentToday,
  ),
  controller: seedSession(role: TenantRole.owner, uid: ownerUid),
);

/// The afternoon the sent tab is read on, as on the design's boards.
final DateTime _sentToday = DateTime(2026, 10, 3, 14, 40);

/// One email receipt as the server records it.
Map<String, Object?> _delivery(
  String? receipt,
  String status,
  DateTime at, {
  String? name,
  String email = 'w•••@gmail.com',
  bool automatic = true,
  String? reason,
}) => <String, Object?>{
  'saleId': 'co-${receipt ?? 'pending'}',
  'receiptNumber': ?(receipt == null ? null : 'CT-A7F-$receipt'),
  'customerName': ?name,
  'emailMasked': email,
  'trigger': automatic ? 'automatic' : 'manual',
  'status': status,
  'reason': ?reason,
  'createdAt': at,
};

/// The design's eight: every status, both triggers, names and bare addresses,
/// reasons, today and the day before, and one not numbered yet.
final List<Map<String, Object?>> _sentReceipts = <Map<String, Object?>>[
  _delivery(
    '20261003-0042',
    'delivered',
    DateTime(2026, 10, 3, 14, 32),
    name: 'Wanjiku Mwangi',
  ),
  _delivery(
    '20261003-0041',
    'sent',
    DateTime(2026, 10, 3, 14, 5),
    email: 'n•••@gmail.com',
    automatic: false,
  ),
  _delivery(
    '20261003-0040',
    'delivered',
    DateTime(2026, 10, 3, 13, 58),
    name: 'Otieno Ouma',
    automatic: false,
  ),
  _delivery(
    '20261003-0039',
    'sending',
    DateTime(2026, 10, 3, 13, 57),
    name: 'Achieng Atieno',
  ),
  _delivery(
    '20261003-0035',
    'failed',
    DateTime(2026, 10, 3, 12, 40),
    email: 'p•••@outlook.com',
    automatic: false,
    reason: 'invalid_recipient',
  ),
  _delivery(
    '20261003-0031',
    'skipped',
    DateTime(2026, 10, 3, 11, 2),
    name: 'Kamau Njoroge',
    reason: 'opted_out',
  ),
  _delivery(
    '20261002-0058',
    'delivered',
    DateTime(2026, 10, 2, 18, 20),
    name: 'Mary Wambui',
  ),
  _delivery(
    null,
    'queued',
    DateTime(2026, 10, 2, 17, 45),
    name: 'James Kiprono',
    reason: 'waiting_for_sale',
  ),
];

Future<void> _openSentTab(WidgetTester tester) async {
  await tester.tap(find.text('Sent receipts'));
  await tester.pumpAndSettle();
}

const List<ScreenshotViewport> _phone = <ScreenshotViewport>[mobileViewport];

void main() {
  screenshotCase('email-receipts', build: _email, viewports: _phone);

  screenshotCase(
    'email-receipts-read-only',
    build: () => _email(mode: 'manual', readOnly: true),
    fullPage: false,
    viewports: _phone,
  );

  screenshotCase(
    'email-receipts-off',
    build: () => _email(enabled: false),
    fullPage: false,
    afterPump: (tester) async {
      // Opened, as the board draws it.
      await tester.tap(find.text('Where receipts come from'));
      await tester.pumpAndSettle();
    },
    viewports: _phone,
  );

  screenshotCase(
    'email-receipts-sent',
    build: () => _email(deliveries: _sentReceipts),
    afterPump: _openSentTab,
    viewports: _phone,
  );

  screenshotCase(
    'email-receipts-sent-empty',
    build: _email,
    fullPage: false,
    afterPump: _openSentTab,
    viewports: _phone,
  );

  screenshotCase(
    'email-receipts-sent-reading',
    build: () =>
        _email(held: Completer<List<TenantQueryDocumentSnapshot>>().future),
    fullPage: false,
    afterPump: (tester) async {
      await _openSentTab(tester);
      // Past the placeholders' threshold, which a settle does not wait for.
      await tester.pump(const Duration(seconds: 1));
    },
    viewports: _phone,
  );
}
