import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    String role = 'merchant',
  }) async {
    final authResponse = await client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'phone': phone,
      },
    );

    if (authResponse.user != null) {
      try {

      try {
        await client.from('users').insert({
          'id': authResponse.user!.id,
          'full_name': fullName,
          'email': email,
          'password': 'hashed_by_auth',
          'role': role,
          'phone': phone,
            'is_active': false,
            'access_status': 'pending',
          });
          debugPrint('User record created successfully via direct insert');
        } catch (e) {

          debugPrint('Direct insert failed, using database function: $e');
          final result = await client.rpc('create_user_on_signup', params: {
            'p_user_id': authResponse.user!.id,
            'p_email': email,
            'p_full_name': fullName,
            'p_phone': phone,
            'p_role': role,
          });
          debugPrint('User record created successfully via database function: $result');
        }
      } catch (e) {

        debugPrint('Error creating user record: $e');

        if (!e.toString().contains('duplicate') && !e.toString().contains('23505')) {
          rethrow;
        }
      }
    }

    return authResponse;
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  static User? get currentUser => client.auth.currentUser;
  static Session? get currentSession => client.auth.currentSession;
  static bool get isSignedIn => currentUser != null;

  static Future<String?> getUserRole() async {
    final userId = currentUser?.id;
    if (userId == null) return null;

    try {
      final response = await client
          .from('users')
          .select('role')
          .eq('id', userId)
          .maybeSingle();

      return response?['role'] as String?;
    } catch (e) {
      debugPrint('Error getting user role: $e');
      return null;
    }
  }

  static Future<bool> isMerchant() async {
    final role = await getUserRole();
    if (role != 'merchant') return false;

    final userId = currentUser?.id;
    if (userId == null) return false;

    try {
      final merchant = await client
          .from('merchants')
          .select('verified, access_status')
          .eq('id', userId)
          .maybeSingle();

      if (merchant == null) return false;

      final verified = merchant['verified'] as bool? ?? false;
      final accessStatus = merchant['access_status'] as String? ?? 'pending';

      return verified && accessStatus == 'approved';
    } catch (e) {
      debugPrint('Error checking merchant status: $e');
      return false;
    }
  }

  static Future<void> savePendingMerchantData({
    required String userId,
    required String businessName,
    required String address,
    required String municipality,
    required String contactNumber,
    required String ownerName,
    required String ownerContact,
    required double latitude,
    required double longitude,
    String? placeId,
    String? dtiCertificateUrl,
    String? mayorPermitUrl,
    String? loadingStationCode,
  }) async {
    try {

      try {
        await client.from('pending_merchant_registrations').insert({
          'user_id': userId,
          'business_name': businessName,
          'address': address,
          'municipality': municipality,
          'contact_number': contactNumber,
          'owner_name': ownerName,
          'owner_contact': ownerContact,
          'latitude': latitude,
          'longitude': longitude,
          'map_place_id': placeId,
          'dti_certificate_url': dtiCertificateUrl,
          'mayor_permit_url': mayorPermitUrl,
          'loading_station_code': loadingStationCode,
        });
        debugPrint('Pending merchant data saved successfully via direct insert');
      } catch (e) {

        debugPrint('Direct insert failed, using database function: $e');
        try {
          final result = await client.rpc('create_pending_merchant_registration', params: {
            'p_user_id': userId,
            'p_business_name': businessName,
            'p_address': address,
            'p_municipality': municipality,
            'p_contact_number': contactNumber,
            'p_owner_name': ownerName,
            'p_owner_contact': ownerContact,
            'p_latitude': latitude,
            'p_longitude': longitude,
            'p_map_place_id': placeId,
            'p_dti_certificate_url': dtiCertificateUrl,
            'p_mayor_permit_url': mayorPermitUrl,
          });
          debugPrint('Database function result: $result');
          debugPrint('Pending merchant data saved successfully via database function');
        } catch (functionError) {
          debugPrint('Database function also failed: $functionError');
          rethrow;
        }
      }
    } catch (e) {
      debugPrint('Error saving pending merchant data: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> getPendingMerchantData(String userId) async {
    try {
      final response = await client
          .from('pending_merchant_registrations')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('Error getting pending merchant data: $e');
      return null;
    }
  }

  static Future<bool> isApprovedMerchant() async {
    final userId = currentUser?.id;
    if (userId == null) return false;

    try {
      final user = await client
          .from('users')
          .select('role, is_active')
          .eq('id', userId)
          .maybeSingle();

      if (user == null || user['role'] != 'merchant') return false;
      if (user['is_active'] != true) return false;

      final merchant = await client
          .from('merchants')
          .select('verified, access_status')
          .eq('id', userId)
          .maybeSingle();




      if (merchant == null) {



        return true;
      }

      final verified = merchant['verified'] as bool? ?? false;
      final accessStatus = merchant['access_status'] as String? ?? 'pending';
      return verified && accessStatus == 'approved';
    } catch (e) {
      debugPrint('Error checking approved merchant status: $e');
      return false;
    }
  }
}
