import 'package:flutter/material.dart';

import '../hid.dart';

typedef _Status = ({IconData icon, String title, String? detail, String? action});

_Status _describe(HidState state) => switch (state.status) {
  HidStatus.connected => (
    icon: Icons.bluetooth_connected,
    title: 'Connected to ${state.name}',
    detail: 'Keys and pointer moves go to this device.',
    action: 'Disconnect',
  ),
  HidStatus.connecting => (icon: Icons.bluetooth_searching, title: 'Connecting…', detail: null, action: null),
  HidStatus.ready => (
    icon: Icons.bluetooth,
    title: 'Not connected',
    detail: 'Pick a paired device below, or pair a new one.',
    action: null,
  ),
  HidStatus.permission => (
    icon: Icons.lock_outline,
    title: 'Bluetooth permission needed',
    detail:
        'Allow "Nearby devices" so HidPad can reach your computer. '
        'If no dialog opens, allow it in the system settings for this app.',
    action: 'Allow',
  ),
  HidStatus.off => (icon: Icons.bluetooth_disabled, title: 'Bluetooth is off', detail: null, action: 'Turn on'),
  HidStatus.busy => (
    icon: Icons.error_outline,
    title: 'Bluetooth keyboard role is taken',
    detail: 'Another app may be using this phone as a Bluetooth keyboard. Close that app, then try again.',
    action: 'Try again',
  ),
  HidStatus.unsupported => (
    icon: Icons.error_outline,
    title: 'Not supported on this phone',
    detail: "This phone's Bluetooth cannot act as a keyboard or mouse.",
    action: null,
  ),
  HidStatus.stalled => (
    icon: Icons.error_outline,
    title: 'Bluetooth is slow to start',
    detail: 'The phone has not confirmed the keyboard role yet.',
    action: 'Try again',
  ),
  _ => (
    icon: Icons.bluetooth_searching,
    title: 'Starting Bluetooth…',
    detail: 'If this never finishes, this phone may be unable to act as a Bluetooth keyboard.',
    action: null,
  ),
};

/// Connection status, pairing help, and the list of paired devices.
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> with WidgetsBindingObserver {
  final _hid = Hid.instance;
  List<PairedDevice> _devices = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hid.state.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hid.state.removeListener(_reload);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload(); // the user may have paired in system settings
  }

  Future<void> _reload() async {
    final devices = await _hid.devices();
    if (mounted) setState(() => _devices = devices);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ValueListenableBuilder(
      valueListenable: _hid.state,
      builder: (context, state, _) {
        final status = _describe(state);
        final detail = status.detail;
        final action = status.action;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(status.icon, size: 32, color: state.connected ? scheme.primary : scheme.onSurfaceVariant),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(status.title, style: theme.textTheme.titleMedium),
                          if (detail != null) Text(detail, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    if (action != null) ...[
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: state.connected ? _hid.disconnect : () => _hid.fix(retry: true),
                        child: Text(action),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pair a new device', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text(
                      '1. Tap "Make this phone visible".\n'
                      '2. On the computer, open Bluetooth settings and add a device.\n'
                      '3. Choose this phone and confirm the pairing code on both sides.',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A computer that was paired with this phone before HidPad was set up, or through '
                      'another keyboard app, must be removed on both sides and paired again.',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: state.registered ? _hid.makeDiscoverable : null,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Make this phone visible'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Paired devices', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_devices.isEmpty)
              Text(
                'No paired devices yet.',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            for (final device in _devices)
              Card(
                child: ListTile(
                  enabled: state.registered,
                  leading: const Icon(Icons.computer),
                  title: Text(device.name),
                  subtitle: Text(device.address),
                  trailing: state.connected && state.address == device.address
                      ? Icon(Icons.check_circle, color: scheme.primary, semanticLabel: 'Connected')
                      : const Text('Connect'),
                  onTap: () => _hid.connect(device.address),
                ),
              ),
          ],
        );
      },
    );
  }
}
