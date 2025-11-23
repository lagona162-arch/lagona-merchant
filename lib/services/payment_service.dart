import 'dart:io';
import '../models/payment.dart';
import '../services/supabase_service.dart';
import '../services/merchant_service.dart';

class PaymentService {
  // Get payment receipt for an order
  static Future<PaymentReceipt?> getPaymentReceipt(String deliveryId) async {
    try {
      final response = await SupabaseService.client
          .from('payment_receipts')
          .select()
          .eq('delivery_id', deliveryId)
          .maybeSingle();

      if (response == null) return null;
      return PaymentReceipt.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  // Create payment receipt (called when buyer submits payment)
  static Future<void> createPaymentReceipt({
    required String deliveryId,
    File? screenshot,
    required String referenceNumber,
    required String payerName,
    required double amount,
  }) async {
    String? screenshotUrl;
    if (screenshot != null) {
      screenshotUrl = await _uploadPaymentScreenshot(screenshot, deliveryId);
    }

    await SupabaseService.client.from('payment_receipts').insert({
      'delivery_id': deliveryId,
      'screenshot_url': screenshotUrl,
      'reference_number': referenceNumber,
      'payer_name': payerName,
      'amount': amount,
      'status': 'pending',
    });
  }

  // Merchant verifies payment receipt
  static Future<void> verifyPaymentReceipt(
    String paymentReceiptId,
    bool verified,
  ) async {
    await SupabaseService.client
        .from('payment_receipts')
        .update({
          'status': verified ? 'verified' : 'rejected',
        })
        .eq('id', paymentReceiptId);
  }

  // Upload payment screenshot
  static Future<String> _uploadPaymentScreenshot(
    File file,
    String deliveryId,
  ) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
    final filePath = 'payment_receipts/$deliveryId/$fileName';
    final fileBytes = await file.readAsBytes();

    try {
      await SupabaseService.client.storage
          .from('payment-receipts')
          .uploadBinary(filePath, fileBytes);
    } catch (e) {
      if (e.toString().contains('already exists') ||
          e.toString().contains('409')) {
        await SupabaseService.client.storage
            .from('payment-receipts')
            .remove([filePath]);
        await SupabaseService.client.storage
            .from('payment-receipts')
            .uploadBinary(filePath, fileBytes);
      } else {
        throw Exception('Failed to upload payment screenshot: ${e.toString()}');
      }
    }

    final publicUrl = SupabaseService.client.storage
        .from('payment-receipts')
        .getPublicUrl(filePath);

    return publicUrl;
  }
}

