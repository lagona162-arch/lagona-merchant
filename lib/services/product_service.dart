import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../services/supabase_service.dart';
import '../services/merchant_service.dart';

class ProductService {
  // Get current merchant ID
  static Future<String?> _getMerchantId() async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return null;

    final merchant = await MerchantService.getMerchantByUserId(userId);
    return merchant?.id;
  }

  // Get all categories
  static Future<List<String>> getCategories() async {
    final merchantId = await _getMerchantId();
    if (merchantId == null) return [];

    final response = await SupabaseService.client
        .from('merchant_products')
        .select('category')
        .eq('merchant_id', merchantId)
        .not('category', 'is', null);

    final categories = response
        .map((e) => e['category'] as String)
        .toSet()
        .toList()
      ..sort();
    return categories;
  }

  // Add category - creates a hidden placeholder product to establish the category
  static Future<void> addCategory(String category) async {
    final merchantId = await _getMerchantId();
    if (merchantId == null) throw Exception('Merchant not found');

    // Check if category already exists
    final existingCategories = await getCategories();
    if (existingCategories.contains(category)) {
      throw Exception('Category already exists');
    }

    // Create a hidden placeholder product to establish the category
    // The category will be available for selection when creating products
    final result = await SupabaseService.client.from('merchant_products').insert({
      'merchant_id': merchantId,
      'name': '_CATEGORY_PLACEHOLDER_$category',
      'category': category,
      'price': 0.01,
      'stock': 0,
    }).select();

    // Keep the placeholder but mark it as hidden via naming convention
    // When fetching products for display, we'll filter these out
    if (result.isEmpty) {
      throw Exception('Failed to create category');
    }
  }

  // Update category
  static Future<void> updateCategory(String oldCategory, String newCategory) async {
    final merchantId = await _getMerchantId();
    if (merchantId == null) return;

    await SupabaseService.client
        .from('merchant_products')
        .update({'category': newCategory})
        .eq('merchant_id', merchantId)
        .eq('category', oldCategory);
  }

  // Delete category (only if no products use it)
  static Future<void> deleteCategory(String category) async {
    final merchantId = await _getMerchantId();
    if (merchantId == null) return;

    // Check for actual products (not placeholders) using this category
    final products = await SupabaseService.client
        .from('merchant_products')
        .select()
        .eq('merchant_id', merchantId)
        .eq('category', category)
        .not('name', 'like', '_CATEGORY_PLACEHOLDER_%');

    if (products.isNotEmpty) {
      throw Exception('Cannot delete category with existing products');
    }

    // Delete the placeholder product for this category
    await SupabaseService.client
        .from('merchant_products')
        .delete()
        .eq('merchant_id', merchantId)
        .eq('category', category)
        .like('name', '_CATEGORY_PLACEHOLDER_%');
  }

  // Get all products (excluding category placeholders)
  static Future<List<MerchantProduct>> getProducts() async {
    final merchantId = await _getMerchantId();
    if (merchantId == null) return [];

    final response = await SupabaseService.client
        .from('merchant_products')
        .select()
        .eq('merchant_id', merchantId)
        .not('name', 'like', '_CATEGORY_PLACEHOLDER_%')
        .order('created_at', ascending: false);

    return response.map((json) => MerchantProduct.fromJson(json)).toList();
  }

  // Add product
  static Future<void> addProduct({
    required String name,
    String? category,
    required double price,
    int stock = 0,
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
      if (imageUrl != null) 'image_url': imageUrl,
    });
  }

  // Update product
  static Future<void> updateProduct({
    required String productId,
    required String name,
    String? category,
    required double price,
    required int stock,
    File? imageFile,
  }) async {
    final updateData = <String, dynamic>{
      'name': name,
      'category': category,
      'price': price,
      'stock': stock,
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

  // Delete product
  static Future<void> deleteProduct(String productId) async {
    await SupabaseService.client
        .from('merchant_products')
        .delete()
        .eq('id', productId);
  }

  // Helper to upload product images
  static Future<String> _uploadProductImage(File file) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    // Use merchant-image bucket with merchant-product folder structure
    // Path structure: {userId}/merchant-product/{filename} to match merchant-image bucket RLS policy [1] = userId
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
    final filePath = '$userId/merchant-product/$fileName';
    
    // Debug: Print path for troubleshooting
    debugPrint('Uploading product image to bucket: merchant-image, path: $filePath with userId: $userId');
    final fileBytes = await file.readAsBytes();

    // Upload file - try to upload, if file exists, remove and re-upload
    try {
      await SupabaseService.client.storage
          .from('merchant-image')
          .uploadBinary(
            filePath,
            fileBytes,
          );
    } catch (e) {
      // If upload fails because file exists, try to remove it first
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
}

