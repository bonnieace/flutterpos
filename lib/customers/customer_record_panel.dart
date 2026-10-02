/// One customer: how to reach them, whether their receipts go to them on
/// WhatsApp, their points, and what they have bought.
library;

import 'package:flutter/material.dart';

import '../reporting/reporting_currency.dart';
import '../reports/analysis/report_prose.dart';
import '../sales/sale_history.dart';
import '../sales/sales_report_panel.dart';
import '../suppliers/supplier_card.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_staff_names.dart';
import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tabs.dart';
import '../ui/money_text.dart';
import '../ui/tokens.dart';
import '../observability/app_telemetry.dart';
import 'customer.dart';
import 'customer_card.dart';
import 'customer_credit.dart';
import 'customer_directory_panel.dart';
import 'customer_form.dart';
import 'customer_payment_sheet.dart';

/// One customer's record, as a route.
final class TenantCustomerRecordScreen extends StatefulWidget {
  const TenantCustomerRecordScreen({
    super.key,
    required this.reader,
    required this.customerId,
    this.writer,
    this.salesReader,
    this.currency,
    this.payments,
  });

  final TenantDataReader reader;
  final String customerId;
  final TenantCustomerWriter? writer;
  final TenantSalesHistoryQueryReader? salesReader;

  /// Where *Record a payment* queues one. Absent, the record offers none.
  final CustomerPaymentServices? payments;

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

  Future<void> _recordPayment(
    TenantSession session,
    TenantCustomer customer,
  ) async {
    final payments = widget.payments;
    if (payments == null) return;
    final notice = await showCustomerPaymentDialog(
      context,
      session: session,
      customer: customer,
      services: payments,
      currency: widget.currency ?? '',
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
            currency: widget.currency,
            onRecordPayment:
                widget.payments != null &&
                    TenantCustomerCreditRepository.canTakePaymentInSession(
                      session,
                    )
                ? () => _recordPayment(session, customer)
                : null,
            // Every customer may buy on credit, so every one has an account.
            statement: TenantCustomerStatement(
              key: ValueKey('customer-statement-$_generation'),
              reader: widget.reader,
              session: session,
              customer: customer,
            ),
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
    this.currency,
    this.onRecordPayment,
    this.statement,
  });

  final TenantCustomer customer;
  final Widget purchases;
  final String? currency;
  final VoidCallback? onRecordPayment;
  final Widget? statement;
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
        ...<Widget>[
          SizedBox(height: tokens.spacing.s16),
          _AccountCard(
            customer: customer,
            currency: currency,
            onRecordPayment: onRecordPayment,
          ),
        ],
        SizedBox(height: tokens.spacing.s24),
        _RecordTabs(statement: statement, purchases: purchases),
      ],
    );
  }
}

/// *Statement* and *Purchases*, as two tabs of one record.
///
/// **Tabs rather than two sections, at the developer's direction on
/// 2026-10-02.** They answer different questions - how the account got to its
/// balance, and what the customer bought - and stacked, the second was below a
/// fold on every phone. Both stay alive, so moving between them never reads
/// either again; only the chosen one is laid out.
final class _RecordTabs extends StatelessWidget {
  const _RecordTabs({required this.statement, required this.purchases});

  final Widget? statement;
  final Widget purchases;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) {
          final tabs = DefaultTabController.of(context);
          return AnimatedBuilder(
            animation: tabs,
            builder: (context, _) => Column(
              key: const ValueKey('customer-record-tabs'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const AppTabs(
                  tabs: <String>['Statement', 'Purchases'],
                  isScrollable: false,
                ),
                SizedBox(height: tokens.spacing.s16),
                Visibility(
                  visible: tabs.index == 0,
                  maintainState: true,
                  child: statement ?? const SizedBox.shrink(),
                ),
                Visibility(
                  visible: tabs.index == 1,
                  maintainState: true,
                  child: purchases,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// What the customer owes, against what they may owe, and the way to take a
/// payment.
final class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.customer,
    required this.currency,
    required this.onRecordPayment,
  });

  final TenantCustomer customer;
  final String? currency;
  final VoidCallback? onRecordPayment;

  String _amount(int minor) {
    final text = moneyTextOfMinor(minor);
    final code = currency;
    return code == null || code.isEmpty ? text : '$code $text';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final balance = customer.balanceMinor;
    final limit = customer.creditLimitMinor;
    final since = customer.owingSince;
    return AppCard(
      key: const ValueKey('customer-record-account'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _Headline(
                  caption: balance < 0 ? 'Paid ahead' : 'Owes',
                  value: _amount(balance.abs()),
                  valueKey: const ValueKey('customer-record-balance'),
                  figure: true,
                ),
              ),
              SizedBox(width: tokens.spacing.s12),
              Expanded(
                child: _Headline(
                  caption: limit == null ? 'Credit' : 'Credit limit',
                  value: customer.creditBlocked
                      ? 'Blocked'
                      : limit == null
                      ? 'Allowed'
                      : _amount(limit),
                  valueKey: const ValueKey('customer-record-credit-limit'),
                  figure: limit != null && !customer.creditBlocked,
                  end: true,
                ),
              ),
            ],
          ),
          if (since != null && balance > 0) ...<Widget>[
            SizedBox(height: tokens.spacing.s8),
            Text(
              key: const ValueKey('customer-record-owing-since'),
              'Owing since ${reportShortDate(_isoDate(since))}',
              style: tokens.typography.caption.copyWith(
                color: tokens.colors.text.secondary,
              ),
            ),
          ],
          if (customer.overLimit) ...<Widget>[
            SizedBox(height: tokens.spacing.s12),
            Callout(
              key: const ValueKey('customer-record-over-limit'),
              status: AppStatus.attention,
              title: 'Over their limit',
              message:
                  'They owe ${_amount(balance - (limit ?? 0))} more than the '
                  'limit they were given before limits were withdrawn.',
            ),
          ],
          if (onRecordPayment case final record?) ...<Widget>[
            SizedBox(height: tokens.spacing.s16),
            AppButton(
              key: const ValueKey('customer-record-take-payment'),
              label: 'Record a payment',
              icon: Icons.payments_outlined,
              tier: AppButtonTier.secondary,
              expand: true,
              onPressed: record,
            ),
          ],
        ],
      ),
    );
  }
}

String _isoDate(DateTime at) {
  final local = at.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

/// A customer's statement: every sale on credit, repayment and return that
/// moved what they owe, newest first, each with the balance it left.
final class TenantCustomerStatement extends StatefulWidget {
  const TenantCustomerStatement({
    super.key,
    required this.reader,
    required this.session,
    required this.customer,
  });

  final TenantDataReader reader;
  final TenantSession session;
  final TenantCustomer customer;

  static const int pageSize = 20;

  @override
  State<TenantCustomerStatement> createState() =>
      _TenantCustomerStatementState();
}

final class _TenantCustomerStatementState
    extends State<TenantCustomerStatement> {
  final List<TenantCustomerLedgerEntry> _entries =
      <TenantCustomerLedgerEntry>[];
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
      final page = await TenantCustomerCreditRepository(
        session: widget.session,
        reader: widget.reader,
      ).loadStatement(
        widget.customer.id,
        pageSize: TenantCustomerStatement.pageSize,
        cursor: first ? null : _cursor,
      );
      if (!mounted) return;
      setState(() {
        if (first) _entries.clear();
        _entries.addAll(page.entries);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'customers.statement_read',
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  String _money(int minor) => _currency.format(minor / 100);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      key: const ValueKey('customer-statement'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_failed)
          ErrorState(
            key: const ValueKey('customer-statement-failure'),
            badgeLabel: 'Not read',
            statement: "This customer's account could not be read.",
            stillTrue: 'Nothing has been recorded or changed.',
            actions: <Widget>[
              AppButton(
                key: const ValueKey('customer-statement-retry'),
                label: 'Try again',
                onPressed: () => _load(first: _entries.isEmpty),
              ),
            ],
          )
        else if (_loading && _entries.isEmpty)
          const LoadingState(message: 'Reading their account')
        else ...<Widget>[
          if (_entries.isEmpty)
            const EmptyState(
              key: ValueKey('customer-statement-empty'),
              title: 'Nothing on their account yet',
              hint:
                  'Each sale on credit and each payment back is listed here '
                  'once it reaches the server.',
              illustration: 'file-search.svg',
            )
          else
            for (final (index, entry) in _entries.indexed) ...<Widget>[
              if (index > 0) SizedBox(height: tokens.spacing.s12),
              _StatementRow(
                key: ValueKey('customer-statement-${entry.id}'),
                entry: entry,
                money: _money,
              ),
            ],
          if (_hasMore) ...<Widget>[
            SizedBox(height: tokens.spacing.s12),
            AppButton(
              key: const ValueKey('customer-statement-more'),
              label: 'Show older entries',
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

/// One statement line: what happened, what it did to the balance - in words
/// and with a sign, never by colour alone - and what they owed after.
final class _StatementRow extends StatelessWidget {
  const _StatementRow({super.key, required this.entry, required this.money});

  final TenantCustomerLedgerEntry entry;
  final String Function(int minor) money;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final change = entry.changeMinor;
    final detail = <String>[
      if (entry.at case final at?) reportShortDate(_isoDate(at)),
      if (entry.receiptNumber case final receipt?) 'Receipt $receipt',
      if (entry.tender case final tender?) tender.label,
    ].join(' · ');
    final after = entry.balanceAfterMinor;
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
                    entry.kind.label,
                    style: tokens.typography.titleMedium.copyWith(
                      color: tokens.colors.text.primary,
                    ),
                  ),
                ),
                Text(
                  '${change > 0 ? '+' : '-'} ${money(change.abs())}',
                  key: ValueKey('customer-statement-change-${entry.id}'),
                  style: tokens.typography.numericBody.copyWith(
                    color: tokens.colors.text.money,
                  ),
                ),
              ],
            ),
            if (detail.isNotEmpty) ...<Widget>[
              SizedBox(height: tokens.spacing.s4),
              Text(
                detail,
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
            ],
            SizedBox(height: tokens.spacing.s4),
            Text(
              after < 0
                  ? 'Then ${money(-after)} paid ahead'
                  : 'Then owed ${money(after)}',
              style: tokens.typography.bodyMedium.copyWith(
                color: tokens.colors.text.secondary,
              ),
            ),
            if (entry.overLimit) ...<Widget>[
              SizedBox(height: tokens.spacing.s8),
              const StatusBadge(
                status: AppStatus.attention,
                label: 'Went over their limit',
              ),
            ],
          ],
        ),
      ),
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

  /// Who rang each sale up, by UID, for the card's footer. A name that cannot
  /// be read leaves the UID, as every other sales list does.
  final Map<String, String> _names = <String, String>{};
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
      final page = await TenantSaleHistoryRepository(
        session: widget.session,
        reader: widget.reader,
        reportReader: widget.salesReader,
      ).loadCustomerSales(
        customerId: widget.customer.id,
        pageSize: TenantCustomerPurchases.pageSize,
        cursor: first ? null : _cursor,
      );
      final names = await TenantStaffNameResolver(
        session: widget.session,
        reader: widget.reader,
      ).resolve(page.items.map((sale) => sale.soldById));
      if (!mounted) return;
      setState(() {
        if (first) _sales.clear();
        _names.addAll(names);
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
              // The Sales report's own card, so a sale looks the same here.
              TenantSaleCard(
                key: ValueKey('customer-purchase-${sale.id}'),
                sale: sale,
                staffLabel: tenantStaffLabel(
                  sale.soldById,
                  names: _names,
                  selfUid: widget.session.uid,
                ),
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

