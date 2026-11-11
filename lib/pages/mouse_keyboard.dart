import 'package:flutter/material.dart';

import '../hid.dart';
import '../keys.dart';
import '../widgets.dart';

/// Touchpad, mouse buttons, and a box that types with the phone keyboard.
class MouseKeyboardPage extends StatelessWidget {
  const MouseKeyboardPage({super.key});

  static const _buttonRowHeight = 64.0;

  Widget _button(String label, int button, {int flex = 2}) => Expanded(
    flex: flex,
    child: PressKey(
      label: label,
      onDown: () => Hid.instance.mouseButton(button, true),
      onUp: () => Hid.instance.mouseButton(button, false),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                const Positioned.fill(child: Touchpad()),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    tooltip: 'Pointer settings',
                    icon: const Icon(Icons.tune),
                    onPressed: () => showPointerSettings(context),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: _buttonRowHeight,
            child: Row(
              children: [
                _button('Left', MouseButton.left),
                _button('Middle', MouseButton.middle, flex: 1),
                _button('Right', MouseButton.right),
              ],
            ),
          ),
          const TypingField(),
        ],
      ),
    );
  }
}
