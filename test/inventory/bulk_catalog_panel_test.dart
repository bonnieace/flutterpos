import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/notices.dart';

import '../support/buttons.dart';

const String _productsPath = 'tenants/tenant-a/products';
const String _categoriesPath = 'tenants/tenant-a/categories';

/// Two products and one refusable row, which is the smallest sheet that proves
/// the report is per row rather than a count.
const String _sheet =
    'name,sku,price,quantity,category\n'
    'Mandazi,M-1,20,12,Bakery\n'
    'Samosa,S-1,25,,Bakery\n';

void main() {
  testWidgets('a cashier is refused the whole route', (tester) async {
    await _pump(
      tester,
      _controller(role: TenantRole.cashier),
      _Reader.seeded(),
      batch: _BatchCallable(),
      import: _ImportCallable(),
    );

    expect(find.byKey(const ValueKey('bulk-catalog-denied')), findsOne);
    expect(find.byKey(const ValueKey('bulk-catalog-preview')), findsNothing);
  });

  testWidgets('a build with neither callable offers neither half', (
    tester,
  ) async {
    await _pump(tester, _controller(), _Reader.seeded());

    expect(find.byKey(const ValueKey('bulk-catalog-unavailable')), findsOne);
    expect(_enabled(tester, 'bulk-catalog-preview'), isFalse);

    await _choose(tester, 'bulk-catalog-task-import');

    expect(find.byKey(const ValueKey('bulk-catalog-unavailable')), findsOne);
    expect(_enabled(tester, 'bulk-catalog-preview'), isFalse);
  });

  testWidgets('a correction is previewed, reported per row, then applied', (
    tester,
  ) async {
    final batch = _BatchCallable();
    var syncs = 0;

    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      batch: batch,
      onChanged: () => syncs++,
    );
    await _select(tester, 'pd-001');
    await _select(tester, 'pd-002');
    await _choose(tester, 'bulk-catalog-category-cat-drinks');

    expect(_text(tester, 'bulk-catalog-selection'), startsWith('2 products'));
    await _tap(tester, 'bulk-catalog-preview');

    // A preview writes nothing and says so, and the report names every row
    // rather than counting them.
    expect(batch.payloads.single['mode'], 'preview');
    expect(
      _text(tester, 'bulk-catalog-summary'),
      startsWith('Nothing has been written. 2 would be corrected'),
    );
    expect(find.byKey(const ValueKey('bulk-catalog-row-1')), findsOne);
    expect(find.byKey(const ValueKey('bulk-catalog-row-2')), findsOne);
    expect(
      _text(tester, 'bulk-catalog-row-detail-1'),
      'Product 1 • from Bakery to Drinks',
    );

    await _tap(tester, 'bulk-catalog-commit');
    // The confirmation states the consequence of this particular field, and that
    // nothing else about a product moves.
    expect(find.textContaining('Every grouped report'), findsOne);
    expect(find.textContaining('their stock is untouched'), findsOne);
    await _tap(tester, 'bulk-catalog-confirm');

    // One request ID across the preview and its commit, which is exactly what
    // the server's write-no-record-for-a-preview decision exists to allow.
    expect(batch.payloads, hasLength(2));
    expect(batch.payloads.last['mode'], 'commit');
    expect(batch.payloads.last['requestId'], batch.payloads.first['requestId']);
    expect(batch.payloads.last['rows'], batch.payloads.first['rows']);
    expect(syncs, 1);
    expect(find.byKey(const ValueKey('bulk-catalog-committed')), findsOne);
    expect(
      _text(tester, 'bulk-catalog-summary'),
      startsWith('2 were corrected'),
    );
    // The selection is emptied, so the next correction is not a near-repeat of
    // one that already landed.
    expect(_text(tester, 'bulk-catalog-selection'), 'No products chosen.');
  });

  testWidgets('a manager is offered no money correction at all', (
    tester,
  ) async {
    await _pump(
      tester,
      _controller(role: TenantRole.manager),
      _Reader.seeded(),
      batch: _BatchCallable(),
    );

    // One row naming money refuses every row with it, so the whole correction is
    // withheld rather than offered and refused.
    expect(find.byKey(const ValueKey('bulk-catalog-field-price')), findsNothing);
    expect(find.byKey(const ValueKey('bulk-catalog-field-cost')), findsNothing);
    expect(
      find.byKey(const ValueKey('bulk-catalog-field-clear-cost')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('bulk-catalog-field-categoryId')), findsOne);
    expect(
      _callout(tester, 'bulk-catalog-money-hidden'),
      contains('refuses every row'),
    );
  });

  testWidgets('a manager\'s sheet with a cost column is refused whole', (
    tester,
  ) async {
    final import = _ImportCallable();

    await _pump(
      tester,
      _controller(role: TenantRole.manager),
      _Reader.seeded(),
      import: import,
    );
    await _choose(tester, 'bulk-catalog-task-import');
    expect(
      _callout(tester, 'bulk-catalog-import-cost-hidden'),
      contains('A price is not'),
    );
    await _paste(tester, 'name,sku,price,cost,category\nMandazi,M-1,20,9,Bakery');
    await _tap(tester, 'bulk-catalog-preview');

    // Refused before anything is sent, where the server also decides it: over
    // the request, before any row is read.
    expect(import.payloads, isEmpty);
    expect(
      snackNotice(tester).message,
      startsWith('Only an owner or administrator may record what a product'),
    );
    // Every value this notice can hold is a refusal raised before anything was
    // sent - the one surface in the family with no success branch - and the
    // type states that rather than leaving it to be traced.
    expect(snackNotice(tester).status, AppStatus.problem);
    // Every value this notice can hold is a refusal raised before anything was
    // sent, which the type now states rather than leaving to be traced.
    expect(snackNotice(tester).status, AppStatus.problem);
  });

  testWidgets('a repriced page states the before and the after of each row', (
    tester,
  ) async {
    final batch = _BatchCallable();

    await _pump(tester, _controller(), _Reader.seeded(), batch: batch);
    await _select(tester, 'pd-001');
    await _choose(tester, 'bulk-catalog-field-price');
    await _enter(tester, 'bulk-catalog-value', '19.99');
    await _tap(tester, 'bulk-catalog-preview');

    expect(
      _text(tester, 'bulk-catalog-row-detail-1'),
      'Product 1 • from 65.00 to 19.99',
    );
    await _tap(tester, 'bulk-catalog-commit');
    expect(find.textContaining('no figure already reported moves'), findsOne);
    await _tap(tester, 'bulk-catalog-cancel');

    // Cancelling sends nothing further and leaves the preview standing.
    expect(batch.payloads, hasLength(1));
    expect(find.byKey(const ValueKey('bulk-catalog-commit')), findsOne);
  });

  testWidgets('a category nothing can read is named, never shown as an ID', (
    tester,
  ) async {
    final batch = _BatchCallable();

    await _pump(
      tester,
      _controller(),
      _Reader.strandedCategory(),
      batch: batch,
    );

    // The row a person ticks, and then the report line describing what it is
    // being moved out of. Both used to state the document ID.
    expect(find.textContaining(unlistedTenantCategoryLabel), findsOne);
    await _select(tester, 'pd-001');
    await _choose(tester, 'bulk-catalog-category-cat-drinks');
    await _tap(tester, 'bulk-catalog-preview');

    expect(
      _text(tester, 'bulk-catalog-row-detail-1'),
      'Product 1 • from $unlistedTenantCategoryLabel to Drinks',
    );
    expect(_documentIdsOnScreen(tester), isEmpty);
  });

  testWidgets('a price the till could not record is refused where typed', (
    tester,
  ) async {
    final batch = _BatchCallable();

    await _pump(tester, _controller(), _Reader.seeded(), batch: batch);
    await _select(tester, 'pd-001');
    await _choose(tester, 'bulk-catalog-field-price');
    await _enter(tester, 'bulk-catalog-value', '19.999');
    await _tap(tester, 'bulk-catalog-preview');

    expect(batch.payloads, isEmpty);
    expect(
      snackNotice(tester).message,
      startsWith('The price must be a plain amount'),
    );
    expect(find.byKey(const ValueKey('bulk-catalog-summary')), findsNothing);
  });

  testWidgets('changing the selection throws the report away', (tester) async {
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      batch: _BatchCallable(),
    );
    await _select(tester, 'pd-001');
    await _choose(tester, 'bulk-catalog-category-cat-drinks');
    await _tap(tester, 'bulk-catalog-preview');
    expect(find.byKey(const ValueKey('bulk-catalog-summary')), findsOne);

    await _select(tester, 'pd-002');

    // A report describing rows that are no longer chosen is a statement about a
    // request nobody would now send.
    expect(find.byKey(const ValueKey('bulk-catalog-summary')), findsNothing);
    expect(find.byKey(const ValueKey('bulk-catalog-commit')), findsNothing);
  });

  testWidgets('a chain that stops part way says which requests answered', (
    tester,
  ) async {
    // Sixty products is two requests, because the server takes fifty at a time
    // and this side chains. They are chosen across two catalog pages, which is
    // the ordinary way a selection gets past fifty at all - a single read page is
    // itself bounded well below it. The second request is refused.
    final batch = _BatchCallable(
      failAt: 1,
      error: FirebaseFunctionsException(
        code: 'already-exists',
        message: 'A different request used this requestId.',
      ),
    );

    await _pump(
      tester,
      _controller(),
      _Reader.seeded(productCount: 60),
      batch: batch,
      pageSize: 40,
    );
    await _tap(tester, 'bulk-catalog-select-page');
    await _tap(tester, 'bulk-catalog-next-page');
    await _tap(tester, 'bulk-catalog-select-page');
    expect(_text(tester, 'bulk-catalog-selection'), startsWith('60 products'));
    await _choose(tester, 'bulk-catalog-category-cat-drinks');
    expect(_label(tester, 'bulk-catalog-preview'), 'Preview (2 requests)');
    await _tap(tester, 'bulk-catalog-preview');

    expect(batch.payloads, hasLength(2));
    expect(
      _text(tester, 'bulk-catalog-summary'),
      // "One of two requests" is a singular subject, so the noun agrees with
      // the total and the verb with the count answered.
      endsWith('1 of 2 requests was previewed.'),
    );
    expect(
      _callout(tester, 'bulk-catalog-report-failure'),
      allOf(contains('already used'), contains('Only the rows listed above')),
    );
    // The first page's rows are reported, and a commit is not offered: a preview
    // whose chain stopped has not described the whole change.
    expect(find.byKey(const ValueKey('bulk-catalog-row-50')), findsOne);
    expect(find.byKey(const ValueKey('bulk-catalog-row-51')), findsNothing);
    expect(_enabled(tester, 'bulk-catalog-commit'), isFalse);
  });

  testWidgets('an import is reported by sheet line, and names its hazard', (
    tester,
  ) async {
    final import = _ImportCallable();
    var syncs = 0;

    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      import: import,
      onChanged: () => syncs++,
    );
    await _choose(tester, 'bulk-catalog-task-import');
    await _paste(tester, _sheet);
    await _tap(tester, 'bulk-catalog-preview');

    expect(import.payloads.single['mode'], 'preview');
    expect(
      _text(tester, 'bulk-catalog-summary'),
      'Nothing has been written. 2 would be created and 0 cannot be.',
    );
    // Line 2 and line 3 of the pasted text, header included, because that is
    // what the person's own editor shows.
    expect(
      _text(tester, 'bulk-catalog-row-detail-2'),
      allOf(startsWith('Line 2 •'), contains('opens holding 12')),
    );
    expect(
      _text(tester, 'bulk-catalog-row-detail-3'),
      contains('opens holding 0'),
    );
    // Finding 5's first half: the sheet said `Bakery`, the server answers with
    // the `cat-bakery` it wrote, and the preview names what was typed.
    expect(
      _text(tester, 'bulk-catalog-row-detail-2'),
      contains('filed under Bakery'),
    );
    expect(_documentIdsOnScreen(tester), isEmpty);

    await _tap(tester, 'bulk-catalog-commit');
    // The one hazard this app cannot prevent, stated where a person can see it.
    expect(
      find.textContaining('Running this sheet again creates these products'),
      findsOne,
    );
    expect(find.textContaining('recorded in the stock ledger'), findsOne);
    await _tap(tester, 'bulk-catalog-confirm');

    expect(import.payloads, hasLength(2));
    expect(import.payloads.last['mode'], 'commit');
    expect(import.payloads.last['requestId'], import.payloads.first['requestId']);
    expect(syncs, 1);
    expect(
      _text(tester, 'bulk-catalog-committed'),
      contains('would create these products again'),
    );
  });

  testWidgets('rows this client refuses are reported and never sent', (
    tester,
  ) async {
    final import = _ImportCallable();

    await _pump(tester, _controller(), _Reader.seeded(), import: import);
    await _choose(tester, 'bulk-catalog-task-import');
    await _paste(
      tester,
      'name,sku,price,category\n'
      'Mandazi,M-1,20,Bakery\n'
      ',S-1,25,Bakery\n'
      'Priced,P-1,19.999,Bakery\n',
    );
    await _tap(tester, 'bulk-catalog-preview');

    // One row reaches the server; the other two are named at once, in the report
    // beside it, rather than found one round trip at a time.
    expect((import.payloads.single['rows']! as List), hasLength(1));
    expect(
      _text(tester, 'bulk-catalog-summary'),
      'Nothing has been written. 1 would be created and 2 cannot be.',
    );
    expect(
      _text(tester, 'bulk-catalog-row-detail-3'),
      contains('product name must not be blank'),
    );
    expect(
      _text(tester, 'bulk-catalog-row-detail-4'),
      contains('at most two decimal places'),
    );
  });

  testWidgets('a header this import cannot read refuses the sheet', (
    tester,
  ) async {
    final import = _ImportCallable();

    await _pump(tester, _controller(), _Reader.seeded(), import: import);
    await _choose(tester, 'bulk-catalog-task-import');
    await _paste(
      tester,
      'name,sku,price,category,supplier\nMandazi,M-1,20,Bakery,Acme',
    );
    await _tap(tester, 'bulk-catalog-preview');

    expect(import.payloads, isEmpty);
    expect(
      snackNotice(tester).message,
      startsWith('"supplier" is not a column this import reads'),
    );
  });

  testWidgets('a commit whose answer cannot be trusted is an unknown outcome', (
    tester,
  ) async {
    final batch = _BatchCallable(corruptAt: 1);

    await _pump(tester, _controller(), _Reader.seeded(), batch: batch);
    await _select(tester, 'pd-001');
    await _choose(tester, 'bulk-catalog-category-cat-drinks');
    await _tap(tester, 'bulk-catalog-preview');
    await _tap(tester, 'bulk-catalog-commit');
    await _tap(tester, 'bulk-catalog-confirm');

    // The request was sent, so the page may have been written. It is reported as
    // unknown rather than as a failure, and re-previewing is the way out.
    expect(batch.payloads, hasLength(2));
    expect(
      _callout(tester, 'bulk-catalog-report-failure'),
      allOf(contains('may or may not have been written'), contains('Nothing was written.')),
    );
    // A stopped chain is the one `problem` on this route. Every other notice
    // here is `info`, so the status is carrying the difference rather than the
    // paragraph having to.
    expect(_status(tester, 'bulk-catalog-report-failure'), AppStatus.problem);
  });

  testWidgets('both explanations fold, and the words survive the fold', (
    tester,
  ) async {
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      batch: _BatchCallable(),
      import: _ImportCallable(),
    );

    // Closed means gone from the tree rather than clipped to nothing, so a
    // screen reader does not read out prose nobody can see.
    expect(find.byKey(const ValueKey('bulk-catalog-scope')), findsNothing);
    await _open(tester, 'bulk-catalog-scope-disclosure');
    expect(
      _text(tester, 'bulk-catalog-scope'),
      startsWith('Nothing here happens until it has been shown to you first.'),
    );

    await _choose(tester, 'bulk-catalog-task-import');
    expect(find.byKey(const ValueKey('bulk-catalog-sheet-help')), findsNothing);
    await _open(tester, 'bulk-catalog-sheet-help-disclosure');
    expect(
      _text(tester, 'bulk-catalog-sheet-help'),
      allOf(
        contains('header line included'),
        contains('The header must name name, sku, and price.'),
        contains('An opening quantity is recorded as an opening balance'),
      ),
    );
  });

  testWidgets('every explanation on this route fits its one line on a phone', (
    tester,
  ) async {
    // A character count and not a render measurement, deliberately: `flutter
    // test` has no Material fonts, so an intrinsic-width read here reports a
    // fallback font's advance widths. The budget was measured in the harness,
    // where the fonts are real. Both of this route's summaries are asserted,
    // and the import one only exists once the task is switched.
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      batch: _BatchCallable(),
      import: _ImportCallable(),
      width: 411,
    );

    expect(_summaries(tester), hasLength(1));
    await _choose(tester, 'bulk-catalog-task-import');
    expect(_summaries(tester), hasLength(2));
    for (final summary in _summaries(tester)) {
      expect(
        summary.length,
        lessThanOrEqualTo(Disclosure.summaryCharacterBudget),
        reason: summary,
      );
    }
  });

  testWidgets('a report states each row\'s outcome as a status, not a word', (
    tester,
  ) async {
    final import = _ImportCallable();

    await _pump(tester, _controller(), _Reader.seeded(), import: import);
    await _choose(tester, 'bulk-catalog-task-import');
    await _paste(
      tester,
      'name,sku,price,category\n'
      'Mandazi,M-1,20,Bakery\n'
      ',S-1,25,Bakery\n',
    );
    await _tap(tester, 'bulk-catalog-preview');

    // A report genuinely mixes its outcomes, which is what makes a badge here
    // signal rather than the every-row badge the record rules rule out.
    expect(_rowStatus(tester, 2), AppStatus.attention);
    expect(_rowStatus(tester, 3), AppStatus.problem);
    // §8 rule 2, step 11: a preview writes nothing, so the word is conditional
    // wherever the outcome is. `Refused` is not conditional - the server will
    // not write that row in either mode.
    expect(_rowLabel(tester, 2), 'Would be created');
    expect(_rowLabel(tester, 3), 'Refused');
    expect(_text(tester, 'bulk-catalog-row-subject-3'), isNotEmpty);
  });

  testWidgets('a previewed row is awaiting and a committed one is confirmed', (
    tester,
  ) async {
    // The one mapping on this route that reads the report's mode. A green
    // "confirmed" badge over a report whose own first sentence is "Nothing has
    // been written" would state the opposite of the line above it.
    final batch = _BatchCallable(unchangedAt: 1);

    await _pump(tester, _controller(), _Reader.seeded(), batch: batch);
    await _select(tester, 'pd-001');
    await _select(tester, 'pd-002');
    await _choose(tester, 'bulk-catalog-category-cat-drinks');
    await _tap(tester, 'bulk-catalog-preview');

    expect(_rowStatus(tester, 1), AppStatus.attention);
    // A row that already holds the value is not in play in either mode, so it
    // is `neutral` before and after the commit.
    expect(_rowStatus(tester, 2), AppStatus.neutral);
    expect(_rowLabel(tester, 2), 'Unchanged');
    // The word reads the mode on exactly the outcomes the container does.
    expect(_rowLabel(tester, 1), 'Would be corrected');

    await _tap(tester, 'bulk-catalog-commit');
    await _tap(tester, 'bulk-catalog-confirm');

    expect(_rowStatus(tester, 1), AppStatus.ok);
    expect(_rowStatus(tester, 2), AppStatus.neutral);
    // A row was only ever going to be corrected until the commit landed.
    expect(_rowLabel(tester, 1), 'Corrected');
    expect(_rowLabel(tester, 2), 'Unchanged');
  });

  testWidgets('a summary agrees with its own counts when they are one', (
    tester,
  ) async {
    // The commonest shape this screen draws, and the one it read worst: a
    // person correcting a single mistyped price is the reason the route exists,
    // and the sentence said "1 were corrected, 1 already hold this value".
    final batch = _BatchCallable(unchangedAt: 1);

    await _pump(tester, _controller(), _Reader.seeded(), batch: batch);
    await _select(tester, 'pd-001');
    await _select(tester, 'pd-002');
    await _choose(tester, 'bulk-catalog-category-cat-drinks');
    await _tap(tester, 'bulk-catalog-preview');
    await _tap(tester, 'bulk-catalog-commit');
    await _tap(tester, 'bulk-catalog-confirm');

    expect(
      _text(tester, 'bulk-catalog-summary'),
      '1 was corrected, 1 already holds this value, and 0 cannot be.',
    );
  });
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  UpdateProductsCallable? batch,
  ImportProductsCallable? import,
  VoidCallback? onChanged,
  int pageSize = 20,
  double width = 1400,
}) async {
  tester.view.physicalSize = Size(width, 8000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantBulkCatalogPanel(
            reader: reader,
            batchCallable: batch,
            importCallable: import,
            onChanged: onChanged,
            pageSize: pageSize,
            requestIdFactory: _requestIds(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

TenantCatalogRequestIdFactory _requestIds() {
  var next = 0;
  return () => 'catalog-${++next}';
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, String productId) =>
    _tap(tester, 'bulk-catalog-select-$productId');

Future<void> _choose(WidgetTester tester, String key) => _tap(tester, key);

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  await tester.pumpAndSettle();
}

Future<void> _paste(WidgetTester tester, String sheet) =>
    _enter(tester, 'bulk-catalog-sheet', sheet);

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

/// One [Callout]'s message, read off the component rather than off a `Text`.
String _callout(WidgetTester tester, String key) =>
    tester.widget<Callout>(find.byKey(ValueKey(key))).message;

/// One [Callout]'s status.
AppStatus _status(WidgetTester tester, String key) =>
    tester.widget<Callout>(find.byKey(ValueKey(key))).status;

/// One report row's badge.
StatusBadge _badge(WidgetTester tester, int position) =>
    tester.widget<StatusBadge>(
      find.byKey(ValueKey('bulk-catalog-row-status-$position')),
    );

AppStatus _rowStatus(WidgetTester tester, int position) =>
    _badge(tester, position).status;

String _rowLabel(WidgetTester tester, int position) =>
    _badge(tester, position).label;

/// Every [Disclosure] summary currently on the route.
List<String> _summaries(WidgetTester tester) => tester
    .widgetList<Disclosure>(find.byType(Disclosure))
    .map((disclosure) => disclosure.summary)
    .toList();

/// Opens one [Disclosure] by its own key and settles the spring behind it.
Future<void> _open(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Every rendered string carrying the shape of a category document ID, over the
/// whole tree rather than over one slot. `cat-` is the seeded shape and `ct_` is
/// what `buildCategoryIntent` derives; neither is a word.
Iterable<String> _documentIdsOnScreen(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data)
    .nonNulls
    .where(RegExp(r'cat-|ct_').hasMatch);

String _label(WidgetTester tester, String key) => tester
    .widget<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
    .data!;

bool _enabled(WidgetTester tester, String key) => pressable(tester, key);

TenantSessionController _controller({TenantRole role = TenantRole.owner}) =>
    TenantSessionController()..open(
      uid: 'owner-a',
      membership: TenantMembership(
        tenantId: 'tenant-a',
        tenantName: 'Chilltent',
        tenantSlug: 'chilltent',
        role: role,
        membershipStatus: MembershipStatus.active,
        tenantStatus: TenantStatus.active,
        isOwner: role == TenantRole.owner,
        mirrorVersion: 1,
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 1),
        serverCanAccess: true,
        canonicalTenantExists: true,
        canonicalMembershipExists: true,
      ),
    );

final class _Reader implements TenantDataReader {
  _Reader(this._collections);

  /// One product filed under a category document nothing can read, beside one
  /// filed under a category this page holds.
  factory _Reader.strandedCategory() =>
      _Reader(<String, Map<String, Map<String, Object?>>>{
        _categoriesPath: <String, Map<String, Object?>>{
          'cat-bakery': <String, Object?>{'name': 'Bakery'},
          'cat-drinks': <String, Object?>{'name': 'Drinks'},
        },
        _productsPath: <String, Map<String, Object?>>{
          'pd-001': <String, Object?>{
            'name': 'Product 1',
            'SKU': '6161100001',
            'price': 65,
            'cost': 40,
            'quantity': 1,
            'categoryId': 'cat-not-cached',
          },
        },
      });

  factory _Reader.seeded({int productCount = 2}) =>
      _Reader(<String, Map<String, Map<String, Object?>>>{
        _categoriesPath: <String, Map<String, Object?>>{
          'cat-bakery': <String, Object?>{'name': 'Bakery'},
          'cat-drinks': <String, Object?>{'name': 'Drinks'},
        },
        _productsPath: <String, Map<String, Object?>>{
          for (var index = 1; index <= productCount; index++)
            // Padded so the ascending document-ID order a page answers in is
            // also the numeric order the report's positions are asserted in.
            'pd-${index.toString().padLeft(3, '0')}': <String, Object?>{
              'name': 'Product $index',
              'SKU': '616110000$index',
              'price': 65,
              'cost': 40,
              'quantity': index,
              'categoryId': 'cat-bakery',
            },
        },
      });

  final Map<String, Map<String, Map<String, Object?>>> _collections;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    final documents = _collections[query.collectionPath];
    if (documents == null) return const <TenantQueryDocumentSnapshot>[];
    final ids = documents.keys.toList()..sort();
    final cursor = query.startAfterDocumentId;
    return <TenantQueryDocumentSnapshot>[
      for (final id in ids)
        if (cursor == null || id.compareTo(cursor) > 0)
          TenantQueryDocumentSnapshot(
            path: '${query.collectionPath}/$id',
            data: documents[id]!,
          ),
    ].take(query.limit).toList();
  }
}

/// Answers `updateProducts` the way the server does: every row corrected to the
/// value the request named, so the strict decoder has something to reconcile.
final class _BatchCallable implements UpdateProductsCallable {
  _BatchCallable({this.failAt, this.corruptAt, this.error, this.unchangedAt});

  /// Which call (zero-based) throws [error] instead of answering.
  final int? failAt;

  /// Which call answers something the decoder must refuse.
  final int? corruptAt;

  /// Which row (zero-based within a page) comes back `unchanged` rather than
  /// corrected, which the server answers whenever a product already holds the
  /// value the request names. Nothing else in this file produces one, and it is
  /// the outcome §2.1 has to draw as "not in play".
  final int? unchangedAt;

  final Object? error;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final attempt = payloads.length;
    payloads.add(payload);
    if (attempt == failAt) throw error!;
    final mode = payload['mode']! as String;
    final rows = (payload['rows']! as List).cast<Map<String, Object?>>();
    if (attempt == corruptAt) {
      return <String, Object?>{
        'batchId': 'pb_x',
        'tenantId': payload['tenantId'],
        'mode': mode,
        'rowCount': rows.length,
        'updatedCount': rows.length,
        'unchangedCount': 0,
        'failedCount': 0,
        // Rows the request never named.
        'rows': const <Object?>[],
      };
    }
    final unchanged = unchangedAt != null && unchangedAt! < rows.length ? 1 : 0;
    return <String, Object?>{
      'batchId': 'pb_x',
      'tenantId': payload['tenantId'],
      'mode': mode,
      'rowCount': rows.length,
      'updatedCount': rows.length - unchanged,
      'unchangedCount': unchanged,
      'failedCount': 0,
      'rows': <Object?>[
        for (var index = 0; index < rows.length; index++)
          _corrected(rows[index], index, mode),
      ],
    };
  }

  Map<String, Object?> _corrected(
    Map<String, Object?> row,
    int index,
    String mode,
  ) {
    final field = row.keys.firstWhere((key) => key != 'productId');
    final value = row[field];
    final priced = field == 'price' ? value! as num : 65.0;
    final num? costed = field == 'cost' ? value as num? : 40.0;
    final untouched = index == unchangedAt;
    return <String, Object?>{
      'index': index,
      'productId': row['productId'],
      'status': untouched ? 'unchanged' : 'updated',
      'changedFields': untouched ? const <String>[] : <String>[field],
      'updateId': mode == 'commit' && !untouched ? 'pu_$index' : null,
      'code': null,
      'message': null,
      'product': <String, Object?>{
        'name': 'Product ${row['productId']}',
        'sku': 'sku-${row['productId']}',
        'price': priced.toDouble(),
        'priceMinor': (priced * 100).round(),
        'cost': costed?.toDouble(),
        'costMinor': costed == null ? null : (costed * 100).round(),
        'categoryId': field == 'categoryId' ? value : 'cat-bakery',
      },
    };
  }
}

/// Answers `importProducts` the way the server does, resolving every category
/// name to `cat-bakery`.
final class _ImportCallable implements ImportProductsCallable {
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(payload);
    final mode = payload['mode']! as String;
    final rows = (payload['rows']! as List).cast<Map<String, Object?>>();
    return <String, Object?>{
      'importId': 'im_x',
      'tenantId': payload['tenantId'],
      'mode': mode,
      'rowCount': rows.length,
      'createdCount': rows.length,
      'failedCount': 0,
      'rows': <Object?>[
        for (var index = 0; index < rows.length; index++)
          _created(rows[index], index, mode),
      ],
    };
  }

  Map<String, Object?> _created(
    Map<String, Object?> row,
    int index,
    String mode,
  ) {
    final price = row['price']! as num;
    final cost = row['cost'] as num?;
    final quantity = (row['quantity'] as int?) ?? 0;
    return <String, Object?>{
      'index': index,
      'status': 'created',
      'productId': mode == 'commit' ? 'pd_created$index' : null,
      'adjustmentId': mode == 'commit' && quantity > 0
          ? 'sa_created$index'
          : null,
      'code': null,
      'message': null,
      'product': <String, Object?>{
        'name': row['name'],
        'sku': row['sku'],
        'price': price.toDouble(),
        'priceMinor': (price * 100).round(),
        'cost': cost?.toDouble(),
        'costMinor': cost == null ? null : (cost * 100).round(),
        'quantity': quantity,
        'categoryId': row['categoryId'] ?? 'cat-bakery',
      },
    };
  }
}
