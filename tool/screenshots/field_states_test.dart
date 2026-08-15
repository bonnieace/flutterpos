/// `AppTextField` and `AppSelect`'s state matrix, which `claude.md` hard rule 5
/// and `design.md` §10 both require before a component is finished.
///
/// **Of §5's nine states, six apply to a field and three do not.** `enabled`,
/// `focus-visible`, `disabled`, `error`, `read-only` and `empty` are all real
/// things a field is. `pressed` belongs to a button - a field is not a control
/// you push - and `loading` to an action; a field whose value is not ready yet
/// is `disabled` or `read-only`, which are already here.
///
/// **`hover` is the seventh, and it is captured showing nothing.** §5.2
/// specifies a field's rest, focus and error treatments and says nothing about
/// a pointer resting over one, so there is no hover fill to draw and
/// `claude.md`'s rule against inventing a token forbids picking one. The
/// capture is here rather than omitted because a reviewer needs to see that the
/// absence is deliberate: `90-appbutton-hover-*` shows a real change and
/// `92-appfield-hover` shows none, and the gap is queued in `PLAN.md` as a
/// question for the product owner rather than answered here.
///
/// **The states are produced, not painted.** `error` and `read-only` are
/// properties, so they share one capture with the rest. `focus-visible` is
/// driven by a real autofocus under [FocusHighlightStrategy.alwaysTraditional],
/// for the same reason the button matrix needs it: the highlight mode follows
/// the platform, a test binding reports a touch platform, and a ring only a
/// keyboard user sees would otherwise never appear in a picture. `hover` is a
/// real mouse pointer. The open menu is a real tap.
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/fields.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// One labelled row of the matrix.
class _Row extends StatelessWidget {
  const _Row({required this.state, required this.child});

  final String state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            state,
            style: tokens.typography.labelEyebrow.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
          SizedBox(height: tokens.spacing.s8),
          child,
        ],
      ),
    );
  }
}

/// Controllers live for the page's lifetime; a screenshot case builds its page
/// once per viewport, so they are made here rather than in `build`.
final _named = TextEditingController(text: 'White bread loaf');
final _empty = TextEditingController();
final _wrong = TextEditingController(text: '65.000');
final _receipt = TextEditingController(text: 'CT-A7F-20260812-0041');
final _long = TextEditingController(text: 'a' * 92);

/// The whole matrix on one page.
class _FieldMatrix extends StatelessWidget {
  const _FieldMatrix({required this.title, this.focused = false});

  final String title;

  /// Whether the first field takes the focus, for the focus-visible capture.
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(tokens.spacing.s24),
        child: ConstrainedBox(
          // A form is read at a comfortable measure rather than the full width
          // of a desktop window. 720 is §4.2's form width; it is not declared
          // as a token here because `PLAN.md`'s standing exclusion keeps
          // content widths out of the token layer until step 6 takes them.
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Row(
                state: 'enabled',
                child: AppTextField(
                  key: const ValueKey('field-enabled'),
                  label: 'Product name',
                  controller: _named,
                  autofocus: focused,
                ),
              ),
              _Row(
                state: 'empty - the placeholder is an example, not the label',
                child: AppTextField(
                  key: const ValueKey('field-empty'),
                  label: 'Receipt number',
                  controller: _empty,
                  placeholder: 'CT-A7F-20260731-0042',
                ),
              ),
              const _Row(
                state: 'with a helper line',
                child: AppTextField(
                  key: ValueKey('field-helper'),
                  label: 'Code (SKU or barcode)',
                  helper: 'What the till matches a scan against. No spaces.',
                ),
              ),
              const _Row(
                // `design.md` v0.4's addition. A glyph that does not narrow what
                // the field is for is noise in a form of six, so most fields
                // carry none - this row is here so a reviewer can see what
                // "optional" looks like when it is taken.
                state: 'with a leading icon - optional, and mostly declined',
                child: AppTextField(
                  key: ValueKey('field-leading'),
                  label: 'Email',
                  leading: Icons.email_outlined,
                  placeholder: 'grace@westlands-mart.example',
                ),
              ),
              _Row(
                state: 'error - it replaces the helper and says what to do',
                child: AppTextField(
                  key: const ValueKey('field-error'),
                  label: 'Unit price',
                  controller: _wrong,
                  helper: 'At most two decimal places.',
                  error: 'Use at most two decimal places, such as 65.00.',
                ),
              ),
              _Row(
                state: 'disabled - may not be used',
                child: AppTextField(
                  key: const ValueKey('field-disabled'),
                  label: 'Unit cost (optional)',
                  controller: _named,
                  enabled: false,
                ),
              ),
              _Row(
                state: 'read-only - holds a value that may not be changed',
                child: AppTextField(
                  key: const ValueKey('field-read-only'),
                  label: 'Receipt number',
                  controller: _receipt,
                  readOnly: true,
                ),
              ),
              _Row(
                state: 'counter - renders only above 80% of the limit',
                child: AppTextField(
                  key: const ValueKey('field-counter'),
                  label: 'Reason for this adjustment',
                  controller: _long,
                  maxLength: 100,
                ),
              ),
              _Row(
                state: 'AppSelect - the same well, because §5.2 gives it none',
                child: AppSelect<String>(
                  key: const ValueKey('select-enabled'),
                  label: 'Role',
                  value: 'manager',
                  items: const <AppSelectItem<String>>[
                    AppSelectItem<String>(value: 'admin', label: 'admin'),
                    AppSelectItem<String>(value: 'manager', label: 'manager'),
                    AppSelectItem<String>(value: 'cashier', label: 'cashier'),
                  ],
                  helper: 'What this person may do in the business.',
                  onChanged: (_) {},
                ),
              ),
              const _Row(
                state: 'AppSelect - disabled',
                child: AppSelect<String>(
                  key: ValueKey('select-disabled'),
                  label: 'Role',
                  value: 'owner',
                  items: <AppSelectItem<String>>[
                    AppSelectItem<String>(value: 'owner', label: 'owner'),
                  ],
                  helper: 'An owner\'s role cannot be changed from here.',
                  onChanged: null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  // A form is a desktop and a phone surface both, and the field is the one
  // component whose height changes with density, so both viewports run.
  screenshotCase(
    '92-appfield-states',
    build: () => const _FieldMatrix(title: 'AppTextField - state matrix'),
  );

  screenshotCase(
    '92-appfield-focus',
    viewports: const <ScreenshotViewport>[webViewport],
    build: () => const _FieldMatrix(
      title: 'AppTextField - focus-visible',
      focused: true,
    ),
    afterPump: (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      await tester.pumpAndSettle();
    },
  );

  screenshotCase(
    '92-appfield-hover',
    viewports: const <ScreenshotViewport>[webViewport],
    build: () => const _FieldMatrix(title: 'AppTextField - hover'),
    afterPump: (tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('field-enabled'))),
      );
      await tester.pumpAndSettle();
    },
  );

  screenshotCase(
    '92-appselect-open',
    viewports: const <ScreenshotViewport>[webViewport],
    // The menu is an overlay above the page; a full-page re-render would
    // measure the page under it and photograph the two at different sizes.
    fullPage: false,
    build: () => const _FieldMatrix(title: 'AppSelect - menu open'),
    afterPump: (tester) async {
      await tester.tap(find.byKey(const ValueKey('select-enabled')));
      await tester.pumpAndSettle();
    },
  );
}
