import 'package:flutter/material.dart';

import '../hid.dart';
import '../keys.dart';
import '../widgets.dart';

/// Media keys plus arrows for media players and TV boxes.
class MultimediaPage extends StatelessWidget {
  const MultimediaPage({super.key});

  static final _hid = Hid.instance;

  Widget _media(String label, IconData icon, int usage, {bool primary = false}) => Expanded(
    child: PressKey(
      label: label,
      icon: icon,
      primary: primary,
      onDown: () => _hid.mediaKey(usage, true),
      onUp: () => _hid.mediaKey(usage, false),
    ),
  );

  Widget _key(String label, IconData icon, int usage, {bool primary = false}) => Expanded(
    child: PressKey(
      label: label,
      icon: icon,
      primary: primary,
      onDown: () => _hid.keyDown(usage),
      onUp: () => _hid.keyUp(usage),
    ),
  );

  Widget _row(int flex, List<Widget> keys) => Expanded(
    flex: flex,
    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: keys),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          _row(2, [
            _media('Volume down', Icons.volume_down, Media.volumeDown),
            _media('Mute', Icons.volume_off, Media.mute),
            _media('Volume up', Icons.volume_up, Media.volumeUp),
          ]),
          _row(2, [
            _media('Previous', Icons.skip_previous, Media.previous),
            _media('Rewind', Icons.fast_rewind, Media.rewind),
            _media('Play / Pause', Icons.play_arrow, Media.playPause, primary: true),
            _media('Forward', Icons.fast_forward, Media.fastForward),
            _media('Next', Icons.skip_next, Media.next),
          ]),
          const SizedBox(height: 8),
          _row(2, [
            _key('Back', Icons.arrow_back, Usage.escape),
            _key('Up', Icons.keyboard_arrow_up, Usage.up),
            _media('Home', Icons.home_outlined, Media.home),
          ]),
          _row(2, [
            _key('Left', Icons.keyboard_arrow_left, Usage.left),
            _key('OK', Icons.radio_button_checked, Usage.enter, primary: true),
            _key('Right', Icons.keyboard_arrow_right, Usage.right),
          ]),
          _row(2, [
            _media('Menu', Icons.menu, Media.menu),
            _key('Down', Icons.keyboard_arrow_down, Usage.down),
            _media('Stop', Icons.stop, Media.stop),
          ]),
          const SizedBox(height: 8),
          _row(2, [
            _media('Dimmer', Icons.brightness_low, Media.brightnessDown),
            _media('Brighter', Icons.brightness_high, Media.brightnessUp),
          ]),
        ],
      ),
    );
  }
}
