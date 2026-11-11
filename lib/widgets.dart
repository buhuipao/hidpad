import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hid.dart';
import 'keys.dart';

const _gap = 3.0;

/// Orientation of every screen except the PC keyboard.
const portraitOnly = [DeviceOrientation.portraitUp];

/// A key that reports finger down and finger up, so keys can be held.
class PressKey extends StatefulWidget {
  const PressKey({
    super.key,
    this.label,
    this.icon,
    this.semanticLabel,
    required this.onDown,
    this.onUp,
    this.active = false,
    this.primary = false,
  });

  final String? label;
  final IconData? icon;
  final String? semanticLabel;
  final VoidCallback onDown;
  final VoidCallback? onUp;

  /// Shown as switched on (a latched modifier key).
  final bool active;

  /// The main action of the screen.
  final bool primary;

  @override
  State<PressKey> createState() => _PressKeyState();
}

class _PressKeyState extends State<PressKey> {
  int _fingers = 0;

  void _down(PointerDownEvent _) {
    setState(() => _fingers++);
    if (_fingers > 1) return;
    HapticFeedback.selectionClick();
    widget.onDown();
  }

  void _up(PointerEvent _) {
    if (_fingers == 0) return;
    setState(() => _fingers--);
    if (_fingers == 0) widget.onUp?.call();
  }

  @override
  void dispose() {
    if (_fingers > 0) widget.onUp?.call(); // never leave a key held on the computer
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lit = _fingers > 0 || widget.active;
    final background = lit
        ? scheme.primary
        : widget.primary
        ? scheme.primaryContainer
        : scheme.surfaceContainerHigh;
    final foreground = lit
        ? scheme.onPrimary
        : widget.primary
        ? scheme.onPrimaryContainer
        : scheme.onSurface;
    final icon = widget.icon;
    final label = widget.label;
    return Semantics(
      button: true,
      label: widget.semanticLabel ?? label,
      onTap: () {
        widget.onDown();
        widget.onUp?.call();
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          margin: const EdgeInsets.all(_gap),
          padding: const EdgeInsets.all(4),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10)),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) Icon(icon, color: foreground),
                  if (label != null)
                    Text(
                      label,
                      style: (icon == null ? theme.textTheme.titleMedium : theme.textTheme.labelSmall)?.copyWith(
                        color: foreground,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Laptop-style touchpad: move, tap to click, two fingers to scroll or right-click,
/// three-finger tap for middle click, hold still to drag.
class Touchpad extends StatefulWidget {
  const Touchpad({super.key});

  @override
  State<Touchpad> createState() => _TouchpadState();
}

class _TouchpadState extends State<Touchpad> {
  // Feel of the touchpad. Lengths are logical pixels.
  static const _deadZone = 3.0; // a finger must travel this far before the pointer moves
  static const _tapSlop = 12.0; // travel per finger that still counts as a tap
  static const _tapTime = Duration(milliseconds: 250);
  static const _holdTime = Duration(milliseconds: 400); // hold still this long to start a drag
  static const _scrollStep = 18.0; // finger travel per wheel notch
  static const _defaultSpeed = 2.0;

  final _hid = Hid.instance;
  final _pointers = <int>{};
  final _watch = Stopwatch();
  int _fingers = 0; // most fingers seen in this gesture
  double _travel = 0; // path length of this gesture, all fingers
  Offset _origin = Offset.zero; // where the first finger landed
  Timer? _hold;
  bool _dragging = false;

  void _down(PointerDownEvent event) {
    _hold?.cancel();
    if (_pointers.isEmpty) {
      _fingers = 0;
      _travel = 0;
      _origin = event.position;
      _watch
        ..reset()
        ..start();
      _hold = Timer(_holdTime, _startDrag);
    }
    _pointers.add(event.pointer);
    _fingers = max(_fingers, _pointers.length);
  }

  void _move(PointerMoveEvent event) {
    _travel += event.delta.distance;
    // A hold means the finger stays where it landed. Path length would also count jitter.
    if ((event.position - _origin).distance > _deadZone) _hold?.cancel();
    if (_travel < _deadZone) return;
    if (_pointers.length == 1) {
      final speed = _hid.prefDouble(Pref.pointerSpeed, _defaultSpeed);
      _hid.movePointer(event.delta.dx * speed, event.delta.dy * speed);
    } else {
      // Every finger reports its own movement, so share it out. By default the page
      // follows the fingers, like on a phone screen.
      final direction = _hid.prefBool(Pref.reverseScroll, false) ? -1 : 1;
      final notches = direction / (_scrollStep * _pointers.length);
      _hid.scroll(event.delta.dy * notches, -event.delta.dx * notches);
    }
  }

  void _up(PointerEvent event) {
    if (!_pointers.remove(event.pointer) || _pointers.isNotEmpty) return;
    _hold?.cancel();
    if (_dragging) {
      setState(() => _dragging = false);
      _hid.mouseButton(MouseButton.left, false);
    } else if (event is PointerUpEvent && _travel <= _tapSlop * _fingers && _watch.elapsed < _tapTime) {
      _hid.click(switch (_fingers) {
        1 => MouseButton.left,
        2 => MouseButton.right,
        _ => MouseButton.middle,
      });
    }
  }

  void _startDrag() {
    if (_pointers.length != 1) return;
    setState(() => _dragging = true);
    HapticFeedback.mediumImpact();
    _hid.mouseButton(MouseButton.left, true);
  }

  @override
  void dispose() {
    _hold?.cancel();
    if (_dragging) _hid.mouseButton(MouseButton.left, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: 'Touchpad',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.all(_gap),
          padding: const EdgeInsets.all(24),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _dragging ? scheme.primary : scheme.outlineVariant, width: _dragging ? 2 : 1),
          ),
          child: Text(
            _dragging
                ? 'Dragging'
                : 'Tap to click\nTwo fingers to scroll or right-click\nHold still, then move, to drag',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Pointer speed and scroll direction.
void showPointerSettings(BuildContext context) {
  final hid = Hid.instance;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => ValueListenableBuilder(
      valueListenable: hid.prefs,
      builder: (context, _, _) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Pointer speed'),
              subtitle: Slider(
                min: 0.5,
                max: 5,
                divisions: 9,
                value: hid.prefDouble(Pref.pointerSpeed, _TouchpadState._defaultSpeed),
                label: hid.prefDouble(Pref.pointerSpeed, _TouchpadState._defaultSpeed).toStringAsFixed(1),
                onChanged: (value) => hid.setPref(Pref.pointerSpeed, value),
              ),
            ),
            SwitchListTile(
              title: const Text('Reverse scroll direction'),
              value: hid.prefBool(Pref.reverseScroll, false),
              onChanged: (value) => hid.setPref(Pref.reverseScroll, value),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Text box that sends what is typed with the phone keyboard to the computer, as it is typed.
class TypingField extends StatefulWidget {
  const TypingField({super.key});

  @override
  State<TypingField> createState() => _TypingFieldState();
}

class _TypingFieldState extends State<TypingField> {
  // An invisible first character, so Backspace in an empty box still produces a change.
  static const _anchor = '​';

  final _hid = Hid.instance;
  final _controller = TextEditingController(text: _anchor);
  String _sent = ''; // text of the current line that is already on the computer

  /// Shows [text] after the anchor, with the cursor at the end.
  void _show(String text) => _controller.value = TextEditingValue(
    text: '$_anchor$text',
    selection: TextSelection.collapsed(offset: text.length + 1),
  );

  void _changed(String value) {
    final text = value.replaceAll(_anchor, '');
    if (!value.startsWith(_anchor)) {
      if (text.isEmpty && _sent.isEmpty) _hid.tapKey(Usage.backspace);
      _show(text);
    }
    // Undo what differs from the last version (autocorrect can rewrite a word), then type the rest.
    var same = 0;
    while (same < text.length && same < _sent.length && text[same] == _sent[same]) {
      same++;
    }
    final removed = _sent.substring(same).runes.where((rune) => usKey(String.fromCharCode(rune)) != null);
    for (var i = 0; i < removed.length; i++) {
      _hid.tapKey(Usage.backspace);
    }
    _hid.typeText(text.substring(same));
    _sent = text;
  }

  void _enter() {
    _hid.tapKey(Usage.enter);
    _show('');
    _sent = '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gap, 8, _gap, _gap),
      child: TextField(
        controller: _controller,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.visiblePassword, // plain Latin keys, no word suggestions
        textInputAction: TextInputAction.send,
        onChanged: _changed,
        onEditingComplete: _enter, // also keeps the keyboard open
        decoration: InputDecoration(
          labelText: 'Type to send keys',
          floatingLabelBehavior: FloatingLabelBehavior.always,
          prefixIcon: const Icon(Icons.keyboard_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

/// Strip shown on control screens while no computer is connected.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, required this.onOpenDevices});

  final VoidCallback onOpenDevices;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder(
      valueListenable: Hid.instance.state,
      builder: (context, state, _) => state.connected
          ? const SizedBox.shrink()
          : Material(
              color: scheme.errorContainer,
              child: InkWell(
                onTap: onOpenDevices,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.bluetooth_disabled, color: scheme.onErrorContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Not connected. Tap to open Bluetooth devices.',
                          style: TextStyle(color: scheme.onErrorContainer),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: scheme.onErrorContainer),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
