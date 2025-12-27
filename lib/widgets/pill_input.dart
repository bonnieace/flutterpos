import 'package:flutter/material.dart';
import '../keyboard_scope.dart';
import '../theme.dart';

class PillInput extends StatefulWidget {
  final String label;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextEditingController controller;
  final FocusNode focusNode;
  final dynamic keyboard;

  const PillInput({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    required this.focusNode,
    this.obscure = false,
    this.keyboard,
  });

  @override
  State<PillInput> createState() => _PillInputState();
}

class _PillInputState extends State<PillInput> {
  bool _isFocused = false;
  bool _obscureText = false;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscure;
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() {
      _isFocused = widget.focusNode.hasFocus;
    });
    if (_isFocused && widget.keyboard != null) {
      widget.keyboard.attach(
        controller: widget.controller,
        focusNode: widget.focusNode,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 12,
            letterSpacing: 1.2,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            FocusScope.of(context).requestFocus(widget.focusNode);
            if (widget.keyboard != null) {
              widget.keyboard.attach(
                controller: widget.controller,
                focusNode: widget.focusNode,
              );
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: mutedGreen,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: _isFocused ? accentGreen : Colors.transparent,
                width: 2,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: accentGreen.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
            ),
            child: Row(
              children: [
                Icon(widget.icon, color: Colors.white54),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    obscureText: widget.obscure ? _obscureText : false,
                    readOnly: false,
                    showCursor: true,
                    enableInteractiveSelection: false, // Prevent selection/highlight
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      hintText: widget.hint,
                      hintStyle: const TextStyle(color: Colors.white38),
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                  ),
                ),
                if (widget.obscure)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _obscureText = !_obscureText;
                        // Restore cursor to end after toggling
                        widget.controller.selection = TextSelection.collapsed(
                          offset: widget.controller.text.length,
                        );
                      });
                    },
                    child: Icon(
                      _obscureText ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white54,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
