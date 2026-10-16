import 'dart:math';
import 'package:openfoodfacts/openfoodfacts.dart' as off;

// Salud Health Score v2.0 beta
//
//   Score = clip(B + Δ, 0, 100)
//   B     = 0.7·N + 0.3·((F + S) / 2)
//   N = Nutrient Balance, F = Food Ingredient, S = Processing,
//   Δ = capped goal adjustment (the only place the user's goal enters).
//
// The public API (HealthScoreResult fields, getScoreColor, getScoreDescription)
// still uses a 0–1 scale so existing callers keep working. The 0–100 values
// are available through the new `score`, `baseScore`, `band`, etc. fields.

enum WeightGoal {
  loseWeight,
  gainWeight,
  maintainWeight,
}

/// Which "how much this goal cares" row from section 3.7.2 applies.
enum _Goal { generalHealth, loseWeight, gainWeight }

enum DietStatus { yes, no, unknown }

// Kept so existing settings UI / constructors still compile. Only
// [userWeightGoal] affects the new algorithm; the macro fields are ignored.
class UserPreferences {
  @Deprecated('Unused by Salud Health Score v2')
  final double carbGoalPercentage;
  @Deprecated('Unused by Salud Health Score v2')
  final double proteinGoalPercentage;
  @Deprecated('Unused by Salud Health Score v2')
  final double fatsGoalPercentage;

  final WeightGoal userWeightGoal;

  @Deprecated('Unused by Salud Health Score v2')
  final double carbShortageWeight;
  @Deprecated('Unused by Salud Health Score v2')
  final double proteinShortageWeight;
  @Deprecated('Unused by Salud Health Score v2')
  final double fatShortageWeight;
  @Deprecated('Unused by Salud Health Score v2')
  final double carbSurplusWeight;
  @Deprecated('Unused by Salud Health Score v2')
  final double proteinSurplusWeight;
  @Deprecated('Unused by Salud Health Score v2')
  final double fatSurplusWeight;

  UserPreferences({
    this.carbGoalPercentage = 0.5,
    this.proteinGoalPercentage = 0.25,
    this.fatsGoalPercentage = 0.25,
    this.userWeightGoal = WeightGoal.maintainWeight,
    this.carbShortageWeight = 1.0,
    this.proteinShortageWeight = 1.5,
    this.fatShortageWeight = 1.0,
    this.carbSurplusWeight = 0.8,
    this.proteinSurplusWeight = 0.5,
    this.fatSurplusWeight = 1.2,
  });
}

class HealthScoreResult {
  // ---- Legacy fields (all 0–1) ----
  /// Final score / 100.
  final double overallScore;

  /// Goal fit: 0.5 = no adjustment, >0.5 = goal boosted the score,
  /// <0.5 = goal lowered it. Derived from Δ (range ±12).
  final double energyScore;

  /// Processing Score S / 100 (the old macro score no longer exists).
  final double macroScore;

  /// Food Ingredient Score F / 100.
  final double ingredientScore;

  /// Nutrient Balance Score N / 100.
  final double nutritionScore;

  // ---- New fields ----
  /// Final score, 0–100.
  final double score;

  /// Base Quality Score B (same for every user), 0–100.
  final double baseScore;

  /// Goal adjustment Δ, in score points (about −12 to +12).
  final double goalAdjustment;

  /// Poor / Fair / Good / Excellent.
  final String band;

  /// True if any input was missing or guessed, so the UI should show "estimate".
  final bool isEstimate;

  /// Human-readable notes on what was missing or assumed.
  final List<String> estimateNotes;

  /// Allergen ids from the label (e.g. "en:milk"). Never affects the score.
  final List<String> allergens;

  /// Diet compatibility flags. Never affects the score.
  final Map<String, DietStatus> dietFlags;

  HealthScoreResult({
    required this.overallScore,
    required this.energyScore,
    required this.macroScore,
    required this.ingredientScore,
    required this.nutritionScore,
    this.score = 0,
    this.baseScore = 0,
    this.goalAdjustment = 0,
    this.band = 'Fair',
    this.isEstimate = false,
    this.estimateNotes = const [],
    this.allergens = const [],
    this.dietFlags = const {},
  });
}

class HealthScoreCalculator {
  // ---------------------------------------------------------------------------
  // Reference data (tunable)
  // ---------------------------------------------------------------------------

  // Appendix A – Neutral (0). Checked first.
  static const List<String> _neutralKeywords = [
    'water', 'salt', 'yeast', 'spice', 'pepper', 'paprika', 'cinnamon',
    'garlic powder', 'onion powder', 'vinegar', 'baking soda',
    'sodium bicarbonate', 'natural flavor', 'natural flavour',
    'citric acid', 'lecithin', 'xanthan', 'guar gum', 'pectin',
  ];

  // Appendix A – Refined / processed (−1).
  static const List<String> _refinedKeywords = [
    'sugar', 'syrup', 'dextrose', 'glucose', 'fructose', 'sucrose',
    'maltodextrin', 'enriched', 'bleached', 'white flour', 'wheat flour',
    'flour', 'starch', 'hydrogenated', 'butter', 'shortening', 'margarine',
    'refined', 'vegetable oil', 'palm oil', 'canola oil', 'soybean oil',
    'sunflower oil', 'corn oil', 'cottonseed oil', 'oil',
  ];

  // Appendix A – Whole (+1). Not exhaustive; unknown ingredients score 0.
  static const List<String> _wholeKeywords = [
    'whole', 'oat', 'brown rice', 'quinoa', 'barley', 'bulgur', 'millet',
    'rye', 'buckwheat', 'corn', 'bean', 'lentil', 'chickpea', 'pea', 'soy',
    'almond', 'peanut', 'walnut', 'pecan', 'cashew', 'pistachio', 'hazelnut',
    'nut', 'seed', 'flax', 'chia', 'sesame', 'sunflower', 'pumpkin',
    'apple', 'banana', 'berry', 'strawberr', 'blueberr', 'raspberr', 'orange',
    'lemon', 'lime', 'grape', 'mango', 'pineapple', 'peach', 'pear', 'cherry',
    'date', 'raisin', 'fig', 'coconut', 'avocado', 'tomato', 'potato',
    'carrot', 'spinach', 'kale', 'broccoli', 'cauliflower', 'cabbage',
    'lettuce', 'onion', 'garlic', 'pepper', 'cucumber', 'celery', 'mushroom',
    'zucchini', 'squash', 'beet', 'fruit', 'vegetable',
    'chicken', 'beef', 'turkey', 'pork', 'fish', 'salmon', 'tuna', 'egg',
    'milk', 'meat', 'lamb',
  ];

  // Section 3.5 – flagged additives (each category counts once).
  static const Map<String, List<String>> _additiveFlags = {
    'artificial': [
      'artificial flavor', 'artificial flavour', 'artificial color',
      'artificial colour', 'red 40', 'red 3', 'yellow 5', 'yellow 6',
      'blue 1', 'blue 2', 'sucralose', 'aspartame', 'acesulfame', 'saccharin',
    ],
    'hydrogenated': ['partially hydrogenated'],
    'hfcs': ['high fructose corn syrup', 'high-fructose corn syrup'],
    'msg': ['monosodium glutamate'],
  };

  // Section 3.7.2 – λ table: [energy, protein, sugar]
  static const Map<_Goal, List<double>> _lambda = {
    _Goal.generalHealth: [-0.2, 0.2, -0.3],
    _Goal.loseWeight: [-0.6, 0.2, -0.3],
    _Goal.gainWeight: [0.5, 0.5, -0.2],
  };

  static const List<String> _glutenKeywords = [
    'wheat', 'barley', 'rye', 'malt', 'spelt', 'semolina', 'farina', 'gluten',
  ];

  // ---------------------------------------------------------------------------
  // Entry point
  // ---------------------------------------------------------------------------

  static HealthScoreResult calculateHealthScore(
      off.Product product, UserPreferences userPrefs) {
    final notes = <String>[];
    final nutrients = product.nutriments;

    final ingredientsText = product.ingredientsText ?? '';
    final ingredients = parseIngredients(ingredientsText);
    final allergens = product.allergens?.ids ?? <String>[];
    final dietFlags = _dietFlags(product, ingredientsText);

    // No nutrient data → neutral result (matches old behavior).
    if (nutrients == null) {
      return _neutralResult(
        'No nutrient data available.',
        allergens,
        dietFlags,
      );
    }

    // Calories per 100 g. Used as C (per 100 g is equivalent to per serving
    // because every nutrient is rescaled by the same ratio) and as D.
    final kcal100g =
        nutrients.getValue(off.Nutrient.energyKCal, off.PerSize.oneHundredGrams);
    if (kcal100g == null || kcal100g <= 0) {
      return _neutralResult(
        'Calories missing or zero; cannot score per 100 kcal.',
        allergens,
        dietFlags,
      );
    }

    // --- Step 1: read & normalize ------------------------------------------
    double? read(off.Nutrient n) =>
        nutrients.getValue(n, off.PerSize.oneHundredGrams);

    final fiber = read(off.Nutrient.fiber);
    final protein = read(off.Nutrient.proteins);
    final satFat = read(off.Nutrient.saturatedFat);

    double? sugar = read(off.Nutrient.addedSugars);
    if (sugar == null) {
      sugar = read(off.Nutrient.sugars);
      notes.add(sugar == null
          ? 'Added sugars missing; treated as 0.'
          : 'Added sugars missing; used total sugars.');
    }

    // OFF sodium is in grams. Fall back to salt / 2.5 if needed.
    double? sodiumG = read(off.Nutrient.sodium);
    if (sodiumG == null) {
      final salt = read(off.Nutrient.salt);
      if (salt != null) {
        sodiumG = salt / 2.5;
        notes.add('Sodium missing; derived from salt.');
      }
    }
    final sodiumMg = sodiumG == null ? null : sodiumG * 1000.0;

    if (fiber == null) notes.add('Fiber missing; treated as 0.');
    if (protein == null) notes.add('Protein missing; treated as 0.');
    if (satFat == null) notes.add('Saturated fat missing; treated as 0.');
    if (sodiumMg == null) notes.add('Sodium missing; treated as 0.');

    final fiber100 = normalizePer100Kcal(fiber ?? 0, kcal100g);
    final sugar100 = normalizePer100Kcal(sugar ?? 0, kcal100g);
    final satFat100 = normalizePer100Kcal(satFat ?? 0, kcal100g);
    final sodium100 = normalizePer100Kcal(sodiumMg ?? 0, kcal100g);
    final protein100 = normalizePer100Kcal(protein ?? 0, kcal100g);

    // --- Step 3: N ----------------------------------------------------------
    final n = nutrientBalanceScore(
      fiber100: fiber100,
      sugar100: sugar100,
      satFat100: satFat100,
      sodium100: sodium100,
      protein100: protein100,
    );

    // --- Step 4: F ----------------------------------------------------------
    if (ingredients.isEmpty) {
      notes.add('Ingredient list missing; ingredient score neutral.');
    }
    final f = foodIngredientScore(ingredients);

    // --- Step 5: S ----------------------------------------------------------
    int? nova = product.novaGroup;
    if (nova == null || nova < 1 || nova > 4) {
      nova = ingredients.length >= 5 ? 4 : 3;
      notes.add('NOVA group missing; estimated as group $nova.');
    }
    final s = processingScore(nova, ingredientsText);

    // --- Step 6: B ----------------------------------------------------------
    final b = baseQualityScore(n, f, s);

    // --- Step 7: Δ ----------------------------------------------------------
    final delta = goalAdjustment(
      goal: _mapGoal(userPrefs.userWeightGoal),
      kcalPer100g: kcal100g,
      protein100: protein100,
      sugar100: sugar100,
    );

    // --- Step 8: final ------------------------------------------------------
    final total = _clip(b + delta, 0, 100);

    return HealthScoreResult(
      overallScore: total / 100.0,
      energyScore: _clip((delta + 12.0) / 24.0, 0, 1),
      macroScore: s / 100.0,
      ingredientScore: f / 100.0,
      nutritionScore: n / 100.0,
      score: total,
      baseScore: b,
      goalAdjustment: delta,
      band: bandFor(total),
      isEstimate: notes.isNotEmpty,
      estimateNotes: notes,
      allergens: allergens,
      dietFlags: dietFlags,
    );
  }

  // ---------------------------------------------------------------------------
  // Step 1 – normalize
  // ---------------------------------------------------------------------------

  /// Formula 1: x100 = x × (100 ÷ C)
  static double normalizePer100Kcal(double x, double calories) =>
      x * (100.0 / calories);

  // ---------------------------------------------------------------------------
  // Step 3 – Nutrient Balance Score (0–100)
  // ---------------------------------------------------------------------------

  static double pointsFiber(double x100) => 10.0 * min(x100 / 9.5, 1.0);
  static double pointsSugar(double x100) => 10.0 * max(1.0 - x100 / 10.0, 0.0);
  static double pointsSatFat(double x100) => 10.0 * max(1.0 - x100 / 5.0, 0.0);
  static double pointsSodium(double x100) => 10.0 * max(1.0 - x100 / 225.0, 0.0);
  static double pointsProtein(double x100) => 10.0 * min(x100 / 8.0, 1.0);

  /// Formula 2: N = (sum of five points) ÷ 5 × 10
  static double nutrientBalanceScore({
    required double fiber100,
    required double sugar100,
    required double satFat100,
    required double sodium100,
    required double protein100,
  }) {
    final sum = pointsFiber(fiber100) +
        pointsSugar(sugar100) +
        pointsSatFat(satFat100) +
        pointsSodium(sodium100) +
        pointsProtein(protein100);
    return sum / 5.0 * 10.0;
  }

  // ---------------------------------------------------------------------------
  // Step 4 – Food Ingredient Score (0–100)
  // ---------------------------------------------------------------------------

  /// Splits an ingredient string on top-level commas only, so
  /// "flour (wheat, niacin), sugar" becomes ["flour (wheat, niacin)", "sugar"].
  static List<String> parseIngredients(String text) {
    if (text.trim().isEmpty) return [];
    final cleaned = text.replaceAll('_', '').replaceAll('*', '');
    final parts = <String>[];
    final buf = StringBuffer();
    int depth = 0;
    for (final ch in cleaned.split('')) {
      if (ch == '(' || ch == '[') depth++;
      if ((ch == ')' || ch == ']') && depth > 0) depth--;
      if ((ch == ',' || ch == ';') && depth == 0) {
        parts.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    parts.add(buf.toString());
    return parts
        .map((e) => e.trim().replaceAll(RegExp(r'\.$'), '').trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Returns +1 (whole), −1 (refined/processed) or 0 (neutral).
  static int classifyIngredient(String raw) {
    // Classify on the name only, not the sub-ingredients in parentheses.
    final name = raw.split(RegExp(r'[\(\[]')).first.toLowerCase().trim();
    if (name.isEmpty) return 0;

    bool hasAny(List<String> keys) => keys.any(name.contains);

    if (name.contains('whole')) return 1; // "whole wheat flour", "whole grain"
    if (name.contains('virgin') && name.contains('oil')) return 0;
    if (hasAny(_neutralKeywords) && !hasAny(['sugar', 'oil', 'flour'])) {
      return 0;
    }
    if (hasAny(_refinedKeywords)) return -1;
    if (hasAny(_wholeKeywords)) return 1;
    return 0;
  }

  /// Formulas 3 & 4: R = Σ w·c over first three, F = 50 + (R ÷ W) × 50
  static double foodIngredientScore(List<String> ingredients) {
    if (ingredients.isEmpty) return 50.0;
    const weights = [3, 2, 1];
    final used = min(3, ingredients.length);
    double r = 0;
    double w = 0;
    for (int i = 0; i < used; i++) {
      r += weights[i] * classifyIngredient(ingredients[i]);
      w += weights[i];
    }
    return 50.0 + (r / w) * 50.0;
  }

  // ---------------------------------------------------------------------------
  // Step 5 – Processing Score (0–100)
  // ---------------------------------------------------------------------------

  static int countAdditiveFlags(String ingredientsText) {
    final t = ingredientsText.toLowerCase();
    int count = 0;
    for (final keys in _additiveFlags.values) {
      if (keys.any(t.contains)) count++;
    }
    return count;
  }

  /// Formula 5: S = max(base − 10·n, 0), deduction capped at 30.
  static double processingScore(int novaGroup, String ingredientsText) {
    const base = {1: 100.0, 2: 75.0, 3: 50.0, 4: 10.0};
    final n = countAdditiveFlags(ingredientsText);
    final deduction = min(10.0 * n, 30.0);
    return max((base[novaGroup] ?? 50.0) - deduction, 0.0);
  }

  // ---------------------------------------------------------------------------
  // Step 6 – Base Quality Score
  // ---------------------------------------------------------------------------

  /// Formula 6: B = 0.7·N + 0.3·((F + S) ÷ 2)
  static double baseQualityScore(double n, double f, double s) =>
      0.7 * n + 0.3 * ((f + s) / 2.0);

  // ---------------------------------------------------------------------------
  // Step 7 – Goal Adjustment
  // ---------------------------------------------------------------------------

  static _Goal _mapGoal(WeightGoal g) {
    switch (g) {
      case WeightGoal.loseWeight:
        return _Goal.loseWeight;
      case WeightGoal.gainWeight:
        return _Goal.gainWeight;
      case WeightGoal.maintainWeight:
        return _Goal.generalHealth;
    }
  }

  /// Formula 7: Δ = 12 × tanh(λe·ae + λp·ap + λs·as)
  static double goalAdjustment({
    required _Goal goal,
    required double kcalPer100g,
    required double protein100,
    required double sugar100,
  }) {
    final aE = _clip((kcalPer100g - 250.0) / 250.0, -1, 1);
    final aP = _clip((protein100 - 4.0) / 4.0, -1, 1);
    // Typo fix from the doc: sugar concern uses sugar, not protein.
    final aS = _clip((sugar100 - 5.0) / 5.0, -1, 1);

    final l = _lambda[goal]!;
    return 12.0 * _tanh(l[0] * aE + l[1] * aP + l[2] * aS);
  }

  // ---------------------------------------------------------------------------
  // Step 8 – band
  // ---------------------------------------------------------------------------

  static String bandFor(double score) {
    if (score >= 80) return 'Excellent';
    if (score >= 60) return 'Good';
    if (score >= 40) return 'Fair';
    return 'Poor';
  }

  // ---------------------------------------------------------------------------
  // Step 2 – constraint flags (never scored)
  // ---------------------------------------------------------------------------

  static Map<String, DietStatus> _dietFlags(
      off.Product product, String ingredientsText) {
    final labels = (product.labelsTags ?? <String>[]).map((e) => e.toLowerCase());
    final text = ingredientsText.toLowerCase();
    final analysis = product.ingredientsAnalysisTags;

    DietStatus vegan = DietStatus.unknown;
    switch (analysis?.veganStatus) {
      case off.VeganStatus.VEGAN:
        vegan = DietStatus.yes;
        break;
      case off.VeganStatus.NON_VEGAN:
        vegan = DietStatus.no;
        break;
      default:
        break;
    }

    DietStatus vegetarian = DietStatus.unknown;
    switch (analysis?.vegetarianStatus) {
      case off.VegetarianStatus.VEGETARIAN:
        vegetarian = DietStatus.yes;
        break;
      case off.VegetarianStatus.NON_VEGETARIAN:
        vegetarian = DietStatus.no;
        break;
      default:
        break;
    }

    DietStatus gluten = DietStatus.unknown;
    if (_glutenKeywords.any(text.contains)) {
      gluten = DietStatus.no;
    } else if (labels.any((l) => l == 'en:gluten-free' || l == 'en:no-gluten')) {
      gluten = DietStatus.yes;
    }

    // Halal / kosher only when OFF has a label; never guessed.
    final halal =
        labels.contains('en:halal') ? DietStatus.yes : DietStatus.unknown;
    final kosher =
        labels.contains('en:kosher') ? DietStatus.yes : DietStatus.unknown;

    return {
      'vegan': vegan,
      'vegetarian': vegetarian,
      'halal': halal,
      'kosher': kosher,
      'glutenFree': gluten,
    };
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static HealthScoreResult _neutralResult(
    String note,
    List<String> allergens,
    Map<String, DietStatus> dietFlags,
  ) {
    return HealthScoreResult(
      overallScore: 0.5,
      energyScore: 0.5,
      macroScore: 0.5,
      ingredientScore: 0.5,
      nutritionScore: 0.5,
      score: 50,
      baseScore: 50,
      goalAdjustment: 0,
      band: 'Fair',
      isEstimate: true,
      estimateNotes: [note],
      allergens: allergens,
      dietFlags: dietFlags,
    );
  }

  static double _clip(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);

  // dart:math has no tanh.
  static double _tanh(double x) {
    final e2x = exp(2.0 * x);
    return (e2x - 1.0) / (e2x + 1.0);
  }

  // ---------------------------------------------------------------------------
  // UI helpers (input is the 0–1 overallScore, as before)
  // ---------------------------------------------------------------------------

  static String getScoreColor(double score) {
    if (score >= 0.8) return 'green';
    if (score >= 0.6) return 'lightgreen';
    if (score >= 0.4) return 'yellow';
    if (score >= 0.2) return 'orange';
    return 'red';
  }

  /// Uses the doc's four bands (Poor 0–39, Fair 40–59, Good 60–79, Excellent 80+).
  static String getScoreDescription(double score) => bandFor(score * 100.0);
}