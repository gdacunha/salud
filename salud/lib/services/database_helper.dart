import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

/// Model for a scanned product record
class ScannedProductRecord {
  final int? id;
  final String barcode;
  final String productName;
  final String? brand;
  final String? imageUrl;
  final String nutrientsJson; // Store nutrients as JSON
  final String? ingredientsText;
  final double healthScore;
  final DateTime scannedAt;
  
  ScannedProductRecord({
    this.id,
    required this.barcode,
    required this.productName,
    this.brand,
    this.imageUrl,
    required this.nutrientsJson,
    this.ingredientsText,
    required this.healthScore,
    required this.scannedAt,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'product_name': productName,
      'brand': brand,
      'image_url': imageUrl,
      'nutrients_json': nutrientsJson,
      'ingredients_text': ingredientsText,
      'health_score': healthScore,
      'scanned_at': scannedAt.toIso8601String(),
    };
  }
  
  factory ScannedProductRecord.fromMap(Map<String, dynamic> map) {
    return ScannedProductRecord(
      id: map['id'] as int?,
      barcode: map['barcode'] as String,
      productName: map['product_name'] as String,
      brand: map['brand'] as String?,
      imageUrl: map['image_url'] as String?,
      nutrientsJson: map['nutrients_json'] as String,
      ingredientsText: map['ingredients_text'] as String?,
      healthScore: map['health_score'] as double,
      scannedAt: DateTime.parse(map['scanned_at'] as String),
    );
  }
}

/// Database helper for managing scanned products
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;
  
  factory DatabaseHelper() => _instance;
  
  DatabaseHelper._internal();
  
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'salud.db');
    
    print('Database path: $path');
    
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }
  
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE scanned_products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT NOT NULL,
        product_name TEXT NOT NULL,
        brand TEXT,
        image_url TEXT,
        nutrients_json TEXT NOT NULL,
        ingredients_text TEXT,
        health_score REAL NOT NULL,
        scanned_at TEXT NOT NULL
      )
    ''');
    
    // Create index on barcode for faster lookups
    await db.execute('''
      CREATE INDEX idx_barcode ON scanned_products(barcode)
    ''');
    
    // Create index on scanned_at for faster time-based queries
    await db.execute('''
      CREATE INDEX idx_scanned_at ON scanned_products(scanned_at DESC)
    ''');
    
    print('Database tables created successfully');
  }
  
  /// Insert a new scanned product
  Future<int> insertScan(ScannedProductRecord record) async {
    final db = await database;
    final id = await db.insert(
      'scanned_products',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    print('Inserted scan with ID: $id');
    return id;
  }
  
  /// Get all scanned products ordered by most recent
  Future<List<ScannedProductRecord>> getAllScans() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'scanned_products',
      orderBy: 'scanned_at DESC',
    );
    
    return List.generate(maps.length, (i) {
      return ScannedProductRecord.fromMap(maps[i]);
    });
  }
  
  /// Get total number of scans
  Future<int> getTotalScans() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM scanned_products');
    return Sqflite.firstIntValue(result) ?? 0;
  }
  
  /// Get number of unique products scanned
  Future<int> getUniqueProductCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(DISTINCT barcode) as count FROM scanned_products');
    return Sqflite.firstIntValue(result) ?? 0;
  }
  
  /// Get scans for a specific barcode
  Future<List<ScannedProductRecord>> getScansByBarcode(String barcode) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'scanned_products',
      where: 'barcode = ?',
      whereArgs: [barcode],
      orderBy: 'scanned_at DESC',
    );
    
    return List.generate(maps.length, (i) {
      return ScannedProductRecord.fromMap(maps[i]);
    });
  }
  
  /// Check if a product has been scanned before
  Future<bool> hasBeenScanned(String barcode) async {
    final db = await database;
    final result = await db.query(
      'scanned_products',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    return result.isNotEmpty;
  }
  
  /// Get the last scan of a specific product
  Future<ScannedProductRecord?> getLastScan(String barcode) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'scanned_products',
      where: 'barcode = ?',
      whereArgs: [barcode],
      orderBy: 'scanned_at DESC',
      limit: 1,
    );
    
    if (maps.isEmpty) return null;
    return ScannedProductRecord.fromMap(maps[0]);
  }
  
  /// Delete a specific scan
  Future<int> deleteScan(int id) async {
    final db = await database;
    return await db.delete(
      'scanned_products',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  /// Delete all scans for a specific barcode
  Future<int> deleteAllScansForBarcode(String barcode) async {
    final db = await database;
    return await db.delete(
      'scanned_products',
      where: 'barcode = ?',
      whereArgs: [barcode],
    );
  }
  
  /// Clear all scans
  Future<int> clearAllScans() async {
    final db = await database;
    return await db.delete('scanned_products');
  }
  
  /// Get scans from the last N days
  Future<List<ScannedProductRecord>> getRecentScans(int days) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    final List<Map<String, dynamic>> maps = await db.query(
      'scanned_products',
      where: 'scanned_at >= ?',
      whereArgs: [cutoffDate.toIso8601String()],
      orderBy: 'scanned_at DESC',
    );
    
    return List.generate(maps.length, (i) {
      return ScannedProductRecord.fromMap(maps[i]);
    });
  }
  
  /// Get average health score
  Future<double> getAverageHealthScore() async {
    final db = await database;
    final result = await db.rawQuery('SELECT AVG(health_score) as avg FROM scanned_products');
    final avg = result[0]['avg'];
    return avg != null ? (avg as num).toDouble() : 0.0;
  }
  
  /// Close the database
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}