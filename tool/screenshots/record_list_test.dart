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
///
/// **A record's states are not §5's nine.** A record is not a control: it has
/// no hover, no focus-visible, no pressed and no loading, because the only
/// things on it that can be pressed are its actions, and those are `AppButton`s
/// that brought their own six to `93-*`. `disabled` belongs to an action and is
/// captured in the actions case; `empty` belongs to the list and has its own.
library;

import 'package:flutter/material.dart';
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
