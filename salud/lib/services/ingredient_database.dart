import 'dart:convert';
import 'package:flutter/services.dart';

// Database of ingredient risk scores (0-10)
// 0 = Very healthy, 10 = Very unhealthy
class IngredientDatabase {
  static Map<String, double> _riskScores = {};
  static bool _isInitialized = false;
  static String _version = '';
  static String _lastUpdated = '';

  // Initialize the database by loading from JSON file
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Load the JSON file from assets
      final String jsonString = await rootBundle.loadString('assets/ingredient_risk_scores.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      // Extract metadata
      _version = jsonData['version'] ?? 'unknown';
      _lastUpdated = jsonData['last_updated'] ?? 'unknown';

      // Load ingredients
      final Map<String, dynamic> ingredients = jsonData['ingredients'] ?? {};
      _riskScores = ingredients.map((key, value) => MapEntry(
        key.toLowerCase(),
        (value as num).toDouble(),
      ));

      _isInitialized = true;
      print('Ingredient database loaded: v$_version ($_lastUpdated) with ${_riskScores.length} ingredients');
    } catch (e) {
      print('Error loading ingredient database: $e');
      // Fall back to empty database
      _riskScores = {};
      _isInitialized = true;
    }
  }

  // Get risk score for an ingredient (0-10)
  // Returns 5.0 (moderate risk) if ingredient not found
  static double getRiskScore(String ingredient) {
    if (!_isInitialized) {
      print('Warning: Ingredient database not initialized. Call initialize() first.');
      return 5.0;
    }

    // Normalize the ingredient name
    String normalized = ingredient.toLowerCase().trim();

    // Check for exact match
    if (_riskScores.containsKey(normalized)) {
      return _riskScores[normalized]!;
    }

    // Check for partial matches
    for (var entry in _riskScores.entries) {
      if (normalized.contains(entry.key) || entry.key.contains(normalized)) {
        return entry.value;
      }
    }

    // Default to moderate risk if not found
    return 5.0;
  }

  // Add or update an ingredient's risk score at runtime
  static void setRiskScore(String ingredient, double score) {
    if (score < 0 || score > 10) {
      throw ArgumentError('Risk score must be between 0 and 10');
    }
    _riskScores[ingredient.toLowerCase().trim()] = score;
  }

  // Get all ingredients in the database
  static Map<String, double> getAllIngredients() {
    return Map.from(_riskScores);
  }

  // Check if database is initialized
  static bool get isInitialized => _isInitialized;

  // Get database version
  static String get version => _version;

  // Get last update date
  static String get lastUpdated => _lastUpdated;

  // Get number of ingredients in database
  static int get count => _riskScores.length;

  // Clear the database (useful for testing or reloading)
  static void clear() {
    _riskScores.clear();
    _isInitialized = false;
    _version = '';
    _lastUpdated = '';
  }
}