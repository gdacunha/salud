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

  // Macro ratio weights for shortage and surplus
  final double carbShortageWeight;
  final double proteinShortageWeight;
  final double fatShortageWeight;
  final double carbSurplusWeight;
  final double proteinSurplusWeight;
  final double fatSurplusWeight;

  UserPreferences({
    this.carbGoalPercentage = 0.5,
    this.proteinGoalPercentage = 0.25,
    this.fatsGoalPercentage = 0.25,
    this.userWeightGoal = WeightGoal.maintainWeight,

    // Default weights - can be tuned
    this.carbShortageWeight = 1.0,
    this.proteinShortageWeight = 1.5,  // Penalize protein shortage more
    this.fatShortageWeight = 1.0,
    this.carbSurplusWeight = 0.8,
    this.proteinSurplusWeight = 0.5,   // Less penalty for extra protein
    this.fatSurplusWeight = 1.2,       // Higher penalty for extra fat
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
  static const double kQ = 0.7;     // Ingreidnet quality constant

  // Macro ratio constants
  static const double alpha = 2.0; // Shortage exponent (controls nonlinearity)

  // Weights - these can be tuned
  static const double wE = 0.25;    // Energy Ratio Score weight
  static const double wM = 0.20;    // Macro Ratio Score weight
  static const double wQ = 0.35;    // Ingredient Quality Score weight
  static const double wN = 0.20;    // Nutrient Density Score weight

  // Calculate the Overall Health Score -- this is the one that is displayed to the user
  static HealthScoreResult calculateHealthScore(off.Product product, UserPreferences userPrefs){
    // Extract nutrient data
    final nutrients = product.nutriments;
    if (nutrients == null) {
      // Return neutral score if no nutrient data
      return HealthScoreResult(
        overallScore: 0.5,
        energyScore: 0.5,
        macroScore: 0.5,
        ingredientScore: 0.5,
        nutritionScore: 0.5,
      );
    }
    // Get calories per 100g
    final calories = nutrients.getValue(off.Nutrient.energyKCal, off.PerSize.oneHundredGrams) ?? 0.0;
    
    // Calculate sub-scores
    final energyScore = _calculateEnergyScore(calories, userPrefs);
    final macroScore = _calculateMacroScore(nutrients, userPrefs);
    final ingredientScore = _calculateIngredientScore(product);
    final nutrientScore = _calculateNutrientDensityScore(nutrients, calories);
    
    // Calculate overall score
    final overallScore = pow(energyScore, wE) * 
                        pow(macroScore, wM) * 
                        pow(ingredientScore, wQ) * 
                        pow(nutrientScore, wN);
    
    return HealthScoreResult(
      overallScore: overallScore.toDouble(),
      energyScore: energyScore,
      macroScore: macroScore,
      ingredientScore: ingredientScore,
      nutritionScore: nutrientScore / 100.0,
    );
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

    // Calculate weighted distance D
    double D = 0.0;
    
    // Carbs
    final carbShortage = max(0.0, userPrefs.carbGoalPercentage - fc);
    final carbSurplus = max(0.0, fc - userPrefs.carbGoalPercentage);
    D += userPrefs.carbShortageWeight * pow(carbShortage, alpha) + 
         userPrefs.carbSurplusWeight * carbSurplus;
    
    // Protein
    final proteinShortage = max(0.0, userPrefs.proteinGoalPercentage - fp);
    final proteinSurplus = max(0.0, fp - userPrefs.proteinGoalPercentage);
    D += userPrefs.proteinShortageWeight * pow(proteinShortage, alpha) + 
         userPrefs.proteinSurplusWeight * proteinSurplus;
    
    // Fat
    final fatShortage = max(0.0, userPrefs.fatsGoalPercentage - ff);
    final fatSurplus = max(0.0, ff - userPrefs.fatsGoalPercentage);
    D += userPrefs.fatShortageWeight * pow(fatShortage, alpha) + 
         userPrefs.fatSurplusWeight * fatSurplus;
    
    // Calculate maximum possible distance (worst case scenario)
    // Worst case: all macros in one category (e.g., 100% carbs, 0% protein, 0% fat)
    final Dmax = userPrefs.carbShortageWeight * pow(userPrefs.carbGoalPercentage, alpha) + 
                 userPrefs.carbSurplusWeight * (1.0 - userPrefs.carbGoalPercentage) +
                 userPrefs.proteinShortageWeight * pow(userPrefs.proteinGoalPercentage, alpha) +
                 userPrefs.fatShortageWeight * pow(userPrefs.fatsGoalPercentage, alpha);
    
    // Macro score (normalized)
    final sM = 1.0 - (D / Dmax);
    
    return sM.clamp(0.0, 1.0);
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
    // Daily Values (DV) - based on FDA recommendations for adults
    final Map<off.Nutrient, double> dailyValues = {
      // Macronutrients
      off.Nutrient.proteins: 50.0,        // g
      off.Nutrient.fiber: 28.0,           // g
      
      // Vitamins (in same units as OFF API returns)
      off.Nutrient.vitaminA: 900.0,       // µg
      off.Nutrient.vitaminB1: 1.2,        // mg
      off.Nutrient.vitaminB2: 1.3,        // mg
      off.Nutrient.pantothenicAcid: 16.0,       // mg (niacin)
      off.Nutrient.vitaminB6: 1.7,        // mg
      off.Nutrient.vitaminB9: 400.0,      // µg (folate)
      off.Nutrient.vitaminB12: 2.4,       // µg
      off.Nutrient.vitaminC: 90.0,        // mg
      off.Nutrient.vitaminD: 20.0,        // µg
      off.Nutrient.vitaminE: 15.0,        // mg
      off.Nutrient.vitaminK: 120.0,       // µg
      
      // Minerals
      off.Nutrient.calcium: 1300.0,       // mg
      off.Nutrient.iron: 18.0,            // mg
      off.Nutrient.magnesium: 420.0,      // mg
      off.Nutrient.phosphorus: 1250.0,    // mg
      off.Nutrient.potassium: 4700.0,     // mg
      off.Nutrient.zinc: 11.0,            // mg
      off.Nutrient.copper: 0.9,           // mg
      off.Nutrient.manganese: 2.3,        // mg
      off.Nutrient.selenium: 55.0,        // µg
    };
    
    double sumCappedContributions = 0.0;
    int nutrientsAboveThreshold = 0;
    int totalNutrients = dailyValues.length;
    
    for (var entry in dailyValues.entries) {
      final nutrient = entry.key;
      final dv = entry.value;
      
      // Get nutrient amount per 100g
      final amount = nutrientFacts.getValue(nutrient, off.PerSize.oneHundredGrams) ?? 0.0;
      
      // Calculate ratio (percent of daily value)
      final ratio = amount / dv;
      
      // Cap contribution at 100% DV to prevent dominance
      final cappedContribution = min(ratio, 1.0);
      sumCappedContributions += cappedContribution;
      
      // Count nutrients that exceed 5% DV threshold
      if (ratio > 0.05) {
        nutrientsAboveThreshold++;
      }
    }
    
    // Density component: average contribution per nutrient
    final densityComponent = sumCappedContributions / totalNutrients;
    
    // Variety component: fraction of nutrients that meaningfully contribute
    final varietyComponent = nutrientsAboveThreshold / totalNutrients;
    
    // Final nutrient score (0-100 scale)
    final sN = 100.0 * densityComponent * varietyComponent;
    
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