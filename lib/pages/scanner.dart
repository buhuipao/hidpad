import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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
  List<String> _history = const [];
  Map<String, DateTime> _lastSeen = const {}; // codes in view now or a moment ago

  void _detect(BarcodeCapture capture) {
    final now = DateTime.now();
    final inView = {
      for (final barcode in capture.barcodes)
        if (barcode.rawValue case final value? when value.isNotEmpty) value,
    };
    final recent = {
      for (final seen in _lastSeen.entries)
        if (now.difference(seen.value) < _repeatGap) seen.key: seen.value,
    };
    final fresh = inView.where((value) => !recent.containsKey(value)).toList();
    _lastSeen = {...recent, for (final value in inView) value: now};
    if (fresh.isEmpty) return;
    HapticFeedback.mediumImpact();
    fresh.forEach(_send);
    setState(() => _history = [...fresh, ..._history].take(_historySize).toList());
  }

  void _send(String value) => _hid.typeText(_hid.prefBool(Pref.scanEnter, true) ? '$value\n' : value);

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
              child: MobileScanner(onDetect: _detect),
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
