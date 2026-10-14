/// The Production route: every batch made, newest first, and recording the
/// next one.
library;

import 'package:flutter/material.dart';

import '../checkout/checkout_draft.dart';
import '../inventory/product_image_cache.dart';
import '../reporting/reporting_currency.dart';
import '../reports/analysis/production_analysis.dart';
import '../reports/analysis/production_report.dart';
import '../reports/analysis/report_prose.dart';
import '../reports/report_document.dart';
import '../reports/report_file.dart';
import '../reports/report_identity_source.dart';
import '../reports/report_period.dart';
import '../reports/report_run.dart';
import '../reports/ui/report_action.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_session.dart';
import '../ui/money_text.dart';
import '../ui/record_sheet.dart';
import '../ui/buttons.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'production_batch.dart';
import 'production_batch_card.dart';
import 'production_form_panel.dart';
import '../observability/app_telemetry.dart';
import 'production_cost_screen.dart';

/// What the Production route reads first: the newest batches, the currency
/// their costs are stated in, and the sizes of the products they made.
final class TenantProductionView {
  const TenantProductionView({
    required this.page,
    required this.currency,
    this.sizes = const <String, String>{},
  });

  final TenantProductionPage page;
  final TenantReportingCurrency currency;

  /// Each product's size, by ID. See [TenantProductSizes].
  final Map<String, String> sizes;
}

/// The Production route, as the home tile opens it.
final class TenantProductionScreen extends StatefulWidget {
  const TenantProductionScreen({
    super.key,
    required this.reader,
    this.services,
    this.reportSaver,
    this.imageCache,
    this.clock,
  });

  final TenantDataReader reader;

  /// What recording a batch needs. Null renders the history read-only.
  final TenantProductionServices? services;

  /// Where a generated production report goes. Null renders no report control.
  final TenantReportSaver? reportSaver;

  /// Lets a report's branding lockup reuse the logo this device already holds.
  final TenantImageCache? imageCache;

  final DateTime Function()? clock;

  /// How many batches one read shows before *Show older batches*.
  static const int pageSize = 20;

  @override
  State<TenantProductionScreen> createState() => _TenantProductionScreenState();
}

final class _TenantProductionScreenState extends State<TenantProductionScreen> {
  int _generation = 0;
  int? _loadersFor;
  late TenantGuardedLoader<TenantProductionView> _loader;
  TenantGuardedLoader<TenantProductionView>? _loaderCached;

  /// Older batches, read on request below the first page.
  final List<TenantProductionBatch> _older = <TenantProductionBatch>[];
  final Map<String, String> _olderSizes = <String, String>{};
  String? _olderCursor;
  bool? _olderHasMore;
  bool _readingOlder = false;

  void _composeLoaders() {
    if (_loadersFor == _generation) return;
    _loadersFor = _generation;
    TenantGuardedLoader<TenantProductionView> readWith(
      TenantDataReader reader,
    ) => (session) async {
      final page = await TenantProductionRepository(
        session: session,
        reader: reader,
      ).loadBatches(pageSize: TenantProductionScreen.pageSize);
      return TenantProductionView(
        page: page,
        currency: await TenantReportingCurrency.read(
          session: session,
          reader: reader,
        ),
        sizes: await TenantProductSizes(
          session: session,
          reader: reader,
        ).read(page.items.map((batch) => batch.productId)),
      );
    };
    _loader = readWith(widget.reader);
    final cached = widget.reader.cached;
    _loaderCached = cached == null ? null : readWith(cached);
  }

  void _reload() => setState(() {
    _generation++;
    _older.clear();
    _olderSizes.clear();
    _olderCursor = null;
    _olderHasMore = null;
  });

  Future<void> _record() async {
    final services = widget.services;
    if (services == null) return;
    final notice = await openRecordProductionScreen(
      context,
      reader: widget.reader,
      services: services,
    );
    if (!mounted || notice == null) return;
    showAppSnackBar(context, notice);
    _reload();
  }

  Future<void> _readOlder(TenantSession session, String? cursor) async {
    if (cursor == null || _readingOlder) return;
    setState(() => _readingOlder = true);
    try {
      final page = await TenantProductionRepository(
        session: session,
        reader: widget.reader,
      ).loadBatches(pageSize: TenantProductionScreen.pageSize, cursor: cursor);
      final sizes = await TenantProductSizes(
        session: session,
        reader: widget.reader,
      ).read(page.items.map((batch) => batch.productId));
      if (!mounted) return;
      setState(() {
        _older.addAll(page.items);
        _olderSizes.addAll(sizes);
        _olderCursor = page.nextCursor;
        _olderHasMore = page.hasMore;
        _readingOlder = false;
      });
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'production.history_page_read',
      );
      if (!mounted) return;
      setState(() => _readingOlder = false);
      showAppSnackBar(
        context,
        const AppNotice.unknown(
          'The older batches could not be read. Nothing has changed.',
        ),
      );
    }
  }

  DateTime _now() => (widget.clock ?? () => DateTime.now().toUtc())();

  /// The production report, narrowed to one product or covering all of them.
  Widget? _reportAction(TenantSession session) {
    final saver = widget.reportSaver;
    if (saver == null) return null;
    final repository = TenantProductionRepository(
      session: session,
      reader: widget.reader,
    );
    return TenantReportAction(
      clock: _now,
      run: TenantReportRun.withSubject(
        kind: TenantReportKind.production,
        support: TenantReportPeriodSupport.range,
        saver: saver,
        subject: TenantReportSubject(
          label: 'Product',
          allLabel: 'All products',
          loadOptions: () async {
            final made = await repository.loadMadeProducts();
            final sizes = await TenantProductSizes(
              session: session,
              reader: widget.reader,
            ).read(made.map((product) => product.id));
            return <TenantReportSubjectOption>[
              for (final product in made)
                TenantReportSubjectOption(
                  id: product.id,
                  label: tenantProductLabel(product.name, sizes[product.id]),
                ),
            ];
          },
        ),
        buildForSubject: (period, subject) async {
          final read = await TenantProductionReportSource(
            repository: repository,
          ).gather(period, productId: subject?.id);
          final identity = await readTenantReportIdentity(
            session: session,
            reader: widget.reader,
            generatedAt: _now(),
            imageCache: widget.imageCache,
          );
          return describeProductionReport(
            identity: identity,
            analysis: TenantProductionAnalysis.from(
              period: period,
              batches: read.batches,
              sizes: await TenantProductSizes(
                session: session,
                reader: widget.reader,
              ).read(read.batches.map((batch) => batch.productId)),
              subject: subject,
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
    return TenantRouteGuard<TenantProductionView>(
      allowedRoles: TenantProductionRepository.allowedRoles,
      load: _loader,
      loadCached: _loaderCached,
      holdsNothing: (view) => view.page.items.isEmpty,
      loading: const _ProductionFrame(
        child: LoadingState(message: 'Reading production'),
      ),
      failure: (context, error) => const _ProductionFrame(
        child: ErrorState(
          key: ValueKey('production-failure'),
          badgeLabel: 'Not read',
          statement: 'The production batches could not be read.',
          stillTrue: 'Nothing has been recorded or changed.',
        ),
      ),
      builder: (context, session, view) {
        final batches = <TenantProductionBatch>[...view.page.items, ..._older];
        final hasMore = _olderHasMore ?? view.page.hasMore;
        final cursor = _olderHasMore == null
            ? view.page.nextCursor
            : _olderCursor;
        return _ProductionFrame(
          reportAction: _reportAction(session),
          child: _ProductionContents(
            batches: batches,
            sizes: <String, String>{...view.sizes, ..._olderSizes},
            currency: view.currency,
            hasMore: hasMore,
            readingOlder: _readingOlder,
            onRecord: widget.services == null ? null : _record,
            onOlder: () => _readOlder(session, cursor),
          ),
        );
      },
    );
  }
}

final class _ProductionFrame extends StatelessWidget {
  const _ProductionFrame({required this.child, this.reportAction});

  final Widget child;
  final Widget? reportAction;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Production',
    contentWidth: RecordSheet.contentWidth(context),
    actions: <Widget>[if (reportAction != null) reportAction!],
    body: child,
  );
}

final class _ProductionContents extends StatelessWidget {
  const _ProductionContents({
    required this.batches,
    required this.sizes,
    required this.currency,
    required this.hasMore,
    required this.readingOlder,
    required this.onRecord,
    required this.onOlder,
  });

  final List<TenantProductionBatch> batches;
  final Map<String, String> sizes;
  final TenantReportingCurrency currency;
  final bool hasMore;
  final bool readingOlder;
  final VoidCallback? onRecord;
  final VoidCallback onOlder;

  String _money(int minor) => currency.format(minor / 100);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final inset = width < AppLayout.contract.mediumFloor
        ? tokens.spacing.s16
        : width < AppLayout.contract.expandedFloor
        ? tokens.spacing.s20
        : tokens.spacing.s24;
    final table = RecordSheet.drawnAt(width);
    return ListView(
      key: const ValueKey('production'),
      padding: RecordSheet.pagePadding(
        context,
        fallback: EdgeInsets.all(inset),
      ),
      children: <Widget>[
        // On the table's top edge from 1024 instead; see [_sheet].
        if (onRecord case final record? when !table) ...<Widget>[
          AppButton(
            key: const ValueKey('production-record'),
            label: 'Record production',
            icon: Icons.add_circle_outline,
            tier: AppButtonTier.secondary,
            expand: true,
            onPressed: record,
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        if (table)
          _sheet(context, tokens)
        else if (batches.isEmpty)
          _empty
        else
          for (final (index, batch) in batches.indexed) ...<Widget>[
            if (index > 0) SizedBox(height: tokens.spacing.s12),
            TenantProductionBatchCard(
              key: ValueKey('production-row-${batch.id}'),
              batch: batch,
              size: sizes[batch.productId],
              money: _money,
              onOpenCosts: () => openProductionCostScreen(
                context,
                batch: batch,
                money: _money,
                size: sizes[batch.productId],
              ),
            ),
          ],
        if (hasMore) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          AppButton(
            key: const ValueKey('production-older'),
            label: 'Show older batches',
            loading: readingOlder,
            expand: true,
            onPressed: readingOlder ? null : onOlder,
          ),
        ],
      ],
    );
  }

  static const Widget _empty = EmptyState(
    key: ValueKey('production-empty'),
    title: 'No batches yet',
    hint: 'Record a batch to update stock and costs.',
    illustration: 'production.svg',
  );

  void _openCosts(BuildContext context, TenantProductionBatch batch) =>
      openProductionCostScreen(
        context,
        batch: batch,
        money: _money,
        size: sizes[batch.productId],
      );

  /// The large-screen list: one row per batch, *Record production* on its top
  /// edge.
  ///
  /// **The same batches, read the same way, drawn as rows** -
  /// `docs/design/tables/`, at the developer's direction on 2026-10-13. A row
  /// opens the cost of that batch, which is all the card's *View costs* did,
  /// and the costs line up down their columns so a batch that cost more than
  /// the one before is visible at a glance. Below 1024 the cards are unchanged.
  Widget _sheet(BuildContext context, AppTokens tokens) {
    final cents = batches.any(
      (batch) =>
          batch.unitCostMinor % 100 != 0 || batch.totalCostMinor % 100 != 0,
    );
    String? reserve(int minor) => cents && minor % 100 == 0 ? '.00' : null;
    return RecordSheet(
      key: const ValueKey('production-sheet'),
      columns: <SheetColumn>[
        const SheetColumn(label: 'Made', kind: SheetColumnKind.text),
        const SheetColumn(
          label: 'Product and batch',
          kind: SheetColumnKind.identity,
        ),
        const SheetColumn(label: 'Units', kind: SheetColumnKind.figure),
        SheetColumn(
          label: 'Cost per unit',
          kind: SheetColumnKind.figure,
          unit: currency.code,
        ),
        SheetColumn(
          label: 'Total cost',
          kind: SheetColumnKind.figure,
          unit: currency.code,
        ),
      ],
      bar: onRecord == null
          ? null
          : Row(
              children: <Widget>[
                const Spacer(),
                AppButton(
                  key: const ValueKey('production-record'),
                  label: 'Record production',
                  icon: Icons.add_circle_outline,
                  tier: AppButtonTier.secondary,
                  onPressed: onRecord,
                ),
              ],
            ),
      body: batches.isEmpty ? _empty : null,
      rows: <SheetRow>[
        for (final batch in batches)
          SheetRow(
            id: batch.id,
            key: ValueKey('production-row-${batch.id}'),
            // The card's *View costs*, which a row is now in full.
            pressKey: ValueKey('production-costs-${batch.id}'),
            onPressed: () => _openCosts(context, batch),
            semanticLabel: tenantProductLabel(
              batch.productName,
              sizes[batch.productId],
            ),
            semanticHint: 'Opens what this batch cost.',
            cells: <SheetCell?>[
              SheetText(
                batch.occurredAt == null
                    ? 'Date not recorded'
                    : reportShortDate(checkoutBusinessDate(batch.occurredAt!)),
                key: ValueKey('production-made-${batch.id}'),
              ),
              SheetText(
                tenantProductLabel(batch.productName, sizes[batch.productId]),
                caption: batch.batchNumber,
                captionKey: ValueKey('production-number-${batch.id}'),
              ),
              SheetFigure('${batch.quantity}'),
              SheetFigure(
                moneyTextGroupedOfMinor(batch.unitCostMinor),
                reserve: reserve(batch.unitCostMinor),
                key: ValueKey('production-unit-${batch.id}'),
              ),
              SheetFigure(
                moneyTextGroupedOfMinor(batch.totalCostMinor),
                reserve: reserve(batch.totalCostMinor),
                key: ValueKey('production-total-${batch.id}'),
              ),
            ],
          ),
      ],
    );
  }
}
