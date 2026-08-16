/// `ShiftBanner` and `SyncIndicator`, per `claude.md` hard rule 5 and §10 — and
/// the only pictures of the two components `design.md` §5.2 gained in v0.7 from
/// the product owner's own drawings.
///
/// **The banner's three states are the three a shift is actually in**, which is
/// why they are named here rather than enumerated from `AppStatus`: a shift is
/// never `info` and never `neutral`, and photographing five states for a control
/// that has three would be photographing the component rather than the screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/banner.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_application_1/ui/sync_indicator.dart';
import 'package:flutter_application_1/ui/tokens.dart';

import 'harness.dart';

void main() {
  screenshotCase(
    '98-shiftbanner-three-states',
    build: _Banners.new,
    fullPage: false,
  );

  screenshotCase(
    '98-syncindicator-button',
    build: _Buttons.new,
    fullPage: false,
  );

  screenshotCase(
    '98-syncindicator-panel',
    build: _Panel.new,
    fullPage: false,
  );
}

final class _Banners extends StatelessWidget {
  const _Banners();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return _Sheet(
      title: 'ShiftBanner - three states',
      children: <Widget>[
        ShiftBanner(
          status: AppStatus.neutral,
          heading: 'No shift open',
          detail: 'Sales can be recorded, but nothing counts to a drawer yet.',
          action: AppButton(
            label: 'Open shift',
            tier: AppButtonTier.primary,
            onPressed: () {},
          ),
          onOpenDetails: () {},
        ),
        SizedBox(height: tokens.spacing.s16),
        ShiftBanner(
          status: AppStatus.ok,
          heading: 'Shift open',
          detail: 'Opened 07:12 UTC. 17 sales, KES 4,220.00 recorded.',
          action: AppButton(label: 'Count cash', onPressed: () {}),
          onOpenDetails: () {},
        ),
        SizedBox(height: tokens.spacing.s16),
        ShiftBanner(
          status: AppStatus.attention,
          heading: 'Cash count unfinished',
          detail:
              'Expected KES 4,220.00 over 17 sales. Finish it before '
              'switching shop.',
          action: AppButton(
            label: 'Close shift',
            tier: AppButtonTier.primary,
            onPressed: () {},
          ),
          onOpenDetails: () {},
        ),
      ],
    );
  }
}

final class _Buttons extends StatelessWidget {
  const _Buttons();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return _Sheet(
      title: 'SyncIndicator - clear, waiting, needing attention',
      children: <Widget>[
        Row(
          children: <Widget>[
            SyncIndicator(waiting: 0, onOpen: () {}),
            SizedBox(width: tokens.spacing.s24),
            SyncIndicator(waiting: 2, onOpen: () {}),
            SizedBox(width: tokens.spacing.s24),
            SyncIndicator(waiting: 3, needsAttention: true, onOpen: () {}),
          ],
        ),
      ],
    );
  }
}

final class _Panel extends StatelessWidget {
  const _Panel();

  @override
  Widget build(BuildContext context) => _Sheet(
    title: 'SyncQueuePanel',
    children: <Widget>[
      SyncQueuePanel(
        title: 'Checkouts on this device',
        onClose: () {},
        entries: const <SyncQueueEntry>[
          SyncQueueEntry(
            label: 'Saved offline',
            count: 2,
            status: AppStatus.attention,
          ),
          SyncQueueEntry(label: 'Submitting', count: 0),
          SyncQueueEntry(label: 'Awaiting confirmation', count: 0),
          SyncQueueEntry(label: 'Needs attention', count: 0),
          SyncQueueEntry(label: 'Confirmed', count: 11),
        ],
        explanation: const Disclosure(
          summary: 'Why can I not send these?',
          child: Text(
            'This device sends them on its own as soon as it can reach the '
            'server. There is nothing to press, and a sale is never lost by '
            'waiting.',
          ),
        ),
      ),
    ],
  );
}

final class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Scaffold(
      backgroundColor: tokens.colors.surface.base,
      body: Padding(
        padding: EdgeInsets.all(tokens.spacing.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              style: tokens.typography.titleMedium.copyWith(
                color: tokens.colors.text.primary,
              ),
            ),
            SizedBox(height: tokens.spacing.s16),
            ...children,
          ],
        ),
      ),
    );
  }
}
