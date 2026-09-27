/// A fortnight of the audit trail, for the logs report's tests and samples.
///
/// Shaped like a real business rather than like tidy test data: one member
/// makes most of the changes, the platform acts on the business twice, one of
/// those is a critical alert, and one event is of a kind this client has no
/// name for yet. Those are the cases the report has something to say about.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uzapay_pos/audit/audit_log.dart';
import 'package:uzapay_pos/reports/analysis/logs_analysis.dart';
import 'package:uzapay_pos/reports/report_period.dart';

TenantAuditRecord auditRecord({
  required String id,
  required String eventType,
  required DateTime at,
  String? actorUid,
  String? actorType,
  String? targetUid,
  bool critical = false,
}) => TenantAuditRecord.fromDocument(
  path: 'tenants/tenant-a/audit_logs/$id',
  data: <String, Object?>{
    'tenantId': 'tenant-a',
    'eventType': eventType,
    if (actorUid != null) 'actorUid': actorUid,
    if (actorType != null) 'actorType': actorType,
    if (targetUid != null) 'targetUid': targetUid,
    if (critical) 'severity': 'critical',
    'createdAt': Timestamp.fromDate(at),
  },
);

/// The first fortnight of September.
TenantReportPeriod fixtureLogsPeriod() =>
    TenantReportPeriod(startDate: '2026-09-01', endDate: '2026-09-14');

List<TenantAuditRecord> fixtureLogs() => <TenantAuditRecord>[
  auditRecord(
    id: 'aud-1',
    eventType: 'stock_adjusted',
    at: DateTime.utc(2026, 9, 2, 8),
    actorUid: 'manager-a',
  ),
  auditRecord(
    id: 'aud-2',
    eventType: 'stock_adjusted',
    at: DateTime.utc(2026, 9, 4, 9),
    actorUid: 'manager-a',
  ),
  auditRecord(
    id: 'aud-3',
    eventType: 'stock_adjusted',
    at: DateTime.utc(2026, 9, 5, 11),
    actorUid: 'manager-a',
  ),
  auditRecord(
    id: 'aud-4',
    eventType: 'staff_invited',
    at: DateTime.utc(2026, 9, 5, 14),
    actorUid: 'owner-a',
    targetUid: 'cashier-c',
  ),
  auditRecord(
    id: 'aud-5',
    eventType: 'return_verified_stock_restored',
    at: DateTime.utc(2026, 9, 9, 16),
    actorUid: 'manager-a',
  ),
  // The platform acting on the business, and the one worth answering.
  auditRecord(
    id: 'aud-6',
    eventType: 'no_active_administrator',
    at: DateTime.utc(2026, 9, 11, 3),
    actorType: 'platform',
    critical: true,
  ),
  auditRecord(
    id: 'aud-7',
    eventType: 'tenant_lifecycle_changed',
    at: DateTime.utc(2026, 9, 11, 4),
    actorType: 'platform_admin',
  ),
  // A kind this client does not model yet.
  auditRecord(
    id: 'aud-8',
    eventType: 'price_list_published',
    at: DateTime.utc(2026, 9, 13, 10),
    actorUid: 'owner-a',
  ),
];

TenantLogsAnalysis fixtureLogsAnalysis({
  List<TenantAuditRecord>? previous,
  bool truncated = false,
}) => TenantLogsAnalysis.from(
  period: fixtureLogsPeriod(),
  records: fixtureLogs(),
  previous: previous,
  truncated: truncated,
);
