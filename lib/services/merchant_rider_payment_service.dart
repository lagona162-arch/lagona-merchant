import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/supabase_service.dart';

class MerchantRiderPaymentService {
  static Future<String> uploadPaymentPhoto(File photo, String deliveryId) async {
    try {
      final userId = SupabaseService.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final fileName = 'merchant_rider_payment_${deliveryId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '$userId/merchant-rider-payments/$fileName';

      final fileBytes = await photo.readAsBytes();

      try {
        await SupabaseService.client.storage
            .from('merchant-image')
            .uploadBinary(filePath, fileBytes);
      } catch (e) {
        if (e.toString().contains('already exists') || e.toString().contains('409')) {
          await SupabaseService.client.storage
              .from('merchant-image')
              .remove([filePath]);
          await SupabaseService.client.storage
              .from('merchant-image')
              .uploadBinary(filePath, fileBytes);
        } else {
          rethrow;
        }
      }

      final publicUrl = SupabaseService.client.storage
          .from('merchant-image')
          .getPublicUrl(filePath);

      debugPrint('Payment photo uploaded: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('Error uploading payment photo: $e');
      rethrow;
    }
  }

  static Future<void> submitMerchantToRiderPayment({
    required String deliveryId,
    required String merchantId,
    required String riderId,
    required double amount,
    required String riderGcashNumber,
    required String referenceNumber,
    required String senderName,
    required File paymentPhoto,
  }) async {
    try {
      final photoUrl = await uploadPaymentPhoto(paymentPhoto, deliveryId);

      final paymentData = {
        'delivery_id': deliveryId,
        'merchant_id': merchantId,
        'rider_id': riderId,
        'amount': amount,
        'rider_gcash_number': riderGcashNumber,
        'reference_number': referenceNumber,
        'sender_name': senderName,
        'payment_photo_url': photoUrl,
        'status': 'pending_confirmation',
        'created_at': DateTime.now().toIso8601String(),
      };

      await SupabaseService.client
          .from('merchant_rider_payments')
          .insert(paymentData);

      debugPrint('Merchant-to-rider payment submitted: $deliveryId');

      await SupabaseService.client.from('notifications').insert({
        'rider_id': riderId,
        'delivery_id': deliveryId,
        'type': 'merchant_payment_pending',
        'title': 'Payment Received - Please Confirm',
        'message': 'Merchant has sent payment of ₱${amount.toStringAsFixed(2)}. Please confirm receipt.',
        'read': false,
        'created_at': DateTime.now().toIso8601String(),
      });

      debugPrint('Notification sent to rider for payment confirmation');
    } catch (e) {
      debugPrint('Error submitting merchant-to-rider payment: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> getMerchantRiderPayment(String deliveryId) async {
    try {
      final response = await SupabaseService.client
          .from('merchant_rider_payments')
          .select('*')
          .eq('delivery_id', deliveryId)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('Error fetching merchant-rider payment: $e');
      return null;
    }
  }

  static Future<bool> hasMerchantRiderPayment(String deliveryId) async {
    final payment = await getMerchantRiderPayment(deliveryId);
    return payment != null;
  }
}

