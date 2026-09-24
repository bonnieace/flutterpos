/// The names a report prints where its figures are grouped by person.
///
/// **A UID is not a name, and a document that leaves the device is read by
/// somebody who has never seen one.** Four reports rank people - who recorded
/// a return, who worked a shift, who took a count, who made a change - and the
/// records they are built from carry a UID and nothing else. The staff
/// directory is the only place a display name lives, so the name is always a
/// joined figure, exactly as a return's value is.
///
/// The join is made after the analysis, not inside it. Grouping is by UID
/// because the UID is the identity: two people may share a display name, a
/// name may be edited between one report and the next, and a member who leaves
/// the roster still recorded what they recorded. The name is a label put on
/// the group at the last moment, which is also why an unresolved one costs
/// nothing but a label.
///
/// **It degrades rather than failing.** `firestore.rules` lets a cashier read
/// only its own staff record, so a cashier generating the returns report - the
/// one report a cashier may generate - sees itself by name and its colleagues
/// by UID. That is the degradation `TenantStaffNameResolver` is built for and
/// the one the rules file says these surfaces take. The report says so in a
/// caveat rather than leaving a reader to wonder what the strings are.
library;

import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_staff_names.dart';
import 'report_scope.dart';

/// Display names for the people one report names, by UID.
final class TenantReportPeople {
  const TenantReportPeople(this._names);

  /// No names at all, which every label falls back through.
  ///
  /// This is what a renderer test uses, and what a report gets when the
  /// directory could not be reached: every row still prints, identified by the
  /// only identity the record carried.
  const TenantReportPeople.none() : _names = const <String, String>{};

  final Map<String, String> _names;

  /// What to print for [uid]: the display name, or the UID where none could be
  /// read.
  String label(String uid) => _names[uid] ?? uid;

  /// Whether a name was resolved for [uid].
  bool isNamed(String uid) => _names.containsKey(uid);

  /// How many of [uids] will print as a UID.
  int unnamed(Iterable<String> uids) =>
      uids.where((uid) => !_names.containsKey(uid)).length;

  /// The caveat to carry where any of [uids] could not be named, and null
  /// where every one of them was.
  ///
  /// [noun] names what the people are to this report - 'recorded a return',
  /// 'worked a shift' - so the sentence says which rows are affected rather
  /// than making the reader match it to a table.
  TenantReportCaveat? caveat(Iterable<String> uids, {required String noun}) {
    final short = unnamed(uids);
    if (short == 0) return null;
    final one = short == 1;
    return TenantReportCaveat(
      kind: TenantReportCaveatKind.roleRestricted,
      sentence:
          '$short of the people who $noun ${one ? 'is' : 'are'} shown by the '
          'identifier the record carried rather than by name, because this '
          "role may read only its own entry in the staff directory. The "
          'figures beside ${one ? 'it' : 'them'} are complete; only the label '
          'is missing, and a colleague with the roster can put a name to '
          '${one ? 'it' : 'them'}.',
    );
  }
}

/// Reads display names for [uids], and answers with the UID for any it cannot.
///
/// **Never throws for a missing name.** `TenantStaffNameResolver` is the one
/// repository in this app that does not fail a read closed, for the reason
/// given there: a label is a convenience and the UID beside it is the
/// authoritative identity. A report is held to the same rule - a page of
/// financial evidence is not withheld because a name could not be fetched.
Future<TenantReportPeople> readTenantReportPeople({
  required TenantSession session,
  required TenantDataReader reader,
  required Iterable<String> uids,
}) async {
  final wanted = uids.toSet();
  if (wanted.isEmpty) return const TenantReportPeople.none();

  final resolver = TenantStaffNameResolver(session: session, reader: reader);
  try {
    return TenantReportPeople(await resolver.resolve(wanted));
  } on TenantScopeViolation {
    // A transport answering outside this tenant is a broken boundary, not an
    // unavailable label, and the resolver deliberately rethrows it. A report
    // must not paper over it with UIDs.
    rethrow;
  } catch (_) {
    // Everything else - offline, denied, malformed - is a label this report
    // does without.
    return const TenantReportPeople.none();
  }
}
