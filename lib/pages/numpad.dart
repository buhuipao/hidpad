import 'package:flutter/material.dart';

import '../hid.dart';
import '../keys.dart';
import '../widgets.dart';

typedef _Key = ({String label, int usage, int flex});

_Key _k(String label, int usage, {int flex = 1}) => (label: label, usage: usage, flex: flex);

_Key _digit(int n) => _k('$n', n == 0 ? Usage.keypad0 : Usage.keypad1 + n - 1, flex: n == 0 ? 2 : 1);

final _rows = <List<_Key>>[
  [_k('Num', Usage.numLock), _k('/', Usage.keypadDivide), _k('*', Usage.keypadMultiply), _k('-', Usage.keypadMinus)],
  [_digit(7), _digit(8), _digit(9), _k('+', Usage.keypadPlus)],
  [_digit(4), _digit(5), _digit(6), _k('⌫', Usage.backspace)],
  [_digit(1), _digit(2), _digit(3), _k('Tab', Usage.tab)],
  [_digit(0), _k('.', Usage.keypadDot), _k('Enter', Usage.keypadEnter)],
];

/// Numeric keypad.
class NumpadPage extends StatelessWidget {
  const NumpadPage({super.key});

  static const _maxWidth = 480.0;

  @override
  Widget build(BuildContext context) {
    final hid = Hid.instance;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              for (final row in _rows)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final key in row)
                        Expanded(
                          flex: key.flex,
                          child: PressKey(
                            label: key.label,
                            semanticLabel: key.label == '⌫' ? 'Backspace' : null,
                            primary: key.usage == Usage.keypadEnter,
                            onDown: () => hid.keyDown(key.usage),
                            onUp: () => hid.keyUp(key.usage),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
