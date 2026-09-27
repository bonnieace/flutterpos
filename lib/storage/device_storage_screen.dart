import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/scaffold.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'device_storage.dart';

/// The whole app, for as long as one startup store will not open.
///
/// It is its own [MaterialApp] because it runs before the real one exists:
/// the stores it asks about are what the real app is built from. [attempt]
/// keys it, so each new question starts with fresh buttons rather than the
/// busy state of the answer to the last one.
final class DeviceStorageProblemApp extends StatelessWidget {
  DeviceStorageProblemApp({
    required this.theme,
    required this.store,
    required this.canContinue,
    required this.onChoice,
    required int attempt,
  }) : super(key: ValueKey<int>(attempt));

  final ThemeData theme;
  final DeviceStore store;
  final bool canContinue;
  final ValueChanged<DeviceStorageChoice> onChoice;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    home: DeviceStorageProblemScreen(
      store: store,
      canContinue: canContinue,
      onChoice: onChoice,
    ),
  );
}

/// Says which store could not be opened, and lets whoever holds the phone
/// try again or carry on without it.
///
/// **Anyone holding the phone may continue**, at the product owner's direction
/// on 2026-09-27: nobody is signed in this early, and a till that cannot open
/// must not wait for a manager. What protects the data is that continuing sets
/// the file aside rather than deleting it, and that [DeviceStore.loss] is read
/// out in a confirmation before anything happens.
final class DeviceStorageProblemScreen extends StatefulWidget {
  const DeviceStorageProblemScreen({
    super.key,
    required this.store,
    required this.canContinue,
    required this.onChoice,
  });

  final DeviceStore store;
  final bool canContinue;
  final ValueChanged<DeviceStorageChoice> onChoice;

  @override
  State<DeviceStorageProblemScreen> createState() =>
      _DeviceStorageProblemScreenState();
}

class _DeviceStorageProblemScreenState
    extends State<DeviceStorageProblemScreen> {
  DeviceStorageChoice? _chosen;

  void _choose(DeviceStorageChoice choice) {
    if (_chosen != null) return;
    setState(() => _chosen = choice);
    widget.onChoice(choice);
  }

  Future<void> _confirmContinue() async {
    final store = widget.store;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Continue without ${store.title.toLowerCase()}?',
      consequence: store.loss,
      stillTrue:
          'The unreadable file stays on this phone, so it may still be '
          'recovered later.',
      confirmLabel: 'Continue without it',
      cancelLabel: 'Go back',
      confirmKey: const ValueKey<String>('device-storage-confirm'),
    );
    if (confirmed && mounted) _choose(DeviceStorageChoice.continueWithout);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final busy = _chosen != null;
    final retry = AppButton(
      key: const ValueKey<String>('device-storage-retry'),
      label: 'Try again',
      tier: AppButtonTier.primary,
      loading: _chosen == DeviceStorageChoice.retry,
      onPressed: busy ? null : () => _choose(DeviceStorageChoice.retry),
    );
    return AppScaffold(
      title: 'This phone could not open its data',
      contentWidth: AppContentWidth.reading,
      automaticallyImplyLeading: false,
      body: ListView(
        padding: EdgeInsets.all(tokens.spacing.s24),
        children: <Widget>[
          Callout(
            status: AppStatus.problem,
            icon: Icons.sd_card_alert_outlined,
            title: widget.store.title,
            message: widget.canContinue
                ? 'The app could not read what it keeps on this phone for '
                      'this. Nothing has been deleted.'
                : 'This phone’s secure key storage did not answer, so nothing '
                      'it protects can be read yet. Nothing has been deleted.',
          ),
          SizedBox(height: tokens.spacing.s16),
          Text(
            widget.canContinue
                ? 'Try again first. If it keeps failing, you can carry on '
                      'without it: ${widget.store.loss}'
                : 'Try again. If it keeps failing, restart the phone and open '
                      'the app again.',
            style: tokens.density
                .body(tokens.typography)
                .copyWith(color: tokens.colors.text.secondary),
          ),
          SizedBox(height: tokens.spacing.s24),
          AppActionRow(
            alignment: MainAxisAlignment.start,
            actions: <Widget>[
              retry,
              if (widget.canContinue)
                AppButton(
                  key: const ValueKey<String>('device-storage-continue'),
                  label: 'Continue without it',
                  tier: AppButtonTier.destructive,
                  loading: _chosen == DeviceStorageChoice.continueWithout,
                  onPressed: busy ? null : _confirmContinue,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
