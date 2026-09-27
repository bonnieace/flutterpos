/// Who stock is bought from: the read model, the form's validation, and the
/// intents a device may send.
///
/// **A supplier holds no stock.** It is who a delivery came from and how to
/// reach them; its history is the deliveries recorded against it, never a figure
/// stored on it.
///
/// **Every rule here mirrors one `functions/src/operations/suppliers.ts`
/// enforces**, so a mistake a person can fix is reported on the form instead of
/// costing a round trip, and a queued supplier is never refused for something
/// the device could have caught. The one rule the device cannot enforce alone -
/// that no two suppliers share a name - is checked here against the directory
/// this device has read, and again by the server against every one.
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

/// The server's `MAXIMUM_PRODUCT_NAME_LENGTH`, which a supplier name shares.
const int maximumSupplierNameLength = 120;
const int maximumSupplierPhoneLength = 32;
const int maximumSupplierEmailLength = 254;
const int maximumSupplierAddressLength = 300;
const int maximumSupplierTaxReferenceLength = 64;
const int maximumSupplierNotesLength = 1000;

/// The server's `MAXIMUM_SUPPLIER_SCAN`: the most suppliers one name is checked
/// against, and so the most this device reads for the directory.
const int maximumSupplierDirectory = 500;

/// Raised when a supplier write is refused before anything is queued.
final class TenantSupplierException implements Exception {
  const TenantSupplierException(this.code);

  final String code;

  @override
  String toString() => 'TenantSupplierException($code)';
}

/// The folded form two supplier names are compared in.
///
/// The server's `foldCategoryName`, character for character: "abc
/// distributors" and "ABC Distributors" are one supplier.
String foldSupplierName(String value) =>
    value.trim().replaceAll(_whitespaceRun, ' ').toLowerCase();

/// Strict read model for `tenants/{tenantId}/suppliers/{supplierId}`.
final class TenantSupplier {
  TenantSupplier.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) : id = _supplierId(path),
       tenantId = _tenantId(path),
       name = _requiredName(data['name']),
       phone = _optionalText(data['phone']),
       email = _optionalText(data['email']),
       address = _optionalText(data['address']),
       taxReference = _optionalText(data['taxReference']),
       notes = _optionalText(data['notes']),
       // Absent reads as active: a supplier is written active and only ever
       // marked otherwise explicitly.
       active = data['active'] != false,
       lastDeliveryAt = tenantStoredInstant(data['lastDeliveryAt']);

  factory TenantSupplier.fromSnapshot(TenantQueryDocumentSnapshot snapshot) =>
      TenantSupplier.fromDocument(path: snapshot.path, data: snapshot.data);

  final String id;
  final String tenantId;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? taxReference;
  final String? notes;

  /// Whether the supplier is still offered when stock is received. An inactive
  /// supplier keeps its name and its history; it is simply not offered.
  final bool active;

  /// When a delivery was last recorded against this supplier, when one has.
  final DateTime? lastDeliveryAt;

  String get foldedName => foldSupplierName(name);

  /// The value this supplier holds for one editable [field].
  String? valueOf(TenantSupplierField field) => switch (field) {
    TenantSupplierField.name => name,
    TenantSupplierField.phone => phone,
    TenantSupplierField.email => email,
    TenantSupplierField.address => address,
    TenantSupplierField.taxReference => taxReference,
    TenantSupplierField.notes => notes,
  };

  static String _supplierId(String path) {
    final parts = path.split('/');
    if (parts.length != 4 ||
        parts[0] != 'tenants' ||
        parts[2] != TenantCollection.suppliers.segment) {
      throw const FormatException('Not a supplier document.');
    }
    return validateTenantDocumentId(parts[3], fieldName: 'supplierId');
  }

  static String _tenantId(String path) => validateTenantId(path.split('/')[1]);

  static String _requiredName(Object? value) {
    if (value is! String || value.trim().isEmpty || value != value.trim()) {
      throw const FormatException('A supplier must have a name.');
    }
    return value;
  }

  /// A contact field, read permissively: a value that is not text is shown as
  /// nothing rather than refusing the supplier, because a directory that one
  /// malformed row empties is worse than a blank phone number.
  static String? _optionalText(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;
}

/// The fields a supplier form offers, with the key the server reads each by.
enum TenantSupplierField {
  name('name', 'Name'),
  phone('phone', 'Phone'),
  email('email', 'Email'),
  address('address', 'Address'),
  taxReference('taxReference', 'Tax or business reference'),
  notes('notes', 'Notes');

  const TenantSupplierField(this.wireKey, this.label);

  final String wireKey;
  final String label;
}

/// What the supplier form holds, as typed.
final class TenantSupplierDraft {
  const TenantSupplierDraft({
    required this.name,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.taxReference = '',
    this.notes = '',
  });

  factory TenantSupplierDraft.of(TenantSupplier supplier) =>
      TenantSupplierDraft(
        name: supplier.name,
        phone: supplier.phone ?? '',
        email: supplier.email ?? '',
        address: supplier.address ?? '',
        taxReference: supplier.taxReference ?? '',
        notes: supplier.notes ?? '',
      );

  final String name;
  final String phone;
  final String email;
  final String address;
  final String taxReference;
  final String notes;

  String raw(TenantSupplierField field) => switch (field) {
    TenantSupplierField.name => name,
    TenantSupplierField.phone => phone,
    TenantSupplierField.email => email,
    TenantSupplierField.address => address,
    TenantSupplierField.taxReference => taxReference,
    TenantSupplierField.notes => notes,
  };

  /// Every field normalized exactly as the server will store it, or a refusal
  /// naming the field that cannot be. Empty optional fields come back null.
  Map<TenantSupplierField, String?> normalized() =>
      <TenantSupplierField, String?>{
        for (final field in TenantSupplierField.values)
          field: normalizeSupplierField(field, raw(field)),
      };
}

/// One field, normalized as `functions/src/operations/suppliers.ts` normalizes
/// it, or a [TenantSupplierException] naming what is wrong.
///
/// The name is required and never comes back null; every other field comes back
/// null when it is empty.
String? normalizeSupplierField(TenantSupplierField field, String value) {
  switch (field) {
    case TenantSupplierField.name:
      final name = _singleLine(value);
      if (name.isEmpty ||
          name.length > maximumSupplierNameLength ||
          _hasControl(name)) {
        throw const TenantSupplierException('invalid_supplier_name');
      }
      return name;
    case TenantSupplierField.phone:
      final phone = _singleLine(value);
      if (phone.isEmpty) return null;
      if (phone.length > maximumSupplierPhoneLength ||
          !_phoneShape.hasMatch(phone)) {
        throw const TenantSupplierException('invalid_supplier_phone');
      }
      return phone;
    case TenantSupplierField.email:
      final email = _singleLine(value);
      if (email.isEmpty) return null;
      if (email.length > maximumSupplierEmailLength ||
          !_emailShape.hasMatch(email)) {
        throw const TenantSupplierException('invalid_supplier_email');
      }
      return email;
    case TenantSupplierField.address:
      final address = _singleLine(value);
      if (address.isEmpty) return null;
      if (address.length > maximumSupplierAddressLength ||
          _hasControl(address)) {
        throw const TenantSupplierException('invalid_supplier_address');
      }
      return address;
    case TenantSupplierField.taxReference:
      final reference = _singleLine(value);
      if (reference.isEmpty) return null;
      if (reference.length > maximumSupplierTaxReferenceLength ||
          _hasControl(reference)) {
        throw const TenantSupplierException('invalid_supplier_tax_reference');
      }
      return reference;
    case TenantSupplierField.notes:
      // Notes keep their line breaks, and nothing else unusual - the server's
      // `notesText`, step for step.
      final notes = value
          .replaceAll(RegExp(r'\r\n?'), '\n')
          .split('\n')
          .map((line) => line.trim().replaceAll(RegExp(r'[^\S\n]+'), ' '))
          .join('\n')
          .trim();
      if (notes.isEmpty) return null;
      if (notes.length > maximumSupplierNotesLength ||
          _hasControl(notes.replaceAll('\n', ''))) {
        throw const TenantSupplierException('invalid_supplier_notes');
      }
      return notes;
  }
}

/// A validated instruction to add exactly one supplier.
final class TenantSupplierCreateIntent {
  const TenantSupplierCreateIntent._({
    required this.path,
    required this.tenantId,
    required this.supplierId,
    required this.fields,
    required this.createdBy,
  });

  final String path;
  final String tenantId;
  final String supplierId;
  final Map<TenantSupplierField, String?> fields;
  final String createdBy;

  String get name => fields[TenantSupplierField.name]!;

  /// The document a device composes: what the overlay draws and what the queue
  /// replays. The server takes the actor from the request, not from here.
  Map<String, Object?> documentData() => <String, Object?>{
    for (final entry in fields.entries)
      if (entry.value != null) entry.key.wireKey: entry.value,
    'active': true,
    'createdBy': createdBy,
  };
}

/// A validated instruction to correct exactly one supplier.
///
/// It carries **only what moves**: a changed field, a cleared field as an
/// explicit null, and a change of standing. A correction that moves nothing is
/// refused before it is queued, because the server refuses it too.
final class TenantSupplierUpdateIntent {
  const TenantSupplierUpdateIntent._({
    required this.path,
    required this.tenantId,
    required this.supplierId,
    required this.changes,
    required this.active,
  });

  final String path;
  final String tenantId;
  final String supplierId;

  /// Every field that moves, and to what. A null value clears the field.
  final Map<TenantSupplierField, String?> changes;

  /// The new standing, or null when it is not changing.
  final bool? active;

  String? get name => changes[TenantSupplierField.name];

  Map<String, Object?> documentData() => <String, Object?>{
    for (final entry in changes.entries) entry.key.wireKey: entry.value,
    if (active != null) 'active': active,
  };

  /// One operation per distinct correction, so a second correction made before
  /// the first lands queues beside it rather than colliding with it.
  String get operationId =>
      'supplier-update-$supplierId-'
      '${tenantMutationFingerprint(documentData()).substring(0, 16)}';
}

/// Which suppliers a directory view shows.
enum TenantSupplierStanding {
  active('active', 'Active'),
  inactive('inactive', 'Inactive'),
  all('all', 'All suppliers');

  const TenantSupplierStanding(this.wireValue, this.label);

  final String wireValue;
  final String label;

  bool admits(TenantSupplier supplier) => switch (this) {
    TenantSupplierStanding.active => supplier.active,
    TenantSupplierStanding.inactive => !supplier.active,
    TenantSupplierStanding.all => true,
  };
}

/// Every supplier this business holds, read whole.
///
/// **Read whole rather than paged**, because the duplicate check is a question
/// about every name and the directory is bounded by the same figure the server
/// checks against. [truncated] says when a business holds more than that.
final class TenantSupplierDirectory {
  TenantSupplierDirectory({
    required List<TenantSupplier> suppliers,
    required this.truncated,
  }) : suppliers = List<TenantSupplier>.unmodifiable(
         List<TenantSupplier>.of(suppliers)..sort(_byName),
       );

  /// Sorted by folded name, so the list reads alphabetically whatever order
  /// the suppliers were added in.
  final List<TenantSupplier> suppliers;
  final bool truncated;

  List<TenantSupplier> get active =>
      suppliers.where((supplier) => supplier.active).toList(growable: false);

  TenantSupplier? byId(String id) {
    for (final supplier in suppliers) {
      if (supplier.id == id) return supplier;
    }
    return null;
  }

  /// The suppliers a view shows: those admitted by [standing] whose name
  /// contains [search], folded as names are compared.
  List<TenantSupplier> filtered({
    required TenantSupplierStanding standing,
    String search = '',
  }) {
    final needle = foldSupplierName(search);
    return <TenantSupplier>[
      for (final supplier in suppliers)
        if (standing.admits(supplier) &&
            (needle.isEmpty || supplier.foldedName.contains(needle)))
          supplier,
    ];
  }

  /// The supplier already answering to [name], other than [exceptId].
  TenantSupplier? holderOf(String name, {String? exceptId}) {
    final folded = foldSupplierName(name);
    for (final supplier in suppliers) {
      if (supplier.id != exceptId && supplier.foldedName == folded) {
        return supplier;
      }
    }
    return null;
  }

  static int _byName(TenantSupplier left, TenantSupplier right) {
    final byName = left.foldedName.compareTo(right.foldedName);
    return byName != 0 ? byName : left.id.compareTo(right.id);
  }
}

/// Reads one business's suppliers and builds the writes a form may send.
final class TenantSupplierRepository extends TenantReadRepository {
  TenantSupplierRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  final TenantCollectionReader _collectionReader;

  /// The roles that receive stock, which are the roles `createSupplier` and
  /// `updateSupplier` admit and the roles the rule lets read the directory.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  static bool canManageInSession(TenantSession session) =>
      session.canAccess(allowedRoles: allowedRoles);

  static const int _pageSize = 50;

  /// Every supplier, up to [maximumSupplierDirectory].
  Future<TenantSupplierDirectory> loadDirectory() async {
    _requireRole();
    final suppliers = <TenantSupplier>[];
    String? cursor;
    var truncated = false;
    while (true) {
      final page = await readCollectionPage(
        TenantCollection.suppliers,
        collectionReader: _collectionReader,
        pageSize: _pageSize,
        cursor: cursor,
      );
      for (final snapshot in page.items) {
        final supplier = TenantSupplier.fromSnapshot(snapshot);
        if (supplier.tenantId != session.tenantId) {
          throw const TenantSupplierException('cross_tenant_supplier');
        }
        suppliers.add(supplier);
      }
      if (!page.hasMore || page.nextCursor == null) break;
      if (suppliers.length >= maximumSupplierDirectory) {
        truncated = true;
        break;
      }
      cursor = page.nextCursor;
    }
    return TenantSupplierDirectory(suppliers: suppliers, truncated: truncated);
  }

  /// One supplier by its ID, or null when this business holds none by it.
  Future<TenantSupplier?> loadSupplier(String supplierId) async {
    _requireRole();
    final data = await readDocument(TenantCollection.suppliers, supplierId);
    if (data == null) return null;
    return TenantSupplier.fromDocument(
      path: paths.supplier(supplierId),
      data: data,
    );
  }

  /// Builds the one create the typed form describes.
  ///
  /// [directory] is the directory this form was opened over, so a name another
  /// supplier already answers to is refused here in the words the server would
  /// use, rather than after a queue drain.
  TenantSupplierCreateIntent buildCreateIntent({
    required TenantSupplierDraft draft,
    required TenantSupplierDirectory directory,
    required String requestId,
  }) {
    _requireRole();
    _requireRequestId(requestId);
    final fields = draft.normalized();
    if (directory.holderOf(fields[TenantSupplierField.name]!) != null) {
      throw const TenantSupplierException('duplicate_supplier_name');
    }
    final supplierId = _deterministicSupplierId(
      tenantId: session.tenantId,
      createdBy: session.uid,
      requestId: requestId,
    );
    return TenantSupplierCreateIntent._(
      path: paths.supplier(supplierId),
      tenantId: session.tenantId,
      supplierId: supplierId,
      fields: Map<TenantSupplierField, String?>.unmodifiable(fields),
      createdBy: session.uid,
    );
  }

  /// Builds the one correction the typed form describes, carrying only what
  /// moves.
  TenantSupplierUpdateIntent buildUpdateIntent({
    required TenantSupplier supplier,
    required TenantSupplierDraft draft,
    required TenantSupplierDirectory directory,
  }) {
    _requireRole();
    _requireOwned(supplier);
    final fields = draft.normalized();
    final changes = <TenantSupplierField, String?>{
      for (final entry in fields.entries)
        if (entry.value != supplier.valueOf(entry.key)) entry.key: entry.value,
    };
    if (changes.isEmpty) {
      throw const TenantSupplierException('supplier_unchanged');
    }
    final name = changes[TenantSupplierField.name];
    if (name != null &&
        directory.holderOf(name, exceptId: supplier.id) != null) {
      throw const TenantSupplierException('duplicate_supplier_name');
    }
    return TenantSupplierUpdateIntent._(
      path: paths.supplier(supplier.id),
      tenantId: session.tenantId,
      supplierId: supplier.id,
      changes: Map<TenantSupplierField, String?>.unmodifiable(changes),
      active: null,
    );
  }

  /// Marks [supplier] inactive, or offers it again.
  TenantSupplierUpdateIntent buildStandingIntent({
    required TenantSupplier supplier,
    required bool active,
  }) {
    _requireRole();
    _requireOwned(supplier);
    if (supplier.active == active) {
      throw const TenantSupplierException('supplier_unchanged');
    }
    return TenantSupplierUpdateIntent._(
      path: paths.supplier(supplier.id),
      tenantId: session.tenantId,
      supplierId: supplier.id,
      changes: const <TenantSupplierField, String?>{},
      active: active,
    );
  }

  void _requireRole() {
    if (!canManageInSession(session)) {
      throw const TenantSupplierException('supplier_forbidden');
    }
  }

  void _requireOwned(TenantSupplier supplier) {
    // A supplier decoded while another business was open can never be changed
    // from this one, even though both paths would be well-formed.
    if (supplier.tenantId != session.tenantId) {
      throw const TenantSupplierException('supplier_forbidden');
    }
  }
}

/// How a supplier write left this device.
final class TenantSupplierWriteResult {
  const TenantSupplierWriteResult.queued(this.operationId);

  /// The queued record, which is also what an undo would withdraw.
  final String operationId;
}

/// Where a supplier write is sent. The composition root supplies the queued
/// writer, so `lib/suppliers` keeps depending on `lib/tenancy` and not the
/// other way round.
abstract interface class TenantSupplierWriter {
  Future<TenantSupplierWriteResult> createSupplier(
    TenantSupplierCreateIntent intent,
  );

  Future<TenantSupplierWriteResult> updateSupplier(
    TenantSupplierUpdateIntent intent,
  );
}

/// A fresh request ID for one supplier create.
String secureTenantSupplierRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'supplier-${base64Url.encode(bytes).replaceAll('=', '')}';
}

String _deterministicSupplierId({
  required String tenantId,
  required String createdBy,
  required String requestId,
}) {
  final digest = sha256.convert(
    utf8.encode(
      <String>[
        'createTenantSupplier',
        tenantId,
        createdBy,
        requestId,
      ].join(' '),
    ),
  );
  return 'sp_${digest.toString().substring(0, 40)}';
}

void _requireRequestId(String requestId) {
  if (!_requestIdPattern.hasMatch(requestId)) {
    throw const TenantSupplierException('invalid_request_id');
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
final RegExp _phoneShape = RegExp(r'^[0-9+()\-. ]{3,}$');
final RegExp _emailShape = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
