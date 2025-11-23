import 'package:flutter/foundation.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../services/supabase_service.dart';
import '../services/merchant_service.dart';

class OrderService {
  // Get orders for current merchant (deliveries only, no user data)
  static Future<List<Delivery>> getMerchantOrders() async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return [];

    final merchant = await MerchantService.getMerchantByUserId(userId);
    if (merchant == null) return [];

    // Only fetch deliveries, no nested user data
    final response = await SupabaseService.client
        .from('deliveries')
        .select('*')
        .eq('merchant_id', merchant.id)
        .order('created_at', ascending: false);

    return response.map((json) => Delivery.fromJson(json)).toList();
  }

  // Get customer information for a specific delivery
  static Future<Map<String, dynamic>?> getCustomerInfo(String customerId) async {
    if (customerId.isEmpty) return null;

    try {
      // Since customers.id = users.id, query users directly
      final user = await SupabaseService.client
          .from('users')
          .select('id, full_name, email')
          .eq('id', customerId)
          .maybeSingle();

      return user;
    } catch (e) {
      debugPrint('Error fetching customer info: $e');
      return null;
    }
  }

  // Get customer name from delivery
  static String? getCustomerName(Delivery delivery) {
    // If delivery has customer info embedded, extract it
    // Otherwise, return null and UI will use customer ID
    return null;
  }

  // Update order status
  static Future<void> updateOrderStatus(
    String orderId,
    DeliveryStatus newStatus,
  ) async {
    await SupabaseService.client
        .from('deliveries')
        .update({'status': newStatus.value})
        .eq('id', orderId);
  }

  // Get order items with stock information
  static Future<List<DeliveryItem>> getOrderItems(String deliveryId) async {
    try {
      final response = await SupabaseService.client
          .from('delivery_items')
          .select('''
            *,
            merchant_products (
              id,
              merchant_id,
              name,
              price,
              stock,
              image_url,
              created_at
            )
          ''')
          .eq('delivery_id', deliveryId);

      debugPrint('Fetched ${response.length} delivery items for delivery $deliveryId');

      return response.map((json) {
        // Handle merchant_products which might be a Map or null
        Map<String, dynamic>? productJson;
        final merchantProducts = json['merchant_products'];
        
        if (merchantProducts != null) {
          if (merchantProducts is Map<String, dynamic>) {
            productJson = merchantProducts;
          } else if (merchantProducts is List && merchantProducts.isNotEmpty) {
            productJson = merchantProducts.first as Map<String, dynamic>?;
          }
        }
        
        debugPrint('Delivery item ${json['id']}: product_id=${json['product_id']}, has_product=${productJson != null}');
        
        try {
          return DeliveryItem(
            id: json['id'] as String? ?? '',
            deliveryId: json['delivery_id'] as String? ?? '',
            productId: json['product_id'] as String? ?? '',
            quantity: json['quantity'] as int? ?? 1,
            subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
            product: productJson != null
                ? MerchantProduct.fromJson(productJson)
                : null,
          );
        } catch (e) {
          debugPrint('Error parsing delivery item ${json['id']}: $e');
          debugPrint('JSON: $json');
          rethrow;
        }
      }).toList();
    } catch (e) {
      debugPrint('Error fetching order items: $e');
      rethrow;
    }
  }

  // Check if order items have sufficient stock
  static Future<Map<String, dynamic>> checkStockAvailability(
    String deliveryId,
  ) async {
    final items = await getOrderItems(deliveryId);
    final issues = <String>[];
    bool allAvailable = true;

    for (var item in items) {
      if (item.product == null) {
        issues.add('Product ${item.productId} not found');
        allAvailable = false;
        continue;
      }

      if (item.product!.stock < item.quantity) {
        issues.add(
          '${item.product!.name}: Required ${item.quantity}, Available ${item.product!.stock}',
        );
        allAvailable = false;
      }
    }

    return {
      'available': allAvailable,
      'issues': issues,
      'items': items,
    };
  }

  // Confirm order availability (check stock and approve)
  static Future<bool> confirmOrderAvailability(String deliveryId) async {
    final stockCheck = await checkStockAvailability(deliveryId);
    
    if (!stockCheck['available'] as bool) {
      return false;
    }

    // Update order status to accepted
    await updateOrderStatus(deliveryId, DeliveryStatus.accepted);
    
    // Reduce stock for ordered items
    final items = stockCheck['items'] as List<DeliveryItem>;
    for (var item in items) {
      if (item.product != null) {
        final newStock = item.product!.stock - item.quantity;
        await SupabaseService.client
            .from('merchant_products')
            .update({'stock': newStock})
            .eq('id', item.productId);
      }
    }

    return true;
  }

  // Request payment from buyer
  static Future<void> requestPayment(String deliveryId) async {
    // Update status to 'accepted' and set payment_requested to true
    await SupabaseService.client
        .from('deliveries')
        .update({
          'status': DeliveryStatus.accepted.value,
          'payment_requested': true,
        })
        .eq('id', deliveryId);
  }

  // Confirm payment received (rider assignment is handled separately)
  static Future<void> confirmPaymentReceived(String deliveryId) async {
    await updateOrderStatus(deliveryId, DeliveryStatus.paymentReceived);
  }
}

