/// Who a business sells to: the read model, the form's validation, the search,
/// and the intents a device may send.
///
/// **A customer is a contact, not a ledger.** It is who a sale was for and how
/// to reach them. The figures on it - points, sale count, last sale - are
/// written by the server as sales arrive and are only ever read here.
///
/// **Every rule here mirrors one `functions/src/operations/customers.ts`
/// enforces**, so a mistake a person can fix is reported on the form rather
/// than after a queue drain, and a queued customer is drawn - and found by the
/// till's search - exactly as the server will store them.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_pending_mutation.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';

/// The server's `MAXIMUM_PRODUCT_NAME_LENGTH`, which a customer name shares.
const int maximumCustomerNameLength = 120;
const int maximumCustomerEmailLength = 254;
const int maximumCustomerNotesLength = 1000;

/// The trailing digits a phone search also answers to - the server's
/// `NATIONAL_NUMBER_DIGITS`, and its note is the argument.
const int customerNationalNumberDigits = 9;

/// The longest a single search token is prefixed to, as on the server.
const int _maximumSearchTokenLength = 120;

/// Raised when a customer write or search is refused before anything is sent.
final class TenantCustomerException implements Exception {
  const TenantCustomerException(this.code);

  final String code;

  @override
  String toString() => 'TenantCustomerException($code)';
}

/// Strict read model for `tenants/{tenantId}/customers/{customerId}`.
final class TenantCustomer {
  TenantCustomer.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) : id = _customerId(path),
       tenantId = _tenantId(path),
       name = _requiredName(data['name']),
       phone = _optionalText(data['phone']),
       email = _optionalText(data['email']),
       kraPin = _optionalText(data['kraPin']),
       notes = _optionalText(data['notes']),
       // Consent is a `true` and nothing else: absent, `false` or malformed all
       // read as no, because a receipt sent without consent cannot be unsent.
       whatsappOptIn = data['whatsappOptIn'] == true,
       // Absent reads as active: a customer is written active and only ever
       // marked otherwise explicitly.
       active = data['active'] != false,
       points = _count(data['points']),
       saleCount = _count(data['saleCount']),
       lastSaleAt = tenantStoredInstant(data['lastSaleAt']),
       creditLimitMinor = _limit(data['creditLimitMinor']),
       creditBlocked = data['creditBlocked'] == true,
       balanceMinor = _balance(data['balanceMinor']),
       owingSince = tenantStoredInstant(data['owingSince']),
       lastPaymentAt = tenantStoredInstant(data['lastPaymentAt']);

  factory TenantCustomer.fromSnapshot(TenantQueryDocumentSnapshot snapshot) =>
      TenantCustomer.fromDocument(path: snapshot.path, data: snapshot.data);

  final String id;
  final String tenantId;
  final String name;

  /// E.164, as the server stores it - `+254712345678`.
  final String? phone;
  final String? email;
  final String? kraPin;
  final String? notes;

  /// Whether this customer agreed to get receipts on WhatsApp, for [phone].
  final bool whatsappOptIn;

  /// Whether the customer is still offered at the till. An inactive customer
  /// keeps their name, history and points; they are simply not offered.
  final bool active;

  /// Loyalty points, as the server last counted them. Never negative.
  final int points;
  final int saleCount;
  final DateTime? lastSaleAt;

  /// A limit set before limits were withdrawn on 2026-10-02, or null. Kept
  /// and shown where one exists; nothing new sets one.
  final int? creditLimitMinor;

  /// Whether a manager has stopped this customer buying on credit. Any named
  /// customer may, unless this says otherwise.
  final bool creditBlocked;

  /// What they owe, as the server last moved it. Below zero when they have
  /// paid ahead, and the shop owes them.
  final int balanceMinor;

  /// When they started owing, or null while they owe nothing.
  final DateTime? owingSince;

  final DateTime? lastPaymentAt;

  /// Whether a cashier may put a sale on this customer's account.
  bool get allowsCredit => active && !creditBlocked;

  /// What they owe, never below zero - the figure a "who owes" list sorts by.
  int get owedMinor => balanceMinor > 0 ? balanceMinor : 0;

  /// How much more they may take on credit before reaching their limit.
  int get creditAvailableMinor {
    final limit = creditLimitMinor;
    if (limit == null) return 0;
    final available = limit - balanceMinor;
    return available > 0 ? available : 0;
  }

  /// Whether they owe more than a limit set before limits were withdrawn.
  /// Without one, nobody is over anything.
  bool get overLimit {
    final limit = creditLimitMinor;
    return limit != null && balanceMinor > limit;
  }

  /// Whether a receipt may go to this customer on WhatsApp.
  bool get receivesWhatsapp => active && phone != null && whatsappOptIn;

  /// The number shown beside the name where somebody else might see the
  /// screen: enough to tell two Johns apart, not enough to copy down.
  String? get maskedPhone => maskCustomerPhone(phone);

  /// The value this customer holds for one editable [field].
  String? valueOf(TenantCustomerField field) => switch (field) {
    TenantCustomerField.name => name,
    TenantCustomerField.phone => phone,
    TenantCustomerField.email => email,
    TenantCustomerField.kraPin => kraPin,
    TenantCustomerField.notes => notes,
  };

  static String _customerId(String path) {
    final parts = path.split('/');
    if (parts.length != 4 ||
        parts[0] != 'tenants' ||
        parts[2] != TenantCollection.customers.segment) {
      throw const FormatException('Not a customer document.');
    }
    return validateTenantDocumentId(parts[3], fieldName: 'customerId');
  }

  static String _tenantId(String path) => validateTenantId(path.split('/')[1]);

  static String _requiredName(Object? value) {
    if (value is! String || value.trim().isEmpty || value != value.trim()) {
      throw const FormatException('A customer must have a name.');
    }
    return value;
  }

  /// A contact field, read permissively, as a supplier's is: a directory that
  /// one malformed row empties is worse than a blank number.
  static String? _optionalText(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  static int _count(Object? value) => value is int && value > 0 ? value : 0;

  static int? _limit(Object? value) => value is int && value > 0 ? value : null;

  static int _balance(Object? value) => value is int ? value : 0;
}

/// The largest credit limit the server accepts: ten billion of the major unit.
const int maximumCustomerCreditLimitMinor = 1000000000000;

/// `+254 ••• 678`, or null where there is no number.
String? maskCustomerPhone(String? phone) {
  if (phone == null || phone.length < 8) return phone;
  return '${phone.substring(0, 4)} ••• ${phone.substring(phone.length - 3)}';
}

/// The fields a customer form offers, with the key the server reads each by.
enum TenantCustomerField {
  name('name', 'Name'),
  phone('phone', 'Phone'),
  email('email', 'Email'),
  kraPin('kraPin', 'KRA PIN'),
  notes('notes', 'Notes');

  const TenantCustomerField(this.wireKey, this.label);

  final String wireKey;
  final String label;
}

/// What the customer form holds, as typed.
///
/// [phone] is already E.164 - the form joins the dialling code and the number
/// with `normalizeE164` - or empty for no number.
final class TenantCustomerDraft {
  const TenantCustomerDraft({
    required this.name,
    this.phone = '',
    this.email = '',
    this.kraPin = '',
    this.notes = '',
    this.whatsappOptIn = false,
    this.creditLimitMinor,
    this.creditAllowed = true,
  });

  factory TenantCustomerDraft.of(TenantCustomer customer) =>
      TenantCustomerDraft(
        name: customer.name,
        phone: customer.phone ?? '',
        email: customer.email ?? '',
        kraPin: customer.kraPin ?? '',
        notes: customer.notes ?? '',
        whatsappOptIn: customer.whatsappOptIn,
        creditLimitMinor: customer.creditLimitMinor,
        creditAllowed: !customer.creditBlocked,
      );

  final String name;
  final String phone;
  final String email;
  final String kraPin;
  final String notes;
  final bool whatsappOptIn;

  /// The credit limit to give, or null for none. Zero means none too.
  final int? creditLimitMinor;

  /// Whether this customer may buy on credit - yes, unless a manager says no.
  final bool creditAllowed;

  /// [creditLimitMinor] as the server will store it, or a refusal.
  int? normalizedCreditLimit() {
    final limit = creditLimitMinor;
    if (limit == null || limit == 0) return null;
    if (limit < 0 || limit > maximumCustomerCreditLimitMinor) {
      throw const TenantCustomerException('invalid_customer_credit_limit');
    }
    return limit;
  }

  String raw(TenantCustomerField field) => switch (field) {
    TenantCustomerField.name => name,
    TenantCustomerField.phone => phone,
    TenantCustomerField.email => email,
    TenantCustomerField.kraPin => kraPin,
    TenantCustomerField.notes => notes,
  };

  /// Every field normalized exactly as the server will store it, or a refusal
  /// naming the field that cannot be. Empty optional fields come back null.
  Map<TenantCustomerField, String?> normalized() =>
      <TenantCustomerField, String?>{
        for (final field in TenantCustomerField.values)
          field: normalizeCustomerField(field, raw(field)),
      };
}

/// One field, normalized as `functions/src/operations/customers.ts` normalizes
/// it, or a [TenantCustomerException] naming what is wrong.
String? normalizeCustomerField(TenantCustomerField field, String value) {
  switch (field) {
    case TenantCustomerField.name:
      final name = _singleLine(value);
      if (name.isEmpty ||
          name.length > maximumCustomerNameLength ||
          _hasControl(name)) {
        throw const TenantCustomerException('invalid_customer_name');
      }
      return name;
    case TenantCustomerField.phone:
      final phone = _singleLine(value);
      if (phone.isEmpty) return null;
      if (!_e164Shape.hasMatch(phone)) {
        throw const TenantCustomerException('invalid_customer_phone');
      }
      return phone;
    case TenantCustomerField.email:
      final email = _singleLine(value);
      if (email.isEmpty) return null;
      if (email.length > maximumCustomerEmailLength ||
          !_emailShape.hasMatch(email)) {
        throw const TenantCustomerException('invalid_customer_email');
      }
      return email;
    case TenantCustomerField.kraPin:
      final pin = _singleLine(value).toUpperCase();
      if (pin.isEmpty) return null;
      if (!_kraPinShape.hasMatch(pin)) {
        throw const TenantCustomerException('invalid_customer_kra_pin');
      }
      return pin;
    case TenantCustomerField.notes:
      // Notes keep their line breaks, and nothing else unusual - the server's
      // `notesText`, step for step.
      final notes = value
          .replaceAll(RegExp(r'\r\n?'), '\n')
          .split('\n')
          .map((line) => line.trim().replaceAll(RegExp(r'[^\S\n]+'), ' '))
          .join('\n')
          .trim();
      if (notes.isEmpty) return null;
      if (notes.length > maximumCustomerNotesLength ||
          _hasControl(notes.replaceAll('\n', ''))) {
        throw const TenantCustomerException('invalid_customer_notes');
      }
      return notes;
  }
}

/// Normalizes customer search text exactly as the server does.
String tenantCustomerSearchTerm(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// The sort name and search prefixes stored on one customer.
///
/// **The server's `customerSearchFields`, character for character**, so a
/// customer queued on this device is found by the same searches a stored one
/// is, and the queued document reads back equal to what the server wrote.
({String searchName, List<String> searchPrefixes}) tenantCustomerSearchFields({
  required String name,
  String? phone,
}) {
  final normalizedName = tenantCustomerSearchTerm(name);
  final tokens = <String>{normalizedName, ...normalizedName.split(' ')};
  if (phone != null && phone.isNotEmpty) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    tokens.add(digits);
    if (digits.length > customerNationalNumberDigits) {
      final national = digits.substring(
        digits.length - customerNationalNumberDigits,
      );
      tokens
        ..add(national)
        ..add('0$national');
    }
  }
  final prefixes = <String>{};
  for (final token in tokens) {
    final maximum = min(token.length, _maximumSearchTokenLength);
    for (var length = 2; length <= maximum; length++) {
      prefixes.add(token.substring(0, length));
    }
  }
  final sorted = prefixes.toList()..sort();
  return (
    searchName: normalizedName,
    searchPrefixes: List<String>.unmodifiable(sorted),
  );
}

/// What somebody typed into a customer search, as the prefix it is matched by.
///
/// **A number is searched by its digits**, so `0712 345` finds the same
/// customer as `0712345`; anything else is searched as a name. Null where there
/// is nothing worth searching for yet - the index starts at two characters.
String? tenantCustomerSearchPrefix(String typed) {
  final term = tenantCustomerSearchTerm(typed);
  final digits = term.replaceAll(RegExp(r'[\s+()\-.]'), '');
  final prefix = RegExp(r'^\d+$').hasMatch(digits) ? digits : term;
  if (prefix.length < 2) return null;
  return prefix.length > _maximumSearchTokenLength
      ? prefix.substring(0, _maximumSearchTokenLength)
      : prefix;
}

/// A validated instruction to add exactly one customer.
final class TenantCustomerCreateIntent {
  const TenantCustomerCreateIntent._({
    required this.path,
    required this.tenantId,
    required this.customerId,
    required this.fields,
    required this.whatsappOptIn,
    required this.createdBy,
    this.creditLimitMinor,
    this.creditBlocked = false,
  });

  final String path;
  final String tenantId;
  final String customerId;
  final Map<TenantCustomerField, String?> fields;
  final bool whatsappOptIn;
  final String createdBy;

  /// The credit limit given with the customer, or null for none.
  final int? creditLimitMinor;

  /// Whether the customer is added blocked from buying on credit.
  final bool creditBlocked;

  String get name => fields[TenantCustomerField.name]!;
  String? get phone => fields[TenantCustomerField.phone];
  String? get kraPin => fields[TenantCustomerField.kraPin];

  /// The document a device composes: what the overlay draws, what the picker
  /// finds, and what the queue replays. The server takes the actor from the
  /// request and computes its own search fields, which come out the same.
  Map<String, Object?> documentData() {
    final search = tenantCustomerSearchFields(name: name, phone: phone);
    return <String, Object?>{
      for (final entry in fields.entries)
        if (entry.value != null) entry.key.wireKey: entry.value,
      if (whatsappOptIn) 'whatsappOptIn': true,
      if (creditLimitMinor != null) 'creditLimitMinor': creditLimitMinor,
      if (creditBlocked) 'creditBlocked': true,
      'active': true,
      'searchName': search.searchName,
      'searchPrefixes': search.searchPrefixes,
      'createdBy': createdBy,
    };
  }
}

/// A validated instruction to correct exactly one customer.
///
/// It carries **only what moves**, as a supplier correction does. A changed
/// name or number carries the search fields it implies, so the overlay finds
/// the customer under what they are now called.
final class TenantCustomerUpdateIntent {
  const TenantCustomerUpdateIntent._({
    required this.path,
    required this.tenantId,
    required this.customerId,
    required this.changes,
    required this.whatsappOptIn,
    required this.active,
    required this.search,
    this.creditLimit,
    this.creditBlocked,
  });

  final String path;
  final String tenantId;
  final String customerId;

  /// Every field that moves, and to what. A null value clears the field.
  final Map<TenantCustomerField, String?> changes;

  /// Consent recorded (true) or withdrawn (false), or null when unchanged.
  final bool? whatsappOptIn;

  /// The new standing, or null when it is not changing.
  final bool? active;

  final ({String searchName, List<String> searchPrefixes})? search;

  /// The new credit limit - a null value stops credit - or null when the
  /// limit is not changing.
  final ({int? value})? creditLimit;

  /// Credit blocked (true) or allowed again (false), or null when unchanged.
  final bool? creditBlocked;

  Map<String, Object?> documentData() => <String, Object?>{
    for (final entry in changes.entries) entry.key.wireKey: entry.value,
    if (whatsappOptIn != null) 'whatsappOptIn': whatsappOptIn,
    if (active != null) 'active': active,
    if (creditLimit case final limit?) 'creditLimitMinor': limit.value,
    if (creditBlocked != null) 'creditBlocked': creditBlocked,
    if (search case final search?) ...<String, Object?>{
      'searchName': search.searchName,
      'searchPrefixes': search.searchPrefixes,
    },
  };

  /// One operation per distinct correction, so a second correction made before
  /// the first lands queues beside it rather than colliding with it.
  String get operationId =>
      'customer-update-$customerId-'
      '${tenantMutationFingerprint(documentData()).substring(0, 16)}';
}

/// Which customers a directory view shows.
enum TenantCustomerStanding {
  active('active', 'Active'),
  inactive('inactive', 'Inactive'),
  all('all', 'All customers'),

  /// Everyone who owes money, biggest debt first - read through
  /// [TenantCustomerCreditRepository.loadOwing], not this search.
  owing('owing', 'Who owes');

  const TenantCustomerStanding(this.wireValue, this.label);

  final String wireValue;
  final String label;

  /// The `active` filter this standing asks the server for.
  bool? get activeFilter => switch (this) {
    TenantCustomerStanding.active => true,
    TenantCustomerStanding.inactive => false,
    TenantCustomerStanding.all || TenantCustomerStanding.owing => null,
  };
}

/// One page of customers, in name order.
final class TenantCustomerPage {
  TenantCustomerPage({
    required List<TenantCustomer> customers,
    required this.nextCursor,
  }) : customers = List<TenantCustomer>.unmodifiable(customers);

  final List<TenantCustomer> customers;

  /// Where the next page starts, or null when this was the last.
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// Reads one business's customers and builds the writes a form may send.
final class TenantCustomerRepository extends TenantReadRepository {
  TenantCustomerRepository({
    required super.session,
    required super.reader,
    TenantCustomerSearchReader? searchReader,
  }) : _searchReader =
           searchReader ??
           switch (reader) {
             final TenantCustomerSearchReader search => search,
             _ => null,
           };

  final TenantCustomerSearchReader? _searchReader;

  /// Everyone who sells, which is everyone `createCustomer` admits: the till is
  /// where a customer is met.
  static const List<TenantRole> createRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
    TenantRole.cashier,
  ];

  /// Who may correct a customer, mark one inactive, or record consent
  /// afterwards - `updateCustomer`'s roles, and the Customers screen's.
  static const List<TenantRole> manageRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  static bool canCreateInSession(TenantSession session) =>
      session.canAccess(allowedRoles: createRoles);

  static bool canManageInSession(TenantSession session) =>
      session.canAccess(allowedRoles: manageRoles);

  static const int maximumPageSize = 50;

  /// One page of customers whose name or number starts with [search].
  ///
  /// An empty or one-character [search] lists every customer of [standing] in
  /// name order, which is what a directory opened with nothing typed shows.
  Future<TenantCustomerPage> search({
    String search = '',
    TenantCustomerStanding standing = TenantCustomerStanding.active,
    int pageSize = 20,
    String? cursor,
  }) async {
    if (!session.canAccess()) {
      throw const TenantCustomerException('customer_forbidden');
    }
    if (pageSize < 1 || pageSize > maximumPageSize) {
      throw RangeError.range(pageSize, 1, maximumPageSize, 'pageSize');
    }
    final searchReader = _searchReader;
    if (searchReader == null) {
      throw StateError('This reader does not support customer search.');
    }
    final collectionPath = paths.collectionPath(TenantCollection.customers);
    final snapshots = await searchReader.searchTenantCustomers(
      TenantCustomerSearchQuery.scoped(
        collectionPath: collectionPath,
        limit: pageSize + 1,
        searchPrefix: tenantCustomerSearchPrefix(search),
        active: standing.activeFilter,
        startAfter: cursor == null ? null : _decodeCursor(cursor),
      ),
    );
    if (snapshots.length > pageSize + 1) {
      throw const TenantScopeViolation(
        'Customer search returned more documents than requested.',
      );
    }
    final expectedPrefix = '$collectionPath/';
    final seen = <String>{};
    final customers = <TenantCustomer>[];
    for (final snapshot in snapshots) {
      if (!snapshot.path.startsWith(expectedPrefix) ||
          snapshot.path.substring(expectedPrefix.length).contains('/')) {
        throw TenantScopeViolation(
          'Customer search escaped $collectionPath with ${snapshot.path}.',
        );
      }
      if (!seen.add(snapshot.path)) {
        throw const TenantScopeViolation(
          'Customer search returned the same document twice.',
        );
      }
      final customer = TenantCustomer.fromSnapshot(snapshot);
      if (customer.tenantId != session.tenantId) {
        throw const TenantCustomerException('cross_tenant_customer');
      }
      customers.add(customer);
    }
    final hasMore = customers.length > pageSize;
    final visible = customers.take(pageSize).toList(growable: false);
    final last = visible.isEmpty ? null : visible.last;
    return TenantCustomerPage(
      customers: visible,
      nextCursor: hasMore && last != null
          ? _encodeCursor(
              TenantCustomerSearchPosition(
                searchName: tenantCustomerSearchTerm(last.name),
                documentId: last.id,
              ),
            )
          : null,
    );
  }

  /// The customer already holding [phone], other than [exceptId], among those
  /// this reader can see.
  ///
  /// **The device's half of the server's rule**, asked before a create is
  /// queued so a cashier is offered the customer who is already there rather
  /// than told, after a drain, that the number was taken. The server checks
  /// again against every customer.
  Future<TenantCustomer?> holderOfPhone(
    String phone, {
    String? exceptId,
  }) async {
    final page = await search(
      search: phone,
      standing: TenantCustomerStanding.all,
      pageSize: 10,
    );
    for (final customer in page.customers) {
      if (customer.id != exceptId && customer.phone == phone) return customer;
    }
    return null;
  }

  /// One customer by their ID, or null when this business holds none by it.
  Future<TenantCustomer?> loadCustomer(String customerId) async {
    if (!session.canAccess()) {
      throw const TenantCustomerException('customer_forbidden');
    }
    final data = await readDocument(TenantCollection.customers, customerId);
    if (data == null) return null;
    return TenantCustomer.fromDocument(
      path: paths.customer(customerId),
      data: data,
    );
  }

  /// Builds the one create the typed form describes.
  TenantCustomerCreateIntent buildCreateIntent({
    required TenantCustomerDraft draft,
    required String requestId,
  }) {
    if (!canCreateInSession(session)) {
      throw const TenantCustomerException('customer_forbidden');
    }
    _requireRequestId(requestId);
    final fields = draft.normalized();
    final optedIn = draft.whatsappOptIn;
    if (optedIn && fields[TenantCustomerField.phone] == null) {
      throw const TenantCustomerException('consent_needs_phone');
    }
    // Credit is lending the shop's money, which is a manager's decision even
    // where a cashier may add the customer.
    final creditLimit = draft.normalizedCreditLimit();
    if ((creditLimit != null || !draft.creditAllowed) &&
        !canManageInSession(session)) {
      throw const TenantCustomerException('customer_forbidden');
    }
    final customerId = _deterministicCustomerId(
      tenantId: session.tenantId,
      createdBy: session.uid,
      requestId: requestId,
    );
    return TenantCustomerCreateIntent._(
      path: paths.customer(customerId),
      tenantId: session.tenantId,
      customerId: customerId,
      fields: Map<TenantCustomerField, String?>.unmodifiable(fields),
      whatsappOptIn: optedIn,
      createdBy: session.uid,
      creditLimitMinor: creditLimit,
      creditBlocked: !draft.creditAllowed,
    );
  }

  /// Builds the one correction the typed form describes, carrying only what
  /// moves.
  ///
  /// **A new number withdraws the consent given for the old one**, unless the
  /// same correction records it again - the server's rule, sent explicitly so
  /// the overlay draws what the server will store.
  TenantCustomerUpdateIntent buildUpdateIntent({
    required TenantCustomer customer,
    required TenantCustomerDraft draft,
  }) {
    _requireManage();
    _requireOwned(customer);
    final fields = draft.normalized();
    final changes = <TenantCustomerField, String?>{
      for (final entry in fields.entries)
        if (entry.value != customer.valueOf(entry.key)) entry.key: entry.value,
    };
    final phoneChanges = changes.containsKey(TenantCustomerField.phone);
    final resultingPhone = phoneChanges
        ? changes[TenantCustomerField.phone]
        : customer.phone;
    if (draft.whatsappOptIn && resultingPhone == null) {
      throw const TenantCustomerException('consent_needs_phone');
    }
    bool? optIn;
    if (draft.whatsappOptIn && (!customer.whatsappOptIn || phoneChanges)) {
      optIn = true;
    } else if (!draft.whatsappOptIn && customer.whatsappOptIn) {
      optIn = false;
    }
    final creditLimit = draft.normalizedCreditLimit();
    final limitChanges = creditLimit != customer.creditLimitMinor;
    final blockChanges = draft.creditAllowed == customer.creditBlocked;
    if (changes.isEmpty && optIn == null && !limitChanges && !blockChanges) {
      throw const TenantCustomerException('customer_unchanged');
    }
    final renamed =
        changes.containsKey(TenantCustomerField.name) || phoneChanges;
    return TenantCustomerUpdateIntent._(
      path: paths.customer(customer.id),
      tenantId: session.tenantId,
      customerId: customer.id,
      changes: Map<TenantCustomerField, String?>.unmodifiable(changes),
      whatsappOptIn: optIn,
      active: null,
      creditLimit: limitChanges ? (value: creditLimit) : null,
      creditBlocked: blockChanges ? !draft.creditAllowed : null,
      search: renamed
          ? tenantCustomerSearchFields(
              name: changes[TenantCustomerField.name] ?? customer.name,
              phone: resultingPhone,
            )
          : null,
    );
  }

  /// Marks [customer] inactive, or offers them again.
  TenantCustomerUpdateIntent buildStandingIntent({
    required TenantCustomer customer,
    required bool active,
  }) {
    _requireManage();
    _requireOwned(customer);
    if (customer.active == active) {
      throw const TenantCustomerException('customer_unchanged');
    }
    return TenantCustomerUpdateIntent._(
      path: paths.customer(customer.id),
      tenantId: session.tenantId,
      customerId: customer.id,
      changes: const <TenantCustomerField, String?>{},
      whatsappOptIn: null,
      active: active,
      search: null,
    );
  }

  void _requireManage() {
    if (!canManageInSession(session)) {
      throw const TenantCustomerException('customer_forbidden');
    }
  }

  void _requireOwned(TenantCustomer customer) {
    // A customer decoded while another business was open can never be changed
    // from this one, even though both paths would be well-formed.
    if (customer.tenantId != session.tenantId) {
      throw const TenantCustomerException('customer_forbidden');
    }
  }
}

/// How a customer write left this device.
final class TenantCustomerWriteResult {
  const TenantCustomerWriteResult.queued(this.operationId);

  /// The queued record, which is also what an undo would withdraw.
  final String operationId;
}

/// Where a customer write is sent. The composition root supplies the queued
/// writer, so `lib/customers` depends on `lib/tenancy` and not the other way
/// round.
abstract interface class TenantCustomerWriter {
  Future<TenantCustomerWriteResult> createCustomer(
    TenantCustomerCreateIntent intent,
  );

  Future<TenantCustomerWriteResult> updateCustomer(
    TenantCustomerUpdateIntent intent,
  );
}

/// A fresh request ID for one customer create.
String secureTenantCustomerRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'customer-${base64Url.encode(bytes).replaceAll('=', '')}';
}

String _deterministicCustomerId({
  required String tenantId,
  required String createdBy,
  required String requestId,
}) {
  final digest = sha256.convert(
    utf8.encode(
      <String>[
        'createTenantCustomer',
        tenantId,
        createdBy,
        requestId,
      ].join(' '),
    ),
  );
  return 'cu_${digest.toString().substring(0, 40)}';
}

/// Whether [value] is shaped as an ID this device would mint for a customer.
///
/// The server acts only on IDs of this shape, and a sale naming anything else
/// is read as a walk-in.
bool isTenantCustomerId(String value) => _customerIdShape.hasMatch(value);

String _encodeCursor(TenantCustomerSearchPosition position) => base64Url.encode(
  utf8.encode(
    jsonEncode(<String, Object?>{
      'n': position.searchName,
      'd': position.documentId,
    }),
  ),
);

TenantCustomerSearchPosition _decodeCursor(String cursor) {
  try {
    final decoded = jsonDecode(utf8.decode(base64Url.decode(cursor)));
    if (decoded is Map &&
        decoded['n'] is String &&
        decoded['d'] is String) {
      return TenantCustomerSearchPosition(
        searchName: decoded['n'] as String,
        documentId: validateTenantDocumentId(
          decoded['d'] as String,
          fieldName: 'customerId',
        ),
      );
    }
  } on FormatException {
    // Fall through to the refusal below.
  } on ArgumentError {
    // Fall through to the refusal below.
  }
  throw const FormatException('The customer cursor is not one this issued.');
}

void _requireRequestId(String requestId) {
  if (!_requestIdPattern.hasMatch(requestId)) {
    throw const TenantCustomerException('invalid_request_id');
  }
}

String _singleLine(String value) =>
    value.trim().replaceAll(_whitespaceRun, ' ');

bool _hasControl(String value) {
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || (codeUnit >= 0x7f && codeUnit <= 0x9f)) return true;
  }
  return false;
}

final RegExp _whitespaceRun = RegExp(r'\s+');
final RegExp _e164Shape = RegExp(r'^\+[1-9]\d{7,14}$');
final RegExp _emailShape = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final RegExp _kraPinShape = RegExp(r'^[A-Z][0-9]{9}[A-Z]$');
final RegExp _customerIdShape = RegExp(r'^cu_[0-9a-f]{40}$');
final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
