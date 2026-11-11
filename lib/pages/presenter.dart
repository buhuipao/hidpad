import 'package:flutter/material.dart';

import '../hid.dart';
import '../keys.dart';
import '../widgets.dart';

/// Slide remote: next / previous, start and end the show, and a pointer pad.
class PresenterPage extends StatelessWidget {
  const PresenterPage({super.key});

  static final _hid = Hid.instance;

  Widget _key(String label, IconData icon, int usage, {int mods = 0, int flex = 1, bool primary = false}) => Expanded(
    flex: flex,
    child: PressKey(
      label: label,
      icon: icon,
      primary: primary,
      onDown: () => _hid.tapKey(usage, mods: mods),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Page Up / Page Down is what hardware slide clickers send.
                _key('Previous', Icons.navigate_before, Usage.pageUp),
                _key('Next', Icons.navigate_next, Usage.pageDown, flex: 2, primary: true),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _key('Start', Icons.slideshow, Usage.f5),
                _key('From here', Icons.play_circle_outline, Usage.f5, mods: Mod.shift),
                _key('Black', Icons.dark_mode_outlined, Usage.b),
                _key('End', Icons.close, Usage.escape),
              ],
            ),
          ),
          const Expanded(flex: 4, child: Touchpad()),
        ],
      ),
    );
  }
}
