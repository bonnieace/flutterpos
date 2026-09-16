/// `QuantityStepper`'s state matrix, per `claude.md` hard rule 5 and §10.
///
/// **Five rows.** `enabled`; `disabled`; `error`, where what was typed is not a
/// quantity the till can sell; and the two *bounds*, where one side is
/// unavailable on its own — a line whose product the cached catalog no longer
/// holds cannot be incremented, and a caller may withhold the minus. `hover`,
/// `focus-visible` and `pressed` belong to the controls inside it; `loading`,
/// `read-only` and `empty` have no meaning for a count.
///
/// **Both label states are photographed**, because the cart uses the one
/// without a word and every other caller would use the one with. Sixteen lines
/// each saying *Quantity* over a control shaped like one is what the labelless
/// case exists for.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/stepper.dart';
import 'package:flutter_application_1/ui/tokens.dart';

import 'harness.dart';

void main() {
  const cases = <String, _Case>{
    'enabled': _Case(),
    'unlabelled': _Case(label: null),
    'disabled': _Case(enabled: false),
    'error': _Case(
      quantity: 3,
      error: 'Not a quantity this register can sell. This line still has 3.',
    ),
    'no-increment': _Case(canIncrement: false),
    'no-decrement': _Case(canDecrement: false),
  };

  cases.forEach((name, state) {
    screenshotCase(
      '97-quantitystepper-$name',
      build: () => _Host(state: state),
      fullPage: false,
    );
  });
}

final class _Case {
  const _Case({
    this.label = 'Quantity',
    this.quantity = 1,
    this.error,
    this.enabled = true,
    this.canIncrement = true,
    this.canDecrement = true,
  });

  final String? label;
  final int quantity;
  final String? error;
  final bool enabled;
  final bool canIncrement;
  final bool canDecrement;
}

final class _Host extends StatelessWidget {
  const _Host({required this.state});

  final _Case state;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Scaffold(
      backgroundColor: tokens.colors.surface.base,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s24),
          child: QuantityStepper(
            label: state.label,
            quantity: state.quantity,
            // The till's own ceiling, so the picture shows the width a cart
            // line actually gets rather than the default.
            maximum: 1000000,
            error: state.error,
            enabled: state.enabled,
            onChanged: (_) {},
            onIncrement: state.canIncrement ? () {} : null,
            onDecrement: state.canDecrement ? () {} : null,
          ),
        ),
      ),
    );
  }
}
