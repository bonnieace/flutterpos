import 'tenant_id.dart';
import 'tenant_paths.dart';
import 'tenant_repository.dart';

/// A bounded page paired with the staff display names it needs.
final class TenantNamedPage<T> {
  const TenantNamedPage({required this.page, required this.names});

  final T page;

  /// Resolved display names by UID. A UID that could not be resolved is
  /// deliberately absent rather than guessed.
  final Map<String, String> names;
}

/// Resolves canonical staff display names for the UIDs shown on one page.
///
/// This is the one repository that does **not** fail a page closed. A display
/// name is a convenience label; the UID beside it is the authoritative
/// identity, so an unreadable, missing, or malformed staff record degrades to
/// the UID rather than hiding a page of financial evidence. A transport that
/// answers outside this tenant is still refused, because that is a broken
/// boundary rather than an unavailable label.
final class TenantStaffNameResolver extends TenantReadRepository {
  TenantStaffNameResolver({required super.session, required super.reader});

  /// The most staff documents one page may resolve.
  ///
  /// A page is bounded, but its cashiers are not necessarily few. Reading a
  /// document per row is the cost of a label, so it is capped and the remainder
  /// simply shows UIDs.
  static const int maximumResolvedUids = 25;

  final Map<String, String?> _cache = <String, String?>{};

  /// Resolves [uids] in order, reusing anything already resolved.
  Future<Map<String, String>> resolve(Iterable<String> uids) async {
    final requested = <String>{};
    for (final uid in uids) {
      try {
        requested.add(validateTenantDocumentId(uid, fieldName: 'uid'));
      } on ArgumentError {
        // Never produced by a validated read model; it simply has no name.
        continue;
      }
    }

    var lookups = 0;
    for (final uid in requested) {
      if (_cache.containsKey(uid)) continue;
      if (lookups >= maximumResolvedUids) break;
      lookups++;
      _cache[uid] = await _readDisplayName(uid);
    }

    return <String, String>{
      for (final uid in requested)
        if (_cache[uid] case final name?) uid: name,
    };
  }

  Future<String?> _readDisplayName(String uid) async {
    final Map<String, Object?>? data;
    try {
      data = await readDocument(TenantCollection.staff, uid);
    } on TenantScopeViolation {
      rethrow;
    } catch (_) {
      // A denied or unavailable read is expected: the staff record may be
      // outside what this role may see. The caller falls back to the UID.
      return null;
    }
    if (data == null) return null;
    // The canonical record must name the UID its own path names, exactly as
    // the staff directory requires, or it describes somebody else.
    if (data['uid'] != uid) return null;
    return _displayName(data['name']);
  }

  /// Only the explicit name is used. The staff record also carries an email and
  /// a phone number, and a history row is not the place to disclose either.
  static String? _displayName(Object? value) {
    if (value is! String) return null;
    final name = value.trim();
    if (name.isEmpty || name.length > 120) return null;
    for (final codeUnit in name.codeUnits) {
      if (codeUnit < 0x20 || codeUnit == 0x7f) return null;
    }
    return name;
  }
}

/// The label shown for a cashier UID.
///
/// The UID stays visible whenever a name is resolved: it is the identity every
/// other record - sale, shift, audit - is attributed by.
String tenantStaffLabel(
  String uid, {
  required Map<String, String> names,
  String? selfUid,
  String selfLabel = 'You',
}) {
  final name = names[uid];
  if (uid == selfUid) return name == null ? selfLabel : '$selfLabel ($name)';
  return name == null ? uid : '$name ($uid)';
}
