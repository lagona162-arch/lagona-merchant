class MerchantProduct {
  final String id;
  final String merchantId;
  final String? category;
  final String name;
  final double price;
  final int stock;
  final DateTime createdAt;
  final String? imageUrl;

  MerchantProduct({
    required this.id,
    required this.merchantId,
    this.category,
    required this.name,
    required this.price,
    this.stock = 0,
    required this.createdAt,
    this.imageUrl,
  });

  factory MerchantProduct.fromJson(Map<String, dynamic> json) {
    return MerchantProduct(
      id: json['id'] as String? ?? '',
      merchantId: json['merchant_id'] as String? ?? '',
      category: json['category'] as String?,
      name: json['name'] as String? ?? 'Unknown Product',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      stock: json['stock'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      imageUrl: json['image_url'] as String?,
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
      'created_at': createdAt.toIso8601String(),
      'image_url': imageUrl,
    };
  }
}

