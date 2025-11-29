import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/colors.dart';
import '../../services/supabase_service.dart';
import '../auth/login_screen.dart';
import 'merchant_dashboard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isCheckingRole = true;
  bool _isMerchant = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  void _checkAuth() {

    SupabaseService.client.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        _verifyMerchantRole();
      }
    });
    _verifyMerchantRole();
  }

  Future<void> _verifyMerchantRole() async {
    if (!SupabaseService.isSignedIn) {
      setState(() {
        _isCheckingRole = false;
        _isMerchant = false;
      });
      return;
    }

    setState(() {
      _isCheckingRole = true;
    });

    try {

      final role = await SupabaseService.getUserRole();

      if (role != 'merchant') {

        await SupabaseService.signOut();

        if (mounted) {
          setState(() {
            _isMerchant = false;
            _isCheckingRole = false;
          });
        }
        return;
      }

      final isMerchant = await SupabaseService.isMerchant();

      if (!isMerchant) {

        await SupabaseService.signOut();
      }

      if (mounted) {
        setState(() {
          _isMerchant = isMerchant;
          _isCheckingRole = false;
        });
      }
    } catch (e) {

      debugPrint('Error verifying merchant role: $e');
      try {
        await SupabaseService.signOut();
      } catch (signOutError) {
        debugPrint('Error signing out: $signOutError');
      }

      if (mounted) {
        setState(() {
          _isMerchant = false;
          _isCheckingRole = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    if (_isCheckingRole) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (SupabaseService.isSignedIn && _isMerchant) {
      return const MerchantDashboardScreen();
    }

    return const LoginScreen();
  }
}
