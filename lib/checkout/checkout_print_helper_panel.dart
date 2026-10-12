/// The print helper, on the Printer page of a web till on Windows: whether it
/// is running here, the download when it is not, and removing it when it is.
///
/// **Looking for it is what turns it on.** The card asks the helper who it is
/// as the page opens; an answer is remembered in this browser, and from then
/// on receipts to network and USB printers go its way. Until the helper has
/// been found, nothing at the counter knocks on this computer's door - see
/// `checkout_print_helper.dart`.
///
/// **Removing it is asked of the helper itself**, because a page cannot
/// delete a program: it stops, takes itself out of Windows' start-up and
/// *Apps* list, and its folder goes a moment later. A helper from before it
/// could do that (1.0.3 and earlier) is sent to Windows' *Apps* list instead.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../observability/app_telemetry.dart';
import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/dialogs.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'checkout_print_helper.dart';

/// Everything the card needs from the composition root.
final class PrintHelperSetup {
  const PrintHelperSetup({
    required this.helper,
    required this.memory,
    required this.download,
  });

  final PrintHelper helper;
  final PrintHelperMemory memory;

  /// Starts the helper's download. Injected so a test downloads nothing.
  final Future<void> Function() download;
}

/// What a look for the helper found.
enum _Look { looking, running, absent }

final class PrintHelperCard extends StatefulWidget {
  const PrintHelperCard({super.key, required this.setup, this.onLooked});

  final PrintHelperSetup setup;

  /// Called after every look with whether the helper answered, so a tab can
  /// ask it what it can print to - or say that it is not here yet.
  final ValueChanged<bool>? onLooked;

  /// How often the card looks again once the download was pressed.
  static const Duration watchEvery = Duration(seconds: 3);

  /// How long it keeps looking: long enough to download, get past Windows'
  /// warning and run it, without asking the helper forever.
  static const Duration watchFor = Duration(minutes: 10);

  @override
  State<PrintHelperCard> createState() => _PrintHelperCardState();
}

class _PrintHelperCardState extends State<PrintHelperCard> {
  _Look _look = _Look.looking;
  String? _version;

  /// Set once the download was pressed, so the steps that follow it show.
  bool _downloaded = false;

  /// Looking again by itself, after the download, so starting the helper is
  /// the last thing anybody has to do.
  Timer? _watch;

  /// The helper is being asked to remove itself.
  bool _removing = false;

  /// Why the running helper could not be removed from here, until it is asked
  /// again.
  PrintHelperRemoval? _notRemoved;

  @override
  void initState() {
    super.initState();
    unawaited(_lookForHelper());
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  /// Asks the helper who it is. [quietly] keeps the card as it is while it
  /// asks, which is how the watch looks without flickering.
  Future<void> _lookForHelper({bool quietly = false}) async {
    if (!quietly) setState(() => _look = _Look.looking);
    final version = await widget.setup.helper.version();
    if (!mounted) return;
    if (version != null) {
      widget.setup.memory.markSeen();
      _watch?.cancel();
    }
    if (quietly && version == null) return;
    setState(() {
      _version = version;
      _look = version == null ? _Look.absent : _Look.running;
    });
    widget.onLooked?.call(version != null);
  }

  Future<void> _download() async {
    try {
      await widget.setup.download();
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'printing.helper_download',
      );
      return;
    }
    if (!mounted) return;
    setState(() => _downloaded = true);
    _watch?.cancel();
    final until = DateTime.now().add(PrintHelperCard.watchFor);
    _watch = Timer.periodic(PrintHelperCard.watchEvery, (timer) {
      if (DateTime.now().isAfter(until)) {
        timer.cancel();
        return;
      }
      unawaited(_lookForHelper(quietly: true));
    });
  }

  Future<void> _remove() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove the print helper?',
      consequence:
          'It stops and is removed from this computer. Receipts from this '
          'browser are not printed on network or USB printers until it is '
          'installed again.',
      stillTrue:
          'Sales are recorded as normal, and the printer settings stay as '
          'they are.',
      confirmLabel: 'Remove',
      confirmKey: const ValueKey('print-helper-remove-confirm'),
      cancelKey: const ValueKey('print-helper-remove-cancel'),
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _removing = true;
      _notRemoved = null;
    });
    final outcome = await widget.setup.helper.remove();
    if (!mounted) return;
    if (outcome != PrintHelperRemoval.removed) {
      setState(() {
        _removing = false;
        _notRemoved = outcome;
      });
      return;
    }
    widget.setup.memory.forget();
    setState(() {
      _removing = false;
      _version = null;
      _downloaded = false;
      _look = _Look.absent;
    });
    widget.onLooked?.call(false);
    showAppSnackBar(
      context,
      const AppNotice.confirmed(
        'The print helper was removed from this '
        'computer.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return switch (_look) {
      _Look.looking => const Callout(
        key: ValueKey('print-helper-looking'),
        status: AppStatus.info,
        icon: Icons.print_outlined,
        message: 'Looking for the print helper on this computer…',
      ),
      _Look.running => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Callout(
            key: const ValueKey('print-helper-running'),
            status: AppStatus.ok,
            icon: Icons.print_outlined,
            title: 'Print helper is running',
            message:
                'Version $_version. Receipts from this browser go through it '
                'to network and USB printers.',
            action: AppButton(
              key: const ValueKey('print-helper-remove'),
              label: 'Remove print helper',
              icon: Icons.delete_outline,
              tier: AppButtonTier.secondary,
              loading: _removing,
              onPressed: _remove,
            ),
          ),
          if (_notRemoved case final outcome?) ...<Widget>[
            SizedBox(height: tokens.spacing.s8),
            Callout(
              key: const ValueKey('print-helper-not-removed'),
              status: AppStatus.attention,
              message: outcome == PrintHelperRemoval.outdated
                  ? 'This print helper is too old to remove from here. Open '
                        'Windows Settings, then Apps, and uninstall “UzaPay '
                        'print helper”.'
                  : 'The print helper did not answer, so it was not removed. '
                        'Try again, or open Windows Settings, then Apps, and '
                        'uninstall “UzaPay print helper”.',
            ),
          ],
        ],
      ),
      _Look.absent => AppCard(
        key: const ValueKey('print-helper-absent'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Install the print helper',
              style: tokens.typography.titleMedium.copyWith(
                color: tokens.colors.text.primary,
              ),
            ),
            SizedBox(height: tokens.spacing.s4),
            Text(
              'A browser cannot print to a receipt printer by itself. Install '
              'this once on this computer and it prints for UzaPay from then '
              'on, starting with Windows.',
              style: tokens.typography.bodyMedium.copyWith(
                color: tokens.colors.text.secondary,
              ),
            ),
            if (_downloaded) ...<Widget>[
              SizedBox(height: tokens.spacing.s12),
              const Callout(
                key: ValueKey('print-helper-steps'),
                status: AppStatus.info,
                message:
                    'Open the downloaded file. If Windows says it protected '
                    'your PC, choose More info, then Run anyway. This page '
                    'notices by itself when the helper is running.',
              ),
            ],
            SizedBox(height: tokens.spacing.s16),
            AppActionRow(
              expandActions: true,
              actions: <Widget>[
                AppButton(
                  key: const ValueKey('print-helper-check'),
                  label: 'Check again',
                  tier: AppButtonTier.secondary,
                  expand: true,
                  onPressed: () => _lookForHelper(),
                ),
                AppButton(
                  key: const ValueKey('print-helper-download'),
                  label: 'Download print helper',
                  icon: Icons.download_outlined,
                  tier: AppButtonTier.primary,
                  expand: true,
                  onPressed: _download,
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.s8),
            const Disclosure(
              key: ValueKey('print-helper-about'),
              summary: 'What the print helper does',
              child: _About(),
            ),
          ],
        ),
      ),
    };
  }
}

final class _About extends StatelessWidget {
  const _About();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final style = tokens.typography.bodyMedium.copyWith(
      color: tokens.colors.text.secondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'A small program for Windows that sends this browser’s receipts to '
          'the printer, which a browser cannot do by itself. It installs for '
          'you alone, needs no administrator, and starts with Windows.',
          style: style,
        ),
        SizedBox(height: tokens.spacing.s8),
        Text(
          'It prints only what UzaPay sends it, and only to printers plugged '
          'into this computer or on this shop’s own network.',
          style: style,
        ),
        SizedBox(height: tokens.spacing.s8),
        Text(
          'To remove it, open Windows Settings, then Apps, and uninstall '
          '“UzaPay print helper”.',
          style: style,
        ),
      ],
    );
  }
}
