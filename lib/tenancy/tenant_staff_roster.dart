/// One person in a settings list of the business's staff, with a control.
///
/// **Lifted out of the stock count rota on 2026-09-29**, when *Agreed prices*
/// needed exactly the same row: who the person is, whether they can be asked,
/// and a control beside them. Two copies of the avatar ring and the standing
/// badge is how two settings screens come to disagree about who has left.
library;

import 'package:flutter/material.dart';

import '../ui/status.dart';
import '../ui/tokens.dart';
import 'tenant_membership_labels.dart';
import 'tenant_staff_directory.dart';
import 'tenant_types.dart';

/// A line under a person's name that is about their place in this list.
@immutable
final class TenantStaffRosterNote {
  const TenantStaffRosterNote({
    required this.status,
    required this.icon,
    required this.text,
  });

  final AppStatus status;
  final IconData icon;
  final String text;
}

/// One person: who they are, whether they can be asked, and the control.
///
/// **Wide, the control ends the row; compact, it goes under the name.** Seven
/// people down a phone with a control squeezed beside each name would cut the
/// names or the control, and both are the answer. Under the name, aligned
/// with it, the control has the row's whole width.
final class TenantStaffRosterRow extends StatelessWidget {
  const TenantStaffRosterRow({
    super.key,
    required this.keyPrefix,
    required this.member,
    required this.wide,
    required this.control,
    this.note,
  });

  /// Starts the keys of the standing badge and the note, so each screen's
  /// tests go on addressing the keys they always did.
  final String keyPrefix;
  final TenantStaffSummary member;
  final bool wide;
  final Widget control;
  final TenantStaffRosterNote? note;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final deactivated = member.status == MembershipStatus.inactive;
    final standing = switch (member.status) {
      MembershipStatus.pending => (label: 'Invited', icon: Icons.mail_outline),
      MembershipStatus.inactive => (label: 'Deactivated', icon: Icons.block),
      MembershipStatus.active => null,
    };
    final caption = tokens.typography.caption;
    final line = note;

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                member.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.typography.bodyLarge.copyWith(
                  // Stepped back, not hidden: who is listed does not change.
                  color: deactivated
                      ? colors.text.secondary
                      : colors.text.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (standing != null) ...<Widget>[
              SizedBox(width: tokens.spacing.s8),
              // Neutral: whether an invitation is in trouble is the Staff
              // screen's question. Here it only matters that it is one.
              StatusBadge(
                key: ValueKey('$keyPrefix-standing-${member.uid}'),
                status: AppStatus.neutral,
                icon: standing.icon,
                label: standing.label,
              ),
            ],
          ],
        ),
        SizedBox(height: tokens.spacing.s4),
        if (line != null)
          Row(
            key: ValueKey('$keyPrefix-note-${member.uid}'),
            children: <Widget>[
              Icon(
                line.icon,
                size: StatusBadge.iconSize,
                color: line.status.role(tokens).fg,
              ),
              SizedBox(width: tokens.spacing.s4),
              Flexible(
                child: Text(
                  line.text,
                  style: caption.copyWith(color: line.status.role(tokens).fg),
                ),
              ),
            ],
          )
        else
          Text(
            tenantRoleLabel(member.role),
            style: caption.copyWith(color: colors.text.tertiary),
          ),
      ],
    );

    final who = Row(
      children: <Widget>[
        TenantStaffRosterAvatar(member: member),
        SizedBox(width: tokens.spacing.s12),
        Expanded(child: identity),
      ],
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.s16,
        vertical: tokens.spacing.s12,
      ),
      child: wide
          ? Row(
              children: <Widget>[
                // Three to two: the name and its line get the larger share,
                // and the control gets what its label needs.
                Expanded(flex: 3, child: who),
                SizedBox(width: tokens.spacing.s12),
                Expanded(flex: 2, child: control),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                who,
                SizedBox(height: tokens.spacing.s8),
                Padding(
                  padding: EdgeInsets.only(
                    left: TenantStaffRosterAvatar.size + tokens.spacing.s12,
                  ),
                  child: control,
                ),
              ],
            ),
    );
  }
}

/// A member's initials inside their identity ring.
///
/// **The Staff list's own treatment and figures**, redrawn rather than shared
/// because that avatar is private to `tenant_staff_directory.dart`: initials in
/// primary ink on `surface.field`, with `accent.identity` as a two-pixel ring,
/// which is what passes §9 where a filled block did not. A deactivated member's
/// ring steps down to `border.strong`, the one change a row makes to say they
/// have left.
final class TenantStaffRosterAvatar extends StatelessWidget {
  const TenantStaffRosterAvatar({super.key, required this.member});

  final TenantStaffSummary member;

  /// The Staff list's row size.
  static const double size = 40;

  /// The Staff list's ring.
  static const double ringWidth = 2;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final ring = member.status == MembershipStatus.inactive
        ? tokens.colors.surface.borderStrong
        : tokens.colors.accent.identityFor(member.uid);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.colors.surface.field,
          borderRadius: BorderRadius.circular(tokens.radius.lg),
          border: Border.all(color: ring, width: ringWidth),
        ),
        child: Text(
          _initials(member.displayName),
          style: tokens.typography.labelLarge.copyWith(
            color: tokens.colors.text.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    final first = words.first.characters.first;
    final last = words.length > 1 ? words.last.characters.first : '';
    return '$first$last'.toUpperCase();
  }
}
