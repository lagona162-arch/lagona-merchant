class ProductAddon {
  final String id;
  final String productId;
  final String name;
  final double price;
  final int stock;
  final bool isAvailable;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProductAddon({
    required this.id,
    required this.productId,
    required this.name,
    required this.price,
    this.stock = 0,
    this.isAvailable = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProductAddon.fromJson(Map<String, dynamic> json) {
    return ProductAddon(
      id: json['id'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Add-on',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      stock: json['stock'] as int? ?? 0,
      isAvailable: json['is_available'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'name': name,
      'price': price,
      'stock': stock,
      'is_available': isAvailable,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class MerchantProduct {
  final String id;
  final String merchantId;
  final String? category;
  final String name;
  final double price;
  final int stock;
  final bool isAvailable;
  final DateTime createdAt;
  final String? imageUrl;
  final List<ProductAddon> addons;

  MerchantProduct({
    required this.id,
    required this.merchantId,
    this.category,
    required this.name,
    required this.price,
    this.stock = 0,
    this.isAvailable = true,
    required this.createdAt,
    this.imageUrl,
    this.addons = const [],
  });

  factory MerchantProduct.fromJson(Map<String, dynamic> json) {
    final addonsJson = json['addons'] as List<dynamic>?;
    final addons = addonsJson != null
        ? addonsJson.map((e) => ProductAddon.fromJson(e as Map<String, dynamic>)).toList()
        : <ProductAddon>[];

    return MerchantProduct(
      id: json['id'] as String? ?? '',
      merchantId: json['merchant_id'] as String? ?? '',
      category: json['category'] as String?,
      name: json['name'] as String? ?? 'Unknown Product',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      stock: json['stock'] as int? ?? 0,
      isAvailable: json['is_available'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      imageUrl: json['image_url'] as String?,
      addons: addons,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'merchant_id': merchantId,
      'category': category,
      'name': name,
      'price': price,
      'stock': stock,
      'is_available': isAvailable,
      'created_at': createdAt.toIso8601String(),
      'image_url': imageUrl,
      'addons': addons.map((addon) => addon.toJson()).toList(),
    };
  }
}
