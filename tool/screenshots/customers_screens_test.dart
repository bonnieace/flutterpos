/// Evidence for customers and WhatsApp receipts: the directory, a customer's
/// record, the form that adds one, the till's customer picker, the WhatsApp
/// tile and the Loyalty tab.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/checkout/checkout_configuration_writer.dart';
import 'package:uzapay_pos/customers/customers.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/whatsapp/whatsapp.dart';

import 'fakes.dart';
import 'harness.dart';

/// Takes every write and records nothing: these captures are of what a person
/// sees, and no capture here submits.
final class _Writer implements TenantCustomerWriter {
  const _Writer();

  @override
  Future<TenantCustomerWriteResult> createCustomer(
    TenantCustomerCreateIntent intent,
  ) async => const TenantCustomerWriteResult.queued('customer-create-capture');

  @override
  Future<TenantCustomerWriteResult> updateCustomer(
    TenantCustomerUpdateIntent intent,
  ) async => const TenantCustomerWriteResult.queued('customer-update-capture');
}

final class _ConfigurationWriter implements TenantConfigurationDocumentWriter {
  const _ConfigurationWriter();

  @override
  Future<TenantConfigurationWriteResult> merge({
    required String path,
    required Map<String, Object?> data,
  }) async => const TenantConfigurationWriteResult.committed();
}

final class _ReceiptWriter implements TenantWhatsappReceiptWriter {
  const _ReceiptWriter();

  @override
  Future<void> send(TenantWhatsappReceiptIntent intent) async {}
}

const String _jane = 'cu_0123456789abcdef0123456789abcdef01234567';
const String _otieno = 'cu_1123456789abcdef0123456789abcdef01234567';
const String _mary = 'cu_2123456789abcdef0123456789abcdef01234567';

Map<String, Object?> _customer(
  String name, {
  String? phone,
  bool optedIn = false,
  bool active = true,
  int points = 0,
  String? kraPin,
  DateTime? lastSaleAt,
}) {
  final search = tenantCustomerSearchFields(name: name, phone: phone);
  return <String, Object?>{
    'name': name,
    if (phone != null) 'phone': phone,
    if (optedIn) 'whatsappOptIn': true,
    'active': active,
    if (points > 0) 'points': points,
    if (kraPin != null) 'kraPin': kraPin,
    if (lastSaleAt != null) 'lastSaleAt': lastSaleAt,
    'searchName': search.searchName,
    'searchPrefixes': search.searchPrefixes,
  };
}

final Map<String, Map<String, Object?>> _customers =
    <String, Map<String, Object?>>{
      _jane: _customer(
        'Jane Wanjiku',
        phone: '+254712345678',
        optedIn: true,
        points: 42,
        kraPin: 'A012345678Z',
        lastSaleAt: DateTime.utc(2026, 9, 29, 9),
      ),
      _otieno: _customer(
        'John Otieno',
        phone: '+254700000001',
        lastSaleAt: DateTime.utc(2026, 9, 12, 9),
      ),
      _mary: _customer('Mary Akinyi', active: false),
    };

/// The seeded business, with customers searchable the way the index answers.
final class _Business
    implements TenantDataReader, TenantCustomerSearchReader {
  _Business({this.eReceipts, this.deliveries})
    : _business = FakeTenantReader.business();

  final FakeTenantReader _business;
  final Map<String, Object?>? eReceipts;

  /// The WhatsApp receipts the sent tab lists, newest first. Null answers the
  /// two the till and the record captures have always drawn.
  final List<Map<String, Object?>>? deliveries;

  String get _root => 'tenants/$seedTenantId';

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (path == '$_root/configuration/e_receipts' && eReceipts != null) {
      return TenantDocumentSnapshot(path: path, data: eReceipts!);
    }
    if (path == '$_root/configuration/loyalty') {
      return TenantDocumentSnapshot(
        path: path,
        data: const <String, Object?>{
          'enabled': true,
          'minorUnitsPerPoint': 10000,
        },
      );
    }
    final id = path.split('/').last;
    if (path.startsWith('$_root/customers/') && _customers[id] != null) {
      return TenantDocumentSnapshot(path: path, data: _customers[id]!);
    }
    return _business.getDocument(path);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    if (query.collectionPath.endsWith('/receipt_deliveries') &&
        deliveries != null) {
      return <TenantQueryDocumentSnapshot>[
        for (final (index, data) in deliveries!.indexed)
          TenantQueryDocumentSnapshot(
            path: '${query.collectionPath}/rd_${index + 1}',
            data: data,
          ),
      ];
    }
    if (query.collectionPath.endsWith('/receipt_deliveries')) {
      return <TenantQueryDocumentSnapshot>[
        TenantQueryDocumentSnapshot(
          path: '${query.collectionPath}/rd_1',
          data: <String, Object?>{
            'saleId': 'co-1',
            'receiptNumber': 'AMINA-CT-7F2-014',
            'customerName': 'Jane Wanjiku',
            'phoneMasked': '+254•••678',
            'trigger': 'automatic',
            'status': 'read',
            'createdAt': DateTime.utc(2026, 10, 1, 9, 30),
          },
        ),
        TenantQueryDocumentSnapshot(
          path: '${query.collectionPath}/rd_2',
          data: <String, Object?>{
            'saleId': 'co-2',
            'receiptNumber': 'AMINA-CT-7F2-011',
            'phoneMasked': '+254•••001',
            'trigger': 'manual',
            'status': 'failed',
            'reason': 'refused_131026',
            'createdAt': DateTime.utc(2026, 10, 1, 8, 10),
          },
        ),
      ];
    }
    if (query.collectionPath.endsWith('/sales')) {
      return const <TenantQueryDocumentSnapshot>[];
    }
    return _business.getCollectionPage(query);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> searchTenantCustomers(
    TenantCustomerSearchQuery query,
  ) async {
    final rows = <TenantQueryDocumentSnapshot>[
      for (final entry in _customers.entries)
        if ((query.active == null ||
                (entry.value['active'] != false) == query.active) &&
            (query.searchPrefix == null ||
                (entry.value['searchPrefixes']! as List<String>).contains(
                  query.searchPrefix,
                )))
          TenantQueryDocumentSnapshot(
            path: '${query.collectionPath}/${entry.key}',
            data: entry.value,
          ),
    ]..sort(
        (left, right) => (left.data['searchName']! as String).compareTo(
          right.data['searchName']! as String,
        ),
      );
    return rows.take(query.limit).toList();
  }
}

Widget _directory() => inSession(
  TenantCustomersScreen(reader: _Business(), writer: const _Writer()),
  controller: seedSession(role: TenantRole.manager, uid: managerUid),
);

Widget _record() => inSession(
  TenantCustomerRecordScreen(
    reader: _Business(),
    writer: const _Writer(),
    customerId: _jane,
    currency: seedCurrency,
  ),
  controller: seedSession(role: TenantRole.manager, uid: managerUid),
);

Widget _till() => inSession(
  TenantCheckoutScreen(
    cache: FakeCatalogSource(),
    drafts: FakeDraftSink(),
    customers: CheckoutCustomerServices(
      reader: _Business(
        eReceipts: const <String, Object?>{
          'whatsappEnabled': true,
          'mode': 'manual',
          'format': 'pdf',
        },
      ),
      writer: const _Writer(),
      receiptWriter: const _ReceiptWriter(),
    ),
  ),
  controller: seedSession(role: TenantRole.cashier, uid: cashierUid),
);

Widget _whatsapp({
  bool enabled = true,
  String mode = 'automatic',
  String format = 'pdf',
  List<Map<String, Object?>>? deliveries,
}) => inSession(
  TenantWhatsappReceiptsScreen(
    reader: _Business(
      eReceipts: <String, Object?>{
        'whatsappEnabled': enabled,
        'mode': mode,
        'format': format,
      },
      deliveries: deliveries,
    ),
    writer: const _ConfigurationWriter(),
    statusCheck: (_) async => true,
    clock: () => _sentToday,
  ),
  controller: seedSession(role: TenantRole.owner, uid: ownerUid),
);

/// The afternoon the sent tab is read on: a Saturday, as on the design's
/// boards (`docs/design/whatsapp-receipts/`).
final DateTime _sentToday = DateTime(2026, 10, 3, 14, 40);

/// One WhatsApp receipt as the server records it.
Map<String, Object?> _delivery(
  String receipt,
  String status,
  DateTime at, {
  String? name,
  String phone = '+254•••678',
  bool automatic = true,
  String? reason,
}) => <String, Object?>{
  'saleId': 'co-$receipt',
  'receiptNumber': 'CT-A7F-$receipt',
  'customerName': ?name,
  'phoneMasked': phone,
  'trigger': automatic ? 'automatic' : 'manual',
  'status': status,
  'reason': ?reason,
  'createdAt': at,
};

/// The design's eight: every status, both triggers, names and bare numbers,
/// reasons, today and yesterday.
final List<Map<String, Object?>> _sentReceipts = <Map<String, Object?>>[
  _delivery(
    '20261003-0042',
    'read',
    DateTime(2026, 10, 3, 14, 32),
    name: 'Wanjiku Mwangi',
  ),
  _delivery('20261003-0041', 'delivered', DateTime(2026, 10, 3, 14, 5)),
  _delivery(
    '20261003-0040',
    'sent',
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
    phone: '+254•••219',
    reason: 'refused_131026',
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
    'read',
    DateTime(2026, 10, 2, 18, 20),
    name: 'Mary Wambui',
    automatic: false,
  ),
  _delivery(
    '20261002-0057',
    'queued',
    DateTime(2026, 10, 2, 17, 45),
    phone: '+254•••530',
    reason: 'waiting_for_sale',
  ),
];

Future<void> _openSentTab(WidgetTester tester) async {
  await tester.tap(find.text('Sent receipts'));
  await tester.pumpAndSettle();
}

/// The Customers screen as an owner opens it, with loyalty as its second tab
/// since 2026-10-04.
Widget _loyalty() => inSession(
  TenantCustomersScreen(
    reader: _Business(),
    writer: const _Writer(),
    loyalty: (_) => TenantLoyaltySettingsPanel(
      reader: _Business(),
      writer: const _ConfigurationWriter(),
    ),
  ),
  controller: seedSession(role: TenantRole.owner, uid: ownerUid),
);

Future<void> _openLoyaltyTab(WidgetTester tester) async {
  await tester.tap(find.text('Loyalty'));
  await tester.pumpAndSettle();
}

void main() {
  screenshotCase(
    'customers-directory',
    build: _directory,
    viewports: responsiveViewports,
  );

  screenshotCase(
    'customer-add',
    build: _directory,
    fullPage: false,
    afterPump: (tester) async {
      await tester.tap(find.byKey(const ValueKey('customers-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('customer-form-name')),
        'Amina Hassan',
      );
      await tester.enterText(
        find.byKey(const ValueKey('phone-local-number')),
        '0722 111 222',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('customer-form-whatsapp-consent')),
      );
      await tester.pumpAndSettle();
    },
    viewports: responsiveViewports,
  );

  screenshotCase(
    'customer-record',
    build: _record,
    viewports: responsiveViewports,
  );

  screenshotCase(
    'till-walk-in',
    build: _till,
    fullPage: false,
    viewports: responsiveViewports,
  );

  screenshotCase(
    'till-customer-picker',
    build: _till,
    fullPage: false,
    afterPump: (tester) async {
      await tester.tap(find.byKey(const ValueKey('screen-title-action')));
      await tester.pumpAndSettle();
    },
    viewports: responsiveViewports,
  );

  screenshotCase(
    'whatsapp-receipts',
    build: _whatsapp,
    viewports: responsiveViewports,
  );

  // The other two settings the design draws, and the sent tab: phone only,
  // because the screen is the reading column at every width.
  screenshotCase(
    'whatsapp-receipts-summary',
    build: () => _whatsapp(mode: 'manual', format: 'summary'),
    fullPage: false,
    viewports: const <ScreenshotViewport>[mobileViewport],
  );

  screenshotCase(
    'whatsapp-receipts-off',
    build: () => _whatsapp(enabled: false),
    fullPage: false,
    viewports: const <ScreenshotViewport>[mobileViewport],
  );

  screenshotCase(
    'whatsapp-receipts-sent',
    build: () => _whatsapp(deliveries: _sentReceipts),
    fullPage: false,
    afterPump: _openSentTab,
    viewports: const <ScreenshotViewport>[mobileViewport],
  );

  screenshotCase(
    'whatsapp-receipts-sent-empty',
    build: () => _whatsapp(deliveries: const <Map<String, Object?>>[]),
    fullPage: false,
    afterPump: _openSentTab,
    viewports: const <ScreenshotViewport>[mobileViewport],
  );

  // The list under the switch an owner gets.
  screenshotCase(
    'customers-tabs',
    build: _loyalty,
    viewports: responsiveViewports,
  );

  screenshotCase(
    'customers-loyalty',
    build: _loyalty,
    afterPump: _openLoyaltyTab,
    viewports: responsiveViewports,
  );
}
