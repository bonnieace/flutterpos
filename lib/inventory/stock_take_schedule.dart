/// When a count is due, who owes it, and what happens if they have not taken it.
///
/// **This is the only part of stock take that a business configures**, and it is
/// deliberately small: which days, who counts what, and how hard the reminder
/// pushes. Everything else - what a count means, who may take one, what happens
/// to the figures - is decided by the code and not by a setting.
///
/// **Nobody is assigned by default, and that is the safe state.** A business that
/// has never opened this screen is never interrupted at the till. An obligation
/// exists only where somebody has written one down.
library;

import '../tenancy/tenancy.dart';
import 'stock_take.dart';

/// What happens when somebody who owes a count opens the register.
enum TenantStockTakeEnforcement {
  /// Nothing. The schedule is recorded but does not interrupt anybody.
  off,

  /// A question they may decline, once per visit to the till.
  prompt,

  /// The till is not reachable until the count is handed in.
  ///
  /// **It clears on handing in, not on approval.** A cashier must never be held
  /// out of the till waiting for a manager to be reachable - offline that could
  /// be a whole day - so the obligation is discharged the moment the count is
  /// durable on the device.
  block,
}

/// One person, and what they are expected to count.
final class TenantStockTakeAssignment {
  const TenantStockTakeAssignment({required this.uid, this.categoryId});

  final String uid;

  /// The category they count, or null for the whole catalog.
  ///
  /// Null is the "one person counts everything" arrangement; a category is the
  /// "split a long list between people" one. They are the same field because
  /// they are the same fact - what this person is on the hook for.
  final String? categoryId;

  TenantStockTakeScope get scope => categoryId == null
      ? const TenantStockTakeEverything()
      : TenantStockTakeCategory(categoryId!);

  Map<String, Object?> toMap() => <String, Object?>{
    'uid': uid,
    if (categoryId != null) 'categoryId': categoryId,
  };

  static TenantStockTakeAssignment fromMap(Map<String, Object?> map) {
    final uid = map['uid'];
    final categoryId = map['categoryId'];
    if (uid is! String || uid.isEmpty) {
      throw const FormatException('an assignment must name a member.');
    }
    if (categoryId != null && (categoryId is! String || categoryId.isEmpty)) {
      throw const FormatException('categoryId must be a category when present.');
    }
    return TenantStockTakeAssignment(
      uid: uid,
      categoryId: categoryId as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TenantStockTakeAssignment &&
      other.uid == uid &&
      other.categoryId == categoryId;

  @override
  int get hashCode => Object.hash(uid, categoryId);
}

/// The most assignments one business may record.
///
/// Bounded because the document is read by every device on every till entry, and
/// an unbounded list would make that read grow without limit.
const int maximumStockTakeAssignments = 50;

/// Strict read model for `tenants/{tenantId}/configuration/stock_take`.
final class TenantStockTakeSchedule {
  TenantStockTakeSchedule({
    required this.enforcement,
    required Set<int> weekdays,
    required List<TenantStockTakeAssignment> assignments,
  }) : weekdays = Set<int>.unmodifiable(weekdays),
       assignments = List<TenantStockTakeAssignment>.unmodifiable(assignments) {
    for (final weekday in weekdays) {
      if (weekday < DateTime.monday || weekday > DateTime.sunday) {
        throw const FormatException('a weekday must be 1 through 7.');
      }
    }
    if (assignments.length > maximumStockTakeAssignments) {
      throw const FormatException('too many assignments.');
    }
  }

  /// What a business that has configured nothing behaves like.
  ///
  /// **Off, no days, nobody assigned.** Three separate reasons this interrupts
  /// no one, so a partial or damaged document cannot accidentally lock a till.
  static final TenantStockTakeSchedule none = TenantStockTakeSchedule(
    enforcement: TenantStockTakeEnforcement.off,
    weekdays: const <int>{},
    assignments: const <TenantStockTakeAssignment>[],
  );

  /// Unknown fields are ignored and known ones must be exactly valid, which is
  /// the asymmetry every configuration document here uses: a setting a later
  /// build adds must not stop this one working.
  factory TenantStockTakeSchedule.fromMap(Map<String, Object?> map) {
    final enforcement = TenantStockTakeEnforcement.values
        .where((value) => value.name == map['enforcement'])
        .firstOrNull;
    if (enforcement == null) {
      throw const FormatException('enforcement must be off, prompt or block.');
    }
    final weekdays = map['weekdays'];
    if (weekdays is! List) {
      throw const FormatException('weekdays must be a list.');
    }
    final assignments = map['assignments'];
    if (assignments is! List) {
      throw const FormatException('assignments must be a list.');
    }
    return TenantStockTakeSchedule(
      enforcement: enforcement,
      weekdays: <int>{
        for (final weekday in weekdays)
          if (weekday is int)
            weekday
          else
            throw const FormatException('a weekday must be a whole number.'),
      },
      assignments: <TenantStockTakeAssignment>[
        for (final assignment in assignments)
          if (assignment is Map)
            TenantStockTakeAssignment.fromMap(
              Map<String, Object?>.from(assignment.cast<String, Object?>()),
            )
          else
            throw const FormatException('an assignment must be an object.'),
      ],
    );
  }

  final TenantStockTakeEnforcement enforcement;

  /// `DateTime.monday` through `DateTime.sunday`.
  final Set<int> weekdays;
  final List<TenantStockTakeAssignment> assignments;

  Map<String, Object?> documentData({required String updatedBy}) =>
      <String, Object?>{
        'enforcement': enforcement.name,
        'weekdays': (weekdays.toList()..sort()),
        'assignments': <Map<String, Object?>>[
          for (final assignment in assignments) assignment.toMap(),
        ],
        'updatedBy': updatedBy,
      };

  /// Whether a count is expected on the day [businessDate] names.
  ///
  /// The date is parsed rather than taken as a `DateTime` so the weekday is the
  /// business day's, not the device's idea of now - a shop trading past midnight
  /// is still on the previous business date, and the count belongs to that day.
  bool fallsOn(String businessDate) {
    if (enforcement == TenantStockTakeEnforcement.off) return false;
    final parsed = DateTime.tryParse(businessDate);
    if (parsed == null) return false;
    return weekdays.contains(parsed.weekday);
  }

  /// What [uid] is expected to count on that day, which is usually nothing.
  List<TenantStockTakeScope> scopesFor({
    required String uid,
    required String businessDate,
  }) {
    if (!fallsOn(businessDate)) return const <TenantStockTakeScope>[];
    return <TenantStockTakeScope>[
      for (final assignment in assignments)
        if (assignment.uid == uid) assignment.scope,
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is TenantStockTakeSchedule &&
      other.enforcement == enforcement &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays) &&
      other.assignments.length == assignments.length &&
      _sameAssignments(other.assignments);

  bool _sameAssignments(List<TenantStockTakeAssignment> other) {
    for (var i = 0; i < assignments.length; i++) {
      if (other[i] != assignments[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    enforcement,
    Object.hashAllUnordered(weekdays),
    Object.hashAll(assignments),
  );
}

/// Whether this business has a schedule, and whether it could be read.
enum TenantStockTakeScheduleState { published, absent, malformed }

final class TenantPublishedStockTakeSchedule {
  const TenantPublishedStockTakeSchedule._(this.state, this._schedule);

  const TenantPublishedStockTakeSchedule.published(
    TenantStockTakeSchedule schedule,
  ) : this._(TenantStockTakeScheduleState.published, schedule);

  const TenantPublishedStockTakeSchedule.absent()
    : this._(TenantStockTakeScheduleState.absent, null);

  const TenantPublishedStockTakeSchedule.malformed()
    : this._(TenantStockTakeScheduleState.malformed, null);

  final TenantStockTakeScheduleState state;
  final TenantStockTakeSchedule? _schedule;

  /// The published schedule, or the one that interrupts nobody.
  ///
  /// **A malformed or missing document yields `none`, never a guess.** This is
  /// read on the way into the till: a document nobody can parse must not be
  /// allowed to hold a shop out of its own register, so the failure mode is
  /// "no count is due" and the one person who can fix it sees `malformed` on
  /// the settings screen.
  TenantStockTakeSchedule get schedule => _schedule ?? TenantStockTakeSchedule.none;

  TenantStockTakeSchedule? get published => _schedule;
}

/// Guarded read-only repository for one business's counting schedule.
final class TenantStockTakeScheduleRepository extends TenantReadRepository {
  TenantStockTakeScheduleRepository({required super.session, required super.reader});

  static const documentId = 'stock_take';

  /// Owner and administrator write it, which is what the existing
  /// `configuration/{documentId}` rule already allows and therefore needs no
  /// rules change. **Every active member reads it**, because the till checks it
  /// on the way in and a cashier is exactly who it is about.
  static const List<TenantRole> writeRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
  ];

  Future<TenantPublishedStockTakeSchedule> load() async {
    final data = await readDocument(TenantCollection.configuration, documentId);
    if (data == null) return const TenantPublishedStockTakeSchedule.absent();
    try {
      return TenantPublishedStockTakeSchedule.published(
        TenantStockTakeSchedule.fromMap(data),
      );
    } on FormatException {
      return const TenantPublishedStockTakeSchedule.malformed();
    }
  }
}

/// Raised when a schedule change is refused before anything is written.
final class TenantStockTakeScheduleException implements Exception {
  const TenantStockTakeScheduleException(this.code);

  final String code;

  @override
  String toString() => 'TenantStockTakeScheduleException($code)';
}

/// One schedule change, ready to be queued.
final class TenantStockTakeScheduleIntent {
  const TenantStockTakeScheduleIntent._({
    required this.path,
    required this.tenantId,
    required this.schedule,
    required this.updatedBy,
  });

  final String path;
  final String tenantId;
  final TenantStockTakeSchedule schedule;
  final String updatedBy;

  Map<String, Object?> documentData() =>
      schedule.documentData(updatedBy: updatedBy);
}

final class TenantStockTakeSchedulePublisher extends TenantReadRepository {
  TenantStockTakeSchedulePublisher({required super.session, required super.reader});

  static const List<TenantRole> allowedRoles =
      TenantStockTakeScheduleRepository.writeRoles;

  Future<TenantPublishedStockTakeSchedule> loadPublished() =>
      TenantStockTakeScheduleRepository(session: session, reader: reader).load();

  /// Builds the one instruction these values describe.
  ///
  /// **Every refusal happens here**, before anything is sent, exactly as the
  /// printer and branding publishers do.
  TenantStockTakeScheduleIntent buildIntent({
    required TenantStockTakeEnforcement enforcement,
    required Set<int> weekdays,
    required List<TenantStockTakeAssignment> assignments,
    required TenantPublishedStockTakeSchedule published,
  }) {
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantStockTakeScheduleException('stock_take_forbidden');
    }
    final TenantStockTakeSchedule schedule;
    try {
      schedule = TenantStockTakeSchedule(
        enforcement: enforcement,
        weekdays: weekdays,
        assignments: assignments,
      );
    } on FormatException {
      throw const TenantStockTakeScheduleException('invalid_schedule');
    }
    // **A schedule that expects somebody on no day expects nothing**, and
    // recording it would be a setting that reads as switched on and behaves as
    // switched off. Say so instead.
    if (enforcement != TenantStockTakeEnforcement.off) {
      if (weekdays.isEmpty) {
        throw const TenantStockTakeScheduleException('no_days_chosen');
      }
      if (assignments.isEmpty) {
        throw const TenantStockTakeScheduleException('nobody_assigned');
      }
    }
    // One person may count two categories; they may not be told twice to count
    // the same one.
    final seen = <String>{};
    for (final assignment in assignments) {
      if (!seen.add('${assignment.uid}::${assignment.categoryId ?? '*'}')) {
        throw const TenantStockTakeScheduleException('duplicate_assignment');
      }
    }
    // Re-saving the identical document is refused for the reason the currency
    // publisher gives: it rewrites the provenance and asks every device to
    // re-read a setting that cannot have changed.
    if (published.published == schedule) {
      throw const TenantStockTakeScheduleException('schedule_unchanged');
    }
    return TenantStockTakeScheduleIntent._(
      path: paths.configurationDocument(
        TenantStockTakeScheduleRepository.documentId,
      ),
      tenantId: session.tenantId,
      schedule: schedule,
      updatedBy: session.uid,
    );
  }
}
