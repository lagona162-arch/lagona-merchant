import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/payment.dart';
import '../services/supabase_service.dart';
import '../services/merchant_service.dart';

class PaymentService {

  static Future<PaymentReceipt?> getPaymentReceipt(String deliveryId) async {
    try {
      final response = await SupabaseService.client
          .from('payments')
          .select()
          .eq('delivery_id', deliveryId)
          .maybeSingle();

      if (response == null) return null;
      return PaymentReceipt.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching payment receipt: $e');
      return null;
    }
  }

  static Future<Map<String, PaymentReceipt?>> getPaymentReceipts(
    List<String> deliveryIds,
  ) async {
    if (deliveryIds.isEmpty) return {};

    try {
      debugPrint('getPaymentReceipts: Fetching receipts for ${deliveryIds.length} delivery IDs');

      final response = await SupabaseService.client
          .from('payments')
          .select();

      debugPrint('getPaymentReceipts: Fetched ${response.length} total payment receipts from database');

      final filteredResponse = response.where((receipt) {
        final deliveryId = receipt['delivery_id'] as String?;
        final matches = deliveryId != null && deliveryIds.contains(deliveryId);
        if (matches) {
          debugPrint('getPaymentReceipts: Found receipt for delivery ${deliveryId?.substring(0, 6)} - Status: ${receipt['status']}');
        }
        return matches;
      }).toList();

      debugPrint('getPaymentReceipts: Filtered to ${filteredResponse.length} matching receipts');

      final Map<String, PaymentReceipt?> receiptsMap = {};

      for (var deliveryId in deliveryIds) {
        receiptsMap[deliveryId] = null;
      }

      for (var receiptData in filteredResponse) {
        try {
          final receipt = PaymentReceipt.fromJson(receiptData);
          receiptsMap[receipt.deliveryId] = receipt;
          debugPrint('getPaymentReceipts: Mapped receipt ${receipt.id.substring(0, 6)} to delivery ${receipt.deliveryId.substring(0, 6)}');
        } catch (e) {
          debugPrint('Error parsing payment receipt: $e');
          debugPrint('Receipt data: $receiptData');
        }
      }

      final receiptsWithData = receiptsMap.entries.where((e) => e.value != null).length;
      debugPrint('getPaymentReceipts: Returning ${receiptsWithData} receipts with data out of ${receiptsMap.length} total');

      return receiptsMap;
    } catch (e) {
      debugPrint('Error fetching payment receipts: $e');
      debugPrint('Stack trace: ${StackTrace.current}');

      return {for (var id in deliveryIds) id: null};
    }
  }


  static Future<Map<String, PaymentReceipt?>> getMerchantPaymentReceipts(
    String merchantId,
  ) async {
    try {

      final deliveriesResponse = await SupabaseService.client
          .from('deliveries')
          .select('id')
          .eq('merchant_id', merchantId);

      if (deliveriesResponse.isEmpty) return {};

      final deliveryIds = deliveriesResponse
          .map<String>((d) => d['id'] as String)
          .toList();

      return await getPaymentReceipts(deliveryIds);
    } catch (e) {
      debugPrint('Error fetching merchant payment receipts: $e');
      return {};
    }
  }

  static Future<List<PaymentReceipt>> getPaymentReceiptsByStatus(
    String merchantId,
    PaymentStatus status,
  ) async {
    try {

      final response = await SupabaseService.client
          .from('payments')
          .select('''
            *,
            deliveries!inner(merchant_id)
          ''')
          .eq('deliveries.merchant_id', merchantId)
          .eq('status', status.value)
          .order('created_at', ascending: false);

      return response
          .map<PaymentReceipt>((json) => PaymentReceipt.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching payment receipts by status: $e');
      return [];
    }
  }

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

    await SupabaseService.client.from('payments').insert({
      'delivery_id': deliveryId,
      'payment_proof_url': screenshotUrl,
      'reference_number': referenceNumber,
      'ewallet_name': payerName,
      'amount': amount,
      'status': 'pending',
    });
  }

  static Future<void> verifyPaymentReceipt(
    String paymentReceiptId,
    bool verified,
  ) async {
    await SupabaseService.client
        .from('payments')
        .update({
          'status': verified ? 'verified' : 'rejected',
        })
        .eq('id', paymentReceiptId);
  }

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
