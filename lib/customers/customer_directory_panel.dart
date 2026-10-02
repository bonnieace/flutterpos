/// The Customers route: who the business sells to, found by name or number,
/// added and corrected, and marked inactive when they stop coming.
///
/// **Searched on the server a page at a time**, unlike suppliers. A shop has
/// tens of suppliers and may have thousands of customers, so the directory is
/// the product search's shape - an indexed prefix, a page, a cursor - rather
/// than a whole collection read and filtered here. This device's copy answers
/// first, so a list opened with no signal shows every customer it has seen.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../checkout/checkout_configuration.dart';
import '../suppliers/supplier_card.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/money_text.dart';
import '../ui/pagination.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import '../observability/app_telemetry.dart';
import 'customer.dart';
import 'customer_card.dart';
import 'customer_credit.dart';
import 'customer_form.dart';
import 'customer_payment_sheet.dart';
import 'customer_record_panel.dart';

/// What one read of the directory answers with.
final class TenantCustomersView {
  const TenantCustomersView({
    required this.page,
    required this.currency,
    this.owedTotalMinor,
  });

  final TenantCustomerPage page;

  /// What everyone listed owes in all, on the *Who owes* view; null on every
  /// other.
  final int? owedTotalMinor;

  /// The business's currency, which decides the dialling code a new customer's
  /// number starts from. Null where it could not be read.
  final String? currency;
}

/// The Customers route, as the home tile opens it.
final class TenantCustomersScreen extends StatefulWidget {
  const TenantCustomersScreen({
    super.key,
    required this.reader,
    this.writer,
    this.salesReader,
    this.payments,
  });

  final TenantDataReader reader;

  /// Where a customer write is queued. Null renders a read-only directory.
  final TenantCustomerWriter? writer;

  /// Where a record's *Record a payment* queues one. Null offers none.
  final CustomerPaymentServices? payments;

  /// What a customer's purchase history is read through. Null reads it through
  /// [reader].
  final TenantSalesHistoryQueryReader? salesReader;

  /// How many customers one page of the list shows.
  static const int pageSize = 20;

  @override
  State<TenantCustomersScreen> createState() => _TenantCustomersScreenState();
}

final class _TenantCustomersScreenState extends State<TenantCustomersScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  TenantCustomerStanding _standing = TenantCustomerStanding.active;
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;

  /// Bumped after every write, which is what makes the guard read again.
  int _generation = 0;
  String? _loaderKey;
  TenantGuardedLoader<TenantCustomersView>? _loader;
  TenantGuardedLoader<TenantCustomersView>? _loaderCached;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// One loader per question, memoised so a rebuild for any other reason does
  /// not read again - see `catalog_management_panel.dart`, whose note this is.
  void _composeLoaders() {
    final key = '$_generation:$_pageIndex:$_query:${_standing.wireValue}';
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    final query = _query;
    final standing = _standing;
    TenantGuardedLoader<TenantCustomersView> readWith(
      TenantDataReader reader, {
      required bool cachedPass,
    }) => (session) async {
      int? owedTotal;
      final TenantCustomerPage page;
      if (standing == TenantCustomerStanding.owing) {
        // **Every debtor, sorted here**, so it is one list rather than pages:
        // see `loadOwing`. A search narrows it by name as the cashier types.
        final term = tenantCustomerSearchTerm(query);
        final owing = (await TenantCustomerCreditRepository(
          session: session,
          reader: reader,
        ).loadOwing()).where(
          (customer) => term.isEmpty ||
              customer.name.toLowerCase().contains(term),
        ).toList();
        owedTotal = owing.fold<int>(0, (sum, c) => sum + c.owedMinor);
        page = TenantCustomerPage(customers: owing, nextCursor: null);
      } else {
        page = await TenantCustomerRepository(
          session: session,
          reader: reader,
        ).search(
          search: query,
          standing: standing,
          pageSize: TenantCustomersScreen.pageSize,
          cursor: cursor,
        );
      }
      // **An empty copy is not an answer.** A device that has never read the
      // directory holds nothing, and drawing "No customers yet" while the
      // server is still answering would be a false empty page. The guard drops
      // a cached failure silently and waits for the server.
      if (cachedPass && page.customers.isEmpty) {
        throw const _NothingHeldOnThisDevice();
      }
      String? currency;
      try {
        currency = (await TenantCheckoutConfigurationRepository(
          session: session,
          reader: reader,
        ).load())?.currency;
      } catch (error, stackTrace) {
        AppTelemetry.captureHandled(
          error,
          stackTrace,
          boundary: 'customers.currency_read',
        );
      }
      return TenantCustomersView(
        page: page,
        currency: currency,
        owedTotalMinor: owedTotal,
      );
    };
    _loader = readWith(widget.reader, cachedPass: false);
    final cached = widget.reader.cached;
    _loaderCached = cached == null ? null : readWith(cached, cachedPass: true);
  }

  void _restart() => setState(() {
    _cursors = <String?>[null];
    _pageIndex = 0;
  });

  void _reload() => setState(() {
    _cursors = <String?>[null];
    _pageIndex = 0;
    _generation++;
  });

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(AppMotion.standard.long.duration, () {
      if (!mounted) return;
      final next = tenantCustomerSearchPrefix(value) == null ? '' : value;
      if (next == _query) return;
      _query = next;
      _restart();
    });
  }

  void _setStanding(TenantCustomerStanding standing) {
    if (standing == _standing) return;
    _standing = standing;
    _restart();
  }

  void _nextPage(String? cursor) {
    if (cursor == null) return;
    setState(() {
      _cursors = <String?>[..._cursors.take(_pageIndex + 1), cursor];
      _pageIndex++;
    });
  }

  Future<void> _openForm(
    TenantSession session,
    String? currency, {
    TenantCustomer? customer,
  }) async {
    final writer = widget.writer;
    if (writer == null) return;
    final outcome = await showCustomerFormSheet(
      context,
      session: session,
      reader: widget.reader,
      writer: writer,
      customer: customer,
      dialCode: dialCodeForCurrency(currency),
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
    String? currency,
  ) async {
    final payments = widget.payments;
    if (payments == null) return;
    final notice = await showCustomerPaymentDialog(
      context,
      session: session,
      customer: customer,
      services: payments,
      currency: currency ?? '',
    );
    if (!mounted || notice == null) return;
    showAppSnackBar(context, notice);
    _reload();
  }

  Future<void> _openRecord(TenantCustomer customer, String? currency) async {
    final controller = TenantSessionScope.of(context);
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: controller,
          child: TenantCustomerRecordScreen(
            reader: widget.reader,
            writer: widget.writer,
            salesReader: widget.salesReader,
            customerId: customer.id,
            currency: currency,
            payments: widget.payments,
          ),
        ),
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    _composeLoaders();
    return TenantRouteGuard<TenantCustomersView>(
      allowedRoles: TenantCustomerRepository.manageRoles,
      load: _loader!,
      loadCached: _loaderCached,
      loading: const _CustomersFrame(
        child: LoadingState(message: 'Reading customers'),
      ),
      failure: (context, error) => const _CustomersFrame(
        child: ErrorState(
          key: ValueKey('customers-failure'),
          badgeLabel: 'Not read',
          statement: 'The customers could not be read.',
          stillTrue: 'Nothing has been recorded or changed.',
        ),
      ),
      builder: (context, session, view) => _CustomersFrame(
        child: _CustomersContents(
          view: view,
          search: _search,
          standing: _standing,
          pageIndex: _pageIndex,
          hasQuery: _query.isNotEmpty || _standing != TenantCustomerStanding.active,
          canWrite: widget.writer != null,
          onSearchChanged: _onSearchChanged,
          onStandingChanged: _setStanding,
          onAdd: widget.writer == null
              ? null
              : () => _openForm(session, view.currency),
          onView: (customer) => _openRecord(customer, view.currency),
          onEdit: widget.writer == null
              ? null
              : (customer) =>
                    _openForm(session, view.currency, customer: customer),
          onSetActive: widget.writer == null
              ? null
              : (customer, active) =>
                    _setActive(session, customer, active: active),
          onRecordPayment:
              widget.payments != null &&
                  TenantCustomerCreditRepository.canTakePaymentInSession(
                    session,
                  )
              ? (customer) => _recordPayment(session, customer, view.currency)
              : null,
          onPrevious: _pageIndex == 0
              ? null
              : () => setState(() => _pageIndex--),
          onNext: () => _nextPage(view.page.nextCursor),
        ),
      ),
    );
  }
}

/// What the cached pass throws when this device holds no customers to show.
///
/// Never shown and never caught by name: the guard drops a cached failure, so
/// this is how an empty copy waits for the server rather than claiming there
/// are no customers.
final class _NothingHeldOnThisDevice implements Exception {
  const _NothingHeldOnThisDevice();
}

/// Marks [customer] inactive - asking first - or offers them again, and answers
/// with the notice to show, or null when the person changed their mind.
Future<AppNotice?> setCustomerStanding(
  BuildContext context, {
  required TenantSession session,
  required TenantDataReader reader,
  required TenantCustomerWriter writer,
  required TenantCustomer customer,
  required bool active,
}) async {
  if (!active) {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Mark ${customer.name} inactive?',
      consequence:
          'They stop being offered at the till and stop getting receipts on '
          'WhatsApp. Every sale to them stays on record, with their points, and '
          'they can be offered again at any time.',
      confirmLabel: 'Mark inactive',
      confirmKey: const ValueKey('customer-inactive-confirm'),
      cancelKey: const ValueKey('customer-inactive-cancel'),
    );
    if (!confirmed) return null;
  }
  try {
    final intent = TenantCustomerRepository(
      session: session,
      reader: reader,
    ).buildStandingIntent(customer: customer, active: active);
    await writer.updateCustomer(intent);
  } on TenantCustomerException catch (error) {
    return AppNotice.refused(customerRefusalMessage(error.code));
  } catch (error, stackTrace) {
    AppTelemetry.captureHandled(
      error,
      stackTrace,
      boundary: 'customers.update',
    );
    return const AppNotice.refused(
      'This change could not be saved on this device, so nothing was '
      'recorded. Try again.',
    );
  }
  return AppNotice.confirmed(
    active
        ? '${customer.name} is offered at the till again.'
        : '${customer.name} is inactive. Their sales stay on record.',
  );
}

final class _CustomersFrame extends StatelessWidget {
  const _CustomersFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Customers',
    subtitle: 'Who buys from you.',
    contentWidth: AppContentWidth.records,
    body: child,
  );
}

final class _CustomersContents extends StatelessWidget {
  const _CustomersContents({
    required this.view,
    required this.search,
    required this.standing,
    required this.pageIndex,
    required this.hasQuery,
    required this.canWrite,
    required this.onSearchChanged,
    required this.onStandingChanged,
    required this.onAdd,
    required this.onView,
    required this.onEdit,
    required this.onSetActive,
    required this.onPrevious,
    required this.onNext,
    this.onRecordPayment,
  });

  final TenantCustomersView view;
  final TextEditingController search;
  final TenantCustomerStanding standing;
  final int pageIndex;
  final bool hasQuery;
  final bool canWrite;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<TenantCustomerStanding> onStandingChanged;
  final VoidCallback? onAdd;
  final ValueChanged<TenantCustomer> onView;
  final ValueChanged<TenantCustomer>? onEdit;
  final void Function(TenantCustomer customer, bool active)? onSetActive;
  final VoidCallback? onPrevious;
  final VoidCallback onNext;

  /// Takes a repayment from one customer, into the caller's own shift.
  final ValueChanged<TenantCustomer>? onRecordPayment;

  List<SupplierMenuAction> _actions(TenantCustomer customer) =>
      <SupplierMenuAction>[
        SupplierMenuAction(
          label: 'View',
          icon: Icons.visibility_outlined,
          itemKey: ValueKey('customer-menu-view-${customer.id}'),
          onSelected: () => onView(customer),
        ),
        if (onEdit case final edit?)
          SupplierMenuAction(
            label: 'Edit',
            icon: Icons.edit_outlined,
            itemKey: ValueKey('customer-edit-${customer.id}'),
            onSelected: () => edit(customer),
          ),
        // Beside the record's own button, for the person standing at the
        // list with the money in their hand.
        if (onRecordPayment case final record?)
          SupplierMenuAction(
            label: 'Record a payment',
            icon: Icons.payments_outlined,
            itemKey: ValueKey('customer-record-payment-${customer.id}'),
            onSelected: () => record(customer),
          ),
        if (onSetActive case final setActive?)
          customer.active
              ? SupplierMenuAction(
                  label: 'Mark inactive',
                  icon: Icons.block_outlined,
                  destructive: true,
                  itemKey: ValueKey('customer-inactive-${customer.id}'),
                  onSelected: () => setActive(customer, false),
                )
              : SupplierMenuAction(
                  label: 'Reactivate',
                  icon: Icons.replay_outlined,
                  itemKey: ValueKey('customer-reactivate-${customer.id}'),
                  onSelected: () => setActive(customer, true),
                ),
      ];

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < AppLayout.contract.mediumFloor;
    final inset = compact
        ? tokens.spacing.s16
        : width < AppLayout.contract.expandedFloor
        ? tokens.spacing.s20
        : tokens.spacing.s24;
    final shown = view.page.customers;
    final lastPage = !view.page.hasMore;

    final searchField = AppTextField(
      key: const ValueKey('customers-search'),
      controller: search,
      label: 'Search customers',
      placeholder: 'Name or number',
      dense: true,
      leading: Icons.search,
      onChanged: onSearchChanged,
    );
    final standingFilter = AppSelect<TenantCustomerStanding>(
      key: const ValueKey('customers-standing-filter'),
      value: standing,
      label: 'Show',
      dense: true,
      leading: Icons.filter_alt_outlined,
      items: <AppSelectItem<TenantCustomerStanding>>[
        for (final option in TenantCustomerStanding.values)
          AppSelectItem<TenantCustomerStanding>(
            key: ValueKey('customers-standing-${option.wireValue}'),
            value: option,
            label: option.label,
          ),
      ],
      onChanged: (value) {
        if (value != null) onStandingChanged(value);
      },
    );

    return PagedListView(
      listKey: const ValueKey('customers'),
      padding: EdgeInsets.all(inset),
      pagination: Pagination(
        pageNumber: pageIndex + 1,
        previousKey: const ValueKey('customers-previous-page'),
        nextKey: const ValueKey('customers-next-page'),
        pageKey: const ValueKey('customers-page'),
        onPrevious: onPrevious,
        onNext: lastPage ? null : onNext,
        endOfList: lastPage,
      ),
      children: <Widget>[
        if (onAdd case final add?) ...<Widget>[
          AppButton(
            key: const ValueKey('customers-add'),
            label: 'Add customer',
            icon: Icons.person_add_alt_outlined,
            tier: AppButtonTier.secondary,
            expand: true,
            onPressed: add,
          ),
          SizedBox(height: tokens.spacing.s12),
        ],
        if (!canWrite) ...<Widget>[
          const Callout(
            key: ValueKey('customers-read-only'),
            status: AppStatus.info,
            message:
                'This build cannot change customers, so the list is read-only '
                'here.',
          ),
          SizedBox(height: tokens.spacing.s12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: searchField),
            SizedBox(
              width: compact ? tokens.spacing.s8 : tokens.spacing.s12,
            ),
            Expanded(child: standingFilter),
          ],
        ),
        SizedBox(height: tokens.spacing.s16),
        if (view.owedTotalMinor case final owed? when shown.isNotEmpty)
          ...<Widget>[
            Callout(
              key: const ValueKey('customers-owed-total'),
              status: AppStatus.info,
              message:
                  '${shown.length == 1 ? '1 customer owes' : '${shown.length} customers owe'} '
                  '${view.currency == null ? '' : '${view.currency} '}'
                  '${moneyTextOfMinor(owed)} in all. Biggest first.',
            ),
            SizedBox(height: tokens.spacing.s16),
          ],
        if (shown.isEmpty && standing == TenantCustomerStanding.owing)
          const EmptyState(
            key: ValueKey('customers-nobody-owes'),
            title: 'Nobody owes you anything',
            hint:
                'Customers who buy on credit are listed here, biggest debt '
                'first, until they have paid it back.',
            illustration: 'file-search.svg',
          )
        else if (shown.isEmpty)
          EmptyState(
            key: ValueKey(hasQuery ? 'customers-no-matches' : 'customers-empty'),
            title: hasQuery ? 'No matching customers' : 'No customers yet',
            hint: hasQuery
                ? 'Try another name or number, or show every customer.'
                : 'Add the people who buy from you, here or at the till, so a '
                      'sale can say who it was for and send them their '
                      'receipt.',
            illustration: hasQuery ? 'file-search.svg' : 'logistics.svg',
          )
        else
          for (final (index, customer) in shown.indexed) ...<Widget>[
            if (index > 0) SizedBox(height: tokens.spacing.s12),
            TenantCustomerCard(
              key: ValueKey('customer-row-${customer.id}'),
              customer: customer,
              onOpen: () => onView(customer),
              actions: _actions(customer),
            ),
          ],
      ],
    );
  }
}
