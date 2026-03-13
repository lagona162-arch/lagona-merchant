import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/rider.dart';
import '../services/supabase_service.dart';
import '../services/merchant_service.dart';
import '../services/rider_wallet_service.dart';
import '../core/timezone_helper.dart';

class RiderService {

  static Future<List<Rider>> getPriorityRiders(String merchantId) async {
    try {

      final response = await SupabaseService.client
          .from('merchant_rider_preferences')
          .select('rider_id, priority_order')
          .eq('merchant_id', merchantId)
          .eq('is_priority', true)
          .order('priority_order', ascending: true);

      if (response.isEmpty) {
        return [];
      }

      final riderIds = response.map((item) => item['rider_id'] as String).toList();


      final futures = riderIds.map((riderId) async {
        try {
          final rider = await SupabaseService.client
              .from('riders')
              .select('*')
              .eq('id', riderId)
              .maybeSingle();

          final user = await SupabaseService.client
              .from('users')
              .select('id, full_name, phone, email')
              .eq('id', riderId)
              .maybeSingle();

          return {'rider': rider, 'user': user};
        } catch (e) {
          debugPrint('Error fetching rider/user $riderId: $e');
          return {'rider': null, 'user': null};
        }
      }).toList();

      final results = await Future.wait(futures);
      final ridersData = <Map<String, dynamic>>[];
      final usersData = <Map<String, dynamic>>[];

      for (final result in results) {
        if (result['rider'] != null) {
          ridersData.add(result['rider'] as Map<String, dynamic>);
        }
        if (result['user'] != null) {
          usersData.add(result['user'] as Map<String, dynamic>);
        }
      }

      final userMap = <String, Map<String, dynamic>>{};
      for (var user in usersData) {
        userMap[user['id'] as String] = user;
      }

      final priorityOrderMap = <String, int>{};
      for (var item in response) {
        final riderId = item['rider_id'] as String;
        final order = item['priority_order'] as int?;
        if (order != null) {
          priorityOrderMap[riderId] = order;
        }
      }

      final riders = <Rider>[];
      for (var riderData in ridersData) {
        final riderJson = Map<String, dynamic>.from(riderData);
        final riderId = riderJson['id'] as String;
        final userData = userMap[riderId];

        if (userData != null) {
          riderJson['full_name'] = userData['full_name'];
          riderJson['phone'] = userData['phone'];
        }

        if (riderJson['plate_number'] != null) {
          riderJson['vehicle_number'] = riderJson['plate_number'];
        }

        final status = riderJson['status'] as String?;
        riderJson['is_available'] = status == 'available';

        riders.add(Rider.fromJson(riderJson));
      }

      riders.sort((a, b) {
        final orderA = priorityOrderMap[a.id] ?? 999;
        final orderB = priorityOrderMap[b.id] ?? 999;
        return orderA.compareTo(orderB);
      });

      return riders;
    } catch (e) {
      debugPrint('Error fetching priority riders: $e');

      return [];
    }
  }

  static Future<List<Rider>> getAllRiders({String? loadingStationId}) async {
    try {

      var query = SupabaseService.client.from('riders').select('*');

      if (loadingStationId != null && loadingStationId.isNotEmpty) {
        query = query.eq('loading_station_id', loadingStationId);
      }

      final riders = await query.order('created_at', ascending: false);

      if (riders.isEmpty) {
        return [];
      }

      final riderIds = riders.map((r) => r['id'] as String).toList();
      final userMap = <String, Map<String, dynamic>>{};

      for (final riderId in riderIds) {
        try {
          final user = await SupabaseService.client
              .from('users')
              .select('id, full_name, phone, email')
              .eq('id', riderId)
              .maybeSingle();
          if (user != null) {
            userMap[riderId] = user;
          }
        } catch (e) {
          debugPrint('Error fetching user $riderId: $e');
        }
      }

      return riders.map((json) {
        final riderJson = Map<String, dynamic>.from(json);
        final riderId = riderJson['id'] as String;
        final userData = userMap[riderId];

        if (userData != null) {
          riderJson['full_name'] = userData['full_name'];
          riderJson['phone'] = userData['phone'];
        }

        if (riderJson['plate_number'] != null) {
          riderJson['vehicle_number'] = riderJson['plate_number'];
        }

        final status = riderJson['status'] as String?;
        riderJson['is_available'] = status == 'available';

        return Rider.fromJson(riderJson);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching riders: $e');
      return [];
    }
  }

  static Future<bool> isPriorityRider(String merchantId, String riderId) async {
    try {
      final response = await SupabaseService.client
          .from('merchant_rider_preferences')
          .select()
          .eq('merchant_id', merchantId)
          .eq('rider_id', riderId)
          .eq('is_priority', true)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  static Future<void> addPriorityRider({
    required String merchantId,
    required String riderId,
  }) async {
    try {

      final exists = await isPriorityRider(merchantId, riderId);
      if (exists) {
        throw Exception('Rider is already in priority list');
      }

      final currentPriorities = await SupabaseService.client
          .from('merchant_rider_preferences')
          .select('priority_order')
          .eq('merchant_id', merchantId)
          .eq('is_priority', true)
          .order('priority_order', ascending: false)
          .limit(1);

      int nextPriorityOrder = 1;
      if (currentPriorities.isNotEmpty) {
        nextPriorityOrder =
            (currentPriorities.first['priority_order'] as int? ?? 0) + 1;
      }

      await SupabaseService.client.from('merchant_rider_preferences').upsert({
        'merchant_id': merchantId,
        'rider_id': riderId,
        'is_priority': true,
        'priority_order': nextPriorityOrder,
      });
    } catch (e) {
      throw Exception('Failed to add priority rider: ${e.toString()}');
    }
  }

  static Future<void> removePriorityRider({
    required String merchantId,
    required String riderId,
  }) async {
    try {
      await SupabaseService.client
          .from('merchant_rider_preferences')
          .update({'is_priority': false, 'priority_order': null})
          .eq('merchant_id', merchantId)
          .eq('rider_id', riderId);
    } catch (e) {
      throw Exception('Failed to remove priority rider: ${e.toString()}');
    }
  }

  static Future<void> updatePriorityOrder({
    required String merchantId,
    required List<String> riderIds,
  }) async {
    try {

      for (int i = 0; i < riderIds.length; i++) {
        await SupabaseService.client
            .from('merchant_rider_preferences')
            .update({
              'priority_order': i + 1,
            })
            .eq('merchant_id', merchantId)
            .eq('rider_id', riderIds[i]);
      }
    } catch (e) {
      throw Exception('Failed to update priority order: ${e.toString()}');
    }
  }

  static Future<Map<String, int>> getPriorityRiderOrder(
    String merchantId,
  ) async {
    try {
      final response = await SupabaseService.client
          .from('merchant_rider_preferences')
          .select('rider_id, priority_order')
          .eq('merchant_id', merchantId)
          .eq('is_priority', true);

      final orderMap = <String, int>{};
      for (var item in response) {
        final riderId = item['rider_id'] as String;
        final order = item['priority_order'] as int?;
        if (riderId != null && order != null) {
          orderMap[riderId] = order;
        }
      }

      return orderMap;
    } catch (e) {
      return {};
    }
  }

  static Future<List<Rider>> getAvailableRiders() async {
    try {

      // DB uses enum rider_status; only 'available' is valid for "can accept". (no 'online' in enum)
      final riders = await SupabaseService.client
          .from('riders')
          .select('*')
          .eq('status', 'available')
          .order('created_at', ascending: false);

      if (riders.isEmpty) {
        return [];
      }

      final riderIds = riders.map((r) => r['id'] as String).toList();
      final userMap = <String, Map<String, dynamic>>{};

      for (final riderId in riderIds) {
        try {
          final user = await SupabaseService.client
              .from('users')
              .select('id, full_name, phone, email')
              .eq('id', riderId)
              .maybeSingle();
          if (user != null) {
            userMap[riderId] = user;
          }
        } catch (e) {
          debugPrint('Error fetching user $riderId: $e');
        }
      }

      return riders.map((json) {
        final riderJson = Map<String, dynamic>.from(json);
        final riderId = riderJson['id'] as String;
        final userData = userMap[riderId];

        if (userData != null) {
          riderJson['full_name'] = userData['full_name'];
          riderJson['phone'] = userData['phone'];
        }

        if (riderJson['plate_number'] != null) {
          riderJson['vehicle_number'] = riderJson['plate_number'];
        }

        riderJson['is_available'] = true; // already filtered to available

        return Rider.fromJson(riderJson);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching available riders: $e');
      return [];
    }
  }

  static Future<bool> isRiderAvailable(String riderId) async {
    try {
      final response = await SupabaseService.client
          .from('riders')
          .select('status')
          .eq('id', riderId)
          .maybeSingle();

      if (response == null) return false;
      final status = response['status'] as String?;
      return status == 'available';
    } catch (e) {
      debugPrint('Error checking rider availability: $e');
      return false;
    }
  }

  /// Fetches rider statuses from Supabase to verify connection and see which
  /// status values exist in the DB. Expected: available, online (can accept),
  /// busy (has active order), offline. Returns map of status -> count.
  static Future<Map<String, int>> getRiderStatusesFromSupabase() async {
    try {
      final response = await SupabaseService.client
          .from('riders')
          .select('status');
      final counts = <String, int>{};
      for (final row in response) {
        final status = row['status'] as String? ?? 'null';
        counts[status] = (counts[status] ?? 0) + 1;
      }
      debugPrint('Supabase riders statuses: $counts');
      return counts;
    } catch (e) {
      debugPrint('Error fetching rider statuses from Supabase: $e');
      return {};
    }
  }

  static Future<void> assignRiderToDelivery({
    required String deliveryId,
    required String riderId,
    String? status,
  }) async {
    final updateData = <String, dynamic>{
      'rider_id': riderId,
    };

    if (status != null) {
      updateData['status'] = status;
      debugPrint('Updating delivery $deliveryId: rider_id=$riderId, status=$status');
    } else {
      debugPrint('Updating delivery $deliveryId: rider_id=$riderId (no status change)');
    }

    final response = await SupabaseService.client
        .from('deliveries')
        .update(updateData)
        .eq('id', deliveryId)
        .select();

    if (response.isEmpty) {
      throw Exception('Failed to assign rider: delivery not found or update failed');
    }

    debugPrint('Delivery $deliveryId updated successfully: ${response.first}');

    try {
      final riderUpdateResponse = await SupabaseService.client
          .from('riders')
          .update({'status': 'busy'})
          .eq('id', riderId)
          .select('status');
      
      if (riderUpdateResponse.isNotEmpty) {
        debugPrint('✅ Rider $riderId status updated to "busy" (confirmed: ${riderUpdateResponse.first['status']})');
      } else {
        debugPrint('⚠️ Warning: Rider $riderId not found when updating status');
      }
    } catch (e) {
      debugPrint('❌ ERROR: Failed to update rider status to busy: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      throw Exception('Failed to update rider status: ${e.toString()}');
    }

    try {
      await _deductFromRiderWalletOnAssignment(deliveryId, riderId);
    } catch (e) {
      debugPrint('CRITICAL: Failed to deduct from rider wallet during assignment: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  static Future<void> _deductFromRiderWalletOnAssignment(String deliveryId, String riderId) async {
    debugPrint('=== WALLET DEDUCTION START ===');
    debugPrint('Delivery ID: $deliveryId');
    debugPrint('Rider ID: $riderId');

    try {
      final deliveryData = await SupabaseService.client
          .from('deliveries')
          .select('delivery_fee')
          .eq('id', deliveryId)
          .maybeSingle();

      debugPrint('Delivery data fetched: ${deliveryData != null ? "Found" : "Not found"}');

      if (deliveryData == null) {
        debugPrint('ERROR: Delivery not found for wallet deduction: $deliveryId');
        throw Exception('Delivery not found for wallet deduction: $deliveryId');
      }

      final deliveryFee = (deliveryData['delivery_fee'] as num?)?.toDouble();
      debugPrint('Delivery fee: ${deliveryFee ?? "null"}');

      if (deliveryFee == null || deliveryFee <= 0) {
        debugPrint('ERROR: Delivery $deliveryId has no delivery fee (${deliveryFee ?? "null"}), skipping wallet deduction');
        throw Exception('Delivery has no valid delivery fee: ${deliveryFee ?? "null"}');
      }

      debugPrint('Proceeding with wallet deduction...');
      await RiderWalletService.deductFromRiderWallet(
        riderId: riderId,
        deliveryFee: deliveryFee,
        deductionRate: 0.20,
      );

      debugPrint('✅ Wallet deduction completed for delivery $deliveryId: ₱${(deliveryFee * 0.20).toStringAsFixed(2)} deducted from rider $riderId');
      debugPrint('=== WALLET DEDUCTION END ===');
    } catch (e) {
      debugPrint('❌ ERROR in wallet deduction: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      debugPrint('=== WALLET DEDUCTION END (WITH ERROR) ===');
      rethrow;
    }
  }

  static Future<String?> findAndAssignRider({
    required String deliveryId,
    required String merchantId,
  }) async {

    final priorityRiders = await getPriorityRiders(merchantId);
    final availablePriorityRiders =
        priorityRiders.where((r) => r.isAvailable).toList();

    if (availablePriorityRiders.isNotEmpty) {

      await Future.delayed(const Duration(seconds: 30));

      final stillAvailable = availablePriorityRiders
          .where((r) => r.isAvailable)
          .toList();

      if (stillAvailable.isNotEmpty) {

        final rider = stillAvailable.first;
        if (await isRiderAvailable(rider.id)) {
          await assignRiderToDelivery(
            deliveryId: deliveryId,
            riderId: rider.id,
          );
          return rider.id;
        }
      }
    }

    final allRiders = await getAvailableRiders();
    if (allRiders.isNotEmpty) {

      final nonPriorityRiders = allRiders
          .where((r) => !availablePriorityRiders.any((pr) => pr.id == r.id))
          .toList();

      if (nonPriorityRiders.isEmpty) {

        final anyRider = allRiders.first;
        if (await isRiderAvailable(anyRider.id)) {
          await assignRiderToDelivery(
            deliveryId: deliveryId,
            riderId: anyRider.id,
          );
          return anyRider.id;
        }
      } else {

        final rider = nonPriorityRiders.first;
        if (await isRiderAvailable(rider.id)) {
          await assignRiderToDelivery(
            deliveryId: deliveryId,
            riderId: rider.id,
          );
          return rider.id;
        }
      }
    }

    return null;
  }

  /// Calculate distance between two coordinates using Haversine formula
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371; // Earth radius in kilometers

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.asin(math.sqrt(a));

    return earthRadius * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * (3.141592653589793 / 180.0);
  }

  /// Get riders within a specified radius (in km) from a location
  static Future<List<Rider>> getRidersWithinRadius({
    required double latitude,
    required double longitude,
    required double radiusKm,
    List<String>? excludeRiderIds,
  }) async {
    try {
      final allRiders = await getAvailableRiders();
      
      // Filter by distance
      final nearbyRiders = allRiders.where((rider) {
        if (rider.latitude == null || rider.longitude == null) return false;
        if (excludeRiderIds != null && excludeRiderIds.contains(rider.id)) {
          return false;
        }
        
        final distance = calculateDistance(
          latitude,
          longitude,
          rider.latitude!,
          rider.longitude!,
        );
        
        return distance <= radiusKm;
      }).toList();

      return nearbyRiders;
    } catch (e) {
      debugPrint('Error fetching riders within radius: $e');
      return [];
    }
  }

  /// Send delivery offer to a rider
  /// For priority offers: expiresIn should be the total window (e.g., 10 minutes)
  /// For broadcast offers: expiresIn should be when the broadcast expires
  static Future<void> sendDeliveryOffer({
    required String deliveryId,
    required String riderId,
    required String offerType, // 'priority' or 'broadcast'
    required Duration expiresIn, // Total time until expiration (from now)
  }) async {
    try {
      // Calculate expiration time in PHT, then convert to UTC for database
      final phtNow = TimezoneHelper.nowPHT();
      final phtExpiresAt = phtNow.add(expiresIn);
      final utcExpiresAt = TimezoneHelper.phtToUTC(phtExpiresAt);

      final row = {
        'delivery_id': deliveryId,
        'rider_id': riderId,
        'offer_type': offerType,
        'status': 'pending',
        'expires_at': utcExpiresAt.toIso8601String(),
      };

      // Idempotent: insert; if duplicate (rider already has offer), refresh expiry only (keep offer_type)
      try {
        await SupabaseService.client.from('delivery_offers').insert(row);
      } on PostgrestException catch (e) {
        if (e.code == '23505') {
          await SupabaseService.client
              .from('delivery_offers')
              .update({
                'status': 'pending',
                'expires_at': utcExpiresAt.toIso8601String(),
              })
              .eq('delivery_id', deliveryId)
              .eq('rider_id', riderId);
        } else {
          rethrow;
        }
      }

      // Send notification to rider
      final minutesRemaining = expiresIn.inMinutes;
      final secondsRemaining = expiresIn.inSeconds % 60;
      String timeRemaining;
      if (minutesRemaining > 0) {
        timeRemaining = '$minutesRemaining minute${minutesRemaining > 1 ? 's' : ''}';
        if (secondsRemaining > 0) {
          timeRemaining += ' and $secondsRemaining second${secondsRemaining > 1 ? 's' : ''}';
        }
      } else {
        timeRemaining = '$secondsRemaining second${secondsRemaining > 1 ? 's' : ''}';
      }

      await SupabaseService.client.from('notifications').insert({
        'rider_id': riderId,
        'delivery_id': deliveryId,
        'type': offerType == 'priority' ? 'priority_delivery_offer' : 'delivery_offer',
        'title': offerType == 'priority' ? 'Priority Delivery Offer' : 'New Delivery Offer',
        'message': offerType == 'priority' 
            ? 'You have a priority delivery offer. You have exclusive access for the first minute, then all riders can accept. Total window: $timeRemaining.'
            : 'You have a new delivery offer. Please accept or decline within $timeRemaining.',
        'read': false,
        'is_read': false,
      });
    } catch (e) {
      debugPrint('Error sending delivery offer: $e');
      rethrow;
    }
  }

  /// Check if a rider has accepted an offer
  static Future<bool> checkRiderAcceptedOffer({
    required String deliveryId,
    required String riderId,
  }) async {
    try {
      final response = await SupabaseService.client
          .from('delivery_offers')
          .select('status')
          .eq('delivery_id', deliveryId)
          .eq('rider_id', riderId)
          .eq('status', 'accepted')
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('Error checking rider offer acceptance: $e');
      return false;
    }
  }

  /// Check if any rider has accepted an offer for a delivery
  static Future<String?> checkAnyRiderAccepted(String deliveryId) async {
    try {
      final response = await SupabaseService.client
          .from('delivery_offers')
          .select('rider_id')
          .eq('delivery_id', deliveryId)
          .eq('status', 'accepted')
          .maybeSingle();

      return response != null ? response['rider_id'] as String? : null;
    } catch (e) {
      debugPrint('Error checking if any rider accepted: $e');
      return null;
    }
  }

  /// Get pending offers for a delivery
  static Future<List<Map<String, dynamic>>> getPendingOffers(String deliveryId) async {
    try {
      // Compare with current UTC time (database stores in UTC)
      final utcNow = TimezoneHelper.nowUTC();
      final response = await SupabaseService.client
          .from('delivery_offers')
          .select('id, rider_id, offer_type, expires_at')
          .eq('delivery_id', deliveryId)
          .eq('status', 'pending')
          .lt('expires_at', utcNow.toIso8601String());

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting pending offers: $e');
      return [];
    }
  }

  /// Expire old offers (only those past expiration time)
  static Future<void> expireOldOffers(String deliveryId) async {
    try {
      // Compare with current UTC time (database stores in UTC)
      final utcNow = TimezoneHelper.nowUTC();
      await SupabaseService.client
          .from('delivery_offers')
          .update({'status': 'expired'})
          .eq('delivery_id', deliveryId)
          .eq('status', 'pending')
          .lt('expires_at', utcNow.toIso8601String());
    } catch (e) {
      debugPrint('Error expiring old offers: $e');
    }
  }

  /// Expire all pending offers for a delivery (used when cancelling or starting a new search)
  static Future<void> expireAllPendingOffers(String deliveryId) async {
    try {
      await SupabaseService.client
          .from('delivery_offers')
          .update({'status': 'expired'})
          .eq('delivery_id', deliveryId)
          .eq('status', 'pending');
    } catch (e) {
      debugPrint('Error expiring all pending offers: $e');
    }
  }

  /// Delete all pending and expired offers for a delivery. Call at start of
  /// find rider and when merchant cancels. Does not touch accepted offers.
  /// If delete is not allowed (e.g. RLS), falls back to expiring them.
  static Future<void> deleteAllOffersForDelivery(String deliveryId) async {
    try {
      await SupabaseService.client
          .from('delivery_offers')
          .delete()
          .eq('delivery_id', deliveryId)
          .or('status.eq.pending,status.eq.expired');
    } catch (e) {
      debugPrint('Error deleting delivery offers (trying expire instead): $e');
      try {
        await SupabaseService.client
            .from('delivery_offers')
            .update({'status': 'expired'})
            .eq('delivery_id', deliveryId)
            .eq('status', 'pending');
      } catch (e2) {
        debugPrint('Error expiring delivery offers: $e2');
      }
    }
  }

  /// Delete only the queued (pending) offers for this delivery and these riders.
  /// Call when merchant cancels. Uses RPC so it works even when RLS blocks direct delete.
  static Future<void> deleteOffersForDeliveryAndRiders(
    String deliveryId,
    Iterable<String> riderIds,
  ) async {
    if (riderIds.isEmpty) return;
    final list = riderIds.toList();
    try {
      await SupabaseService.client.rpc(
        'cancel_find_rider_offers',
        params: {'p_delivery_id': deliveryId, 'p_rider_ids': list},
      );
    } catch (e) {
      debugPrint('RPC cancel_find_rider_offers failed (run the SQL migration?): $e');
      try {
        await SupabaseService.client
            .from('delivery_offers')
            .delete()
            .eq('delivery_id', deliveryId)
            .eq('status', 'pending')
            .inFilter('rider_id', list);
      } catch (e2) {
        debugPrint('Client delete failed: $e2');
        for (final riderId in list) {
          try {
            await SupabaseService.client
                .from('delivery_offers')
                .update({'status': 'expired'})
                .eq('delivery_id', deliveryId)
                .eq('rider_id', riderId)
                .eq('status', 'pending');
          } catch (_) {}
        }
      }
    }
  }

  /// After the 1-min priority window, update all pending priority offers for this
  /// delivery to broadcast (offer_type and is_priority reflect the broadcast phase).
  static Future<void> updatePriorityOffersToBroadcast(
    String deliveryId,
    Duration remainingTime,
  ) async {
    try {
      final utcExpiresAt = TimezoneHelper.phtToUTC(
        TimezoneHelper.nowPHT().add(remainingTime),
      );
      await SupabaseService.client
          .from('delivery_offers')
          .update({
            'offer_type': 'broadcast',
            'expires_at': utcExpiresAt.toIso8601String(),
            'is_priority': false,
          })
          .eq('delivery_id', deliveryId)
          .eq('offer_type', 'priority')
          .eq('status', 'pending');
    } catch (e) {
      debugPrint('Error updating priority offers to broadcast: $e');
    }
  }
}
