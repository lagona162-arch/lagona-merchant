import 'package:flutter/foundation.dart';
import '../services/supabase_service.dart';

class RiderWalletService {
  static Future<void> deductFromRiderWallet({
    required String riderId,
    required double deliveryFee,
    double deductionRate = 0.20,
  }) async {
    if (deliveryFee <= 0) {
      debugPrint('Delivery fee is 0 or negative, skipping deduction');
      return;
    }

    final deductionAmount = deliveryFee * deductionRate;
    debugPrint('Deducting ${deductionAmount.toStringAsFixed(2)} (${(deductionRate * 100).toStringAsFixed(0)}% of ${deliveryFee.toStringAsFixed(2)}) from rider $riderId wallet');

    try {
      final riderData = await SupabaseService.client
          .from('riders')
          .select('balance')
          .eq('id', riderId)
          .maybeSingle();

      if (riderData == null) {
        throw Exception('Rider not found: $riderId');
      }

      final currentBalance = (riderData['balance'] as num?)?.toDouble() ?? 0.0;

      debugPrint('Current rider wallet balance: ${currentBalance.toStringAsFixed(2)}');

      final newBalance = currentBalance - deductionAmount;

      if (newBalance < 0) {
        debugPrint('Warning: Deduction would result in negative balance. Current: ${currentBalance.toStringAsFixed(2)}, Deduction: ${deductionAmount.toStringAsFixed(2)}');
      }

      await SupabaseService.client
          .from('riders')
          .update({'balance': newBalance})
          .eq('id', riderId);

      debugPrint('Successfully deducted ${deductionAmount.toStringAsFixed(2)} from rider wallet. New balance: ${newBalance.toStringAsFixed(2)}');

      try {
        await _createTransactionRecord(
          riderId: riderId,
          amount: -deductionAmount,
          deliveryFee: deliveryFee,
          deductionRate: deductionRate,
          balanceAfter: newBalance,
        );
      } catch (e) {
        debugPrint('Warning: Failed to create transaction record: $e');
      }
    } catch (e) {
      debugPrint('Error deducting from rider wallet: $e');
      rethrow;
    }
  }

  static Future<void> _createTransactionRecord({
    required String riderId,
    required double amount,
    required double deliveryFee,
    required double deductionRate,
    required double balanceAfter,
  }) async {
    try {
      await SupabaseService.client.from('rider_wallet_transactions').insert({
        'rider_id': riderId,
        'amount': amount,
        'transaction_type': 'deduction',
        'description': 'Delivery fee deduction (${(deductionRate * 100).toStringAsFixed(0)}% of ₱${deliveryFee.toStringAsFixed(2)})',
        'balance_after': balanceAfter,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Transaction record table may not exist: $e');
    }
  }

  static Future<double> getRiderWalletBalance(String riderId) async {
    try {
      final riderData = await SupabaseService.client
          .from('riders')
          .select('balance')
          .eq('id', riderId)
          .maybeSingle();

      if (riderData == null) {
        throw Exception('Rider not found: $riderId');
      }

      return (riderData['balance'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      debugPrint('Error getting rider wallet balance: $e');
      rethrow;
    }
  }
}
