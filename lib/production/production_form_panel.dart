/// Recording what a batch made and what it cost to make.
///
/// **A route rather than a sheet**, for the reason receiving a delivery is one:
/// every figure here is typed, and in a sheet the keyboard covers the row being
/// typed into.
library;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/observability/app_telemetry.dart';

import '../checkout/checkout_draft.dart';
import '../inventory/catalog_management.dart';
import '../inventory/product_visual.dart';
import '../inventory/product_typeahead.dart';
import '../reporting/reporting_currency.dart';
import '../reports/analysis/report_prose.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'production_batch.dart';

/// Everything recording production needs from the composition root.
final class TenantProductionServices {
  const TenantProductionServices({
    required this.writer,
    this.productSearchReader,
  });

  final TenantProductionWriter writer;
  final TenantProductSearchReader? productSearchReader;
}

/// The words that open when *Keep these out of Expenses* is tapped.
///
/// Named so the screen and its test say the same sentence: it is the one thing
/// on this form that decides whether the business's profit is counted right.
const String productionExpensesWarning =
    'These costs become part of what each unit costs. If you also record them '
    'in Expenses they are counted twice, and your profit will look lower than '
    'it was.';

/// Pushes the production form, and answers with the notice to show once it
/// closes, or null when nothing was recorded.
Future<AppNotice?> openRecordProductionScreen(
  BuildContext context, {
  required TenantDataReader reader,
  required TenantProductionServices services,
}) {
  final controller = TenantSessionScope.of(context);
  return Navigator.of(context).push<AppNotice>(
    AppPageRoute<AppNotice>(
      builder: (routeContext) => TenantSessionScope(
        controller: controller,
        child: TenantRecordProductionScreen(
          reader: reader,
          services: services,
          onCompleted: (notice) => Navigator.of(routeContext).pop(notice),
        ),
      ),
    ),
  );
}

/// The production form, as a route.
final class TenantRecordProductionScreen extends StatefulWidget {
  const TenantRecordProductionScreen({
    super.key,
    required this.reader,
    required this.services,
    required this.onCompleted,
    this.requestIdFactory,
    this.clock,
  });

  final TenantDataReader reader;
  final TenantProductionServices services;
  final ValueChanged<AppNotice> onCompleted;
  final String Function()? requestIdFactory;

  /// What names the business day a batch number carries.
  final DateTime Function()? clock;

  @override
  State<TenantRecordProductionScreen> createState() =>
      _TenantRecordProductionScreenState();
}

final class _TenantRecordProductionScreenState
    extends State<TenantRecordProductionScreen> {
  // Method tear-offs rather than closures: two tear-offs of one method on one
  // object are equal, so the guard sees the same loader every build and reads
  // once.
  Future<TenantReportingCurrency> _load(TenantSession session) =>
      TenantReportingCurrency.read(session: session, reader: widget.reader);

  Future<TenantReportingCurrency> _loadCached(TenantSession session) =>
      TenantReportingCurrency.read(
        session: session,
        reader: widget.reader.cached ?? widget.reader,
      );

  @override
  Widget build(BuildContext context) =>
      TenantRouteGuard<TenantReportingCurrency>(
        allowedRoles: TenantProductionRepository.allowedRoles,
        load: _load,
        loadCached: widget.reader.cached == null ? null : _loadCached,
        loading: const _ProductionFormFrame(
          child: LoadingState(message: 'Opening the form'),
        ),
        failure: (context, error) => const _ProductionFormFrame(
          child: ErrorState(
            key: ValueKey('production-form-failure'),
            badgeLabel: 'Not read',
            statement: 'The form could not be opened.',
            stillTrue: 'Nothing has been recorded or changed.',
          ),
        ),
        builder: (context, session, currency) => _ProductionFormFrame(
          child: _ProductionForm(
            session: session,
            reader: widget.reader,
            services: widget.services,
            currency: currency,
            requestIdFactory: widget.requestIdFactory,
            clock: widget.clock ?? () => DateTime.now().toUtc(),
            onCompleted: widget.onCompleted,
          ),
        ),
      );
}

final class _ProductionFormFrame extends StatelessWidget {
  const _ProductionFormFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Record production',
    subtitle: 'What was made, and what it cost.',
    contentWidth: AppContentWidth.reading,
    body: child,
  );
}

/// One expense row, with the two fields it is typed into.
final class _RowState {
  _RowState({String description = '', String amount = '', this.carriedMinor})
    : description = TextEditingController(text: description),
      amount = TextEditingController(text: amount);

  final TextEditingController description;
  final TextEditingController amount;
  final Key key = UniqueKey();

  /// The last batch's amount for this row, which the row follows in
  /// proportion to how many are made. Null for a row added here, and once the
  /// amount is typed into: a typed figure is the person's, and stays as typed.
  int? carriedMinor;

  void dispose() {
    description.dispose();
    amount.dispose();
  }

  TenantProductionRowDraft get draft => TenantProductionRowDraft(
    description: description.text,
    amount: amount.text,
  );
}

final class _ProductionForm extends StatefulWidget {
  const _ProductionForm({
    required this.session,
    required this.reader,
    required this.services,
    required this.currency,
    required this.requestIdFactory,
    required this.clock,
    required this.onCompleted,
  });

  final TenantSession session;
  final TenantDataReader reader;
  final TenantProductionServices services;
  final TenantReportingCurrency currency;
  final String Function()? requestIdFactory;
  final DateTime Function() clock;
  final ValueChanged<AppNotice> onCompleted;

  @override
  State<_ProductionForm> createState() => _ProductionFormState();
}

final class _ProductionFormState extends State<_ProductionForm> {
  final TextEditingController _quantity = TextEditingController();
  final List<_RowState> _rows = <_RowState>[_RowState()];
  TenantProduct? _product;

  /// Whether the search is open again over a product already chosen, after
  /// *Edit*. The chosen product holds until another is picked or the search is
  /// typed into, so opening the search and backing out loses nothing.
  bool _choosingProduct = false;

  /// The batch the rows were started from, said so beside them.
  TenantProductionBatch? _startedFrom;
  bool _busy = false;
  String? _error;

  /// A change to any field, which also retires a refusal about the last
  /// attempt: left up, it went on naming a row that had since been corrected.
  void _edited() => setState(() => _error = null);

  /// How many were made, while it reads as a batch the form could send.
  int? get _made {
    final units = int.tryParse(_quantity.text.trim());
    return units == null || units < 1 || units > maximumProductionQuantity
        ? null
        : units;
  }

  /// A new quantity carries the rows still following the last batch with it.
  /// Each is worked out from the last batch's own figure, never from the one
  /// on screen, so typing 1 on the way to 120 loses nothing to rounding.
  void _quantityEdited() {
    final from = _startedFrom?.quantity;
    final to = _made;
    setState(() {
      _error = null;
      if (from == null || from < 1 || to == null) return;
      for (final row in _rows) {
        final carried = row.carriedMinor;
        if (carried == null) continue;
        row.amount.text = tenantCatalogMajorUnits(
          productionScaledAmountMinor(carried, from: from, to: to),
        );
      }
    });
  }

  void _amountEdited(_RowState row) {
    row.carriedMinor = null;
    _edited();
  }

  /// One request per batch, held until it is queued.
  String? _requestId;

  @override
  void dispose() {
    _quantity.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  TenantProductionRepository get _repository => TenantProductionRepository(
    session: widget.session,
    reader: widget.reader,
  );

  List<TenantProductionRowDraft> get _drafts => <TenantProductionRowDraft>[
    for (final row in _rows) row.draft,
  ];

  TenantProductionPreview? get _preview =>
      TenantProductionPreview.of(quantity: _quantity.text, rows: _drafts);

  bool get _canSubmit {
    final preview = _preview;
    return !_busy &&
        _product != null &&
        preview != null &&
        preview.unitCostMinor != null &&
        preview.unitCostMinor! >= 1;
  }

  String _money(int minor) => widget.currency.format(minor / 100);

  Future<void> _selectProduct(TenantProduct product) async {
    setState(() {
      _product = product;
      _choosingProduct = false;
      _startedFrom = null;
      _error = null;
    });
    TenantProductionBatch? last;
    try {
      last = await _repository.lastBatchOf(product.id);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'production.last_batch_read',
      );
      // A batch that cannot be looked up is simply not offered as a start.
      last = null;
    }
    if (!mounted || last == null || _product?.id != product.id) return;
    // **Only over rows nobody has typed into.** Starting from the last batch
    // saves a baker typing the same four rows every morning; overwriting rows
    // somebody already filled in would lose their work.
    if (_rows.any((row) => !row.draft.isBlank)) return;
    // **The whole batch, so the same batch again is one tap.** How many were
    // made comes too, unless a figure is already typed; the costs are then
    // carried to whichever quantity stands, and follow it from there.
    final from = last.quantity;
    if (from < 1) return;
    if (_quantity.text.trim().isEmpty) _quantity.text = '$from';
    final to = _made ?? from;
    setState(() {
      for (final row in _rows) {
        row.dispose();
      }
      _rows
        ..clear()
        ..addAll(<_RowState>[
          for (final expense in last!.expenses)
            _RowState(
              description: expense.description,
              amount: tenantCatalogMajorUnits(
                productionScaledAmountMinor(
                  expense.amountMinor,
                  from: from,
                  to: to,
                ),
              ),
              carriedMinor: expense.amountMinor,
            ),
        ]);
      if (_rows.isEmpty) _rows.add(_RowState());
      _startedFrom = last;
    });
  }

  void _addRow() => setState(() => _rows.add(_RowState()));

  void _removeRow(_RowState row) => setState(() {
    _rows.remove(row);
    row.dispose();
    if (_rows.isEmpty) _rows.add(_RowState());
  });

  String _refusal(TenantProductionException error) {
    final row = error.row;
    return switch (error.code) {
      'invalid_quantity' =>
        'Enter how many were made, as a whole number from 1 to '
            '$maximumProductionQuantity.',
      'invalid_description' =>
        'Cost $row needs a description - what the money was spent on.',
      'invalid_amount' =>
        'Cost $row must be an amount above zero with at most two decimal '
            'places.',
      'no_costs' =>
        'A batch needs at least one cost. A batch with no cost cannot be '
            'recorded.',
      'too_many_costs' =>
        'A batch can carry up to $maximumProductionExpenses costs. Combine some '
            'of them.',
      'cost_rounds_to_nothing' =>
        'The cost per unit rounds to nothing. Check the costs and how many '
            'were made.',
      'cost_too_large' => 'The cost per unit is larger than a sale can record.',
      'retired_product' => 'That product has been retired.',
      'production_forbidden' =>
        'Only an owner, administrator or manager may record production.',
      _ => 'This batch could not be recorded as entered.',
    };
  }

  Future<void> _submit() async {
    final product = _product;
    if (product == null) return;
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'production.complete',
      screen: 'production',
      context: {'product_id': product.id, 'product_name': product.name},
    );
    final TenantProductionIntent intent;
    try {
      intent = _repository.buildIntent(
        product: product,
        quantity: _quantity.text,
        rows: _drafts,
        requestId: _requestId ??=
            (widget.requestIdFactory ?? secureTenantProductionRequestId)(),
        businessDate: checkoutBusinessDate(widget.clock()),
      );
    } on TenantProductionException catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'production.validate',
      );
      setState(() => _error = _refusal(error));
      return;
    }
    telemetry.recordStep(
      operation,
      'validated',
      data: {
        'request_id': _requestId,
        'quantity': intent.quantity,
        'total_cost_minor': intent.totalCostMinor,
      },
    );
    setState(() => _error = null);
    final previous = intent.previousCostMinor;
    final costSentence = previous == null
        ? 'Its cost becomes ${_money(intent.unitCostMinor)} for every sale '
              'from now on.'
        : previous == intent.unitCostMinor
        ? 'Its cost stays at ${_money(intent.unitCostMinor)}.'
        : 'Its cost changes from ${_money(previous)} to '
              '${_money(intent.unitCostMinor)} for every sale from now on.';
    final confirmed = await showConfirmDialog(
      context,
      title: 'Complete this batch?',
      consequence:
          '${product.name}: ${product.quantity} to ${intent.quantityAfter} in '
          'stock. $costSentence\n\n'
          '${intent.quantity} made for ${_money(intent.totalCostMinor)}.',
      stillTrue:
          'The batch is recorded permanently and cannot be edited. Sales '
          'already recorded keep the cost they were sold at.',
      confirmLabel: 'Complete',
      tier: AppButtonTier.secondary,
      confirmKey: const ValueKey('production-confirm'),
      cancelKey: const ValueKey('production-cancel'),
    );
    if (!mounted || !confirmed) {
      telemetry.recordStep(operation, 'cancelled');
      return;
    }
    telemetry.recordStep(operation, 'confirmed');
    setState(() => _busy = true);
    try {
      await telemetry.trace(
        operation,
        'save_batch',
        () => widget.services.writer.complete(intent),
      );
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'production.save',
        data: {
          'request_id': _requestId,
          'product_id': product.id,
          'quantity': intent.quantity,
          'total_cost_minor': intent.totalCostMinor,
        },
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'This batch could not be saved on this device, so nothing was '
            'recorded. Try again.';
      });
      return;
    }
    telemetry.recordStep(operation, 'saved_locally');
    if (!mounted) return;
    widget.onCompleted(
      AppNotice.confirmed(
        '${intent.quantity} ${product.name} recorded as batch '
        '${intent.batchNumber}, at ${_money(intent.unitCostMinor)} each. The '
        'stock shows now, and it is on its way to the server.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final inset = width < AppLayout.contract.mediumFloor
        ? tokens.spacing.s16
        : tokens.spacing.s24;
    final product = _product;
    final preview = _preview;
    final startedFrom = _startedFrom;
    return ListView(
      key: const ValueKey('production-form'),
      padding: EdgeInsets.all(inset),
      children: <Widget>[
        const SectionHeading('What was made'),
        SizedBox(height: tokens.spacing.s8),
        // **The search or the product, never both.** Once a product is chosen
        // the search gives way to the product itself, and *Edit* brings the
        // search back.
        if (product == null || _choosingProduct) ...<Widget>[
          // **Above the search, not under it**: the search opens its
          // suggestions downward the moment *Edit* focuses it, and a way back
          // drawn beneath the field sat under that list.
          if (product != null) ...<Widget>[
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: AppButton(
                key: const ValueKey('production-product-keep'),
                label: 'Keep ${product.name}',
                icon: Icons.undo,
                tier: AppButtonTier.tertiary,
                size: AppButtonSize.sm,
                onPressed: _busy
                    ? null
                    : () => setState(() => _choosingProduct = false),
              ),
            ),
            SizedBox(height: tokens.spacing.s4),
          ],
          TenantProductTypeAhead(
            key: const ValueKey('production-product-search'),
            session: widget.session,
            reader: widget.reader,
            productSearchReader: widget.services.productSearchReader,
            label: 'Product made',
            selected: product,
            enabled: !_busy,
            // Focused only when *Edit* opened it: on arrival the form's first
            // question is read before the keyboard covers it.
            autofocus: _choosingProduct,
            onSelected: _selectProduct,
            onEdited: () => setState(() {
              _product = null;
              _choosingProduct = false;
              _startedFrom = null;
              _error = null;
            }),
          ),
        ] else
          _ChosenProduct(
            product: product,
            costLabel: product.cost == null
                ? 'No cost recorded'
                : 'Costs '
                      '${_money(checkoutMinorUnitsFromMajor(product.cost!) ?? 0)}',
            onEdit: _busy
                ? null
                : () => setState(() => _choosingProduct = true),
          ),
        SizedBox(height: tokens.spacing.s12),
        AppTextField(
          key: const ValueKey('production-quantity'),
          controller: _quantity,
          enabled: !_busy,
          label: 'How many were made',
          leading: Icons.numbers,
          keyboardType: TextInputType.number,
          onChanged: (_) => _quantityEdited(),
        ),
        SizedBox(height: tokens.spacing.s24),
        const SectionHeading('What it cost'),
        SizedBox(height: tokens.spacing.s8),
        const Disclosure(
          key: ValueKey('production-expenses-warning'),
          summary: 'Keep these out of Expenses',
          child: Text(
            key: ValueKey('production-expenses-warning-text'),
            productionExpensesWarning,
          ),
        ),
        if (startedFrom != null) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          Text(
            key: const ValueKey('production-started-from'),
            'Started from batch ${startedFrom.batchNumber}'
            '${startedFrom.occurredAt == null ? '' : ' of ${reportShortDate(checkoutBusinessDate(startedFrom.occurredAt!))}'}. '
            'The costs follow how many were made until you change one.',
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        ],
        SizedBox(height: tokens.spacing.s12),
        for (final (index, row) in _rows.indexed) ...<Widget>[
          if (index > 0) SizedBox(height: tokens.spacing.s8),
          Row(
            key: row.key,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: AppTextField(
                  key: ValueKey('production-row-description-$index'),
                  controller: row.description,
                  enabled: !_busy,
                  label: 'Cost ${index + 1}',
                  // One example, on the first row. Repeated on every row it
                  // read as a value the form had filled in.
                  placeholder: index == 0 ? 'Flour' : null,
                  maxLength: maximumProductionDescriptionLength,
                  onChanged: (_) => _edited(),
                ),
              ),
              SizedBox(width: tokens.spacing.s8),
              Expanded(
                flex: 2,
                child: AppTextField(
                  key: ValueKey('production-row-amount-$index'),
                  controller: row.amount,
                  enabled: !_busy,
                  label: 'Amount',
                  leading: Icons.payments_outlined,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => _amountEdited(row),
                ),
              ),
              IconButton(
                key: ValueKey('production-row-remove-$index'),
                tooltip: 'Remove cost ${index + 1}',
                constraints: BoxConstraints.tight(
                  tokens.density.minimumTapTarget,
                ),
                icon: Icon(Icons.close, color: tokens.colors.text.secondary),
                onPressed: _busy ? null : () => _removeRow(row),
              ),
            ],
          ),
        ],
        SizedBox(height: tokens.spacing.s8),
        AppButton(
          key: const ValueKey('production-add-row'),
          label: 'Add cost',
          icon: Icons.add,
          expand: true,
          onPressed: _busy || _rows.length >= maximumProductionExpenses
              ? null
              : _addRow,
        ),
        SizedBox(height: tokens.spacing.s16),
        _Figures(
          total: preview == null ? null : _money(preview.totalCostMinor),
          perUnit: preview?.unitCostMinor == null
              ? null
              : _money(preview!.unitCostMinor!),
        ),
        if (_error case final message?) ...<Widget>[
          SizedBox(height: tokens.spacing.s16),
          Callout(
            key: const ValueKey('production-error'),
            status: AppStatus.problem,
            message: message,
          ),
        ],
        SizedBox(height: tokens.spacing.s32),
        AppButton(
          key: const ValueKey('production-submit'),
          label: 'Complete production',
          icon: Icons.check_circle_outline,
          tier: AppButtonTier.secondary,
          loading: _busy,
          expand: true,
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
    );
  }
}

/// The product a batch is being recorded for, once it is chosen: the catalog's
/// own picture or initials, what is on the shelf now, and *Edit* to choose
/// again.
final class _ChosenProduct extends StatelessWidget {
  const _ChosenProduct({
    required this.product,
    required this.costLabel,
    required this.onEdit,
  });

  final TenantProduct product;
  final String costLabel;

  /// Null while the batch is being saved.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return AppCard(
      key: const ValueKey('production-product'),
      child: Row(
        children: <Widget>[
          SizedBox.square(
            dimension: tokens.spacing.s48,
            child: TenantProductVisual(
              product: product,
              semanticLabel: '${product.name} product image',
            ),
          ),
          SizedBox(width: tokens.spacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  product.name,
                  key: const ValueKey('production-product-name'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.titleMedium.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                ),
                SizedBox(height: tokens.spacing.s4),
                Text(
                  '${product.quantity} in stock · $costLabel',
                  style: tokens.typography.caption.copyWith(
                    color: tokens.colors.text.tertiary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.spacing.s8),
          AppButton(
            key: const ValueKey('production-product-edit'),
            label: 'Edit',
            icon: Icons.edit_outlined,
            size: AppButtonSize.md,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

/// The cost per unit and the total, as the rows add up so far - led by the
/// figure the batch exists to settle, the way the sales report leads with its
/// takings.
final class _Figures extends StatelessWidget {
  const _Figures({required this.total, required this.perUnit});

  final String? total;
  final String? perUnit;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final label = tokens.typography.labelMedium.copyWith(
      color: tokens.colors.text.secondary,
    );
    // A figure is set in the money face; the words standing in for one until
    // it can be worked out are set in the interface face, so neither is read
    // as the other.
    final waiting = tokens.typography.bodyMedium.copyWith(
      color: tokens.colors.text.tertiary,
    );
    return AppCard(
      key: const ValueKey('production-figures'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      child: Row(
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.colors.status.ok.bg,
              borderRadius: BorderRadius.circular(tokens.radius.md),
            ),
            child: Padding(
              padding: EdgeInsets.all(tokens.spacing.s12),
              child: Icon(
                Icons.calculate_outlined,
                size: tokens.spacing.s24,
                color: tokens.colors.action.primary.container,
              ),
            ),
          ),
          SizedBox(width: tokens.spacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Cost per unit', style: label),
                SizedBox(height: tokens.spacing.s4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    key: const ValueKey('production-unit-cost'),
                    perUnit ??
                        (total == null ? '-' : 'Enter how many were made'),
                    maxLines: 1,
                    style: perUnit == null
                        ? waiting
                        : tokens.typography.numericHero.copyWith(
                            color: tokens.colors.text.money,
                          ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.spacing.s12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Total', style: label),
              SizedBox(height: tokens.spacing.s4),
              Text(
                key: const ValueKey('production-total'),
                total ?? 'Enter the costs',
                style: total == null
                    ? waiting
                    : tokens.typography.numericBody.copyWith(
                        color: tokens.colors.text.money,
                        fontSize: tokens.typography.bodyLarge.fontSize,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
