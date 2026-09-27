/// Receiving a delivery: one supplier, one reference, as many product lines as
/// the invoice carries.
///
/// **A route rather than a sheet**, for the reason the stock adjustment is one:
/// a line is typed into, and in a sheet the keyboard covers the figure being
/// typed. A delivery can run to dozens of lines, which a sheet was never the
/// shape for.
library;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/observability/app_telemetry.dart';

import '../checkout/checkout_draft.dart';
import '../inventory/product_typeahead.dart';
import '../reporting/reporting_currency.dart';
import '../reports/analysis/report_prose.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'supplier.dart';
import 'supplier_delivery.dart';
import 'supplier_form.dart';

/// Everything receiving a delivery needs from the composition root.
final class TenantSupplierDeliveryServices {
  const TenantSupplierDeliveryServices({
    required this.writer,
    this.productSearchReader,
  });

  final TenantSupplierDeliveryWriter writer;
  final TenantProductSearchReader? productSearchReader;
}

/// Pushes the delivery form, and answers with the notice to show once it
/// closes, or null when nothing was received.
///
/// [supplierId] opens it with that supplier already chosen, which is how a
/// supplier's own record starts one.
Future<AppNotice?> openReceiveDeliveryScreen(
  BuildContext context, {
  required TenantDataReader reader,
  required TenantSupplierDeliveryServices services,
  TenantSupplierWriter? supplierWriter,
  String? supplierId,
}) {
  final controller = TenantSessionScope.of(context);
  return Navigator.of(context).push<AppNotice>(
    AppPageRoute<AppNotice>(
      builder: (routeContext) => TenantSessionScope(
        controller: controller,
        child: TenantReceiveDeliveryScreen(
          reader: reader,
          services: services,
          supplierWriter: supplierWriter,
          initialSupplierId: supplierId,
          onCompleted: (notice) => Navigator.of(routeContext).pop(notice),
        ),
      ),
    ),
  );
}

/// What the delivery form reads before it can be filled in.
final class TenantDeliveryFormView {
  const TenantDeliveryFormView({
    required this.directory,
    required this.currency,
  });

  final TenantSupplierDirectory directory;
  final TenantReportingCurrency currency;
}

/// The delivery form, as a route.
final class TenantReceiveDeliveryScreen extends StatefulWidget {
  const TenantReceiveDeliveryScreen({
    super.key,
    required this.reader,
    required this.services,
    required this.onCompleted,
    this.supplierWriter,
    this.initialSupplierId,
    this.requestIdFactory,
  });

  final TenantDataReader reader;
  final TenantSupplierDeliveryServices services;

  /// Where a supplier added from inside the form is queued. Null offers no
  /// *Add new supplier*.
  final TenantSupplierWriter? supplierWriter;
  final String? initialSupplierId;
  final ValueChanged<AppNotice> onCompleted;
  final String Function()? requestIdFactory;

  @override
  State<TenantReceiveDeliveryScreen> createState() =>
      _TenantReceiveDeliveryScreenState();
}

final class _TenantReceiveDeliveryScreenState
    extends State<TenantReceiveDeliveryScreen> {
  int _generation = 0;
  int? _loadersFor;
  late TenantGuardedLoader<TenantDeliveryFormView> _loader;
  TenantGuardedLoader<TenantDeliveryFormView>? _loaderCached;

  late String? _supplierId = widget.initialSupplierId;

  void _composeLoaders() {
    if (_loadersFor == _generation) return;
    _loadersFor = _generation;
    TenantGuardedLoader<TenantDeliveryFormView> readWith(
      TenantDataReader reader,
    ) =>
        (session) async => TenantDeliveryFormView(
          directory: await TenantSupplierRepository(
            session: session,
            reader: reader,
          ).loadDirectory(),
          currency: await TenantReportingCurrency.read(
            session: session,
            reader: reader,
          ),
        );
    _loader = readWith(widget.reader);
    final cached = widget.reader.cached;
    _loaderCached = cached == null ? null : readWith(cached);
  }

  @override
  Widget build(BuildContext context) {
    _composeLoaders();
    return TenantRouteGuard<TenantDeliveryFormView>(
      allowedRoles: TenantSupplierRepository.allowedRoles,
      load: _loader,
      loadCached: _loaderCached,
      loading: const _DeliveryFrame(
        child: LoadingState(message: 'Reading suppliers'),
      ),
      failure: (context, error) => const _DeliveryFrame(
        child: ErrorState(
          key: ValueKey('delivery-failure'),
          badgeLabel: 'Not read',
          statement:
              'The suppliers could not be read, so a delivery cannot be '
              'received yet.',
          stillTrue: 'Nothing has been recorded or changed.',
        ),
      ),
      builder: (context, session, view) => _DeliveryFrame(
        child: _DeliveryForm(
          session: session,
          reader: widget.reader,
          view: view,
          services: widget.services,
          supplierWriter: widget.supplierWriter,
          supplierId: _supplierId,
          requestIdFactory: widget.requestIdFactory,
          onSupplierChosen: (id) => setState(() => _supplierId = id),
          onSupplierAdded: (id) => setState(() {
            _supplierId = id;
            // The directory is read again so the supplier just added is one
            // the form can choose.
            _generation++;
          }),
          onCompleted: widget.onCompleted,
        ),
      ),
    );
  }
}

final class _DeliveryFrame extends StatelessWidget {
  const _DeliveryFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Receive delivery',
    subtitle: 'Stock in from a supplier.',
    contentWidth: AppContentWidth.reading,
    body: child,
  );
}

/// One line of the form, with the fields it is typed into.
final class _LineState {
  _LineState(this.product);

  final TenantProduct product;
  final TextEditingController quantity = TextEditingController();
  final TextEditingController unitCost = TextEditingController();

  void dispose() {
    quantity.dispose();
    unitCost.dispose();
  }

  TenantDeliveryLineDraft get draft => TenantDeliveryLineDraft(
    product: product,
    quantity: quantity.text,
    unitCost: unitCost.text,
  );
}

final class _DeliveryForm extends StatefulWidget {
  const _DeliveryForm({
    required this.session,
    required this.reader,
    required this.view,
    required this.services,
    required this.supplierWriter,
    required this.supplierId,
    required this.requestIdFactory,
    required this.onSupplierChosen,
    required this.onSupplierAdded,
    required this.onCompleted,
  });

  final TenantSession session;
  final TenantDataReader reader;
  final TenantDeliveryFormView view;
  final TenantSupplierDeliveryServices services;
  final TenantSupplierWriter? supplierWriter;
  final String? supplierId;
  final String Function()? requestIdFactory;
  final ValueChanged<String> onSupplierChosen;
  final ValueChanged<String> onSupplierAdded;
  final ValueChanged<AppNotice> onCompleted;

  @override
  State<_DeliveryForm> createState() => _DeliveryFormState();
}

final class _DeliveryFormState extends State<_DeliveryForm> {
  static const String _newSupplier = '__new_supplier__';

  final TextEditingController _reference = TextEditingController();
  final List<_LineState> _lines = <_LineState>[];
  final List<int> _openProductFields = <int>[0];
  int _nextProductField = 1;
  bool _busy = false;
  String? _error;

  /// One request per delivery, held until it is queued: every page is named
  /// from it, so a retry after a partial failure names the same pages.
  String? _requestId;

  @override
  void dispose() {
    _reference.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  TenantSupplier? get _supplier {
    final id = widget.supplierId;
    final supplier = id == null ? null : widget.view.directory.byId(id);
    return supplier != null && supplier.active ? supplier : null;
  }

  bool get _canSubmit =>
      !_busy &&
      _supplier != null &&
      _lines.isNotEmpty &&
      _lines.every((line) => line.quantity.text.trim().isNotEmpty);

  String _money(int minor) => widget.view.currency.format(minor / 100);

  Future<void> _chooseSupplier(String? value) async {
    if (value == null) return;
    if (value != _newSupplier) {
      widget.onSupplierChosen(value);
      return;
    }
    final writer = widget.supplierWriter;
    if (writer == null) return;
    String? added;
    await showSupplierFormSheet(
      context,
      session: widget.session,
      repository: TenantSupplierRepository(
        session: widget.session,
        reader: widget.reader,
      ),
      writer: writer,
      directory: widget.view.directory,
      onSaved: (id) => added = id,
    );
    if (added case final id?) widget.onSupplierAdded(id);
  }

  void _addProduct() => setState(() {
    _openProductFields.add(_nextProductField++);
  });

  void _selectProduct(int field, TenantProduct product) {
    if (_lines.any((line) => line.product.id == product.id)) return;
    setState(() {
      _openProductFields.remove(field);
      _lines.add(_LineState(product));
      _error = null;
    });
  }

  void _removeProductField(int field) => setState(() {
    _openProductFields.remove(field);
  });

  void _remove(_LineState line) => setState(() {
    _lines.remove(line);
    line.dispose();
  });

  String _refusal(TenantSupplierDeliveryException error) {
    final name = error.productName;
    return switch (error.code) {
      'invalid_quantity' =>
        'Enter how many units of $name arrived, as a whole number from 1 to '
            '$maximumDeliveryLineQuantity.',
      'invalid_unit_cost' =>
        'The unit cost for $name must be an amount above zero with at most two '
            'decimal places - or left blank to keep its cost as it is.',
      'duplicate_product' =>
        '$name is on this delivery twice. Put all of it on one line.',
      'retired_product' =>
        '$name has been retired, so stock cannot be received into it.',
      'quantity_out_of_range' => '$name cannot hold that much more stock.',
      'invalid_reference' =>
        'A reference may be up to $maximumDeliveryReferenceLength characters on '
            'one line.',
      'inactive_supplier' =>
        'That supplier is inactive. Offer it again from its record first.',
      'too_many_lines' =>
        'One delivery can hold up to $maximumDeliveryLines products. Record the '
            'rest as a second delivery.',
      'no_lines' => 'Add at least one product that arrived.',
      'delivery_forbidden' =>
        'Only an owner, administrator or manager may receive a delivery.',
      _ => 'This delivery could not be received as entered.',
    };
  }

  String _consequence(
    TenantSupplierDeliveryIntent intent,
    TenantSupplierDelivery? earlier,
  ) {
    const listed = 8;
    final buffer = StringBuffer();
    if (earlier != null) {
      final when = earlier.occurredAt == null
          ? ''
          : ', recorded ${reportShortDate(checkoutBusinessDate(earlier.occurredAt!))}';
      buffer.write(
        '${intent.supplier.name} already has a delivery under '
        '${intent.reference}$when. Check this is not the same one.\n\n',
      );
    }
    final products = intent.lines.length;
    buffer.write(
      'From ${intent.supplier.name}'
      '${intent.reference == null ? '' : ' · ${intent.reference}'}: '
      '$products ${products == 1 ? 'product' : 'products'}, '
      '${intent.unitCount} ${intent.unitCount == 1 ? 'unit' : 'units'}.\n',
    );
    for (final line in intent.lines.take(listed)) {
      buffer.write(
        '\n${line.product.name}: ${line.product.quantity} to '
        '${line.quantityAfter} in stock.',
      );
      if (line.changesCost) {
        final previous = line.previousCostMinor;
        buffer.write(
          previous == null
              ? ' Cost becomes ${_money(line.unitCostMinor!)} for every sale '
                    'from now on.'
              : ' Cost changes from ${_money(previous)} to '
                    '${_money(line.unitCostMinor!)} for every sale from now on.',
        );
      }
    }
    if (products > listed) {
      buffer.write('\n\nAnd ${products - listed} more.');
    }
    return buffer.toString();
  }

  Future<void> _submit() async {
    final supplier = _supplier;
    if (supplier == null) return;
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'receiving.delivery',
      screen: 'receiving',
      context: {'supplier_id': supplier.id, 'supplier_name': supplier.name},
    );
    final repository = TenantSupplierDeliveryRepository(
      session: widget.session,
      reader: widget.reader,
    );
    final TenantSupplierDeliveryIntent intent;
    try {
      intent = repository.buildIntent(
        supplier: supplier,
        reference: _reference.text,
        lines: <TenantDeliveryLineDraft>[for (final line in _lines) line.draft],
        requestId: _requestId ??=
            (widget.requestIdFactory ?? secureTenantDeliveryRequestId)(),
      );
    } on TenantSupplierDeliveryException catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'receiving.validate',
      );
      setState(() => _error = _refusal(error));
      return;
    }
    telemetry.recordStep(
      operation,
      'validated',
      data: {'request_id': _requestId, 'line_count': intent.lines.length},
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    TenantSupplierDelivery? earlier;
    if (intent.reference case final reference?) {
      try {
        earlier = await repository.findByReference(
          supplierId: supplier.id,
          reference: reference,
        );
      } catch (error, stackTrace) {
        AppTelemetry.captureHandled(
          error,
          stackTrace,
          operation: operation,
          boundary: 'receiving.reference_lookup',
        );
        // A warning that cannot be checked is not a reason to refuse.
        earlier = null;
      }
    }
    if (!mounted) return;
    // Not busy while the question is open: the person is reading, and a
    // spinner under a dialog says something is happening that is not.
    setState(() => _busy = false);
    final confirmed = await showConfirmDialog(
      context,
      title: 'Receive this delivery?',
      consequence: _consequence(intent, earlier),
      stillTrue:
          'Every line is recorded permanently in its product\'s stock ledger. '
          'Sales already recorded keep the cost they were sold at.',
      // One word: the dialog's buttons share a phone's width with *Cancel*.
      confirmLabel: 'Receive',
      tier: AppButtonTier.secondary,
      confirmKey: const ValueKey('delivery-confirm'),
      cancelKey: const ValueKey('delivery-cancel'),
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
        'save_delivery',
        () => widget.services.writer.receive(intent),
      );
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'receiving.save',
        data: {
          'request_id': _requestId,
          'supplier_id': supplier.id,
          'line_count': intent.lines.length,
        },
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error'.contains('operation_id_conflict')
            ? 'Part of this delivery is already saved on this device with '
                  'different figures. Leave this screen and check the '
                  'supplier\'s deliveries before receiving it again.'
            : 'This delivery could not be saved on this device, so nothing '
                  'was recorded. Try again.';
      });
      return;
    }
    telemetry.recordStep(operation, 'saved_locally');
    if (!mounted) return;
    final products = intent.lines.length;
    widget.onCompleted(
      AppNotice.confirmed(
        'Delivery from ${supplier.name} received: $products '
        '${products == 1 ? 'product' : 'products'}, ${intent.unitCount} '
        '${intent.unitCount == 1 ? 'unit' : 'units'}. The stock shows now, and '
        'it is on its way to the server.',
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
    final active = widget.view.directory.active;
    final chosen = _supplier;
    return ListView(
      key: const ValueKey('delivery-form'),
      padding: EdgeInsets.all(inset),
      children: <Widget>[
        const Disclosure(
          key: ValueKey('delivery-explanation'),
          summary: 'What receiving does',
          child: Text(
            key: ValueKey('delivery-explanation-text'),
            'Each product\'s stock goes up by what arrived, and each line is '
            'recorded in that product\'s stock ledger.\n\n'
            'A unit cost you enter becomes the product\'s cost for every sale '
            'from now on. Leave it blank to keep the cost as it is. Sales '
            'already recorded keep the cost they were sold at.',
          ),
        ),
        SizedBox(height: tokens.spacing.s16),
        // Typed nullable so it can stand empty until a supplier is chosen.
        AppSelect<String?>(
          key: const ValueKey('delivery-supplier'),
          label: 'Supplier',
          value: chosen?.id,
          enabled: !_busy,
          helper: active.isEmpty
              ? 'Add the supplier this delivery came from.'
              : null,
          items: <AppSelectItem<String?>>[
            for (final supplier in active)
              AppSelectItem<String?>(
                key: ValueKey('delivery-supplier-${supplier.id}'),
                value: supplier.id,
                label: supplier.name,
              ),
            if (widget.supplierWriter != null)
              const AppSelectItem<String?>(
                key: ValueKey('delivery-supplier-new'),
                value: _newSupplier,
                label: 'Add new supplier',
              ),
          ],
          onChanged: _busy ? null : _chooseSupplier,
        ),
        SizedBox(height: tokens.spacing.s12),
        AppTextField(
          key: const ValueKey('delivery-reference'),
          controller: _reference,
          enabled: !_busy,
          label: 'Invoice or reference (optional)',
          placeholder: 'INV-48392',
          maxLength: maximumDeliveryReferenceLength,
          leading: Icons.receipt_long_outlined,
        ),
        SizedBox(height: tokens.spacing.s16),
        const SectionHeading('What arrived'),
        SizedBox(height: tokens.spacing.s8),
        for (final (index, line) in _lines.indexed) ...<Widget>[
          if (index > 0) SizedBox(height: tokens.spacing.s12),
          _DeliveryLineCard(
            line: line,
            enabled: !_busy,
            costLabel: line.product.cost == null
                ? 'No cost recorded'
                : checkoutMinorUnitsFromMajor(line.product.cost!) == null
                ? 'Cost unreadable'
                : 'Costs ${_money(checkoutMinorUnitsFromMajor(line.product.cost!)!)}',
            // A refusal is about the last attempt, and goes with any edit.
            onChanged: () => setState(() => _error = null),
            onRemove: () => _remove(line),
          ),
        ],
        if (_lines.isEmpty)
          Text(
            key: const ValueKey('delivery-no-lines'),
            'Nothing added yet. Add each product on the invoice.',
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        for (final field in _openProductFields) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          Row(
            key: ValueKey('delivery-product-field-$field'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TenantProductTypeAhead(
                  session: widget.session,
                  reader: widget.reader,
                  productSearchReader: widget.services.productSearchReader,
                  label: 'Product',
                  excludedIds: <String>{
                    for (final line in _lines) line.product.id,
                  },
                  enabled: !_busy,
                  onSelected: (product) => _selectProduct(field, product),
                ),
              ),
              IconButton(
                key: ValueKey('delivery-product-field-remove-$field'),
                tooltip: 'Remove product search',
                icon: Icon(Icons.close, color: tokens.colors.text.secondary),
                onPressed: _busy ? null : () => _removeProductField(field),
              ),
            ],
          ),
        ],
        SizedBox(height: tokens.spacing.s12),
        AppButton(
          key: const ValueKey('delivery-add-product'),
          label: 'Add product',
          icon: Icons.add,
          expand: true,
          onPressed:
              _busy ||
                  _lines.length + _openProductFields.length >=
                      maximumDeliveryLines
              ? null
              : _addProduct,
        ),
        if (_error case final message?) ...<Widget>[
          SizedBox(height: tokens.spacing.s16),
          Callout(
            key: const ValueKey('delivery-error'),
            status: AppStatus.problem,
            message: message,
          ),
        ],
        SizedBox(height: tokens.spacing.s32),
        AppButton(
          key: const ValueKey('delivery-submit'),
          label: 'Receive delivery',
          icon: Icons.local_shipping_outlined,
          tier: AppButtonTier.secondary,
          loading: _busy,
          expand: true,
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
    );
  }
}

/// One product line: what it holds now, and what arrived.
final class _DeliveryLineCard extends StatelessWidget {
  const _DeliveryLineCard({
    required this.line,
    required this.enabled,
    required this.costLabel,
    required this.onChanged,
    required this.onRemove,
  });

  final _LineState line;
  final bool enabled;
  final String costLabel;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final product = line.product;
    return DecoratedBox(
      key: ValueKey('delivery-line-${product.id}'),
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        borderRadius: BorderRadius.circular(tokens.radius.lg),
        border: Border.all(color: tokens.colors.surface.cardEdge),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                        '${product.quantity} in stock · $costLabel',
                        style: tokens.typography.caption.copyWith(
                          color: tokens.colors.text.tertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('delivery-line-remove-${product.id}'),
                  tooltip: 'Remove ${product.name}',
                  constraints: BoxConstraints.tight(
                    tokens.density.minimumTapTarget,
                  ),
                  icon: Icon(Icons.close, color: tokens.colors.text.secondary),
                  onPressed: enabled ? onRemove : null,
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.s12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: AppTextField(
                    key: ValueKey('delivery-line-quantity-${product.id}'),
                    controller: line.quantity,
                    enabled: enabled,
                    label: 'Units',
                    leading: Icons.numbers,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => onChanged(),
                  ),
                ),
                SizedBox(width: tokens.spacing.s12),
                Expanded(
                  child: AppTextField(
                    key: ValueKey('delivery-line-cost-${product.id}'),
                    controller: line.unitCost,
                    enabled: enabled,
                    label: 'Unit cost (optional)',
                    leading: Icons.payments_outlined,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
