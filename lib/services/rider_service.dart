import 'package:flutter/foundation.dart';
import '../models/rider.dart';
import '../services/supabase_service.dart';
import '../services/merchant_service.dart';

class RiderService {
  // Get priority/favorite riders for a merchant
  static Future<List<Rider>> getPriorityRiders(String merchantId) async {
    try {
      // Query riders that have been tagged/favorited by the merchant
      final response = await SupabaseService.client
          .from('merchant_rider_preferences')
          .select('rider_id, priority_order')
          .eq('merchant_id', merchantId)
          .eq('is_priority', true)
          .order('priority_order', ascending: true);

      if (response.isEmpty) {
        return [];
      }

      // Get rider IDs
      final riderIds = response.map((item) => item['rider_id'] as String).toList();

      // Fetch riders and users in parallel (since .inFilter might not be available)
      // We'll fetch each one individually and run them in parallel
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

      // Create a map of user data by ID
      final userMap = <String, Map<String, dynamic>>{};
      for (var user in usersData) {
        userMap[user['id'] as String] = user;
      }

      // Create a map of priority order by rider ID
      final priorityOrderMap = <String, int>{};
      for (var item in response) {
        final riderId = item['rider_id'] as String;
        final order = item['priority_order'] as int?;
        if (order != null) {
          priorityOrderMap[riderId] = order;
        }
      }

      // Merge user data into rider json and sort by priority order
      final riders = <Rider>[];
      for (var riderData in ridersData) {
        final riderJson = Map<String, dynamic>.from(riderData);
        final riderId = riderJson['id'] as String;
        final userData = userMap[riderId];
        
        if (userData != null) {
          riderJson['full_name'] = userData['full_name'];
          riderJson['phone'] = userData['phone'];
        }
        
        // Map plate_number to vehicle_number
        if (riderJson['plate_number'] != null) {
          riderJson['vehicle_number'] = riderJson['plate_number'];
        }
        
        // Map status to is_available
        final status = riderJson['status'] as String?;
        riderJson['is_available'] = status == 'available';

        riders.add(Rider.fromJson(riderJson));
      }

      // Sort by priority order
      riders.sort((a, b) {
        final orderA = priorityOrderMap[a.id] ?? 999;
        final orderB = priorityOrderMap[b.id] ?? 999;
        return orderA.compareTo(orderB);
      });

      return riders;
    } catch (e) {
      debugPrint('Error fetching priority riders: $e');
      // If the table doesn't exist, return empty list
      return [];
    }
  }

  // Get all riders (for selection) - filtered by loading_station_id if provided
  static Future<List<Rider>> getAllRiders({String? loadingStationId}) async {
    try {
      // Get riders first
      var query = SupabaseService.client.from('riders').select('*');
      
      // Filter by loading_station_id if provided
      if (loadingStationId != null && loadingStationId.isNotEmpty) {
        query = query.eq('loading_station_id', loadingStationId);
      }
      
      final riders = await query.order('created_at', ascending: false);
      
      if (riders.isEmpty) {
        return [];
      }

      // Collect rider IDs and fetch user data
      final riderIds = riders.map((r) => r['id'] as String).toList();
      final userMap = <String, Map<String, dynamic>>{};
      
      // Fetch user data for each rider ID
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

      // Merge user data into rider json
      return riders.map((json) {
        final riderJson = Map<String, dynamic>.from(json);
        final riderId = riderJson['id'] as String;
        final userData = userMap[riderId];
        
        if (userData != null) {
          riderJson['full_name'] = userData['full_name'];
          riderJson['phone'] = userData['phone'];
        }
        
        // Map plate_number to vehicle_number
        if (riderJson['plate_number'] != null) {
          riderJson['vehicle_number'] = riderJson['plate_number'];
        }
        
        // Map status to is_available (status = 'available' means isAvailable = true)
        final status = riderJson['status'] as String?;
        riderJson['is_available'] = status == 'available';

        return Rider.fromJson(riderJson);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching riders: $e');
      return [];
    }
  }

  // Check if a rider is already a priority for merchant
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

  // Add priority rider
  static Future<void> addPriorityRider({
    required String merchantId,
    required String riderId,
  }) async {
    try {
      // Check if already exists
      final exists = await isPriorityRider(merchantId, riderId);
      if (exists) {
        throw Exception('Rider is already in priority list');
      }

      // Get current max priority order
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

      // Insert or update preference
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

  // Remove priority rider
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

  // Update priority order (for reordering)
  static Future<void> updatePriorityOrder({
    required String merchantId,
    required List<String> riderIds, // Ordered list of rider IDs
  }) async {
    try {
      // Update priority order for each rider
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

  // Get priority riders with their order info
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

  // Get all available riders (fallback)
  static Future<List<Rider>> getAvailableRiders() async {
    try {
      // Get riders with status = 'available'
      final riders = await SupabaseService.client
          .from('riders')
          .select('*')
          .eq('status', 'available')
          .order('created_at', ascending: false);

      if (riders.isEmpty) {
        return [];
      }

      // Collect rider IDs and fetch user data
      final riderIds = riders.map((r) => r['id'] as String).toList();
      final userMap = <String, Map<String, dynamic>>{};
      
      // Fetch user data for each rider ID
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

      // Merge user data into rider json
      return riders.map((json) {
        final riderJson = Map<String, dynamic>.from(json);
        final riderId = riderJson['id'] as String;
        final userData = userMap[riderId];
        
        if (userData != null) {
          riderJson['full_name'] = userData['full_name'];
          riderJson['phone'] = userData['phone'];
        }
        
        // Map plate_number to vehicle_number
        if (riderJson['plate_number'] != null) {
          riderJson['vehicle_number'] = riderJson['plate_number'];
        }
        
        // Map status to is_available
        riderJson['is_available'] = true; // Already filtered by status = 'available'

        return Rider.fromJson(riderJson);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching available riders: $e');
      return [];
    }
  }

  // Check if a rider is available
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

  // Assign rider to delivery
  static Future<void> assignRiderToDelivery({
    required String deliveryId,
    required String riderId,
    String? status, // Optional: update status at the same time
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
  }

  // Find and assign a rider with priority logic
  // Priority riders get 30 seconds to accept, then others are assigned
  static Future<String?> findAndAssignRider({
    required String deliveryId,
    required String merchantId,
  }) async {
    // First, try priority riders
    final priorityRiders = await getPriorityRiders(merchantId);
    final availablePriorityRiders =
        priorityRiders.where((r) => r.isAvailable).toList();

    if (availablePriorityRiders.isNotEmpty) {
      // Wait 30 seconds for priority rider
      await Future.delayed(const Duration(seconds: 30));

      // Check again if priority rider is still available
      final stillAvailable = availablePriorityRiders
          .where((r) => r.isAvailable)
          .toList();

      if (stillAvailable.isNotEmpty) {
        // Assign first available priority rider
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

    // If no priority rider available, get other available riders
    final allRiders = await getAvailableRiders();
    if (allRiders.isNotEmpty) {
      // Filter out priority riders if we already checked them
      final nonPriorityRiders = allRiders
          .where((r) => !availablePriorityRiders.any((pr) => pr.id == r.id))
          .toList();

      if (nonPriorityRiders.isEmpty) {
        // If all riders are priority and none available, try any rider
        final anyRider = allRiders.first;
        if (await isRiderAvailable(anyRider.id)) {
          await assignRiderToDelivery(
            deliveryId: deliveryId,
            riderId: anyRider.id,
          );
          return anyRider.id;
        }
      } else {
        // Assign first available non-priority rider
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

    return null; // No rider available
  }
}

