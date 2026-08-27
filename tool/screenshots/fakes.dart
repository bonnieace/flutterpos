/// One in-memory business, and the stand-ins every screen reads it through.
///
/// The shape of every document here is copied from the widget test that already
/// pins that screen's read model - `test/**/*_panel_test.dart` - so a screenshot
/// shows the populated surface rather than the "we could not read this" state a
/// wrong field name produces. The *content* is the local seed script's business,
/// `rules-tests/scripts/seed-dev-emulator.js`, so a picture taken here and a
/// person driving the emulators see the same shop.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/returns/returns.dart';
import 'package:flutter_application_1/shift/shift.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:hive/hive.dart';

const String seedTenantId = 'dev-shop';
const String seedTenantName = 'Dev Corner Shop';
const String seedTenantSlug = 'dev-corner-shop';
const String seedCurrency = 'KES';

const String ownerUid = 'owner-dev';
const String adminUid = 'admin-dev';
const String managerUid = 'manager-dev';
const String cashierUid = 'cashier-dev';

/// A device ID in the exact shape a receipt number is derived from.
const String seedDeviceId = 'dev-0123456789abcdef0123456789abcdef';

const String seedPayloadHash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

/// The business day the seeded records belong to.
///
/// Derived from the wall clock through the app's own function, because the
/// surfaces that read a day - the daily summary, reconciliation - compute the
/// same string from `DateTime.now()` and read by exact path. A hardcoded date
/// would render those two screens permanently empty.
///
/// **So the harness is deterministic within one UTC day and not across two, and
/// that is a trap for the way this project measures a change.** Every phase
/// reports "N images moved" as its evidence of containment, hashing
/// `screenshots/` before and after. When a session straddles midnight UTC, every
/// capture that renders a business date or a seeded timestamp moves on the next
/// run for that reason alone - roughly forty of them, none of which the change
/// touched. Phase 07 spent a bisect on it: a nine-file spacing repoint appeared
/// to move 36 reporting, shift, returns and receipt images, and re-measuring
/// against a same-day baseline showed it moved **none**.
///
/// The tell is that the moved set is all date-bearing screens and contains
/// nothing you edited. **Re-baseline and re-run rather than going looking for
/// the cause in your own diff.** Fixing it properly means one injectable clock
/// shared by the fixtures and the surfaces under test, which is a behaviour
/// change and needs its own authorisation.
String seedBusinessDate([int daysAgo = 0]) => checkoutBusinessDate(
  DateTime.now().toUtc().subtract(Duration(days: daysAgo)),
);

/// A moment inside [seedBusinessDate], for a `createdAt` that reads sensibly.
Timestamp seedTimestamp({int daysAgo = 0, int hour = 9, int minute = 30}) {
  final day = DateTime.now().toUtc().subtract(Duration(days: daysAgo));
  return Timestamp.fromDate(
    DateTime.utc(day.year, day.month, day.day, hour, minute),
  );
}

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

TenantMembership seedMembership({
  TenantRole role = TenantRole.owner,
  String tenantId = seedTenantId,
  String tenantName = seedTenantName,
  MembershipStatus membershipStatus = MembershipStatus.active,
  TenantStatus tenantStatus = TenantStatus.active,
  bool canAccess = true,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantName,
  tenantSlug: tenantId == seedTenantId ? seedTenantSlug : tenantId,
  role: role,
  membershipStatus: membershipStatus,
  tenantStatus: tenantStatus,
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 6, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
  serverCanAccess: canAccess,
  canonicalTenantExists: canAccess,
  canonicalMembershipExists: canAccess,
);

TenantSessionController seedSession({
  TenantRole role = TenantRole.owner,
  String uid = ownerUid,
}) => TenantSessionController()
  ..open(
    uid: uid,
    membership: seedMembership(role: role),
  );

/// Puts [child] under a live session, which is what every guarded surface reads
/// its business and role from.
Widget inSession(Widget child, {TenantSessionController? controller}) =>
    TenantSessionScope(controller: controller ?? seedSession(), child: child);

// ---------------------------------------------------------------------------
// Catalog
// ---------------------------------------------------------------------------

const Map<String, Map<String, Object?>> seedCategories =
    <String, Map<String, Object?>>{
      'cat-bakery': <String, Object?>{'name': 'Bakery'},
      'cat-drinks': <String, Object?>{'name': 'Drinks'},
      'cat-household': <String, Object?>{'name': 'Household'},
    };

/// The seed script's catalog, with unit costs added to the products that have
/// one so the profit surfaces have something complete to show.
const Map<String, Map<String, Object?>> seedProducts =
    <String, Map<String, Object?>>{
      'pd-bar-soap-blue': <String, Object?>{
        'name': 'Bar soap - blue',
        'SKU': '5901234123457',
        'price': 145,
        'cost': 112,
        'quantity': 24,
        'categoryId': 'cat-household',
        'image': 'https://inventory.test/products/bar-soap.png',
      },
      'pd-bread-white': <String, Object?>{
        'name': 'White bread loaf',
        'SKU': '6161100000019',
        'price': 65,
        'cost': 48,
        'quantity': 40,
        'categoryId': 'cat-bakery',
        'image': 'https://inventory.test/products/white-bread.png',
      },
      'pd-charcoal-2kg': <String, Object?>{
        'name': 'Charcoal 2kg',
        'SKU': '6161100000071',
        'price': 260,
        'quantity': 12,
        'categoryId': 'cat-household',
      },
      'pd-mandazi': <String, Object?>{
        'name': 'Mandazi',
        'SKU': '6161100000026',
        'price': 20,
        'cost': 11,
        'quantity': 120,
        'categoryId': 'cat-bakery',
      },
      'pd-milk-500': <String, Object?>{
        'name': 'Milk 500ml',
        'SKU': '6161100000057',
        'price': 70,
        'cost': 55,
        'quantity': -3,
        'categoryId': 'cat-drinks',
      },
      'pd-soda-300': <String, Object?>{
        'name': 'Soda 300ml',
        'SKU': '6161100000033',
        'price': 50,
        'cost': 34,
        'quantity': 96,
        'categoryId': 'cat-drinks',
      },
      'pd-water-1l': <String, Object?>{
        'name': 'Water 1L',
        'SKU': '6161100000040',
        'price': 80,
        'cost': 62,
        'quantity': 0,
        'categoryId': 'cat-drinks',
      },
    };

List<TenantCategory> seedCatalogCategories() => <TenantCategory>[
  for (final entry in seedCategories.entries)
    TenantCategory.fromSnapshot(
      TenantQueryDocumentSnapshot(
        path: 'tenants/$seedTenantId/categories/${entry.key}',
        data: entry.value,
      ),
    ),
];

List<TenantProduct> seedCatalogProducts() => <TenantProduct>[
  for (final entry in seedProducts.entries)
    TenantProduct.fromDocument(
      path: 'tenants/$seedTenantId/products/${entry.key}',
      data: entry.value,
    ),
];

TenantProduct seedProduct(String id) => TenantProduct.fromDocument(
  path: 'tenants/$seedTenantId/products/$id',
  data: seedProducts[id]!,
);

// ---------------------------------------------------------------------------
// Staff
// ---------------------------------------------------------------------------

Map<String, Map<String, Object?>> seedStaff() => <String, Map<String, Object?>>{
  ownerUid: <String, Object?>{
    'uid': ownerUid,
    'email': 'grace@devcorner.test',
    'name': 'Grace Wanjiru',
    'phone': '+254700100200',
    'role': 'owner',
    'status': 'active',
    'invitationStatus': 'accepted',
    'searchPrefixes': _seedStaffSearchPrefixes(
      'Grace Wanjiru',
      'grace@devcorner.test',
    ),
  },
  adminUid: <String, Object?>{
    'uid': adminUid,
    'email': 'peter@devcorner.test',
    'name': 'Peter Otieno',
    'phone': '+254700100201',
    'role': 'admin',
    'status': 'active',
    'invitationStatus': 'accepted',
    'searchPrefixes': _seedStaffSearchPrefixes(
      'Peter Otieno',
      'peter@devcorner.test',
    ),
  },
  managerUid: <String, Object?>{
    'uid': managerUid,
    'email': 'amina@devcorner.test',
    'name': 'Amina Hassan',
    'phone': '+254700100202',
    'role': 'manager',
    'status': 'active',
    'invitationStatus': 'accepted',
    'searchPrefixes': _seedStaffSearchPrefixes(
      'Amina Hassan',
      'amina@devcorner.test',
    ),
  },
  cashierUid: <String, Object?>{
    'uid': cashierUid,
    'email': 'brian@devcorner.test',
    'name': 'Brian Kimani',
    'phone': '+254700100203',
    'role': 'cashier',
    'status': 'active',
    'invitationStatus': 'accepted',
    'searchPrefixes': _seedStaffSearchPrefixes(
      'Brian Kimani',
      'brian@devcorner.test',
    ),
  },
  'pending-dev': <String, Object?>{
    'uid': 'pending-dev',
    'email': 'newhire@devcorner.test',
    'name': 'Faith Njeri',
    'phone': '+254700100204',
    'role': 'cashier',
    'status': 'pending',
    'invitationStatus': 'pending',
    'searchPrefixes': _seedStaffSearchPrefixes(
      'Faith Njeri',
      'newhire@devcorner.test',
    ),
  },
};

List<String> _seedStaffSearchPrefixes(String name, String email) {
  final values = <String>{};
  final sources = <String>[
    name.toLowerCase(),
    ...name.toLowerCase().split(RegExp(r'\s+')),
    email.toLowerCase(),
    ...email.toLowerCase().split(RegExp(r'[@.]')),
  ];
  for (final source in sources) {
    for (var length = 2; length <= source.length && length <= 120; length++) {
      values.add(source.substring(0, length));
    }
  }
  final sorted = values.toList()..sort();
  return sorted;
}

/// Every staff member's display name, for the surfaces that resolve an actor
/// UID to a person.
Map<String, String> seedStaffNames() => <String, String>{
  for (final entry in seedStaff().entries)
    entry.key: entry.value['name']! as String,
};

// ---------------------------------------------------------------------------
// Operational records
// ---------------------------------------------------------------------------

Map<String, Map<String, Object?>> seedSales() {
  final businessDate = seedBusinessDate();

  /// The figures are derived from the lines rather than stated beside them.
  ///
  /// The sale read model refuses a document whose subtotal does not equal the
  /// sum of its lines, and fails the whole page closed when it does - so a
  /// hand-written total that is out by one discount makes every sales surface
  /// render "could not be loaded" instead of a sale.
  Map<String, Object?> sale({
    required int sequence,
    required String soldById,
    required List<Map<String, Object?>> items,
    int discountMinor = 0,
    String shiftId = 'shift-morning',
  }) {
    var subtotalMinor = 0;
    for (final line in items) {
      subtotalMinor += line['lineTotalMinor']! as int;
    }
    final totalMinor = subtotalMinor - discountMinor;
    return <String, Object?>{
      'checkoutId': 'co-$sequence',
      'tenantId': seedTenantId,
      'soldById': soldById,
      'payloadHash': seedPayloadHash,
      'payloadSchemaVersion': 2,
      'currency': seedCurrency,
      'businessDate': businessDate,
      'clientCreatedAtMs': 1785484800000 + sequence * 60000,
      'shiftId': shiftId,
      'deviceId': seedDeviceId,
      'receiptNumber': formatCheckoutReceiptNumber(
        deviceId: seedDeviceId,
        businessDate: businessDate,
        sequence: sequence,
      ),
      'receiptSequence': sequence,
      'tender': 'cash',
      'items': items,
      'subtotalMinor': subtotalMinor,
      'subtotal': subtotalMinor / 100,
      'discountMinor': discountMinor,
      'discount': discountMinor / 100,
      'totalMinor': totalMinor,
      'total': totalMinor / 100,
      'createdAt': seedTimestamp(hour: 8 + sequence),
    };
  }

  Map<String, Object?> line({
    required String productId,
    required String name,
    required int quantity,
    required int unitPriceMinor,
    int? unitCostMinor,
  }) => <String, Object?>{
    'productId': productId,
    'name': name,
    'quantity': quantity,
    'unitPriceMinor': unitPriceMinor,
    if (unitCostMinor != null) 'unitCostMinor': unitCostMinor,
    'lineTotalMinor': unitPriceMinor * quantity,
  };

  return <String, Map<String, Object?>>{
    'co-1': sale(
      sequence: 1,
      soldById: cashierUid,
      items: <Map<String, Object?>>[
        line(
          productId: 'pd-bread-white',
          name: 'White bread loaf',
          quantity: 2,
          unitPriceMinor: 6500,
          unitCostMinor: 4800,
        ),
        line(
          productId: 'pd-mandazi',
          name: 'Mandazi',
          quantity: 1,
          unitPriceMinor: 2000,
          unitCostMinor: 1100,
        ),
      ],
    ),
    'co-2': sale(
      sequence: 2,
      soldById: cashierUid,
      discountMinor: 500,
      items: <Map<String, Object?>>[
        line(
          productId: 'pd-bar-soap-blue',
          name: 'Bar soap - blue',
          quantity: 2,
          unitPriceMinor: 14500,
          unitCostMinor: 11200,
        ),
      ],
    ),
    // The evening shift's one sale. Its shift and its seller have to agree:
    // the shift sales read model refuses the whole page when one sale names a
    // seller the shift does not belong to.
    'co-3': sale(
      sequence: 3,
      soldById: managerUid,
      shiftId: 'shift-evening',
      items: <Map<String, Object?>>[
        line(
          productId: 'pd-soda-300',
          name: 'Soda 300ml',
          quantity: 2,
          unitPriceMinor: 5000,
          unitCostMinor: 3400,
        ),
        line(
          productId: 'pd-water-1l',
          name: 'Water 1L',
          quantity: 1,
          unitPriceMinor: 8000,
          unitCostMinor: 6200,
        ),
      ],
    ),
  };
}

Map<String, Map<String, Object?>>
seedShifts() => <String, Map<String, Object?>>{
  'shift-evening': <String, Object?>{
    'shiftId': 'shift-evening',
    'tenantId': seedTenantId,
    'staffId': managerUid,
    'deviceId': seedDeviceId,
    'businessDate': seedBusinessDate(),
    'status': 'open',
    'startTime': seedTimestamp(hour: 14),
    'totalSalesMinor': 18000,
    'totalSales': 180.0,
    'transactionCount': 1,
  },
  'shift-morning': <String, Object?>{
    'shiftId': 'shift-morning',
    'tenantId': seedTenantId,
    'staffId': cashierUid,
    'deviceId': seedDeviceId,
    'businessDate': seedBusinessDate(),
    'status': 'closed',
    'startTime': seedTimestamp(hour: 6),
    'endTime': seedTimestamp(hour: 13, minute: 45),
    'closingCashMinor': 44000,
    'closingCash': 440.0,
    'totalSalesMinor': 44000,
    'totalSales': 440.0,
    'transactionCount': 2,
  },
  // Owned by the manager on purpose: the shift history route opens on "My
  // shifts", so the session reading it needs a closed shift of its own before
  // the page has anything to show.
  'shift-yesterday': <String, Object?>{
    'shiftId': 'shift-yesterday',
    'tenantId': seedTenantId,
    'staffId': managerUid,
    'deviceId': seedDeviceId,
    'businessDate': seedBusinessDate(1),
    'status': 'closed',
    'startTime': seedTimestamp(daysAgo: 1, hour: 6),
    'endTime': seedTimestamp(daysAgo: 1, hour: 18),
    'closingCashMinor': 125000,
    'closingCash': 1250.0,
    'totalSalesMinor': 98750,
    'totalSales': 987.5,
    'transactionCount': 9,
    'summaryAmendmentId': 'sm_a1b2c3',
    'summaryAmendedGeneration': 'generation-one',
    'summaryAmendmentCount': 1,
    'summaryAmendedAt': seedTimestamp(daysAgo: 1, hour: 19),
  },
};

Map<String, Map<String, Object?>> seedReturns() =>
    <String, Map<String, Object?>>{
      'ret-1': <String, Object?>{
        'returnId': 'ret-1',
        'tenantId': seedTenantId,
        'saleId': 'co-1',
        'createdBy': cashierUid,
        'status': 'pending',
        'reason': 'Loaf was stale',
        'itemsReturned': <Object?>[
          <String, Object?>{
            'productId': 'pd-bread-white',
            'productName': 'White bread loaf',
            'quantity': 1,
          },
        ],
        'createdAt': seedTimestamp(hour: 11),
      },
      'ret-2': <String, Object?>{
        'returnId': 'ret-2',
        'tenantId': seedTenantId,
        'saleId': 'co-2',
        'createdBy': cashierUid,
        'status': 'verified',
        'reason': 'Wrong scent sold',
        'itemsReturned': <Object?>[
          <String, Object?>{
            'productId': 'pd-bar-soap-blue',
            'productName': 'Bar soap - blue',
            'quantity': 1,
          },
        ],
        'createdAt': seedTimestamp(daysAgo: 1, hour: 15),
        'verified': true,
        'verifiedBy': managerUid,
        'verifiedAt': seedTimestamp(hour: 8),
        'stockRestored': true,
        'stockRestoredAt': seedTimestamp(hour: 8),
        'stockRestorationId': 'rv_a1b2c3',
      },
    };

Map<String, Map<String, Object?>> seedStockAdjustments() =>
    <String, Map<String, Object?>>{
      'sa_000001': <String, Object?>{
        'tenantId': seedTenantId,
        'productId': 'pd-milk-500',
        'sourceType': 'manual_adjustment',
        'adjustmentType': 'damage',
        'quantityDelta': -3,
        'previousQuantity': 10,
        'quantityAfter': 7,
        'reason': 'Cartons split in the crate',
        'actorUid': managerUid,
        'requestId': 'adjust-stock-a1b2c3d4',
        'createdAt': seedTimestamp(daysAgo: 2, hour: 9),
      },
      'sa_000002': <String, Object?>{
        'tenantId': seedTenantId,
        'productId': 'pd-bread-white',
        'sourceType': 'manual_adjustment',
        'adjustmentType': 'restock',
        'quantityDelta': 24,
        'previousQuantity': 16,
        'quantityAfter': 40,
        'reason': 'Morning delivery received',
        'actorUid': ownerUid,
        'requestId': 'adjust-stock-b2c3d4e5',
        'createdAt': seedTimestamp(daysAgo: 1, hour: 7),
      },
      'sa_000003': <String, Object?>{
        'tenantId': seedTenantId,
        'productId': 'pd-charcoal-2kg',
        'sourceType': 'manual_adjustment',
        'adjustmentType': 'stock_take',
        'quantityDelta': -2,
        'previousQuantity': 14,
        'quantityAfter': 12,
        'reason': 'Counted at close of month',
        'actorUid': adminUid,
        'requestId': 'adjust-stock-c3d4e5f6',
        'createdAt': seedTimestamp(hour: 10),
      },
    };

/// The per-product ledger, keyed by full document path because a collection
/// group is ordered by the whole path rather than by a leaf ID.
Map<String, Map<String, Object?>> seedStockMovements() {
  /// **`adjustmentType` and `sourceId` are optional, and that is what the
  /// server actually writes.** `adjustStock` records a typed category and no
  /// source; a reconciled sale records the sale it came from and no category.
  /// This helper used to require the category on every movement, so the sale
  /// below carried `adjustmentType: 'sale'` - which was invisible while a row
  /// was four unlabelled lines and became a column reading "Adjustment type:
  /// sale" the moment §4.3's table drew one. A fixture where every record fills
  /// every column also proves nothing about the empty cell §4.3 promises.
  Map<String, Object?> movement({
    required String productId,
    required String movementId,
    required String sourceType,
    required int quantityDelta,
    required int previousQuantity,
    required String actorUid,
    String? adjustmentType,
    String? sourceId,
    String? reason,
    int daysAgo = 0,
    int hour = 9,
  }) => <String, Object?>{
    'movementId': movementId,
    'tenantId': seedTenantId,
    'productId': productId,
    'sourceType': sourceType,
    if (adjustmentType != null) 'adjustmentType': adjustmentType,
    if (sourceId != null) 'sourceId': sourceId,
    'quantityDelta': quantityDelta,
    'previousQuantity': previousQuantity,
    'quantityAfter': previousQuantity + quantityDelta,
    if (reason != null) 'reason': reason,
    'actorUid': actorUid,
    'recordedAt': seedTimestamp(daysAgo: daysAgo, hour: hour),
  };

  return <String, Map<String, Object?>>{
    'tenants/$seedTenantId/products/pd-bread-white/stock_movements/mv_000001':
        movement(
          productId: 'pd-bread-white',
          movementId: 'mv_000001',
          sourceType: 'opening_balance',
          adjustmentType: 'restock',
          quantityDelta: 16,
          previousQuantity: 0,
          actorUid: ownerUid,
          reason: 'Opening stock recorded at creation',
          daysAgo: 3,
          hour: 8,
        ),
    'tenants/$seedTenantId/products/pd-bread-white/stock_movements/mv_000002':
        movement(
          productId: 'pd-bread-white',
          movementId: 'mv_000002',
          sourceType: 'manual_adjustment',
          adjustmentType: 'restock',
          quantityDelta: 24,
          previousQuantity: 16,
          actorUid: ownerUid,
          reason: 'Morning delivery received',
          daysAgo: 1,
          hour: 7,
        ),
    'tenants/$seedTenantId/products/pd-milk-500/stock_movements/mv_000003':
        movement(
          productId: 'pd-milk-500',
          movementId: 'mv_000003',
          sourceType: 'manual_adjustment',
          adjustmentType: 'damage',
          quantityDelta: -3,
          previousQuantity: 10,
          actorUid: managerUid,
          reason: 'Cartons split in the crate',
          daysAgo: 2,
          hour: 9,
        ),
    'tenants/$seedTenantId/products/pd-soda-300/stock_movements/mv_000004':
        movement(
          productId: 'pd-soda-300',
          movementId: 'mv_000004',
          sourceType: 'sale',
          sourceId: 'co-1',
          quantityDelta: -2,
          previousQuantity: 98,
          actorUid: cashierUid,
          hour: 11,
        ),
  };
}

Map<String, Map<String, Object?>> seedAuditLogs() =>
    <String, Map<String, Object?>>{
      'aud_000001': <String, Object?>{
        'tenantId': seedTenantId,
        'eventType': 'staff_invited',
        'actorUid': adminUid,
        'targetUid': 'pending-dev',
        'requestId': 'invite-staff-a1b2c3d4',
        'role': 'cashier',
        'createdAt': seedTimestamp(daysAgo: 1, hour: 11),
      },
      'aud_000002': <String, Object?>{
        'tenantId': seedTenantId,
        'eventType': 'tenant_lifecycle_changed',
        'fromStatus': 'pending',
        'toStatus': 'active',
        'actorType': 'platform_admin',
        'fanoutOperationId': 'op-000123',
        'createdAt': seedTimestamp(daysAgo: 3, hour: 14),
      },
      'aud_000003': <String, Object?>{
        'tenantId': seedTenantId,
        'eventType': 'staff_updated',
        'actorUid': ownerUid,
        'targetUid': managerUid,
        'requestId': 'update-staff-d4e5f6a7',
        'role': 'manager',
        'createdAt': seedTimestamp(hour: 9),
      },
      'aud_000004': <String, Object?>{
        'tenantId': seedTenantId,
        'eventType': 'stock_adjusted',
        'actorUid': managerUid,
        'requestId': 'adjust-stock-a1b2c3d4',
        'createdAt': seedTimestamp(daysAgo: 2, hour: 9),
      },
    };

Map<String, Object?> seedDailyMetrics({
  required String businessDate,
  double sales = 910.0,
  double profit = 274.0,
  int transactions = 3,
  int shiftCount = 2,
  int incompleteCostLineCount = 0,
}) => <String, Object?>{
  'tenantId': seedTenantId,
  'businessDate': businessDate,
  'sales': sales,
  'profit': profit,
  'transactions': transactions,
  'transactionCount': transactions,
  'shiftCount': shiftCount,
  'incompleteCostLineCount': incompleteCostLineCount,
  'metricGeneration': 'gen-000418',
  'sourceDirtyRevision': 3,
  'regeneratedAt': seedTimestamp(hour: 2, minute: 30),
};

/// One business day as the reconciliation intake records it.
///
/// [invalidLineCount] is a parameter because **the day page's unusable-lines
/// branch had never been photographed**: the seeded day has always had a clean
/// intake, so the second tile in its `StatRow` - and the sentence under the row
/// saying what those lines cost - existed only in a widget test. It is the same
/// "a fixture that hides the case the component exists for" trap the stock
/// family recorded and the reconciliation sweep hit again.
Map<String, Object?> seedReconciliationIntake({
  required String businessDate,
  String status = 'clean',
  int invalidLineCount = 0,
}) => <String, Object?>{
  'tenantId': seedTenantId,
  'businessDate': businessDate,
  'status': status,
  'revision': 3,
  'processedRevision': 3,
  'saleReceiptCount': 3,
  'invalidLineCount': invalidLineCount,
  'metricGeneration': 'gen-000418',
  'lastReceiptAt': seedTimestamp(hour: 13),
  'processedAt': seedTimestamp(hour: 2, minute: 30),
};

/// One of each difference reconciliation can find and not resolve.
Map<String, Map<String, Object?>> seedReconciliationAnomalies() =>
    <String, Map<String, Object?>>{
      // **A kind that carries prose *and* a figure**, which is the mixed case
      // step 8 created on this screen and which nothing photographed: the three
      // seeded differences were one pure-figure record, one figure-and-sentence
      // record, and one of each. A broken chain states its expected quantity as
      // the thing that cannot be trusted, and keeps a paragraph saying why that
      // is not a quantity disagreement. It is filed against the one seeded
      // product that already carries a difference, so `21b-product-stock-
      // differences` photographs it too.
      'chain_d4e5f6': <String, Object?>{
        'tenantId': seedTenantId,
        'productId': 'pd-milk-500',
        'jobId': 'rj_000001',
        'anomalyType': 'checkpoint_chain_invalid',
        'expectedQuantity': 10,
        'observedQuantity': 10,
        'variance': 0,
        'createdAt': seedTimestamp(hour: 2, minute: 30),
      },
      'sale_a1b2c3': <String, Object?>{
        'tenantId': seedTenantId,
        'sourceType': 'sale',
        'sourceId': 'co-1',
        'anomalyType': 'invalid_sale_lines',
        'invalidLineCount': 2,
        'createdAt': seedTimestamp(hour: 2, minute: 30),
      },
      'shift_b2c3d4': <String, Object?>{
        'tenantId': seedTenantId,
        'shiftId': 'shift-yesterday',
        'jobId': 'rj_000001',
        'anomalyType': 'shift_variance',
        'salesVariance': -12.5,
        'transactionVariance': 2,
        'createdAt': seedTimestamp(hour: 2, minute: 30),
      },
      'stock_c3d4e5': <String, Object?>{
        'tenantId': seedTenantId,
        'productId': 'pd-milk-500',
        'jobId': 'rj_000001',
        'anomalyType': 'stock_variance',
        'expectedQuantity': 10,
        'observedQuantity': 7,
        'variance': -3,
        'createdAt': seedTimestamp(hour: 2, minute: 30),
      },
    };

Map<String, Map<String, Object?>> seedShiftAmendments() =>
    <String, Map<String, Object?>>{
      'sm_a1b2c3': <String, Object?>{
        'amendmentId': 'sm_a1b2c3',
        'tenantId': seedTenantId,
        'shiftId': 'shift-yesterday',
        'staffId': managerUid,
        'businessDate': seedBusinessDate(1),
        'sourceType': 'reconciliation_shift_variance',
        'expectationId': 'exp-000117',
        'expectationGeneration': 'generation-one',
        'previousTotalSalesMinor': 98750,
        'previousTransactionCount': 9,
        'previousRepresentationsAgreed': true,
        'totalSalesMinor': 98250,
        'transactionCount': 9,
        'salesVarianceMinor': 500,
        'transactionVariance': 0,
        'clearedAnomalyId': null,
        'mutatesCountedCash': false,
        'reason': 'A late sale arrived after the shift closed',
        'actorUid': adminUid,
        'requestId': 'amend-shift-a1b2c3d4',
        'createdAt': seedTimestamp(daysAgo: 1, hour: 19),
      },
    };

// ---------------------------------------------------------------------------
// Readers
// ---------------------------------------------------------------------------

/// Serves documents, bounded collection pages, and collection-group pages out
/// of plain maps, honouring the exact cursor, bound, ordering, and equality
/// filters the guarded repositories construct.
final class FakeTenantReader
    implements
        TenantDataReader,
        TenantCollectionGroupReader,
        TenantStaffDirectoryQueryReader,
        TenantSalesHistoryQueryReader {
  FakeTenantReader({
    Map<String, Map<String, Object?>> documents =
        const <String, Map<String, Object?>>{},
    Map<String, Map<String, Map<String, Object?>>> collections =
        const <String, Map<String, Map<String, Object?>>>{},
    Map<String, Map<String, Map<String, Object?>>> groups =
        const <String, Map<String, Map<String, Object?>>>{},
  }) : documents = Map<String, Map<String, Object?>>.of(documents),
       collections = <String, Map<String, Map<String, Object?>>>{
         for (final entry in collections.entries)
           entry.key: Map<String, Map<String, Object?>>.of(entry.value),
       },
       groups = <String, Map<String, Map<String, Object?>>>{
         for (final entry in groups.entries)
           entry.key: Map<String, Map<String, Object?>>.of(entry.value),
       };

  /// The whole seeded business, which is what most screens want.
  factory FakeTenantReader.business({
    Map<String, Map<String, Object?>> extraDocuments =
        const <String, Map<String, Object?>>{},
  }) {
    const root = 'tenants/$seedTenantId';
    final today = seedBusinessDate();
    return FakeTenantReader(
      documents: <String, Map<String, Object?>>{
        root: <String, Object?>{
          'tenantId': seedTenantId,
          'name': seedTenantName,
          'slug': seedTenantSlug,
          'status': 'active',
          'ownerUid': ownerUid,
        },
        '$root/configuration/checkout': <String, Object?>{
          'currency': seedCurrency,
        },
        '$root/configuration/branding': <String, Object?>{
          'companyName': seedTenantName,
          'slogan': 'Everything the corner needs',
        },
        for (var offset = 0; offset < 7; offset++)
          '$root/daily_metrics/${seedBusinessDate(offset)}': seedDailyMetrics(
            businessDate: seedBusinessDate(offset),
            sales: offset == 0 ? 910.0 : 1180.0 + offset * 45,
            profit: offset == 0 ? 274.0 : 331.0 + offset * 12,
            transactions: offset == 0 ? 3 : 9 + offset,
            incompleteCostLineCount: offset > 3 ? 4 + offset : 0,
          ),
        '$root/reconciliation_dirty_days/$today': seedReconciliationIntake(
          businessDate: today,
        ),
        // Also by exact path: one run is read as a document by the route that
        // explains a single run, and as a page by the route that lists them.
        for (final entry in seedReconciliationJobs().entries)
          '$root/reconciliation_jobs/${entry.key}': entry.value,
        for (final entry in seedStaff().entries)
          '$root/staff/${entry.key}': entry.value,
        for (final entry in seedProducts.entries)
          '$root/products/${entry.key}': entry.value,
        ...extraDocuments,
      },
      collections: <String, Map<String, Map<String, Object?>>>{
        '$root/categories': seedCategories,
        '$root/products': seedProducts,
        '$root/staff': seedStaff(),
        '$root/sales': seedSales(),
        '$root/shifts': seedShifts(),
        '$root/returns': seedReturns(),
        '$root/stock_adjustments': seedStockAdjustments(),
        '$root/audit_logs': seedAuditLogs(),
        '$root/shift_amendments': seedShiftAmendments(),
        '$root/reconciliation_jobs': seedReconciliationJobs(),
        '$root/reconciliation_anomalies': seedReconciliationAnomalies(),
        for (final path in seedStockMovements().keys)
          _collectionOf(path): <String, Map<String, Object?>>{
            for (final entry in seedStockMovements().entries)
              if (_collectionOf(entry.key) == _collectionOf(path))
                _idOf(entry.key): entry.value,
          },
      },
      groups: <String, Map<String, Map<String, Object?>>>{
        'stock_movements': seedStockMovements(),
      },
    );
  }

  final Map<String, Map<String, Object?>> documents;
  final Map<String, Map<String, Map<String, Object?>>> collections;
  final Map<String, Map<String, Map<String, Object?>>> groups;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final data = documents[path];
    return data == null ? null : TenantDocumentSnapshot(path: path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    final documents = collections[query.collectionPath];
    if (documents == null) return const <TenantQueryDocumentSnapshot>[];
    final ids = documents.keys.toList()..sort();
    if (query.descending) {
      final reversed = ids.reversed.toList();
      ids
        ..clear()
        ..addAll(reversed);
    }
    final results = <TenantQueryDocumentSnapshot>[];
    for (final id in ids) {
      final cursor = query.startAfterDocumentId;
      if (cursor != null) {
        final passed = query.descending
            ? id.compareTo(cursor) < 0
            : id.compareTo(cursor) > 0;
        if (!passed) continue;
      }
      final data = documents[id]!;
      if (!query.equalityFilters.entries.every(
        (filter) => data[filter.key] == filter.value,
      )) {
        continue;
      }
      results.add(
        TenantQueryDocumentSnapshot(
          path: '${query.collectionPath}/$id',
          data: data,
        ),
      );
      if (results.length >= query.limit) break;
    }
    return results;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionGroupPage(
    TenantCollectionGroupQuery query,
  ) async {
    final documents = groups[query.collectionId];
    if (documents == null) return const <TenantQueryDocumentSnapshot>[];
    final paths = documents.keys.toList()..sort();
    final results = <TenantQueryDocumentSnapshot>[];
    for (final path in paths) {
      final cursor = query.startAfterDocumentPath;
      if (cursor != null && path.compareTo(cursor) <= 0) continue;
      final data = documents[path]!;
      if (!query.equalityFilters.entries.every(
        (filter) => data[filter.key] == filter.value,
      )) {
        continue;
      }
      results.add(TenantQueryDocumentSnapshot(path: path, data: data));
      if (results.length >= query.limit) break;
    }
    return results;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantStaff(
    TenantStaffDirectoryQuery query,
  ) async {
    final source = collections[query.collectionPath];
    if (source == null) return const <TenantQueryDocumentSnapshot>[];
    final ids = source.keys.toList()..sort();
    final results = <TenantQueryDocumentSnapshot>[];
    for (final id in ids) {
      if (query.startAfter != null &&
          id.compareTo(query.startAfter!.documentId) <= 0) {
        continue;
      }
      final data = source[id]!;
      if (query.role != null && data['role'] != query.role ||
          query.status != null && data['status'] != query.status) {
        continue;
      }
      if (query.searchPrefix != null) {
        final prefixes = data['searchPrefixes'];
        if (prefixes is! List<Object?> ||
            !prefixes.contains(query.searchPrefix)) {
          continue;
        }
      }
      results.add(
        TenantQueryDocumentSnapshot(
          path: '${query.collectionPath}/$id',
          data: data,
        ),
      );
      if (results.length >= query.limit) break;
    }
    return results;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantSalesHistory(
    TenantSalesHistoryQuery query,
  ) async {
    final source = collections[query.collectionPath];
    if (source == null) return const <TenantQueryDocumentSnapshot>[];
    final entries =
        source.entries.where((entry) {
          final businessDate = entry.value['businessDate'];
          return businessDate is String &&
              businessDate.compareTo(query.startBusinessDate) >= 0 &&
              businessDate.compareTo(query.endBusinessDate) <= 0 &&
              (query.soldById == null ||
                  entry.value['soldById'] == query.soldById);
        }).toList()..sort((left, right) {
          final dateOrder = (right.value['businessDate']! as String).compareTo(
            left.value['businessDate']! as String,
          );
          return dateOrder != 0 ? dateOrder : right.key.compareTo(left.key);
        });
    final results = <TenantQueryDocumentSnapshot>[];
    for (final entry in entries) {
      final position = query.startAfter;
      if (position != null) {
        final businessDate = entry.value['businessDate']! as String;
        final isAfter =
            businessDate.compareTo(position.businessDate) < 0 ||
            businessDate == position.businessDate &&
                entry.key.compareTo(position.documentId) < 0;
        if (!isAfter) continue;
      }
      results.add(
        TenantQueryDocumentSnapshot(
          path: '${query.collectionPath}/${entry.key}',
          data: entry.value,
        ),
      );
      if (results.length >= query.limit) break;
    }
    return results;
  }
}

Map<String, Map<String, Object?>> seedReconciliationJobs() =>
    <String, Map<String, Object?>>{
      'rj_000001': <String, Object?>{
        'tenantId': seedTenantId,
        'source': 'sale_trigger',
        'sourceKey': '1785540000000',
        'mode': 'incremental',
        'localDate': seedBusinessDate(),
        'requestedBy': 'system:sale_trigger',
        'status': 'completed',
        'phase': 'finalize',
        'attemptCount': 1,
        'consecutiveFailureCount': 0,
        'rerunRequested': false,
        'metricsProcessed': 1,
        'productsProcessed': 7,
        'stockVarianceCount': 1,
        'shiftsProcessed': 2,
        'shiftVarianceCount': 1,
        'completedAt': seedTimestamp(hour: 2, minute: 31),
        'updatedAt': seedTimestamp(hour: 2, minute: 31),
      },
      'rj_000002': <String, Object?>{
        'tenantId': seedTenantId,
        'source': 'operator_request',
        'sourceKey': 'reconcile-a1b2c3d4',
        'mode': 'full',
        'localDate': seedBusinessDate(1),
        'requestedBy': adminUid,
        'status': 'completed',
        'phase': 'finalize',
        'attemptCount': 1,
        'consecutiveFailureCount': 0,
        'rerunRequested': false,
        'metricsProcessed': 1,
        'productsProcessed': 7,
        'stockVarianceCount': 0,
        'shiftsProcessed': 1,
        'shiftVarianceCount': 0,
        'completedAt': seedTimestamp(daysAgo: 1, hour: 2, minute: 31),
        'updatedAt': seedTimestamp(daysAgo: 1, hour: 2, minute: 31),
      },
    };

String _collectionOf(String documentPath) {
  final segments = documentPath.split('/');
  return segments.sublist(0, segments.length - 1).join('/');
}

String _idOf(String documentPath) => documentPath.split('/').last;

// ---------------------------------------------------------------------------
// Callables
// ---------------------------------------------------------------------------

/// A callable that answers with a canned map and records nothing.
///
/// Every callable boundary in this app is `Future<Object?> call(Map)`, so one
/// class stands in for all of them. Screenshots do not press a button that
/// commits, so the answer only has to exist.
final class FakeCallable
    implements
        AdjustStockCallable,
        AmendShiftSummaryCallable,
        ImportProductsCallable,
        RequestReconciliationCallable,
        SalesTotalsCallable,
        UpdateProductCallable,
        UpdateProductsCallable,
        VerifyReturnCallable {
  FakeCallable([this.answer = const <String, Object?>{}]);

  final Map<String, Object?> answer;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(payload);
    return answer;
  }
}

/// `getSalesComparison`, answering a **different** total per business day.
///
/// **[FakeCallable] cannot photograph the home's trend line and that is why
/// this exists.** That fake answers every call with one fixed map, so today
/// and the day before come back identical and the greeting can only ever draw
/// *level with yesterday* - the one state of the three that says least. This
/// one keys its answer off `previousStartDate`, which is the only thing that
/// differs between the home's two requests, so a capture shows a real rise or
/// fall with its arrow and its percentage.
final class FakeSalesComparisonCallable implements SalesTotalsCallable {
  FakeSalesComparisonCallable({
    required this.salesByBusinessDate,
    this.fallbackSales = 0,
  });

  /// Takings per `yyyy-MM-dd` business date, as the server would add them up.
  final Map<String, double> salesByBusinessDate;

  /// What a day nobody listed took. Zero is a real answer - a shop that was
  /// shut - and the greeting refuses to divide by it rather than printing an
  /// arbitrary 100%.
  final double fallbackSales;

  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(payload);
    final date = payload['previousStartDate'] as String?;
    final sales = salesByBusinessDate[date] ?? fallbackSales;
    // One transaction per 100 taken, so `transactions` and
    // `scannedTransactions` agree - the decoder refuses an answer whose counts
    // disagree with what it claims to have read.
    final transactions = sales == 0 ? 0 : (sales / 100).ceil();
    return <String, Object?>{
      'scannedTransactions': transactions,
      'previous': <String, Object?>{
        'transactions': transactions,
        'sales': sales,
        'profit': sales / 4,
        'incompleteCostLineCount': 0,
      },
    };
  }
}

/// `updateProducts`, answering the way the server does, with a mixed report.
///
/// **[FakeCallable] cannot photograph a bulk report and that is why this
/// exists.** The strict decoder reconciles the answer against the page it sent -
/// same business, same mode, one outcome per row in order, every acted-on row
/// coming back holding exactly the value requested - so an empty map produces a
/// refusal notice rather than a report, and no capture had ever put a row
/// outcome on screen.
///
/// It answers one row `unchanged` and one `failed` so a single picture carries
/// three of §2.1's five statuses at once. That is the point of it: a report that
/// is all one outcome would photograph the case the badge is least useful in.
final class FakeBulkCatalogCallable implements UpdateProductsCallable {
  FakeBulkCatalogCallable({this.unchangedAt = 1, this.failedAt = 2});

  /// Which row (zero-based within a page) already holds the value.
  final int unchangedAt;

  /// Which row the server refuses.
  final int failedAt;

  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(payload);
    final mode = payload['mode']! as String;
    final rows = (payload['rows']! as List).cast<Map<String, Object?>>();
    var unchanged = 0;
    var failed = 0;
    final outcomes = <Map<String, Object?>>[];
    for (var index = 0; index < rows.length; index++) {
      if (index == failedAt) {
        failed++;
        outcomes.add(<String, Object?>{
          'index': index,
          'productId': rows[index]['productId'],
          'status': 'failed',
          'code': 'failed-precondition',
          'message': 'This product was retired while the preview was open.',
        });
        continue;
      }
      if (index == unchangedAt) unchanged++;
      outcomes.add(_outcome(rows[index], index, mode));
    }
    return <String, Object?>{
      'batchId': 'pb_dev0001',
      'tenantId': payload['tenantId'],
      'mode': mode,
      'rowCount': rows.length,
      'updatedCount': rows.length - unchanged - failed,
      'unchangedCount': unchanged,
      'failedCount': failed,
      'rows': outcomes,
    };
  }

  /// One acted-on row, holding the seeded product's own facts with the corrected
  /// field replaced - which is what the decoder checks rather than trusts.
  Map<String, Object?> _outcome(
    Map<String, Object?> row,
    int index,
    String mode,
  ) {
    final productId = row['productId']! as String;
    final field = row.keys.firstWhere((key) => key != 'productId');
    final value = row[field];
    final seeded = seedProducts[productId]!;
    final unchanged = index == unchangedAt;
    final price = field == 'price' ? value! as num : seeded['price']! as num;
    final num? cost = field == 'cost' ? value as num? : seeded['cost'] as num?;
    return <String, Object?>{
      'index': index,
      'productId': productId,
      'status': unchanged ? 'unchanged' : 'updated',
      'changedFields': unchanged ? const <String>[] : <String>[field],
      'updateId': mode == 'commit' && !unchanged ? 'pu_dev000$index' : null,
      'code': null,
      'message': null,
      'product': <String, Object?>{
        'name': seeded['name'],
        'sku': seeded['SKU'],
        'price': price.toDouble(),
        'priceMinor': (price * 100).round(),
        'cost': cost?.toDouble(),
        'costMinor': cost == null ? null : (cost * 100).round(),
        'categoryId': field == 'categoryId' ? value : seeded['categoryId'],
      },
    };
  }
}

/// The catalog write boundary, accepting every change.
///
/// It is supplied so the route draws its "add a product", "add a category", and
/// "retire" controls; a route built without a writer is deliberately read-only.
final class FakeCatalogWriter implements TenantCatalogWriter {
  @override
  Future<TenantCatalogWriteResult> createCategory(
    TenantCategoryCreateIntent intent,
  ) async => const TenantCatalogWriteResult.committed();

  @override
  Future<TenantCatalogWriteResult> createProduct(
    TenantProductCreateIntent intent,
  ) async => const TenantCatalogWriteResult.committed();

  @override
  Future<TenantCatalogWriteResult> renameCategory(
    TenantCategoryRenameIntent intent,
  ) async => const TenantCatalogWriteResult.committed();

  @override
  Future<TenantCatalogWriteResult> retireProduct(
    TenantProductRetireIntent intent,
  ) async => const TenantCatalogWriteResult.committed();
}

/// The checkout configuration write boundary, supplied for the same reason.
final class FakeCheckoutConfigurationWriter
    implements TenantCheckoutConfigurationWriter {
  @override
  Future<TenantCheckoutConfigurationWriteResult> publish(
    TenantCheckoutConfigurationUpdateIntent intent,
  ) async => const TenantCheckoutConfigurationWriteResult.committed();
}

/// The generic configuration-document write boundary, which the printer
/// settings route depends on. Committing is what makes the route draw its
/// *Save* control; a screenshot never reaches Firestore.
final class FakeConfigurationDocumentWriter
    implements TenantConfigurationDocumentWriter {
  @override
  Future<TenantConfigurationWriteResult> merge({
    required String path,
    required Map<String, Object?> data,
  }) async => const TenantConfigurationWriteResult.committed();
}

/// Both reconciliation actions, so the surfaces that offer them draw them.
TenantReconciliationActions fakeReconciliationActions() =>
    TenantReconciliationActions(
      requestCallable: FakeCallable(),
      amendShiftSummaryCallable: FakeCallable(),
    );

/// The period totals `getSalesComparison` returns, complete enough that the
/// profit statement and the tender split both render.
Map<String, Object?> seedSalesTotalsResponse() => <String, Object?>{
  'previous': <String, Object?>{
    'sales': 6420.5,
    'profit': 1937.25,
    'transactions': 48,
    'incompleteCostLineCount': 0,
  },
  'scannedTransactions': 48,
  'byTender': <String, Object?>{
    'cash': <String, Object?>{'sales': 3810.25, 'transactions': 29},
    'mpesa': <String, Object?>{'sales': 1980.0, 'transactions': 13},
    'card': <String, Object?>{'sales': 540.25, 'transactions': 5},
    'unrecorded': <String, Object?>{'sales': 90.0, 'transactions': 1},
    'other': <String, Object?>{'sales': 0.0, 'transactions': 0},
  },
};

/// The offline catalog the till prices from.
final class FakeCatalogSource implements CheckoutCatalogSource {
  FakeCatalogSource({this.snapshot});

  final CheckoutCatalogSnapshot? snapshot;

  static CheckoutCatalogSnapshot seeded({String uid = cashierUid}) =>
      CheckoutCatalogSnapshot.forTesting(
        uid: uid,
        tenantId: seedTenantId,
        configuration: TenantCheckoutConfiguration(currency: seedCurrency),
        categories: seedCatalogCategories(),
        products: seedCatalogProducts(),
      );

  @override
  Future<CheckoutCatalogSnapshot?> read({
    required String uid,
    required String tenantId,
  }) async => snapshot ?? seeded(uid: uid);
}

// ---------------------------------------------------------------------------
// Routing
// ---------------------------------------------------------------------------

const RootRoutingProfile seedTenantProfile = RootRoutingProfile(
  accountType: RootAccountType.tenantUser,
  globalStatus: 'active',
);

const RootRoutingProfile seedPlatformProfile = RootRoutingProfile(
  accountType: RootAccountType.platformAdmin,
  globalStatus: 'active',
);

/// Answers bootstrap out of a fixed membership list, so the real routing shell
/// can be driven to any of its phases without Firebase.
final class FakeRoutingGateway
    implements TenantDirectoryGateway, RootRoutingGateway {
  FakeRoutingGateway({
    required this.memberships,
    this.profile = seedTenantProfile,
    this.rootFailures = 0,
  });

  final List<TenantMembership> memberships;
  final RootRoutingProfile profile;

  /// How many bootstrap attempts throw before one succeeds, which is how the
  /// failure route is reached.
  int rootFailures;

  @override
  Future<RootRoutingProfile> getRootRoutingProfile(String uid) async {
    if (rootFailures > 0) {
      rootFailures--;
      throw StateError('The business directory did not answer.');
    }
    return profile;
  }

  @override
  Future<TenantListPage> listMyTenants({
    required int pageSize,
    String? cursor,
  }) async =>
      TenantListPage(items: memberships, nextCursor: null, hasMore: false);
}

final class FakeSelectionStore implements TenantSelectionStore {
  FakeSelectionStore([this.value]);

  String? value;

  @override
  Future<String?> readLastSelectedTenant(String uid) async => value;

  @override
  Future<void> writeLastSelectedTenant(String uid, String tenantId) async =>
      value = tenantId;
}

TenantBootstrapService fakeBootstrapService(FakeRoutingGateway gateway) =>
    TenantBootstrapService(
      rootGateway: gateway,
      directory: TenantDirectory(gateway),
      selectionStore: FakeSelectionStore(),
    );

/// The callables the routing shell offers, all answering successfully.
final class FakeTenancyCallable
    implements
        AcceptTenantInvitationCallable,
        AcceptVisibleTenantInvitationCallable,
        RequestTenantCallable,
        SendAccountVerificationCallable,
        SetDefaultTenantCallable,
        SetGlobalUserStatusCallable,
        SetTenantLifecycleCallable {
  FakeTenancyCallable([
    this.answer = const <String, Object?>{'accepted': true},
  ]);

  final Map<String, Object?> answer;

  @override
  Future<Object?> call(Map<String, Object?> payload) async => answer;
}

/// The six staff-directory callables, all answering successfully.
final class FakeStaffCallable
    implements
        CancelTenantInvitationCallable,
        InviteStaffCallable,
        ReplacePendingStaffEmailCallable,
        ResendStaffInvitationCallable,
        SetStaffStatusCallable,
        UpdateStaffUserCallable {
  @override
  Future<Object?> call(Map<String, Object?> payload) async => <String, Object?>{
    'tenantId': seedTenantId,
    ...payload,
  };
}

/// A return writer a screenshot never reaches: the landing route passes the
/// actions down to routes that are opened separately.
final class FakeReturnWriter implements TenantReturnWriter {
  @override
  Future<TenantReturnWriteResult> recordReturn(
    TenantReturnCreateIntent intent,
  ) async => throw UnimplementedError('A screenshot records no return.');
}

/// The return actions a read-only surface is given so its management controls
/// are drawn.
TenantReturnActions fakeReturnActions() => TenantReturnActions(
  writer: FakeReturnWriter(),
  verifyCallable: FakeCallable(),
);

final class FakeEmailDeliveryStatusCallable
    implements EmailDeliveryStatusCallable {
  @override
  Future<Object?> call() async => <String, Object?>{'suppressed': false};
}

// ---------------------------------------------------------------------------
// Platform administration
// ---------------------------------------------------------------------------

/// One data source behind all four platform tabs.
final class FakePlatformDataSource
    implements
        PlatformPendingTenantDataSource,
        PlatformLifecycleTenantDataSource,
        PlatformRejectedTenantDataSource,
        PlatformGlobalUserDataSource {
  static PlatformTenantDocument _tenant({
    required String id,
    required String name,
    required String status,
    int createdDay = 1,
    int updatedDay = 4,
  }) => PlatformTenantDocument(
    id: id,
    data: <String, Object?>{
      'name': name,
      'slug': id,
      'ownerUid': 'owner-$id',
      'status': status,
      'createdAt': DateTime.utc(2026, 8, createdDay),
      'updatedAt': DateTime.utc(2026, 8, updatedDay),
    },
  );

  static PlatformTenantDocument _owner(String id) => PlatformTenantDocument(
    id: 'owner-$id',
    data: <String, Object?>{
      'email': 'owner@$id.test',
      'displayName': 'Owner of $id',
      'accountType': 'tenant_user',
      'globalStatus': 'active',
    },
  );

  @override
  Future<List<PlatformTenantDocument>> loadPendingTenantDocuments({
    required int limit,
    PlatformPendingTenantCursor? cursor,
  }) async => cursor != null
      ? const <PlatformTenantDocument>[]
      : <PlatformTenantDocument>[
          _tenant(
            id: 'kilimani-grocers',
            name: 'Kilimani Grocers',
            status: 'pending',
          ),
          _tenant(
            id: 'ngong-road-kiosk',
            name: 'Ngong Road Kiosk',
            status: 'pending',
            createdDay: 3,
          ),
        ];

  @override
  Future<List<PlatformTenantDocument>> loadLifecycleTenantDocuments({
    required int limit,
    PlatformLifecycleTenantCursor? cursor,
  }) async => cursor != null
      ? const <PlatformTenantDocument>[]
      : <PlatformTenantDocument>[
          _tenant(id: seedTenantId, name: seedTenantName, status: 'active'),
          _tenant(
            id: 'westlands-mart',
            name: 'Westlands Mart',
            status: 'suspended',
            createdDay: 2,
          ),
        ];

  @override
  Future<List<PlatformTenantDocument>> loadRejectedTenantDocuments({
    required int limit,
    PlatformRejectedTenantCursor? cursor,
  }) async => cursor != null
      ? const <PlatformTenantDocument>[]
      : <PlatformTenantDocument>[
          _tenant(
            id: 'unverified-trader',
            name: 'Unverified Trader',
            status: 'rejected',
            createdDay: 2,
          ),
        ];

  @override
  Future<void> prepareExactReview(String uid) async {}

  @override
  Future<PlatformTenantDocument?> loadRootUser(String uid) async =>
      _owner(uid.startsWith('owner-') ? uid.substring(6) : seedTenantId);

  @override
  Future<List<PlatformCanonicalStaffDocument>> loadTargetStaffDocuments(
    String uid,
  ) async => <PlatformCanonicalStaffDocument>[
    PlatformCanonicalStaffDocument(
      tenantId: seedTenantId,
      id: uid,
      data: <String, Object?>{
        'uid': uid,
        'email': 'brian@devcorner.test',
        'name': 'Brian Kimani',
        'role': 'cashier',
        'status': 'active',
        'invitationStatus': 'accepted',
      },
    ),
  ];

  @override
  Future<List<PlatformTenantDocument>> loadOwnedTenantDocuments(
    String uid,
  ) async => <PlatformTenantDocument>[
    _tenant(id: seedTenantId, name: seedTenantName, status: 'active'),
  ];

  @override
  Future<PlatformTenantDocument?> loadTenant(String tenantId) async =>
      _tenant(id: tenantId, name: seedTenantName, status: 'active');

  @override
  Future<List<PlatformCanonicalStaffDocument>> loadAdministrativeStaffDocuments(
    String tenantId,
  ) async => <PlatformCanonicalStaffDocument>[
    PlatformCanonicalStaffDocument(
      tenantId: tenantId,
      id: ownerUid,
      data: <String, Object?>{
        'uid': ownerUid,
        'email': 'grace@devcorner.test',
        'name': 'Grace Wanjiru',
        'role': 'owner',
        'status': 'active',
        'invitationStatus': 'accepted',
      },
    ),
  ];
}

// ---------------------------------------------------------------------------
// Shift lifecycle
// ---------------------------------------------------------------------------

/// The shift documents this device wrote, held in memory.
///
/// The panel opens and closes a shift through the app's own writer, so the
/// behaviour a screenshot shows is the real lifecycle rather than a mock of it.
final class FakeShiftServer {
  final Map<String, Map<String, Object?>> shifts =
      <String, Map<String, Object?>>{};

  Future<void> create(String path, Map<String, Object?> data) async {
    shifts[path] = <String, Object?>{
      ...data,
      'startTime': seedTimestamp(hour: 6),
    };
  }

  Future<void> update(String path, Map<String, Object?> data) async {
    final current = shifts[path];
    if (current == null) throw StateError('No shift at $path.');
    shifts[path] = <String, Object?>{
      ...current,
      ...data,
      'endTime': seedTimestamp(hour: 18),
    };
  }

  /// A reader over the shifts above, joined to the seeded business so the
  /// history route behind the panel has records to list.
  TenantDataReader get reader => _FakeShiftReader(this);
}

final class _FakeShiftReader implements TenantDataReader {
  _FakeShiftReader(this._server) : _business = FakeTenantReader.business();

  final FakeShiftServer _server;
  final FakeTenantReader _business;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final live = _server.shifts[path];
    if (live != null) return TenantDocumentSnapshot(path: path, data: live);
    return _business.getDocument(path);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) => _business.getCollectionPage(query);
}

final class FakeSalesLedger implements ShiftSalesLedger {
  const FakeSalesLedger([this.summary = ShiftSalesSummary.empty]);

  final ShiftSalesSummary summary;

  @override
  Future<ShiftSalesSummary> summarize({
    required String uid,
    required String tenantId,
    required String shiftId,
  }) async => summary;
}

/// Builds the shift controller the landing panel drives, over an in-memory
/// Hive box the caller opened.
TenantShiftController fakeShiftController({
  required TenantSessionController sessions,
  required HiveTenantShiftState localState,
  required FakeShiftServer server,
  ShiftSalesSummary sales = ShiftSalesSummary.empty,
}) => TenantShiftController(
  sessionController: sessions,
  localState: localState,
  reader: server.reader,
  writer: FirebaseTenantShiftWriter.forTesting(
    create: server.create,
    update: server.update,
    isOnline: () async => true,
  ),
  salesLedger: FakeSalesLedger(sales),
  deviceId: seedDeviceId,
  isOnline: () async => true,
);

/// Opens the encrypted shift-state box in memory.
///
/// `bytes: Uint8List(0)` is what keeps every durable operation inside the
/// widget test's fake-async zone; a file-backed box would never complete there.
Future<HiveTenantShiftState> openMemoryShiftState() async {
  final box = await Hive.openBox<dynamic>(
    HiveTenantShiftState.boxName,
    encryptionCipher: HiveAesCipher(
      Uint8List.fromList(List<int>.filled(32, 7)),
    ),
    crashRecovery: false,
    bytes: Uint8List(0),
  );
  return HiveTenantShiftState.fromBox(box);
}

// ---------------------------------------------------------------------------
// Local checkout evidence
// ---------------------------------------------------------------------------

/// Stands in for the encrypted outbox's counts on the landing route.
final class FakeEvidenceSource implements CheckoutEvidenceSource {
  const FakeEvidenceSource([this.summary = const CheckoutEvidenceSummary()]);

  final CheckoutEvidenceSummary summary;

  @override
  Future<CheckoutEvidenceSummary> summarize(TenantSession session) async =>
      summary;
}

/// A draft sink that accepts every save, so the till renders its "saved"
/// confirmation rather than a refusal.
final class FakeDraftSink implements CheckoutDraftSink {
  FakeDraftSink({this.printFailure, this.refusalCode});

  final List<CheckoutDraftRequest> requests = <CheckoutDraftRequest>[];

  /// A `PrinterTransportCode` the saved sale comes back carrying, or null for
  /// a receipt that reached the printer.
  final String? printFailure;

  /// A `CheckoutDraftException` code every save throws, or null for a sink that
  /// keeps what it is given.
  ///
  /// **The one state of the till nothing photographed.** Hard rule 5 asks for a
  /// component's whole matrix in the harness, and the sale path's error branch -
  /// a sale that was *not* written - existed only in the widget tests. It is the
  /// branch ST-036 gets wrong, so it is the one a reviewer needs a picture of.
  final String? refusalCode;
  int _sequence = 0;

  @override
  Future<CheckoutSavedDraft> saveDraft(CheckoutDraftRequest request) async {
    if (refusalCode case final code?) {
      throw CheckoutDraftException(code);
    }
    requests.add(request);
    _sequence++;
    return CheckoutSavedDraft(
      checkoutId: 'co-screenshot-$_sequence',
      receiptNumber: formatCheckoutReceiptNumber(
        deviceId: seedDeviceId,
        businessDate: seedBusinessDate(),
        sequence: _sequence,
      ),
      receiptPrintFailure: printFailure,
    );
  }
}

/// Answers the catalog form's file picker with one deterministic photograph.
///
/// The bytes are the same picture `screenshotProductImage()` draws for the
/// catalog rows, so a capture of the chosen state and a capture of the saved
/// state show the same product rather than two unrelated pictures.
final class FakeProductImagePicker extends FilePicker {
  FakeProductImagePicker(this.bytes);

  final Uint8List bytes;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult(<PlatformFile>[
    PlatformFile(name: 'shelf.png', size: bytes.length, bytes: bytes),
  ]);
}

/// Accepts a product photograph and hands back an address, storing nothing.
final class FakeProductImageStore implements TenantProductImageStore {
  const FakeProductImageStore();

  @override
  Future<TenantProductImageUpload> upload({
    required String tenantId,
    required String productId,
    required TenantProductImageCandidate candidate,
  }) async => TenantProductImageUpload(
    url: Uri.parse(
      'https://storage.test/tenantProductImages/$tenantId/$productId/image.png',
    ),
    objectPath: 'tenantProductImages/$tenantId/$productId/image.png',
  );

  @override
  Future<void> removeOwned({
    required String tenantId,
    required String productId,
    required Uri imageUrl,
  }) async {}
}

/// Stands in for the background-removal service, in each of the three states
/// the catalog form draws it in.
///
/// [FakeBackgroundRemover.holding] never answers, which is how the *in flight*
/// capture is taken - that case is rendered with `settle: false`, because a
/// spinner never reaches a quiet frame.
final class FakeBackgroundRemover implements TenantProductBackgroundRemover {
  const FakeBackgroundRemover(this.cutOut) : failure = null, _holds = false;

  const FakeBackgroundRemover.refusing(this.failure)
    : cutOut = null,
      _holds = false;

  const FakeBackgroundRemover.holding()
    : cutOut = null,
      failure = null,
      _holds = true;

  final Uint8List? cutOut;
  final TenantBackgroundRemovalFailure? failure;
  final bool _holds;

  @override
  bool canRemoveInSession(TenantSession session) => true;

  @override
  Future<TenantProductImageCandidate> remove({
    required TenantSession session,
    required TenantProductImageCandidate candidate,
  }) {
    if (_holds) return Completer<TenantProductImageCandidate>().future;
    final refusal = failure;
    if (refusal != null) {
      return Future<TenantProductImageCandidate>.error(
        TenantBackgroundRemovalException(refusal),
      );
    }
    return Future<TenantProductImageCandidate>.value(
      TenantProductImageCandidate(
        bytes: cutOut!,
        fileName: cutOutFileName(candidate.fileName),
      ),
    );
  }
}
