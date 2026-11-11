import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../hid.dart';
import '../keys.dart';
import '../widgets.dart';

/// One key cap. Modifier keys set [mod] (a [Mod] bit); all other keys set [usage].
/// [width] is in quarter key units, so 4 is a normal key.
typedef _Key = ({String label, String? shifted, IconData? icon, int usage, int mod, int width});

_Key _k(String label, int usage, {int width = 4, IconData? icon}) =>
    (label: label, shifted: null, icon: icon, usage: usage, mod: 0, width: width);

_Key _m(String label, int mod, int width) =>
    (label: label, shifted: null, icon: null, usage: 0, mod: mod, width: width);

List<_Key> _chars(String plain, String shifted, {int width = 4}) => [
  for (var i = 0; i < plain.length; i++)
    (label: plain[i], shifted: shifted[i], icon: null, usage: usKey(plain[i])!.usage, mod: 0, width: width),
];

// US layout. Every row is 64 quarter units wide (the F row stretches to fit).
final _rows = <List<_Key>>[
  [
    _k('Esc', Usage.escape),
    for (var i = 0; i < 12; i++) _k('F${i + 1}', Usage.f1 + i),
    _k('PrtSc', Usage.printScreen),
    _k('Del', Usage.delete),
  ],
  [
    ..._chars('`1234567890-=', '~!@#\$%^&*()_+'),
    _k('Backspace', Usage.backspace, width: 8, icon: Icons.backspace_outlined),
    _k('Home', Usage.home),
  ],
  [
    _k('Tab', Usage.tab, width: 6),
    ..._chars('qwertyuiop[]', 'QWERTYUIOP{}'),
    ..._chars('\\', '|', width: 6),
    _k('PgUp', Usage.pageUp),
  ],
  [
    _k('Caps', Usage.capsLock, width: 7),
    ..._chars("asdfghjkl;'", 'ASDFGHJKL:"'),
    _k('Enter', Usage.enter, width: 9),
    _k('PgDn', Usage.pageDown),
  ],
  [
    _m('Shift', Mod.shift, 9),
    ..._chars('zxcvbnm,./', 'ZXCVBNM<>?'),
    _m('Shift', Mod.shift, 7),
    _k('Up', Usage.up, icon: Icons.keyboard_arrow_up),
    _k('End', Usage.end),
  ],
  [
    _m('Ctrl', Mod.ctrl, 5),
    _m('Win', Mod.gui, 5),
    _m('Alt', Mod.alt, 5),
    _k('Space', Usage.space, width: 27, icon: Icons.space_bar),
    _m('AltGr', Mod.rightAlt, 5),
    _m('Ctrl', Mod.ctrl, 5),
    _k('Left', Usage.left, icon: Icons.keyboard_arrow_left),
    _k('Down', Usage.down, icon: Icons.keyboard_arrow_down),
    _k('Right', Usage.right, icon: Icons.keyboard_arrow_right),
  ],
];

/// Full PC keyboard, shown in landscape.
class PcKeyboardPage extends StatefulWidget {
  const PcKeyboardPage({super.key});

  @override
  State<PcKeyboardPage> createState() => _PcKeyboardPageState();
}

class _PcKeyboardPageState extends State<PcKeyboardPage> {
  final _hid = Hid.instance;

  /// Modifiers that are on: true = locked, false = released after the next key.
  Map<int, bool> _held = const {};

  int get _mods => _held.keys.fold(0, (bits, bit) => bits | bit);

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(portraitOnly);
    _hid.releaseKeys();
    super.dispose();
  }

  /// Tap once: on for the next key. Tap again: locked. Tap again: off.
  void _cycle(int mod) {
    setState(() {
      _held = switch (_held[mod]) {
        null => {..._held, mod: false},
        false => {..._held, mod: true},
        true => {..._held}..remove(mod),
      };
    });
    _hid.setModifiers(_mods);
  }

  void _keyUp(int usage) {
    _hid.keyUp(usage);
    if (!_held.containsValue(false)) return;
    setState(() {
      _held = {
        for (final entry in _held.entries)
          if (entry.value) entry.key: true,
      };
    });
    _hid.setModifiers(_mods);
  }

  Widget _cap(_Key key, bool shift) => key.mod != 0
      ? PressKey(
          label: key.label,
          icon: _held[key.mod] == true ? Icons.lock : null,
          semanticLabel: key.label,
          active: _held.containsKey(key.mod),
          onDown: () => _cycle(key.mod),
        )
      : PressKey(
          label: key.icon != null
              ? null
              : shift
              ? key.shifted ?? key.label
              : key.label,
          icon: key.icon,
          semanticLabel: key.label,
          onDown: () => _hid.keyDown(key.usage),
          onUp: () => _keyUp(key.usage),
        );

  @override
  Widget build(BuildContext context) {
    final shift = _held.containsKey(Mod.shift);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          for (final row in _rows)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final key in row) Expanded(flex: key.width, child: _cap(key, shift))],
              ),
            ),
        ],
      ),
    );
  }
}
