import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'keys.dart';

/// Status names, the same as Status in MainActivity.kt.
abstract final class HidStatus {
  static const starting = 'starting'; // waiting for the system Bluetooth service or the registration
  static const stalled = 'stalled'; // the registration was not confirmed in time
  static const permission = 'permission';
  static const off = 'off';
  static const unsupported = 'unsupported';
  static const busy = 'busy';
  static const ready = 'ready';
  static const connecting = 'connecting';
  static const connected = 'connected';
}

/// Names of saved settings.
abstract final class Pref {
  static const pointerSpeed = 'speed';
  static const reverseScroll = 'reverseScroll';
  static const scanEnter = 'scanEnter';
}

/// Connection status as reported by MainActivity.kt.
@immutable
class HidState {
  const HidState(this.status, {this.name, this.address});

  /// One of [HidStatus].
  final String status;
  final String? name;
  final String? address;

  bool get connected => status == HidStatus.connected;

  /// Registered as a keyboard, so connecting and pairing can work.
  bool get registered => const {HidStatus.ready, HidStatus.connecting, HidStatus.connected}.contains(status);
}

typedef PairedDevice = ({String name, String address});

/// The phone's Bluetooth keyboard + mouse. Talks to MainActivity.kt over channel "hidpad".
class Hid {
  Hid._();
  static final instance = Hid._();

  static const _channel = MethodChannel('hidpad');

  // Report ids and layouts, see HidDescriptor.kt.
  static const _keyboard = 1;
  static const _mouse = 2;
  static const _consumer = 3;
  static const _keySlots = 6;
  static const _maxStep = 127;

  /// Pause after each key report when typing text, so slow computers do not drop keys.
  static const _keyGap = Duration(milliseconds: 5);

  final state = ValueNotifier(const HidState(HidStatus.starting));

  /// Saved settings, all stored as text.
  final prefs = ValueNotifier(const <String, String>{});

  Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'state') state.value = _parseState(call.arguments as Map);
    });
    prefs.value = await _channel.invokeMapMethod<String, String>('prefs') ?? const {};
    state.value = _parseState(await _channel.invokeMapMethod<String, Object?>('state') ?? const {});
    await fix();
  }

  HidState _parseState(Map<Object?, Object?> map) => HidState(
    map['status'] as String? ?? HidStatus.starting,
    name: map['name'] as String?,
    address: map['address'] as String?,
  );

  // ---- settings ----

  double prefDouble(String key, double fallback) => double.tryParse(prefs.value[key] ?? '') ?? fallback;

  bool prefBool(String key, bool fallback) => (prefs.value[key] ?? '$fallback') == 'true';

  Future<void> setPref(String key, Object value) {
    prefs.value = {...prefs.value, key: '$value'};
    return _channel.invokeMethod('setPref', {'key': key, 'value': '$value'});
  }

  /// Opens [url] in the phone's browser. False when the phone has no app that can open it.
  Future<bool> openUrl(String url) async => await _channel.invokeMethod<bool>('openUrl', url) ?? false;

  // ---- connection ----

  /// Asks the user for whatever is missing (permission, Bluetooth on), then registers.
  /// With [retry], a registration that the system did not confirm in time is started again.
  Future<void> fix({bool retry = false}) => _channel.invokeMethod('fix', retry);

  Future<List<PairedDevice>> devices() async {
    final list = await _channel.invokeListMethod<Map<Object?, Object?>>('devices') ?? const [];
    return [for (final d in list) (name: d['name'] as String, address: d['address'] as String)];
  }

  Future<void> connect(String address) => _channel.invokeMethod('connect', address);

  Future<void> disconnect() => _channel.invokeMethod('disconnect');

  /// Shows the system dialog that makes the phone visible to computers for pairing.
  Future<void> makeDiscoverable() => _channel.invokeMethod('discoverable');

  Future<void> _send(int id, List<int> data) =>
      _channel.invokeMethod('send', {'id': id, 'data': Uint8List.fromList(data)});

  // ---- keyboard ----

  int _mods = 0;
  Set<int> _keys = const {};

  // Keyboard reports go out one after another, so a quick second key cannot overtake the first.
  Future<void> _queue = Future.value();

  Future<void> _enqueue(Future<void> Function() job) {
    final done = _queue.then((_) => job());
    _queue = done.catchError((Object _) {}); // keeps the queue alive; the caller still gets the error
    return done;
  }

  List<int> _keyboardReport(int mods, Set<int> keys) => [
    mods,
    0,
    ...keys.take(_keySlots),
    ...List.filled(max(0, _keySlots - keys.length), 0),
  ];

  Future<void> _sendKeys() => _send(_keyboard, _keyboardReport(_mods, _keys));

  Future<void> keyDown(int usage) => _enqueue(() {
    _keys = {..._keys, usage};
    return _sendKeys();
  });

  Future<void> keyUp(int usage) => _enqueue(() {
    _keys = {..._keys}..remove(usage);
    return _sendKeys();
  });

  /// Holds exactly these modifier keys ([Mod] bits) until changed.
  Future<void> setModifiers(int mods) => _enqueue(() {
    _mods = mods;
    return _sendKeys();
  });

  Future<void> releaseKeys() => _enqueue(() {
    _mods = 0;
    _keys = const {};
    return _sendKeys();
  });

  /// Presses and releases one key, with extra [mods] held for that press.
  Future<void> tapKey(int usage, {int mods = 0}) => _enqueue(() => _tap(usage, mods));

  Future<void> _tap(int usage, int mods) async {
    await _send(_keyboard, _keyboardReport(_mods | mods, {..._keys, usage}));
    await Future<void>.delayed(_keyGap);
    await _sendKeys();
    await Future<void>.delayed(_keyGap);
  }

  /// Types [text] as key presses. Characters that have no US key are skipped.
  Future<void> typeText(String text) => _enqueue(() async {
    for (final rune in text.runes) {
      final key = usKey(String.fromCharCode(rune));
      if (key != null) await _tap(key.usage, key.shift ? Mod.shift : 0);
    }
  });

  // ---- mouse ----

  int _buttons = 0;

  // Parts of a step that did not fit in a whole number yet.
  double _restX = 0;
  double _restY = 0;
  double _restWheel = 0;
  double _restPan = 0;

  Future<void> _sendMouse(int dx, int dy, int wheel, int pan) =>
      _send(_mouse, [_buttons, dx & 0xFF, dy & 0xFF, wheel & 0xFF, pan & 0xFF]);

  Future<void> mouseButton(int button, bool down) {
    _buttons = down ? _buttons | button : _buttons & ~button;
    return _sendMouse(0, 0, 0, 0);
  }

  Future<void> click(int button) async {
    if (_buttons & button != 0) return; // held by an on-screen button: a tap must not release it
    await mouseButton(button, true);
    await mouseButton(button, false);
  }

  /// Moves the pointer by a relative amount. Fractions carry over to the next call.
  Future<void> movePointer(double dx, double dy) async {
    _restX += dx;
    _restY += dy;
    var x = _restX.truncate();
    var y = _restY.truncate();
    _restX -= x;
    _restY -= y;
    while (x != 0 || y != 0) {
      final stepX = x.clamp(-_maxStep, _maxStep);
      final stepY = y.clamp(-_maxStep, _maxStep);
      x -= stepX;
      y -= stepY;
      await _sendMouse(stepX, stepY, 0, 0);
    }
  }

  /// Scrolls by wheel notches: [vertical] up is positive, [horizontal] right is positive.
  Future<void> scroll(double vertical, double horizontal) async {
    _restWheel += vertical;
    _restPan += horizontal;
    final wheel = _restWheel.truncate().clamp(-_maxStep, _maxStep);
    final pan = _restPan.truncate().clamp(-_maxStep, _maxStep);
    _restWheel -= wheel;
    _restPan -= pan;
    if (wheel != 0 || pan != 0) await _sendMouse(0, 0, wheel, pan);
  }

  // ---- media keys ----

  int _media = 0; // the report has room for one media key

  Future<void> mediaKey(int usage, bool down) async {
    if (!down && usage != _media) return; // a newer key already replaced this one
    _media = down ? usage : 0;
    await _send(_consumer, [_media & 0xFF, _media >> 8]);
  }
}
