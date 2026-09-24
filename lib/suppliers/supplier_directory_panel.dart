/// The Suppliers route: who stock is bought from, found by name, added and
/// corrected, and marked inactive when a business stops buying from them.
///
/// **The whole directory is read and then filtered here**, rather than paged
/// from the server. The duplicate-name check is a question about every
/// supplier, the server asks it against at most [maximumSupplierDirectory], and
/// the directory is read to the same bound - so what a person searches is
/// exactly what the check compares against, and search works offline.
library;

import 'package:flutter/material.dart';

import '../checkout/checkout_draft.dart';
import '../reports/analysis/report_prose.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/pagination.dart';
import '../ui/record_list.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'supplier.dart';
import 'supplier_delivery_panel.dart';
import 'supplier_form.dart';
import 'supplier_record_panel.dart';

/// Builds the one extra control a surface outside this folder adds to the
/// directory's toolbar - the report - without this folder importing it.
typedef TenantSupplierDirectoryAction =
    Widget? Function(
      BuildContext context,
      TenantSession session,
      TenantSupplierDirectory directory,
    );

/// The Suppliers route, as the home tile opens it.
final class TenantSuppliersScreen extends StatefulWidget {
  const TenantSuppliersScreen({
    super.key,
    required this.reader,
    this.writer,
    this.deliveries,
    this.reportAction,
  });

  final TenantDataReader reader;

  /// Where a supplier write is queued. Null renders a read-only directory.
  final TenantSupplierWriter? writer;

  /// What receiving a delivery needs. Null offers no *Receive delivery*.
  final TenantSupplierDeliveryServices? deliveries;

  /// The toolbar's report control, when the build carries one.
  final TenantSupplierDirectoryAction? reportAction;

  @override
  State<TenantSuppliersScreen> createState() => _TenantSuppliersScreenState();
}

final class _TenantSuppliersScreenState extends State<TenantSuppliersScreen> {
  final TextEditingController _search = TextEditingController();
  TenantSupplierStanding _standing = TenantSupplierStanding.active;
  int _pageIndex = 0;

  /// Bumped after every write, which is what makes the guard read again. The
  /// loaders are rebuilt only then, because the guard re-reads whenever its
  /// loader changes identity - a search keystroke must not.
  int _generation = 0;
  int? _loadersFor;
  late TenantGuardedLoader<TenantSupplierDirectory> _loader;
  TenantGuardedLoader<TenantSupplierDirectory>? _loaderCached;

  /// How many suppliers one page of the list shows.
  static const int pageSize = 20;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _composeLoaders() {
    if (_loadersFor == _generation) return;
    _loadersFor = _generation;
    final reader = widget.reader;
    _loader = (session) =>
        TenantSupplierRepository(session: session, reader: reader)
            .loadDirectory();
    final cached = reader.cached;
    _loaderCached = cached == null
        ? null
        : (session) => TenantSupplierRepository(session: session, reader: cached)
              .loadDirectory();
  }

  void _reload() => setState(() => _generation++);

  void _setStanding(TenantSupplierStanding standing) => setState(() {
    _standing = standing;
    _pageIndex = 0;
  });

  Future<void> _openForm(
    TenantSession session,
    TenantSupplierDirectory directory, {
    TenantSupplier? supplier,
  }) async {
    final writer = widget.writer;
    if (writer == null) return;
    final notice = await showSupplierFormSheet(
      context,
      session: session,
      repository: TenantSupplierRepository(session: session, reader: widget.reader),
      writer: writer,
      directory: directory,
      supplier: supplier,
    );
    if (!mounted || notice == null) return;
    showAppSnackBar(context, notice);
    _reload();
  }

  Future<void> _setActive(
    TenantSession session,
    TenantSupplier supplier, {
    required bool active,
  }) async {
    final writer = widget.writer;
    if (writer == null) return;
    final notice = await setSupplierStanding(
      context,
      session: session,
      reader: widget.reader,
      writer: writer,
      supplier: supplier,
      active: active,
    );
    if (!mounted || notice == null) return;
    showAppSnackBar(context, notice);
    _reload();
  }

  Future<void> _openRecord(TenantSupplier supplier) async {
    final controller = TenantSessionScope.of(context);
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: controller,
          child: TenantSupplierRecordScreen(
            reader: widget.reader,
            writer: widget.writer,
            deliveries: widget.deliveries,
            supplierId: supplier.id,
          ),
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _receive() async {
    final deliveries = widget.deliveries;
    if (deliveries == null) return;
    final notice = await openReceiveDeliveryScreen(
      context,
      reader: widget.reader,
      services: deliveries,
      supplierWriter: widget.writer,
    );
    if (!mounted || notice == null) return;
    showAppSnackBar(context, notice);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    _composeLoaders();
    return TenantRouteGuard<TenantSupplierDirectory>(
      allowedRoles: TenantSupplierRepository.allowedRoles,
      load: _loader,
      loadCached: _loaderCached,
      loading: const _SuppliersFrame(
        child: LoadingState(message: 'Reading suppliers'),
      ),
      failure: (context, error) => const _SuppliersFrame(
        child: ErrorState(
          key: ValueKey('suppliers-failure'),
          badgeLabel: 'Not read',
          statement: 'The suppliers could not be read.',
          stillTrue: 'Nothing has been recorded or changed.',
        ),
      ),
      builder: (context, session, directory) => _SuppliersFrame(
        reportAction: widget.reportAction?.call(context, session, directory),
        child: _SuppliersContents(
          directory: directory,
          search: _search,
          standing: _standing,
          pageIndex: _pageIndex,
          canWrite: widget.writer != null,
          primaryAction: widget.deliveries == null
              ? null
              : AppButton(
                  key: const ValueKey('suppliers-receive'),
                  label: 'Receive delivery',
                  icon: Icons.local_shipping_outlined,
                  tier: AppButtonTier.primary,
                  expand: true,
                  onPressed: _receive,
                ),
          onSearchChanged: () => setState(() => _pageIndex = 0),
          onStandingChanged: _setStanding,
          onAdd: widget.writer == null
              ? null
              : () => _openForm(session, directory),
          onView: _openRecord,
          onEdit: widget.writer == null
              ? null
              : (supplier) => _openForm(session, directory, supplier: supplier),
          onSetActive: widget.writer == null
              ? null
              : (supplier, active) =>
                    _setActive(session, supplier, active: active),
          onPrevious: _pageIndex == 0
              ? null
              : () => setState(() => _pageIndex--),
          onNext: () => setState(() => _pageIndex++),
        ),
      ),
    );
  }
}

/// Marks [supplier] inactive - asking first - or offers it again, and answers
/// with the notice to show, or null when the person changed their mind.
///
/// Shared by the directory and a supplier's own record, so the question and the
/// sentence afterwards are the same wherever it is asked.
Future<AppNotice?> setSupplierStanding(
  BuildContext context, {
  required TenantSession session,
  required TenantDataReader reader,
  required TenantSupplierWriter writer,
  required TenantSupplier supplier,
  required bool active,
}) async {
  if (!active) {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Mark ${supplier.name} inactive?',
      consequence:
          'It stops being offered when a delivery is received. Every delivery '
          'already recorded against it stays on record, and it can be offered '
          'again at any time.',
      confirmLabel: 'Mark inactive',
      confirmKey: const ValueKey('supplier-inactive-confirm'),
      cancelKey: const ValueKey('supplier-inactive-cancel'),
    );
    if (!confirmed) return null;
  }
  try {
    final intent = TenantSupplierRepository(
      session: session,
      reader: reader,
    ).buildStandingIntent(supplier: supplier, active: active);
    await writer.updateSupplier(intent);
  } on TenantSupplierException catch (error) {
    return AppNotice.refused(supplierRefusalMessage(error.code));
  } catch (_) {
    return const AppNotice.refused(
      'This change could not be saved on this device, so nothing was '
      'recorded. Try again.',
    );
  }
  return AppNotice.confirmed(
    active
        ? '${supplier.name} is offered again when a delivery is received.'
        : '${supplier.name} is inactive. Its deliveries stay on record.',
  );
}

/// When a delivery was last recorded, in the shop's own day: `22 Sep`.
String supplierLastDeliveryLabel(TenantSupplier supplier) {
  final at = supplier.lastDeliveryAt;
  if (at == null) return 'None yet';
  return reportShortDate(checkoutBusinessDate(at.toUtc()));
}

final class _SuppliersFrame extends StatelessWidget {
  const _SuppliersFrame({required this.child, this.reportAction});

  final Widget child;
  final Widget? reportAction;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Suppliers',
    subtitle: 'Who stock is bought from.',
    contentWidth: AppContentWidth.records,
    actions: <Widget>[if (reportAction != null) reportAction!],
    body: child,
  );
}

final class _SuppliersContents extends StatelessWidget {
  const _SuppliersContents({
    required this.directory,
    required this.search,
    required this.standing,
    required this.pageIndex,
    required this.canWrite,
    required this.primaryAction,
    required this.onSearchChanged,
    required this.onStandingChanged,
    required this.onAdd,
    required this.onView,
    required this.onEdit,
    required this.onSetActive,
    required this.onPrevious,
    required this.onNext,
  });

  final TenantSupplierDirectory directory;
  final TextEditingController search;
  final TenantSupplierStanding standing;
  final int pageIndex;
  final bool canWrite;
  final Widget? primaryAction;
  final VoidCallback onSearchChanged;
  final ValueChanged<TenantSupplierStanding> onStandingChanged;
  final VoidCallback? onAdd;
  final ValueChanged<TenantSupplier> onView;
  final ValueChanged<TenantSupplier>? onEdit;
  final void Function(TenantSupplier supplier, bool active)? onSetActive;
  final VoidCallback? onPrevious;
  final VoidCallback onNext;

  bool get _hasQuery =>
      search.text.trim().isNotEmpty ||
      standing != TenantSupplierStanding.active;

  List<RecordAction> _actions(TenantSupplier supplier) => <RecordAction>[
    RecordAction(
      label: 'View',
      icon: Icons.visibility_outlined,
      actionKey: ValueKey('supplier-view-${supplier.id}'),
      onPressed: () => onView(supplier),
    ),
    if (onEdit case final edit?)
      RecordAction(
        label: 'Edit',
        icon: Icons.edit_outlined,
        actionKey: ValueKey('supplier-edit-${supplier.id}'),
        onPressed: () => edit(supplier),
      ),
    if (onSetActive case final setActive?)
      supplier.active
          ? RecordAction(
              label: 'Mark inactive',
              icon: Icons.block_outlined,
              destructive: true,
              actionKey: ValueKey('supplier-inactive-${supplier.id}'),
              onPressed: () => setActive(supplier, false),
            )
          : RecordAction(
              label: 'Reactivate',
              icon: Icons.replay_outlined,
              actionKey: ValueKey('supplier-reactivate-${supplier.id}'),
              onPressed: () => setActive(supplier, true),
            ),
  ];

  RecordItem _record(TenantSupplier supplier) => RecordItem(
    id: supplier.id,
    recordKey: ValueKey('supplier-row-${supplier.id}'),
    title: supplier.name,
    titleKey: ValueKey('supplier-name-${supplier.id}'),
    subtitle: supplier.phone ?? supplier.email,
    // **Only the exception wears a badge.** An active supplier is the
    // ordinary case, and a list where every row is badged has no signal in it.
    status: supplier.active
        ? null
        : RecordStatus(
            status: AppStatus.neutral,
            label: 'Inactive',
            badgeKey: ValueKey('supplier-inactive-badge-${supplier.id}'),
          ),
    attributes: <RecordAttribute>[
      RecordAttribute(
        label: 'Last delivery',
        value: supplierLastDeliveryLabel(supplier),
        valueKey: ValueKey('supplier-last-delivery-${supplier.id}'),
      ),
    ],
    actions: _actions(supplier),
  );

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
    final matching = directory.filtered(
      standing: standing,
      search: search.text,
    );
    final pageCount = matching.isEmpty
        ? 1
        : (matching.length / _TenantSuppliersScreenState.pageSize).ceil();
    final page = pageIndex.clamp(0, pageCount - 1);
    final shown = matching
        .skip(page * _TenantSuppliersScreenState.pageSize)
        .take(_TenantSuppliersScreenState.pageSize)
        .toList(growable: false);
    final lastPage = page >= pageCount - 1;

    final searchField = AppTextField(
      key: const ValueKey('suppliers-search'),
      controller: search,
      label: 'Search suppliers',
      placeholder: 'Search by name',
      dense: true,
      leading: Icons.search,
      onChanged: (_) => onSearchChanged(),
    );
    final standingFilter = AppSelect<TenantSupplierStanding>(
      key: const ValueKey('suppliers-standing-filter'),
      value: standing,
      label: 'Show',
      dense: true,
      leading: Icons.filter_alt_outlined,
      items: <AppSelectItem<TenantSupplierStanding>>[
        for (final option in TenantSupplierStanding.values)
          AppSelectItem<TenantSupplierStanding>(
            key: ValueKey('suppliers-standing-${option.wireValue}'),
            value: option,
            label: option.label,
          ),
      ],
      onChanged: (value) {
        if (value != null) onStandingChanged(value);
      },
    );

    return PagedListView(
      listKey: const ValueKey('suppliers'),
      padding: EdgeInsets.all(inset),
      pagination: Pagination(
        pageNumber: page + 1,
        previousKey: const ValueKey('suppliers-previous-page'),
        nextKey: const ValueKey('suppliers-next-page'),
        pageKey: const ValueKey('suppliers-page'),
        onPrevious: page == 0 ? null : onPrevious,
        onNext: lastPage ? null : onNext,
        endOfList: lastPage,
      ),
      children: <Widget>[
        if (primaryAction case final action?) ...<Widget>[
          action,
          SizedBox(height: tokens.spacing.s12),
        ],
        if (onAdd case final add?) ...<Widget>[
          AppButton(
            key: const ValueKey('suppliers-add'),
            label: 'Add supplier',
            icon: Icons.add_business_outlined,
            tier: AppButtonTier.secondary,
            expand: true,
            onPressed: add,
          ),
          SizedBox(height: tokens.spacing.s12),
        ],
        if (!canWrite) ...<Widget>[
          const Callout(
            key: ValueKey('suppliers-read-only'),
            status: AppStatus.info,
            message: 'This build cannot change suppliers, so the list is '
                'read-only here.',
          ),
          SizedBox(height: tokens.spacing.s12),
        ],
        if (directory.truncated) ...<Widget>[
          const Callout(
            key: ValueKey('suppliers-truncated'),
            status: AppStatus.attention,
            message:
                'This business holds more than $maximumSupplierDirectory '
                'suppliers, which is more than any screen here reads. Some are '
                'not listed, and a new name cannot be checked against them.',
          ),
          SizedBox(height: tokens.spacing.s12),
        ],
        if (compact)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: searchField),
              SizedBox(width: tokens.spacing.s8),
              Expanded(child: standingFilter),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: searchField),
              SizedBox(width: tokens.spacing.s12),
              Expanded(child: standingFilter),
            ],
          ),
        SizedBox(height: tokens.spacing.s16),
        RecordList(
          identityLabel: 'Supplier',
          items: <RecordItem>[for (final supplier in shown) _record(supplier)],
          empty: EmptyState(
            key: ValueKey(_hasQuery ? 'suppliers-no-matches' : 'suppliers-empty'),
            title: _hasQuery ? 'No matching suppliers' : 'No suppliers yet',
            hint: _hasQuery
                ? 'Try another name, or show every supplier.'
                : 'Add the businesses you buy stock from, so each delivery can '
                      'say where it came from.',
            illustration: _hasQuery ? 'file-search.svg' : 'logistics.svg',
          ),
        ),
      ],
    );
  }
}
