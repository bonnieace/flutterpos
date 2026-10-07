/// The Production route: every batch made, newest first, and recording the
/// next one.
library;

import 'package:flutter/material.dart';

import '../inventory/product_image_cache.dart';
import '../reporting/reporting_currency.dart';
import '../reports/analysis/production_analysis.dart';
import '../reports/analysis/production_report.dart';
import '../reports/report_document.dart';
import '../reports/report_file.dart';
import '../reports/report_identity_source.dart';
import '../reports/report_period.dart';
import '../reports/report_run.dart';
import '../reports/ui/report_action.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
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

/// What the Production route reads first: the newest batches, and the
/// currency their costs are stated in.
final class TenantProductionView {
  const TenantProductionView({required this.page, required this.currency});

  final TenantProductionPage page;
  final TenantReportingCurrency currency;
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
  String? _olderCursor;
  bool? _olderHasMore;
  bool _readingOlder = false;

  void _composeLoaders() {
    if (_loadersFor == _generation) return;
    _loadersFor = _generation;
    TenantGuardedLoader<TenantProductionView> readWith(
      TenantDataReader reader,
    ) =>
        (session) async => TenantProductionView(
          page: await TenantProductionRepository(
            session: session,
            reader: reader,
          ).loadBatches(pageSize: TenantProductionScreen.pageSize),
          currency: await TenantReportingCurrency.read(
            session: session,
            reader: reader,
          ),
        );
    _loader = readWith(widget.reader);
    final cached = widget.reader.cached;
    _loaderCached = cached == null ? null : readWith(cached);
  }

  void _reload() => setState(() {
    _generation++;
    _older.clear();
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
      if (!mounted) return;
      setState(() {
        _older.addAll(page.items);
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

  /// The production report, narrowed to one product made here or covering all
  /// of them.
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
          loadOptions: () async => <TenantReportSubjectOption>[
            for (final product in await repository.loadMadeHereProducts())
              TenantReportSubjectOption(
                id: product.id,
                label: product.name,
                note: product.retired ? 'retired' : null,
              ),
          ],
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
    subtitle: 'What was made, and what it cost.',
    contentWidth: AppContentWidth.records,
    actions: <Widget>[if (reportAction != null) reportAction!],
    body: child,
  );
}

final class _ProductionContents extends StatelessWidget {
  const _ProductionContents({
    required this.batches,
    required this.currency,
    required this.hasMore,
    required this.readingOlder,
    required this.onRecord,
    required this.onOlder,
  });

  final List<TenantProductionBatch> batches;
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
    return ListView(
      key: const ValueKey('production'),
      padding: EdgeInsets.all(inset),
      children: <Widget>[
        if (onRecord case final record?) ...<Widget>[
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
        if (batches.isEmpty)
          const EmptyState(
            key: ValueKey('production-empty'),
            title: 'No batches yet',
            hint:
                'Record what was made and what it cost, and its stock and its '
                'cost follow. Mark a product as Produced in Inventory first.',
            illustration: 'approve.svg',
          )
        else
          for (final (index, batch) in batches.indexed) ...<Widget>[
            if (index > 0) SizedBox(height: tokens.spacing.s12),
            TenantProductionBatchCard(
              key: ValueKey('production-row-${batch.id}'),
              batch: batch,
              money: _money,
              onOpenCosts: () => openProductionCostScreen(
                context,
                batch: batch,
                money: _money,
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
}
