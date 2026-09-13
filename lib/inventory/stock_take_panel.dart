/// Counting the shelf, one product at a time.
///
/// **Nothing on this screen says what the books hold, and that is the feature.**
/// A blind count is the only kind worth taking: showing somebody the expected
/// figure tells them exactly what to write, which is precisely what a count of a
/// shop where things go missing needs to not do. The device *has* the figure -
/// it is in the catalog cache this screen reads its list from - and records it
/// silently as `seenQuantity` so the gap between counting and submitting stays
/// legible to whoever reviews it. It never renders it.
///
/// **The list comes from the offline catalog, not from Firestore.** That is the
/// same snapshot the till prices sales against: it works in a stock room with no
/// signal, it needs no paging, and it already leaves out retired products. A
/// count is taken where the stock is, and the stock is not near the router.
///
/// **Every keystroke is durable.** A stock take is an hour of somebody's
/// attention, so each number goes into the encrypted local draft as it is typed,
/// and the app being killed mid-aisle costs nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../checkout/checkout_catalog_cache.dart';
import '../checkout/checkout_draft.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'stock_take.dart';
import 'stock_take_draft_store.dart';

/// The route a person counts from.
final class TenantStockTakeScreen extends StatelessWidget {
  const TenantStockTakeScreen({
    super.key,
    required this.catalog,
    required this.drafts,
    required this.writer,
    this.obligations,
    this.scope = const TenantStockTakeEverything(),
    this.onSubmitted,
    this.requestIdFactory,
    this.businessDate,
  });

  final CheckoutCatalogSource catalog;
  final TenantStockTakeDraftSource drafts;
  final TenantStockTakeWriter writer;

  /// Told when a count is handed in, so the register stops asking for it.
  ///
  /// Optional, because counting from the menu on a day nobody was asked to
  /// count is a perfectly ordinary thing to do.
  final TenantStockTakeObligationSource? obligations;
  final TenantStockTakeScope scope;
  final VoidCallback? onSubmitted;
  final String Function()? requestIdFactory;
  final String Function()? businessDate;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Stock count',
    subtitle: 'Write down what is on the shelf.',
    contentWidth: AppContentWidth.records,
    body: TenantStockTakePanel(
      catalog: catalog,
      drafts: drafts,
      writer: writer,
      obligations: obligations,
      scope: scope,
      onSubmitted: onSubmitted,
      requestIdFactory: requestIdFactory,
      businessDate: businessDate,
    ),
  );
}

final class TenantStockTakePanel extends StatefulWidget {
  const TenantStockTakePanel({
    super.key,
    required this.catalog,
    required this.drafts,
    required this.writer,
    this.obligations,
    this.scope = const TenantStockTakeEverything(),
    this.onSubmitted,
    this.requestIdFactory,
    this.businessDate,
  });

  final CheckoutCatalogSource catalog;
  final TenantStockTakeDraftSource drafts;
  final TenantStockTakeWriter writer;

  /// Told when a count is handed in, so the register stops asking for it.
  ///
  /// Optional, because counting from the menu on a day nobody was asked to
  /// count is a perfectly ordinary thing to do.
  final TenantStockTakeObligationSource? obligations;
  final TenantStockTakeScope scope;
  final VoidCallback? onSubmitted;
  final String Function()? requestIdFactory;
  final String Function()? businessDate;

  @override
  State<TenantStockTakePanel> createState() => _TenantStockTakePanelState();
}

class _TenantStockTakePanelState extends State<TenantStockTakePanel> {
  TenantStockTakeDraft? _draft;
  final Map<String, TextEditingController> _fields =
      <String, TextEditingController>{};

  /// The product whose field is currently wrong, and why. One at a time,
  /// because a person types into one field at a time.
  String? _invalidProductId;
  bool _submitting = false;

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _businessDate =>
      widget.businessDate?.call() ??
      checkoutBusinessDate(DateTime.now().toUtc());

  @override
  Widget build(BuildContext context) => TenantRouteGuard<CheckoutCatalogSnapshot?>(
    // Every active member, which is the point: counting is the one inventory
    // act a cashier performs, and it moves no stock.
    allowedRoles: TenantStockTakeGateway.allowedRoles,
    load: (session) =>
        widget.catalog.read(uid: session.uid, tenantId: session.tenantId),
    denied: const ErrorState(
      status: AppStatus.problem,
      badgeLabel: 'Not allowed',
      statement: 'You are not signed in to a business that can be counted.',
    ),
    builder: (context, session, snapshot) =>
        _build(context, session, snapshot),
  );

  Widget _build(
    BuildContext context,
    TenantSession session,
    CheckoutCatalogSnapshot? snapshot,
  ) {
    final tokens = AppTokens.componentOf(context);
    if (snapshot == null) {
      // The till has never synced on this device, so there is nothing to count
      // against. Saying so is more use than an empty list.
      return const EmptyState(
        key: ValueKey('stock-take-no-catalog'),
        title: 'No catalog on this device yet',
        hint:
            'Open the register once while you have a connection. The product '
            'list is saved here and the count then works with no signal.',
      );
    }

    final products = _inScope(snapshot);
    if (products.isEmpty) {
      return const EmptyState(
        key: ValueKey('stock-take-empty'),
        title: 'Nothing to count',
        hint: 'There are no products here to count.',
      );
    }

    final draft = _draft ??= _resume(session, products.length);

    return ListView(
      padding: EdgeInsets.all(tokens.spacing.s16),
      children: <Widget>[
        _progress(draft, products.length),
        SizedBox(height: tokens.spacing.s16),
        for (final product in products) ...<Widget>[
          _line(product, draft, session),
          SizedBox(height: tokens.spacing.s12),
        ],
        SizedBox(height: tokens.spacing.s8),
        AppButton(
          key: const ValueKey('stock-take-submit'),
          label: 'Hand in this count',
          tier: AppButtonTier.primary,
          loading: _submitting,
          onPressed: draft.isEmpty || _submitting
              ? null
              : () => _submit(session, products.length),
        ),
      ],
    );
  }

  /// The products this count covers, in the order they are counted.
  ///
  /// Ordered by name rather than by ID, because the person holding the phone is
  /// walking a shelf and reading labels.
  List<TenantProduct> _inScope(CheckoutCatalogSnapshot snapshot) {
    final scope = widget.scope;
    final products = <TenantProduct>[
      for (final product in snapshot.products)
        if (scope is! TenantStockTakeCategory ||
            product.categoryId == scope.categoryId)
          product,
    ]..sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
    return products;
  }

  TenantStockTakeDraft _resume(TenantSession session, int productsInScope) {
    final existing = widget.drafts.draftFor(
      uid: session.uid,
      tenantId: session.tenantId,
    );
    // **A count resumes rather than restarts**, but only within the day and the
    // scope it was taken for. Yesterday's half-finished count is not part of
    // today's, and one category's is not another's.
    if (existing != null &&
        existing.businessDate == _businessDate &&
        existing.scope == widget.scope) {
      for (final entry in existing.counts.entries) {
        _fields[entry.key] = TextEditingController(
          text: '${entry.value.counted}',
        );
      }
      return existing;
    }
    final requestId =
        widget.requestIdFactory?.call() ?? secureTenantStockTakeRequestId();
    return TenantStockTakeDraft(
      takeId: tenantStockTakeId(
        tenantId: session.tenantId,
        counterUid: session.uid,
        requestId: requestId,
        businessDate: _businessDate,
      ),
      tenantId: session.tenantId,
      businessDate: _businessDate,
      scope: widget.scope,
      productsInScope: productsInScope,
      startedAt: DateTime.now().toUtc(),
      counts: const <String, TenantStockTakeCount>{},
    );
  }

  Widget _progress(TenantStockTakeDraft draft, int total) {
    final remaining = total - draft.countedLineCount;
    return Callout(
      key: const ValueKey('stock-take-progress'),
      status: remaining == 0 ? AppStatus.ok : AppStatus.info,
      title: '${draft.countedLineCount} of $total counted',
      message: remaining == 0
          ? 'Every product here has a number against it. Hand the count in when '
                'you are ready.'
          : 'Leave a box empty for anything you did not get to. An empty box '
                'and a zero are not the same thing: zero means you looked and '
                'the shelf was bare.',
    );
  }

  Widget _line(
    TenantProduct product,
    TenantStockTakeDraft draft,
    TenantSession session,
  ) {
    final controller = _fields.putIfAbsent(
      product.id,
      TextEditingController.new,
    );
    return AppTextField(
      key: ValueKey('stock-take-line-${product.id}'),
      label: product.name,
      helper: product.sku,
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(signed: false),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
      error: _invalidProductId == product.id
          ? 'Write a whole number of units, or leave it empty.'
          : null,
      onChanged: (raw) => _record(session, product, raw),
    );
  }

  Future<void> _record(
    TenantSession session,
    TenantProduct product,
    String raw,
  ) async {
    final draft = _draft;
    if (draft == null) return;
    final int? counted;
    try {
      counted = tenantStockTakeCountOf(raw);
    } on TenantStockTakeException {
      setState(() => _invalidProductId = product.id);
      return;
    }
    final next = counted == null
        // An emptied box takes the line out entirely. Storing zero here would
        // turn "I did not get to it" into "the shelf was bare".
        ? draft.withoutCount(product.id)
        : draft.withCount(
            product.id,
            TenantStockTakeCount(
              counted: counted,
              // **Read, never rendered.** The figure this device holds, kept so
              // the window between counting and submitting can be read later by
              // somebody entitled to see both.
              seenQuantity: product.quantity,
              countedAt: DateTime.now().toUtc(),
            ),
          );
    setState(() {
      _draft = next;
      if (_invalidProductId == product.id) _invalidProductId = null;
    });
    await widget.drafts.save(uid: session.uid, draft: next);
  }

  Future<void> _submit(TenantSession session, int productsInScope) async {
    final draft = _draft;
    if (draft == null || draft.isEmpty || _submitting) return;
    final skipped = productsInScope - draft.countedLineCount;
    final confirmed = await _confirm(draft, skipped);
    if (!confirmed || !mounted) return;

    setState(() => _submitting = true);
    try {
      // **Every page is queued before this returns**, so handing in a count
      // needs no connection and nothing is half-sent: the pages are durable
      // together, and the worker carries them in order because they share the
      // take's path.
      for (final page in TenantStockTakeGateway(session).pagesFor(draft)) {
        await widget.writer.submitPage(page);
      }
      await widget.drafts.clear(uid: session.uid, tenantId: session.tenantId);
      // **The obligation is discharged here, not when the pages drain.** A
      // cashier held out of the till until a manager approves - or until the
      // signal comes back - is a shop that cannot trade, and the count is
      // already as durable as anything else on this device.
      await widget.obligations?.markSatisfied(
        uid: session.uid,
        tenantId: session.tenantId,
        businessDate: draft.businessDate,
        scopeKey: draft.scope.scopeKey,
      );
      if (!mounted) return;
      setState(() {
        _draft = null;
        for (final controller in _fields.values) {
          controller.clear();
        }
      });
      widget.onSubmitted?.call();
      _report(
        AppNotice.confirmed(
          'Count handed in. ${draft.countedLineCount} '
          '${draft.countedLineCount == 1 ? 'product' : 'products'} recorded.',
        ),
      );
    } on TenantStockTakeException catch (error) {
      _report(AppNotice.refused(_failureMessage(error.failure)));
    } catch (_) {
      // The pages that did reach the queue are still there, and re-handing in
      // sends them again harmlessly - the server keys each page by the take and
      // the page number.
      _report(
        const AppNotice.unknown(
          'This count has not been handed in. Your numbers are still saved '
          'here, so try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Says what is about to be handed in, and what is being left out.
  ///
  /// **The one figure worth stopping for is the skipped one.** A count handed in
  /// with half the shelf blank is not wrong - a person may only have been asked
  /// for one aisle - but it is worth being sure about, because nothing on the
  /// other side can tell the difference between "not counted" and "not counted
  /// yet".
  Future<bool> _confirm(TenantStockTakeDraft draft, int skipped) =>
      showConfirmDialog(
        context,
        title: 'Hand in this count?',
        consequence: skipped <= 0
            ? 'All ${draft.countedLineCount} products here have a number '
                  'against them.'
            : 'You have counted ${draft.countedLineCount} and left $skipped '
                  'without a number.',
        // §8 rule 6, and the sentence that matters most on this screen: an
        // empty box is not a claim about the shelf.
        stillTrue:
            'Anything left empty is recorded as not counted, not as none on '
            'the shelf. Nothing moves until somebody reviews this.',
        confirmLabel: 'Hand it in',
        cancelLabel: 'Keep counting',
        // Handing in a count destroys nothing and moves no stock.
        tier: AppButtonTier.primary,
        confirmKey: const ValueKey('stock-take-confirm'),
      );

  String _failureMessage(TenantStockTakeFailure failure) => switch (failure) {
    TenantStockTakeFailure.forbidden =>
      'You are not signed in to this business, so nothing was sent.',
    TenantStockTakeFailure.nothingCounted =>
      'Nothing has been counted yet, so there is nothing to hand in.',
    TenantStockTakeFailure.invalidCount =>
      'One of the numbers is not a whole count of units.',
    TenantStockTakeFailure.notRecorded ||
    TenantStockTakeFailure.draftUnreadable =>
      'This count could not be saved on this device, so nothing was sent.',
    TenantStockTakeFailure.invalidScope ||
    TenantStockTakeFailure.invalidPageSize =>
      'This count could not be prepared to send.',
  };

  void _report(AppNotice notice) => showAppSnackBar(context, notice);
}
