import 'package:flutter/material.dart';

import '../tenancy/tenant_staff_names.dart';
import '../ui/fields.dart';
import '../ui/press.dart';
import '../ui/tokens.dart';
import 'sales_totals.dart';
import 'sales_totals_session_context.dart';

/// The period, member, and category choosers, with the notices that explain a
/// chooser that is narrower than it should be.
///
/// They travel together because they are one control surface: all three stay on
/// screen through a failure, since a period that holds too many sales is
/// refused precisely so a shorter one can be picked.
///
/// **All three are `AppSelect` rather than `FilterChipBar`, since 2026-08-23 and
/// at the product owner's direction: where a surface carries more than one
/// filter, the filters are dropdowns.** This is the surface the direction is
/// about. It is the only one in the app with three filters open at once, and as
/// chip strips they were a wall of pills three rows deep whose height grew with
/// the business - one chip per colleague and one per category, so a shop with
/// twelve staff and nine categories pushed the figures the page exists for off
/// the bottom of a phone. A dropdown is a fixed height whatever the business
/// holds.
///
/// A single filter stays a chip strip, and that is the other half of the same
/// rule: one strip is scannable and shows its options without a tap, which is
/// what `FilterChipBar` is for. `reconciliation_anomalies_panel.dart` and the
/// till's category chooser keep theirs.
final class SalesTotalsChoosers extends StatelessWidget {
  const SalesTotalsChoosers({
    super.key,
    required this.period,
    required this.soldById,
    required this.selfUid,
    required this.categoryId,
    required this.sessionContext,
    required this.onChoosePeriod,
    required this.onChooseMember,
    required this.onChooseCategory,
  });

  final TenantSalesPeriod period;
  final String? soldById;

  /// The signed-in member, so its own row reads "You" rather than a UID.
  final String? selfUid;

  final String? categoryId;

  /// The categories and colleagues this session may filter by.
  final SalesTotalsSessionContext sessionContext;

  final ValueChanged<TenantSalesPeriod> onChoosePeriod;
  final ValueChanged<String?> onChooseMember;
  final ValueChanged<String?> onChooseCategory;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final staff = sessionContext.staff;
    final categories = sessionContext.categories;
    final index = TenantSalesPeriod.values.indexOf(period);
    // **A stepper rather than a menu, and the order is the enum's.** The four
    // periods are a ladder - today, a week, a month, a quarter - so stepping
    // along it is one tap where opening a menu and picking was three, and the
    // reading stays on screen while it changes. A menu was also the only
    // control on this page that hid its own current value behind a tap.
    final categorySelect = categories.readable && categories.items.isNotEmpty
        ? AppSelect<String?>(
            key: const ValueKey('sales-totals-category'),
            label: 'Category',
            value: categoryId,
            onChanged: onChooseCategory,
            items: <AppSelectItem<String?>>[
              const AppSelectItem<String?>(
                key: ValueKey('sales-totals-category-all'),
                value: null,
                label: 'All categories',
              ),
              for (final category in categories.items)
                AppSelectItem<String?>(
                  key: ValueKey('sales-totals-category-${category.id}'),
                  value: category.id,
                  label: category.name,
                ),
            ],
          )
        : null;
    final memberSelect = AppSelect<String?>(
      key: const ValueKey('sales-totals-member'),
      label: 'Member',
      value: soldById,
      onChanged: onChooseMember,
      items: <AppSelectItem<String?>>[
        const AppSelectItem<String?>(
          key: ValueKey('sales-totals-member-all'),
          value: null,
          label: 'All members',
        ),
        // The signed-in member is always offered, directory or not: its UID
        // comes from the session, which no read can make unavailable.
        if (selfUid case final uid?)
          AppSelectItem<String?>(
            // **Keyed by role, not by UID.** A test and the home both reach
            // "only mine" without knowing whose session it is.
            key: const ValueKey('sales-totals-member-self'),
            value: uid,
            label: tenantStaffLabel(uid, names: staff.names, selfUid: uid),
          ),
        for (final uid in staff.uids)
          if (uid != selfUid)
            AppSelectItem<String?>(
              key: ValueKey('sales-totals-member-$uid'),
              value: uid,
              label: tenantStaffLabel(
                uid,
                names: staff.names,
                selfUid: selfUid,
              ),
            ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _PeriodStep(
              semanticLabel: 'Earlier period',
              icon: Icons.chevron_left,
              // The enum runs shortest first, so *earlier* is forward along it.
              onPressed: index < TenantSalesPeriod.values.length - 1
                  ? () => onChoosePeriod(TenantSalesPeriod.values[index + 1])
                  : null,
            ),
            Expanded(
              child: Text(
                period.label,
                key: const ValueKey('sales-totals-period'),
                textAlign: TextAlign.center,
                style: tokens.typography.titleMedium.copyWith(
                  color: tokens.colors.text.primary,
                ),
              ),
            ),
            _PeriodStep(
              semanticLabel: 'Shorter period',
              icon: Icons.chevron_right,
              // There is nothing shorter than today, and a control that looks
              // pressable and does nothing is worse than one that says it
              // cannot.
              onPressed: index > 0
                  ? () => onChoosePeriod(TenantSalesPeriod.values[index - 1])
                  : null,
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.s12),
        // **Two filters, one row.** They qualify the same figure and are read
        // together; stacked, they pushed the takings below the fold on a phone
        // for no reading they gave back.
        //
        // **Captioned rather than dense, which is the opposite of what half
        // width suggests.** `AppSelect.dense` trades the caption for a leading
        // glyph, and at 183 logical pixels the glyph, its gap and the well's
        // padding leave about ten characters - so both columns read *All
        // memb...* and *All catego...*, naming neither the filter nor its
        // value. The caption costs one line of height once and gives the value
        // the width back.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: memberSelect),
            if (categorySelect case final select?) ...[
              SizedBox(width: tokens.spacing.s12),
              Expanded(child: select),
            ],
          ],
        ),
        if (!staff.readable) ...[
          SizedBox(height: tokens.spacing.s8),
          const Text(
            key: ValueKey('sales-totals-staff-unavailable'),
            'The colleague list could not be read, so only the whole-business '
            'total is available.',
          ),
        ] else if (staff.truncated) ...[
          SizedBox(height: tokens.spacing.s8),
          const Text(
            key: ValueKey('sales-totals-staff-truncated'),
            'This business has more members than are listed here.',
          ),
        ],
        if (!categories.readable) ...[
          SizedBox(height: tokens.spacing.s8),
          const Text(
            key: ValueKey('sales-totals-categories-unavailable'),
            'The category list could not be read, so only the whole-catalog '
            'total is available.',
          ),
        ] else if (categories.truncated) ...[
          SizedBox(height: tokens.spacing.s8),
          const Text(
            key: ValueKey('sales-totals-categories-truncated'),
            'This business has more categories than are listed here.',
          ),
        ],
      ],
    );
  }
}

/// One end of the period stepper.
final class _PeriodStep extends StatelessWidget {
  const _PeriodStep({
    required this.semanticLabel,
    required this.icon,
    required this.onPressed,
  });

  final String semanticLabel;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final size = tokens.density.minimumTapTarget;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: PressSurface(
        borderRadius: BorderRadius.circular(tokens.radius.pill),
        onPressed: onPressed,
        hoverOverlay: tokens.colors.action.secondary.hoverFill(),
        pressedOverlay: tokens.colors.action.secondary.pressedFill(),
        excludeSemantics: true,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Icon(
            icon,
            color: onPressed == null
                ? tokens.colors.text.disabled
                : tokens.colors.text.secondary,
          ),
        ),
      ),
    );
  }
}
