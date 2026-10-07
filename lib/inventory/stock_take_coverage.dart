/// The counting rota read the other way round: category by category, what is
/// counted and what is not.
///
/// **Why this exists.** The rota is edited one person at a time, and whether
/// the whole shop is covered was stated nowhere - the only way to find out was
/// to read every row and check it against the category list from memory. And a
/// deactivated member was offered the same row as anyone else, so a category
/// down to somebody who can no longer sign in *looked* counted while the till
/// gate would never ask anybody to count it.
///
/// **It reads the rota as drawn, not as published.** The settings screen hands
/// it the form's current choices, so it moves as they change and before Save.
/// It therefore never claims to describe what is in force; the callouts above
/// the form still do that, from the published document.
///
/// **Nothing here reads or writes.** Every input is already held by the
/// settings screen - the categories, the staff page and the form - so this is
/// display logic with no new read behind it. It is still logic the screen did
/// not have before, which is why it lives in its own file with its own tests.
library;

import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_staff_directory.dart';
import '../tenancy/tenant_types.dart';
import '../ui/status.dart';
import 'stock_take_schedule.dart';

/// Which of the coverage line's states the rota is in.
enum StockTakeCoverageKind {
  /// Nobody is down for anything.
  nobodyOnRota,

  /// The rota exists and the setting is *Nothing*, so nobody is asked.
  recordedOnly,

  /// The catalog has no categories, so a count is of everything or nothing.
  noCategories,

  /// Somebody who can sign in counts the whole list.
  wholeList,

  /// Every category is down to somebody who can sign in.
  everyCategory,

  /// Some categories are down to nobody at all.
  gaps,

  /// Some category is down only to people who cannot sign in.
  ///
  /// **The one fault.** The rota says the category is counted and the gate
  /// will never ask anybody to count it.
  unreachable,
}

/// A category nobody who can sign in is down for, and who it is down to.
final class StockTakeUnreachableCategory {
  const StockTakeUnreachableCategory({
    required this.category,
    required this.people,
  });

  final String category;

  /// The deactivated people it is down to, by display name.
  final List<String> people;
}

/// What the rota as drawn amounts to.
final class StockTakeCoverage {
  const StockTakeCoverage._({
    required this.kind,
    required this.counted,
    required this.total,
    this.uncovered = const <String>[],
    this.unreachable = const <StockTakeUnreachableCategory>[],
    this.wholeListBy,
  });

  /// Reads [assignments] against [categories] and [staff].
  ///
  /// [assignments] is the form's rota, one entry per choice. A null
  /// `categoryId` is the whole list, as it is on the published document.
  ///
  /// **A person the staff page does not hold is counted as able to sign in.**
  /// The screen reads one bounded page of staff, so an assignment to somebody
  /// past it is somebody whose standing is not known here - and unknown is not
  /// a fault. Only a member the page shows as `inactive` is unreachable.
  factory StockTakeCoverage.of({
    required TenantStockTakeEnforcement enforcement,
    required List<TenantCategory> categories,
    required List<TenantStaffSummary> staff,
    required Iterable<TenantStockTakeAssignment> assignments,
  }) {
    final rota = assignments.toList();
    final total = categories.length;
    if (rota.isEmpty) {
      return StockTakeCoverage._(
        kind: StockTakeCoverageKind.nobodyOnRota,
        counted: 0,
        total: total,
      );
    }
    if (enforcement == TenantStockTakeEnforcement.off) {
      return StockTakeCoverage._(
        kind: StockTakeCoverageKind.recordedOnly,
        counted: 0,
        total: total,
      );
    }
    if (categories.isEmpty) {
      return const StockTakeCoverage._(
        kind: StockTakeCoverageKind.noCategories,
        counted: 0,
        total: 0,
      );
    }

    final members = <String, TenantStaffSummary>{
      for (final member in staff) member.uid: member,
    };
    bool canSignIn(String uid) =>
        members[uid]?.status != MembershipStatus.inactive;
    String nameOf(String uid) => members[uid]?.displayName ?? uid;

    for (final assignment in rota) {
      if (assignment.categoryId == null && canSignIn(assignment.uid)) {
        return StockTakeCoverage._(
          kind: StockTakeCoverageKind.wholeList,
          counted: total,
          total: total,
          wholeListBy: nameOf(assignment.uid),
        );
      }
    }

    var counted = 0;
    final uncovered = <String>[];
    final unreachable = <StockTakeUnreachableCategory>[];
    for (final category in categories) {
      final assignees = <String>[
        for (final assignment in rota)
          if (assignment.categoryId == null ||
              assignment.categoryId == category.id)
            assignment.uid,
      ];
      if (assignees.any(canSignIn)) {
        counted++;
      } else if (assignees.isEmpty) {
        uncovered.add(category.name);
      } else {
        unreachable.add(
          StockTakeUnreachableCategory(
            category: category.name,
            people: <String>{for (final uid in assignees) nameOf(uid)}.toList(),
          ),
        );
      }
    }
    return StockTakeCoverage._(
      kind: unreachable.isNotEmpty
          ? StockTakeCoverageKind.unreachable
          : uncovered.isNotEmpty
          ? StockTakeCoverageKind.gaps
          : StockTakeCoverageKind.everyCategory,
      counted: counted,
      total: total,
      uncovered: uncovered,
      unreachable: unreachable,
    );
  }

  final StockTakeCoverageKind kind;

  /// Categories down to somebody who can sign in.
  final int counted;
  final int total;

  /// Category names nobody at all is down for, in catalog order.
  final List<String> uncovered;

  /// Categories down only to people who cannot sign in, in catalog order.
  final List<StockTakeUnreachableCategory> unreachable;

  /// Who counts the whole list, when [kind] is [StockTakeCoverageKind.wholeList].
  final String? wholeListBy;

  /// Whether the *n of m categories counted* figure means anything.
  ///
  /// Not while nobody is asked, and not with no categories to count.
  bool get showsCount => switch (kind) {
    StockTakeCoverageKind.nobodyOnRota ||
    StockTakeCoverageKind.recordedOnly ||
    StockTakeCoverageKind.noCategories => false,
    _ => true,
  };

  /// **Colour marks the one fault, not the gaps.** Leaving garden stock
  /// uncounted can be a decision, so gaps are `info`; a category down only to
  /// somebody who cannot sign in is a rota that says one thing and does
  /// another, so it is `attention`. Nothing set up is a working state a
  /// business is in on purpose, and is `neutral`.
  AppStatus get status => switch (kind) {
    StockTakeCoverageKind.nobodyOnRota ||
    StockTakeCoverageKind.recordedOnly ||
    StockTakeCoverageKind.noCategories => AppStatus.neutral,
    StockTakeCoverageKind.wholeList ||
    StockTakeCoverageKind.everyCategory => AppStatus.ok,
    StockTakeCoverageKind.gaps => AppStatus.info,
    StockTakeCoverageKind.unreachable => AppStatus.attention,
  };

  /// `4 of 6 categories counted`.
  String get countLabel =>
      '$counted of $total ${total == 1 ? 'category' : 'categories'} counted';

  String get title => switch (kind) {
    StockTakeCoverageKind.nobodyOnRota => 'Nobody is on the rota',
    StockTakeCoverageKind.recordedOnly => 'Recorded, and nobody is asked',
    StockTakeCoverageKind.noCategories => 'This catalog has no categories',
    StockTakeCoverageKind.wholeList => '$wholeListBy counts the whole list',
    StockTakeCoverageKind.everyCategory =>
      'Every category has somebody counting it',
    StockTakeCoverageKind.gaps =>
      uncovered.length <= _namedInTitle
          ? 'Nobody is down for ${_joined(uncovered, 'or')}'
          : 'Nobody is down for ${uncovered.length} of $total categories',
    StockTakeCoverageKind.unreachable =>
      '${_count(uncovered.length + unreachable.length)} '
          '${uncovered.length + unreachable.length == 1 ? 'category' : 'categories'} '
          'will not be counted',
  };

  /// The sentence under [title], or null where the title says it all.
  ///
  /// **Shorter since 2026-10-03, at the developer's direction.** The good
  /// states said everything twice - *Every category has somebody counting it*,
  /// then *Each of the 6 categories is down to somebody who can sign in* - and
  /// the count beside the heading already gives the figure. What still has a
  /// sentence is what the title cannot carry: which categories, and who.
  String? get message => switch (kind) {
    StockTakeCoverageKind.nobodyOnRota =>
      'Choose what each person counts below.',
    StockTakeCoverageKind.recordedOnly =>
      'The register ignores the rota while this is Nothing.',
    StockTakeCoverageKind.noCategories =>
      'Each person counts everything or nothing.',
    StockTakeCoverageKind.wholeList ||
    StockTakeCoverageKind.everyCategory => null,
    StockTakeCoverageKind.gaps => _gapsMessage(),
    StockTakeCoverageKind.unreachable => _unreachableMessage(),
  };

  /// How many uncounted categories the gaps title names before it counts
  /// them instead. Past two, a title stops fitting on one line.
  static const int _namedInTitle = 2;

  /// How many the gaps message names before it says *and n more*.
  static const int _namedInMessage = 5;

  String _gapsMessage() {
    if (uncovered.length > _namedInTitle) {
      final named = uncovered.take(_namedInMessage).toList();
      final more = uncovered.length - named.length;
      final list = more > 0
          ? '${named.join(', ')} and $more more'
          : _joined(named, 'and');
      return '$list ${uncovered.length == 1 ? 'is' : 'are'} not counted on '
          'any day.';
    }
    // The rest is the count beside the heading, so it is not said again here.
    final pronoun = uncovered.length == 1 ? 'It is' : 'They are';
    return '$pronoun not counted on any day.';
  }

  String _unreachableMessage() {
    final sentences = <String>[];
    final uncoveredClause = uncovered.isEmpty
        ? null
        : uncovered.length <= 3
        ? 'Nobody is down for ${_joined(uncovered, 'or')}'
        : 'Nobody is down for ${uncovered.length} categories';

    // Grouped by who they are down to, so one departed person with three
    // categories is one sentence and not three.
    final groups = <String, List<String>>{};
    final peopleOf = <String, List<String>>{};
    for (final entry in unreachable) {
      final key = entry.people.join('\u0000');
      groups.putIfAbsent(key, () => <String>[]).add(entry.category);
      peopleOf[key] = entry.people;
    }
    final groupClauses = <String>[
      for (final key in groups.keys) _downTo(groups[key]!, peopleOf[key]!),
    ];

    if (uncoveredClause != null && groupClauses.isNotEmpty) {
      // Category names keep their capital, so the second clause joins on as
      // it stands: "Nobody is down for Fasteners, and Plumbing is down to…".
      sentences.add('$uncoveredClause, and ${groupClauses.first}');
      sentences.addAll(groupClauses.skip(1));
    } else if (uncoveredClause != null) {
      sentences.add('$uncoveredClause.');
    } else {
      sentences.addAll(groupClauses);
    }
    return sentences.join(' ');
  }

  /// `Plumbing is down to David Mutiso, who is deactivated and cannot sign in
  /// to count it.`
  static String _downTo(List<String> categories, List<String> people) {
    final what = categories.length <= 3
        ? _joined(categories, 'and')
        : '${categories.length} categories';
    final plural = categories.length > 1;
    final who = _joined(people, 'and');
    final many = people.length > 1;
    return '$what ${plural ? 'are' : 'is'} down to $who, who '
        '${many ? 'are' : 'is'} deactivated and cannot sign in to count '
        '${plural ? 'them' : 'it'}.';
  }

  static String _joined(List<String> items, String conjunction) {
    if (items.length <= 1) return items.join();
    return '${items.take(items.length - 1).join(', ')} $conjunction '
        '${items.last}';
  }

  /// A count as a word up to nine, the way a sentence would say it.
  static String _count(int n) => switch (n) {
    1 => 'One',
    2 => 'Two',
    3 => 'Three',
    4 => 'Four',
    5 => 'Five',
    6 => 'Six',
    7 => 'Seven',
    8 => 'Eight',
    9 => 'Nine',
    _ => '$n',
  };
}
