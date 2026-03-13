// This file will handle the api calls for the open food facts api

// api base url: 'https://world.openfoodfacts.org/api/v2'
// api staging url (used for testing): 'https://world.openfoodfacts.net'

import 'package:openfoodfacts/openfoodfacts.dart' as off;

class OpenFoodFactsService {
  // Initialize the OpenFoodFacts API configuration
  static void initialize() {
    off.OpenFoodAPIConfiguration.userAgent = off.UserAgent(
      name: 'Salud',
      url: 'https://github.com/gdacunha/salud',
    );
    off.OpenFoodAPIConfiguration.globalLanguages = <off.OpenFoodFactsLanguage>[
      off.OpenFoodFactsLanguage.ENGLISH
    ];
    off.OpenFoodAPIConfiguration.globalCountry = off.OpenFoodFactsCountry.USA;
  }

  // Get product by barcode using the official package
  static Future<off.Product?> getProductByBarcode(String barcode) async {
    try {
      // Debug: Print the barcode being queried
      print('API Service: Fetching product for barcode: $barcode');

      final configuration = off.ProductQueryConfiguration(
        barcode,
        language: off.OpenFoodFactsLanguage.ENGLISH,
        fields: [
          off.ProductField.ALL, // Get all available fields
        ],
        version: off.ProductQueryVersion.v3,
      );

      final result = await off.OpenFoodAPIClient.getProductV3(configuration);

      // Debug: Print the result status
      print('API Service: Result status for $barcode: ${result.status}');
      print('API Service: Status value: ${result.status}');

      if (result.status == off.ProductResultV3.statusSuccess && result.product != null) {
        // Debug: Print API product info
        print('API Service: Product found - ${result.product!.productName}');
        return result.product;
      }
      else if (result.status == off.ProductResultV3.statusWarning && result.product != null) {
        // Some products return with warning status but still have data
        print('API Service: Product found with warning - ${result.product!.productName}');
        return result.product;
      } 
      else {
        print('API Service: Product not found or invalid status');
        return null;
      }
    } catch (e) {
      print('Error fetching product: $e');
      return null;
    }
  }

  // Search products by name using the official package
  static Future<List<off.Product>> searchProducts(String searchTerm) async {
    try {
      final configuration = off.ProductSearchQueryConfiguration(
        parametersList: <off.Parameter>[off.SearchTerms(terms: [searchTerm])],
        language: off.OpenFoodFactsLanguage.ENGLISH,
        fields: [off.ProductField.ALL],
        version: off.ProductQueryVersion.v3
      );

      final result = await off.OpenFoodAPIClient.searchProducts(
        null,
        configuration,
      );

      if (result.products != null && result.products!.isNotEmpty) {
        return result.products!;
      }
      return [];
    } catch (e) {
      print('Error searching products: $e');
      return [];
    }
  }

  // Get products by category for recommendation system
  static Future<List<off.Product>> getProductsByCategory(String category) async {
    try {
      final configuration = off.ProductSearchQueryConfiguration(
        parametersList: <off.Parameter>[
          //off.SearchTerms(terms: [searchTerm]),
          off.TagFilter.fromType(
            tagFilterType: off.TagFilterType.CATEGORIES,
            tagName: category,
          ),
        ],
        version: off.ProductQueryVersion.v3
      );

      final result = await off.OpenFoodAPIClient.searchProducts(
        null,
        configuration,
      );

      if (result.products != null && result.products!.isNotEmpty) {
        return result.products!;
      }
      return [];
    } catch (e) {
      print('Error fetching category products: $e');
      return [];
    }
  }
}