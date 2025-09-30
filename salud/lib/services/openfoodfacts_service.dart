// This file will handle the api calls for the open food facts api

// api base url: 'https://world.openfoodfacts.org/api/v2'
// api staging url (used for testing): 'https://world.openfoodfacts.net'

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product.dart';

// Class defines functions that interact with the Open Food Facts API
class OpenFoodFactsService {
  static const String baseUrl = 'https://world.openfoodfacts.net';

  static Future<Product?> getProductByBarcode(String barcode) async {
    try {
      final url = Uri.parse('$baseUrl/product/$barcode.json');
      final response = await http.get(url);

      // If success
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Check if product exists
        if (data['status'] == 1 && data['product'] != null) {
          return Product.fromJson(data['product']);
        }
      }
      return null;
    } catch (e) {
      print('Error fetching product: $e');
      return null;
    }
  }

  // Search products by name
  static Future<List<Product>> searchProducts(String searchTerm) async {
    try {
      final url = Uri.parse('$baseUrl/cgi/search.pl')
          .replace(queryParameters: {
        'search_terms': searchTerm,
        'json': '1',
        'page_size': '10',
        'page': '1',
      });

      final response = await http.get(url);

      // If success
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Check if products exist
        if (data['products'] != null) {
          // Convert list of products to Product object and return list of Product objects
          return (data['products'] as List)
              .map((productJson) => Product.fromJson(productJson))
              .toList();
        }
      }
      return [];
    } catch (e) {
      print('Error searching products: $e');
      return [];
    }
  }

  // Get products by category for recommendation system
  static Future<List<Product>> getProductsByCategory(String category) async {
    try {
      final url = Uri.parse('$baseUrl/cgi/search.pl')
          .replace(queryParameters: {
        'tagtype_0': 'categories',
        'tag_contains_0': 'contains',
        'tag_0': category,
        'json': '1',
        'page_size': '20',
        'page': '1',
      });

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['products'] != null) {
          return (data['products'] as List)
              .map((productJson) => Product.fromJson(productJson))
              .toList();
        }
      }
      return [];
    } catch (e) {
      print('Error fetching category products: $e');
      return [];
    }
  }
}