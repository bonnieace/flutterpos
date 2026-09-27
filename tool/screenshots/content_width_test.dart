/// Step 6's first half: `design.md` §4.2's content widths, photographed.
///
/// **The matrix of a layout contract is not §5's nine states.** A max content
/// width has no hover, no press and nothing to disable - it is not a control.
/// What varies is the two dimensions the contract itself has: **which of §4.2's
/// three rows a page declares**, and **where on the width axis the window sits**.
///
/// **The second dimension has five values, not two, and this file used to
/// capture two of them.** §4.1's floors and §4.2's maxima are boundaries on the
/// same axis and they interleave - 720, 768, 1024, 1200 - so the axis is cut
/// into five regions and a row can render differently in each. The three rows at
/// [everyRegionViewports] is that matrix in full, at fifteen pictures. It was
/// six, and six was the matrix of a two-value axis that does not exist.
///
/// **The narrowest is the most important and the easiest to skip.** 411 is
/// narrower than every maximum §4.2 states, so all three rows must look
/// *identical* there - a constraint that fires on a phone would be a constraint
/// that had been written as a fixed width by mistake. The three mobile images
/// being interchangeable is the evidence, and it is why `full` is captured at
/// all rather than only described.
///
/// **767 is where the two dimensions come apart.** It is still `compact`, and
/// `reading` is already capped, so `reading` and `records` stop being
/// interchangeable one region below the band floor everyone reaches for. If
/// those two images match, a maximum has been wired to a band by mistake.
///
/// **What the widest shows is the defect §4.2 was written about.** `full` is the
/// app as it was before this step: a record row 1,400 pixels wide with its
/// identity at one end and its actions at the other. `records` is the same rows
/// at 1200, and `reading` is what a form gets.
///
/// **And `records` buys nothing until 1200.** Its image is byte-identical to
/// `full`'s at 1024, 834, 767 and 411 and differs only at 1440, which is the
/// arithmetic - a `ConstrainedBox` at 1200 constrains nothing narrower than
/// itself - made visible rather than asserted. Worth having in pictures because
/// it is the thing a reader assumes about the wrong boundary: the row shape
/// changes at 1024 and the cap fires at 1200, and this app's `expanded` band
/// starts in the 176 logical pixels between them.
library;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/ui/buttons.dart';
import 'package:uzapay_pos/ui/fields.dart';
import 'package:uzapay_pos/ui/scaffold.dart';
import 'package:uzapay_pos/ui/tokens.dart';

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
    viewports: everyRegionViewports,
    build: () => const _Page(
      title: 'Checkout settings',
      width: AppContentWidth.reading,
      body: _Form(),
    ),
  );

  screenshotCase(
    '95-content-width-records',
    viewports: everyRegionViewports,
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
    viewports: everyRegionViewports,
    build: () => const _Page(
      title: 'Manage catalog',
      width: AppContentWidth.full,
      body: _Records(),
    ),
  );
}
