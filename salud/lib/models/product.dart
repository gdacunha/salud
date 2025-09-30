class Product {
  final String? barcode;
  final String? name;
  final String? brand;
  final String? imageUrl;
  final Map<String, dynamic>? nutriments;
  final String? ingredients;

  Product({
    this.barcode,
    this.name,
    this.brand,
    this.imageUrl,
    this.nutriments,
    this.ingredients,
  });

  // Convert from API json to product object
  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      barcode: json['code'],
      name: json['product_name'] ?? json['product_name_en'],
      brand: json['brands'],
      imageUrl: json['image_url'],
      nutriments: json['nutriments'],
      ingredients: json['ingredients_text'] ?? json['ingredients_text_en']
    );
  }

  // Convert from Product object to json for local storage
  Map<String, dynamic> toJson() {
    return {
      'code': barcode,
      'product_name': name,
      'brands': brand,
      'image_url': imageUrl,
      'nutriments': nutriments,
      'ingredients_text': ingredients,
    };
  }
}