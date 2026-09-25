/// Recording what a batch made and what it cost to make.
///
/// **A route rather than a sheet**, for the reason receiving a delivery is one:
/// every figure here is typed, and in a sheet the keyboard covers the row being
/// typed into.
library;

import 'package:flutter/material.dart';

import '../checkout/checkout_draft.dart';
import '../inventory/catalog_management.dart';
import '../inventory/product_picker.dart';
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
  _RowState({String description = '', String amount = ''})
    : description = TextEditingController(text: description),
      amount = TextEditingController(text: amount);

  final TextEditingController description;
  final TextEditingController amount;
  final Key key = UniqueKey();

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

  /// The batch the rows were started from, said so beside them.
  TenantProductionBatch? _startedFrom;
  bool _busy = false;
  String? _error;

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

  TenantProductionRepository get _repository =>
      TenantProductionRepository(session: widget.session, reader: widget.reader);

  List<TenantProductionRowDraft> get _drafts =>
      <TenantProductionRowDraft>[for (final row in _rows) row.draft];

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

  Future<void> _chooseProduct() async {
    final product = await showTenantProductPicker(
      context,
      session: widget.session,
      reader: widget.reader,
      productSearchReader: widget.services.productSearchReader,
      admits: (product) => product.costType == TenantProductCostType.produced,
      refusedHint:
          'Some products that match are bought in. Mark a product as Made '
          'here when you edit it in Inventory to record production for it.',
      title: 'What was made?',
    );
    if (product == null || !mounted) return;
    setState(() {
      _product = product;
      _startedFrom = null;
      _error = null;
    });
    TenantProductionBatch? last;
    try {
      last = await _repository.lastBatchOf(product.id);
    } catch (_) {
      // A batch that cannot be looked up is simply not offered as a start.
      last = null;
    }
    if (!mounted || last == null || _product?.id != product.id) return;
    // **Only over rows nobody has typed into.** Starting from the last batch
    // saves a baker typing the same four rows every morning; overwriting rows
    // somebody already filled in would lose their work.
    if (_rows.any((row) => !row.draft.isBlank)) return;
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
              amount: tenantCatalogMajorUnits(expense.amountMinor),
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
      'not_made_here' =>
        'That product is bought in. Mark it as Made here in Inventory first.',
      'retired_product' => 'That product has been retired.',
      'production_forbidden' =>
        'Only an owner, administrator or manager may record production.',
      _ => 'This batch could not be recorded as entered.',
    };
  }

  Future<void> _submit() async {
    final product = _product;
    if (product == null) return;
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
    } on TenantProductionException catch (error) {
      setState(() => _error = _refusal(error));
      return;
    }
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
      tier: AppButtonTier.primary,
      confirmKey: const ValueKey('production-confirm'),
      cancelKey: const ValueKey('production-cancel'),
    );
    if (!mounted || !confirmed) return;
    setState(() => _busy = true);
    try {
      await widget.services.writer.complete(intent);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'This batch could not be saved on this device, so nothing was '
            'recorded. Try again.';
      });
      return;
    }
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
        if (product == null)
          AppButton(
            key: const ValueKey('production-choose-product'),
            label: 'Choose the product',
            icon: Icons.bakery_dining_outlined,
            expand: true,
            onPressed: _busy ? null : _chooseProduct,
          )
        else
          AppCard(
            key: const ValueKey('production-product'),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        product.name,
                        style: tokens.typography.titleMedium.copyWith(
                          color: tokens.colors.text.primary,
                        ),
                      ),
                      SizedBox(height: tokens.spacing.s4),
                      Text(
                        '${product.quantity} in stock · '
                        '${product.cost == null ? 'No cost recorded' : 'Costs ${_money(checkoutMinorUnitsFromMajor(product.cost!) ?? 0)}'}',
                        style: tokens.typography.caption.copyWith(
                          color: tokens.colors.text.tertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                AppButton(
                  key: const ValueKey('production-change-product'),
                  label: 'Change',
                  onPressed: _busy ? null : _chooseProduct,
                ),
              ],
            ),
          ),
        SizedBox(height: tokens.spacing.s12),
        AppTextField(
          key: const ValueKey('production-quantity'),
          controller: _quantity,
          enabled: !_busy,
          label: 'How many were made',
          leading: Icons.numbers,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
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
            '${startedFrom.createdAt == null ? '' : ' of ${reportShortDate(checkoutBusinessDate(startedFrom.createdAt!))}'}. '
            'Change anything that was different this time.',
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
                  placeholder: 'Flour',
                  maxLength: maximumProductionDescriptionLength,
                  onChanged: (_) => setState(() {}),
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
                  onChanged: (_) => setState(() {}),
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
          tier: AppButtonTier.primary,
          loading: _busy,
          expand: true,
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
    );
  }
}

/// The total and the cost per unit, as the rows add up so far.
final class _Figures extends StatelessWidget {
  const _Figures({required this.total, required this.perUnit});

  final String? total;
  final String? perUnit;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    Widget line(String label, String value, Key key, {bool emphasis = false}) =>
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: tokens.typography.bodyMedium.copyWith(
                  color: tokens.colors.text.secondary,
                ),
              ),
            ),
            Text(
              key: key,
              value,
              style:
                  (emphasis
                          ? tokens.typography.numericHero
                          : tokens.typography.numericBody)
                      .copyWith(color: tokens.colors.text.money),
            ),
          ],
        );
    return AppCard(
      key: const ValueKey('production-figures'),
      child: Column(
        children: <Widget>[
          line(
            'Total',
            total ?? 'Enter the costs',
            const ValueKey('production-total'),
          ),
          SizedBox(height: tokens.spacing.s8),
          line(
            'Cost per unit',
            perUnit ?? (total == null ? '-' : 'Enter how many were made'),
            const ValueKey('production-unit-cost'),
            emphasis: perUnit != null,
          ),
        ],
      ),
    );
  }
}
