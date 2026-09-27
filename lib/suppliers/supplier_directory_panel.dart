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
import '../inventory/product_image_cache.dart';
import '../reports/analysis/report_prose.dart';
import '../reports/analysis/supplier_analysis.dart';
import '../reports/analysis/supplier_report.dart';
import '../reports/report_document.dart';
import '../reports/report_file.dart';
import '../reports/report_identity_source.dart';
import '../reports/report_period.dart';
import '../reports/report_run.dart';
import '../reports/ui/report_action.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/pagination.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'supplier.dart';
import 'supplier_card.dart';
import 'supplier_delivery.dart';
import 'supplier_delivery_panel.dart';
import 'supplier_form.dart';
import 'supplier_record_panel.dart';
import '../observability/app_telemetry.dart';

/// The Suppliers route, as the home tile opens it.
final class TenantSuppliersScreen extends StatefulWidget {
  const TenantSuppliersScreen({
    super.key,
    required this.reader,
    this.writer,
    this.deliveries,
    this.reportSaver,
    this.imageCache,
    this.clock,
  });

  final TenantDataReader reader;

  /// Where a supplier write is queued. Null renders a read-only directory.
  final TenantSupplierWriter? writer;

  /// What receiving a delivery needs. Null offers no *Receive delivery*.
  final TenantSupplierDeliveryServices? deliveries;

  /// Where a generated supplier report goes. Null renders no report control.
  final TenantReportSaver? reportSaver;

  /// Lets a report's branding lockup reuse the logo this device already holds.
  final TenantImageCache? imageCache;

  /// Injected so a test and a report generated at midnight agree about which
  /// business day it is.
  final DateTime Function()? clock;

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
    _loader = (session) => TenantSupplierRepository(
      session: session,
      reader: reader,
    ).loadDirectory();
    final cached = reader.cached;
    _loaderCached = cached == null
        ? null
        : (session) => TenantSupplierRepository(
            session: session,
            reader: cached,
          ).loadDirectory();
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
      repository: TenantSupplierRepository(
        session: session,
        reader: widget.reader,
      ),
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

  /// Receives a delivery, from [supplier] when a card's menu names one.
  Future<void> _receive([TenantSupplier? supplier]) async {
    final deliveries = widget.deliveries;
    if (deliveries == null) return;
    final notice = await openReceiveDeliveryScreen(
      context,
      reader: widget.reader,
      services: deliveries,
      supplierWriter: widget.writer,
      supplierId: supplier?.id,
    );
    if (!mounted || notice == null) return;
    showAppSnackBar(context, notice);
    _reload();
  }

  DateTime _now() => (widget.clock ?? () => DateTime.now().toUtc())();

  /// The supplier report, narrowed to one supplier or covering all of them.
  ///
  /// **The chooser lists the directory already read**, active suppliers first
  /// and inactive ones after them, labelled - a period can include deliveries
  /// from a supplier that has since been marked inactive, and leaving it out
  /// would make that period's report impossible to produce.
  Widget? _reportAction(
    TenantSession session,
    TenantSupplierDirectory directory,
  ) {
    final saver = widget.reportSaver;
    if (saver == null) return null;
    return TenantReportAction(
      clock: _now,
      run: TenantReportRun.withSubject(
        kind: TenantReportKind.suppliers,
        support: TenantReportPeriodSupport.range,
        saver: saver,
        subject: TenantReportSubject(
          label: 'Supplier',
          allLabel: 'All suppliers',
          loadOptions: () async => <TenantReportSubjectOption>[
            for (final supplier in <TenantSupplier>[
              ...directory.suppliers.where((supplier) => supplier.active),
              ...directory.suppliers.where((supplier) => !supplier.active),
            ])
              TenantReportSubjectOption(
                id: supplier.id,
                label: supplier.name,
                note: supplier.active ? null : 'inactive',
              ),
          ],
        ),
        buildForSubject: (period, subject) async {
          final read = await TenantSupplierReportSource(
            repository: TenantSupplierDeliveryRepository(
              session: session,
              reader: widget.reader,
            ),
          ).gather(period, supplierId: subject?.id);
          final identity = await readTenantReportIdentity(
            session: session,
            reader: widget.reader,
            generatedAt: _now(),
            imageCache: widget.imageCache,
          );
          return describeSupplierReport(
            identity: identity,
            analysis: TenantSupplierAnalysis.from(
              period: period,
              deliveries: read.deliveries,
              subject: subject,
              restocksWithoutSupplier: read.restocks,
              restocksTruncated: read.restocksTruncated,
              truncated: read.truncated,
              reachedTo: read.reachedTo,
              recordsRead: read.read,
            ),
          );
        },
      ),
    );
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
        reportAction: _reportAction(session, directory),
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
                  tier: AppButtonTier.secondary,
                  expand: true,
                  onPressed: () => _receive(),
                ),
          onSearchChanged: () => setState(() => _pageIndex = 0),
          onStandingChanged: _setStanding,
          onAdd: widget.writer == null
              ? null
              : () => _openForm(session, directory),
          onView: _openRecord,
          onReceive: widget.deliveries == null ? null : _receive,
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
  } catch (error, stackTrace) {
    AppTelemetry.captureHandled(
      error,
      stackTrace,
      boundary: 'suppliers.update',
    );
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
    required this.onReceive,
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

  /// Null offers no *Receive delivery*, as on the page's own action.
  final ValueChanged<TenantSupplier>? onReceive;
  final ValueChanged<TenantSupplier>? onEdit;
  final void Function(TenantSupplier supplier, bool active)? onSetActive;
  final VoidCallback? onPrevious;
  final VoidCallback onNext;

  bool get _hasQuery =>
      search.text.trim().isNotEmpty ||
      standing != TenantSupplierStanding.active;

  /// *View* and *Receive delivery* lead, at the developer's direction on
  /// 2026-09-27. The whole card still opens the record; the menu names it too.
  /// Receiving is offered only for an active supplier, as the record does.
  List<SupplierMenuAction> _actions(TenantSupplier supplier) =>
      <SupplierMenuAction>[
        SupplierMenuAction(
          label: 'View',
          icon: Icons.visibility_outlined,
          itemKey: ValueKey('supplier-menu-view-${supplier.id}'),
          onSelected: () => onView(supplier),
        ),
        if (onReceive case final receive? when supplier.active)
          SupplierMenuAction(
            label: 'Receive delivery',
            icon: Icons.local_shipping_outlined,
            itemKey: ValueKey('supplier-receive-${supplier.id}'),
            onSelected: () => receive(supplier),
          ),
        if (onEdit case final edit?)
          SupplierMenuAction(
            label: 'Edit',
            icon: Icons.edit_outlined,
            itemKey: ValueKey('supplier-edit-${supplier.id}'),
            onSelected: () => edit(supplier),
          ),
        if (onSetActive case final setActive?)
          supplier.active
              ? SupplierMenuAction(
                  label: 'Mark inactive',
                  icon: Icons.block_outlined,
                  destructive: true,
                  itemKey: ValueKey('supplier-inactive-${supplier.id}'),
                  onSelected: () => setActive(supplier, false),
                )
              : SupplierMenuAction(
                  label: 'Reactivate',
                  icon: Icons.replay_outlined,
                  itemKey: ValueKey('supplier-reactivate-${supplier.id}'),
                  onSelected: () => setActive(supplier, true),
                ),
      ];

  Widget _card(TenantSupplier supplier) => TenantSupplierCard(
    key: ValueKey('supplier-row-${supplier.id}'),
    supplier: supplier,
    lastDeliveryLabel: supplierLastDeliveryLabel(supplier),
    onOpen: () => onView(supplier),
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
      // One word: the field is half a phone wide beside the filter.
      placeholder: 'Search',
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
            message:
                'This build cannot change suppliers, so the list is '
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
        if (directory.suppliers.isNotEmpty) ...<Widget>[
          // Inset by the focus ring's gutter, which every button and card on
          // this page reserves around itself, so the four edges line up.
          Padding(
            padding: EdgeInsets.all(
              tokens.colors.action.focusRing.width +
                  tokens.colors.action.focusRing.offset,
            ),
            child: _DirectorySummary(directory: directory),
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        if (shown.isEmpty)
          EmptyState(
            key: ValueKey(
              _hasQuery ? 'suppliers-no-matches' : 'suppliers-empty',
            ),
            title: _hasQuery ? 'No matching suppliers' : 'No suppliers yet',
            hint: _hasQuery
                ? 'Try another name, or show every supplier.'
                : 'Add the businesses you buy stock from, so each delivery can '
                      'say where it came from.',
            illustration: _hasQuery ? 'file-search.svg' : 'logistics.svg',
          )
        else
          for (final (index, supplier) in shown.indexed) ...<Widget>[
            if (index > 0) SizedBox(height: tokens.spacing.s12),
            _card(supplier),
          ],
      ],
    );
  }
}

/// The directory's headline, drawn the way the sales report leads with its
/// takings: a mark, the figure the screen is about, and the one beside it.
///
/// **Counted over the whole directory, not the filtered page**, so the figures
/// do not move while somebody types a name - the list below narrows and this
/// keeps describing the business. Nothing here is read that the list has not
/// already read.
final class _DirectorySummary extends StatelessWidget {
  const _DirectorySummary({required this.directory});

  final TenantSupplierDirectory directory;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final active = directory.suppliers.where((supplier) => supplier.active);
    final inactive = directory.suppliers.length - active.length;
    TenantSupplier? latest;
    for (final supplier in directory.suppliers) {
      final at = supplier.lastDeliveryAt;
      if (at == null) continue;
      if (latest == null || at.isAfter(latest.lastDeliveryAt!)) {
        latest = supplier;
      }
    }
    return AppCard(
      key: const ValueKey('suppliers-summary'),
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
                Icons.storefront_outlined,
                size: tokens.spacing.s24,
                color: tokens.colors.action.primary.container,
              ),
            ),
          ),
          SizedBox(width: tokens.spacing.s12),
          Expanded(
            child: _SummaryFigure(
              caption: 'Active suppliers',
              value: '${active.length}',
              valueKey: const ValueKey('suppliers-summary-active'),
              detail: inactive == 0 ? 'None inactive' : '$inactive inactive',
            ),
          ),
          SizedBox(width: tokens.spacing.s12),
          Expanded(
            child: _SummaryFigure(
              caption: 'Last delivery',
              value: latest == null
                  ? 'None yet'
                  : supplierLastDeliveryLabel(latest),
              valueKey: const ValueKey('suppliers-summary-last-delivery'),
              detail: latest?.name,
              end: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// One headline figure: `label.md` over `numeric.hero` over `caption`.
final class _SummaryFigure extends StatelessWidget {
  const _SummaryFigure({
    required this.caption,
    required this.value,
    required this.valueKey,
    this.detail,
    this.end = false,
  });

  final String caption;
  final String value;
  final Key valueKey;
  final String? detail;

  /// Whether the figure sits against the card's far edge.
  final bool end;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final align = end ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.typography.labelMedium.copyWith(
            color: tokens.colors.text.secondary,
          ),
        ),
        SizedBox(height: tokens.spacing.s4),
        // A figure that does not fit is drawn smaller, never cut: a truncated
        // date is a wrong date.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: end
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: Text(
            value,
            key: valueKey,
            maxLines: 1,
            style: tokens.typography.numericHero.copyWith(
              color: tokens.colors.text.primary,
            ),
          ),
        ),
        if (detail case final line?) ...<Widget>[
          SizedBox(height: tokens.spacing.s4),
          Text(
            line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: end ? TextAlign.end : TextAlign.start,
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        ],
      ],
    );
  }
}
