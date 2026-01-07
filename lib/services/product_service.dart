import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../services/supabase_service.dart';
import '../services/merchant_service.dart';

class ProductService {

  static Future<String?> _getMerchantId() async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return null;

    final merchant = await MerchantService.getMerchantByUserId(userId);
    return merchant?.id;
  }

  static Future<List<String>> getCategories() async {
    final merchantId = await _getMerchantId();
    if (merchantId == null) return [];

    final response = await SupabaseService.client
        .from('merchant_categories')
        .select('name')
        .eq('merchant_id', merchantId)
        .order('name');

    return response.map((e) => e['name'] as String).toList();
  }

  static Future<void> addCategory(String category) async {
    final merchantId = await _getMerchantId();
    if (merchantId == null) throw Exception('Merchant not found');

    final existingCategories = await getCategories();
    if (existingCategories.contains(category)) {
      throw Exception('Category already exists');
    }

    final result = await SupabaseService.client
        .from('merchant_categories')
        .insert({
      'merchant_id': merchantId,
          'name': category,
        })
        .select();

    if (result.isEmpty) {
      throw Exception('Failed to create category');
    }
  }

  static Future<void> updateCategory(String oldCategory, String newCategory) async {
    final merchantId = await _getMerchantId();
    if (merchantId == null) return;

    // Update the category name in merchant_categories table
    await SupabaseService.client
        .from('merchant_categories')
        .update({'name': newCategory})
        .eq('merchant_id', merchantId)
        .eq('name', oldCategory);

    // Update all products that reference this category
    await SupabaseService.client
        .from('merchant_products')
        .update({'category': newCategory})
        .eq('merchant_id', merchantId)
        .eq('category', oldCategory);
  }

  static Future<void> deleteCategory(String category) async {
    final merchantId = await _getMerchantId();
    if (merchantId == null) return;

    // Check if there are any products using this category
    final products = await SupabaseService.client
        .from('merchant_products')
        .select()
        .eq('merchant_id', merchantId)
        .eq('category', category);

    if (products.isNotEmpty) {
      throw Exception('Cannot delete category with existing products');
    }

    // Delete the category from merchant_categories table
    await SupabaseService.client
        .from('merchant_categories')
        .delete()
        .eq('merchant_id', merchantId)
        .eq('name', category);
  }

  static Future<List<MerchantProduct>> getProducts() async {
    final merchantId = await _getMerchantId();
    if (merchantId == null) return [];

    final response = await SupabaseService.client
        .from('merchant_products')
        .select('''
          *,
          product_addons(*)
        ''')
        .eq('merchant_id', merchantId)
        .not('name', 'like', '_CATEGORY_PLACEHOLDER_%')
        .order('created_at', ascending: false);

    return response.map((json) {
      final productJson = Map<String, dynamic>.from(json);
      if (json['product_addons'] != null) {
        productJson['addons'] = json['product_addons'];
      } else {
        productJson['addons'] = <dynamic>[];
      }
      return MerchantProduct.fromJson(productJson);
    }).toList();
  }

  static Future<void> addProduct({
    required String name,
    String? category,
    required double price,
    int stock = 0,
    bool isAvailable = true,
    File? imageFile,
  }) async {
    final merchantId = await _getMerchantId();
    if (merchantId == null) throw Exception('Merchant not found');

    String? imageUrl;
    if (imageFile != null) {
      imageUrl = await _uploadProductImage(imageFile);
    }

    await SupabaseService.client.from('merchant_products').insert({
      'merchant_id': merchantId,
      'name': name,
      'category': category,
      'price': price,
      'stock': stock,
      'is_available': isAvailable,
      if (imageUrl != null) 'image_url': imageUrl,
    });
  }

  static Future<void> updateProduct({
    required String productId,
    required String name,
    String? category,
    required double price,
    required int stock,
    required bool isAvailable,
    File? imageFile,
  }) async {
    final updateData = <String, dynamic>{
      'name': name,
      'category': category,
      'price': price,
      'stock': stock,
      'is_available': isAvailable,
    };

    if (imageFile != null) {
      final imageUrl = await _uploadProductImage(imageFile);
      updateData['image_url'] = imageUrl;
    }

    await SupabaseService.client
        .from('merchant_products')
        .update(updateData)
        .eq('id', productId);
  }

  static Future<void> deleteProduct(String productId) async {
    await SupabaseService.client
        .from('merchant_products')
        .delete()
        .eq('id', productId);
  }

  static Future<String> _uploadProductImage(File file) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
    final filePath = '$userId/merchant-product/$fileName';

    debugPrint('Uploading product image to bucket: merchant-image, path: $filePath with userId: $userId');
    final fileBytes = await file.readAsBytes();

    try {
      await SupabaseService.client.storage
          .from('merchant-image')
          .uploadBinary(
            filePath,
            fileBytes,
          );
    } catch (e) {

      if (e.toString().contains('already exists') || e.toString().contains('409')) {
        try {
          await SupabaseService.client.storage
              .from('merchant-image')
              .remove([filePath]);
          await SupabaseService.client.storage
              .from('merchant-image')
              .uploadBinary(
                filePath,
                fileBytes,
              );
        } catch (e2) {
          throw Exception('Failed to upload product image: ${e2.toString()}');
        }
      } else {
        throw Exception('Failed to upload product image: ${e.toString()}');
      }
    }

    final publicUrl = SupabaseService.client.storage
        .from('merchant-image')
        .getPublicUrl(filePath);

    return publicUrl;
  }

  static Future<List<ProductAddon>> getProductAddons(String productId) async {
    try {
      final response = await SupabaseService.client
          .from('product_addons')
          .select()
          .eq('product_id', productId)
          .order('created_at', ascending: true);

      return response.map((json) => ProductAddon.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching product add-ons: $e');
      return [];
    }
  }

  static Future<void> addProductAddon({
    required String productId,
    required String name,
    required double price,
    int stock = 0,
    bool isAvailable = true,
  }) async {
    try {
      await SupabaseService.client.from('product_addons').insert({
        'product_id': productId,
        'name': name,
        'price': price,
        'stock': stock,
        'is_available': isAvailable,
      });
      debugPrint('Add-on added successfully: $name');
    } catch (e) {
      debugPrint('Error adding product add-on: $e');
      rethrow;
    }
  }

  static Future<void> updateProductAddon({
    required String addonId,
    required String name,
    required double price,
    required int stock,
    required bool isAvailable,
  }) async {
    try {
      await SupabaseService.client
          .from('product_addons')
          .update({
            'name': name,
            'price': price,
            'stock': stock,
            'is_available': isAvailable,
          })
          .eq('id', addonId);
      debugPrint('Add-on updated successfully: $name');
    } catch (e) {
      debugPrint('Error updating product add-on: $e');
      rethrow;
    }
  }

  static Future<void> deleteProductAddon(String addonId) async {
    try {
      await SupabaseService.client
          .from('product_addons')
          .delete()
          .eq('id', addonId);
      debugPrint('Add-on deleted successfully');
    } catch (e) {
      debugPrint('Error deleting product add-on: $e');
      rethrow;
    }
  }
}
