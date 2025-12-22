import 'package:flutter/material.dart';

class KeyboardController {
  TextEditingController? _controller;
  FocusNode? _focusNode;

  void attach({
    required TextEditingController controller,
    required FocusNode focusNode,
  }) {
    _controller = controller;
    _focusNode = focusNode;
    _focusNode!.requestFocus();
  }

  void insert(String value) {
    if (_controller == null) return;

    final text = _controller!.text;
    final selection = _controller!.selection;

    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;

    final newText = text.replaceRange(start, end, value);
    final newOffset = start + value.length;
    _controller!
      ..text = newText
      ..selection = TextSelection.collapsed(offset: newOffset);

    _focusNode?.requestFocus();
  }

  void backspace() {
    if (_controller == null) return;

    final text = _controller!.text;
    final selection = _controller!.selection;

    if (selection.start <= 0) return;

    final start = selection.start - 1;
    final newText = text.replaceRange(start, selection.start, '');
    _controller!
      ..text = newText
      ..selection = TextSelection.collapsed(offset: start);

    _focusNode?.requestFocus();
  }
}
