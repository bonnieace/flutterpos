import 'package:flutter/material.dart';
import '../theme.dart';

class PillButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final bool filled;
  final bool muted;
  final VoidCallback onTap;

  const PillButton({
    super.key,
    required this.text,
    this.icon,
    this.filled = false,
    this.muted = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: filled
              ? accentGreen
              : muted
                  ? mutedGreen
                  : Colors.white,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: filled ? Colors.black : Colors.black),
                const SizedBox(width: 8),
              ],
              Text(
                text,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: filled ? Colors.black : Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
