import 'package:flutter/material.dart';

import '../tenancy/tenant_staff_names.dart';
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
        Wrap(
          key: const ValueKey('sales-totals-period'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in TenantSalesPeriod.values)
              ChoiceChip(
                key: ValueKey('sales-totals-period-${option.name}'),
                label: Text(option.label),
                selected: option == period,
                onSelected: (_) => onChoosePeriod(option),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          key: const ValueKey('sales-totals-member'),
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey('sales-totals-member-all'),
              label: const Text('Whole business'),
              selected: soldById == null,
              onSelected: (_) => onChooseMember(null),
            ),
            // The signed-in member is always offered, directory or not: its UID
            // comes from the session, which no read can make unavailable.
            if (selfUid case final uid?)
              ChoiceChip(
                key: const ValueKey('sales-totals-member-self'),
                label: Text(
                  tenantStaffLabel(uid, names: staff.names, selfUid: uid),
                ),
                selected: soldById == uid,
                onSelected: (_) => onChooseMember(uid),
              ),
            for (final uid in staff.uids)
              if (uid != selfUid)
                ChoiceChip(
                  key: ValueKey('sales-totals-member-$uid'),
                  label: Text(
                    tenantStaffLabel(uid, names: staff.names, selfUid: selfUid),
                  ),
                  selected: soldById == uid,
                  onSelected: (_) => onChooseMember(uid),
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
          Wrap(
            key: const ValueKey('sales-totals-category'),
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('sales-totals-category-all'),
                label: const Text('All categories'),
                selected: categoryId == null,
                onSelected: (_) => onChooseCategory(null),
              ),
              for (final category in categories.items)
                ChoiceChip(
                  key: ValueKey('sales-totals-category-${category.id}'),
                  label: Text(category.name),
                  selected: category.id == categoryId,
                  onSelected: (_) => onChooseCategory(category.id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
