import 'dart:math';
import 'package:openfoodfacts/openfoodfacts.dart' as off;

enum WeightGoal {
    loseWeight,
    gainWeight,
    maintainWeight,
  }

// Contains user preferences and metrics necessary for health score calulation weighting
class UserPreferences {
  // Macro Ratio
  final double carbGoalPercentage;
  final double proteinGoalPercentage;
  final double fatsGoalPercentage;

  // Weight Goal
  final WeightGoal userWeightGoal;

  UserPreferences({
    this.carbGoalPercentage = 0.5,
    this.proteinGoalPercentage = 0.25,
    this.fatsGoalPercentage = 0.25,
    this.userWeightGoal = WeightGoal.maintainWeight,
  }) {
    if ((carbGoalPercentage + proteinGoalPercentage + fatsGoalPercentage) != 1.0) {
      throw ArgumentError("Error: Macro goal must sum to 1.0");
    }
  }
}

class HealthScoreResult {
  final double overallScore;
  final double energyScore;
  final double macroScore;
  final double ingredientScore;
  final double nutritionScore;

  HealthScoreResult({
    required this.overallScore,
    required this.energyScore,
    required this.macroScore,
    required this.ingredientScore,
    required this.nutritionScore
  });
}

class HealthScoreCalculator {
  // Constants - these can be tuned
  static const double kE = 0.01;    // Energy Score constant
  static const double kN = 0.05;    // Nutrient Density constant
  static const double kQ = 0.7;     // Ingreidnet quality constant

  // Weights - these can be tuned
  static const double wE = 0.25;    // Energy Ratio Score weight
  static const double wM = 0.20;    // Macro Ratio Score weight
  static const double wQ = 0.35;    // Ingredient Quality Score weight
  static const double wN = 0.20;    // Nutrient Density Score weight

  // Calculate the Overall Health Score -- this is the one that is displayed to the user
  static HealthScoreResult calculateHealthScore(off.Product product, UserPreferences userPrefs){

  }

  // Calculate the Energy Ratio Subscore
  static double _calculateEnergyScore(double calories, UserPreferences userPrefs) {

  }

  // Calculate the Macro Ration Subscore
  static double _calculateMacroScore(off.Nutriments nutrientFacts, UserPreferences userPrefts) {

  }

  // Calculate Ingredient Quality Subscore
  static double _calculateIngredientScore(off.Product product) {

  }

  // Calculate the Nutrient Density Subscore
  static double _calculateNutrientDensityScore(off.Nutriments nutrientFacts, double calories) {

  }
}