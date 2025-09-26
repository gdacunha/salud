// main.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Barcode Scanner Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color.fromRGBO(101, 215, 190, 1)),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Salude Barcode Scanner Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<String> scannedCodes = [];

  void _addScannedCode(String code) {
    setState(() {
      if (!scannedCodes.contains(code)) {
        scannedCodes.insert(0, code);
      }
    });
  }

  void _clearHistory() {
    setState(() {
      scannedCodes.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          if (scannedCodes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: _clearHistory,
              tooltip: 'Clear History',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.qr_code_scanner,
              size: 100,
              color: Color.fromRGBO(101, 215, 190, 1),
            ),
            const SizedBox(height: 20),
            const Text(
              'Welcome to Salud (Alpha)',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Tap the button below to start scanning barcodes and QR codes',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BarcodeScannerPage(),
                  ),
                );
                if (result != null) {
                  _addScannedCode(result);
                }
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Start Scanning'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 30),
            if (scannedCodes.isNotEmpty) ...[
              const Divider(),
              const Text(
                'Scan History:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: scannedCodes.length,
                  itemBuilder: (context, index) {
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.qr_code),
                        title: Text(
                          scannedCodes[index],
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            // Copy to clipboard functionality would go here
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Copied: ${scannedCodes[index]}'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  MobileScannerController cameraController = MobileScannerController();
  bool _screenOpened = false;
  bool _flashOn = false;
  bool _frontCamera = false;

  @override
  void initState() {
    super.initState();
    _screenOpened = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            color: Colors.white,
            icon: Icon(
              _flashOn ? Icons.flash_on : Icons.flash_off,
              color: _flashOn ? Colors.yellow : Colors.grey,
            ),
            iconSize: 32.0,
            onPressed: () {
              setState(() {
                _flashOn = !_flashOn;
              });
              cameraController.toggleTorch();
            },
          ),
          IconButton(
            color: Colors.white,
            icon: Icon(
              _frontCamera ? Icons.camera_front : Icons.camera_rear,
            ),
            iconSize: 32.0,
            onPressed: () {
              setState(() {
                _frontCamera = !_frontCamera;
              });
              cameraController.switchCamera();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: cameraController,
            onDetect: _foundBarcode,
          ),
          // Overlay with scanning area
          Container(
            decoration: ShapeDecoration(
              shape: QRScannerOverlayShape(
                borderColor: Colors.red,
                borderRadius: 10,
                borderLength: 30,
                borderWidth: 10,
                cutOutSize: MediaQuery.of(context).size.width * 0.8,
              ),
            ),
          ),
          // Instructions at the bottom
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: const Text(
                'Point your camera at a barcode or QR code',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      offset: Offset(1, 1),
                      blurRadius: 2,
                      color: Colors.black,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _foundBarcode(BarcodeCapture capture) {
    if (!_screenOpened) {
      final List<Barcode> barcodes = capture.barcodes;
      for (final barcode in barcodes) {
        if (barcode.rawValue != null) {
          _screenOpened = true;
          Navigator.pop(context, barcode.rawValue);
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }
}

// Custom overlay shape for the scanner
class QRScannerOverlayShape extends ShapeBorder {
  const QRScannerOverlayShape({
    this.borderColor = Colors.red,
    this.borderWidth = 3.0,
    this.overlayColor = const Color.fromRGBO(0, 0, 0, 80),
    this.borderRadius = 0,
    this.borderLength = 40,
    this.cutOutSize = 250,
  });

  final Color borderColor;
  final double borderWidth;
  final Color overlayColor;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(10);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(getOuterPath(rect), Offset.zero);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    Path getLeftTopPath(Rect rect) {
      return Path()
        ..moveTo(rect.left, rect.bottom)
        ..lineTo(rect.left, rect.top + borderRadius)
        ..quadraticBezierTo(rect.left, rect.top, rect.left + borderRadius, rect.top)
        ..lineTo(rect.right, rect.top);
    }

    return getLeftTopPath(rect)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.top);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final width = rect.width;
    // final borderWidthSize = width / 2;
    final height = rect.height;
    final borderOffset = borderWidth / 2;
    final cutOutWidth = cutOutSize;
    final cutOutHeight = cutOutSize;

    final cutOutRect = Rect.fromLTWH(
      rect.left + width / 2 - cutOutWidth / 2 + borderOffset,
      rect.top + height / 2 - cutOutHeight / 2 + borderOffset,
      cutOutWidth - borderOffset * 2,
      cutOutHeight - borderOffset * 2,
    );

    final outerRect = Rect.fromLTWH(rect.left, rect.top, width, height);
    final Paint paint = Paint()..color = overlayColor;
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(outerRect),
        Path()
          ..addRRect(
            RRect.fromRectAndRadius(cutOutRect, Radius.circular(borderRadius)),
          ),
      ),
      paint,
    );

    // Draw the border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final path = Path();
    
    // Top-left corner
    path.moveTo(cutOutRect.left - borderOffset, cutOutRect.top - borderOffset + borderLength);
    path.lineTo(cutOutRect.left - borderOffset, cutOutRect.top - borderOffset + borderRadius);
    path.quadraticBezierTo(cutOutRect.left - borderOffset, cutOutRect.top - borderOffset,
        cutOutRect.left - borderOffset + borderRadius, cutOutRect.top - borderOffset);
    path.lineTo(cutOutRect.left - borderOffset + borderLength, cutOutRect.top - borderOffset);

    // Top-right corner
    path.moveTo(cutOutRect.right + borderOffset - borderLength, cutOutRect.top - borderOffset);
    path.lineTo(cutOutRect.right + borderOffset - borderRadius, cutOutRect.top - borderOffset);
    path.quadraticBezierTo(cutOutRect.right + borderOffset, cutOutRect.top - borderOffset,
        cutOutRect.right + borderOffset, cutOutRect.top - borderOffset + borderRadius);
    path.lineTo(cutOutRect.right + borderOffset, cutOutRect.top - borderOffset + borderLength);

    // Bottom-right corner
    path.moveTo(cutOutRect.right + borderOffset, cutOutRect.bottom + borderOffset - borderLength);
    path.lineTo(cutOutRect.right + borderOffset, cutOutRect.bottom + borderOffset - borderRadius);
    path.quadraticBezierTo(cutOutRect.right + borderOffset, cutOutRect.bottom + borderOffset,
        cutOutRect.right + borderOffset - borderRadius, cutOutRect.bottom + borderOffset);
    path.lineTo(cutOutRect.right + borderOffset - borderLength, cutOutRect.bottom + borderOffset);

    // Bottom-left corner
    path.moveTo(cutOutRect.left - borderOffset + borderLength, cutOutRect.bottom + borderOffset);
    path.lineTo(cutOutRect.left - borderOffset + borderRadius, cutOutRect.bottom + borderOffset);
    path.quadraticBezierTo(cutOutRect.left - borderOffset, cutOutRect.bottom + borderOffset,
        cutOutRect.left - borderOffset, cutOutRect.bottom + borderOffset - borderRadius);
    path.lineTo(cutOutRect.left - borderOffset, cutOutRect.bottom + borderOffset - borderLength);

    canvas.drawPath(path, borderPaint);
  }

  @override
  ShapeBorder scale(double t) {
    return QRScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth,
      overlayColor: overlayColor,
    );
  }
}