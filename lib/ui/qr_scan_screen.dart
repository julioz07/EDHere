import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../l10n/l10n.dart';

/// Lê um QR code e devolve o texto dele.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Ler QR code'))),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            errorBuilder: (context, error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  tr('Não foi possível usar a câmara ({v}). Confirma a permissão da câmara nas definições da app.',
                      {'v': error.errorCode.name}),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            onDetect: (capture) {
              if (_done) return;
              final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
              if (raw == null) return;
              _done = true;
              Navigator.of(context).pop(raw);
            },
          ),
          IgnorePointer(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
