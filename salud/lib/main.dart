// main.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:openfoodfacts/openfoodfacts.dart' as off;
import 'services/openfoodfacts_service.dart';
import 'services/health_score_calculator.dart';
import 'services/database_helper.dart';
import 'dart:convert';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the OpenFoodFacts API configuration
  OpenFoodFactsService.initialize();
  
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
      home: const MyHomePage(title: 'Salud Barcode Scanner Demo'),
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
  List<off.Product> scannedProducts = [];
  bool _isLoading = false;
  int _totalScans = 0;
  int _uniqueProducts = 0;
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // Placeholder user preferences for health score calculation
  final UserPreferences userPrefs = UserPreferences(
    carbGoalPercentage: 0.50,
    proteinGoalPercentage: 0.25,
    fatsGoalPercentage: 0.25,
    userWeightGoal: WeightGoal.gainWeight,
  );

  @override
  void initState() {
    super.initState();
    _loadScannedProducts();
  }
  
  Future<void> _loadScannedProducts() async {
    final scans = await _dbHelper.getAllScans();
    final totalScans = await _dbHelper.getTotalScans();
    final uniqueProducts = await _dbHelper.getUniqueProductCount();
    
    setState(() {
      scannedProducts = scans;
      _totalScans = totalScans;
      _uniqueProducts = uniqueProducts;
    });
    
    print('Loaded ${scans.length} scans from database');
  }

  void _addScannedProduct(off.Product product, double healthScore) async {
    // Convert nutrients to JSON
    final nutrientsJson = json.encode({
      'energyKCal': product.nutriments?.getValue(off.Nutrient.energyKCal, off.PerSize.oneHundredGrams),
      'proteins': product.nutriments?.getValue(off.Nutrient.proteins, off.PerSize.oneHundredGrams),
      'carbohydrates': product.nutriments?.getValue(off.Nutrient.carbohydrates, off.PerSize.oneHundredGrams),
      'fat': product.nutriments?.getValue(off.Nutrient.fat, off.PerSize.oneHundredGrams),
      'fiber': product.nutriments?.getValue(off.Nutrient.fiber, off.PerSize.oneHundredGrams),
    });
    
    final record = ScannedProductRecord(
      barcode: product.barcode ?? 'unknown',
      productName: product.productName ?? 'Unknown Product',
      brand: product.brands,
      imageUrl: product.imageFrontSmallUrl ?? product.imageFrontUrl,
      nutrientsJson: nutrientsJson,
      ingredientsText: product.ingredientsText,
      healthScore: healthScore,
      scannedAt: DateTime.now(),
    );
    await _dbHelper.insertScan(record);
    await _loadScannedProducts();
  }

  void _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text('Are you sure you want to delete all scan history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      await _dbHelper.clearAllScans();
      await _loadScannedProducts();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scan history cleared')),
        );
      }
    }
  }

  Future<void> _handleScannedBarcode(String barcode) async {
    setState(() {
      _isLoading = true;
    });

    // Debug: Print barcode to console
    print('DEBUG: Scanned barcode: $barcode');

    try {
      final product = await OpenFoodFactsService.getProductByBarcode(barcode);
      
      if (product != null) {
        // Calculate health score
        final healthScore = HealthScoreCalculator.calculateHealthScore(
          product,
          userPrefs,
        );
        
        _addScannedProduct(product, healthScore.overallScore);
        // Debug: Print success
        print('DEBUG: Product found - ${product.productName}');
      }
      else {
        // Debug: Print not found
        print('DEBUG: Product not found for barcode: $barcode');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Product not found for barcode: $barcode'),
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'Copy',
                onPressed: () {
                  // You could add clipboard functionality here if needed
                  print('DEBUG: User wants to copy barcode: $barcode');
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      // Debug: Print error
      print('DEBUG: Error fetching product for barcode $barcode: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching product: $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          if (scannedProducts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: _clearHistory,
              tooltip: 'Clear History',
            ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
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
                      await _handleScannedBarcode(result);
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
                if (scannedProducts.isNotEmpty) ...[
                  const Divider(),
                  // Statistics Card
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text(
                                '$_totalScans',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text('Total Scans'),
                            ],
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: Colors.grey,
                          ),
                          Column(
                            children: [
                              Text(
                                '$_uniqueProducts',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text('Unique Items'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Scan History:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: scannedProducts.length,
                      itemBuilder: (context, index) {
                        final record = scannedProducts[index];
                        
                        return Card(
                          child: ListTile(
                            leading: record.imageUrl != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      record.imageUrl!,
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return const Icon(Icons.food_bank, size: 50);
                                      },
                                    ),
                                  )
                                : const Icon(Icons.food_bank, size: 50),
                            title: Text(
                              record.productName,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (record.brand != null && record.brand!.isNotEmpty)
                                  Text(record.brand!),
                                const SizedBox(height: 4),
                                Text(
                                  _formatTimestamp(record.scannedAt),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Text('Health Score: ',
                                        style: TextStyle(fontWeight: FontWeight.bold)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _getScoreColorFromValue(record.healthScore),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${(record.healthScore * 100).toInt()}/100',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      HealthScoreCalculator.getScoreDescription(record.healthScore),
                                      style: TextStyle(
                                        color: _getScoreColorFromValue(record.healthScore),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                await _dbHelper.deleteScan(record.id!);
                                await _loadScannedProducts();
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
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color.fromRGBO(101, 215, 190, 1),
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Fetching product information...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showProductDetails(BuildContext context, off.Product product) {
  // Calculate health score for detail view
    final healthScore = HealthScoreCalculator.calculateHealthScore(
      product,
      userPrefs,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(product.productName ?? 'Unknown Product'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (product.imageFrontUrl != null)
                Center(
                  child: Image.network(
                    product.imageFrontUrl!,
                    height: 150,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.food_bank, size: 100);
                    },
                  ),
                ),
              const SizedBox(height: 16),

              // Health Score Section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getScoreColorFromValue(healthScore.overallScore).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _getScoreColorFromValue(healthScore.overallScore),
                    width: 2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Salud Health Score',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getScoreColorFromValue(healthScore.overallScore),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${(healthScore.overallScore * 100).toInt()}/100',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      HealthScoreCalculator.getScoreDescription(healthScore.overallScore),
                      style: TextStyle(
                        color: _getScoreColorFromValue(healthScore.overallScore),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(height: 16),
                    const Text('Score Breakdown:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _buildScoreBar('Energy', healthScore.energyScore),
                    _buildScoreBar('Macros', healthScore.macroScore),
                    _buildScoreBar('Ingredients', healthScore.ingredientScore),
                    _buildScoreBar('Nutrients', healthScore.nutritionScore),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),

              if (product.brands != null && product.brands!.isNotEmpty) ...[
                const Text('Brand:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(product.brands!),
                const SizedBox(height: 8),
              ],
              const Text('Barcode:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(product.barcode ?? 'Unknown'),
              const SizedBox(height: 8),
              if (product.nutriments != null) ...[
                const Text('Nutrition (per 100g):', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                if (product.nutriments!.getValue(off.Nutrient.energyKCal, off.PerSize.oneHundredGrams) != null)
                  Text('Energy: ${product.nutriments!.getValue(off.Nutrient.energyKCal, off.PerSize.oneHundredGrams)} kcal'),
                if (product.nutriments!.getValue(off.Nutrient.proteins, off.PerSize.oneHundredGrams) != null)
                  Text('Protein: ${product.nutriments!.getValue(off.Nutrient.proteins, off.PerSize.oneHundredGrams)}g'),
                if (product.nutriments!.getValue(off.Nutrient.carbohydrates, off.PerSize.oneHundredGrams) != null)
                  Text('Carbs: ${product.nutriments!.getValue(off.Nutrient.carbohydrates, off.PerSize.oneHundredGrams)}g'),
                if (product.nutriments!.getValue(off.Nutrient.sugars, off.PerSize.oneHundredGrams) != null)
                  Text('Sugars: ${product.nutriments!.getValue(off.Nutrient.sugars, off.PerSize.oneHundredGrams)}g'),
                if (product.nutriments!.getValue(off.Nutrient.fat, off.PerSize.oneHundredGrams) != null)
                  Text('Fat: ${product.nutriments!.getValue(off.Nutrient.fat, off.PerSize.oneHundredGrams)}g'),
                if (product.nutriments!.getValue(off.Nutrient.saturatedFat, off.PerSize.oneHundredGrams) != null)
                  Text('Saturated Fat: ${product.nutriments!.getValue(off.Nutrient.saturatedFat, off.PerSize.oneHundredGrams)}g'),
                if (product.nutriments!.getValue(off.Nutrient.fiber, off.PerSize.oneHundredGrams) != null)
                  Text('Fiber: ${product.nutriments!.getValue(off.Nutrient.fiber, off.PerSize.oneHundredGrams)}g'),
                if (product.nutriments!.getValue(off.Nutrient.sodium, off.PerSize.oneHundredGrams) != null)
                  Text('Sodium: ${product.nutriments!.getValue(off.Nutrient.sodium, off.PerSize.oneHundredGrams)}g'),
                const SizedBox(height: 8),
              ],
              if (product.ingredientsText != null && product.ingredientsText!.isNotEmpty) ...[
                const Text('Ingredients:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(product.ingredientsText!),
                const SizedBox(height: 8),
              ],
              if (product.nutriscore != null) ...[
                const Text('Nutri-Score:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(product.nutriscore!.toUpperCase(), 
                     style: TextStyle(
                       fontSize: 24, 
                       fontWeight: FontWeight.bold,
                       color: _getNutriScoreColor(product.nutriscore!)
                     )),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreBar(String label, double score) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: score,
                  child: Container(
                    height: 20,
                    decoration: BoxDecoration(
                      color: _getScoreColorFromValue(score),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 30,
            child: Text(
              '${(score * 100).toInt()}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
  
  Color _getScoreColorFromValue(double score) {
    if (score >= 0.8) return Colors.green;
    if (score >= 0.6) return Colors.lightGreen;
    if (score >= 0.4) return Colors.yellow[700]!;
    if (score >= 0.2) return Colors.orange;
    return Colors.red;
  }

  Color _getNutriScoreColor(String grade) {
    switch (grade.toLowerCase()) {
      case 'a':
        return Colors.green;
      case 'b':
        return Colors.lightGreen;
      case 'c':
        return Colors.yellow[700]!;
      case 'd':
        return Colors.orange;
      case 'e':
        return Colors.red;
      default:
        return Colors.grey;
    }
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