import 'package:flutter/material.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/buttons.dart';
import 'package:uzapay_pos/ui/fields.dart';
import 'package:uzapay_pos/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

final _tokens = spiritTheme.extension<AppTokens>()!;

/// Mounts [child] under the app's own theme, optionally at compact density.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  AppDensity density = AppDensity.comfortable,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => Theme(
            data: Theme.of(context).copyWith(
              extensions: <ThemeExtension<dynamic>>[
                AppTokens.of(context).withDensity(density),
              ],
            ),
            child: Padding(padding: const EdgeInsets.all(24), child: child),
          ),
        ),
      ),
    ),
  );
}

/// The well itself - the one [DecoratedBox] that draws the border.
BoxDecoration _wellDecoration(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(AppFieldWell),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return box.decoration as BoxDecoration;
}

TextStyle _styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

void main() {
  group('the well is §5.2\'s well', () {
    testWidgets('surface.field, border.strong at 1px, radius.md', (
      tester,
    ) async {
      // **The design's own input rule, which it writes as CSS rather than
      // leaving to be inferred**: `background-color: surface-elevated;
      // border: 1px solid outline-variant; border-radius: borderRadius.xl`.
      // `surface.field`, `surface.borderStrong` and `radius.md` are those
      // three values. The 2026-08-23 pill override was withdrawn the same day
      // the instruction became "match the Stitch render".
      await _pump(tester, const AppTextField(label: 'Product name'));
      final decoration = _wellDecoration(tester);
      expect(decoration.color, _tokens.colors.surface.field);
      expect(
        (decoration.border! as Border).top.color,
        _tokens.colors.surface.borderStrong,
      );
      expect((decoration.border! as Border).top.width, 1);
      expect(
        (decoration.borderRadius! as BorderRadius).topLeft.x,
        _tokens.radius.md,
      );
    });

    testWidgets('the placeholder is text.secondary, and the reason is §9', (
      tester,
    ) async {
      // `text.tertiary` measures 4.29:1 on `surface.field` against §9's 4.5,
      // where it measured 5.9 on the page. `test/ui/tokens_test.dart` asserts
      // the figure; this asserts the widget acted on it.
      await _pump(
        tester,
        const AppTextField(label: 'Receipt number', placeholder: 'CT-A7F-0042'),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.hintStyle!.color, _tokens.colors.text.secondary);
    });

    testWidgets('an optional leading icon, at §5.2\'s named 18', (
      tester,
    ) async {
      await _pump(tester, const AppTextField(label: 'Password'));
      expect(find.byType(Icon), findsNothing);

      await _pump(
        tester,
        const AppTextField(label: 'Password', leading: Icons.lock_outline),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, Icons.lock_outline);
      expect(icon.size, AppButton.iconSize);
      expect(icon.color, _tokens.colors.text.tertiary);
    });

    testWidgets('the label is persistent, label.md, text.secondary', (
      tester,
    ) async {
      // §5.2's first sentence, and the one this app broke in three different
      // ways: a floating label, a placeholder standing in for a label, and a
      // label in uppercase.
      await _pump(tester, const AppTextField(label: 'Product name'));
      expect(find.text('Product name'), findsOneWidget);
      final style = _styleOf(tester, 'Product name');
      expect(style.fontSize, _tokens.typography.labelMedium.fontSize);
      expect(style.fontWeight, _tokens.typography.labelMedium.fontWeight);
      expect(style.color, _tokens.colors.text.secondary);
      expect(style.letterSpacing, _tokens.typography.labelMedium.letterSpacing);
    });

    testWidgets('the label stays visible once the field has a value', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'Bread');
      addTearDown(controller.dispose);
      await _pump(
        tester,
        AppTextField(label: 'Product name', controller: controller),
      );
      expect(find.text('Product name'), findsOneWidget);
      expect(find.text('Bread'), findsOneWidget);
    });

    testWidgets('it is 48 high at comfortable and 32 at compact', (
      tester,
    ) async {
      // §5.2 says 48 at comfortable; §3 says the same surface's minimum tap
      // target is 48 there and 32 at compact. One figure, read from §3 rather
      // than declared twice.
      await _pump(tester, const AppTextField(label: 'Name'));
      final comfortable = tester.getSize(
        find
            .descendant(
              of: find.byType(AppFieldWell),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(comfortable.height, 48);

      await _pump(
        tester,
        const AppTextField(label: 'Name'),
        density: AppDensity.compact,
      );
      final compact = tester.getSize(
        find
            .descendant(
              of: find.byType(AppFieldWell),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(compact.height, 32);
    });
  });

  group('§5.2: the error replaces the helper, and states what to do', () {
    testWidgets('a helper line is caption / text.tertiary', (tester) async {
      await _pump(
        tester,
        const AppTextField(
          label: 'Code (SKU or barcode)',
          helper: 'What the register matches a scan against. No spaces.',
        ),
      );
      final style = _styleOf(
        tester,
        'What the register matches a scan against. No spaces.',
      );
      expect(style.fontSize, _tokens.typography.caption.fontSize);
      expect(style.color, _tokens.colors.text.tertiary);
    });

    testWidgets('an error takes the helper\'s place rather than joining it', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppTextField(
          label: 'Unit price',
          helper: 'At most two decimal places.',
          error: 'Enter a price with at most two decimal places.',
        ),
      );
      expect(find.text('At most two decimal places.'), findsNothing);
      expect(
        find.text('Enter a price with at most two decimal places.'),
        findsOneWidget,
      );
    });

    testWidgets('the error is status.problem.fg and the border its own', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppTextField(label: 'Unit price', error: 'Enter a whole number.'),
      );
      expect(
        _styleOf(tester, 'Enter a whole number.').color,
        _tokens.colors.status.problem.fg,
      );
      // `status.problem.fg`, which is the same value the theme's own
      // `errorBorder` paints. The 30%-alpha `border` is a status *chip's*
      // edge; on a dark well it is nearly invisible, and an outline nobody
      // can see is not the second signal §9 asks an error to carry.
      expect(
        (_wellDecoration(tester).border! as Border).top.color,
        _tokens.colors.status.problem.fg,
      );
    });

    testWidgets('the field does not change height when it goes wrong', (
      tester,
    ) async {
      // Which is the layout consequence of "replaces" rather than "joins", and
      // the reason it is worth a test: a form that reflowed under the finger
      // typing into it would be a worse fault than the wrong colour.
      await _pump(
        tester,
        const AppTextField(label: 'Unit price', helper: 'At most two places.'),
      );
      final quiet = tester.getSize(find.byType(AppFieldWell));
      await _pump(
        tester,
        const AppTextField(
          label: 'Unit price',
          helper: 'At most two places.',
          error: 'At most two places.',
        ),
      );
      expect(tester.getSize(find.byType(AppFieldWell)), quiet);
    });

    testWidgets('the message is text, so it is not carried by colour alone', (
      tester,
    ) async {
      // §9 and §5.2 both. A red border with nothing beside it fails for a
      // colourblind reader and in print, and this is the assertion that would
      // fail if someone made the error an outline-only state.
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const AppTextField(
          label: 'Email',
          error: 'Enter a valid email address.',
        ),
      );
      expect(
        find.bySemanticsLabel('Enter a valid email address.'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('§5.2: the counter renders only above 80% of the limit', () {
    testWidgets('nothing at all below the threshold', (tester) async {
      final controller = TextEditingController(text: 'a' * 79);
      addTearDown(controller.dispose);
      await _pump(
        tester,
        AppTextField(label: 'Name', controller: controller, maxLength: 100),
      );
      expect(find.textContaining('/100'), findsNothing);
    });

    testWidgets('and it appears at exactly 80%', (tester) async {
      final controller = TextEditingController(text: 'a' * 80);
      addTearDown(controller.dispose);
      await _pump(
        tester,
        AppTextField(label: 'Name', controller: controller, maxLength: 100),
      );
      expect(find.text('80/100'), findsOneWidget);
    });

    testWidgets('it appears while typing, not only on a rebuild', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'a' * 7);
      addTearDown(controller.dispose);
      await _pump(
        tester,
        AppTextField(label: 'Name', controller: controller, maxLength: 10),
      );
      expect(find.textContaining('/10'), findsNothing);
      await tester.enterText(find.byType(TextField), 'a' * 9);
      await tester.pump();
      expect(find.text('9/10'), findsOneWidget);
    });

    testWidgets('it counts characters, not code units', (tester) async {
      // The same unit `maxLength` enforces. A counter that disagreed with the
      // limit it names would be worse than none.
      final controller = TextEditingController(text: 'ééé');
      addTearDown(controller.dispose);
      await _pump(
        tester,
        AppTextField(label: 'Name', controller: controller, maxLength: 3),
      );
      expect(find.text('3/3'), findsOneWidget);
    });

    testWidgets('there is only one counter, not the framework\'s as well', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'a' * 9);
      addTearDown(controller.dispose);
      await _pump(
        tester,
        AppTextField(label: 'Name', controller: controller, maxLength: 10),
      );
      expect(find.textContaining('/10'), findsOneWidget);
    });
  });

  group('the state matrix §5 asks for', () {
    testWidgets('disabled: the label, the value and the border all say so', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'Bread');
      addTearDown(controller.dispose);
      await _pump(
        tester,
        AppTextField(
          label: 'Product name',
          controller: controller,
          enabled: false,
        ),
      );
      expect(
        _styleOf(tester, 'Product name').color,
        _tokens.colors.action.disabledLabel,
      );
      expect(
        (_wellDecoration(tester).border! as Border).top.color,
        _tokens.colors.action.disabledBorder,
      );
      await tester.enterText(find.byType(TextField), 'Milk');
      expect(controller.text, 'Bread');
    });

    testWidgets('read-only: the value is shown and cannot be changed', (
      tester,
    ) async {
      // A different state from disabled, and the distinction is the point: a
      // disabled field is one a person may not use, a read-only one holds a
      // value they may not change.
      final controller = TextEditingController(text: 'CT-A7F-20260812-0041');
      addTearDown(controller.dispose);
      await _pump(
        tester,
        AppTextField(
          label: 'Receipt number',
          controller: controller,
          readOnly: true,
        ),
      );
      expect(find.text('CT-A7F-20260812-0041'), findsOneWidget);
      expect(
        (_wellDecoration(tester).border! as Border).top.color,
        _tokens.colors.surface.borderStrong,
        reason: 'read-only is not disabled and does not borrow its border',
      );
      await tester.enterText(find.byType(TextField), 'nope');
      expect(controller.text, 'CT-A7F-20260812-0041');
    });

    testWidgets('empty: the placeholder is an example and goes when typed in', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        AppTextField(
          label: 'Receipt number',
          controller: controller,
          placeholder: 'CT-A7F-20260731-0042',
        ),
      );
      double placeholderOpacity() => tester
          .widget<AnimatedOpacity>(
            find
                .ancestor(
                  of: find.text('CT-A7F-20260731-0042'),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          )
          .opacity;

      expect(find.text('CT-A7F-20260731-0042'), findsOneWidget);
      expect(placeholderOpacity(), 1);
      await tester.enterText(find.byType(TextField), 'CT-A7F-20260812-0001');
      await tester.pumpAndSettle();
      // The hint widget stays in the tree and fades, which is what
      // `InputDecorator` does; asserting `findsNothing` would be asserting an
      // implementation detail that is not true.
      expect(placeholderOpacity(), 0);
      expect(find.text('CT-A7F-20260812-0001'), findsOneWidget);
    });

    testWidgets('focus-visible: the ring is painted, and only when focused', (
      tester,
    ) async {
      await _pump(tester, const AppTextField(label: 'Product name'));
      Iterable<BoxDecoration> rings() => tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .where(
            (decoration) =>
                (decoration.border as Border?)?.top.color ==
                _tokens.colors.action.focusRing.fieldColor,
          );
      expect(rings(), isEmpty);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      // **One outline, not an outline and a ring.** Since 2026-09-24 it is one
      // pixel of the accent rather than two, which read as a lit box.
      // It is painted outside the stroke so the field does not reflow.
      expect(rings(), hasLength(1));
      final outline = rings().single.border!.top;
      expect(outline.width, _tokens.colors.action.focusRing.fieldWidth);
      expect(outline.strokeAlign, BorderSide.strokeAlignOutside);
    });

    testWidgets('and focusing it does not move the field', (tester) async {
      // The ring's 4px is reserved whether it is painted or not, for the same
      // reason `PressSurface` reserves it: a form that reflowed as the focus
      // moved between two of its fields would be a worse §9 failure than the
      // one the ring fixes.
      await _pump(tester, const AppTextField(label: 'Product name'));
      final before = tester.getRect(find.byType(TextField));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(TextField)), before);
    });

    testWidgets('focus-visible: no glow - the outline takes the field focus', (
      tester,
    ) async {
      // **The blurred halo is gone as of 2026-08-23.** The design draws focus
      // as two crisp lines - `border-color: primary` and
      // `box-shadow: 0 0 0 1px primary` - and a blur beside §9's ring read as
      // a lit field rather than a focused one. §2.1's "depth is a surface
      // step, never a drop shadow" now has no exception in this component.
      await _pump(tester, const AppTextField(label: 'Product name'));
      expect(_wellDecoration(tester).boxShadow, anyOf(isNull, isEmpty));
      expect(
        (_wellDecoration(tester).border! as Border).top.color,
        _tokens.colors.surface.borderStrong,
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(_wellDecoration(tester).boxShadow, anyOf(isNull, isEmpty));
      expect(
        (_wellDecoration(tester).border! as Border).top.color,
        _tokens.colors.action.focusRing.fieldColor,
      );
    });

    testWidgets('a disabled field is not focusable, so it never lights up', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppTextField(label: 'Unit cost', enabled: false),
      );
      expect(_wellDecoration(tester).boxShadow, anyOf(isNull, isEmpty));
      expect(
        (_wellDecoration(tester).border! as Border).top.color,
        _tokens.colors.action.disabledBorder,
      );
    });
  });

  group('the editing behaviour a call site already relies on', () {
    testWidgets('onChanged fires with the new value', (tester) async {
      final seen = <String>[];
      await _pump(tester, AppTextField(label: 'Name', onChanged: seen.add));
      await tester.enterText(find.byType(TextField), 'Bread');
      expect(seen, <String>['Bread']);
    });

    testWidgets('maxLength is enforced, not merely counted', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        AppTextField(label: 'Name', controller: controller, maxLength: 5),
      );
      await tester.enterText(find.byType(TextField), 'abcdefghij');
      expect(controller.text, 'abcde');
    });

    testWidgets('onSubmitted fires', (tester) async {
      var submitted = 0;
      await _pump(
        tester,
        AppTextField(label: 'Receipt number', onSubmitted: (_) => submitted++),
      );
      await tester.enterText(find.byType(TextField), 'CT-1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(submitted, 1);
    });
  });

  group('a validator lands in the same slot the error does', () {
    Widget form(GlobalKey<FormState> key, {String? error}) => Form(
      key: key,
      child: AppTextField(
        label: 'Email',
        error: error,
        validator: (value) =>
            (value ?? '').contains('@') ? null : 'Enter a valid email address.',
      ),
    );

    testWidgets('Form.validate reaches it, exactly as a TextFormField', (
      tester,
    ) async {
      final key = GlobalKey<FormState>();
      await _pump(tester, form(key));
      expect(find.text('Enter a valid email address.'), findsNothing);
      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(
        _styleOf(tester, 'Enter a valid email address.').color,
        _tokens.colors.status.problem.fg,
      );
      await tester.enterText(find.byType(TextField), 'amina@example.com');
      expect(key.currentState!.validate(), isTrue);
      await tester.pump();
      expect(find.text('Enter a valid email address.'), findsNothing);
    });

    testWidgets('and an explicit error wins over it', (tester) async {
      // A server's refusal is about the value that was submitted; a validator
      // is about the value on screen. Two messages in one slot is worse than
      // either.
      final key = GlobalKey<FormState>();
      await _pump(tester, form(key, error: 'That address is already invited.'));
      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('That address is already invited.'), findsOneWidget);
      expect(find.text('Enter a valid email address.'), findsNothing);
    });
  });

  group('AppSelect borrows the field\'s well, because §5.2 gives it none', () {
    testWidgets('the same well, label and radius as a text field', (
      tester,
    ) async {
      await _pump(
        tester,
        AppSelect<int>(
          label: 'Role',
          value: 1,
          items: const <AppSelectItem<int>>[
            AppSelectItem<int>(value: 1, label: 'Manager'),
            AppSelectItem<int>(value: 2, label: 'Cashier'),
          ],
          onChanged: (_) {},
        ),
      );
      final decoration = _wellDecoration(tester);
      expect(decoration.color, _tokens.colors.surface.field);
      expect(
        (decoration.border! as Border).top.color,
        _tokens.colors.surface.borderStrong,
      );
      expect(
        (decoration.borderRadius! as BorderRadius).topLeft.x,
        _tokens.radius.md,
      );
      expect(_styleOf(tester, 'Role').color, _tokens.colors.text.secondary);
    });

    testWidgets('choosing an option reports it', (tester) async {
      int? chosen;
      await _pump(
        tester,
        AppSelect<int>(
          label: 'Role',
          value: 1,
          items: const <AppSelectItem<int>>[
            AppSelectItem<int>(value: 1, label: 'Manager'),
            AppSelectItem<int>(value: 2, label: 'Cashier'),
          ],
          onChanged: (value) => chosen = value,
        ),
      );
      await tester.tap(find.text('Manager'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cashier').last);
      await tester.pumpAndSettle();
      expect(chosen, 2);
    });

    testWidgets('a null onChanged disables it, exactly as it does AppButton', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppSelect<int>(
          label: 'Role',
          value: 1,
          items: <AppSelectItem<int>>[
            AppSelectItem<int>(value: 1, label: 'Manager'),
          ],
          onChanged: null,
        ),
      );
      expect(
        (_wellDecoration(tester).border! as Border).top.color,
        _tokens.colors.action.disabledBorder,
      );
      expect(
        _styleOf(tester, 'Role').color,
        _tokens.colors.action.disabledLabel,
      );
    });

    testWidgets('it carries a helper and an error the same way', (
      tester,
    ) async {
      await _pump(
        tester,
        AppSelect<int>(
          label: 'Role',
          value: 1,
          items: const <AppSelectItem<int>>[
            AppSelectItem<int>(value: 1, label: 'Manager'),
          ],
          onChanged: (_) {},
          helper: 'What this person may do.',
          error: 'Choose a role for this person.',
        ),
      );
      expect(find.text('What this person may do.'), findsNothing);
      expect(
        _styleOf(tester, 'Choose a role for this person.').color,
        _tokens.colors.status.problem.fg,
      );
    });
  });

  testWidgets('a field reads no colour of its own - every one is a token', (
    tester,
  ) async {
    // `claude.md` hard rule 2 in the form that can be checked: every colour the
    // well paints is one of the roles, and a literal would show up here as a
    // colour that is in none of them.
    await _pump(
      tester,
      const AppTextField(label: 'Name', helper: 'Such as Bakery.'),
    );
    // **`surface.field` is listed explicitly since 2026-08-22.** The well
    // paints it, and this set passed for months without naming it because in the
    // shipped palette `surface.field` and `action.disabledBorder` were the same
    // `green.700`. Profound Verdant separates them, and the omission surfaced as
    // a failure here - which is the set doing its job.
    final palette = <Color>{
      _tokens.colors.surface.field,
      _tokens.colors.surface.sunken,
      _tokens.colors.surface.borderStrong,
      _tokens.colors.text.primary,
      _tokens.colors.text.secondary,
      _tokens.colors.text.tertiary,
      _tokens.colors.status.problem.border,
      _tokens.colors.action.disabledBorder,
      _tokens.colors.action.focusRing.color,
    };
    final decoration = _wellDecoration(tester);
    expect(palette, contains(decoration.color));
    expect(palette, contains((decoration.border! as Border).top.color));
    expect(palette, contains(_styleOf(tester, 'Name').color));
    expect(palette, contains(_styleOf(tester, 'Such as Bakery.').color));
  });
}
