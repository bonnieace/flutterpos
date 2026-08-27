/// What the business spent that no sale line accounts for.
///
/// **The gap this closes.** `aggregateSales` computes profit as revenue minus
/// the cost of the goods sold, and nothing else. Rent, wages, fuel, a licence
/// and a repair are invisible to it, so a shop can be losing money for a month
/// while every screen in this app reports a healthy margin. An expense is that
/// missing half, and `TenantNetProfitReport` is where the two meet.
///
/// **It is a record, not a setting.** An expense is money that left the
/// business, so it is written once and never edited: a mistake is voided, which
/// leaves both the original and the correction on the record. That is the same
/// treatment a sale and a return already get, for the same reason.
library;

import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../checkout/checkout_draft.dart';
import '../checkout/checkout_receipt.dart';
import '../checkout/checkout_sale.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';

/// Raised when an expense document cannot be trusted.
final class TenantExpenseException implements Exception {
  const TenantExpenseException(this.code);

  final String code;

  @override
  String toString() => 'TenantExpenseException($code)';
}

/// What an expense was for.
///
/// **A closed set, at the product owner's direction on 2026-08-27.** The
/// project this was carried across from took free text with a typeahead, and
/// paid for it twice: every keystroke read the whole collection to find the
/// distinct values, and nothing stopped one business spelling `Electricity`,
/// `electricity` and `Power` into three separate totals. A closed set costs a
/// release to extend and is worth it - a category is an axis every total on
/// every report is grouped by, and an axis whose values drift is not one.
///
/// [wireValue] is what Firestore stores and what the security rule enumerates.
/// It is deliberately not `name`, so renaming a constant here can never
/// silently orphan every record already written under the old spelling.
enum TenantExpenseCategory {
  rent('rent', 'Rent'),
  wages('wages', 'Wages'),
  utilities('utilities', 'Utilities'),
  transport('transport', 'Transport'),
  supplies('supplies', 'Supplies'),
  repairs('repairs', 'Repairs'),
  licences('licences', 'Licences'),

  /// Everything the list above does not name.
  ///
  /// **Last, and never the default.** A category chooser that opens on *Other*
  /// makes it the cheapest answer, and a report where most of the money is
  /// filed under *Other* tells its reader nothing at all.
  other('other', 'Other');

  const TenantExpenseCategory(this.wireValue, this.label);

  /// The value stored in Firestore and enumerated by the security rule.
  final String wireValue;

  /// What a person reads on screen.
  final String label;

  /// The stored value's category, or `null` where nothing recognises it.
  ///
  /// Null rather than [other]: a value this app does not model means something
  /// wrote a category nothing here recognises, and folding that into *Other*
  /// would report a data problem as an ordinary expense.
  static TenantExpenseCategory? fromWire(Object? value) {
    for (final category in values) {
      if (category.wireValue == value) return category;
    }
    return null;
  }
}

/// The document ID an expense recorded on [businessDate] is filed under.
///
/// **The business date leads, and that is load-bearing rather than tidy.**
/// `TenantReadRepository` orders every page by document ID and accepts only
/// equality filters - there is no range query reachable from a client
/// repository at all. Putting the date first makes ascending document-ID order
/// chronological order, which is what turns "every expense between these two
/// dates" into a cursor and a stop condition instead of one query per day.
///
/// [token] distinguishes two expenses recorded on the same day and must be
/// reused across a retry of the same intent, so a retry overwrites its own
/// record rather than filing a second one.
String tenantExpenseId(String businessDate, String token) {
  final date = validateCheckoutBusinessDate(businessDate);
  if (token.isEmpty || token.length > 64 || !_tokenPattern.hasMatch(token)) {
    throw ArgumentError.value(token, 'token', 'Expected a URL-safe token.');
  }
  return validateTenantDocumentId('$date-$token');
}

/// The business date an expense ID was filed under, or `null` if it carries no
/// usable one.
///
/// This is how a range read decides it has paged past the end of the period it
/// was asked for, so it reads the date out of the key rather than out of the
/// document: the key is what the ordering is on, and a document whose stored
/// `businessDate` disagreed with its own key would otherwise page forever.
String? tenantExpenseIdBusinessDate(String expenseId) {
  if (expenseId.length < _businessDateLength + 1) return null;
  final candidate = expenseId.substring(0, _businessDateLength);
  if (expenseId[_businessDateLength] != '-') return null;
  try {
    return validateCheckoutBusinessDate(candidate);
  } on ArgumentError {
    return null;
  }
}

/// A fresh token for one record intent.
///
/// The same value must be reused across a retry of that intent, and a new one
/// created only for a genuinely different expense. Modelled on
/// `secureTenantReturnRequestId`.
String secureTenantExpenseToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(12, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Strict read model for `tenants/{tenantId}/expenses/{expenseId}`.
final class TenantExpense {
  factory TenantExpense.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) {
    final segments = path.split('/');
    if (segments.length != 4 ||
        segments[0] != 'tenants' ||
        segments[2] != TenantCollection.expenses.segment) {
      throw const TenantExpenseException('invalid_expense_path');
    }
    final String tenantId;
    final String expenseId;
    try {
      tenantId = validateTenantId(segments[1]);
      expenseId = validateTenantDocumentId(segments[3]);
    } on ArgumentError {
      throw const TenantExpenseException('invalid_expense_path');
    }
    // The document repeats the identity its own path encodes, so a record can
    // never be presented under a business it does not belong to.
    if (data['tenantId'] != tenantId || data['expenseId'] != expenseId) {
      throw const TenantExpenseException('expense_identity_mismatch');
    }

    final businessDate = _requiredBusinessDate(data);
    // The key and the field must agree. They are written together and the range
    // read trusts the key, so a disagreement means this record would be counted
    // into a period it does not belong to.
    if (tenantExpenseIdBusinessDate(expenseId) != businessDate) {
      throw const TenantExpenseException('expense_identity_mismatch');
    }

    final category = TenantExpenseCategory.fromWire(data['category']);
    if (category == null) {
      throw const TenantExpenseException('unknown_expense_category');
    }

    final amountMinor = _requiredMinorAmount(data);
    // Both halves of the amount are stored, exactly as a closed shift stores
    // `totalSales` beside `totalSalesMinor`. Disagreement means something other
    // than this app's writer produced the document.
    if (checkoutMinorUnitsFromMajor(_requiredFiniteNumber(data, 'amount')) !=
        amountMinor) {
      throw const TenantExpenseException('inconsistent_expense_amount');
    }

    return TenantExpense._(
      tenantId: tenantId,
      expenseId: expenseId,
      businessDate: businessDate,
      category: category,
      description: _requiredDescription(data),
      amountMinor: amountMinor,
      recordedBy: _requiredUid(data, 'recordedBy'),
      createdAt: _requiredInstant(data, 'createdAt'),
      voidedAt: _optionalInstant(data, 'voidedAt'),
      voidedBy: data['voidedBy'] == null
          ? null
          : _requiredUid(data, 'voidedBy'),
      voidReason: data['voidReason'] == null
          ? null
          : _requiredDescription(data, field: 'voidReason'),
    );
  }

  const TenantExpense._({
    required this.tenantId,
    required this.expenseId,
    required this.businessDate,
    required this.category,
    required this.description,
    required this.amountMinor,
    required this.recordedBy,
    required this.createdAt,
    required this.voidedAt,
    required this.voidedBy,
    required this.voidReason,
  });

  final String tenantId;
  final String expenseId;
  final String businessDate;
  final TenantExpenseCategory category;
  final String description;

  /// The amount in whole minor units, which is the canonical figure.
  final int amountMinor;

  final String recordedBy;
  final DateTime createdAt;

  /// When this record was withdrawn, or `null` while it still counts.
  final DateTime? voidedAt;
  final String? voidedBy;
  final String? voidReason;

  /// Whether this record has been withdrawn and counts towards nothing.
  bool get isVoided => voidedAt != null;

  /// The amount in major units, for display only.
  double get amount => amountMinor / 100;
}

/// Every expense in one period, with the totals a report needs.
///
/// **[truncated] is the field that matters.** The range read is bounded, and a
/// period holding more expenses than the bound returns a total that is too
/// small - which makes net profit look *better* than it was. That is the exact
/// failure `TenantProfitBasis.incomplete` exists to refuse, so this reports the
/// shortfall rather than hiding it, and `TenantNetProfitReport` withholds the
/// figure when it is set.
final class TenantExpensePeriod {
  factory TenantExpensePeriod({
    required String startDate,
    required String endDate,
    required List<TenantExpense> records,
    required bool truncated,
  }) {
    var totalMinor = 0;
    final byCategory = <TenantExpenseCategory, int>{};
    for (final record in records) {
      // A voided record stays in [records] so the list can show it, and counts
      // towards nothing. It is money that did not leave the business.
      if (record.isVoided) continue;
      totalMinor += record.amountMinor;
      byCategory.update(
        record.category,
        (existing) => existing + record.amountMinor,
        ifAbsent: () => record.amountMinor,
      );
    }
    return TenantExpensePeriod._(
      startDate: startDate,
      endDate: endDate,
      records: List<TenantExpense>.unmodifiable(records),
      truncated: truncated,
      totalMinor: totalMinor,
      totalByCategory: Map<TenantExpenseCategory, int>.unmodifiable(byCategory),
    );
  }

  /// A period nothing was read for, so that a surface with no expense read
  /// wired to it has something to hold that is not `null`-shaped.
  factory TenantExpensePeriod.empty({
    required String startDate,
    required String endDate,
  }) => TenantExpensePeriod(
    startDate: startDate,
    endDate: endDate,
    records: const <TenantExpense>[],
    truncated: false,
  );

  const TenantExpensePeriod._({
    required this.startDate,
    required this.endDate,
    required this.records,
    required this.truncated,
    required this.totalMinor,
    required this.totalByCategory,
  });

  final String startDate;
  final String endDate;

  /// Every record read, newest first, voided ones included.
  final List<TenantExpense> records;

  /// Whether the read stopped at its bound before reaching [endDate].
  final bool truncated;

  /// What was spent in the period, in whole minor units, voided records
  /// excluded.
  final int totalMinor;

  final Map<TenantExpenseCategory, int> totalByCategory;

  double get total => totalMinor / 100;

  /// The categories that hold anything, largest first.
  ///
  /// A category with nothing in it is not a row of zero; it is a row that does
  /// not exist.
  List<TenantExpenseCategory> get spentCategories {
    final categories = totalByCategory.keys.toList()
      ..sort((a, b) {
        final byAmount = totalByCategory[b]!.compareTo(totalByCategory[a]!);
        // A stable tie-break, so two equal categories do not swap places
        // between two reads of the same period.
        return byAmount != 0 ? byAmount : a.index.compareTo(b.index);
      });
    return List<TenantExpenseCategory>.unmodifiable(categories);
  }

  /// Just one of this period's business dates, as a period of its own.
  ///
  /// Lets a surface listing several days read the whole span once and split it,
  /// rather than issuing one query per day.
  ///
  /// **[truncated] travels with the slice.** A read that stopped early may have
  /// dropped records belonging to any date in the span, so no day cut out of an
  /// incomplete read can claim to be complete itself.
  TenantExpensePeriod forDate(String businessDate) => TenantExpensePeriod(
    startDate: businessDate,
    endDate: businessDate,
    records: <TenantExpense>[
      for (final record in records)
        if (record.businessDate == businessDate) record,
    ],
    truncated: truncated,
  );

  /// [category]'s share of [totalMinor], between 0 and 1, or `null` when there
  /// is no total to take a share of.
  ///
  /// Null rather than zero for an empty period, for the reason
  /// `TenantProfitReport.marginPercent` is null on takings of nothing: a share
  /// of no spending is a division by zero, not a share of nothing.
  double? shareOf(TenantExpenseCategory category) {
    if (totalMinor <= 0) return null;
    return (totalByCategory[category] ?? 0) / totalMinor;
  }
}

final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9_-]+$');

/// `yyyy-MM-dd`.
const int _businessDateLength = 10;

String _requiredBusinessDate(Map<String, Object?> data) {
  final value = data['businessDate'];
  if (value is! String) {
    throw const TenantExpenseException('invalid_expense_document');
  }
  try {
    return validateCheckoutBusinessDate(value);
  } on ArgumentError {
    throw const TenantExpenseException('invalid_expense_document');
  }
}

int _requiredMinorAmount(Map<String, Object?> data) {
  final value = data['amountMinor'];
  // Zero is refused as well as negative: an expense of nothing is not a thing
  // that happened, and recording one would put a row on a report that no money
  // corresponds to.
  if (value is! int || value <= 0 || value > maximumCheckoutMinorAmount) {
    throw const TenantExpenseException('invalid_expense_document');
  }
  return value;
}

double _requiredFiniteNumber(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! num || !value.isFinite) {
    throw const TenantExpenseException('invalid_expense_document');
  }
  return value.toDouble();
}

String _requiredDescription(
  Map<String, Object?> data, {
  String field = 'description',
}) {
  final value = data[field];
  if (value is! String || value.trim().length < 3 || value.length > 500) {
    throw const TenantExpenseException('invalid_expense_document');
  }
  return value;
}

String _requiredUid(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String || value.isEmpty || value.length > 128) {
    throw const TenantExpenseException('invalid_expense_document');
  }
  return value;
}

DateTime _requiredInstant(Map<String, Object?> data, String field) {
  final value = _optionalInstant(data, field);
  if (value == null) {
    throw const TenantExpenseException('invalid_expense_document');
  }
  return value;
}

DateTime? _optionalInstant(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  throw const TenantExpenseException('invalid_expense_document');
}
