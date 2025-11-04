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
  static const double kE = 0.01;    // Energy Score constant -- by default assume user is losing weight
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
    // Calculate Caloric Density
    double dc = calories / 100.0;

    double adjustedKE = kE;

    // Calculate the weight based on the user's goals
    if (userPrefs.userWeightGoal == WeightGoal.loseWeight) {
      // weight gain tweak
      adjustedKE = adjustedKE * 1.5;      // Note: 1.5 is subject to change and tweaking
    }
    else if (userPrefs.userWeightGoal == WeightGoal.maintainWeight) {
      // maintanence tweak
      adjustedKE = adjustedKE * 1.25;     // Note: 1.25 is subject to change and tweaking
    }
    // Otherwise user is losing weight and leave as default

    // Normalize to a score from 1-0
    final double scoreEnergy = 1.0 / (1.0 + adjustedKE * dc);

    return scoreEnergy;
  }

  // Calculate the Macro Ration Subscore
  static double _calculateMacroScore(off.Nutriments nutrientFacts, UserPreferences userPrefs) {
    // Get the foods macros
    final carbs = nutrientFacts.getValue(off.Nutrient.carbohydrates, off.PerSize.oneHundredGrams);
    final protein = nutrientFacts.getValue(off.Nutrient.proteins, off.PerSize.oneHundredGrams);
    final fats = nutrientFacts.getValue(off.Nutrient.fat, off.PerSize.oneHundredGrams);

    final totalMacros = carbs! + protein! + fats!;

    // If there is not macro data return a neutral score of 0.5
    if (totalMacros == 0.0) {
      return 0.5;
    }

    // Calculate macro percentages
    final double fc = carbs / totalMacros;      // Percentage of the product that is carbs
    final double fp = protein / totalMacros;    // Percentage of the product that is protein
    final double ff = fats / totalMacros;       // Percentage of the product that is fat

    // Calculate the distance (similarity) between the user's preferences and the products macro split
    final D = (fc - userPrefs.carbGoalPercentage).abs() + 
              (fp - userPrefs.proteinGoalPercentage).abs() + 
              (ff - userPrefs.fatsGoalPercentage).abs();
    
    // Normalize the distance (similarity) to a score from 0-1 -- the closer the ratios are the higher the score
    final double sM = 1.0 - (D / 2.0);

    return sM;
  }

  // Calculate Ingredient Quality Subscore
  static double _calculateIngredientScore(off.Product product) {

  }

  // Calculate the Nutrient Density Subscore
  static double _calculateNutrientDensityScore(off.Nutriments nutrientFacts, double calories) {

  }
}