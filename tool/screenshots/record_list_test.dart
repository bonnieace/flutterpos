/// Step 6's second half: `design.md` §4.3's `RecordList` contract,
/// photographed.
///
/// **The matrix of this component is §4.3's own row, and it is the first one
/// the harness has had to grow a viewport for.** `RecordList` becomes stacked
/// cards, two-column cards, or a data table, and the middle of those three is
/// reachable only between 768 and 1023 - a band no picture in this directory
/// covered until now. Every case below is therefore captured at all three
/// bands, and the `tablet/` images are the whole reason the band exists in the
/// harness.
///
/// The cases are the dimensions the contract actually has:
///
/// - **`96-record-list`** - the full record: identity, status, attributes,
///   provenance, actions. What the three forms do to one list.
/// - **`96-record-list-narrow-loss`** - the one opt-out §4.3 concedes. Two of
///   the five attributes are marked out of the narrow form, so the table has
///   five columns and the cards show three. **The evidence is the difference
///   between this and the case above**, at the two card bands.
/// - **`96-record-actions`** - §4.3's `ActionSet` row past three: a menu on a
///   phone, three and a menu on a tablet, five inline on a desktop window.
/// - **`96-record-list-empty`** - the caller's own words where the rows would
///   be. `EmptyState` is §5.1's, at priority 2, and does not exist.
/// - **`96-record-details`** - the slot §5.2 does not name, added on 2026-08-13
///   with the staff directory: a form one of a record's actions opened. **The
///   `medium` picture is the one worth looking at** - it is the case that
///   exposed a `Row` in five staff forms that could not fit half a page, and it
///   is where a form's buttons wrap to a second line.
///
/// - **`96-record-columns`** - the column arithmetic, added 2026-08-15 with
///   [RecordTableColumns]. It is the one case built to be *hard*: six columns, a
///   standing on one record of four, a provenance line long enough to wrap, one
///   record with four actions where its neighbours have two, and one column of
///   prose. All four of the observations `PLAN.md` carried about the old
///   constants are visible in the `web` picture of it, and the `mobile` and
///   `tablet` ones are the control - a card stacks, so none of this reaches it.
///
/// **A record's states are not §5's nine.** A record is not a control: it has
/// no hover, no focus-visible, no pressed and no loading, because the only
/// things on it that can be pressed are its actions, and those are `AppButton`s
/// that brought their own six to `93-*`. `disabled` belongs to an action and is
/// captured in the actions case; `empty` belongs to the list and has its own.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/fields.dart';
import 'package:flutter_application_1/ui/record_list.dart';
import 'package:flutter_application_1/ui/scaffold.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_application_1/ui/tokens.dart';

import 'harness.dart';

/// Five products, which is the shape most of step 6's thirteen screens are.
List<RecordItem> _catalog({bool withLoss = false}) => <RecordItem>[
  _product(
    id: 'p1',
    name: 'Fresh whole milk 500ml',
    code: 'MLK-500',
    price: 'KES 65.00',
    cost: 'KES 48.00',
    stock: '24',
    status: const RecordStatus(status: AppStatus.ok, label: 'In stock'),
    withLoss: withLoss,
  ),
  _product(
    id: 'p2',
    name: 'White bread, sliced',
    code: 'BRD-800',
    price: 'KES 70.00',
    cost: 'KES 52.00',
    stock: '11',
    status: const RecordStatus(status: AppStatus.ok, label: 'In stock'),
    withLoss: withLoss,
  ),
  _product(
    id: 'p3',
    name: 'Cooking oil 1L',
    code: 'OIL-1000',
    price: 'KES 320.00',
    cost: 'KES 268.00',
    stock: '0',
    status: const RecordStatus(
      status: AppStatus.problem,
      label: 'Out of stock',
    ),
    withLoss: withLoss,
  ),
  _product(
    id: 'p4',
    name: 'Sugar 1kg',
    code: 'SUG-1000',
    price: 'KES 180.00',
    cost: 'KES 151.00',
    stock: '40',
    status: const RecordStatus(status: AppStatus.ok, label: 'In stock'),
    withLoss: withLoss,
  ),
  _product(
    id: 'p5',
    name: 'Maize flour 2kg, sifted',
    code: 'FLR-2000',
    price: 'KES 210.00',
    cost: 'KES 178.00',
    stock: '18',
    status: const RecordStatus(status: AppStatus.neutral, label: 'Retired'),
    withLoss: withLoss,
  ),
];

RecordItem _product({
  required String id,
  required String name,
  required String code,
  required String price,
  required String cost,
  required String stock,
  required RecordStatus status,
  required bool withLoss,
}) => RecordItem(
  id: id,
  title: name,
  subtitle: 'Dairy and chilled',
  status: status,
  attributes: <RecordAttribute>[
    RecordAttribute(label: 'Price', value: price),
    RecordAttribute(label: 'In stock', value: stock),
    // The two a shopkeeper scanning a phone did not come for. A code is
    // compared character by character on a wide screen; a cost is the figure
    // §4.2 puts 1,300 pixels away from the name it belongs to today.
    RecordAttribute(label: 'Code', value: code, inNarrowForm: !withLoss),
    RecordAttribute(label: 'Cost', value: cost, inNarrowForm: !withLoss),
  ],
  provenance: 'Recorded 2026-08-01 09:00 UTC by Amina',
  actions: <RecordAction>[
    RecordAction(label: 'Correct', onPressed: () {}),
    RecordAction(label: 'Adjust stock', onPressed: () {}),
  ],
);

/// One record with five actions, which is §4.3's `ActionSet` row past three.
///
/// The last is disabled and the last but one is destructive, so the `>3` rule,
/// the destructive tier and the disabled rendering are all in the same picture.
RecordItem _manyActions() => RecordItem(
  id: 'm1',
  title: 'Amina Odhiambo',
  subtitle: 'amina@example.com',
  status: const RecordStatus(status: AppStatus.attention, label: 'Pending'),
  attributes: const <RecordAttribute>[
    RecordAttribute(label: 'Role', value: 'manager'),
    RecordAttribute(label: 'Invitation', value: 'sent'),
  ],
  provenance: 'Recorded 2026-08-01 09:00 UTC by You',
  actions: <RecordAction>[
    RecordAction(label: 'Edit', onPressed: () {}),
    RecordAction(label: 'Resend invitation', onPressed: () {}),
    RecordAction(label: 'Replace email', onPressed: () {}),
    RecordAction(label: 'Cancel invitation', destructive: true, onPressed: () {}),
    const RecordAction(label: 'Deactivate', onPressed: null),
  ],
);

/// One member with a form open under them, which is `RecordItem.details`.
///
/// The form is the shape all five of the staff directory's are - a field, then
/// a cancel and a confirm - so the picture answers the question that matters
/// about the slot: whether a form is usable in the width the band gives it.
List<RecordItem> _withDetailsOpen() => <RecordItem>[
  RecordItem(
    id: 'm1',
    title: 'Amina Hassan',
    subtitle: 'amina@devcorner.test',
    status: const RecordStatus(status: AppStatus.ok, label: 'Active'),
    attributes: const <RecordAttribute>[
      RecordAttribute(label: 'Role', value: 'manager'),
    ],
    actions: <RecordAction>[
      RecordAction(label: 'Edit', icon: Icons.edit_outlined, onPressed: () {}),
      RecordAction(
        label: 'Deactivate',
        icon: Icons.person_off_outlined,
        destructive: true,
        onPressed: () {},
      ),
    ],
    details: const _StandInForm(),
  ),
  RecordItem(
    id: 'm2',
    title: 'Brian Kimani',
    subtitle: 'brian@devcorner.test',
    status: const RecordStatus(status: AppStatus.ok, label: 'Active'),
    attributes: const <RecordAttribute>[
      RecordAttribute(label: 'Role', value: 'cashier'),
    ],
    actions: <RecordAction>[
      RecordAction(label: 'Edit', icon: Icons.edit_outlined, onPressed: () {}),
      RecordAction(
        label: 'Deactivate',
        icon: Icons.person_off_outlined,
        destructive: true,
        onPressed: () {},
      ),
    ],
  ),
];

final class _StandInForm extends StatefulWidget {
  const _StandInForm();

  @override
  State<_StandInForm> createState() => _StandInFormState();
}

final class _StandInFormState extends State<_StandInForm> {
  final TextEditingController _name = TextEditingController(
    text: 'Amina Hassan',
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppTextField(label: 'Full name', controller: _name),
        SizedBox(height: tokens.spacing.s16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: tokens.spacing.s8,
          runSpacing: tokens.spacing.s8,
          children: <Widget>[
            AppButton(
              label: 'Cancel',
              tier: AppButtonTier.tertiary,
              onPressed: () {},
            ),
            AppButton(
              label: 'Save changes',
              icon: Icons.save_outlined,
              tier: AppButtonTier.primary,
              onPressed: () {},
            ),
          ],
        ),
      ],
    );
  }
}

/// A six-column ledger, which is the widest shape any of step 6's twelve
/// screens reaches, with every one of the four column-arithmetic observations in
/// it at once.
///
/// The numbers it is built from are the ones the observations were made against:
/// `web/30-shift-corrections` has six columns and ran two values together;
/// `web/23-stock-movements` wrapped a 55-character provenance line on every row;
/// `web-full/13-staff-directory` has one record with four actions and three with
/// two; and `web-full/18-manage-catalog` has a status on two rows of seven.
List<RecordItem> _ledger() => <RecordItem>[
  _movement(
    id: 'mv1',
    product: 'Fresh whole milk 500ml',
    figures: '24 to 18',
    type: 'Sale',
    reason: 'Sold on receipt R-000482',
    source: 'sale-000482',
    counted: '18',
    standing: null,
    actions: 2,
  ),
  _movement(
    id: 'mv2',
    product: 'White bread, sliced',
    figures: '11 to 40',
    type: 'Delivery',
    reason: 'Weekly delivery from Njoro Bakers, checked in by the till',
    source: 'adj-000119',
    counted: '40',
    standing: null,
    actions: 2,
  ),
  _movement(
    id: 'mv3',
    product: 'Cooking oil 1L',
    figures: 'Not recorded',
    type: 'Reconciled sale',
    reason: 'Written by nightly reconciliation',
    source: 'rj-000007',
    counted: '0',
    standing: const RecordStatus(
      status: AppStatus.attention,
      label: 'Difference found',
    ),
    actions: 4,
  ),
  _movement(
    id: 'mv4',
    product: 'Maize flour 2kg, sifted',
    figures: '18 to 17',
    type: 'Correction',
    reason: 'Counted short at close',
    source: 'adj-000121',
    counted: '17',
    standing: null,
    actions: 2,
  ),
];

RecordItem _movement({
  required String id,
  required String product,
  required String figures,
  required String type,
  required String reason,
  required String source,
  required String counted,
  required RecordStatus? standing,
  required int actions,
}) => RecordItem(
  id: id,
  title: product,
  subtitle: 'Dairy and chilled',
  status: standing,
  attributes: <RecordAttribute>[
    RecordAttribute(label: 'Before and after', value: figures),
    RecordAttribute(label: 'Adjustment type', value: type),
    RecordAttribute(label: 'Reason', value: reason, flex: 2),
    RecordAttribute(label: 'Source', value: source),
    RecordAttribute(label: 'On hand', value: counted),
  ],
  provenance: 'Recorded 2026-08-10 08:30 UTC by Grace Wanjiru (owner-dev)',
  actions: <RecordAction>[
    RecordAction(
      label: 'Open the product',
      icon: Icons.inventory_2_outlined,
      onPressed: () {},
    ),
    if (actions > 2) ...<RecordAction>[
      RecordAction(
        label: 'Ask for a re-run',
        icon: Icons.refresh_outlined,
        onPressed: () {},
      ),
      RecordAction(
        label: 'Find the receipt',
        icon: Icons.receipt_long_outlined,
        onPressed: () {},
      ),
    ],
    RecordAction(
      label: 'Adjust stock',
      icon: Icons.tune_outlined,
      onPressed: () {},
    ),
  ],
);

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.list});

  final String title;
  final RecordList list;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: title,
    contentWidth: AppContentWidth.records,
    body: Builder(
      builder: (context) {
        final tokens = AppTokens.componentOf(context);
        return ListView(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s20),
          children: <Widget>[list],
        );
      },
    ),
  );
}

void main() {
  screenshotCase(
    '96-record-list',
    viewports: everyBandViewports,
    build: () => _Page(
      title: 'Manage catalog',
      list: RecordList(identityLabel: 'Product', items: _catalog()),
    ),
  );

  screenshotCase(
    '96-record-list-narrow-loss',
    viewports: everyBandViewports,
    build: () => _Page(
      title: 'Manage catalog',
      list: RecordList(
        identityLabel: 'Product',
        items: _catalog(withLoss: true),
      ),
    ),
  );

  screenshotCase(
    '96-record-actions',
    viewports: everyBandViewports,
    build: () => _Page(
      title: 'Staff directory',
      list: RecordList(
        identityLabel: 'Member',
        items: <RecordItem>[_manyActions()],
      ),
    ),
  );

  screenshotCase(
    '96-record-details',
    viewports: everyBandViewports,
    build: () => _Page(
      title: 'Staff directory',
      list: RecordList(identityLabel: 'Member', items: _withDetailsOpen()),
    ),
  );

  screenshotCase(
    '96-record-columns',
    viewports: everyBandViewports,
    build: () => _Page(
      title: 'Stock movements',
      list: RecordList(identityLabel: 'Movement', items: _ledger()),
    ),
  );

  screenshotCase(
    '96-record-list-empty',
    viewports: everyBandViewports,
    build: () => const _Page(
      title: 'Activity log',
      list: RecordList(
        identityLabel: 'Event',
        items: <RecordItem>[],
        empty: Text('No event has been recorded for this business.'),
      ),
    ),
  );
}
