/// One customer: how to reach them, whether their receipts go to them on
/// WhatsApp, their points, and what they have bought.
library;

import 'package:flutter/material.dart';

import '../reporting/reporting_currency.dart';
import '../reports/analysis/report_prose.dart';
import '../sales/sale_history.dart';
import '../suppliers/supplier_card.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import '../observability/app_telemetry.dart';
import 'customer.dart';
import 'customer_card.dart';
import 'customer_directory_panel.dart';
import 'customer_form.dart';

/// One customer's record, as a route.
final class TenantCustomerRecordScreen extends StatefulWidget {
  const TenantCustomerRecordScreen({
    super.key,
    required this.reader,
    required this.customerId,
    this.writer,
    this.salesReader,
    this.currency,
  });

  final TenantDataReader reader;
  final String customerId;
  final TenantCustomerWriter? writer;
  final TenantSalesHistoryQueryReader? salesReader;

  /// The business's currency, for the dialling code a correction starts from.
  final String? currency;

  @override
  State<TenantCustomerRecordScreen> createState() =>
      _TenantCustomerRecordScreenState();
}

final class _TenantCustomerRecordScreenState
    extends State<TenantCustomerRecordScreen> {
  int _generation = 0;
  int? _loadersFor;
  late TenantGuardedLoader<TenantCustomer?> _loader;
  TenantGuardedLoader<TenantCustomer?>? _loaderCached;

  void _composeLoaders() {
    if (_loadersFor == _generation) return;
    _loadersFor = _generation;
    TenantGuardedLoader<TenantCustomer?> readWith(TenantDataReader reader) =>
        (session) => TenantCustomerRepository(
          session: session,
          reader: reader,
        ).loadCustomer(widget.customerId);
    _loader = readWith(widget.reader);
    final cached = widget.reader.cached;
    _loaderCached = cached == null ? null : readWith(cached);
  }

  void _reload() => setState(() => _generation++);

  Future<void> _edit(TenantSession session, TenantCustomer customer) async {
    final writer = widget.writer;
    if (writer == null) return;
    final outcome = await showCustomerFormSheet(
      context,
      session: session,
      reader: widget.reader,
      writer: writer,
      customer: customer,
      dialCode: dialCodeForCurrency(widget.currency),
    );
    if (!mounted || outcome == null) return;
    showAppSnackBar(context, outcome.notice);
    _reload();
  }

  Future<void> _setActive(
    TenantSession session,
    TenantCustomer customer, {
    required bool active,
  }) async {
    final writer = widget.writer;
    if (writer == null) return;
    final notice = await setCustomerStanding(
      context,
      session: session,
      reader: widget.reader,
      writer: writer,
      customer: customer,
      active: active,
    );
    if (!mounted || notice == null) return;
    showAppSnackBar(context, notice);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    _composeLoaders();
    return TenantRouteGuard<TenantCustomer?>(
      allowedRoles: TenantCustomerRepository.manageRoles,
      load: _loader,
      loadCached: _loaderCached,
      loading: const _RecordFrame(
        title: 'Customer',
        child: LoadingState(message: 'Reading this customer'),
      ),
      failure: (context, error) => const _RecordFrame(
        title: 'Customer',
        child: ErrorState(
          key: ValueKey('customer-record-failure'),
          badgeLabel: 'Not read',
          statement: 'This customer could not be read.',
          stillTrue: 'Nothing has been recorded or changed.',
        ),
      ),
      builder: (context, session, customer) {
        if (customer == null) {
          return const _RecordFrame(
            title: 'Customer',
            child: EmptyState(
              key: ValueKey('customer-record-missing'),
              title: 'This customer is not in this business',
              hint:
                  'They may have been added on a device that has not synced '
                  'yet.',
              illustration: 'file-search.svg',
            ),
          );
        }
        return _RecordFrame(
          title: customer.name,
          child: _RecordContents(
            customer: customer,
            // Keyed by the generation, so a correction reads the history back.
            purchases: TenantCustomerPurchases(
              key: ValueKey('customer-purchases-$_generation'),
              reader: widget.reader,
              salesReader: widget.salesReader,
              session: session,
              customer: customer,
            ),
            onEdit: widget.writer == null
                ? null
                : () => _edit(session, customer),
            onSetActive: widget.writer == null
                ? null
                : (active) => _setActive(session, customer, active: active),
          ),
        );
      },
    );
  }
}

final class _RecordFrame extends StatelessWidget {
  const _RecordFrame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: title,
    subtitle: 'Customer',
    contentWidth: AppContentWidth.records,
    body: child,
  );
}

final class _RecordContents extends StatelessWidget {
  const _RecordContents({
    required this.customer,
    required this.purchases,
    required this.onEdit,
    required this.onSetActive,
  });

  final TenantCustomer customer;
  final Widget purchases;
  final VoidCallback? onEdit;
  final ValueChanged<bool>? onSetActive;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final inset = width < AppLayout.contract.mediumFloor
        ? tokens.spacing.s16
        : tokens.spacing.s24;
    final facts = <(String, String, IconData)>[
      if (customer.phone case final phone?) ('Phone', phone, Icons.phone_outlined),
      if (customer.phone != null)
        (
          'Receipts on WhatsApp',
          customer.whatsappOptIn
              ? 'Agreed. Their receipts can go to this number.'
              : 'Not agreed. No receipt is sent to them on WhatsApp.',
          Icons.chat_outlined,
        ),
      if (customer.kraPin case final pin?) ('KRA PIN', pin, Icons.badge_outlined),
      if (customer.email case final email?) ('Email', email, Icons.mail_outline),
      if (customer.notes case final notes?) ('Notes', notes, Icons.notes_outlined),
    ];
    return ListView(
      key: const ValueKey('customer-record'),
      padding: EdgeInsets.all(inset),
      children: <Widget>[
        if (!customer.active) ...<Widget>[
          const Callout(
            key: ValueKey('customer-record-inactive'),
            status: AppStatus.neutral,
            title: 'Inactive',
            message:
                'Not offered at the till, and sent no receipts. Their sales '
                'and points stay on record, and they can be offered again '
                'below.',
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        if (onEdit != null || onSetActive != null) ...<Widget>[
          AppActionRow(
            alignment: MainAxisAlignment.start,
            expandActions: true,
            actions: <Widget>[
              if (onEdit case final edit?)
                AppButton(
                  key: const ValueKey('customer-record-edit'),
                  label: 'Edit',
                  icon: Icons.edit_outlined,
                  expand: true,
                  onPressed: edit,
                ),
              if (onSetActive case final setActive?)
                customer.active
                    ? AppButton(
                        key: const ValueKey('customer-record-inactive-action'),
                        label: 'Mark inactive',
                        icon: Icons.block_outlined,
                        tier: AppButtonTier.destructive,
                        expand: true,
                        onPressed: () => setActive(false),
                      )
                    : AppButton(
                        key: const ValueKey('customer-record-reactivate'),
                        label: 'Reactivate',
                        icon: Icons.replay_outlined,
                        expand: true,
                        onPressed: () => setActive(true),
                      ),
            ],
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        AppCard(
          key: const ValueKey('customer-record-summary'),
          padding: EdgeInsets.all(tokens.spacing.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  SupplierMonogram(name: customer.name),
                  SizedBox(width: tokens.spacing.s12),
                  Expanded(
                    child: _Headline(
                      caption: 'Points',
                      value: '${customer.points}',
                      valueKey: const ValueKey('customer-record-points'),
                      figure: true,
                    ),
                  ),
                  SizedBox(width: tokens.spacing.s12),
                  Expanded(
                    child: _Headline(
                      caption: 'Last bought',
                      value: customerLastBoughtLabel(customer),
                      valueKey: const ValueKey('customer-record-last-bought'),
                      figure: customer.lastSaleAt != null,
                      end: true,
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.spacing.s16),
              Divider(height: 1, color: tokens.colors.surface.borderSubtle),
              SizedBox(height: tokens.spacing.s12),
              Text(
                'How to reach them',
                style: tokens.typography.titleMedium.copyWith(
                  color: tokens.colors.text.primary,
                ),
              ),
              SizedBox(height: tokens.spacing.s12),
              if (facts.isEmpty)
                Text(
                  'No contact details are recorded for this customer.',
                  key: const ValueKey('customer-record-no-contact'),
                  style: tokens.typography.bodyMedium.copyWith(
                    color: tokens.colors.text.tertiary,
                  ),
                )
              else
                for (final (index, fact) in facts.indexed) ...<Widget>[
                  if (index > 0) SizedBox(height: tokens.spacing.s12),
                  _Fact(label: fact.$1, value: fact.$2, icon: fact.$3),
                ],
            ],
          ),
        ),
        SizedBox(height: tokens.spacing.s24),
        purchases,
      ],
    );
  }
}

/// One headline figure: `label.md` over the figure, figures in the figures'
/// face and words in the interface one.
final class _Headline extends StatelessWidget {
  const _Headline({
    required this.caption,
    required this.value,
    required this.valueKey,
    required this.figure,
    this.end = false,
  });

  final String caption;
  final String value;
  final Key valueKey;
  final bool figure;
  final bool end;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          caption,
          style: tokens.typography.labelMedium.copyWith(
            color: tokens.colors.text.secondary,
          ),
        ),
        SizedBox(height: tokens.spacing.s4),
        Text(
          value,
          key: valueKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: figure
              ? tokens.typography.numericCompact.copyWith(
                  color: tokens.colors.text.primary,
                )
              : tokens.typography.titleMedium.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
        ),
      ],
    );
  }
}

/// One contact detail: a glyph tile, a caption, and the value under it.
final class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.colors.surface.overlay,
              borderRadius: BorderRadius.circular(tokens.radius.sm),
            ),
            child: SizedBox.square(
              dimension: tokens.spacing.s40,
              child: Icon(
                icon,
                size: AppButton.iconSize,
                color: tokens.colors.action.primary.container,
              ),
            ),
          ),
        ),
        SizedBox(width: tokens.spacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
              SizedBox(height: tokens.spacing.s4),
              SelectableText(
                value,
                style: tokens.typography.bodyMedium.copyWith(
                  color: tokens.colors.text.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One customer's purchases, newest first, as a section of their record.
///
/// **Its own read, not the record's**, for the supplier history's reason: a
/// history that cannot be read - an index still building, a device with
/// nothing cached - costs this section and never the details above it.
final class TenantCustomerPurchases extends StatefulWidget {
  const TenantCustomerPurchases({
    super.key,
    required this.reader,
    required this.session,
    required this.customer,
    this.salesReader,
  });

  final TenantDataReader reader;
  final TenantSalesHistoryQueryReader? salesReader;
  final TenantSession session;
  final TenantCustomer customer;

  /// How many sales one read shows before *Show older purchases*.
  static const int pageSize = 10;

  @override
  State<TenantCustomerPurchases> createState() =>
      _TenantCustomerPurchasesState();
}

final class _TenantCustomerPurchasesState
    extends State<TenantCustomerPurchases> {
  final List<TenantSale> _sales = <TenantSale>[];
  TenantReportingCurrency _currency = TenantReportingCurrency.unknown;
  String? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load(first: true);
  }

  Future<void> _load({bool first = false}) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      if (first) {
        _currency = await TenantReportingCurrency.read(
          session: widget.session,
          reader: widget.reader,
        );
      }
      final page = await TenantSaleHistoryRepository(
        session: widget.session,
        reader: widget.reader,
        reportReader: widget.salesReader,
      ).loadCustomerSales(
        customerId: widget.customer.id,
        pageSize: TenantCustomerPurchases.pageSize,
        cursor: first ? null : _cursor,
      );
      if (!mounted) return;
      setState(() {
        if (first) _sales.clear();
        _sales.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'customers.purchases_read',
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      key: const ValueKey('customer-purchases'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SectionHeading('Purchases'),
        SizedBox(height: tokens.spacing.s8),
        if (_failed)
          ErrorState(
            key: const ValueKey('customer-purchases-failure'),
            badgeLabel: 'Not read',
            statement: 'What this customer bought could not be read.',
            stillTrue: 'Nothing has been recorded or changed.',
            actions: <Widget>[
              AppButton(
                key: const ValueKey('customer-purchases-retry'),
                label: 'Try again',
                onPressed: () => _load(first: _sales.isEmpty),
              ),
            ],
          )
        else if (_loading && _sales.isEmpty)
          const LoadingState(message: 'Reading purchases')
        else ...<Widget>[
          if (_sales.isEmpty)
            const EmptyState(
              key: ValueKey('customer-purchases-empty'),
              title: 'No purchases yet',
              hint:
                  'Each sale the till records for this customer is listed '
                  'here once it reaches the server.',
              illustration: 'file-search.svg',
            )
          else
            for (final (index, sale) in _sales.indexed) ...<Widget>[
              if (index > 0) SizedBox(height: tokens.spacing.s12),
              _PurchaseCard(
                key: ValueKey('customer-purchase-${sale.id}'),
                sale: sale,
                money: (minor) => _currency.format(minor / 100),
              ),
            ],
          if (_hasMore) ...<Widget>[
            SizedBox(height: tokens.spacing.s12),
            AppButton(
              key: const ValueKey('customer-purchases-more'),
              label: 'Show older purchases',
              loading: _loading,
              expand: true,
              onPressed: _loading ? null : () => _load(),
            ),
          ],
        ],
      ],
    );
  }
}

/// One purchase: when, what it came to, and what was in it.
final class _PurchaseCard extends StatelessWidget {
  const _PurchaseCard({super.key, required this.sale, required this.money});

  final TenantSale sale;
  final String Function(int minor) money;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        border: Border.all(color: tokens.colors.surface.cardEdge),
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    reportShortDate(sale.businessDate),
                    style: tokens.typography.titleMedium.copyWith(
                      color: tokens.colors.text.primary,
                    ),
                  ),
                ),
                Text(
                  money(sale.totalMinor),
                  key: ValueKey('customer-purchase-total-${sale.id}'),
                  style: tokens.typography.numericBody.copyWith(
                    color: tokens.colors.text.money,
                  ),
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.s4),
            Text(
              sale.lines
                  .map((line) => '${line.quantity} x ${line.name}')
                  .join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tokens.typography.bodyMedium.copyWith(
                color: tokens.colors.text.secondary,
              ),
            ),
            SizedBox(height: tokens.spacing.s4),
            Text(
              'Receipt ${sale.receiptNumber}',
              style: tokens.typography.caption.copyWith(
                color: tokens.colors.text.tertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
