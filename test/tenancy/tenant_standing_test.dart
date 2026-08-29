import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-29 09:00 UTC.
final DateTime _now = DateTime.utc(2026, 8, 29, 9);
const Duration _hour = Duration(hours: 1);

TenantAccess _access({
  TenantStatus tenantStatus = TenantStatus.pending,
  MembershipStatus membershipStatus = MembershipStatus.active,
  DateTime? provisionalUntil,
  TenantRole role = TenantRole.owner,
  bool serverCanAccess = true,
}) => TenantAccess(
  tenantId: 'tenant-a',
  role: role,
  membershipStatus: membershipStatus,
  tenantStatus: tenantStatus,
  serverCanAccess: serverCanAccess,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
  provisionalUntil: provisionalUntil,
);

void main() {
  group('where a business stands', () {
    test('an approved business is approved, window or no window', () {
      // Approval replaces the question rather than answering it, so a leftover
      // window decides nothing. The rules check status first for the same
      // reason.
      for (final until in <DateTime?>[null, _now.subtract(_hour), _now.add(_hour)]) {
        expect(
          _access(
            tenantStatus: TenantStatus.active,
            provisionalUntil: until,
          ).standingAt(_now),
          TenantStanding.approved,
        );
      }
    });

    test('a request inside its window is provisional', () {
      expect(
        _access(provisionalUntil: _now.add(_hour)).standingAt(_now),
        TenantStanding.provisional,
      );
    });

    test('the window shuts at the instant it names, not after it', () {
      final access = _access(provisionalUntil: _now);

      expect(
        access.standingAt(_now.subtract(const Duration(seconds: 1))),
        TenantStanding.provisional,
      );
      expect(access.standingAt(_now), TenantStanding.lapsed);
    });

    test('a pending business with no window is lapsed, never provisional', () {
      // Every tenant requested before the window existed, and every one seeded
      // by hand. Trading is what they must not be able to do.
      expect(_access().standingAt(_now), TenantStanding.lapsed);
    });

    test('rejection, suspension and archival are closed', () {
      for (final status in <TenantStatus>[
        TenantStatus.rejected,
        TenantStatus.suspended,
        TenantStatus.archived,
      ]) {
        expect(
          _access(
            tenantStatus: status,
            provisionalUntil: _now.add(_hour),
          ).standingAt(_now),
          TenantStanding.closed,
          reason: status.name,
        );
      }
    });

    test('a membership that is not canonical is closed whatever the tenant', () {
      expect(
        _access(
          tenantStatus: TenantStatus.active,
          membershipStatus: MembershipStatus.inactive,
        ).standingAt(_now),
        TenantStanding.closed,
      );
      expect(
        _access(
          tenantStatus: TenantStatus.active,
          serverCanAccess: false,
        ).standingAt(_now),
        TenantStanding.closed,
      );
    });
  });

  group('what a standing permits', () {
    test('provisional may both read and write', () {
      final access = _access(provisionalUntil: _now.add(_hour));

      expect(access.canAccess(now: _now), isTrue);
      expect(access.canRead(now: _now), isTrue);
    });

    test('lapsed may read and may not write', () {
      // The whole point of the read-only tail.
      final access = _access(provisionalUntil: _now.subtract(_hour));

      expect(access.canAccess(now: _now), isFalse);
      expect(access.canRead(now: _now), isTrue);
    });

    test('closed may do neither', () {
      final access = _access(tenantStatus: TenantStatus.rejected);

      expect(access.canAccess(now: _now), isFalse);
      expect(access.canRead(now: _now), isFalse);
    });

    test('a role that is not allowed is refused in both directions', () {
      final access = _access(
        tenantStatus: TenantStatus.active,
        role: TenantRole.cashier,
      );

      expect(
        access.canAccess(allowedRoles: const [TenantRole.admin], now: _now),
        isFalse,
      );
      expect(
        access.canRead(allowedRoles: const [TenantRole.admin], now: _now),
        isFalse,
      );
    });
  });

  group('the session a standing allows', () {
    test('a lapsed business can still hold a session', () {
      // Read-only means the business opens. A session it could not hold at all
      // would be a full lockout wearing read-only's name.
      final session = TenantSession(
        uid: 'user-a',
        access: _access(provisionalUntil: _now.subtract(_hour)),
      );

      expect(session.canRead(), isTrue);
      expect(session.canAccess(), isFalse);
    });

    test('a closed business cannot hold one at all', () {
      expect(
        () => TenantSession(
          uid: 'user-a',
          access: _access(tenantStatus: TenantStatus.rejected),
        ),
        throwsStateError,
      );
    });
  });

  group('how long is left', () {
    test('reads down in the largest unit that is still true', () {
      expect(
        tenantProvisionalRemaining(_now.add(const Duration(days: 3)), _now),
        '3 days',
      );
      expect(
        tenantProvisionalRemaining(_now.add(const Duration(hours: 7)), _now),
        '7 hours',
      );
      expect(
        tenantProvisionalRemaining(_now.add(const Duration(minutes: 20)), _now),
        '20 minutes',
      );
    });

    test('rounds down, so the deadline never arrives early', () {
      // 71 hours is two days and twenty-three, so it reads as two. A shopkeeper
      // planning around this must never be told more time than they have.
      expect(
        tenantProvisionalRemaining(_now.add(const Duration(hours: 71)), _now),
        '2 days',
      );
      // And the same one unit down: 59 minutes is not an hour yet.
      expect(
        tenantProvisionalRemaining(_now.add(const Duration(minutes: 59)), _now),
        '59 minutes',
      );
    });

    test('singulars are singular', () {
      expect(
        tenantProvisionalRemaining(_now.add(const Duration(days: 1)), _now),
        '1 day',
      );
      expect(
        tenantProvisionalRemaining(_now.add(const Duration(hours: 1)), _now),
        '1 hour',
      );
    });

    test('under a minute still reads as one', () {
      // "0 minutes left" has stopped being true by the time it is read.
      expect(
        tenantProvisionalRemaining(_now.add(const Duration(seconds: 5)), _now),
        '1 minute',
      );
    });

    test('a window already shut has no time', () {
      expect(tenantProvisionalRemaining(_now.subtract(_hour), _now), 'No time');
    });
  });
}
