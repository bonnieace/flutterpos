/// The trailing toolbar control that starts a report.
///
/// **It goes in `AppScaffold.actions`, not `primaryAction`.** The split is
/// load-bearing: `primaryAction` is what the page exists for, and none of these
/// seven pages exists to produce a file - they exist to be read, and taking a
/// copy away is something you may also want to do.
///
/// **A null run renders nothing at all.** This is the
/// `canDownloadTemplate: widget.sheetSaver != null` gate generalised: a build
/// with no saver wired, or a role that may not read the records behind a
/// report, gets no control rather than a control that does nothing when
/// pressed. A button that fails silently is worse than an absent one.
library;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/observability/app_telemetry.dart';

import '../../tenancy/tenant_session.dart';
import '../../tenancy/tenant_session_controller.dart';
import '../../ui/buttons.dart';
import '../../ui/snackbar.dart';
import '../../ui/tokens.dart';
import '../report_file.dart';
import '../report_run.dart';
import 'report_sheet.dart';

/// The same control, for a page whose scaffold sits above its session guard.
///
/// **Expenses builds its action inside the guard and hands it up; four of the
/// seven pages cannot.** Their `AppScaffold` is on the route widget and the
/// guard is inside the panel below it, so there is no session in scope where
/// the toolbar is built. Threading one up through two or three widget layers
/// is what the staff directory had to do, and doing it four more times would
/// put the plumbing in more places than the feature.
///
/// So this resolves the session itself, from the scope the routing shell
/// already installs above every route. **No session means no control** - the
/// same rule a null run follows, and the honest one while a route is still
/// deciding whether the person may be here at all.
///
/// [runFor] is called with the session rather than closing over one, so the
/// report is always built against the session that is live at the moment the
/// person asks for it rather than the one that was live when the page opened.
final class TenantSessionReportAction extends StatelessWidget {
  const TenantSessionReportAction({
    super.key,
    required this.runFor,
    required this.clock,
  });

  /// Builds the run for the live session, or null where this person gets no
  /// report.
  final TenantReportRun? Function(TenantSession session) runFor;

  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    final session = TenantSessionScope.of(context).session;
    if (session == null) return const SizedBox.shrink();
    return TenantReportAction(run: runFor(session), clock: clock);
  }
}

/// Opens the report picker for one screen's records.
final class TenantReportAction extends StatefulWidget {
  const TenantReportAction({super.key, required this.run, required this.clock});

  /// The report this screen offers. Null renders nothing.
  final TenantReportRun? run;

  /// Injected so a test and a report generated at midnight agree about which
  /// business day "today" is.
  final DateTime Function() clock;

  @override
  State<TenantReportAction> createState() => _TenantReportActionState();
}

final class _TenantReportActionState extends State<TenantReportAction> {
  bool _working = false;

  Future<void> _start() async {
    final run = widget.run;
    if (run == null || _working) return;

    final request = await showTenantReportSheet(
      context,
      kind: run.kind,
      support: run.support,
      subject: run.subject,
      clock: widget.clock,
    );
    if (request == null || !mounted) return;

    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'reports.export',
      screen: 'reports',
      context: {
        'report_kind': run.kind.slug,
        'format': request.format.name,
        'destination': request.destination.name,
        'subject_id': request.subject?.id,
      },
    );
    setState(() => _working = true);
    try {
      final outcome = await run.deliver(
        request,
        telemetryOperation: operation,
        onStage: (stage) {
          telemetry.recordStep(operation, stage.name);
        },
      );
      if (outcome == TenantReportSaveOutcome.saved) {
        telemetry.recordStep(operation, 'confirmed');
        telemetry.finishOperation(operation);
      } else if (outcome == TenantReportSaveOutcome.dismissed) {
        telemetry.recordStep(operation, 'cancelled');
      } else {
        AppTelemetry.captureHandled(
          StateError('export_unavailable'),
          StackTrace.current,
          operation: operation,
          code: 'unavailable',
        );
      }
      if (!mounted) return;
      showAppSnackBar(
        context,
        tenantReportNotice(outcome, run.kind, destination: request.destination),
      );
    } on Object catch (error, stack) {
      AppTelemetry.captureHandled(
        error,
        stack,
        operation: operation,
        boundary: 'reports.export',
      );
      // **Logged as well as said.** The sentence below is what the person
      // needs; it is deliberately not the exception, because an operator
      // cannot act on a `StateError` and should not be shown one. But a
      // failure that is only ever shown as prose is a failure nobody can
      // diagnose from a device, which is exactly the position this was in the
      // first time a report refused to build on a phone.
      debugPrint('Report ${run.kind.slug} failed: $error');
      debugPrintStack(stackTrace: stack);
      if (!mounted) return;
      // **Said plainly, and the period is not claimed.** A report that could
      // not be read must not leave behind a half-built file or a sentence
      // implying one exists somewhere.
      showAppSnackBar(context, tenantReportFailureNotice(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.run == null) return const SizedBox.shrink();

    // **It says its name from 1024 up** (`docs/design/topbar-inner/`): an
    // unlabelled glyph a desktop's width away from the title is a guess.
    // The same press, the same busy state; a secondary 40 in its 48 target.
    final tokens = AppTokens.componentOf(context);
    if (MediaQuery.sizeOf(context).width >= tokens.layout.expandedFloor) {
      return Center(
        child: AppButton(
          key: ValueKey('report-action-${widget.run!.kind.slug}'),
          label: 'Report',
          icon: Icons.summarize_outlined,
          tier: AppButtonTier.secondary,
          size: AppButtonSize.md,
          loading: _working,
          onPressed: _working ? null : _start,
        ),
      );
    }

    return AppIconButton(
      key: ValueKey('report-action-${widget.run!.kind.slug}'),
      icon: Icons.summarize_outlined,
      semanticLabel: 'Download a ${widget.run!.kind.title.toLowerCase()}',
      bordered: false,
      tier: AppButtonTier.tertiary,
      loading: _working,
      onPressed: _working ? null : _start,
    );
  }
}
