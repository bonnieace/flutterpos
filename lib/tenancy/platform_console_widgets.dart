import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ui/buttons.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'platform_console_data.dart';
import 'tenant_types.dart';

// ---------------------------------------------------------------------------
// Dates, as a person reads them: today's by the clock, this week's by the day,
// older ones by the date.
// ---------------------------------------------------------------------------

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int platformDaysBetween(DateTime from, DateTime to) => DateTime(
  to.year,
  to.month,
  to.day,
).difference(DateTime(from.year, from.month, from.day)).inDays;

/// `09:12` today, `Sun 16:05` this week, `14 Oct` before that.
String platformWhen(DateTime moment, DateTime now) {
  final local = moment.toLocal();
  final days = platformDaysBetween(local, now);
  if (days <= 0) return DateFormat('HH:mm').format(local);
  if (days < 7) return DateFormat('EEE HH:mm').format(local);
  return platformShortDate(local, now);
}

/// `14 Oct`, with the year only when it is not this one.
String platformShortDate(DateTime moment, DateTime now) {
  final local = moment.toLocal();
  return local.year == now.year
      ? DateFormat('d MMM').format(local)
      : DateFormat('d MMM y').format(local);
}

/// `Sun 18 Oct, 16:05`.
String platformStamp(DateTime moment) =>
    DateFormat('EEE d MMM, HH:mm').format(moment.toLocal());

/// `12 Aug 2026`.
String platformLongDate(DateTime moment) =>
    DateFormat('d MMM y').format(moment.toLocal());

/// `Today`, `Yesterday`, `Sunday 18 October`.
String platformDayHeading(DateTime moment, DateTime now) {
  final local = moment.toLocal();
  if (_sameDay(local, now)) return 'Today';
  if (platformDaysBetween(local, now) == 1) return 'Yesterday';
  return DateFormat('EEEE d MMMM').format(local);
}

/// `Joined today`, `Joined 12 Aug`.
String platformJoined(DateTime? moment, DateTime now) {
  if (moment == null) return 'Joined';
  if (_sameDay(moment.toLocal(), now)) return 'Joined today';
  return 'Joined ${platformShortDate(moment, now)}';
}

String platformPlural(int count, String one, [String? many]) =>
    '$count ${count == 1 ? one : (many ?? '${one}s')}';

/// Up to two initials from a name or an address.
String platformInitials(String source) {
  final words = source
      .split(RegExp(r'[\s@._-]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  final first = words.first.characters.first;
  final second = words.length > 1 ? words[1].characters.first : '';
  return '$first$second'.toUpperCase();
}

// ---------------------------------------------------------------------------
// Standings: a glyph and a word in every case, never a colour alone.
// ---------------------------------------------------------------------------

StatusBadge platformBusinessBadge(TenantStatus status, {String? label}) =>
    switch (status) {
      TenantStatus.active => StatusBadge(
        status: AppStatus.ok,
        label: label ?? 'Trading',
        icon: Icons.check_circle_outline,
      ),
      TenantStatus.suspended => StatusBadge(
        status: AppStatus.attention,
        label: label ?? 'Suspended',
        icon: Icons.pause_circle_outline,
      ),
      TenantStatus.archived => StatusBadge(
        status: AppStatus.neutral,
        label: label ?? 'Archived',
        icon: Icons.inventory_2_outlined,
      ),
    };

Widget platformPersonBadge(
  PlatformPerson person, {
  PlatformOperation? operation,
}) {
  if (operation != null) {
    return StatusBadge(
      status: AppStatus.attention,
      label: operation.reactivating ? 'Reactivating' : 'Disabling',
      icon: Icons.sync,
    );
  }
  return person.standing == PlatformPersonStanding.active
      ? const StatusBadge(
          status: AppStatus.ok,
          label: 'Active',
          icon: Icons.check_circle_outline,
        )
      : const StatusBadge(
          status: AppStatus.problem,
          label: 'Disabled',
          icon: Icons.person_off_outlined,
        );
}

StatusBadge platformStaffBadge(PlatformStaffStanding standing) =>
    switch (standing) {
      PlatformStaffStanding.active => const StatusBadge(
        status: AppStatus.ok,
        label: 'Active',
        icon: Icons.check_circle_outline,
      ),
      PlatformStaffStanding.invited => const StatusBadge(
        status: AppStatus.attention,
        label: 'Invited',
        icon: Icons.schedule,
      ),
      PlatformStaffStanding.linkExpired => const StatusBadge(
        status: AppStatus.problem,
        label: 'Link expired',
        icon: Icons.error_outline,
      ),
      PlatformStaffStanding.emailRejected => const StatusBadge(
        status: AppStatus.problem,
        label: 'Email rejected',
        icon: Icons.unsubscribe_outlined,
      ),
      PlatformStaffStanding.deactivated => const StatusBadge(
        status: AppStatus.neutral,
        label: 'Deactivated',
        icon: Icons.inventory_2_outlined,
      ),
    };

/// A pill on [StatusBadge]'s metrics for what is not a status: a role, or
/// platform authority. Owner, administrator and platform administrator take
/// `accent.privileged`, the one identity colour the token layer says carries
/// meaning; manager and cashier are neutral.
final class PlatformPill extends StatelessWidget {
  const PlatformPill({
    super.key,
    required this.label,
    required this.icon,
    this.privileged = false,
  });

  factory PlatformPill.role(TenantRole role) => switch (role) {
    TenantRole.owner => const PlatformPill(
      label: 'Owner',
      icon: Icons.workspace_premium_outlined,
      privileged: true,
    ),
    TenantRole.admin => const PlatformPill(
      label: 'Administrator',
      icon: Icons.shield_outlined,
      privileged: true,
    ),
    TenantRole.manager => const PlatformPill(
      label: 'Manager',
      icon: Icons.group_outlined,
    ),
    TenantRole.cashier => const PlatformPill(
      label: 'Cashier',
      icon: Icons.receipt_long_outlined,
    ),
  };

  static const PlatformPill platformAdministrator = PlatformPill(
    label: 'Platform administrator',
    icon: Icons.shield_outlined,
    privileged: true,
  );

  final String label;
  final IconData icon;
  final bool privileged;

  /// The privileged hue's fill and edge, as the staff design draws them.
  static const double _fillAlpha = 0.16;
  static const double _edgeAlpha = 0.30;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final hue = colors.accent.privileged;
    final fg = privileged ? hue : colors.text.secondary;
    return Semantics(
      label: label,
      container: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: StatusBadge.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: privileged
                  ? hue.withValues(alpha: _fillAlpha)
                  : colors.surface.field,
              border: Border.all(
                color: privileged
                    ? hue.withValues(alpha: _edgeAlpha)
                    : colors.surface.borderStrong,
              ),
              borderRadius: BorderRadius.circular(tokens.radius.md),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: StatusBadge.iconSize, color: fg),
                  SizedBox(width: tokens.spacing.s4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.typography.labelMedium.copyWith(color: fg),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The `YOU` marker beside the signed-in operator's own name.
final class PlatformYouMarker extends StatelessWidget {
  const PlatformYouMarker({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Container(
      height: tokens.spacing.s24,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.colors.surface.selected,
        borderRadius: BorderRadius.circular(tokens.radius.pill),
      ),
      child: Text(
        'YOU',
        style: tokens.typography.labelEyebrow.copyWith(
          color: tokens.colors.text.primary,
        ),
      ),
    );
  }
}

/// Initials in a ring: `surface.field` behind them, the identity hue only on
/// the ring, as the staff design draws a person.
final class PlatformAvatar extends StatelessWidget {
  const PlatformAvatar({
    super.key,
    required this.label,
    required this.seed,
    this.small = false,
    this.muted = false,
    this.color,
  });

  final String label;

  /// What the hue is keyed on, so a person keeps one colour everywhere.
  final String seed;
  final bool small;
  final bool muted;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final size = small ? tokens.spacing.s40 : tokens.spacing.s48;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surface.field,
          border: Border.all(
            color: color ?? colors.accent.identityFor(seed),
            width: tokens.layout.chartLine,
          ),
          borderRadius: BorderRadius.circular(tokens.radius.lg),
        ),
        child: Text(
          platformInitials(label),
          style:
              (small
                      ? tokens.typography.labelLarge
                      : tokens.typography.bodyLarge)
                  .copyWith(
                    color: muted ? colors.text.tertiary : colors.text.primary,
                    fontWeight: tokens.typography.labelLarge.fontWeight,
                    letterSpacing: 0,
                  ),
        ),
      ),
    );
  }
}

/// A glyph well in a status role, for an alert or an empty state.
final class PlatformToneWell extends StatelessWidget {
  const PlatformToneWell({
    super.key,
    required this.icon,
    required this.status,
    this.small = false,
  });

  final IconData icon;
  final AppStatus status;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final role = status.role(tokens);
    final size = small ? tokens.spacing.s32 : tokens.spacing.s48;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: role.bg,
        border: Border.all(color: role.border),
        borderRadius: BorderRadius.circular(
          small ? tokens.radius.md : tokens.radius.lg,
        ),
      ),
      child: Icon(
        icon,
        size: small ? tokens.icons.row : tokens.icons.card,
        color: role.fg,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Containers.
// ---------------------------------------------------------------------------

bool platformCompact(BuildContext context) {
  final tokens = AppTokens.componentOf(context);
  return MediaQuery.sizeOf(context).width < tokens.layout.mediumFloor;
}

/// A titled card: an eyebrow, something at the end of its line, a body.
final class PlatformPanel extends StatelessWidget {
  const PlatformPanel({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.gap,
  });

  final String title;
  final Widget? trailing;
  final List<Widget> children;
  final double? gap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final compact = platformCompact(context);
    final spacing = gap ?? tokens.spacing.s16;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        border: Border.all(color: tokens.colors.surface.cardEdge),
        borderRadius: BorderRadius.circular(tokens.radius.lg),
      ),
      child: Padding(
        padding: EdgeInsets.all(
          compact ? tokens.spacing.s16 : tokens.spacing.s20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: tokens.typography.labelEyebrow.copyWith(
                      color: tokens.colors.text.secondary,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            for (final child in children) ...[SizedBox(height: spacing), child],
          ],
        ),
      ),
    );
  }
}

/// The eyebrow-titled card's trailing caption.
final class PlatformCaption extends StatelessWidget {
  const PlatformCaption(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tokens.typography.caption.copyWith(
        color: color ?? tokens.colors.text.tertiary,
      ),
    );
  }
}

/// A text button at the end of a panel's title line.
final class PlatformLink extends StatelessWidget {
  const PlatformLink({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => AppButton(
    label: label,
    tier: AppButtonTier.tertiary,
    size: AppButtonSize.sm,
    onPressed: onPressed,
  );
}

/// A record's facts: labelled columns on a wide screen, labelled rows on a
/// phone.
final class PlatformFacts extends StatelessWidget {
  const PlatformFacts({super.key, required this.facts});

  final List<(String, Widget)> facts;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final compact = platformCompact(context);
    final edge = BorderSide(color: colors.surface.cardEdge);
    final decoration = BoxDecoration(
      color: colors.surface.raised,
      border: Border.all(color: colors.surface.cardEdge),
      borderRadius: BorderRadius.circular(tokens.radius.lg),
    );
    if (compact) {
      return DecoratedBox(
        decoration: decoration,
        child: Column(
          children: <Widget>[
            for (var index = 0; index < facts.length; index++)
              Container(
                constraints: BoxConstraints(
                  minHeight: tokens.density.minimumTapTarget.height,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: tokens.spacing.s16,
                  vertical: tokens.spacing.s8,
                ),
                decoration: BoxDecoration(
                  border: index == 0 ? null : Border(top: edge),
                ),
                child: Row(
                  children: <Widget>[
                    Text(
                      facts[index].$1,
                      style: tokens.typography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                    SizedBox(width: tokens.spacing.s12),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: facts[index].$2,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    return DecoratedBox(
      decoration: decoration,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var index = 0; index < facts.length; index++)
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: tokens.spacing.s20,
                    vertical: tokens.spacing.s16,
                  ),
                  decoration: BoxDecoration(
                    border: index == 0 ? null : Border(left: edge),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        facts[index].$1.toUpperCase(),
                        style: tokens.typography.labelEyebrow.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                      SizedBox(height: tokens.spacing.s8),
                      facts[index].$2,
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The value of a fact in body type.
final class PlatformFactText extends StatelessWidget {
  const PlatformFactText(this.text, {super.key, this.mono = false});

  final String text;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final compact = platformCompact(context);
    final style = mono
        ? (compact ? tokens.typography.monoCaption : tokens.typography.mono)
        : (compact
              ? tokens.typography.bodyMedium
              : tokens.typography.bodyLarge);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style.copyWith(color: tokens.colors.text.primary),
    );
  }
}

/// One record in a list: who or what on the left, its standing on the right,
/// actions at the end. Edged in the problem colour when something about it is
/// wrong.
final class PlatformRecordRow extends StatelessWidget {
  const PlatformRecordRow({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.badge,
    this.note,
    this.noteStatus,
    this.actions = const <Widget>[],
    this.problem = false,
    this.onPressed,
  });

  final Widget leading;
  final Widget title;
  final Widget subtitle;
  final Widget? badge;
  final String? note;

  /// Colours the note: problem or attention. Null is the quiet tertiary.
  final AppStatus? noteStatus;
  final List<Widget> actions;
  final bool problem;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final compact = platformCompact(context);
    final noteColor = noteStatus == null
        ? colors.text.tertiary
        : noteStatus!.role(tokens).fg;
    final noteText = note == null
        ? null
        : Text(
            note!,
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            textAlign: compact ? TextAlign.start : TextAlign.end,
            style: tokens.typography.caption.copyWith(color: noteColor),
          );
    final body = compact
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              leading,
              SizedBox(width: tokens.spacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    title,
                    SizedBox(height: tokens.spacing.s4),
                    subtitle,
                    if (badge != null) ...[
                      SizedBox(height: tokens.spacing.s8),
                      badge!,
                    ],
                    if (noteText != null) ...[
                      SizedBox(height: tokens.spacing.s4),
                      noteText,
                    ],
                  ],
                ),
              ),
            ],
          )
        : Row(
            children: <Widget>[
              leading,
              SizedBox(width: tokens.spacing.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    title,
                    SizedBox(height: tokens.spacing.s4),
                    subtitle,
                  ],
                ),
              ),
              SizedBox(width: tokens.spacing.s16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  ?badge,
                  if (noteText != null) ...[
                    SizedBox(height: tokens.spacing.s4),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: tokens.layout.credential,
                      ),
                      child: noteText,
                    ),
                  ],
                ],
              ),
              for (final action in actions) ...[
                SizedBox(width: tokens.spacing.s16),
                action,
              ],
            ],
          );
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.raised,
        border: Border.all(
          color: problem
              ? colors.status.problem.border
              : colors.surface.cardEdge,
        ),
        borderRadius: BorderRadius.circular(tokens.radius.lg),
      ),
      child: Padding(
        padding: EdgeInsets.all(
          compact ? tokens.spacing.s12 : tokens.spacing.s16,
        ),
        child: body,
      ),
    );
    if (onPressed == null) return card;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radius.lg),
        onTap: onPressed,
        child: card,
      ),
    );
  }
}

/// A name in the row's title line.
final class PlatformRowTitle extends StatelessWidget {
  const PlatformRowTitle({
    super.key,
    required this.name,
    this.after = const [],
  });

  final String name;
  final List<Widget> after;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Wrap(
      spacing: tokens.spacing.s8,
      runSpacing: tokens.spacing.s4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          name,
          style: tokens.typography.bodyLarge.copyWith(
            color: tokens.colors.text.primary,
            fontWeight: tokens.typography.labelMedium.fontWeight,
          ),
        ),
        ...after,
      ],
    );
  }
}

/// A row's second line in body type.
final class PlatformRowText extends StatelessWidget {
  const PlatformRowText(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tokens.typography.bodyMedium.copyWith(
        color: color ?? tokens.colors.text.secondary,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History and activity.
// ---------------------------------------------------------------------------

/// The tone of a timeline dot or an activity glyph.
enum PlatformTone { ok, attention, problem, neutral, privileged }

({Color fg, Color bg, Color border}) platformToneColors(
  AppTokens tokens,
  PlatformTone tone,
) {
  final status = tokens.colors.status;
  final hue = tokens.colors.accent.privileged;
  return switch (tone) {
    PlatformTone.ok => (
      fg: status.ok.fg,
      bg: status.ok.bg,
      border: status.ok.border,
    ),
    PlatformTone.attention => (
      fg: status.attention.fg,
      bg: status.attention.bg,
      border: status.attention.border,
    ),
    PlatformTone.problem => (
      fg: status.problem.fg,
      bg: status.problem.bg,
      border: status.problem.border,
    ),
    PlatformTone.neutral => (
      fg: status.neutral.fg,
      bg: status.neutral.bg,
      border: status.neutral.border,
    ),
    PlatformTone.privileged => (
      fg: hue,
      bg: hue.withValues(alpha: 0.16),
      border: hue.withValues(alpha: 0.30),
    ),
  };
}

final class PlatformTimelineEntry {
  const PlatformTimelineEntry({
    required this.tone,
    required this.icon,
    required this.title,
    required this.meta,
    this.reason,
  });

  final PlatformTone tone;
  final IconData icon;
  final String title;
  final String meta;
  final String? reason;
}

final class PlatformTimeline extends StatelessWidget {
  const PlatformTimeline({super.key, required this.entries});

  final List<PlatformTimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final dot = tokens.spacing.s32;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < entries.length; index++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  width: dot,
                  child: Column(
                    children: <Widget>[
                      Builder(
                        builder: (context) {
                          final tone = platformToneColors(
                            tokens,
                            entries[index].tone,
                          );
                          return Container(
                            width: dot,
                            height: dot,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: tone.bg,
                              border: Border.all(color: tone.border),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              entries[index].icon,
                              size: tokens.icons.row,
                              color: tone.fg,
                            ),
                          );
                        },
                      ),
                      if (index < entries.length - 1)
                        Expanded(
                          child: Container(
                            width: tokens.layout.chartHairline,
                            color: colors.surface.cardEdge,
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(width: tokens.spacing.s12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: tokens.spacing.s4,
                      bottom: index < entries.length - 1
                          ? tokens.spacing.s20
                          : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          entries[index].title,
                          style: tokens.typography.labelMedium.copyWith(
                            color: colors.text.primary,
                          ),
                        ),
                        SizedBox(height: tokens.spacing.s4),
                        Text(
                          entries[index].meta,
                          style: tokens.typography.caption.copyWith(
                            color: colors.text.tertiary,
                          ),
                        ),
                        if (entries[index].reason != null) ...[
                          SizedBox(height: tokens.spacing.s4),
                          Text(
                            '“${entries[index].reason}”',
                            style: tokens.typography.bodyMedium.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One line of an activity or audit list: a glyph in a well, a sentence, an
/// optional second line, a time at the end.
final class PlatformLine extends StatelessWidget {
  const PlatformLine({
    super.key,
    required this.icon,
    required this.sentence,
    required this.time,
    this.tone,
    this.detail,
    this.first = false,
  });

  final IconData icon;
  final PlatformTone? tone;
  final InlineSpan sentence;
  final String? detail;
  final String time;

  /// The first line of a group draws no rule above it.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final glyph = tone == null
        ? colors.text.secondary
        : platformToneColors(tokens, tone!).fg;
    return Container(
      padding: EdgeInsets.symmetric(vertical: tokens.spacing.s12),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(top: BorderSide(color: colors.surface.borderSubtle)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: tokens.spacing.s32,
            height: tokens.spacing.s32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surface.field,
              border: Border.all(color: colors.surface.cardEdge),
              borderRadius: BorderRadius.circular(tokens.radius.md),
            ),
            child: Icon(icon, size: tokens.icons.row, color: glyph),
          ),
          SizedBox(width: tokens.spacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text.rich(
                  sentence,
                  style: tokens.typography.bodyMedium.copyWith(
                    color: colors.text.primary,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: tokens.typography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: tokens.spacing.s12),
          Text(
            time,
            style: tokens.typography.caption.copyWith(
              color: colors.text.tertiary,
              height:
                  tokens.typography.bodyMedium.height! *
                  tokens.typography.bodyMedium.fontSize! /
                  tokens.typography.caption.fontSize!,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bold, for a name inside a sentence.
TextSpan platformBold(BuildContext context, String text) {
  final tokens = AppTokens.componentOf(context);
  return TextSpan(
    text: text,
    style: TextStyle(fontWeight: tokens.typography.labelMedium.fontWeight),
  );
}

// ---------------------------------------------------------------------------
// Loading.
// ---------------------------------------------------------------------------

/// Reads [load] once, again on [reload], and draws [builder] with what came
/// back. **An answer that arrives after a newer request is dropped**, which is
/// the same guard every platform screen before this carried by hand.
final class PlatformLoader<T> extends StatefulWidget {
  const PlatformLoader({
    super.key,
    required this.load,
    required this.builder,
    required this.loadingMessage,
    required this.failure,
    required this.boundary,
    this.isCurrent,
  });

  final Future<T> Function() load;
  final Widget Function(
    BuildContext context,
    T value,
    Future<void> Function() reload,
  )
  builder;
  final String loadingMessage;

  /// What the error state says was not read.
  final String failure;

  /// The telemetry boundary a failure is reported under.
  final String boundary;
  final bool Function()? isCurrent;

  @override
  State<PlatformLoader<T>> createState() => PlatformLoaderState<T>();
}

final class PlatformLoaderState<T> extends State<PlatformLoader<T>> {
  T? _value;
  bool _failed = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void didUpdateWidget(covariant PlatformLoader<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.load, widget.load) &&
        oldWidget.key != widget.key) {
      reload();
    }
  }

  bool _current(int epoch) =>
      mounted && epoch == _epoch && (widget.isCurrent?.call() ?? true);

  Future<void> reload() async {
    final epoch = ++_epoch;
    setState(() => _failed = false);
    try {
      final value = await widget.load();
      if (!_current(epoch)) return;
      setState(() => _value = value);
    } catch (error, stackTrace) {
      reportPlatformRead(error, stackTrace, widget.boundary);
      if (!_current(epoch)) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    if (_failed && value == null) {
      return ErrorState(
        badgeLabel: 'Not read',
        statement: widget.failure,
        stillTrue: 'Nothing was changed.',
        actions: <Widget>[
          AppButton(
            label: 'Try again',
            icon: Icons.refresh,
            tier: AppButtonTier.primary,
            onPressed: reload,
          ),
        ],
      );
    }
    if (value == null) return LoadingState(message: widget.loadingMessage);
    return widget.builder(context, value, reload);
  }
}
