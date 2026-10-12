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

    // A selection is deleted whole; a caret takes the character before it.
    // No selection at all is a caret at the end, as it is for [insert].
    var start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    if (start == end) {
      if (start == 0) return;
      start -= 1;
    }

    final newText = text.replaceRange(start, end, '');
    _controller!
      ..text = newText
      ..selection = TextSelection.collapsed(offset: start);

    _focusNode?.requestFocus();
  }
}
