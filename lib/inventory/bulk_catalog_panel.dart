import 'package:flutter/material.dart';

import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/buttons.dart';
import '../ui/chips.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/pagination.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'bulk_catalog.dart';
import 'bulk_catalog_attempt_store.dart';
import 'product_sheet.dart';
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
    this.sheetPicker,
    this.sheetSaver,
    this.attempts,
    this.offerCorrections = false,
  });

  final TenantDataReader reader;

  /// Whether this route also offers to correct many products at once.
  ///
  /// **Off since 2026-09-14, and the half it hides is still here.** Correcting
  /// a field across many products shared this screen with importing, chosen
  /// between by a pair of chips at the top - which asked somebody who came to
  /// add stock to first work out which of two unrelated jobs the screen was
  /// doing. Adding products is the job it is now. Every line serving the other
  /// one is still compiled, still tested against this flag, and restoring it is
  /// this one argument rather than a rewrite.
  final bool offerCorrections;

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

  /// Choosing a spreadsheet off the device. Absent leaves the button off, which
  /// is what a build with no file picker wired gets; the field below still takes
  /// pasted rows, so the route is never unusable for want of a platform seam.
  final TenantProductSheetPicker? sheetPicker;

  /// Handing a generated template to wherever this device keeps files.
  final TenantProductSheetSaver? sheetSaver;

  /// Where an import that stopped part way is held between attempts. Absent
  /// leaves a stopped import unrecoverable past this screen, which is what a
  /// build with no durable storage wired gets; the recovery still works within
  /// one visit, because the attempt is held in memory either way.
  final TenantProductImportAttemptSource? attempts;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Add many products',
    contentWidth: AppContentWidth.records,
    body: TenantBulkCatalogPanel(
      reader: reader,
      batchCallable: batchCallable,
      importCallable: importCallable,
      onChanged: onChanged,
      requestIdFactory: requestIdFactory,
      sheetPicker: sheetPicker,
      sheetSaver: sheetSaver,
      attempts: attempts,
      offerCorrections: offerCorrections,
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
    this.sheetPicker,
    this.sheetSaver,
    this.attempts,
    this.pageSize = 20,
    this.clock = DateTime.now,
    this.offerCorrections = false,
  });

  final TenantDataReader reader;
  final UpdateProductsCallable? batchCallable;
  final ImportProductsCallable? importCallable;
  final VoidCallback? onChanged;
  final TenantCatalogRequestIdFactory? requestIdFactory;
  final TenantProductSheetPicker? sheetPicker;
  final TenantProductSheetSaver? sheetSaver;

  /// See [TenantBulkCatalogScreen.attempts].
  final TenantProductImportAttemptSource? attempts;

  final int pageSize;

  /// Only the date the template is named with, so a test can name one.
  final DateTime Function() clock;

  /// See [TenantBulkCatalogScreen.offerCorrections].
  final bool offerCorrections;

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

final class _TenantBulkCatalogPanelState extends State<TenantBulkCatalogPanel> {
  // Every controller lives above the guard, for the reason the catalog surface's
  // do: paging and reloading both replace the guarded subtree with a loading
  // indicator, and a pasted four-hundred-row sheet would go with it.
  final TextEditingController _value = TextEditingController();
  final TextEditingController _sheet = TextEditingController();

  // **Fixed at `importSheet` since 2026-09-14, and the other value is kept.**
  // Correcting many products at once was offered beside importing as a pair of
  // chips, which asked somebody who came here to add stock to first decide
  // which of two unrelated jobs this screen was doing. Adding products is the
  // job; `_BulkTask.correct` and every line serving it stay compiled and tested
  // so restoring it is a chip rather than a rewrite.
  late _BulkTask _task = widget.offerCorrections
      ? _BulkTask.correct
      : _BulkTask.importSheet;

  /// The file the rows below were read out of, so the person can see that the
  /// one they chose is the one that was read. Null while nothing was picked -
  /// including for rows that were pasted, which remains a supported way in.
  String? _pickedName;

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

  /// The import this device started and has not seen finish.
  ///
  /// **Not the plan, and the difference is the whole of H3.** A plan is built
  /// from the sheet and dies with it; an attempt is the request IDs a commit
  /// was actually sent under, written down before the first page goes out. A
  /// chain that stops - a refusal, or an answer that never arrived - leaves
  /// this set, and the recovery re-sends *these* pages under *these* keys, so
  /// a page the server already wrote answers off its own idempotency record
  /// instead of creating four hundred products a second time.
  ///
  /// Held in state as well as on disk so the recovery works in a build with no
  /// durable store wired, for as long as this screen is open.
  TenantProductImportAttempt? _attempt;

  /// The session [_attempt] was read for, so it is re-read when that changes
  /// and not on every build.
  String? _attemptKey;

  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  int _generation = 0;
  bool _busy = false;

  /// Reports one write outcome, over the screen rather than inside the page.
  ///
  /// See `showAppSnackBar`: since 2026-09-03 every outcome goes there, and
  /// inline text is left to the one thing it is still right for - a field
  /// saying what is wrong with what was typed into it.
  void _reportNotice(AppNotice notice) => showAppSnackBar(context, notice);

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

  /// *Download Template*, the first of the two things the pre-multitenancy app
  /// offered here.
  ///
  /// The example row names a category this business actually has, because a
  /// category that does not exist refuses its row and a template nobody can
  /// import back teaches the wrong lesson. With no categories yet the column is
  /// left blank rather than filled with something invented.
  Future<void> _downloadTemplate(
    TenantSession session,
    List<TenantCategory> categories,
  ) async {
    final saver = widget.sheetSaver;
    if (saver == null || _busy) return;
    setState(() => _busy = true);
    try {
      final outcome = await saver.save(
        filename: productImportTemplateFilename(widget.clock()),
        contents: productImportTemplateCsv(
          includeCost: TenantBulkCatalogRepository.canChangeMoneyInSession(
            session,
          ),
          categoryName: categories.firstOrNull?.name,
        ),
      );
      if (!mounted) return;
      _reportNotice(switch (outcome) {
        TenantSheetSaveOutcome.saved => const AppNotice(
          status: AppStatus.ok,
          message: 'Template sent. Fill it in and upload it back.',
        ),
        // Not a failure: the person opened the sheet and changed their mind.
        TenantSheetSaveOutcome.dismissed => const AppNotice(
          status: AppStatus.info,
          message: 'Template not sent anywhere.',
        ),
        TenantSheetSaveOutcome.unavailable => const AppNotice(
          status: AppStatus.problem,
          message:
              'This device offered nowhere to send the template. Install a '
              'file manager or a mail app and try again.',
        ),
      });
    } catch (error) {
      if (!mounted) return;
      _reportNotice(
        AppNotice(
          status: AppStatus.problem,
          message: 'The template could not be prepared. $error',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// *Upload*, the second. The file's rows land in the same field pasted rows
  /// land in, so one parser, one preview and one commit serve both ways in - and
  /// a row the sheet got wrong can be fixed here rather than back in Excel.
  Future<void> _chooseFile() async {
    final picker = widget.sheetPicker;
    if (picker == null || _busy) return;
    setState(() => _busy = true);
    try {
      final picked = await picker.pick();
      if (picked == null) return;
      final text = decodeProductSheet(picked);
      if (!mounted) return;
      setState(() {
        _sheet.text = text;
        _pickedName = picked.name;
        // The report on screen described the last sheet, not this one.
        _discardPlan();
      });
    } on TenantProductSheetFormatException catch (error) {
      if (!mounted) return;
      _reportNotice(
        AppNotice(status: AppStatus.problem, message: error.message),
      );
    } catch (error) {
      if (!mounted) return;
      _reportNotice(
        AppNotice(
          status: AppStatus.problem,
          message: 'That file could not be read. $error',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeTask(_BulkTask task) => setState(() {
    _task = task;
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
        _discardPlan();
      });

  TenantBulkCatalogEdit _edit() => switch (_field) {
    TenantProductField.categoryId => TenantBulkCatalogEdit.category(
      _valueCategoryId ?? '',
    ),
    TenantProductField.price => TenantBulkCatalogEdit.price(_value.text),
    TenantProductField.cost =>
      _clearCost
          ? const TenantBulkCatalogEdit.clearCost()
          : TenantBulkCatalogEdit.cost(_value.text),
    // Unreachable: neither is offered, because a name and a code belong to one
    // product each.
    TenantProductField.name ||
    TenantProductField.sku ||
    TenantProductField.image => TenantBulkCatalogEdit.cost(_value.text),
  };

  /// Builds the plan, then asks the server what it would do, writing nothing.
  Future<void> _preview(TenantSession session, _CatalogView view) async {
    if (_busy) return;
    final capturedKey = _sessionKey(session);
    final repository = TenantBulkCatalogRepository(session: session);
    setState(() {
      _busy = true;
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
      _reportNotice(AppNotice.refused(bulkCatalogRefusalMessage(error)));
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
    });
    try {
      final TenantBulkCatalogReport report;
      if (batchPlan != null) {
        report = await _runBatch(
          session,
          batchPlan,
          TenantBulkCatalogMode.commit,
        );
      } else {
        // **Written down before the first page is sent, not after.** An attempt
        // recorded once the chain has stopped would be recorded by a device
        // that may already be offline, or not at all by one that was killed -
        // and the pages whose answers went missing are exactly the ones a
        // recovery needs the keys for.
        final opened = TenantProductImportAttempt.opening(
          plan: importPlan!,
          categoryNames: _importCategoryNames,
          startedAt: widget.clock(),
        );
        await _holdAttempt(session, opened);
        if (!_stillCurrent(capturedKey)) return;
        report = await _commitAttempt(session, opened);
      }
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

  /// Finishes the import this device started and has not seen finish.
  ///
  /// **It does not look at the sheet, and that is the point.** The pages it
  /// sends are the ones the stopped commit sent, under the keys it sent them
  /// under. The first of them is the page nobody knows the fate of: the server
  /// decides, by finding its own record or not finding it, and this device
  /// stops guessing.
  Future<void> _resumeImport(TenantSession session) async {
    if (_busy) return;
    final attempt = _attempt;
    if (attempt == null || attempt.isComplete) return;
    final capturedKey = _sessionKey(session);
    if (!await _confirmed(
          title: 'Finish this import?',
          body:
              'The ${attempt.remainingRowCount} products that were never '
              'confirmed will be sent again under the same request. A page the '
              'server already recorded is answered from that record, so '
              'nothing is created twice.',
          action: 'Finish the import',
        ) ||
        !_stillCurrent(capturedKey)) {
      return;
    }
    setState(() {
      _busy = true;
      _discardPlan();
    });
    try {
      final report = await _commitAttempt(session, attempt);
      if (!_stillCurrent(capturedKey)) return;
      setState(() => _report = report);
      if (report.pagesAnswered > attempt.pagesAnswered) {
        widget.onChanged?.call();
      }
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Stops offering to finish it, without undoing anything it wrote.
  ///
  /// **Nothing is deleted by this.** Pages that landed created products, and a
  /// product is retired rather than un-created. What it discards is this
  /// device's ability to finish the rest safely - so it says so, because the
  /// alternative is somebody clearing the notice and importing the sheet again,
  /// which is the duplication this whole path exists to prevent.
  Future<void> _discardAttempt(TenantSession session) async {
    if (_busy) return;
    final attempt = _attempt;
    if (attempt == null) return;
    final capturedKey = _sessionKey(session);
    if (!await _confirmed(
          title: 'Forget this unfinished import?',
          body:
              'Products it already created stay in the catalog, and the '
              '${attempt.remainingRowCount} that were never confirmed will not '
              'be sent. Importing that sheet again after this would create '
              'every product it did create a second time, so check the catalog '
              'first.',
          action: 'Forget it',
        ) ||
        !_stillCurrent(capturedKey)) {
      return;
    }
    await widget.attempts?.clear(uid: session.uid, tenantId: session.tenantId);
    if (!_stillCurrent(capturedKey)) return;
    setState(() => _attempt = null);
  }

  /// Drives one attempt's remaining pages, writing it back as each answers.
  ///
  /// Sequential and stopping at the first refusal, as a plan's chain is and for
  /// the same reason. What is new is the write between pages: a device killed
  /// on page six resumes at page six, and the five before it are never sent
  /// again.
  Future<TenantBulkCatalogReport> _commitAttempt(
    TenantSession session,
    TenantProductImportAttempt attempt,
  ) async {
    final gateway = TenantProductImportGateway(
      session: session,
      callable: widget.importCallable!,
    );
    var current = attempt;
    TenantBulkCatalogFailure? failure;
    String? detail;
    for (final page in attempt.remainingPages) {
      try {
        final outcomes = describeImportOutcomes(
          page,
          await gateway.send(page, TenantBulkCatalogMode.commit),
          names: attempt.categoryNames,
        );
        current = current.advanced(answered: 1, outcomes: outcomes);
        await _holdAttempt(session, current);
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
    if (current.isComplete) {
      await widget.attempts?.clear(
        uid: session.uid,
        tenantId: session.tenantId,
      );
      if (mounted) setState(() => _attempt = null);
    }
    final rows = <TenantBulkCatalogRowReport>[...current.rows]
      ..sort((left, right) => left.position.compareTo(right.position));
    return TenantBulkCatalogReport(
      mode: TenantBulkCatalogMode.commit,
      pageCount: current.pages.length,
      pagesAnswered: current.pagesAnswered,
      rows: rows,
      failure: failure,
      failureDetail: detail,
    );
  }

  /// Holds [attempt] on this device and in this screen's state.
  ///
  /// Both, because they answer different failures: the store survives the app
  /// being killed, and the field survives nothing at all but is what a build
  /// with no store wired recovers from for as long as this screen is open.
  Future<void> _holdAttempt(
    TenantSession session,
    TenantProductImportAttempt attempt,
  ) async {
    await widget.attempts?.save(uid: session.uid, attempt: attempt);
    if (mounted) setState(() => _attempt = attempt);
  }

  /// Reads the unfinished import for this session, once per session.
  ///
  /// Called from the guard's builder, where the session is known. It assigns
  /// rather than calling `setState`, because the build that calls it is the
  /// build that reads what it assigned.
  void _syncAttempt(TenantSession session) {
    final key = _sessionKey(session);
    if (_attemptKey == key) return;
    _attemptKey = key;
    _attempt = widget.attempts?.attemptFor(
      uid: session.uid,
      tenantId: session.tenantId,
    );
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
        rows.addAll(
          describeBatchOutcomes(page, await gateway.send(page, mode)),
        );
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
    final confirmed = await showConfirmDialog(
      context,
      title: title,
      consequence: body,
      confirmLabel: action,
      tier: AppButtonTier.primary,
      confirmKey: const ValueKey('bulk-catalog-confirm'),
      cancelKey: const ValueKey('bulk-catalog-cancel'),
    );
    return confirmed && mounted;
  }

  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    TenantGuardedLoader<_CatalogView> readWith(TenantDataReader reader) =>
        (session) async {
          final repository = TenantCatalogRepository(
            session: session,
            reader: reader,
          );
          // Every category, for the reason the catalog panel reads them all:
          // a bulk move offers this list as the destination, and one that stops
          // at a page cannot move products into the rest.
          final categories = await repository.loadEveryCategory();
          final products = await repository.loadProducts(
            pageSize: widget.pageSize,
            cursor: cursor,
          );
          return _CatalogView(categories: categories, products: products);
        };
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  String? _loaderKey;
  TenantGuardedLoader<_CatalogView>? _loader;
  TenantGuardedLoader<_CatalogView>? _loaderCached;

  @override
  Widget build(BuildContext context) {
    final guardKey = 'bulk-catalog:$_generation:$_pageIndex';
    _composeLoaders(guardKey);
    return TenantRouteGuard<_CatalogView>(
      allowedRoles: TenantBulkCatalogRepository.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
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
      builder: (context, session, view) {
        _syncAttempt(session);
        return _BulkCatalogContents(
          view: view,
          task: _task,
          busy: _busy,
          report: _report,
          attempt: _attempt,
          onResumeImport: () => _resumeImport(session),
          onDiscardAttempt: () => _discardAttempt(session),
          // Which halves this build has at all. A missing callable is a half this
          // route does not offer, exactly as a missing writer is on the catalog
          // surface.
          canCorrect: widget.batchCallable != null,
          canImport: widget.importCallable != null,
          offerCorrections: widget.offerCorrections,
          onTaskChanged: _changeTask,
          canDownloadTemplate: widget.sheetSaver != null,
          canPickFile: widget.sheetPicker != null,
          pickedName: _pickedName,
          onDownloadTemplate: () =>
              _downloadTemplate(session, view.categories.items),
          onChooseFile: _chooseFile,
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
            _discardPlan();
          }),
          onNextPage: () => _nextPage(view.products.nextCursor),
          onPreviousPage: _previousPage,
        );
      },
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
    required this.report,
    required this.attempt,
    required this.onResumeImport,
    required this.onDiscardAttempt,
    required this.canCorrect,
    required this.canImport,
    required this.offerCorrections,
    required this.onTaskChanged,
    required this.canDownloadTemplate,
    required this.canPickFile,
    required this.pickedName,
    required this.onDownloadTemplate,
    required this.onChooseFile,
    required this.canChangeMoney,
    required this.selected,
    required this.field,
    required this.clearCost,
    required this.valueCategoryId,
    required this.value,
    required this.sheet,
    required this.pageIndex,
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
  final TenantBulkCatalogReport? report;

  /// The import this device started and has not seen finish, or null.
  final TenantProductImportAttempt? attempt;

  final VoidCallback onResumeImport;
  final VoidCallback onDiscardAttempt;
  final bool canCorrect;
  final bool canImport;

  /// See [TenantBulkCatalogScreen.offerCorrections].
  final bool offerCorrections;

  final ValueChanged<_BulkTask> onTaskChanged;

  /// Whether this build wired somewhere to send a generated template.
  final bool canDownloadTemplate;

  /// Whether this build wired a file picker.
  final bool canPickFile;

  /// The file the rows were read out of, or null for pasted rows.
  final String? pickedName;

  final VoidCallback onDownloadTemplate;
  final VoidCallback onChooseFile;
  final bool canChangeMoney;
  final Map<String, TenantProduct> selected;
  final TenantProductField field;
  final bool clearCost;
  final String? valueCategoryId;
  final TextEditingController value;
  final TextEditingController sheet;
  final int pageIndex;
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

  bool get _offered => task == _BulkTask.correct ? canCorrect : canImport;

  /// The import waiting to be finished, when there is one.
  ///
  /// A correction is not held up by it: `updateProducts` addresses each row by
  /// the product it corrects, so it has no creation to repeat.
  TenantProductImportAttempt? get _unfinished {
    final held = attempt;
    if (held == null || held.isComplete) return null;
    return task == _BulkTask.importSheet ? held : null;
  }

  /// Whether a preview would have something to describe.
  bool get _canPreview {
    if (busy || !_offered || _unfinished != null) return false;
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
        _unfinished == null &&
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
    final tokens = AppTokens.componentOf(context);
    return ListView(
      padding: EdgeInsets.all(tokens.spacing.s20),
      children: [
        SectionHeading('Many products at once'),
        SizedBox(height: tokens.spacing.s4),
        // A helper rather than a notice, and the call is worth stating because
        // it could have gone the other way. §5.2 names this route's prose by
        // name as `Disclosure` material, and this paragraph is true of every
        // change either callable will ever make - it is read once. The
        // reconciliation day page's request scope is a `Callout` instead
        // because it corrects a misunderstanding about *what the button covers*;
        // this one promises that the button is safe, which is a different job.
        const Disclosure(
          key: ValueKey('bulk-catalog-scope-disclosure'),
          summary: 'How a bulk change is applied',
          child: Text(
            key: ValueKey('bulk-catalog-scope'),
            'Nothing here happens until it has been shown to you first. Every '
            'change is previewed row by row, writes nothing while it is being '
            'previewed, and is then applied exactly as it was shown. Rows are '
            'sent $maximumBulkCatalogRows at a time, so a large change is '
            'several requests and the report says which of them landed.',
          ),
        ),
        if (offerCorrections) ...<Widget>[
          SizedBox(height: tokens.spacing.s16),
          FilterChipBar<_BulkTask>(
            semanticLabel: 'Which bulk change this is',
            selected: task,
            onSelected: (value) => value == null ? null : onTaskChanged(value),
            options: <FilterChipOption<_BulkTask>>[
              for (final option in _BulkTask.values)
                FilterChipOption<_BulkTask>(
                  key: ValueKey(
                    'bulk-catalog-task-'
                    '${option == _BulkTask.correct ? 'correct' : 'import'}',
                  ),
                  value: option,
                  label: option.label,
                  enabled: !busy,
                ),
            ],
          ),
        ],
        if (_unfinished case final unfinished?) ...[
          SizedBox(height: tokens.spacing.s16),
          // **`attention`, not `problem`.** Nothing has gone wrong that cannot
          // be put right from here, and every product the pages that landed
          // created is in the catalog and correct. What is outstanding is a
          // decision - finish it or forget it - and §2.1 puts work awaiting
          // somebody on the attention row.
          Callout(
            key: const ValueKey('bulk-catalog-unfinished'),
            status: AppStatus.attention,
            message:
                'An import of ${unfinished.rowCount} products stopped after '
                '${unfinished.pagesAnswered} of ${unfinished.pages.length} '
                'requests. Finish it here rather than importing the sheet '
                'again: finishing sends the same requests, so a page the '
                'server already recorded creates nothing, while a fresh '
                'import would create those products a second time.',
          ),
          SizedBox(height: tokens.spacing.s12),
          AppActionRow(
            actions: <Widget>[
              AppButton(
                key: const ValueKey('bulk-catalog-resume'),
                label:
                    'Finish it (${unfinished.remainingRowCount} products left)',
                icon: Icons.restart_alt,
                tier: AppButtonTier.primary,
                onPressed: busy ? null : onResumeImport,
              ),
              AppButton(
                key: const ValueKey('bulk-catalog-forget-attempt'),
                label: 'Forget it',
                tier: AppButtonTier.tertiary,
                onPressed: busy ? null : onDiscardAttempt,
              ),
            ],
          ),
        ],
        if (!_offered) ...[
          SizedBox(height: tokens.spacing.s12),
          // A notice about this build, so it does not fold. `info` is §2.1's
          // own row for it: the half that is missing was never injected, which
          // is not a failure and hides nothing.
          Callout(
            key: const ValueKey('bulk-catalog-unavailable'),
            status: AppStatus.info,
            message: task == _BulkTask.correct
                ? 'This build cannot correct products in bulk.'
                : 'This build cannot import products.',
          ),
        ],
        // **Every value of this one is a refusal, and the type now says so.**
        // It is set from exactly one place — a `TenantBulkCatalogException`
        // raised before anything was sent — so unlike the other six notices in
        // the family it has no success branch to distinguish. Carrying an
        // `AppNotice` rather than a `String?` is what makes that an invariant
        // a reader can see instead of one they have to trace the assignments
        // to establish.
        SizedBox(height: tokens.spacing.s24),
        if (task == _BulkTask.correct)
          ..._correctionForm(context)
        else
          ..._importForm(context),
        SizedBox(height: tokens.spacing.s20),
        // Keep the two decisions in one horizontal action row at every width.
        // a `Row`, and the first test to drive it at §4.1's `compact` band
        // overflowed by 73 pixels on a single button: "Preview, writing
        // nothing" carries a leading icon and §5.2's `space.16` padding, and
        // the discard beside it is another 48dp of control. The row is
        // identical wherever there is room and is the shape the difference list
        // and every paginated surface in this app already uses for a row of
        // controls.
        // Right-aligned since 2026-08-26, with every other action row in the
        // app: the control under a right-handed thumb is the one it presses.
        AppActionRow(
          actions: <Widget>[
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
    final tokens = AppTokens.componentOf(context);
    final categoryNames = tenantCategoryNames(view.categories.items);
    return <Widget>[
      SectionHeading('What to change'),
      SizedBox(height: tokens.spacing.s8),
      // **The one bar whose selection is a pair rather than a value.** Which
      // field moves and whether a cost is being *removed* are two variables in
      // this panel, and three of the four chips answer both at once - so the
      // pair is flattened into `_BulkFieldChoice` here, at the call site that
      // has the problem, and `FilterChipBar` stays a plain single selection.
      //
      // A price and a cost are money, and the server decides permission over
      // the union of every row's fields: one row naming either refuses the
      // whole request. So they are not offered at all rather than offered and
      // refused, which would teach a manager only that the app guesses.
      FilterChipBar<_BulkFieldChoice>(
        semanticLabel: 'Which field this change moves',
        selected: _BulkFieldChoice.of(field, clearCost: clearCost),
        onSelected: (value) => value == null
            ? null
            : onFieldChanged(value.field, clearsCost: value.clearsCost),
        options: <FilterChipOption<_BulkFieldChoice>>[
          for (final choice in _BulkFieldChoice.values)
            if (choice == _BulkFieldChoice.category || canChangeMoney)
              FilterChipOption<_BulkFieldChoice>(
                key: ValueKey('bulk-catalog-field-${choice.slug}'),
                value: choice,
                label: choice.label,
                enabled: !busy,
              ),
        ],
      ),
      if (!canChangeMoney) ...[
        SizedBox(height: tokens.spacing.s8),
        // A role notice at `info`, matching every other one in the catalog
        // family: three of the four corrections are offered and one is not.
        const Callout(
          key: ValueKey('bulk-catalog-money-hidden'),
          status: AppStatus.info,
          message:
              'Only an owner or administrator may change a price or what a '
              'product costs. One row naming either refuses every row in the '
              'same request, so neither is offered here.',
        ),
      ],
      SizedBox(height: tokens.spacing.s12),
      if (field == TenantProductField.categoryId) ...[
        if (view.categories.items.isEmpty)
          const Text(
            key: ValueKey('bulk-catalog-no-categories'),
            'This business has no categories yet, so there is nothing to file '
            'these products under.',
          )
        else
          FilterChipBar<String>(
            semanticLabel: 'The category these products move to',
            selected: valueCategoryId,
            onSelected: (value) =>
                value == null ? null : onCategoryChosen(value),
            options: <FilterChipOption<String>>[
              for (final category in view.categories.items)
                FilterChipOption<String>(
                  key: ValueKey('bulk-catalog-category-${category.id}'),
                  value: category.id,
                  label: category.name,
                  enabled: !busy,
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
      SizedBox(height: tokens.spacing.s20),
      // **The second `Row` on this route that had only ever been laid out
      // wide**, and unlike the first this one is wrong in a picture rather than
      // only in a widget test: at §4.1's `compact` band the count is squeezed
      // to two lines by two controls that take almost the whole width, which
      // the 411 harness capture shows. A `Wrap` keeps all three on one line
      // wherever there is room and drops the controls to their own run where
      // there is not.
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            key: const ValueKey('bulk-catalog-selection'),
            selected.isEmpty
                ? 'No products chosen.'
                : '${selected.length} product${selected.length == 1 ? '' : 's'} '
                      'chosen, across every page.',
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
      SizedBox(height: tokens.spacing.s12),
      Pagination(
        pageNumber: pageIndex + 1,
        previousKey: const ValueKey('bulk-catalog-previous-page'),
        pageKey: const ValueKey('bulk-catalog-page'),
        nextKey: const ValueKey('bulk-catalog-next-page'),
        onPrevious: pageIndex == 0 || busy ? null : onPreviousPage,
        onNext: view.products.hasMore && !busy ? onNextPage : null,
      ),
    ];
  }

  List<Widget> _importForm(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return <Widget>[
      // **The two doors the pre-multitenancy app had, in its order.** Take a
      // template, fill it in, bring it back. Pasting rows still works and is
      // still how a person with the sheet already open gets them in, but it is
      // no longer the only way and no longer the first thing offered.
      SectionHeading('Start from a template'),
      SizedBox(height: tokens.spacing.s4),
      const Text(
        key: ValueKey('bulk-catalog-template-help'),
        'Download the template, fill in one line per product in Excel or any '
        'spreadsheet, then choose the saved file here. A .csv or an .xlsx is '
        'read either way.',
      ),
      SizedBox(height: tokens.spacing.s12),
      AppActionRow(
        actions: <Widget>[
          if (canDownloadTemplate)
            AppButton(
              key: const ValueKey('bulk-catalog-template'),
              label: 'Download template',
              icon: Icons.download_outlined,
              tier: AppButtonTier.secondary,
              onPressed: busy ? null : onDownloadTemplate,
            ),
          if (canPickFile)
            AppButton(
              key: const ValueKey('bulk-catalog-choose-file'),
              label: 'Choose a file',
              icon: Icons.upload_file_outlined,
              tier: AppButtonTier.primary,
              onPressed: busy ? null : onChooseFile,
            ),
        ],
      ),
      if (pickedName case final name?) ...<Widget>[
        SizedBox(height: tokens.spacing.s12),
        // Which file the rows below came out of. A person who picks the wrong
        // export of three finds out here rather than in the report.
        Callout(
          key: const ValueKey('bulk-catalog-picked'),
          status: AppStatus.ok,
          message: 'Read from $name. Check the rows below, then preview.',
        ),
      ],
      SizedBox(height: tokens.spacing.s24),
      SectionHeading('The rows'),
      SizedBox(height: tokens.spacing.s8),
      // Three paragraphs of permanent helper prose behind one fold - §5.1's own
      // description of what `Disclosure` replaces, and the tallest single block
      // in the catalog family. It is true of every sheet this route will ever
      // read, and a person who has pasted one sheet does not read it again.
      const Disclosure(
        key: ValueKey('bulk-catalog-sheet-help-disclosure'),
        summary: 'What the sheet must look like',
        child: Text(
          key: ValueKey('bulk-catalog-sheet-help'),
          'These are the rows that will be imported, whether they were read '
          'out of a file or pasted in. Columns may be separated by commas, '
          'tabs, or semicolons, and a cell holding one of those can be '
          'wrapped in '
          'double quotes.\n\n'
          'The header must name name, sku, and price. It may also name cost, '
          'quantity, and either category — the category\'s own name, matched '
          'against this business — or categoryId. A column this import does '
          'not read is refused rather than ignored, so nothing you supplied is '
          'dropped without being mentioned.\n\n'
          'A category that does not already exist refuses its row: add it on '
          '"Manage catalog" first. An opening quantity is recorded as an '
          'opening balance in the stock ledger, so those units have a stated '
          'origin.',
        ),
      ),
      SizedBox(height: tokens.spacing.s12),
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
        SizedBox(height: tokens.spacing.s8),
        const Callout(
          key: ValueKey('bulk-catalog-import-cost-hidden'),
          status: AppStatus.info,
          message:
              'Only an owner or administrator may record what a product costs, '
              'so a cost column is refused. A price is not: setting a first '
              'price is creation, and the add-product form accepts one too.',
        ),
      ],
    ];
  }

  List<Widget> _reportSection(
    BuildContext context,
    TenantBulkCatalogReport report,
  ) {
    final tokens = AppTokens.componentOf(context);
    return <Widget>[
      SizedBox(height: tokens.spacing.s24),
      SectionHeading('What this does'),
      SizedBox(height: tokens.spacing.s8),
      Text(key: const ValueKey('bulk-catalog-summary'), _summary(report, task)),
      if (report.failure case final failure?) ...[
        SizedBox(height: tokens.spacing.s8),
        // The one `problem` in the catalog family, and it is the only notice in
        // it that reports a failure: a chain that stopped. Every value of
        // [TenantBulkCatalogFailure] means the same thing at this scale - the
        // rest of the request was not sent - so all eight take one status
        // rather than one of them being separated out on a reading §2.1 does
        // not support. `ambiguous` is the arguable one and it is deliberately
        // here: an unknown outcome is not `attention`'s "awaiting", because
        // nothing further is coming.
        Callout(
          key: const ValueKey('bulk-catalog-report-failure'),
          status: AppStatus.problem,
          message: _failureNotice(failure, report),
        ),
      ],
      SizedBox(height: tokens.spacing.s12),
      // Every row, never a count. The server names every broken row at once, and
      // collapsing that into "12 rows failed" would throw away the reason both
      // callables report per row.
      //
      // **The status was a word in the title and is now §2.1's container.** A
      // report genuinely mixes its four outcomes - that is what makes it worth
      // reading row by row - so a badge here carries signal rather than being
      // the every-row badge `RecordList`'s own rule rules out. The card is
      // still a card: screen 20 is not one of the twelve screens step 6 names,
      // and migrating it to `RecordList` would be step 6 work outside step 6's
      // list, exactly as it would be on the differences list.
      for (final row in report.rows)
        Card(
          key: ValueKey('bulk-catalog-row-${row.position}'),
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // §5.2's "leading position", read as first in the record - the
                // reading `RecordList` settled and the shape both catalog
                // screens already draw.
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(
                    key: ValueKey('bulk-catalog-row-status-${row.position}'),
                    status: _rowStatus(row.status, report.mode),
                    label: _rowLabel(row.status, report.mode),
                    semanticLabel:
                        '${row.subject}: '
                        '${_rowLabel(row.status, report.mode).toLowerCase()}',
                  ),
                ),
                SizedBox(height: tokens.spacing.s8),
                Text(
                  key: ValueKey('bulk-catalog-row-subject-${row.position}'),
                  row.subject,
                  style: tokens.typography.titleMedium.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                ),
                Text(
                  key: ValueKey('bulk-catalog-row-detail-${row.position}'),
                  '${task == _BulkTask.correct ? 'Product' : 'Line'} '
                  '${row.position} • ${row.detail}',
                ),
              ],
            ),
          ),
        ),
      SizedBox(height: tokens.spacing.s16),
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

/// Which field a bulk correction moves, with "remove the unit cost" flattened
/// into the same list.
///
/// **A pair, made into a value, because `FilterChipBar` selects one thing.**
/// The panel holds a `TenantProductField` *and* a `clearCost` flag, and three
/// of the four chips set both - `cost` with the flag off and `cost` with it on
/// are different chips answering the same field. Modelling that as a mode
/// inside the component would put a two-variable selection into every other
/// filter bar in the app to serve one screen.
enum _BulkFieldChoice {
  category(TenantProductField.categoryId, false, 'categoryId', 'Category'),
  price(TenantProductField.price, false, 'price', 'Unit price'),
  cost(TenantProductField.cost, false, 'cost', 'Unit cost'),
  clearCost(
    TenantProductField.cost,
    true,
    'clear-cost',
    'Remove the unit cost',
  );

  const _BulkFieldChoice(this.field, this.clearsCost, this.slug, this.label);

  final TenantProductField field;
  final bool clearsCost;

  /// The key fragment each chip already carried, kept so the screen's tests
  /// keep addressing the control they were written about.
  final String slug;
  final String label;

  static _BulkFieldChoice of(
    TenantProductField field, {
    required bool clearCost,
  }) => switch (field) {
    TenantProductField.price => _BulkFieldChoice.price,
    TenantProductField.cost =>
      clearCost ? _BulkFieldChoice.clearCost : _BulkFieldChoice.cost,
    // `categoryId` and `name`. **`name` has no chip and is not reachable
    // here** - a bulk change never moves a product's name, which is why the
    // four chips above are four rather than five - so it falls in with the
    // category rather than being a case that asserts. A wildcard is the honest
    // shape: this maps the *offered* fields and the compiler is telling the
    // truth that the enum is wider than the offer.
    _ => _BulkFieldChoice.category,
  };
}

/// One report row's outcome, as one of §2.1's five.
///
/// **Two of the four are the same in both modes and two are not, and reading the
/// mode is what keeps the badge honest.** A refused row is refused whether or not
/// anything was committed - the client or the server will not write it either
/// way - so it is §2.1's `problem` in both. An unchanged row already holds the
/// value in both. But a row a *preview* calls created or corrected has not been
/// written and may never be, and §2.1 gives `ok` the meaning *"confirmed"*: a
/// green badge over a report whose own first sentence is "Nothing has been
/// written" would be this file stating the opposite of the sentence above it.
/// §2.1's `attention` is *"unreconciled, pending, awaiting"*, and a previewed row
/// is precisely awaiting the commit button below it.
///
/// `unchanged` takes `neutral` - *"archived, retired, closed"* - because the row
/// is not in play. It is deliberately not `info`: `info` is what this route uses
/// for a notice about the page, and one status meaning two things at two scales
/// is the failure §2.1 exists to end.
///
/// ~~**What the badge cannot fix is the word beside it.**~~ **Fixed by step 11 on
/// 2026-08-15** - see [_rowLabel], which reads the mode on exactly the two
/// outcomes this function does, and for the same reason.
AppStatus _rowStatus(
  TenantBulkCatalogRowStatus status,
  TenantBulkCatalogMode mode,
) => switch (status) {
  TenantBulkCatalogRowStatus.created || TenantBulkCatalogRowStatus.updated =>
    mode == TenantBulkCatalogMode.preview ? AppStatus.attention : AppStatus.ok,
  TenantBulkCatalogRowStatus.unchanged => AppStatus.neutral,
  TenantBulkCatalogRowStatus.failed => AppStatus.problem,
};

/// One report row's outcome in words, in the tense the mode has earned.
///
/// **§8 rule 2 - state what is true - and it divides the four exactly where
/// [_rowStatus] divides them.** `Unchanged` and `Refused` are true in both modes:
/// a row that already holds the value holds it whether or not anything was
/// committed, and a row the server will not write is refused either way. But
/// `Created` and `Corrected` are past tense, and a preview writes nothing - so a
/// previewed row claimed a product existed on a report whose own first sentence
/// is "Nothing has been written."
///
/// The conditional wording is `_summary`'s own, one flight up, rather than a
/// second phrasing of one idea: that sentence has said *would be created* and
/// *would be corrected* since it was written, and §8 rule 4 is that the verb
/// persists across a page.
String _rowLabel(
  TenantBulkCatalogRowStatus status,
  TenantBulkCatalogMode mode,
) {
  final preview = mode == TenantBulkCatalogMode.preview;
  // The applied word stays the enum's own, so this function adds a tense rather
  // than a second vocabulary - two places spelling one outcome is the drift the
  // shared wording modules exist to end.
  return switch (status) {
    TenantBulkCatalogRowStatus.created =>
      preview ? 'Would be created' : status.label,
    TenantBulkCatalogRowStatus.updated =>
      preview ? 'Would be corrected' : status.label,
    TenantBulkCatalogRowStatus.unchanged ||
    TenantBulkCatalogRowStatus.failed => status.label,
  };
}

/// One sentence stating what the report is, before any row is read.
///
/// **Every count here agrees with its verb as of step 11, 2026-08-15.** A report
/// over one product read "1 were corrected, 1 already hold this value" - which is
/// the commonest shape this screen has, because a person correcting a single
/// mistyped price is the reason the route exists. Zero takes the plural, so the
/// test is `== 1` rather than `> 1`.
String _summary(TenantBulkCatalogReport report, _BulkTask task) {
  final buffer = StringBuffer();
  final preview = report.mode == TenantBulkCatalogMode.preview;
  if (preview) {
    buffer.write('Nothing has been written. ');
  }
  if (task == _BulkTask.correct) {
    final verb = preview
        ? 'would be corrected'
        : _agrees(report.updatedCount, 'corrected');
    buffer.write(
      '${report.updatedCount} $verb, ${report.unchangedCount} '
      '${report.unchangedCount == 1 ? 'already holds' : 'already hold'} '
      'this value, and ${report.failedCount} cannot be.',
    );
  } else {
    final verb = preview
        ? 'would be created'
        : _agrees(report.createdCount, 'created');
    buffer.write(
      '${report.createdCount} $verb and ${report.failedCount} cannot be.',
    );
  }
  if (report.pageCount > 1) {
    // The subject is "one of three requests", which is singular - the noun
    // agrees with the total and the verb with the count answered.
    final answered = preview
        ? _agrees(report.pagesAnswered, 'previewed')
        : 'landed';
    buffer.write(
      ' ${report.pagesAnswered} of ${report.pageCount} requests $answered.',
    );
  }
  return buffer.toString();
}

/// `was` or `were` before a past participle, agreeing with [count].
String _agrees(int count, String participle) =>
    '${count == 1 ? 'was' : 'were'} $participle';

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
        '\n\nEvery grouped report and every register filter follows the new '
        'category from now on. Figures already recorded are not regrouped.',
      );
    case TenantProductField.name:
    case TenantProductField.sku:
    case TenantProductField.image:
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
