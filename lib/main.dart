import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hid.dart';
import 'pages/devices.dart';
import 'pages/mouse_keyboard.dart';
import 'pages/multimedia.dart';
import 'pages/numpad.dart';
import 'pages/pc_keyboard.dart';
import 'pages/presenter.dart';
import 'pages/scanner.dart';
import 'widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(portraitOnly); // only the PC keyboard turns sideways
  unawaited(Hid.instance.init());
  runApp(const HidPadApp());
}

class HidPadApp extends StatelessWidget {
  const HidPadApp({super.key});

  static const _seed = Color(0xFF6366F1);

  ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HidPad',
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: const Shell(),
  );
}

typedef _Destination = ({String title, IconData icon, Widget Function() build});

/// App frame: top bar, navigation drawer, and the selected screen.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  static final _controls = <_Destination>[
    (title: 'Mouse / Keyboard', icon: Icons.mouse_outlined, build: MouseKeyboardPage.new),
    (title: 'Multimedia', icon: Icons.live_tv_outlined, build: MultimediaPage.new),
    (title: 'PC keyboard', icon: Icons.keyboard_outlined, build: PcKeyboardPage.new),
    (title: 'Numpad', icon: Icons.dialpad_outlined, build: NumpadPage.new),
    (title: 'Presenter', icon: Icons.co_present_outlined, build: PresenterPage.new),
    (title: 'Code scanner', icon: Icons.qr_code_scanner, build: ScannerPage.new),
  ];
  static final _Destination _devices = (
    title: 'Bluetooth devices',
    icon: Icons.devices_outlined,
    build: DevicesPage.new,
  );
  static final _all = [..._controls, _devices];
  static final _devicesIndex = _all.length - 1;

  static const _landscapeBarHeight = 40.0;

  final _scaffold = GlobalKey<ScaffoldState>();
  int _index = 0;

  void _open(int index) => setState(() => _index = index);

  NavigationDrawerDestination _entry(_Destination d) =>
      NavigationDrawerDestination(icon: Icon(d.icon), label: Text(d.title));

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 16, 16, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back only closes the drawer. A swipe from the screen edge on the touchpad counts as
      // Back, and it must not close the app and drop the connection.
      canPop: false,
      onPopInvokedWithResult: (_, _) => _scaffold.currentState?.closeDrawer(),
      child: _frame(context),
    );
  }

  Widget _frame(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final page = _all[_index];
    return Scaffold(
      key: _scaffold,
      appBar: AppBar(
        // Sideways (PC keyboard) the screen is short, so the keys get the height.
        toolbarHeight: landscape ? _landscapeBarHeight : null,
        title: Text(page.title),
        actions: [
          ValueListenableBuilder(
            valueListenable: Hid.instance.state,
            builder: (context, state, _) => IconButton(
              tooltip: state.connected ? 'Connected to ${state.name}' : 'Not connected',
              icon: Icon(state.connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled),
              color: state.connected ? scheme.primary : scheme.onSurfaceVariant,
              onPressed: () => _open(_devicesIndex),
            ),
          ),
        ],
      ),
      drawerEnableOpenDragGesture: false, // an edge swipe belongs to the touchpad
      drawer: NavigationDrawer(
        selectedIndex: _index,
        onDestinationSelected: (index) {
          _open(index);
          _scaffold.currentState?.closeDrawer();
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 16, 8),
            child: Text('HidPad', style: Theme.of(context).textTheme.headlineSmall),
          ),
          _heading('Controls'),
          ..._controls.map(_entry),
          const Divider(indent: 28, endIndent: 28),
          _heading('Configuration'),
          _entry(_devices),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Sideways the keys need the height; the Bluetooth icon in the top bar still shows the state.
            if (_index != _devicesIndex && !landscape) ConnectionBanner(onOpenDevices: () => _open(_devicesIndex)),
            Expanded(
              child: KeyedSubtree(key: ValueKey(_index), child: page.build()),
            ),
          ],
        ),
      ),
    );
  }
}
