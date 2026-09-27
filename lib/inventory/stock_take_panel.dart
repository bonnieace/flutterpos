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
///
/// **Laid out for the shelf, on 2026-09-22.** One row per product, the name at
/// full weight with the box beside it, because the name is what a person reads
/// off the label and the number is the only thing they write. Each row says
/// where it stands - not counted yet, looked and found none, or the product's
/// SKU once it has a number - and *Hand in this count* is pinned at the foot
/// of the screen rather than at the end of a list that can run to hundreds of
/// products. Nothing here reads, writes or decides anything the screen did not
/// before: the draft, the refusals and the hand-in are unchanged.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/observability/app_telemetry.dart';
import 'package:flutter/services.dart';

import '../checkout/checkout_catalog_cache.dart';
import '../checkout/checkout_draft.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/measure.dart';
import '../ui/meter.dart';
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
    // `reading`: a row here is a name and a box, and at `records` width the
    // box drifts a monitor's width away from the name it belongs to.
    contentWidth: AppContentWidth.reading,
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
  Widget build(
    BuildContext context,
  ) => TenantRouteGuard<CheckoutCatalogSnapshot?>(
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
    builder: (context, session, snapshot) => _build(context, session, snapshot),
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
    final inset = AppScaffold.horizontalInset(tokens.spacing);
    final ring = tokens.colors.action.focusRing;
    final gutter = ring.width + ring.offset;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(inset),
            children: <Widget>[
              _progress(draft, products.length),
              // `space.16` under the summary and `space.12` between rows: the
              // summary is a different kind of thing from the rows under it,
              // and the rows are one list.
              for (final (index, product) in products.indexed) ...<Widget>[
                SizedBox(
                  height: index == 0 ? tokens.spacing.s16 : tokens.spacing.s12,
                ),
                _line(context, product, draft, session),
              ],
            ],
          ),
        ),
        // **Pinned, the way the catalog form pins its actions.** A count can
        // run to hundreds of products, and a hand-in at the end of that list
        // is a button nobody can find without scrolling past every one of them.
        //
        // **No rule above it**, which is the design's: the bar is the page's
        // own colour, so the list runs under it and stops there.
        ColoredBox(
          color: tokens.colors.surface.base,
          // The button's focus-ring gutter is given back out of the side inset,
          // so its edges stand on the same line as the cards above it; below
          // it, `space.20` and the gutter put it 24 off the bottom edge.
          child: SafeArea(
            top: false,
            minimum: EdgeInsets.fromLTRB(
              inset - gutter,
              tokens.spacing.s12,
              inset - gutter,
              tokens.spacing.s20,
            ),
            child: AppButton(
              key: const ValueKey('stock-take-submit'),
              label: 'Hand in this count',
              tier: AppButtonTier.primary,
              expand: true,
              loading: _submitting,
              onPressed: draft.isEmpty || _submitting
                  ? null
                  : () => _submit(session, products.length),
            ),
          ),
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
    final products =
        <TenantProduct>[
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
    final counted = draft.countedLineCount;
    final remaining = total - counted;
    return _CountProgress(
      key: const ValueKey('stock-take-progress'),
      counted: counted,
      total: total,
      message: remaining == 0
          ? 'Every product here has a number against it. Hand the count in when '
                'you are ready.'
          : 'Enter 0 if no stock exists.',
    );
  }

  Widget _line(
    BuildContext context,
    TenantProduct product,
    TenantStockTakeDraft draft,
    TenantSession session,
  ) {
    final controller = _fields.putIfAbsent(
      product.id,
      TextEditingController.new,
    );
    final invalid = _invalidProductId == product.id;
    return _CountLine(
      product: product,
      counted: invalid ? null : draft.counts[product.id]?.counted,
      invalid: invalid,
      // Read on every keystroke, since every keystroke rebuilds: `_record`
      // sets state whether the number was taken or refused.
      boxWidth: _CountLine.boxWidthOf(
        AppTokens.componentOf(context),
        controller.text,
        textScaler: MediaQuery.textScalerOf(context),
      ),
      field: AppTextField(
        key: ValueKey('stock-take-line-${product.id}'),
        label: product.name,
        // The product's name is printed beside the box at full weight, so the
        // well carries no caption of its own - see `AppTextField.dense`.
        dense: true,
        figure: true,
        placeholder: _CountLine.emptyMark,
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(signed: false),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        error: invalid ? _CountLine.invalidMessage : null,
        // The row prints the sentence across its whole width; the well keeps
        // the outline and the announcement.
        showsErrorText: false,
        onChanged: (raw) => _record(session, product, raw),
      ),
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
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'inventory.stock_take',
      screen: 'stock_count',
      context: {
        'user_id': session.uid,
        'tenant_id': session.tenantId,
        'counted_rows': draft.countedLineCount,
        'products_in_scope': productsInScope,
      },
    );
    final skipped = productsInScope - draft.countedLineCount;
    final confirmed = await _confirm(draft, skipped);
    if (!confirmed || !mounted) {
      telemetry.recordStep(operation, 'cancelled');
      return;
    }
    telemetry.recordStep(operation, 'confirmed');

    setState(() => _submitting = true);
    try {
      // **Every page is queued before this returns**, so handing in a count
      // needs no connection and nothing is half-sent: the pages are durable
      // together, and the worker carries them in order because they share the
      // take's path.
      await telemetry.trace(operation, 'save_count_pages', () async {
        for (final page in TenantStockTakeGateway(session).pagesFor(draft)) {
          await widget.writer.submitPage(page);
        }
      });
      await widget.drafts.clear(uid: session.uid, tenantId: session.tenantId);
      telemetry.recordStep(operation, 'saved_locally');
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
    } on TenantStockTakeException catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'inventory.stock_take_submit',
      );
      _report(AppNotice.refused(_failureMessage(error.failure)));
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'inventory.stock_take_submit',
      );
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

/// How far the count has got: *118 of 240 counted*, a meter, and what an empty
/// box means.
final class _CountProgress extends StatelessWidget {
  const _CountProgress({
    super.key,
    required this.counted,
    required this.total,
    required this.message,
  });

  final int counted;
  final int total;
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final remaining = total - counted;
    return AppCard(
      // **`space.12` over the heading and `space.16` under the note**, which
      // reads as one margin: the heading's own line carries seven pixels above
      // its capitals, and a caption's last line almost nothing below.
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.s16,
        tokens.spacing.s12,
        tokens.spacing.s16,
        tokens.spacing.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Expanded(
                child: Text(
                  '$counted of $total counted',
                  style: tokens.typography.titleMedium.copyWith(
                    color: colors.text.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: tokens.spacing.s12),
              Text(
                '$remaining left',
                key: const ValueKey('stock-take-remaining'),
                // `numeric.body`'s face at `body.lg`'s size, a step under the
                // heading it sits beside.
                style: tokens.typography.numericBody.copyWith(
                  fontSize: tokens.typography.bodyLarge.fontSize,
                  height: tokens.typography.bodyLarge.height,
                  color: colors.text.tertiary,
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.s12),
          // `ok` all the way: a count half done is not a fault, and the fill
          // is the counted share, which is the good part.
          AppMeter(
            filled: counted,
            of: total,
            status: AppStatus.ok,
            semanticLabel: '$counted of $total counted',
          ),
          SizedBox(height: tokens.spacing.s8),
          Text(
            message,
            style: tokens.typography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One product on the shelf: its name, where it stands, and the box.
///
/// **The line under the name is the row's standing, not a second label.**
/// Empty, it says *Not counted yet*; at zero it says the person looked and
/// found none, in a badge, because an empty box and a zero are the one
/// distinction this screen exists to keep; with a number, it goes back to the
/// SKU. None of these is the figure the books hold - that is never drawn.
final class _CountLine extends StatelessWidget {
  const _CountLine({
    required this.product,
    required this.counted,
    required this.invalid,
    required this.boxWidth,
    required this.field,
  });

  final TenantProduct product;

  /// What is recorded for this product, or null for an empty box.
  final int? counted;

  /// Whether the box holds something that is not a count.
  final bool invalid;

  /// See [boxWidthOf].
  final double boxWidth;
  final Widget field;

  /// What an empty box shows. A dash rather than a zero, which would be a count.
  static const String emptyMark = '\u2014';

  static const String invalidMessage =
      'Write a whole number of units, or leave it empty.';

  /// The box's width for [value]: 96 wide as the design draws it, and wider
  /// only when the figure needs the room.
  ///
  /// **It grows rather than scrolling.** 96 holds five figures, which is any
  /// count a shop shelf produces - but a million is the largest count the model
  /// accepts (`maximumStockTakeCount`), and a box that scrolled its own value
  /// would show `00001` for a typed `1000001`, a different number, on the one
  /// screen whose whole job is writing the right one. Measured rather than
  /// counted in digits, so a larger text size widens the box with the figures.
  /// One figure more than is typed, because the caret sits past the last one.
  ///
  /// Includes the field's focus-ring gutter, which is the width the box is
  /// given; its outline is the gutter narrower either side.
  static double boxWidthOf(
    AppTokens tokens,
    String value, {
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final ring = tokens.colors.action.focusRing;
    final gutter = ring.width + ring.offset;
    final figures = measureTextWidth(
      '0' * (value.length + 1),
      tokens.typography.numericCompact,
      textScaler: textScaler,
    );
    final well = math.max(
      tokens.spacing.s48 + tokens.spacing.s48,
      // `AppFieldWell.figure`'s inset, either side.
      figures + tokens.spacing.s8 * 2,
    );
    return well + gutter * 2;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final problem = colors.status.problem;
    final ring = colors.action.focusRing;
    final gutter = ring.width + ring.offset;
    final sku = product.sku;
    final Widget? standing = invalid
        ? (sku.isEmpty ? null : _sku(tokens, sku))
        : switch (counted) {
            null => Text(
              'Not counted yet',
              key: ValueKey('stock-take-not-counted-${product.id}'),
              style: tokens.typography.bodyMedium.copyWith(
                color: colors.text.tertiary,
              ),
            ),
            0 => StatusBadge(
              key: ValueKey('stock-take-none-there-${product.id}'),
              status: AppStatus.neutral,
              icon: Icons.visibility_outlined,
              label: 'You looked, none there',
            ),
            _ => sku.isEmpty ? null : _sku(tokens, sku),
          };

    // **`AppCard`'s surface, drawn here because its edge can turn.** A row
    // holding something that is not a count takes the problem edge, and
    // `AppCard` has no states of its own - see its note.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.raised,
        borderRadius: BorderRadius.circular(tokens.radius.md),
        border: Border.all(
          color: invalid ? problem.border : colors.surface.cardEdge,
        ),
      ),
      // **`space.8` over and under, `space.12` either side**, and the box's
      // own focus-ring gutter makes each 4 more: 12 from the edge to the box,
      // and the words inset by the same gutter so they stand 16 in, on the
      // line the progress card's words do.
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.s12,
          vertical: tokens.spacing.s8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(start: gutter),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          product.name,
                          style: tokens.typography.titleMedium.copyWith(
                            color: colors.text.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (standing != null) ...<Widget>[
                          SizedBox(height: tokens.spacing.s4),
                          standing,
                        ],
                      ],
                    ),
                  ),
                ),
                SizedBox(width: tokens.spacing.s12),
                SizedBox(width: boxWidth, child: field),
              ],
            ),
            if (invalid)
              Padding(
                // Under the box by its gutter and `space.4`, and clear of the
                // card's foot by the gutter the box would have had.
                padding: EdgeInsetsDirectional.fromSTEB(
                  gutter,
                  tokens.spacing.s4,
                  gutter,
                  gutter,
                ),
                child: Text(
                  invalidMessage,
                  key: ValueKey('stock-take-invalid-${product.id}'),
                  style: tokens.typography.caption.copyWith(color: problem.fg),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Widget _sku(AppTokens tokens, String sku) => Text(
    sku,
    style: tokens.typography.monoCaption.copyWith(
      color: tokens.colors.text.tertiary,
    ),
  );
}
