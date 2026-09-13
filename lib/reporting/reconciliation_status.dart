import 'package:cloud_firestore/cloud_firestore.dart';

import '../checkout/checkout_receipt.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';

/// Raised when a reconciliation record cannot be trusted or read.
final class TenantReconciliationException implements Exception {
  const TenantReconciliationException(this.code);

  final String code;

  @override
  String toString() => 'TenantReconciliationException($code)';
}

/// What the server's own intake record says about one business day.
///
/// `functions/src/reconciliation/**` is the only writer. A sale trigger marks
/// the day `dirty`, the metrics processor marks it `clean` once it has
/// regenerated `daily_metrics` for that exact revision, and a day whose
/// revision could not be read at all is `quarantined`.
enum TenantReconciliationIntakeStatus {
  /// Sales have been received that the published totals do not include yet.
  dirty('dirty', 'Waiting to be regenerated'),

  /// The published totals were regenerated from the sales recorded so far.
  clean('clean', 'Regenerated'),

  /// The server stopped working on this day and recorded why.
  quarantined('quarantined', 'Stopped'),

  /// Any status this client does not model. It carries no wire value; a surface
  /// shows the recorded value verbatim rather than hiding the day.
  other('', 'Unrecognised');

  const TenantReconciliationIntakeStatus(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static TenantReconciliationIntakeStatus parse(String value) {
    for (final status in values) {
      if (status != other && status.wireValue == value) return status;
    }
    return other;
  }
}

/// What asked the server to reconcile.
enum TenantReconciliationRunSource {
  manual('manual', 'Requested by a person'),
  saleTrigger('sale_trigger', 'Triggered by a sale'),
  nightly('nightly', 'Nightly sweep'),
  weekly('weekly', 'Weekly sweep'),
  monthly('monthly', 'Monthly full check'),
  other('', 'Other source');

  const TenantReconciliationRunSource(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static TenantReconciliationRunSource parse(String value) {
    for (final source in values) {
      if (source != other && source.wireValue == value) return source;
    }
    return other;
  }
}

/// Where one run stands.
enum TenantReconciliationRunStatus {
  queued('queued', 'Queued'),
  running('running', 'Running'),
  failed('failed', 'Failed, retry scheduled'),
  completed('completed', 'Completed'),
  quarantined('quarantined', 'Stopped after repeated failures'),
  other('', 'Unrecognised');

  const TenantReconciliationRunStatus(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static TenantReconciliationRunStatus parse(String value) {
    for (final status in values) {
      if (status != other && status.wireValue == value) return status;
    }
    return other;
  }

  /// Whether the server still intends to do more work for this run.
  bool get isOutstanding => this == queued || this == running;
}

/// Which part of the work one run reached.
enum TenantReconciliationRunPhase {
  metrics('metrics', 'Daily totals'),
  stock('stock', 'Stock checkpoints'),
  shifts('shifts', 'Shift verification'),
  finalize('finalize', 'Finishing'),
  other('', 'Unrecognised');

  const TenantReconciliationRunPhase(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static TenantReconciliationRunPhase parse(String value) {
    for (final phase in values) {
      if (phase != other && phase.wireValue == value) return phase;
    }
    return other;
  }
}

/// Strict read model for
/// `tenants/{tenantId}/reconciliation_dirty_days/{businessDate}`.
///
/// This is the one authority on whether a business day's published totals are
/// current. A run is not: `processMetricsPage` takes the oldest outstanding day
/// in the whole business rather than the day the run was queued for, so a
/// completed run does **not** mean the day it names was regenerated. Presenting
/// a list of runs as a per-day verdict would be exactly that mistake.
final class TenantReconciliationIntake {
  factory TenantReconciliationIntake.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) {
    final segments = path.split('/');
    if (segments.length != 4 ||
        segments[0] != 'tenants' ||
        segments[2] != TenantCollection.reconciliationDirtyDays.segment) {
      throw const TenantReconciliationException('invalid_intake_path');
    }
    final String tenantId;
    final String businessDate;
    try {
      tenantId = validateTenantId(segments[1]);
      businessDate = validateCheckoutBusinessDate(segments[3]);
    } on ArgumentError {
      throw const TenantReconciliationException('invalid_intake_path');
    }
    // The document repeats the identity its own path encodes, so an intake
    // record can never be presented under a day or a business it does not
    // describe.
    if (data['tenantId'] != tenantId || data['businessDate'] != businessDate) {
      throw const TenantReconciliationException('intake_identity_mismatch');
    }

    final rawStatus = _requiredString(data, 'status');
    final status = TenantReconciliationIntakeStatus.parse(rawStatus);
    final revision = _requiredCount(data, 'revision');
    final processedRevision = _optionalCount(data, 'processedRevision');
    final lastErrorCode = _optionalString(data, 'lastErrorCode');
    // The processor writes `clean`, `processedRevision`, and the generation it
    // published in one transaction, and a later sale moves the day back to
    // `dirty` with a higher revision. A day that claims to be regenerated but
    // cannot say which revision it published, or names one the day never
    // reached, contradicts the only writer it can have had.
    if (status == TenantReconciliationIntakeStatus.clean &&
        processedRevision != revision) {
      throw const TenantReconciliationException('inconsistent_intake_record');
    }
    if (processedRevision != null && processedRevision > revision) {
      throw const TenantReconciliationException('inconsistent_intake_record');
    }
    // Quarantine is only ever written together with the code that caused it.
    if (status == TenantReconciliationIntakeStatus.quarantined &&
        lastErrorCode == null) {
      throw const TenantReconciliationException('inconsistent_intake_record');
    }

    return TenantReconciliationIntake._(
      tenantId: tenantId,
      businessDate: businessDate,
      statusValue: rawStatus,
      status: status,
      revision: revision,
      processedRevision: processedRevision,
      saleReceiptCount: _optionalCount(data, 'saleReceiptCount') ?? 0,
      invalidLineCount: _optionalCount(data, 'invalidLineCount') ?? 0,
      dirtyReason: _optionalString(data, 'dirtyReason'),
      lastErrorCode: lastErrorCode,
      metricGeneration: _optionalString(data, 'metricGeneration'),
      lastReceiptAt: _optionalInstant(data, 'lastReceiptAt'),
      processedAt: _optionalInstant(data, 'processedAt'),
      updatedAt: _optionalInstant(data, 'updatedAt'),
    );
  }

  const TenantReconciliationIntake._({
    required this.tenantId,
    required this.businessDate,
    required this.statusValue,
    required this.status,
    required this.revision,
    required this.processedRevision,
    required this.saleReceiptCount,
    required this.invalidLineCount,
    required this.dirtyReason,
    required this.lastErrorCode,
    required this.metricGeneration,
    required this.lastReceiptAt,
    required this.processedAt,
    required this.updatedAt,
  });

  final String tenantId;
  final String businessDate;

  /// The raw status, kept so an unmodelled one can be shown as itself.
  final String statusValue;
  final TenantReconciliationIntakeStatus status;

  /// How many times the day's sales have changed what needs regenerating.
  final int revision;

  /// The revision the published totals were generated from, when the day has
  /// been processed at least once.
  final int? processedRevision;

  /// How many sale receipts the server registered for this day.
  final int saleReceiptCount;

  /// How many sale lines the server could not use. These are the lines a profit
  /// figure and a stock movement are missing for.
  final int invalidLineCount;

  /// Why a full check marked the day for regeneration, when one did.
  final String? dirtyReason;

  /// Why the server stopped, on a quarantined day.
  final String? lastErrorCode;

  /// The generation of `daily_metrics` this day last published.
  final String? metricGeneration;

  final DateTime? lastReceiptAt;
  final DateTime? processedAt;
  final DateTime? updatedAt;

  /// Whether sales have been received that the published totals do not cover.
  bool get hasUnpublishedSales => processedRevision != revision;

  bool get hasInvalidSaleLines => invalidLineCount > 0;
}

/// Strict read model for
/// `tenants/{tenantId}/reconciliation_jobs/{jobId}`.
///
/// A run is the unit of server work, not a verdict about a day: see
/// [TenantReconciliationIntake]. It explains what was attempted, how far it
/// got, how many times it has been retried, and the error code it last
/// recorded. Only reconciliation workers write it, and the client can never
/// queue, retry, or cancel one.
final class TenantReconciliationRun {
  factory TenantReconciliationRun.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) {
    final segments = path.split('/');
    if (segments.length != 4 ||
        segments[0] != 'tenants' ||
        segments[2] != TenantCollection.reconciliationJobs.segment) {
      throw const TenantReconciliationException('invalid_run_path');
    }
    final String tenantId;
    final String jobId;
    try {
      tenantId = validateTenantId(segments[1]);
      jobId = validateTenantDocumentId(segments[3], fieldName: 'jobId');
    } on ArgumentError {
      throw const TenantReconciliationException('invalid_run_path');
    }
    // A run does not repeat its own ID - the workers address it by the digest
    // or the five-minute bucket it belongs to - so its path is the one
    // authority on which run it is. The business it names must still agree.
    if (data['tenantId'] != tenantId) {
      throw const TenantReconciliationException('run_identity_mismatch');
    }

    final String businessDate;
    try {
      businessDate = validateCheckoutBusinessDate(
        _requiredString(data, 'localDate'),
      );
    } on ArgumentError {
      throw const TenantReconciliationException('invalid_run_document');
    }

    final rawStatus = _requiredString(data, 'status');
    final status = TenantReconciliationRunStatus.parse(rawStatus);
    final rawPhase = _requiredString(data, 'phase');
    final phase = TenantReconciliationRunPhase.parse(rawPhase);
    final completedAt = _optionalInstant(data, 'completedAt');
    final consecutiveFailureCount = _requiredCount(
      data,
      'consecutiveFailureCount',
    );
    final lastErrorCode = _optionalString(data, 'lastErrorCode');
    // `finalizeReconciliationJob` writes the terminal status, the finishing
    // phase, and the completion instant in one transaction, so a run that
    // claims to have completed without either contradicts its only writer.
    if (status == TenantReconciliationRunStatus.completed &&
        (phase != TenantReconciliationRunPhase.finalize ||
            completedAt == null)) {
      throw const TenantReconciliationException('inconsistent_run_record');
    }
    // `recordReconciliationFailure` is the only writer of `failed`, and it
    // always increments the count and records the code that caused it.
    // `quarantined` is deliberately not checked the same way: a malformed run
    // is quarantined by the retry sweep without touching the count.
    if (status == TenantReconciliationRunStatus.failed &&
        (consecutiveFailureCount < 1 || lastErrorCode == null)) {
      throw const TenantReconciliationException('inconsistent_run_record');
    }
    if (status == TenantReconciliationRunStatus.quarantined &&
        lastErrorCode == null) {
      throw const TenantReconciliationException('inconsistent_run_record');
    }

    final requestedBy = _requiredString(data, 'requestedBy');
    return TenantReconciliationRun._(
      id: jobId,
      tenantId: tenantId,
      businessDate: businessDate,
      sourceValue: _requiredString(data, 'source'),
      source: TenantReconciliationRunSource.parse(
        _requiredString(data, 'source'),
      ),
      mode: _requiredString(data, 'mode'),
      statusValue: rawStatus,
      status: status,
      phaseValue: rawPhase,
      phase: phase,
      requestedBy: requestedBy,
      actorUid: _actorUid(requestedBy),
      attemptCount: _requiredCount(data, 'attemptCount'),
      consecutiveFailureCount: consecutiveFailureCount,
      rerunRequested: data['rerunRequested'] == true,
      metricsProcessed: _requiredCount(data, 'metricsProcessed'),
      productsProcessed: _requiredCount(data, 'productsProcessed'),
      stockVarianceCount: _requiredCount(data, 'stockVarianceCount'),
      shiftsProcessed: _requiredCount(data, 'shiftsProcessed'),
      shiftVarianceCount: _requiredCount(data, 'shiftVarianceCount'),
      // Absent on every run recorded before the declaration existed, which
      // reads correctly as none found rather than as an unreadable run.
      tenderVarianceCount: _optionalCount(data, 'tenderVarianceCount') ?? 0,
      lastErrorCode: lastErrorCode,
      completedAt: completedAt,
      lastFailedAt: _optionalInstant(data, 'lastFailedAt'),
      updatedAt: _optionalInstant(data, 'updatedAt'),
    );
  }

  const TenantReconciliationRun._({
    required this.id,
    required this.tenantId,
    required this.businessDate,
    required this.sourceValue,
    required this.source,
    required this.mode,
    required this.statusValue,
    required this.status,
    required this.phaseValue,
    required this.phase,
    required this.requestedBy,
    required this.actorUid,
    required this.attemptCount,
    required this.consecutiveFailureCount,
    required this.rerunRequested,
    required this.metricsProcessed,
    required this.productsProcessed,
    required this.stockVarianceCount,
    required this.shiftsProcessed,
    required this.shiftVarianceCount,
    required this.tenderVarianceCount,
    required this.lastErrorCode,
    required this.completedAt,
    required this.lastFailedAt,
    required this.updatedAt,
  });

  final String id;
  final String tenantId;

  /// The business day this run was queued for.
  final String businessDate;

  /// The raw source, kept so an unmodelled one can be shown as itself.
  final String sourceValue;
  final TenantReconciliationRunSource source;

  /// `incremental` or `full` today, shown verbatim when it is neither.
  final String mode;

  final String statusValue;
  final TenantReconciliationRunStatus status;
  final String phaseValue;
  final TenantReconciliationRunPhase phase;

  /// Who or what asked for the run: a member's UID, or a `system:` actor.
  final String requestedBy;

  /// The member who asked for the run, when a member did. A scheduled sweep and
  /// a sale trigger name no person, and attributing one to a colleague would be
  /// a fiction.
  final String? actorUid;

  final int attemptCount;
  final int consecutiveFailureCount;

  /// Whether a change arrived while this run was working, so the server will
  /// run it again rather than publish a stale result.
  final bool rerunRequested;

  final int metricsProcessed;
  final int productsProcessed;

  /// Products whose counted stock disagreed with the ledger.
  final int stockVarianceCount;

  final int shiftsProcessed;

  /// Shifts whose closing summary disagreed with the sales recorded against it.
  final int shiftVarianceCount;

  /// Shifts whose declared takings disagree with what their sales derive.
  final int tenderVarianceCount;

  /// The error code the last failure recorded, kept exactly as the server wrote
  /// it. It is a server code rather than a sentence, and it is shown as one.
  final String? lastErrorCode;

  final DateTime? completedAt;
  final DateTime? lastFailedAt;
  final DateTime? updatedAt;

  bool get isOutstanding => status.isOutstanding;

  bool get hasVariances =>
      stockVarianceCount > 0 ||
      shiftVarianceCount > 0 ||
      tenderVarianceCount > 0;
}

/// One bounded page of the runs queued for one business day.
final class TenantReconciliationRunPage {
  TenantReconciliationRunPage({
    required List<TenantReconciliationRun> items,
    required this.nextCursor,
    required this.hasMore,
    required this.businessDate,
  }) : items = List<TenantReconciliationRun>.unmodifiable(items);

  final List<TenantReconciliationRun> items;
  final String? nextCursor;
  final bool hasMore;

  /// The exact business day every run on this page was queued for.
  final String businessDate;
}

/// What the server's intake record says about a business day as a whole.
enum TenantReconciliationDayOutcome {
  /// No sale ever reached the server for this day, so there is nothing to
  /// regenerate. This is the normal state of a day the business did not trade.
  noSalesRecorded,

  /// Sales are recorded that the published totals do not cover yet.
  awaitingRegeneration,

  /// The published totals cover every sale the server has for this day.
  regenerated,

  /// The server stopped working on this day and recorded why.
  blocked,

  /// The intake record carries a status this client does not model.
  unrecognised,
}

/// One business day's reconciliation state: the server's own verdict, plus a
/// bounded page of the runs that worked on it.
final class TenantReconciliationDay {
  const TenantReconciliationDay({
    required this.businessDate,
    required this.intake,
    required this.runs,
  });

  final String businessDate;

  /// Absent when no sale has ever been registered for this day.
  final TenantReconciliationIntake? intake;

  final TenantReconciliationRunPage runs;

  TenantReconciliationDayOutcome get outcome {
    final record = intake;
    if (record == null) return TenantReconciliationDayOutcome.noSalesRecorded;
    return switch (record.status) {
      TenantReconciliationIntakeStatus.dirty =>
        TenantReconciliationDayOutcome.awaitingRegeneration,
      TenantReconciliationIntakeStatus.clean =>
        TenantReconciliationDayOutcome.regenerated,
      TenantReconciliationIntakeStatus.quarantined =>
        TenantReconciliationDayOutcome.blocked,
      TenantReconciliationIntakeStatus.other =>
        TenantReconciliationDayOutcome.unrecognised,
    };
  }
}

/// Guarded read boundary over one tenant's reconciliation state.
///
/// The daily summary already answers "was this day reconciled". This answers
/// "why", and deliberately does not answer the first question a second time:
/// the verdict comes from the server's own intake record for that exact day,
/// and the runs beside it are evidence of the work, not a second verdict.
///
/// Every path is derived from the session's [TenantPaths] and the exact-child,
/// uniqueness, page-size, and ordering proofs of [TenantReadRepository] still
/// apply. No caller can supply a collection path, an ordering, or a raw filter.
/// How many recorded differences this business has not settled.
///
/// **A counter, because the records themselves cannot be counted cheaply.**
/// Anomaly documents are addressed by a digest of what they are about, so the
/// collection has no order and no index; a launcher that wanted a number from
/// it would have to list it on every entry. The server recomputes this in the
/// finalize phase of every completed run, and the two callables that settle a
/// difference adjust it so the figure moves when a person acts rather than at
/// the next nightly sweep.
final class TenantReconciliationOpenDifferences {
  const TenantReconciliationOpenDifferences._({
    required this.tenantId,
    required this.openCount,
    required this.truncated,
    required this.byType,
    required this.countedAt,
  });

  /// The one document this lives at. It is a single figure about the business,
  /// so there is nothing to address it by.
  static const String documentId = 'open_differences';

  factory TenantReconciliationOpenDifferences.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) {
    final segments = path.split('/');
    if (segments.length != 4 ||
        segments[0] != 'tenants' ||
        segments[2] != TenantCollection.reconciliationSummary.segment ||
        segments[3] != documentId) {
      throw const TenantReconciliationException('invalid_summary_path');
    }
    final String tenantId;
    try {
      tenantId = validateTenantId(segments[1]);
    } on ArgumentError {
      throw const TenantReconciliationException('invalid_summary_path');
    }
    if (data['tenantId'] != tenantId) {
      throw const TenantReconciliationException('summary_identity_mismatch');
    }
    final byType = <String, int>{};
    if (data['byType'] case final Map<Object?, Object?> counts) {
      for (final entry in counts.entries) {
        final kind = entry.key;
        final count = entry.value;
        if (kind is! String || count is! int || count < 0) {
          throw const TenantReconciliationException(
            'invalid_reconciliation_field',
          );
        }
        byType[kind] = count;
      }
    }
    return TenantReconciliationOpenDifferences._(
      tenantId: tenantId,
      // **Clamped, not refused.** The recount is the authority and the two
      // callables only nudge it, so a decrement that races a recount can leave
      // this briefly below zero. That is a stale figure rather than a corrupt
      // one, and it repairs itself on the next completed run.
      openCount: _requiredCount(data, 'openCount').clamp(0, _maximumCount),
      truncated: data['truncated'] == true,
      byType: Map<String, int>.unmodifiable(byType),
      countedAt: _optionalInstant(data, 'countedAt'),
    );
  }

  final String tenantId;

  /// How many were open when this was counted.
  final int openCount;

  /// Whether the scan stopped before the end of the collection, so [openCount]
  /// is *at least* this rather than exactly it.
  final bool truncated;

  /// The same figure broken down by kind, for a surface that can use it.
  final Map<String, int> byType;

  final DateTime? countedAt;

  bool get hasOpenDifferences => openCount > 0;
}

final class TenantReconciliationStatusRepository extends TenantReadRepository {
  TenantReconciliationStatusRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  /// The same roles that read the daily summary this surface explains. A
  /// cashier does not read business-wide revenue, so a cashier does not read
  /// why business-wide revenue is what it is either.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  final TenantCollectionReader _collectionReader;

  static bool canReadInSession(TenantSession session) =>
      session.canAccess(allowedRoles: allowedRoles);

  /// Reads one exact business day's reconciliation state.
  ///
  /// The intake record is read by exact document path, because its ID **is**
  /// the business date and a query cannot return a day that has no record yet -
  /// which is exactly the answer "no sale reached the server for this day".
  Future<TenantReconciliationDay> loadDay(
    String businessDate, {
    int pageSize = 20,
    String? cursor,
  }) async {
    if (!canReadInSession(session)) {
      throw const TenantReconciliationException('reconciliation_forbidden');
    }
    final safeDate = _validatedBusinessDate(businessDate);
    return TenantReconciliationDay(
      businessDate: safeDate,
      intake: await _readIntake(safeDate),
      runs: await _loadRuns(
        businessDate: safeDate,
        pageSize: pageSize,
        cursor: cursor,
      ),
    );
  }

  /// Reads one exact run by its own ID.
  ///
  /// Every difference this business records names the run that found it, and
  /// until this existed there was no way to ask anything about that run: the day
  /// page is reached by business date, and a difference carries a product or a
  /// shift rather than a date. A run is addressed by an exact document path for
  /// the same reason the intake record is - its ID is the answer, and a query
  /// cannot distinguish "no such run" from "a run this session may not read".
  ///
  /// Null is a real answer. A run is not immutable and nothing in this app
  /// deletes one, but a difference outlives the retention of anything else, so a
  /// caller has to be able to say the run is no longer there.
  Future<TenantReconciliationRun?> readRun(String jobId) async {
    if (!canReadInSession(session)) {
      throw const TenantReconciliationException('reconciliation_forbidden');
    }
    final String safeJobId;
    try {
      safeJobId = validateTenantDocumentId(jobId, fieldName: 'jobId');
    } on ArgumentError {
      throw const TenantReconciliationException('invalid_run_id');
    }
    final data = await readDocument(
      TenantCollection.reconciliationJobs,
      safeJobId,
    );
    if (data == null) return null;
    final run = TenantReconciliationRun.fromDocument(
      path: paths.reconciliationJob(safeJobId),
      data: data,
    );
    // The last of three agreeing proofs, and the only one a caller could break:
    // `readDocument` refuses a snapshot returned at any other path, and
    // `fromDocument` refuses a document naming another business at this one. This
    // is what would still catch a foreign run if the path above ever stopped
    // being derived from the session, which is the same reason `_readIntake`
    // keeps its own.
    if (run.tenantId != session.tenantId) {
      throw const TenantReconciliationException('cross_tenant_run');
    }
    return run;
  }

  String _validatedBusinessDate(String businessDate) {
    try {
      return validateCheckoutBusinessDate(businessDate);
    } on ArgumentError {
      throw const TenantReconciliationException('invalid_business_date');
    }
  }

  /// How many recorded differences are still open, or null if never counted.
  ///
  /// **One document, read by exact path.** The differences themselves are keyed
  /// by digest, so counting them from here would mean listing the collection -
  /// which a launcher deciding whether to draw a badge must not pay for. The
  /// server recomputes this at the end of every completed run.
  ///
  /// Null means no run has ever finished for this business, which reads as *no
  /// differences have been recorded* rather than as zero. A screen must be able
  /// to tell those apart: one is a clean shop and the other is an unanswered
  /// question.
  Future<TenantReconciliationOpenDifferences?> readOpenDifferences() async {
    final data = await readDocument(
      TenantCollection.reconciliationSummary,
      TenantReconciliationOpenDifferences.documentId,
    );
    if (data == null) return null;
    return TenantReconciliationOpenDifferences.fromDocument(
      path: paths.documentPath(
        TenantCollection.reconciliationSummary,
        TenantReconciliationOpenDifferences.documentId,
      ),
      data: data,
    );
  }

  Future<TenantReconciliationIntake?> _readIntake(String businessDate) async {
    final data = await readDocument(
      TenantCollection.reconciliationDirtyDays,
      businessDate,
    );
    if (data == null) return null;
    final intake = TenantReconciliationIntake.fromDocument(
      path: paths.reconciliationDirtyDay(businessDate),
      data: data,
    );
    if (intake.tenantId != session.tenantId) {
      throw const TenantReconciliationException('cross_tenant_intake');
    }
    return intake;
  }

  /// Reads one bounded page of the runs queued for one business day.
  ///
  /// The filter is one exact `localDate ==` equality on the same ascending key
  /// order, so it is served by Firestore's automatic single-field index and
  /// needs no composite index of its own. The page is ordered by ascending
  /// document ID and is deliberately **not** presented as chronological: a run
  /// ID is `rj_` plus a digest for a scheduled or manual run and
  /// `dirty_{bucket}` for a sale trigger, so document order carries no time
  /// information. Each run states its own instants instead.
  Future<TenantReconciliationRunPage> _loadRuns({
    required String businessDate,
    required int pageSize,
    required String? cursor,
  }) async {
    final page = await readCollectionPage(
      TenantCollection.reconciliationJobs,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
      equalityFilters: <String, Object?>{'localDate': businessDate},
    );
    final items = <TenantReconciliationRun>[];
    for (final snapshot in page.items) {
      final run = TenantReconciliationRun.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (run.tenantId != session.tenantId) {
        throw const TenantReconciliationException('cross_tenant_run');
      }
      // A page narrowed to one day that answers with another day's run is a
      // broken boundary, not a row to quietly skip past: this surface exists to
      // explain one exact business date.
      if (run.businessDate != businessDate) {
        throw const TenantReconciliationException('foreign_reconciliation_day');
      }
      items.add(run);
    }
    return TenantReconciliationRunPage(
      items: items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      businessDate: businessDate,
    );
  }
}

const String _systemActorPrefix = 'system:';

/// A scheduled sweep records `system:nightly` and a sale trigger records
/// `system:sale_trigger`. Neither is a member of the business, and neither is a
/// document ID, so neither is offered to the staff name resolver.
String? _actorUid(String requestedBy) {
  if (requestedBy.startsWith(_systemActorPrefix)) return null;
  try {
    return validateTenantDocumentId(requestedBy, fieldName: 'requestedBy');
  } on ArgumentError {
    throw const TenantReconciliationException('invalid_run_document');
  }
}

String _requiredString(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String ||
      value.isEmpty ||
      value != value.trim() ||
      value.length > 200) {
    throw const TenantReconciliationException('invalid_reconciliation_field');
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw const TenantReconciliationException('invalid_reconciliation_field');
    }
  }
  return value;
}

/// Absent is allowed; present but malformed is not. A writer that recorded a
/// field at all recorded a real value, so a broken one is a broken record.
String? _optionalString(Map<String, Object?> data, String field) =>
    data[field] == null ? null : _requiredString(data, field);

int _requiredCount(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! int || value < 0 || value > _maximumCount) {
    throw const TenantReconciliationException('invalid_reconciliation_field');
  }
  return value;
}

int? _optionalCount(Map<String, Object?> data, String field) =>
    data[field] == null ? null : _requiredCount(data, field);

DateTime? _optionalInstant(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  throw const TenantReconciliationException('invalid_reconciliation_field');
}

const int _maximumCount = 1000000000;
