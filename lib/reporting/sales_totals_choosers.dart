import 'package:flutter/material.dart';

import '../tenancy/tenant_staff_names.dart';
import '../ui/fields.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The period is never null - there is no "no period" reading of a
        // totals page - so a null answer is impossible and is refused rather
        // than silently mapped onto a default.
        AppSelect<TenantSalesPeriod>(
          key: const ValueKey('sales-totals-period'),
          label: 'Period',
          leading: Icons.date_range_outlined,
          value: period,
          onChanged: (value) => onChoosePeriod(value!),
          items: <AppSelectItem<TenantSalesPeriod>>[
            for (final option in TenantSalesPeriod.values)
              AppSelectItem<TenantSalesPeriod>(
                key: ValueKey('sales-totals-period-${option.name}'),
                value: option,
                label: option.label,
              ),
          ],
        ),
        SizedBox(height: tokens.spacing.s12),
        AppSelect<String?>(
          key: const ValueKey('sales-totals-member'),
          label: 'Member',
          leading: Icons.person_outline,
          value: soldById,
          onChanged: onChooseMember,
          items: <AppSelectItem<String?>>[
            const AppSelectItem<String?>(
              key: ValueKey('sales-totals-member-all'),
              value: null,
              label: 'Whole business',
            ),
            // The signed-in member is always offered, directory or not: its UID
            // comes from the session, which no read can make unavailable.
            if (selfUid case final uid?)
              AppSelectItem<String?>(
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
        ),
        if (!staff.readable) ...[
          SizedBox(height: tokens.spacing.s8),
          const Text(
            key: ValueKey('sales-totals-staff-unavailable'),
            'The staff list could not be read, so only your own sales can be '
            'separated out.',
          ),
        ] else if (staff.truncated) ...[
          SizedBox(height: tokens.spacing.s8),
          const Text(
            key: ValueKey('sales-totals-staff-truncated'),
            'This business has more members than are listed here.',
          ),
        ],
        if (!categories.readable) ...[
          SizedBox(height: tokens.spacing.s12),
          const Text(
            key: ValueKey('sales-totals-categories-unavailable'),
            'The category list could not be read, so only the whole-catalog '
            'total is available.',
          ),
        ] else if (categories.items.isNotEmpty) ...[
          SizedBox(height: tokens.spacing.s12),
          AppSelect<String?>(
            key: const ValueKey('sales-totals-category'),
            label: 'Category',
            leading: Icons.category_outlined,
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
          ),
        ],
      ],
    );
  }
}
