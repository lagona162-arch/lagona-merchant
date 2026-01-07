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
    required String paymentMethod, // 'e_wallet' or 'in_person'
    String? riderGcashNumber,
    String? referenceNumber,
    String? senderName,
    File? paymentPhoto,
  }) async {
    try {
      String? photoUrl;
      if (paymentPhoto != null) {
        photoUrl = await uploadPaymentPhoto(paymentPhoto, deliveryId);
      }

      // Check if a payment record already exists for this delivery
      final existingPayment = await getMerchantRiderPayment(deliveryId);
      debugPrint('Existing payment check for delivery $deliveryId: ${existingPayment != null ? "Found" : "Not found"}');
      if (existingPayment != null) {
        debugPrint('Existing payment details: id=${existingPayment['id']}, status=${existingPayment['status']}, method=${existingPayment['payment_method']}');
      }
      
      // Prepare payment data - ensure all fields are explicitly set
      final paymentData = <String, dynamic>{
        'amount': amount,
        'payment_method': paymentMethod,
        'status': 'pending_confirmation',
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Set e-wallet fields based on payment method
      if (paymentMethod == 'e_wallet') {
        paymentData['rider_gcash_number'] = riderGcashNumber;
        paymentData['reference_number'] = referenceNumber;
        paymentData['sender_name'] = senderName;
        paymentData['payment_photo_url'] = photoUrl;
      } else {
        // For in-person payments, explicitly set to null
        paymentData['rider_gcash_number'] = null;
        paymentData['reference_number'] = null;
        paymentData['sender_name'] = null;
        paymentData['payment_photo_url'] = null;
      }

      if (existingPayment != null) {
        // RLS policies may prevent updates, so delete and re-insert instead
        final paymentId = existingPayment['id'] as String;
        debugPrint('Deleting existing payment record with ID: $paymentId to re-create with new data');
        
        try {
          // Delete the existing payment record
          await SupabaseService.client
              .from('merchant_rider_payments')
              .delete()
              .eq('id', paymentId);
          
          debugPrint('Deleted existing payment record. Creating new one...');
        } catch (e) {
          debugPrint('Warning: Could not delete existing payment record: $e');
          // Continue anyway - try to insert (might fail due to unique constraint, but worth trying)
        }
        
        // Insert new payment record with updated data
        paymentData['delivery_id'] = deliveryId;
        paymentData['merchant_id'] = merchantId;
        paymentData['rider_id'] = riderId;
        paymentData['created_at'] = DateTime.now().toIso8601String();
        
        final insertResponse = await SupabaseService.client
            .from('merchant_rider_payments')
            .insert(paymentData)
            .select();
        
        if (insertResponse.isEmpty) {
          throw Exception('Failed to create payment record after deleting old one.');
        }
        
        debugPrint('Successfully re-created payment record for delivery: $deliveryId');
        debugPrint('Insert response: $insertResponse');
      } else {
        // Insert new payment record
        paymentData['delivery_id'] = deliveryId;
        paymentData['merchant_id'] = merchantId;
        paymentData['rider_id'] = riderId;
        paymentData['created_at'] = DateTime.now().toIso8601String();
        
        final insertResponse = await SupabaseService.client
            .from('merchant_rider_payments')
            .insert(paymentData)
            .select();
        
        debugPrint('Created new payment record for delivery: $deliveryId');
        debugPrint('Insert response: $insertResponse');
      }

      debugPrint('Merchant-to-rider payment submitted: $deliveryId (method: $paymentMethod)');

      // Set notification title and message based on payment method
      final String title;
      final String message;
      
      if (paymentMethod == 'e_wallet') {
        title = 'Payment Received - Please Confirm';
        message = 'Merchant has sent payment of ₱${amount.toStringAsFixed(2)} via e-wallet. Please confirm receipt.';
      } else {
        // in_person payment
        title = 'Cash Payment Offer - Collect Payment';
        message = 'Merchant offers to pay ₱${amount.toStringAsFixed(2)} in cash. Please collect payment when you meet.';
      }
      
      debugPrint('Creating notification: title="$title", message="$message"');
      
      await SupabaseService.client.from('notifications').insert({
        'rider_id': riderId,
        'delivery_id': deliveryId,
        'type': 'merchant_payment_pending',
        'title': title,
        'message': message,
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
      // Get all payment records for this delivery, ordered by updated_at descending
      // This handles cases where there might be multiple records (e.g., rejected then re-offered)
      // We use updated_at to get the most recently updated record (e.g., when rider accepts)
      final response = await SupabaseService.client
          .from('merchant_rider_payments')
          .select('*')
          .eq('delivery_id', deliveryId)
          .order('updated_at', ascending: false);

      if (response.isEmpty) {
        return null;
      }

      // Return the most recently updated payment record (first one after ordering by updated_at desc)
      // This ensures we get the latest status (e.g., confirmed after rider accepts)
      final latestPayment = response.first as Map<String, dynamic>;
      
      return latestPayment;
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

