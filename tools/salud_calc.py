"""
Salud Hybrid Health Score — reference implementation
Matches "Hybrid Health Score — Documentation v2.0" section by section.

Each documentation step is its own function:
  Step 1  -> normalize_per_100kcal()
  Step 3  -> nutrient_balance_score()
  Step 4  -> food_ingredient_score()
  Step 5  -> processing_score()
  Step 6  -> base_quality_score()
  Step 7  -> goal_adjustment()
  Step 8  -> final_score()

(Step 2, constraint flags, is intentionally not part of the numeric
score -- see check_constraint_flags() -- it only produces labels like
"contains peanuts" that are shown to the user, never scored.)
"""

import math


# ---------------------------------------------------------------------------
# Step 1 — Normalize a label value to "per 100 calories"  (Documentation §3)
# ---------------------------------------------------------------------------
def normalize_per_100kcal(amount_per_serving, calories_per_serving):
    """
    Formula 1: x_100 = x * (100 / C)

    amount_per_serving   -- grams or mg of a nutrient, from the label
    calories_per_serving -- C, "Calories" on the label
    """
    if calories_per_serving <= 0:
        raise ValueError("Calories per serving must be greater than 0.")
    return amount_per_serving * (100.0 / calories_per_serving)


# ---------------------------------------------------------------------------
# Step 2 — Constraint flags  (Documentation §4)
# Informational only. Never feeds into the score.
# ---------------------------------------------------------------------------
def check_constraint_flags(allergens, diet_flags):
    """
    allergens  -- list of strings, e.g. ["milk", "peanut"]
    diet_flags -- list of strings, e.g. ["vegan", "gluten-free"]
    Returns a dict for display purposes only.
    """
    return {
        "allergens": list(allergens),
        "diet_flags": list(diet_flags),
    }


# ---------------------------------------------------------------------------
# Step 3 — Nutrient Balance Score, N  (Documentation §5, Formula 2)
# ---------------------------------------------------------------------------
def nutrient_balance_score(fiber_g, added_sugar_g, sat_fat_g, sodium_mg,
                            protein_g, calories_per_serving):
    """
    Takes label values PER SERVING (not yet normalized) and does the
    Step 1 normalization internally, then scores each of the five
    nutrients from 0-10, then combines them into N (0-100).
    """
    fiber_100 = normalize_per_100kcal(fiber_g, calories_per_serving)
    sugar_100 = normalize_per_100kcal(added_sugar_g, calories_per_serving)
    satfat_100 = normalize_per_100kcal(sat_fat_g, calories_per_serving)
    sodium_100 = normalize_per_100kcal(sodium_mg, calories_per_serving)
    protein_100 = normalize_per_100kcal(protein_g, calories_per_serving)

    p_fiber = 10 * min(fiber_100 / 9.5, 1)
    p_sugar = 10 * max(1 - sugar_100 / 10, 0)
    p_satfat = 10 * max(1 - satfat_100 / 5, 0)
    p_sodium = 10 * max(1 - sodium_100 / 225, 0)
    p_protein = 10 * min(protein_100 / 8, 1)

    N = (p_fiber + p_sugar + p_satfat + p_sodium + p_protein) / 5 * 10

    details = {
        "fiber_100": fiber_100, "sugar_100": sugar_100,
        "satfat_100": satfat_100, "sodium_100": sodium_100,
        "protein_100": protein_100,
        "p_fiber": p_fiber, "p_sugar": p_sugar, "p_satfat": p_satfat,
        "p_sodium": p_sodium, "p_protein": p_protein,
    }
    return N, details


# ---------------------------------------------------------------------------
# Step 4 — Food Ingredient Score, F  (Documentation §6, Formulas 3-4)
# ---------------------------------------------------------------------------
def food_ingredient_score(ingredient_categories):
    """
    ingredient_categories -- ordered list of +1 (whole), -1 (refined/
    processed), or 0 (neutral) for the FIRST THREE ingredients on the
    label, in label order (largest amount first).

    Example: ["Sugar", "Enriched flour", "Palm oil"] on the label
    becomes [-1, -1, -1] here.
    """
    first_three = ingredient_categories[:3]
    weights = [3, 2, 1][:len(first_three)]

    R = sum(w * c for w, c in zip(weights, first_three))
    W = sum(weights)

    if W == 0:
        return 50.0  # no ingredients given -> neutral

    F = 50 + (R / W) * 50
    return F


# ---------------------------------------------------------------------------
# Step 5 — Processing Score, S  (Documentation §7, Formula 5)
# ---------------------------------------------------------------------------
NOVA_BASE_POINTS = {1: 100, 2: 75, 3: 50, 4: 10}


def processing_score(nova_group, num_additive_flags):
    """
    nova_group         -- 1, 2, 3, or 4 (see documentation Appendix / §7 table)
    num_additive_flags -- count of: artificial sweetener/color/flavor,
                           partially hydrogenated oil, high-fructose corn
                           syrup, added MSG
    """
    if nova_group not in NOVA_BASE_POINTS:
        raise ValueError("nova_group must be 1, 2, 3, or 4.")

    base = NOVA_BASE_POINTS[nova_group]
    deduction = min(10 * num_additive_flags, 30)
    S = max(base - deduction, 0)
    return S


# ---------------------------------------------------------------------------
# Step 6 — Base Quality Score, B  (Documentation §8, Formula 6)
# ---------------------------------------------------------------------------
def base_quality_score(N, F, S, weight_nutrient=0.7, weight_ingredient_processing=0.3):
    """
    B = 0.7*N + 0.3*((F+S)/2)   by default.
    Weights are exposed as parameters so they can be tuned per the
    "tweakable" requirement, but 0.7 / 0.3 are the documented defaults.
    """
    B = weight_nutrient * N + weight_ingredient_processing * ((F + S) / 2)
    return B


# ---------------------------------------------------------------------------
# Step 7 — Goal Adjustment, Delta  (Documentation §9, Formulas 7)
# ---------------------------------------------------------------------------

# lambda values per goal: (energy, protein, sugar)  -- Documentation §9.2
GOAL_LAMBDAS = {
    "general_health": (-0.2, 0.2, -0.3),
    "lose_weight": (-0.6, 0.2, -0.3),
    "gain_weight": (0.5, 0.5, -0.2),
}


def _clip(value, lo, hi):
    return max(lo, min(hi, value))


def goal_adjustment(calories_per_serving, serving_grams, protein_g, added_sugar_g,
                     goal, delta_max=12):
    """
    Computes the three food properties (energy fit, protein fit, sugar
    concern) and combines them with the chosen goal's lambda weights.

    goal -- one of the keys in GOAL_LAMBDAS ("general_health",
            "lose_weight", "gain_weight"), or a custom (le, lp, ls) tuple.
    """
    protein_100 = normalize_per_100kcal(protein_g, calories_per_serving)
    sugar_100 = normalize_per_100kcal(added_sugar_g, calories_per_serving)
    D = calories_per_serving / serving_grams * 100  # calories per 100g

    a_energy = _clip((D - 250) / 250, -1, 1)
    a_protein = _clip((protein_100 - 4) / 4, -1, 1)
    a_sugar = _clip((sugar_100 - 5) / 5, -1, 1)

    if isinstance(goal, str):
        if goal not in GOAL_LAMBDAS:
            raise ValueError(f"Unknown goal '{goal}'. Options: {list(GOAL_LAMBDAS)}")
        lam_e, lam_p, lam_s = GOAL_LAMBDAS[goal]
    else:
        lam_e, lam_p, lam_s = goal  # custom (le, lp, ls) tuple

    weighted_sum = lam_e * a_energy + lam_p * a_protein + lam_s * a_sugar
    delta = delta_max * math.tanh(weighted_sum)

    details = {
        "D_kcal_per_100g": D, "a_energy": a_energy, "a_protein": a_protein,
        "a_sugar": a_sugar, "lambda_energy": lam_e, "lambda_protein": lam_p,
        "lambda_sugar": lam_s, "weighted_sum": weighted_sum,
    }
    return delta, details


# ---------------------------------------------------------------------------
# Step 8 — Final Score  (Documentation §10, Formula 8)
# ---------------------------------------------------------------------------
def final_score(B, delta):
    return _clip(B + delta, 0, 100)


def score_band(score):
    if score < 40:
        return "Poor"
    elif score < 60:
        return "Fair"
    elif score < 80:
        return "Good"
    else:
        return "Excellent"


# ---------------------------------------------------------------------------
# End-to-end wrapper — runs all steps in order for one food + one goal
# ---------------------------------------------------------------------------
def score_food(food, goal, verbose=True):
    N, nutrient_details = nutrient_balance_score(
        fiber_g=food["fiber_g"],
        added_sugar_g=food["added_sugar_g"],
        sat_fat_g=food["sat_fat_g"],
        sodium_mg=food["sodium_mg"],
        protein_g=food["protein_g"],
        calories_per_serving=food["calories_per_serving"],
    )

    F = food_ingredient_score(food["ingredient_categories"])
    S = processing_score(food["nova_group"], food["num_additive_flags"])
    B = base_quality_score(N, F, S)

    delta, goal_details = goal_adjustment(
        calories_per_serving=food["calories_per_serving"],
        serving_grams=food["serving_grams"],
        protein_g=food["protein_g"],
        added_sugar_g=food["added_sugar_g"],
        goal=goal,
    )

    score = final_score(B, delta)
    band = score_band(score)
    flags = check_constraint_flags(food.get("allergens", []), food.get("diet_flags", []))

    result = {
        "name": food["name"], "goal": goal,
        "N": N, "F": F, "S": S, "B": B,
        "delta": delta, "score": score, "band": band,
        "flags": flags,
        "nutrient_details": nutrient_details,
        "goal_details": goal_details,
    }

    if verbose:
        print(f"\n{food['name']}  —  goal: {goal}")
        print(f"  Nutrient Balance Score (N):   {N:6.1f}")
        print(f"  Food Ingredient Score (F):    {F:6.1f}")
        print(f"  Processing Score (S):         {S:6.1f}")
        print(f"  Base Quality Score (B):       {B:6.1f}")
        print(f"  Goal Adjustment (delta):      {delta:+6.1f}")
        print(f"  FINAL SCORE:                  {score:6.1f}   [{band}]")
        if flags["allergens"] or flags["diet_flags"]:
            print(f"  Flags: allergens={flags['allergens']} diet={flags['diet_flags']}")

    return result


# ---------------------------------------------------------------------------
# main() — tweak the values below to score different foods / goals
# ---------------------------------------------------------------------------
def main_test():
    # -----------------------------------------------------------------
    # FOOD 1 — edit these values to match any food's Nutrition Facts
    # label and ingredient list. Ingredient categories: +1 whole,
    # -1 refined/processed, 0 neutral (see documentation Appendix A).
    # -----------------------------------------------------------------
    apple = {
        "name": "Apple, raw (1 medium)",
        "calories_per_serving": 95,      # C
        "serving_grams": 182,            # grams the label's serving equals
        "fiber_g": 4.4,
        "added_sugar_g": 0,
        "sat_fat_g": 0,
        "sodium_mg": 2,
        "protein_g": 0.5,
        "ingredient_categories": [1],    # ["Apple"] -> whole
        "nova_group": 1,
        "num_additive_flags": 0,
        "allergens": [],
        "diet_flags": ["vegan", "vegetarian", "gluten-free"],
    }

    # -----------------------------------------------------------------
    # FOOD 2 — a second example to compare against
    # -----------------------------------------------------------------
    cookie = {
        "name": "Chocolate sandwich cookies (3 cookies)",
        "calories_per_serving": 160,
        "serving_grams": 34,
        "fiber_g": 1,
        "added_sugar_g": 14,
        "sat_fat_g": 2,
        "sodium_mg": 135,
        "protein_g": 1,
        "ingredient_categories": [-1, -1, -1],  # sugar, enriched flour, palm oil
        "nova_group": 4,
        "num_additive_flags": 0,
        "allergens": ["wheat", "soy"],
        "diet_flags": ["vegetarian"],
    }

    # -----------------------------------------------------------------
    # GOALS to test each food against. Add/remove freely, or pass a
    # custom (energy_lambda, protein_lambda, sugar_lambda) tuple
    # instead of a string key.
    # -----------------------------------------------------------------
    goals_to_test = ["general_health", "lose_weight", "gain_weight"]

    foods = [apple, cookie]

    for food in foods:
        for goal in goals_to_test:
            score_food(food, goal)

def indiv_test():
    nutella = {
        "name": "Nutella",
        "calories_per_serving": 200,      # C
        "serving_grams": 37,            # grams the label's serving equals
        "fiber_g": 1,
        "added_sugar_g": 19,
        "sat_fat_g": 4,
        "sodium_mg": 15,
        "protein_g": 2,
        "ingredient_categories": [-1, -1, 1],    # ["Apple"] -> whole
        "nova_group": 4,
        "num_additive_flags": 1,
        "allergens": ["hazelnuts", "milk", "soy"],
        "diet_flags": ["vegetarian"],
    }

    chicken_strips = {
        "name": "Tyson Crispy Chicken Strips",
        "calories_per_serving": 200,      # C
        "serving_grams": 84,            # grams the label's serving equals
        "fiber_g": 0,
        "added_sugar_g": 0,
        "sat_fat_g": 1.5,
        "sodium_mg": 410,
        "protein_g": 13,
        "ingredient_categories": [1, 0, 0],    # ["Apple"] -> whole
        "nova_group": 4,
        "num_additive_flags": 0,
        "allergens": ["wheat"],
        "diet_flags": [],
    }

    greek_yogurt = {
        "name": "Better Goods Whole Milk Greek Yogurt Plain",
        "calories_per_serving": 140,      # C
        "serving_grams": 170,            # grams the label's serving equals
        "fiber_g": 0,
        "added_sugar_g": 0,
        "sat_fat_g": 4,
        "sodium_mg": 75,
        "protein_g": 16,
        "ingredient_categories": [1],    # ["Apple"] -> whole
        "nova_group": 1,
        "num_additive_flags": 0,
        "allergens": ["milk"],
        "diet_flags": ["vegetarian"],
    }

    goals_to_test = ["general_health", "lose_weight", "gain_weight"]
    foods = [nutella, chicken_strips, greek_yogurt]

    for food in foods:
        for goal in goals_to_test:
            score_food(food, goal)

if __name__ == "__main__":
    #main_test()
    indiv_test()