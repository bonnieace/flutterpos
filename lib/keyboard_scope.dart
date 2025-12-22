import 'package:flutter/material.dart';
import 'keyboard_controller.dart';

class KeyboardScope extends InheritedWidget {
  final KeyboardController keyboard;

  const KeyboardScope({
    super.key,
    required this.keyboard,
    required Widget child,
  }) : super(child: child);

  static KeyboardController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<KeyboardScope>();
    assert(scope != null, 'KeyboardScope not found');
    return scope!.keyboard;
  }

  @override
  bool updateShouldNotify(_) => false;
}
