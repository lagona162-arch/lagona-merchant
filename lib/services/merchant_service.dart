import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/merchant.dart';
import '../services/supabase_service.dart';

class MerchantService {
  // Create merchant from pending registration data (called on first login after approval)
  static Future<void> createMerchantFromPending(String userId) async {
    try {
      // Get pending merchant data
      final pendingData = await SupabaseService.getPendingMerchantData(userId);
      
      if (pendingData == null) {
        throw Exception('No pending merchant registration data found. Please contact support.');
      }

      debugPrint('Creating merchant from pending data for user: $userId');

      // Create merchant record from pending data
      final insertData = {
        'id': userId,
        'business_name': pendingData['business_name'] as String,
        'address': pendingData['address'] as String,
        'dti_number': pendingData['dti_certificate_url'] as String?,
        'mayor_permit': pendingData['mayor_permit_url'] as String?,
        'latitude': (pendingData['latitude'] as num).toDouble(),
        'longitude': (pendingData['longitude'] as num).toDouble(),
        'map_place_id': pendingData['map_place_id'] as String?,
        'verified': true, // Set to verified since admin approved
        'access_status': 'approved', // Set to approved
      };

      final response = await SupabaseService.client
          .from('merchants')
          .insert(insertData)
          .select();

      if (response.isEmpty) {
        throw Exception('Failed to create merchant record from pending data');
      }

      debugPrint('Merchant created successfully from pending data');

      // Delete pending registration data after successful merchant creation
      try {
        await SupabaseService.client
            .from('pending_merchant_registrations')
            .delete()
            .eq('user_id', userId);
        debugPrint('Pending merchant data cleaned up');
      } catch (e) {
        debugPrint('Warning: Failed to clean up pending merchant data: $e');
        // Don't throw - merchant was created successfully
      }
    } catch (e) {
      debugPrint('Error creating merchant from pending data: $e');
      rethrow;
    }
  }

  // Create merchant profile
  static Future<void> createMerchant({
    required String userId,
    required String businessName,
    required String address,
    required String municipality,
    required String contactNumber,
    required String ownerName,
    required String ownerContact,
    File? dtiCertificate,
    File? mayorPermit,
    required double latitude,
    required double longitude,
    String? placeId,
  }) async {
    // Upload documents if provided (optional - registration continues even if upload fails)
    // Use userId from parameter instead of currentUser since session might not be established yet
    String? dtiUrl;
    String? mayorPermitUrl;

    if (dtiCertificate != null) {
      try {
        dtiUrl = await _uploadFile(dtiCertificate, 'dti_certificates', userId);
        debugPrint('DTI certificate uploaded successfully: $dtiUrl');
      } catch (e) {
        debugPrint('Warning: Failed to upload DTI certificate: $e');
        debugPrint('Registration will continue without DTI certificate. You can upload it later.');
        // Continue without the document - it's optional
      }
    }

    if (mayorPermit != null) {
      try {
        mayorPermitUrl = await _uploadFile(mayorPermit, 'mayor_permits', userId);
        debugPrint('Mayor permit uploaded successfully: $mayorPermitUrl');
      } catch (e) {
        debugPrint('Warning: Failed to upload Mayor permit: $e');
        debugPrint('Registration will continue without Mayor permit. You can upload it later.');
        // Continue without the document - it's optional
      }
    }

    // Create merchant record (id references users.id)
    try {
      debugPrint('Creating merchant record with userId: $userId');
      debugPrint('Business name: $businessName');
      debugPrint('Address: $address');
      debugPrint('Latitude: $latitude, Longitude: $longitude');
      
      // Verify session is active (or use database function if no session)
      final currentSession = SupabaseService.currentSession;
      final currentUser = SupabaseService.currentUser;
      debugPrint('Current session exists: ${currentSession != null}');
      debugPrint('Current user ID: ${currentUser?.id}');
      debugPrint('Expected user ID: $userId');
      
      final insertData = {
        'id': userId,
        'business_name': businessName,
        'address': address,
        'dti_number': dtiUrl,
        'mayor_permit': mayorPermitUrl,
        'latitude': latitude,
        'longitude': longitude,
        'map_place_id': placeId,
        'verified': false,
      };
      
      debugPrint('Insert data: $insertData');
      
      // Try to insert using standard method first
      List<Map<String, dynamic>> response;
      try {
        response = await SupabaseService.client
            .from('merchants')
            .insert(insertData)
            .select();
        
        debugPrint('Merchant created successfully: ${response.length} record(s)');
        debugPrint('Response data: $response');
      } catch (e) {
        // If insert fails (e.g., no session due to RLS), try using database function
        debugPrint('Standard insert failed (possibly due to RLS): $e');
        debugPrint('Attempting to use database function instead...');
        
        try {
          final functionResult = await SupabaseService.client
              .rpc('create_merchant_on_registration', params: {
            'p_user_id': userId,
            'p_business_name': businessName,
            'p_address': address,
            'p_latitude': latitude,
            'p_longitude': longitude,
            'p_map_place_id': placeId,
            'p_dti_number': dtiUrl,
            'p_mayor_permit': mayorPermitUrl,
          });
          
          debugPrint('Merchant created via database function: $functionResult');
          response = [functionResult as Map<String, dynamic>];
        } catch (functionError) {
          debugPrint('Database function also failed: $functionError');
          rethrow;
        }
      }
      
      if (response.isEmpty) {
        throw Exception('Merchant record was not created - response was empty');
      }
      
      // Verify the record actually exists
      final verification = await SupabaseService.client
          .from('merchants')
          .select()
          .eq('id', userId)
          .maybeSingle();
      
      if (verification == null) {
        throw Exception('Merchant record was created but not found in database');
      }
      
      debugPrint('Merchant record verified in database: ${verification['business_name']}');
    } catch (e) {
      debugPrint('Error creating merchant record: $e');
      // Clean up uploaded documents if merchant creation fails
      if (dtiUrl != null) {
        try {
          final pathParts = dtiUrl.split('/');
          final fileName = pathParts.last;
          await SupabaseService.client.storage
              .from('merchant-documents')
              .remove(['dti_certificates/$userId/$fileName']);
        } catch (cleanupError) {
          debugPrint('Error cleaning up DTI certificate: $cleanupError');
        }
      }
      if (mayorPermitUrl != null) {
        try {
          final pathParts = mayorPermitUrl.split('/');
          final fileName = pathParts.last;
          await SupabaseService.client.storage
              .from('merchant-documents')
              .remove(['mayor_permits/$userId/$fileName']);
        } catch (cleanupError) {
          debugPrint('Error cleaning up mayor permit: $cleanupError');
        }
      }
      rethrow;
    }

    // Update user role to merchant
    try {
      await SupabaseService.client
          .from('users')
          .update({'role': 'merchant'}).eq('id', userId);
      debugPrint('User role updated to merchant');
    } catch (e) {
      debugPrint('Error updating user role: $e');
      // Don't rethrow - merchant record is created, role update is secondary
    }
  }

  // Get merchant by user ID (id = user_id in this schema)
  static Future<Merchant?> getMerchantByUserId(String userId) async {
    final response = await SupabaseService.client
        .from('merchants')
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (response == null) return null;
    return Merchant.fromJson(response);
  }

  // Update merchant
  static Future<void> updateMerchant({
    required String merchantId,
    String? businessName,
    String? address,
    String? slogan,
    String? previewImage,
    double? latitude,
    double? longitude,
    String? placeId,
  }) async {
    final updateData = <String, dynamic>{};
    if (businessName != null) updateData['business_name'] = businessName;
    if (address != null) updateData['address'] = address;
    if (slogan != null) updateData['slogan'] = slogan;
    if (previewImage != null) updateData['preview_image'] = previewImage;
    if (latitude != null) updateData['latitude'] = latitude;
    if (longitude != null) updateData['longitude'] = longitude;
    if (placeId != null) updateData['map_place_id'] = placeId;

    await SupabaseService.client
        .from('merchants')
        .update(updateData)
        .eq('id', merchantId);
  }

  // Upload Logo (preview image)
  static Future<String> uploadLogo(File logoImage) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    // Use merchant-image bucket with preview-images folder structure
    // Path structure: {userId}/preview-images/{filename}
    return await _uploadFile(logoImage, 'preview-images', userId, 'merchant-image');
  }

  // Upload GCash QR Code
  static Future<String> uploadGCashQR(File qrImage) async {
    // Ensure we have userId - use currentUser.id since this is called after login
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    return await _uploadFile(qrImage, 'gcash_qr_codes', userId, 'merchant-documents');
  }

  // Update GCash QR URL and Number
  static Future<void> updateGCashQR({
    required String merchantId,
    String? qrUrl,
    String? gcashNumber,
  }) async {
    final updateData = <String, dynamic>{};
    if (qrUrl != null) updateData['gcash_qr_url'] = qrUrl;
    if (gcashNumber != null) updateData['gcash_number'] = gcashNumber;

    if (updateData.isNotEmpty) {
      await SupabaseService.client
          .from('merchants')
          .update(updateData)
          .eq('id', merchantId);
    }
  }

  // Upload document (public method for registration use)
  static Future<String> uploadDocument(File file, String folder, String userId) async {
    return await _uploadFile(file, folder, userId, 'merchant-documents');
  }

  // Helper method to upload files
  static Future<String> _uploadFile(
    File file, 
    String folder, 
    [String? providedUserId, 
    String? bucketName]
  ) async {
    // Use provided userId if available (for registration), otherwise use currentUser
    final userId = providedUserId ?? SupabaseService.currentUser?.id;
    if (userId == null) {
      throw Exception('User ID is required for file upload');
    }

    // Determine bucket based on folder or use provided bucket
    final bucket = bucketName ?? _getBucketForFolder(folder);

    // Create user-specific path for RLS policies
    // For merchant-image bucket: Path structure is {userId}/folder/{filename} (RLS checks [1] = userId)
    // For other buckets: Path structure is folder/{userId}/{filename} (RLS checks [2] = userId)
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
    final filePath = bucket == 'merchant-image' 
        ? '$userId/$folder/$fileName'  // merchant-image: userId/folder/filename
        : '$folder/$userId/$fileName'; // other buckets: folder/userId/filename
    
    // Debug: Print path for troubleshooting
    debugPrint('Uploading to bucket: $bucket, path: $filePath with userId: $userId');
    final fileBytes = await file.readAsBytes();

    // Upload file
    // Ensure we're using the authenticated client and session is active
    try {
      // Check current auth state
      final currentUser = SupabaseService.currentUser;
      final currentSession = SupabaseService.currentSession;
      debugPrint('Current user ID during upload: ${currentUser?.id}');
      debugPrint('Expected user ID: $userId');
      debugPrint('Session exists: ${currentSession != null}');
      debugPrint('Session token exists: ${currentSession?.accessToken != null}');
      
      if (currentUser?.id != userId && currentUser != null) {
        debugPrint('Warning: Current user ID (${currentUser.id}) does not match expected user ID ($userId)');
      }
      
      await SupabaseService.client.storage.from(bucket).uploadBinary(
        filePath,
        fileBytes,
      );
      debugPrint('File uploaded successfully to bucket: $bucket, path: $filePath');
    } catch (e) {
      debugPrint('Upload error: ${e.toString()}');
      debugPrint('Bucket: $bucket');
      debugPrint('User ID: $userId');
      debugPrint('File path: $filePath');
      
      // If upload fails because file exists, try to remove it first
      if (e.toString().contains('already exists') || 
          e.toString().contains('409') ||
          e.toString().contains('duplicate')) {
        try {
          await SupabaseService.client.storage
              .from(bucket)
              .remove([filePath]);
          await SupabaseService.client.storage.from(bucket).uploadBinary(
            filePath,
            fileBytes,
          );
          debugPrint('File re-uploaded successfully after removing existing file');
        } catch (e2) {
          debugPrint('Re-upload error: ${e2.toString()}');
          throw Exception('Failed to upload file: ${e2.toString()}');
        }
      } else {
        throw Exception('Failed to upload file: ${e.toString()}');
      }
    }

    final publicUrl = SupabaseService.client.storage
        .from(bucket)
        .getPublicUrl(filePath);

    return publicUrl;
  }

  // Helper to determine bucket based on folder
  static String _getBucketForFolder(String folder) {
    switch (folder) {
      case 'preview-images':
        return 'merchant-image';
      case 'merchant-product':
        return 'merchant-image';
      case 'logos': // Legacy support - maps to preview-images
        return 'merchant-image';
      case 'gcash_qr_codes':
        return 'merchant-documents';
      case 'dti_certificates':
      case 'mayor_permits':
      default:
        return 'merchant-documents';
    }
  }
}

