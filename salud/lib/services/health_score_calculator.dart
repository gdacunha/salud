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
    // Get ingredient list from the product
    final ingredientsText = product.ingredientsText;

    // Check if the food product does not have an ingredients list in the OFF database
    if (ingredientsText == null || ingredientsText.isEmpty) {
      return 0.5;       // If no ingredients list return a neutral score
    }

    // Parse ingredients list string into a list
    List<String> ingredients = ingredientsText
                                              .split(',')
                                              .map((e) => e.trim())
                                              .where((e) => e.isNotEmpty)
                                              .toList();
    // Check if there is an element in the list
    if (ingredients.isEmpty) {
      return 0.5;       // If there is no ingredients return and neutral score
    }

    double weightedRiskSum = 0.0;
    double weightSum = 0.0;

    for (int i = 0; i < ingredients.length; i++) {
      // Risk score from 0-10
      final ri = 5;       // TODO: Pull the risk score from the ingredient risk database (5 is a temporary neutral score for now)
      
      // Normal ri score to 0-1
      final riHat = ri / 10.0;

      // Calculate positional weight (earlier ingredients have higher emphasis)
      final wi = pow(kQ, i).toDouble();

      weightedRiskSum += wi *riHat;
      weightSum += wi;
    }

    if (weightSum == 0) {
      return 0.5;
    }

    // Calculate the ingredient quality subscore
    final sQ = 1.0 - weightedRiskSum / weightSum;

    // Clamp in case score falls outside of 0-1
    return sQ.clamp(0.0, 1.0);
  }

  // Calculate the Nutrient Density Subscore
  static double _calculateNutrientDensityScore(off.Nutriments nutrientFacts, double calories) {
    if (calories == 0) {
      return 0.0;
    }

    // Weight conversion constants
    final milligramsConversionConst = 1000.0;
    final microgramsConversionConst = 1000000.0;

    // Sum weight of all nutrients
    double totalNutrientMass = 0.0;

    // Amino Acids
    totalNutrientMass += nutrientFacts.getValue(off.Nutrient.proteins, off.PerSize.oneHundredGrams) ?? 0.0;

    // Fiber
    totalNutrientMass += nutrientFacts.getValue(off.Nutrient.fiber, off.PerSize.oneHundredGrams) ?? 0.0;

    // Vitamins
    // TODO: See if niacin/vitamin b3 is tracked by OFF
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.vitaminA, off.PerSize.oneHundredGrams) ?? 0.0) / microgramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.vitaminB1, off.PerSize.oneHundredGrams) ?? 0.0) / milligramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.vitaminB2, off.PerSize.oneHundredGrams) ?? 0.0) / milligramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.pantothenicAcid, off.PerSize.oneHundredGrams) ?? 0.0) / milligramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.vitaminB6, off.PerSize.oneHundredGrams) ?? 0.0) / milligramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.vitaminB9, off.PerSize.oneHundredGrams) ?? 0.0) / milligramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.vitaminB12, off.PerSize.oneHundredGrams) ?? 0.0) / microgramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.vitaminC, off.PerSize.oneHundredGrams) ?? 0.0) / milligramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.vitaminD, off.PerSize.oneHundredGrams) ?? 0.0) / microgramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.vitaminE, off.PerSize.oneHundredGrams) ?? 0.0) / milligramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.vitaminK, off.PerSize.oneHundredGrams) ?? 0.0) / microgramsConversionConst;

    // Minerals
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.calcium, off.PerSize.oneHundredGrams) ?? 0.0) / milligramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.copper, off.PerSize.oneHundredGrams) ?? 0.0) / milligramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.iodine, off.PerSize.oneHundredGrams) ?? 0.0) / microgramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.iron, off.PerSize.oneHundredGrams) ?? 0.0) / milligramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.magnesium, off.PerSize.oneHundredGrams) ?? 0.0) / milligramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.manganese, off.PerSize.oneHundredGrams) ?? 0.0) / milligramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.phosphorus, off.PerSize.oneHundredGrams) ?? 0.0) / milligramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.potassium, off.PerSize.oneHundredGrams) ?? 0.0) / milligramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.selenium, off.PerSize.oneHundredGrams) ?? 0.0) / microgramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.sodium, off.PerSize.oneHundredGrams) ?? 0.0) / milligramsConversionConst;
    totalNutrientMass += (nutrientFacts.getValue(off.Nutrient.zinc, off.PerSize.oneHundredGrams) ?? 0.0) / milligramsConversionConst;

    // Fatty Acids (already in grams)
    totalNutrientMass += nutrientFacts.getValue(off.Nutrient.omega3, off.PerSize.oneHundredGrams) ?? 0.0;
    totalNutrientMass += nutrientFacts.getValue(off.Nutrient.omega6, off.PerSize.oneHundredGrams) ?? 0.0;

    // Calculate nutrient density
    final dn = totalNutrientMass / 100.0;

    // Calculate nutrient density score
    final sN = 1.0 / (1.0 + kN / dn);

    return sN;
  }

  // Get a color representing the health score
  static String getScoreColor(double score) {
    if (score >= 0.8) return 'green';
    if (score >= 0.6) return 'lightgreen';
    if (score >= 0.4) return 'yellow';
    if (score >= 0.2) return 'orange';
    return 'red';
  }
  
  // Get a text description of the health score
  static String getScoreDescription(double score) {
    if (score >= 0.8) return 'Excellent';
    if (score >= 0.6) return 'Good';
    if (score >= 0.4) return 'Fair';
    if (score >= 0.2) return 'Poor';
    return 'Very Poor';
  }
}