import 'package:flutter/material.dart';

import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/scaffold.dart';
import '../ui/tokens.dart';
import 'bulk_catalog.dart';
import 'catalog_management.dart';

/// The one route that corrects many products at once and imports a spreadsheet.
///
/// Two callables share it deliberately. `updateProducts` and `importProducts`
/// both want the same four steps - hold rows, ask what they would do, read a
/// per-row report, commit exactly that - and the preview is the part worth
/// building once: a spreadsheet is the one input nobody proofreads, and the first
/// time a person should see what four hundred rows are about to do is before they
/// do it.
///
/// Neither half is a Firestore write and neither could be. `allow update` on
/// `products` is the checkout decrement and nothing else, so a bulk correction is
/// N corrections executed on the server. A create *is* client-reachable, but no
/// device can write the `stock_adjustments` record and `stock_movements` entry
/// that give imported units a recorded origin, so an import is a callable too.
final class TenantBulkCatalogScreen extends StatelessWidget {
  const TenantBulkCatalogScreen({
    super.key,
    required this.reader,
    this.batchCallable,
    this.importCallable,
    this.onChanged,
    this.requestIdFactory,
  });

  final TenantDataReader reader;

  /// Corrects one field across many products. Injected by the composition root,
  /// and while it is absent this route does not offer to correct anything.
  final UpdateProductsCallable? batchCallable;

  /// Creates many products from pasted rows, injected for the same reason.
  final ImportProductsCallable? importCallable;

  /// Called after the server acknowledged a commit, so the composition root can
  /// ask the sync pass to re-read what this device caches.
  final VoidCallback? onChanged;

  /// One fresh request ID per page of one plan.
  final TenantCatalogRequestIdFactory? requestIdFactory;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Bulk catalog changes',
    contentWidth: AppContentWidth.records,
    body: TenantBulkCatalogPanel(
      reader: reader,
      batchCallable: batchCallable,
      importCallable: importCallable,
      onChanged: onChanged,
      requestIdFactory: requestIdFactory,
    ),
  );
}

/// Guarded bulk-catalog content, split out to keep it widget-testable.
final class TenantBulkCatalogPanel extends StatefulWidget {
  const TenantBulkCatalogPanel({
    super.key,
    required this.reader,
    this.batchCallable,
    this.importCallable,
    this.onChanged,
    this.requestIdFactory,
    this.pageSize = 20,
    this.categoryPageSize = 50,
  });

  final TenantDataReader reader;
  final UpdateProductsCallable? batchCallable;
  final ImportProductsCallable? importCallable;
  final VoidCallback? onChanged;
  final TenantCatalogRequestIdFactory? requestIdFactory;
  final int pageSize;
  final int categoryPageSize;

  @override
  State<TenantBulkCatalogPanel> createState() => _TenantBulkCatalogPanelState();
}

/// Which callable this screen is currently pointed at.
enum _BulkTask {
  correct('Correct many products'),
  importSheet('Import a spreadsheet');

  const _BulkTask(this.label);

  final String label;
}

final class _TenantBulkCatalogPanelState
    extends State<TenantBulkCatalogPanel> {
  // Every controller lives above the guard, for the reason the catalog surface's
  // do: paging and reloading both replace the guarded subtree with a loading
  // indicator, and a pasted four-hundred-row sheet would go with it.
  final TextEditingController _value = TextEditingController();
  final TextEditingController _sheet = TextEditingController();

  _BulkTask _task = _BulkTask.correct;

  /// Every product picked, keyed by ID and in the order it was picked.
  ///
  /// Held here rather than derived from the rendered page, because a selection
  /// that spans pages is the ordinary case: fifty rows is one request and this
  /// screen exists for four hundred.
  final Map<String, TenantProduct> _selected = <String, TenantProduct>{};

  /// The field a correction moves. `clearCost` is its own case rather than an
  /// empty cost, because omitting `cost` leaves a recorded figure alone and
  /// `cost: null` removes it.
  TenantProductField _field = TenantProductField.categoryId;
  bool _clearCost = false;
  String? _valueCategoryId;

  /// The plan the report below describes, kept so a commit sends the very pages
  /// that were previewed. Rebuilding them would issue new request IDs and, worse,
  /// could reorder rows - and order is part of what the server fingerprints.
  TenantProductBatchPlan? _batchPlan;
  TenantProductImportPlan? _importPlan;

  /// The category names the import report was worded with, held with the plan
  /// and for the same reason: a commit re-sends the pages the preview sent and
  /// must word their rows identically, while this route re-reads its categories
  /// between the two. A correction needs no equivalent - its rows carry the
  /// wording they were planned with.
  Map<String, String> _importCategoryNames = const <String, String>{};
  TenantBulkCatalogReport? _report;

  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  int _generation = 0;
  bool _busy = false;
  String? _notice;

  @override
  void dispose() {
    _value.dispose();
    _sheet.dispose();
    super.dispose();
  }

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

  bool _stillCurrent(String capturedKey) {
    if (!mounted) return false;
    final current = TenantSessionScope.of(context).session;
    return current != null && _sessionKey(current) == capturedKey;
  }

  String _newRequestId() =>
      (widget.requestIdFactory ?? secureTenantCatalogRequestId)();

  void _reload() {
    setState(() {
      _cursors = <String?>[null];
      _pageIndex = 0;
      _generation++;
    });
  }

  void _nextPage(String? cursor) {
    if (cursor == null) return;
    setState(() {
      _cursors = <String?>[..._cursors.take(_pageIndex + 1), cursor];
      _pageIndex++;
    });
  }

  void _previousPage() {
    if (_pageIndex == 0) return;
    setState(() => _pageIndex--);
  }

  /// Throws away the plan and its report.
  ///
  /// Called whenever anything the plan was built from changes, because a report
  /// describing rows that are no longer selected is worse than no report: it is
  /// a statement about a request nobody would now send.
  void _discardPlan() {
    _batchPlan = null;
    _importPlan = null;
    _importCategoryNames = const <String, String>{};
    _report = null;
  }

  void _changeTask(_BulkTask task) => setState(() {
    _task = task;
    _notice = null;
    _discardPlan();
  });

  void _toggle(TenantProduct product, bool selected) => setState(() {
    if (selected) {
      _selected[product.id] = product;
    } else {
      _selected.remove(product.id);
    }
    _discardPlan();
  });

  void _selectPage(Iterable<TenantProduct> products) => setState(() {
    for (final product in products) {
      _selected[product.id] = product;
    }
    _discardPlan();
  });

  void _clearSelection() => setState(() {
    _selected.clear();
    _discardPlan();
  });

  void _changeField(TenantProductField field, {required bool clearsCost}) =>
      setState(() {
        _field = field;
        _clearCost = clearsCost;
        _notice = null;
        _discardPlan();
      });

  TenantBulkCatalogEdit _edit() => switch (_field) {
    TenantProductField.categoryId => TenantBulkCatalogEdit.category(
      _valueCategoryId ?? '',
    ),
    TenantProductField.price => TenantBulkCatalogEdit.price(_value.text),
    TenantProductField.cost => _clearCost
        ? const TenantBulkCatalogEdit.clearCost()
        : TenantBulkCatalogEdit.cost(_value.text),
    // Unreachable: neither is offered, because a name and a code belong to one
    // product each.
    TenantProductField.name ||
    TenantProductField.sku => TenantBulkCatalogEdit.cost(_value.text),
  };

  /// Builds the plan, then asks the server what it would do, writing nothing.
  Future<void> _preview(TenantSession session, _CatalogView view) async {
    if (_busy) return;
    final capturedKey = _sessionKey(session);
    final repository = TenantBulkCatalogRepository(session: session);
    setState(() {
      _busy = true;
      _notice = null;
      _discardPlan();
    });
    try {
      TenantBulkCatalogReport report;
      switch (_task) {
        case _BulkTask.correct:
          final plan = repository.buildBatchPlan(
            products: _selected.values,
            edit: _edit(),
            categories: view.categories.items,
            requestIds: _newRequestId,
          );
          report = await _runBatch(
            session,
            plan,
            TenantBulkCatalogMode.preview,
          );
          if (!_stillCurrent(capturedKey)) return;
          _batchPlan = plan;
        case _BulkTask.importSheet:
          final plan = repository.buildImportPlan(
            sheet: _sheet.text,
            requestIds: _newRequestId,
          );
          final categoryNames = tenantCategoryNames(view.categories.items);
          report = await _runImport(
            session,
            plan,
            TenantBulkCatalogMode.preview,
            categoryNames: categoryNames,
          );
          if (!_stillCurrent(capturedKey)) return;
          _importPlan = plan;
          _importCategoryNames = categoryNames;
      }
      setState(() => _report = report);
    } on TenantBulkCatalogException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      setState(() => _notice = bulkCatalogRefusalMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sends the previewed pages again, in commit mode and under their own request
  /// IDs.
  ///
  /// A commit is offered only after a preview that answered every page, and that
  /// is a rule rather than caution: committing a page nobody previewed is exactly
  /// the thing the preview exists to prevent, and a preview whose chain stopped
  /// has not described the whole change.
  Future<void> _commit(TenantSession session) async {
    if (_busy) return;
    final capturedKey = _sessionKey(session);
    final batchPlan = _batchPlan;
    final importPlan = _importPlan;
    final preview = _report;
    if (preview == null || !preview.complete) return;
    if (!await _confirmed(
          title: batchPlan != null
              ? 'Correct ${batchPlan.rowCount} products?'
              : 'Create ${importPlan!.rowCount} products?',
          body: batchPlan != null
              ? _batchConfirmation(batchPlan, preview)
              : _importConfirmation(importPlan!, preview),
          action: batchPlan != null ? 'Apply corrections' : 'Create products',
        ) ||
        !_stillCurrent(capturedKey)) {
      return;
    }

    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final report = batchPlan != null
          ? await _runBatch(session, batchPlan, TenantBulkCatalogMode.commit)
          : await _runImport(
              session,
              importPlan!,
              TenantBulkCatalogMode.commit,
              categoryNames: _importCategoryNames,
            );
      if (!_stillCurrent(capturedKey)) return;
      setState(() => _report = report);
      // A page that landed changed what this device caches, so the sync pass is
      // asked for even when the chain stopped part way.
      if (report.pagesAnswered > 0) widget.onChanged?.call();
      if (batchPlan != null) _selected.clear();
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Drives one plan's pages in order, stopping at the first refusal.
  ///
  /// Sequential rather than concurrent, and that is not caution either: a commit
  /// is one transaction per page over documents a later page may name, and a
  /// refusal has to stop the chain rather than race the rest of it. Every page
  /// answered before the refusal is reported as answered, because in a commit it
  /// was written.
  Future<TenantBulkCatalogReport> _runBatch(
    TenantSession session,
    TenantProductBatchPlan plan,
    TenantBulkCatalogMode mode,
  ) async {
    final gateway = TenantProductBatchGateway(
      session: session,
      callable: widget.batchCallable!,
    );
    final rows = <TenantBulkCatalogRowReport>[];
    var answered = 0;
    for (final page in plan.pages) {
      try {
        rows.addAll(describeBatchOutcomes(page, await gateway.send(page, mode)));
        answered++;
      } on TenantBulkCatalogRequestException catch (error) {
        return TenantBulkCatalogReport(
          mode: mode,
          pageCount: plan.pages.length,
          pagesAnswered: answered,
          rows: rows,
          failure: error.failure,
          failureDetail: error.detail,
        );
      } on FormatException {
        return TenantBulkCatalogReport(
          mode: mode,
          pageCount: plan.pages.length,
          pagesAnswered: answered,
          rows: rows,
          // The request was sent and its answer could not be trusted, which is
          // exactly the unknown outcome: in a commit this page may have been
          // written, and only a re-read settles it.
          failure: TenantBulkCatalogFailure.ambiguous,
          failureDetail: _untrustedAnswer,
        );
      }
    }
    return TenantBulkCatalogReport(
      mode: mode,
      pageCount: plan.pages.length,
      pagesAnswered: answered,
      rows: rows,
    );
  }

  Future<TenantBulkCatalogReport> _runImport(
    TenantSession session,
    TenantProductImportPlan plan,
    TenantBulkCatalogMode mode, {
    required Map<String, String> categoryNames,
  }) async {
    final gateway = TenantProductImportGateway(
      session: session,
      callable: widget.importCallable!,
    );
    // The rows this client refused are part of the report from the start, so a
    // sheet whose every row was unreadable still produces one.
    final rows = <TenantBulkCatalogRowReport>[...plan.refused];
    var answered = 0;
    TenantBulkCatalogFailure? failure;
    String? detail;
    for (final page in plan.pages) {
      try {
        rows.addAll(
          describeImportOutcomes(
            page,
            await gateway.send(page, mode),
            names: categoryNames,
          ),
        );
        answered++;
      } on TenantBulkCatalogRequestException catch (error) {
        failure = error.failure;
        detail = error.detail;
        break;
      } on FormatException {
        failure = TenantBulkCatalogFailure.ambiguous;
        detail = _untrustedAnswer;
        break;
      }
    }
    rows.sort((left, right) => left.position.compareTo(right.position));
    return TenantBulkCatalogReport(
      mode: mode,
      pageCount: plan.pages.length,
      pagesAnswered: answered,
      rows: rows,
      failure: failure,
      failureDetail: detail,
    );
  }

  Future<bool> _confirmed({
    required String title,
    required String body,
    required String action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          AppButton(
            key: const ValueKey('bulk-catalog-cancel'),
            label: 'Cancel',
            tier: AppButtonTier.tertiary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppButton(
            key: const ValueKey('bulk-catalog-confirm'),
            label: action,
            tier: AppButtonTier.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return confirmed == true && mounted;
  }

  TenantGuardedLoader<_CatalogView> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    return _loader = (session) async {
      final repository = TenantCatalogRepository(
        session: session,
        reader: widget.reader,
      );
      final categories = await repository.loadCategories(
        pageSize: widget.categoryPageSize,
      );
      final products = await repository.loadProducts(
        pageSize: widget.pageSize,
        cursor: cursor,
      );
      return _CatalogView(categories: categories, products: products);
    };
  }

  String? _loaderKey;
  TenantGuardedLoader<_CatalogView>? _loader;

  @override
  Widget build(BuildContext context) {
    final guardKey = 'bulk-catalog:$_generation:$_pageIndex';
    return TenantRouteGuard<_CatalogView>(
      key: ValueKey(guardKey),
      allowedRoles: TenantBulkCatalogRepository.allowedRoles,
      load: _loaderFor(guardKey),
      denied: const Center(
        key: ValueKey('bulk-catalog-denied'),
        child: Text(
          'Only an owner, administrator, or manager may change the catalog.',
        ),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('bulk-catalog-failure'),
        child: Text('The catalog could not be read.'),
      ),
      builder: (context, session, view) => _BulkCatalogContents(
        view: view,
        task: _task,
        busy: _busy,
        notice: _notice,
        report: _report,
        // Which halves this build has at all. A missing callable is a half this
        // route does not offer, exactly as a missing writer is on the catalog
        // surface.
        canCorrect: widget.batchCallable != null,
        canImport: widget.importCallable != null,
        // Taken from the guarded session rather than the caller, so a correction
        // that names money disappears the moment the session stops allowing it.
        canChangeMoney: TenantBulkCatalogRepository.canChangeMoneyInSession(
          session,
        ),
        selected: _selected,
        field: _field,
        clearCost: _clearCost,
        valueCategoryId: _valueCategoryId,
        value: _value,
        sheet: _sheet,
        pageIndex: _pageIndex,
        onTaskChanged: _changeTask,
        onToggle: _toggle,
        onSelectPage: () => _selectPage(view.products.items),
        onClearSelection: _clearSelection,
        onFieldChanged: _changeField,
        onCategoryChosen: (categoryId) => setState(() {
          _valueCategoryId = categoryId;
          _discardPlan();
        }),
        onFormChanged: () => setState(_discardPlan),
        onPreview: () => _preview(session, view),
        onCommit: () => _commit(session),
        onDiscard: () => setState(() {
          _notice = null;
          _discardPlan();
        }),
        onNextPage: () => _nextPage(view.products.nextCursor),
        onPreviousPage: _previousPage,
      ),
    );
  }
}

const String _untrustedAnswer =
    'The request was sent and its answer could not be trusted.';

/// One guarded read of everything this route renders.
final class _CatalogView {
  const _CatalogView({required this.categories, required this.products});

  final TenantCatalogPage<TenantCategory> categories;
  final TenantCatalogPage<TenantProduct> products;
}

final class _BulkCatalogContents extends StatelessWidget {
  const _BulkCatalogContents({
    required this.view,
    required this.task,
    required this.busy,
    required this.notice,
    required this.report,
    required this.canCorrect,
    required this.canImport,
    required this.canChangeMoney,
    required this.selected,
    required this.field,
    required this.clearCost,
    required this.valueCategoryId,
    required this.value,
    required this.sheet,
    required this.pageIndex,
    required this.onTaskChanged,
    required this.onToggle,
    required this.onSelectPage,
    required this.onClearSelection,
    required this.onFieldChanged,
    required this.onCategoryChosen,
    required this.onFormChanged,
    required this.onPreview,
    required this.onCommit,
    required this.onDiscard,
    required this.onNextPage,
    required this.onPreviousPage,
  });

  final _CatalogView view;
  final _BulkTask task;
  final bool busy;
  final String? notice;
  final TenantBulkCatalogReport? report;
  final bool canCorrect;
  final bool canImport;
  final bool canChangeMoney;
  final Map<String, TenantProduct> selected;
  final TenantProductField field;
  final bool clearCost;
  final String? valueCategoryId;
  final TextEditingController value;
  final TextEditingController sheet;
  final int pageIndex;
  final ValueChanged<_BulkTask> onTaskChanged;
  final void Function(TenantProduct product, bool selected) onToggle;
  final VoidCallback onSelectPage;
  final VoidCallback onClearSelection;
  final void Function(TenantProductField field, {required bool clearsCost})
  onFieldChanged;
  final ValueChanged<String> onCategoryChosen;
  final VoidCallback onFormChanged;
  final VoidCallback onPreview;
  final VoidCallback onCommit;
  final VoidCallback onDiscard;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;

  bool get _offered =>
      task == _BulkTask.correct ? canCorrect : canImport;

  /// Whether a preview would have something to describe.
  bool get _canPreview {
    if (busy || !_offered) return false;
    if (task == _BulkTask.importSheet) return sheet.text.trim().isNotEmpty;
    if (selected.isEmpty) return false;
    return switch (field) {
      TenantProductField.categoryId => valueCategoryId != null,
      TenantProductField.cost when clearCost => true,
      _ => value.text.trim().isNotEmpty,
    };
  }

  /// A commit follows a preview that answered every page, and nothing else.
  bool get _canCommit {
    final answered = report;
    return !busy &&
        _offered &&
        answered != null &&
        answered.mode == TenantBulkCatalogMode.preview &&
        answered.complete &&
        (answered.createdCount + answered.updatedCount) > 0;
  }

  /// How many requests one preview or commit will be, stated before it runs.
  ///
  /// For a sheet this counts its non-blank lines less the header, which is an
  /// estimate rather than the answer: a row this client refuses is never sent, so
  /// the real count can be lower. It is on the button rather than in the report
  /// because "this is eight round trips" is what decides whether somebody starts
  /// it now.
  int get _pageCount {
    final rows = task == _BulkTask.correct
        ? selected.length
        : sheet.text
                  .split(RegExp('\r\n|\r|\n'))
                  .where((line) => line.trim().isNotEmpty)
                  .length -
              1;
    if (rows <= 0) return 0;
    return (rows + maximumBulkCatalogRows - 1) ~/ maximumBulkCatalogRows;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Many products at once', style: text.titleMedium),
        const SizedBox(height: 4),
        const Text(
          key: ValueKey('bulk-catalog-scope'),
          'Nothing here happens until it has been shown to you first. Every '
          'change is previewed row by row, writes nothing while it is being '
          'previewed, and is then applied exactly as it was shown. Rows are '
          'sent $maximumBulkCatalogRows at a time, so a large change is several '
          'requests and the report says which of them landed.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final option in _BulkTask.values)
              ChoiceChip(
                key: ValueKey(
                  'bulk-catalog-task-${option == _BulkTask.correct ? 'correct' : 'import'}',
                ),
                label: Text(option.label),
                selected: option == task,
                onSelected: busy ? null : (_) => onTaskChanged(option),
              ),
          ],
        ),
        if (!_offered) ...[
          const SizedBox(height: 12),
          Text(
            key: const ValueKey('bulk-catalog-unavailable'),
            task == _BulkTask.correct
                ? 'This build cannot correct products in bulk.'
                : 'This build cannot import products.',
          ),
        ],
        if (notice case final notice?) ...[
          const SizedBox(height: 16),
          Text(key: const ValueKey('bulk-catalog-notice'), notice),
        ],
        const SizedBox(height: 24),
        if (task == _BulkTask.correct)
          ..._correctionForm(context)
        else
          ..._importForm(context),
        const SizedBox(height: 20),
        Row(
          children: [
            // Preview is the primary here and commit is the primary further
            // down: they are different screen regions, and §2.1 permits one
            // each. Nothing is written by either until the other has been.
            AppButton(
              key: const ValueKey('bulk-catalog-preview'),
              label: _pageCount > 1
                  ? 'Preview ($_pageCount requests)'
                  : 'Preview, writing nothing',
              icon: Icons.fact_check_outlined,
              tier: AppButtonTier.primary,
              onPressed: _canPreview ? onPreview : null,
            ),
            const SizedBox(width: 12),
            if (report != null)
              AppButton(
                key: const ValueKey('bulk-catalog-discard'),
                label: 'Discard this report',
                tier: AppButtonTier.tertiary,
                onPressed: busy ? null : onDiscard,
              ),
          ],
        ),
        if (report case final report?) ..._reportSection(context, report),
      ],
    );
  }

  List<Widget> _correctionForm(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final categoryNames = tenantCategoryNames(view.categories.items);
    return <Widget>[
      Text('What to change', style: text.titleSmall),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            key: const ValueKey('bulk-catalog-field-categoryId'),
            label: const Text('Category'),
            selected: field == TenantProductField.categoryId,
            onSelected: busy
                ? null
                : (_) => onFieldChanged(
                    TenantProductField.categoryId,
                    clearsCost: false,
                  ),
          ),
          // A price and a cost are money, and the server decides permission over
          // the union of every row's fields: one row naming either refuses the
          // whole request. So they are not offered at all rather than offered and
          // refused, which would teach a manager only that the app guesses.
          if (canChangeMoney) ...[
            ChoiceChip(
              key: const ValueKey('bulk-catalog-field-price'),
              label: const Text('Unit price'),
              selected: field == TenantProductField.price,
              onSelected: busy
                  ? null
                  : (_) => onFieldChanged(
                      TenantProductField.price,
                      clearsCost: false,
                    ),
            ),
            ChoiceChip(
              key: const ValueKey('bulk-catalog-field-cost'),
              label: const Text('Unit cost'),
              selected: field == TenantProductField.cost && !clearCost,
              onSelected: busy
                  ? null
                  : (_) => onFieldChanged(
                      TenantProductField.cost,
                      clearsCost: false,
                    ),
            ),
            ChoiceChip(
              key: const ValueKey('bulk-catalog-field-clear-cost'),
              label: const Text('Remove the unit cost'),
              selected: field == TenantProductField.cost && clearCost,
              onSelected: busy
                  ? null
                  : (_) => onFieldChanged(
                      TenantProductField.cost,
                      clearsCost: true,
                    ),
            ),
          ],
        ],
      ),
      if (!canChangeMoney) ...[
        const SizedBox(height: 8),
        Text(
          key: const ValueKey('bulk-catalog-money-hidden'),
          'Only an owner or administrator may change a price or what a product '
          'costs. One row naming either refuses every row in the same request, '
          'so neither is offered here.',
          style: text.bodySmall,
        ),
      ],
      const SizedBox(height: 12),
      if (field == TenantProductField.categoryId) ...[
        if (view.categories.items.isEmpty)
          const Text(
            key: ValueKey('bulk-catalog-no-categories'),
            'This business has no categories yet, so there is nothing to file '
            'these products under.',
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in view.categories.items)
                ChoiceChip(
                  key: ValueKey('bulk-catalog-category-${category.id}'),
                  label: Text(category.name),
                  selected: category.id == valueCategoryId,
                  onSelected: busy
                      ? null
                      : (_) => onCategoryChosen(category.id),
                ),
            ],
          ),
      ] else if (!clearCost)
        AppTextField(
          key: const ValueKey('bulk-catalog-value'),
          controller: value,
          enabled: !busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => onFormChanged(),
          label: field == TenantProductField.price
              ? 'Unit price for every product chosen'
              : 'Unit cost for every product chosen',
          helper: field == TenantProductField.price
              ? 'At most two decimal places. A new price applies to the next '
                    'sale; sales already recorded keep the price they were '
                    'sold at.'
              : 'At most two decimal places. Every sale records the cost as '
                    'it stands at that moment, so this prices the next sale '
                    'and never changes a profit already reported.',
        )
      else
        const Text(
          key: ValueKey('bulk-catalog-clear-cost-note'),
          'Every product chosen stops having a recorded unit cost. Their sales '
          'then report no profit and are counted as missing cost data, rather '
          'than reporting the whole price as profit.',
        ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: Text(
              key: const ValueKey('bulk-catalog-selection'),
              selected.isEmpty
                  ? 'No products chosen.'
                  : '${selected.length} product${selected.length == 1 ? '' : 's'} '
                        'chosen, across every page.',
            ),
          ),
          AppButton(
            key: const ValueKey('bulk-catalog-select-page'),
            label: 'Choose this page',
            tier: AppButtonTier.tertiary,
            size: AppButtonSize.sm,
            onPressed: busy || view.products.items.isEmpty
                ? null
                : onSelectPage,
          ),
          AppButton(
            key: const ValueKey('bulk-catalog-clear-selection'),
            label: 'Clear',
            tier: AppButtonTier.tertiary,
            size: AppButtonSize.sm,
            onPressed: busy || selected.isEmpty ? null : onClearSelection,
          ),
        ],
      ),
      if (view.products.items.isEmpty)
        const Text(
          key: ValueKey('bulk-catalog-no-products'),
          'No products on this page.',
        )
      else
        for (final product in view.products.items)
          CheckboxListTile(
            key: ValueKey('bulk-catalog-select-${product.id}'),
            value: selected.containsKey(product.id),
            onChanged: busy
                ? null
                : (value) => onToggle(product, value ?? false),
            title: Text(product.name),
            subtitle: Text(
              '${tenantCategoryLabel(product.categoryId, names: categoryNames)} '
              '• ${product.sku} • ${product.price.toStringAsFixed(2)}'
              '${product.cost == null ? '' : ' • costs ${product.cost!.toStringAsFixed(2)}'}',
            ),
          ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AppButton(
            key: const ValueKey('bulk-catalog-previous-page'),
            label: 'Previous',
            tier: AppButtonTier.tertiary,
            onPressed: pageIndex == 0 || busy ? null : onPreviousPage,
          ),
          Text(
            key: const ValueKey('bulk-catalog-page'),
            'Page ${pageIndex + 1}',
          ),
          AppButton(
            key: const ValueKey('bulk-catalog-next-page'),
            label: 'Next',
            tier: AppButtonTier.tertiary,
            onPressed: view.products.hasMore && !busy ? onNextPage : null,
          ),
        ],
      ),
    ];
  }

  List<Widget> _importForm(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return <Widget>[
      Text('Paste the rows', style: text.titleSmall),
      const SizedBox(height: 8),
      const Text(
        key: ValueKey('bulk-catalog-sheet-help'),
        'Copy the rows out of the spreadsheet, header line included, and paste '
        'them here. Columns may be separated by commas, tabs, or semicolons, '
        'and a cell holding one of those can be wrapped in double quotes.\n\n'
        'The header must name name, sku, and price. It may also name cost, '
        'quantity, and either category — the category\'s own name, matched '
        'against this business — or categoryId. A column this import does not '
        'read is refused rather than ignored, so nothing you supplied is '
        'dropped without being mentioned.\n\n'
        'A category that does not already exist refuses its row: add it on '
        '"Manage catalog" first. An opening quantity is recorded as an opening '
        'balance in the stock ledger, so those units have a stated origin.',
      ),
      const SizedBox(height: 12),
      AppTextField(
        key: const ValueKey('bulk-catalog-sheet'),
        controller: sheet,
        enabled: !busy,
        minLines: 6,
        maxLines: 14,
        onChanged: (_) => onFormChanged(),
        label: 'Header line, then one line per product',
        placeholder: 'name,sku,price,quantity,category',
      ),
      if (!canChangeMoney) ...[
        const SizedBox(height: 8),
        Text(
          key: const ValueKey('bulk-catalog-import-cost-hidden'),
          'Only an owner or administrator may record what a product costs, so a '
          'cost column is refused. A price is not: setting a first price is '
          'creation, and the add-product form accepts one too.',
          style: text.bodySmall,
        ),
      ],
    ];
  }

  List<Widget> _reportSection(
    BuildContext context,
    TenantBulkCatalogReport report,
  ) {
    final text = Theme.of(context).textTheme;
    return <Widget>[
      const SizedBox(height: 24),
      Text('What this does', style: text.titleMedium),
      const SizedBox(height: 8),
      Text(
        key: const ValueKey('bulk-catalog-summary'),
        _summary(report, task),
      ),
      if (report.failure case final failure?) ...[
        const SizedBox(height: 8),
        Text(
          key: const ValueKey('bulk-catalog-report-failure'),
          _failureNotice(failure, report),
        ),
      ],
      const SizedBox(height: 12),
      // Every row, never a count. The server names every broken row at once, and
      // collapsing that into "12 rows failed" would throw away the reason both
      // callables report per row.
      for (final row in report.rows)
        Card(
          child: ListTile(
            key: ValueKey('bulk-catalog-row-${row.position}'),
            dense: true,
            title: Text('${row.status.label}: ${row.subject}'),
            subtitle: Text(
              key: ValueKey('bulk-catalog-row-detail-${row.position}'),
              '${task == _BulkTask.correct ? 'Product' : 'Line'} '
              '${row.position} • ${row.detail}',
            ),
          ),
        ),
      const SizedBox(height: 16),
      if (report.mode == TenantBulkCatalogMode.preview)
        AppButton(
          key: const ValueKey('bulk-catalog-commit'),
          label: task == _BulkTask.correct
              ? 'Apply exactly this'
              : 'Create exactly this',
          icon: Icons.playlist_add_check_outlined,
          tier: AppButtonTier.primary,
          onPressed: _canCommit ? onCommit : null,
        )
      else
        Text(
          key: const ValueKey('bulk-catalog-committed'),
          task == _BulkTask.correct
              ? 'This is what was written. What each field held before is '
                    'recorded against every product that changed. This device '
                    're-reads its own copy of the catalog on the next sync.'
              : 'This is what was created. Re-running the same sheet would '
                    'create these products again, because nothing in this app '
                    'makes a code unique - correct what was refused and import '
                    'only those rows.',
        ),
    ];
  }
}

/// One sentence stating what the report is, before any row is read.
String _summary(TenantBulkCatalogReport report, _BulkTask task) {
  final buffer = StringBuffer();
  if (report.mode == TenantBulkCatalogMode.preview) {
    buffer.write('Nothing has been written. ');
  }
  if (task == _BulkTask.correct) {
    final verb = report.mode == TenantBulkCatalogMode.preview
        ? 'would be corrected'
        : 'were corrected';
    buffer.write(
      '${report.updatedCount} $verb, ${report.unchangedCount} already hold '
      'this value, and ${report.failedCount} cannot be.',
    );
  } else {
    final verb = report.mode == TenantBulkCatalogMode.preview
        ? 'would be created'
        : 'were created';
    buffer.write(
      '${report.createdCount} $verb and ${report.failedCount} cannot be.',
    );
  }
  if (report.pageCount > 1) {
    buffer.write(
      ' ${report.pagesAnswered} of ${report.pageCount} requests '
      '${report.mode == TenantBulkCatalogMode.preview ? 'were previewed' : 'landed'}.',
    );
  }
  return buffer.toString();
}

String _failureNotice(
  TenantBulkCatalogFailure failure,
  TenantBulkCatalogReport report,
) {
  final wrote = report.mode == TenantBulkCatalogMode.commit;
  final stopped = report.pagesAnswered > 0
      ? wrote
            ? 'The ${report.pagesAnswered} request'
                  '${report.pagesAnswered == 1 ? '' : 's'} listed above '
                  'landed and the rest were not sent.'
            : 'Only the rows listed above were previewed.'
      : wrote
      ? 'Nothing was written.'
      : 'Nothing was previewed.';
  final reason = switch (failure) {
    TenantBulkCatalogFailure.forbidden =>
      'Only an owner, administrator, or manager may change the catalog.',
    TenantBulkCatalogFailure.moneyForbidden =>
      'Only an owner or administrator may change a price or what a product '
          'costs, and one row naming either refuses every row with it.',
    TenantBulkCatalogFailure.duplicateRequest =>
      'One of these requests was already used for a different set of rows. '
          'Discard this report and preview again, which issues new '
          'identifiers.',
    TenantBulkCatalogFailure.tooManyCategories =>
      'This business holds more categories than an import will match names '
          'against. Name each row\'s category by categoryId instead.',
    TenantBulkCatalogFailure.invalidRequest =>
      'The server refused a request as malformed, which means this build and '
          'the server disagree about what a row may hold.',
    TenantBulkCatalogFailure.refused => 'A request was refused.',
    TenantBulkCatalogFailure.ambiguous =>
      wrote
          ? 'The outcome of the next request is unknown, so it may or may not '
                'have been written. The catalog has been re-read; preview '
                'again and apply only what is still wrong - a repeat of the '
                'same request cannot apply it twice.'
          : 'The outcome of the next request is unknown. A preview writes '
                'nothing, so previewing again is safe.',
  };
  return '$reason $stopped';
}

/// States what a bulk correction does, and what it does not touch.
String _batchConfirmation(
  TenantProductBatchPlan plan,
  TenantBulkCatalogReport preview,
) {
  final buffer = StringBuffer(
    'Exactly what the report above lists is applied: '
    '${preview.updatedCount} product'
    '${preview.updatedCount == 1 ? '' : 's'} corrected, '
    '${preview.unchangedCount} left alone because they already hold this '
    'value, and ${preview.failedCount} not changed at all.\n\n'
    'Each correction is recorded permanently against its product, with who '
    'made it and what the field held before. Nothing else about any product '
    'changes: their stock is untouched, their identities stay the same, and '
    'every sale, return, and reported figure already recorded still names '
    'them.',
  );
  switch (plan.field) {
    case TenantProductField.price:
      buffer.write(
        '\n\nThe new price applies to the next sale of each product. Sales '
        'already recorded keep the price they were sold at, so no figure '
        'already reported moves.',
      );
    case TenantProductField.cost:
      buffer.write(
        plan.clearsCost
            ? '\n\nTheir sales then report no profit and are counted as '
                  'missing cost data. Profit already reported does not move: '
                  'every sale recorded the cost as it stood at that moment.'
            : '\n\nEvery sale records what a unit cost at the moment of that '
                  'sale, so this prices the next sale and never changes a '
                  'profit already reported.',
      );
    case TenantProductField.categoryId:
      buffer.write(
        '\n\nEvery grouped report and every till filter follows the new '
        'category from now on. Figures already recorded are not regrouped.',
      );
    case TenantProductField.name:
    case TenantProductField.sku:
      break;
  }
  if (plan.pages.length > 1) {
    buffer.write(
      '\n\nThis is ${plan.pages.length} separate requests of at most '
      '$maximumBulkCatalogRows products. They are sent one after another, and '
      'if one is refused the ones before it have already been applied - the '
      'report will say which.',
    );
  }
  return buffer.toString();
}

/// States what an import does, including the one hazard it cannot prevent.
String _importConfirmation(
  TenantProductImportPlan plan,
  TenantBulkCatalogReport preview,
) {
  final buffer = StringBuffer(
    'Exactly what the report above lists is created: ${preview.createdCount} '
    'product${preview.createdCount == 1 ? '' : 's'}, and '
    '${preview.failedCount} row${preview.failedCount == 1 ? '' : 's'} not '
    'created at all.\n\n'
    'A product created here can be sold, counted, returned, and reported on '
    'immediately. A row with an opening quantity is created holding it, and '
    'those units are recorded in the stock ledger as an opening balance, so '
    'the ledger says where they came from.\n\n'
    'Running this sheet again creates these products a second time. Nothing '
    'in this app makes a code unique, and retiring a product is not an undo - '
    'so correct the rows that were refused and import only those.',
  );
  if (plan.pages.length > 1) {
    buffer.write(
      '\n\nThis is ${plan.pages.length} separate requests of at most '
      '$maximumBulkCatalogRows products. They are sent one after another, and '
      'if one is refused the ones before it have already been created - the '
      'report will say which.',
    );
  }
  return buffer.toString();
}
