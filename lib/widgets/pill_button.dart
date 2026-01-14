import 'package:flutter/material.dart';
import '../theme.dart';

class PillButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final bool filled;
  final bool muted;
  final bool isLoading;
  final VoidCallback? onTap;

  const PillButton({
    super.key,
    required this.text,
    this.icon,
    this.filled = false,
    this.muted = false,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null || isLoading;
    
    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: Opacity(
        opacity: isDisabled ? 0.7 : 1.0,
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
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                    ),
                  )
                : Row(
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
      ),
    );
  }
}
