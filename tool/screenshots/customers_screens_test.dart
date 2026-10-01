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
import 'package:uzapay_pos/ui/scaffold.dart';
import 'package:uzapay_pos/ui/tokens.dart';
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
  _Business({this.eReceipts}) : _business = FakeTenantReader.business();

  final FakeTenantReader _business;
  final Map<String, Object?>? eReceipts;

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

Widget _whatsapp() => inSession(
  TenantWhatsappReceiptsScreen(
    reader: _Business(
      eReceipts: const <String, Object?>{
        'whatsappEnabled': true,
        'mode': 'automatic',
        'format': 'pdf',
      },
    ),
    writer: const _ConfigurationWriter(),
    statusCheck: (_) async => true,
  ),
  controller: seedSession(role: TenantRole.owner, uid: ownerUid),
);

Widget _loyalty() => inSession(
  AppScaffold(
    title: 'Configs',
    contentWidth: AppContentWidth.reading,
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: TenantLoyaltySettingsPanel(
        reader: _Business(),
        writer: const _ConfigurationWriter(),
      ),
    ),
  ),
  controller: seedSession(role: TenantRole.owner, uid: ownerUid),
);

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

  screenshotCase(
    'configs-loyalty',
    build: _loyalty,
    viewports: responsiveViewports,
  );
}
