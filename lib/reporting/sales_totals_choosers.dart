import 'package:flutter/material.dart';

import '../tenancy/tenant_staff_names.dart';
import '../ui/chips.dart';
import 'sales_totals.dart';
import 'sales_totals_session_context.dart';

/// The period, member, and category choosers, with the notices that explain a
/// chooser that is narrower than it should be.
///
/// They travel together because they are one control surface: all three stay on
/// screen through a failure, since a period that holds too many sales is
/// refused precisely so a shorter one can be picked.
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

  /// The signed-in member, so its own chip reads "You" rather than a UID.
  final String? selfUid;

  final String? categoryId;

  /// The categories and colleagues this session may filter by.
  final SalesTotalsSessionContext sessionContext;

  final ValueChanged<TenantSalesPeriod> onChoosePeriod;
  final ValueChanged<String?> onChooseMember;
  final ValueChanged<String?> onChooseCategory;

  @override
  Widget build(BuildContext context) {
    final staff = sessionContext.staff;
    final categories = sessionContext.categories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Chips rather than a segmented button: four periods do not fit across
        // a phone, and a chooser that overflows is a chooser that cannot be
        // used.
        FilterChipBar<TenantSalesPeriod>(
          key: const ValueKey('sales-totals-period'),
          semanticLabel: 'Choose the period',
          selected: period,
          // The period is never null - there is no "no period" reading of a
          // totals page - so a null answer is impossible and is refused rather
          // than silently mapped onto a default.
          onSelected: (value) => onChoosePeriod(value!),
          options: <FilterChipOption<TenantSalesPeriod>>[
            for (final option in TenantSalesPeriod.values)
              FilterChipOption<TenantSalesPeriod>(
                key: ValueKey('sales-totals-period-${option.name}'),
                value: option,
                label: option.label,
              ),
          ],
        ),
        const SizedBox(height: 12),
        FilterChipBar<String>(
          key: const ValueKey('sales-totals-member'),
          semanticLabel: 'Narrow the totals to one member',
          selected: soldById,
          onSelected: onChooseMember,
          options: <FilterChipOption<String>>[
            const FilterChipOption<String>(
              key: ValueKey('sales-totals-member-all'),
              value: null,
              label: 'Whole business',
            ),
            // The signed-in member is always offered, directory or not: its UID
            // comes from the session, which no read can make unavailable.
            if (selfUid case final uid?)
              FilterChipOption<String>(
                key: const ValueKey('sales-totals-member-self'),
                value: uid,
                label: tenantStaffLabel(uid, names: staff.names, selfUid: uid),
              ),
            for (final uid in staff.uids)
              if (uid != selfUid)
                FilterChipOption<String>(
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
          const SizedBox(height: 8),
          const Text(
            key: ValueKey('sales-totals-staff-unavailable'),
            'The staff list could not be read, so only your own sales can be '
            'separated out.',
          ),
        ] else if (staff.truncated) ...[
          const SizedBox(height: 8),
          const Text(
            key: ValueKey('sales-totals-staff-truncated'),
            'This business has more members than are listed here.',
          ),
        ],
        if (!categories.readable) ...[
          const SizedBox(height: 12),
          const Text(
            key: ValueKey('sales-totals-categories-unavailable'),
            'The category list could not be read, so only the whole-catalog '
            'total is available.',
          ),
        ] else if (categories.items.isNotEmpty) ...[
          const SizedBox(height: 12),
          FilterChipBar<String>(
            key: const ValueKey('sales-totals-category'),
            semanticLabel: 'Narrow the totals to one category',
            selected: categoryId,
            onSelected: onChooseCategory,
            options: <FilterChipOption<String>>[
              const FilterChipOption<String>(
                key: ValueKey('sales-totals-category-all'),
                value: null,
                label: 'All categories',
              ),
              for (final category in categories.items)
                FilterChipOption<String>(
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
