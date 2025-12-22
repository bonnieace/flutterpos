import 'package:flutter/material.dart';
import '../keyboard_scope.dart';
import '../theme.dart';

class PosKeyboard extends StatelessWidget {
  const PosKeyboard({super.key});

  static const rows = [
    ["1","2","3","4","5","6","7","8","9","0"],
    ["Q","W","E","R","T","Y","U","I","O","P"],
    ["A","S","D","F","G","H","J","K","L"],
    ["Z","X","C","V","B","N","M","⌫"],
    ["@",".com","Space","Enter"],
  ];

  @override
  Widget build(BuildContext context) {
    final keyboard = KeyboardScope.of(context);

    Widget buildKey(String label, {double flex = 1}) {
      return Expanded(
        flex: flex.toInt(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (label == "⌫") {
              keyboard.backspace();
            } else if (label == "Space") {
              keyboard.insert(" ");
            } else if (label == "Enter") {
              // Optional submit action
            } else {
              keyboard.insert(label);
            }
          },
          child: Container(
            height: 56,
            margin: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: mutedGreen,
              borderRadius: BorderRadius.circular(28),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: rows.map((row) {
          return Row(
            children: row.map((key) {
              if (key == "Space") return buildKey(key, flex: 4);
              if (key == "Enter") return buildKey(key, flex: 2);
              return buildKey(key);
            }).toList(),
          );
        }).toList(),
      ),
    );
  }
}
