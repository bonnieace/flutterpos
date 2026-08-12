/// Step 6's first half: `design.md` §4.2's content widths, photographed.
///
/// **The matrix of a layout contract is not §5's nine states.** A max content
/// width has no hover, no press and nothing to disable - it is not a control.
/// What varies is the two dimensions the contract itself has: **which of §4.2's
/// three rows a page declares**, and **which of §4.1's bands the window is in**.
/// Each of the three rows is captured at both viewports, which is that matrix in
/// full at six pictures.
///
/// **The mobile half is the more important one and is the easiest to skip.**
/// 411 is narrower than every maximum §4.2 states, so all three rows must look
/// *identical* there - a constraint that fires on a phone would be a constraint
/// that had been written as a fixed width by mistake. The three mobile images
/// being interchangeable is the evidence, and it is why `full` is captured at
/// all rather than only described.
///
/// **What the web half shows is the defect §4.2 was written about.** `full` is
/// the app as it was before this step: a record row 1,400 pixels wide with its
/// identity at one end and its actions at the other. `records` is the same rows
/// at 1200, and `reading` is what a form gets.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/fields.dart';
import 'package:flutter_application_1/ui/scaffold.dart';
import 'package:flutter_application_1/ui/tokens.dart';

import 'harness.dart';

/// A record row with its identity at one end and its actions at the other.
///
/// **Deliberately the shape §5.2 names as failing.** The catalog's product row
/// is a `ListTile` whose `trailing` pins to the right edge of whatever it is
/// laid out in, which at 1440 puts *Correct* 1,300 pixels from the name it
/// belongs to. Reproducing that shape is the only way a picture can show what
/// constraining the page buys; closing the rest of the distance is
/// `RecordList`'s job in the second half of this step.
class _Row extends StatelessWidget {
  const _Row({required this.name, required this.detail});

  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.s12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.colors.surface.raised,
          border: Border.all(color: tokens.colors.surface.borderSubtle),
          borderRadius: BorderRadius.circular(tokens.radius.md),
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      style: tokens.typography.titleMedium.copyWith(
                        color: tokens.colors.text.primary,
                      ),
                    ),
                    SizedBox(height: tokens.spacing.s4),
                    Text(
                      detail,
                      style: tokens.typography.numericBody.copyWith(
                        color: tokens.colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppButton(
                label: 'Correct',
                tier: AppButtonTier.secondary,
                size: AppButtonSize.sm,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The record list every screen in step 6's list is some version of.
class _Records extends StatelessWidget {
  const _Records();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s20),
      children: const <Widget>[
        _Row(name: 'Fresh whole milk 500ml', detail: 'KES 65.00 · 24 in stock'),
        _Row(name: 'White bread, sliced', detail: 'KES 70.00 · 11 in stock'),
        _Row(name: 'Cooking oil 1L', detail: 'KES 320.00 · 6 in stock'),
        _Row(name: 'Sugar 1kg', detail: 'KES 180.00 · 40 in stock'),
        _Row(name: 'Maize flour 2kg', detail: 'KES 210.00 · 18 in stock'),
      ],
    );
  }
}

/// A form, which is §4.2's other named row.
class _Form extends StatelessWidget {
  const _Form();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s20),
      children: <Widget>[
        const AppTextField(
          label: 'Currency code',
          helper: 'Three letters, as the shop writes them on a receipt.',
          placeholder: 'KES',
        ),
        SizedBox(height: tokens.density.sectionGap),
        const AppTextField(
          label: 'Receipt footer',
          helper: 'Printed under every receipt this business issues.',
          placeholder:
              'Thank you. Goods once sold may be returned within 7 days.',
        ),
        SizedBox(height: tokens.density.sectionGap),
        AppButton(
          label: 'Publish these settings',
          tier: AppButtonTier.primary,
          onPressed: () {},
        ),
      ],
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.width, required this.body});

  final String title;
  final AppContentWidth width;
  final Widget body;

  @override
  Widget build(BuildContext context) =>
      AppScaffold(title: title, contentWidth: width, body: body);
}

void main() {
  screenshotCase(
    '95-content-width-reading',
    build: () => const _Page(
      title: 'Checkout settings',
      width: AppContentWidth.reading,
      body: _Form(),
    ),
  );

  screenshotCase(
    '95-content-width-records',
    build: () => const _Page(
      title: 'Manage catalog',
      width: AppContentWidth.records,
      body: _Records(),
    ),
  );

  // The before picture, and the only place in the harness §4.2's defect is
  // still visible. Nothing in `lib/` passes `full` - the sale path would, and
  // it is step 7's - so without this case the app has no record of what the
  // constraint changed.
  screenshotCase(
    '95-content-width-full',
    build: () => const _Page(
      title: 'Manage catalog',
      width: AppContentWidth.full,
      body: _Records(),
    ),
  );
}
