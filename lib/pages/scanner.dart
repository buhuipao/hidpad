import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

import '../hid.dart';

/// Scans QR codes and barcodes and types their text on the computer.
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  /// A code is sent again only after it was out of view for this long.
  static const _repeatGap = Duration(seconds: 2);
  static const _historySize = 20;

  final _hid = Hid.instance;
  final _viewKey = GlobalKey(debugLabel: 'scanner view');
  StreamSubscription<Barcode>? _scans;
  bool _cameraDenied = false;
  List<String> _history = const [];
  Map<String, DateTime> _lastSeen = const {}; // codes in view now or a moment ago

  void _onViewCreated(QRViewController controller) {
    _scans?.cancel();
    _scans = controller.scannedDataStream.listen(_detect);
  }

  void _onPermissionSet(QRViewController _, bool granted) {
    if (mounted) setState(() => _cameraDenied = !granted);
  }

  void _detect(Barcode barcode) {
    final value = barcode.code;
    if (value == null || value.isEmpty) return;
    final now = DateTime.now();
    final recent = {
      for (final seen in _lastSeen.entries)
        if (now.difference(seen.value) < _repeatGap) seen.key: seen.value,
    };
    final isFresh = !recent.containsKey(value);
    _lastSeen = {...recent, value: now};
    if (!isFresh) return;
    HapticFeedback.mediumImpact();
    _send(value);
    setState(() => _history = [value, ..._history].take(_historySize).toList());
  }

  void _send(String value) => _hid.typeText(_hid.prefBool(Pref.scanEnter, true) ? '$value\n' : value);

  @override
  void dispose() {
    _scans?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              // The view is removed while the camera is denied: it asks for the permission again on
              // every resume, which loops once Android stops showing the prompt.
              child: _cameraDenied
                  ? ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'The camera is off for HidPad.\nAllow it in the system settings, then try again.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(foregroundColor: Colors.white),
                                onPressed: () => setState(() => _cameraDenied = false),
                                child: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : QRView(key: _viewKey, onQRViewCreated: _onViewCreated, onPermissionSet: _onPermissionSet),
            ),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: _hid.prefs,
          builder: (context, _, _) => SwitchListTile(
            title: const Text('Press Enter after each code'),
            value: _hid.prefBool(Pref.scanEnter, true),
            onChanged: (value) => _hid.setPref(Pref.scanEnter, value),
          ),
        ),
        Expanded(
          flex: 2,
          child: _history.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Point the camera at a QR code or barcode.\nIts text is typed on the computer.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView(
                  children: [
                    for (final value in _history)
                      ListTile(
                        dense: true,
                        title: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.keyboard_return, semanticLabel: 'Send again'),
                        onTap: () => _send(value),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
