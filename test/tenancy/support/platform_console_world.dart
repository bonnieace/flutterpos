/// The platform the console design draws (`docs/design/platform-console`),
/// as documents: Tuesday 20 October 2026, 09:40, 17 businesses and 212
/// accounts, every figure on the boards coming out of a query rather than a
/// literal.
library;

/// The moment the sample world is read at.
final DateTime platformConsoleNow = DateTime(2026, 10, 20, 9, 40);

/// The signed-in operator in the harness and the widget tests.
const String platformConsoleOperatorUid = 'platform-admin';

DateTime _at(int month, int day, [int hour = 10, int minute = 0]) =>
    DateTime(2026, month, day, hour, minute);

const List<String> _given = <String>[
  'Akinyi',
  'Baraka',
  'Chebet',
  'Dennis',
  'Faith',
  'Gitau',
  'Hassan',
  'Imani',
  'Juma',
  'Kerubo',
  'Linet',
  'Moraa',
  'Nafula',
  'Ouma',
  'Pendo',
  'Rehema',
  'Sifa',
  'Tabitha',
  'Wekesa',
  'Zawadi',
  'Atieno',
  'Brian',
  'Cynthia',
];

const List<String> _family = <String>[
  'Kiptoo',
  'Wanjala',
  'Mutua',
  'Nyambura',
  'Omondi',
  'Kariuki',
  'Njoroge',
  'Barasa',
  'Chepkoech',
  'Muthoni',
  'Ndungu',
  'Okello',
  'Wafula',
];

/// A name for the [index]th generated account, the same every run.
String _person(int index) =>
    '${_given[index % _given.length]} ${_family[(index * 7) % _family.length]}';

String _address(int index) {
  final name = _person(index).toLowerCase().replaceAll(' ', '.');
  return '$name$index@gmail.com';
}

Map<String, Map<String, Object?>> platformConsoleWorld() {
  final docs = <String, Map<String, Object?>>{};

  void user(
    String uid,
    String email, {
    String? name,
    DateTime? created,
    bool platform = false,
    bool disabled = false,
    int memberships = 0,
    int owned = 0,
    bool invited = false,
    String? phone,
  }) {
    docs['users/$uid'] = <String, Object?>{
      'email': email,
      'displayName': ?name,
      'phone': ?phone,
      'accountType': platform ? 'platform_admin' : 'tenant_user',
      'identityOrigin': invited ? 'staff_invitation' : 'self_signup',
      'globalStatus': disabled ? 'disabled' : 'active',
      'membershipCount': memberships,
      'ownedTenantCount': owned,
      'ownedActiveTenantCount': owned,
      'createdAt': created ?? _at(9, 1),
      'updatedAt': created ?? _at(9, 1),
    };
  }

  void tenant(
    String id,
    String name,
    String slug,
    String ownerUid,
    DateTime created, {
    String status = 'active',
    DateTime? updated,
  }) {
    docs['tenants/$id'] = <String, Object?>{
      'name': name,
      'slug': slug,
      'status': status,
      'ownerUid': ownerUid,
      'requestedBy': ownerUid,
      'createdAt': created,
      'updatedAt': updated ?? created,
    };
    docs['tenants/$id/lifecycle_history/created-$id'] = <String, Object?>{
      'tenantId': id,
      'eventType': 'tenant_requested',
      'fromStatus': null,
      'toStatus': 'active',
      'actorUid': ownerUid,
      'createdAt': created,
    };
  }

  void staff(
    String tenantId,
    String uid,
    String name,
    String email,
    String role, {
    String status = 'active',
    String? delivery,
    DateTime? expires,
    String? phone,
    DateTime? created,
  }) {
    docs['tenants/$tenantId/staff/$uid'] = <String, Object?>{
      'uid': uid,
      'name': name,
      'email': email,
      'phone': phone ?? '',
      'role': role,
      'status': status,
      'invitationStatus': status == 'pending' ? 'pending' : 'accepted',
      'invitationDeliveryState': ?delivery,
      'invitationExpiresAt': ?expires,
      'createdAt': created ?? _at(8, 14),
    };
  }

  void lifecycle(
    String tenantId,
    String id,
    String from,
    String to,
    String actor,
    DateTime at,
    String? reason,
  ) {
    docs['tenants/$tenantId/lifecycle_history/$id'] = <String, Object?>{
      'tenantId': tenantId,
      'eventType': 'tenant_lifecycle_changed',
      'fromStatus': from,
      'toStatus': to,
      'actorUid': actor,
      'reason': reason,
      'createdAt': at,
    };
    docs['platform_audit_logs/$id'] = <String, Object?>{
      'eventType': 'tenant_lifecycle_changed',
      'tenantId': tenantId,
      'fromStatus': from,
      'toStatus': to,
      'actorUid': actor,
      'reason': reason,
      'createdAt': at,
    };
  }

  // -- The platform administrators -----------------------------------------
  user(
    platformConsoleOperatorUid,
    'master@swahilipro.com',
    name: 'Bonnie Master',
    created: _at(10, 6, 10, 7),
    platform: true,
  );
  user(
    'mercy',
    'mercy.chebet@uzapay.co.ke',
    name: 'Mercy Chebet',
    created: _at(10, 8, 9),
    platform: true,
  );

  // -- Owners and the people the boards name --------------------------------
  user(
    'asha',
    'asha@mwangihardware.co.ke',
    name: 'Asha Mwangi',
    created: _at(8, 12, 9, 50),
    memberships: 1,
    owned: 1,
    phone: '+254712004118',
  );
  user(
    'boniface',
    'boniface@mwangihardware.co.ke',
    name: 'Boniface Otieno',
    created: _at(8, 13),
    memberships: 1,
    invited: true,
  );
  user(
    'grace',
    'grace@mwangihardware.co.ke',
    name: 'Grace Wanjiru',
    created: _at(8, 14),
    memberships: 1,
    invited: true,
  );
  user(
    'daniel',
    'daniel.kamau@gmail.com',
    name: 'Daniel Kamau',
    created: _at(8, 18),
    memberships: 1,
    owned: 1,
  );
  user(
    'esther',
    'esther@wairimusalon.co.ke',
    name: 'Esther Wairimu',
    created: _at(8, 21, 14, 22),
    memberships: 1,
    owned: 1,
    disabled: true,
  );
  user(
    'halima',
    'halima@lakeviewpharmacy.co.ke',
    name: 'Halima Abdi',
    created: _at(8, 26),
    memberships: 1,
    owned: 1,
  );
  user(
    'kevin',
    'kevin.odhiambo@gmail.com',
    name: 'Kevin Odhiambo',
    created: _at(8, 27),
    memberships: 1,
    invited: true,
    disabled: true,
  );
  user(
    'omar',
    'omar.said@gmail.com',
    name: 'Omar Said',
    created: _at(9, 2),
    memberships: 1,
    owned: 1,
  );
  user(
    'joseph',
    'joseph@kilimanigrocers.co.ke',
    name: 'Joseph Kiprono',
    created: _at(9, 3),
    memberships: 1,
    owned: 1,
  );
  user(
    'paul',
    'paul.maina@nyeriagrovet.co.ke',
    name: 'Paul Maina',
    created: _at(9, 9),
    memberships: 1,
    owned: 0,
  );
  user(
    'james',
    'james.njoroge@yahoo.com',
    name: 'James Njoroge',
    created: _at(10, 3),
  );
  user(
    'njeri-w',
    'njeri.wambui@gmail.com',
    name: 'Njeri Wambui',
    created: _at(10, 14, 11, 20),
    memberships: 1,
    owned: 1,
  );
  user(
    'ruth',
    'ruth.achieng@gmail.com',
    name: 'Ruth Achieng',
    created: _at(10, 20, 9, 5),
    memberships: 1,
    owned: 1,
  );

  // -- Businesses ------------------------------------------------------------
  tenant(
    'mwangi-hardware',
    'Mwangi Hardware',
    'mwangi-hardware',
    'asha',
    _at(8, 12, 10, 2),
    updated: _at(10, 10, 8, 15),
  );
  tenant(
    'kamau-butchery',
    'Kamau Butchery',
    'kamau-butchery',
    'daniel',
    _at(8, 18),
    status: 'suspended',
    updated: _at(10, 7, 12),
  );
  tenant(
    'wairimu-salon',
    'Wairimu Salon & Spa',
    'wairimu-salon',
    'esther',
    _at(8, 21, 14, 40),
  );
  tenant(
    'lake-view-pharmacy',
    'Lake View Pharmacy',
    'lake-view-pharmacy',
    'halima',
    _at(8, 26),
  );
  tenant(
    'coast-fresh-juices',
    'Coast Fresh Juices',
    'coast-fresh-juices',
    'omar',
    _at(9, 2),
    status: 'suspended',
    updated: _at(10, 11, 15, 2),
  );
  tenant(
    'kilimani-grocers',
    'Kilimani Grocers',
    'kilimani-grocers',
    'joseph',
    _at(9, 3),
  );
  tenant(
    'nyeri-agrovet',
    'Nyeri Agrovet',
    'nyeri-agrovet',
    'paul',
    _at(9, 9),
    status: 'archived',
    updated: _at(10, 13, 15),
  );
  tenant(
    'duka-la-mama-njeri',
    'Duka la Mama Njeri',
    'duka-la-mama-njeri',
    'njeri-w',
    _at(10, 14, 11, 30),
  );
  tenant(
    'ruths-boutique',
    'Ruth’s Boutique',
    'ruths-boutique',
    'ruth',
    _at(10, 20, 9, 12),
  );

  // Eight more, so the weekly series is the boards' 0 1 3 3 4 2 0 1 0 1 1 1.
  const fillers = <(String, String, int, int)>[
    ('Gikomba Textiles', 'gikomba-textiles', 8, 20),
    ('Thika Road Electronics', 'thika-road-electronics', 8, 25),
    ('Ngong Fresh Dairy', 'ngong-fresh-dairy', 8, 28),
    ('Eldoret Seeds', 'eldoret-seeds', 9, 1),
    ('Kisumu Fish Market', 'kisumu-fish-market', 9, 4),
    ('Machakos Hardware', 'machakos-hardware', 9, 11),
    ('Nakuru Books', 'nakuru-books', 9, 23),
    ('Malindi Crafts', 'malindi-crafts', 10, 8),
  ];
  var ownerIndex = 900;
  for (final (name, slug, month, day) in fillers) {
    final owner = _person(ownerIndex);
    final email = '${owner.split(' ').first.toLowerCase()}@$slug.co.ke';
    ownerIndex++;
    user(
      'owner-$slug',
      email,
      name: owner,
      created: _at(month, day, 9),
      memberships: 1,
      owned: 1,
    );
    tenant(slug, name, slug, 'owner-$slug', _at(month, day, 11));
    staff(slug, 'owner-$slug', owner, email, 'owner');
  }

  // -- Staff -------------------------------------------------------------------
  staff(
    'mwangi-hardware',
    'asha',
    'Asha Mwangi',
    'asha@mwangihardware.co.ke',
    'owner',
    phone: '+254 712 004 118',
  );
  staff(
    'mwangi-hardware',
    'boniface',
    'Boniface Otieno',
    'boniface@mwangihardware.co.ke',
    'admin',
  );
  staff(
    'mwangi-hardware',
    'grace',
    'Grace Wanjiru',
    'grace@mwangihardware.co.ke',
    'manager',
  );
  staff(
    'mwangi-hardware',
    'lydia',
    'Lydia Achieng',
    'lydia.achieng@gmail.com',
    'cashier',
    status: 'pending',
    expires: _at(10, 25),
  );
  staff(
    'mwangi-hardware',
    'njeri-k',
    'Njeri Kariuki',
    'njeri.kariuki@gmail.com',
    'cashier',
    status: 'pending',
    expires: _at(9, 18),
  );
  staff(
    'mwangi-hardware',
    'samuel',
    'Samuel Ochieng',
    'samuel.ochieng@yahoo.com',
    'cashier',
    status: 'pending',
    delivery: 'failed',
  );
  staff(
    'mwangi-hardware',
    'david',
    'David Mutiso',
    'david.mutiso@mwangihardware.co.ke',
    'cashier',
    status: 'inactive',
  );
  staff(
    'mwangi-hardware',
    'peter',
    'Peter Kamau',
    'peter.kamau@mwangihardware.co.ke',
    'cashier',
  );
  for (var index = 1; index <= 13; index++) {
    staff(
      'mwangi-hardware',
      'mh-cashier-$index',
      'Cashier $index',
      'cashier$index@mwangihardware.co.ke',
      'cashier',
    );
  }
  for (var index = 1; index <= 2; index++) {
    staff(
      'mwangi-hardware',
      'mh-invited-$index',
      'New hire $index',
      'hire$index@gmail.com',
      'cashier',
      status: 'pending',
      expires: _at(10, 27),
    );
  }
  staff(
    'kamau-butchery',
    'daniel',
    'Daniel Kamau',
    'daniel.kamau@gmail.com',
    'owner',
  );
  staff(
    'wairimu-salon',
    'esther',
    'Esther Wairimu',
    'esther@wairimusalon.co.ke',
    'owner',
  );
  staff(
    'lake-view-pharmacy',
    'halima',
    'Halima Abdi',
    'halima@lakeviewpharmacy.co.ke',
    'owner',
  );
  staff(
    'lake-view-pharmacy',
    'kevin',
    'Kevin Odhiambo',
    'kevin.odhiambo@gmail.com',
    'cashier',
  );
  for (var index = 1; index <= 9; index++) {
    staff(
      'lake-view-pharmacy',
      'lv-$index',
      'Pharmacist $index',
      'staff$index@lakeviewpharmacy.co.ke',
      'cashier',
    );
  }
  staff(
    'coast-fresh-juices',
    'omar',
    'Omar Said',
    'omar.said@gmail.com',
    'owner',
  );
  staff(
    'kilimani-grocers',
    'joseph',
    'Joseph Kiprono',
    'joseph@kilimanigrocers.co.ke',
    'owner',
  );
  staff(
    'nyeri-agrovet',
    'paul',
    'Paul Maina',
    'paul.maina@nyeriagrovet.co.ke',
    'owner',
  );
  staff(
    'duka-la-mama-njeri',
    'njeri-w',
    'Njeri Wambui',
    'njeri.wambui@gmail.com',
    'owner',
  );
  staff(
    'duka-la-mama-njeri',
    'dn-1',
    'Wanjiku',
    'wanjiku@gmail.com',
    'cashier',
  );
  staff('duka-la-mama-njeri', 'dn-2', 'Otieno', 'otieno@gmail.com', 'cashier');
  staff(
    'ruths-boutique',
    'ruth',
    'Ruth Achieng',
    'ruth.achieng@gmail.com',
    'owner',
  );

  // -- Accounts, to the boards' weekly series of new sign-ups -----------------
  // 4 18 26 31 38 22 15 12 11 8 18 9 from Monday 3 August: the named people
  // above fill some of each week, and filler accounts make up the rest.
  final weekStarts = <DateTime>[
    for (var week = 0; week < 12; week++) DateTime(2026, 8, 3 + 7 * week),
  ];
  const series = <int>[4, 18, 26, 31, 38, 22, 15, 12, 11, 8, 18, 9];
  final users = docs.entries.where((e) => e.key.startsWith('users/')).toList();
  var filler = 0;
  for (var week = 0; week < 12; week++) {
    final start = weekStarts[week];
    final end = week + 1 < 12 ? weekStarts[week + 1] : DateTime(2026, 10, 26);
    final already = users.where((entry) {
      final created = entry.value['createdAt']! as DateTime;
      return !created.isBefore(start) && created.isBefore(end);
    }).length;
    final daysInWeek = week == 11 ? 2 : 7;
    for (var index = 0; index < series[week] - already; index++) {
      filler++;
      final created = start.add(
        Duration(days: index % daysInWeek, hours: 7, minutes: index % 50),
      );
      final noBusiness = filler <= 7;
      user(
        'member-$filler',
        _address(filler),
        name: _person(filler),
        created: created,
        memberships: noBusiness ? 0 : 1,
        invited: !noBusiness,
        disabled: filler == 40,
      );
    }
  }

  // -- What happened -----------------------------------------------------------
  lifecycle(
    'mwangi-hardware',
    'lc-mwangi-suspend',
    'active',
    'suspended',
    platformConsoleOperatorUid,
    _at(10, 9, 17, 40),
    'Owner asked to pause trading during the stock-take.',
  );
  lifecycle(
    'mwangi-hardware',
    'lc-mwangi-reactivate',
    'suspended',
    'active',
    platformConsoleOperatorUid,
    _at(10, 10, 8, 15),
    'Stock-take finished; owner asked to resume.',
  );
  lifecycle(
    'kamau-butchery',
    'lc-kamau',
    'active',
    'suspended',
    platformConsoleOperatorUid,
    _at(10, 7, 12),
    'Chargebacks under review with the bank.',
  );
  lifecycle(
    'coast-fresh-juices',
    'lc-coast',
    'active',
    'suspended',
    platformConsoleOperatorUid,
    _at(10, 11, 15, 2),
    'Owner asked to close for renovation until November.',
  );
  lifecycle(
    'nyeri-agrovet',
    'lc-nyeri',
    'active',
    'archived',
    platformConsoleOperatorUid,
    _at(10, 13, 15),
    'Business closed; owner asked for it to be closed for good.',
  );

  docs['platform_audit_logs/ruths-boutique'] = <String, Object?>{
    'eventType': 'tenant_requested',
    'tenantId': 'ruths-boutique',
    'actorUid': 'ruth',
    'requestId': 'r-ruth',
    'createdAt': _at(10, 20, 9, 12),
  };
  docs['platform_audit_logs/duka-la-mama-njeri'] = <String, Object?>{
    'eventType': 'tenant_requested',
    'tenantId': 'duka-la-mama-njeri',
    'actorUid': 'njeri-w',
    'requestId': 'r-njeri',
    'createdAt': _at(10, 14, 11, 30),
  };
  docs['platform_audit_logs/status-kevin'] = <String, Object?>{
    'eventType': 'global_user_status_changed',
    'uid': 'kevin',
    'targetStatus': 'active',
    'requestedBy': 'mercy',
    'reason': 'Identity confirmed by phone with the pharmacy owner.',
    'status': 'partially_failed',
    'attemptCount': 2,
    'createdAt': _at(10, 20, 8, 51),
  };
  docs['platform_audit_logs/suppression-cleared'] = <String, Object?>{
    'eventType': 'email_suppression_cleared',
    'actorUid': platformConsoleOperatorUid,
    'reason': 'Owner confirmed the inbox was full and is cleared now.',
    'matchingRecordCount': 1,
    'clearedCount': 1,
    'createdAt': _at(10, 19, 11, 20),
  };
  docs['platform_audit_logs/status-esther'] = <String, Object?>{
    'eventType': 'global_user_status_changed',
    'uid': 'esther',
    'targetStatus': 'disabled',
    'requestedBy': 'mercy',
    'reason': 'Owner reported her phone and password stolen.',
    'status': 'completed',
    'attemptCount': 1,
    'affectedTenantIds': <String>['wairimu-salon'],
    'createdAt': _at(10, 18, 16, 5),
  };
  docs['platform_audit_logs/grant-mercy'] = <String, Object?>{
    'action': 'grant_platform_admin',
    'actorUid': platformConsoleOperatorUid,
    'targetUid': 'mercy',
    'reason': 'Second operator for the pilot.',
    'status': 'completed',
    'createdAt': _at(10, 8, 9),
  };

  docs['platform_user_operations/op-kevin'] = <String, Object?>{
    'uid': 'kevin',
    'targetStatus': 'active',
    'requestedBy': 'mercy',
    'status': 'partially_failed',
    'attemptCount': 2,
    'lastErrorCode': 'unavailable',
    'nextAttemptAt': _at(10, 20, 9, 45),
    'createdAt': _at(10, 20, 8, 51),
  };

  docs['platform_alerts/alert-wairimu'] = <String, Object?>{
    'severity': 'critical',
    'type': 'tenant_owner_unavailable',
    'tenantId': 'wairimu-salon',
    'uid': 'esther',
    'operationId': 'status-esther',
    'requestedBy': 'mercy',
    'reason': 'Owner reported her phone and password stolen.',
    'notificationStatus': 'completed',
    'createdAt': _at(10, 18, 16, 5),
  };
  docs['platform_alerts/alert-kilimani'] = <String, Object?>{
    'severity': 'critical',
    'type': 'tenant_reconciliation_quarantined',
    'tenantId': 'kilimani-grocers',
    'jobId': 'job-1',
    'errorCode': 'deadline-exceeded',
    'consecutiveFailureCount': 8,
    'notificationStatus': 'completed',
    'createdAt': _at(10, 19, 2, 10),
  };

  // -- Mwangi Hardware's own audit log ----------------------------------------
  docs['tenants/mwangi-hardware/audit_logs/pu-1'] = <String, Object?>{
    'eventType': 'product_updated',
    'tenantId': 'mwangi-hardware',
    'actorUid': 'grace',
    'changedFields': <String>['price'],
    'changes': <Object?>[
      <String, Object?>{'field': 'price', 'previous': 820, 'next': 850},
    ],
    'createdAt': _at(10, 20, 9, 31),
  };
  docs['tenants/mwangi-hardware/audit_logs/sa-1'] = <String, Object?>{
    'eventType': 'stock_adjusted',
    'tenantId': 'mwangi-hardware',
    'actorUid': 'peter',
    'quantityDelta': -3,
    'adjustmentType': 'damage',
    'createdAt': _at(10, 20, 8, 58),
  };
  docs['tenants/mwangi-hardware/audit_logs/am-1'] = <String, Object?>{
    'eventType': 'shift_summary_amended',
    'tenantId': 'mwangi-hardware',
    'actorUid': 'boniface',
    'salesVarianceMinor': -15000,
    'createdAt': _at(10, 19, 18, 20),
  };
  docs['tenants/mwangi-hardware/audit_logs/rp-1'] = <String, Object?>{
    'eventType': 'receipt_reprinted',
    'tenantId': 'mwangi-hardware',
    'actorUid': 'grace',
    'receiptNumber': 'MH-20261019-0031',
    'createdAt': _at(10, 19, 12, 4),
  };
  docs['tenants/mwangi-hardware/audit_logs/sd-1'] = <String, Object?>{
    'eventType': 'supplier_delivery_received',
    'tenantId': 'mwangi-hardware',
    'actorUid': 'asha',
    'unitCount': 240,
    'costChanges': <Object?>[
      <String, Object?>{},
      <String, Object?>{},
      <String, Object?>{},
      <String, Object?>{},
    ],
    'createdAt': _at(10, 17, 14),
  };
  docs['tenants/mwangi-hardware/audit_logs/si-1'] = <String, Object?>{
    'eventType': 'staff_invited',
    'tenantId': 'mwangi-hardware',
    'actorUid': 'boniface',
    'targetUid': 'lydia',
    'role': 'cashier',
    'createdAt': _at(10, 16, 10),
  };

  return docs;
}

/// The one address the email board finds suppressed.
const Map<String, (String, String)> platformConsoleSuppressed = {
  'samuel.ochieng@yahoo.com': ('hard_bounce', '2026-09-15T08:00:00.000Z'),
};
