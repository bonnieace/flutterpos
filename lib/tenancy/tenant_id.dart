import 'dart:convert';

const int _maximumFirestoreDocumentIdBytes = 1500;

/// Returns whether [value] is a safe, single Firestore document path segment.
bool isValidTenantId(Object? value) =>
    value is String && _isValidPathSegment(value);

/// Validates and returns [tenantId].
///
/// Tenant identifiers are document IDs, never paths. Rejecting separators and
/// control characters prevents a caller from escaping `tenants/{tenantId}`.
String validateTenantId(String tenantId) {
  if (!_isValidPathSegment(tenantId)) {
    throw ArgumentError.value(
      tenantId,
      'tenantId',
      'Must be a non-empty Firestore document ID without path separators, '
          'surrounding whitespace, or control characters.',
    );
  }
  return tenantId;
}

/// Validates a non-tenant document ID used by [TenantPaths].
String validateTenantDocumentId(String documentId, {String? fieldName}) {
  if (!_isValidPathSegment(documentId)) {
    throw ArgumentError.value(
      documentId,
      fieldName ?? 'documentId',
      'Must be a non-empty Firestore document ID without path separators, '
      'surrounding whitespace, or control characters.',
    );
  }
  return documentId;
}

bool _isValidPathSegment(String value) {
  if (value.isEmpty ||
      value != value.trim() ||
      value == '.' ||
      value == '..' ||
      value.contains('/') ||
      utf8.encode(value).length > _maximumFirestoreDocumentIdBytes) {
    return false;
  }

  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      return false;
    }
  }
  return true;
}
