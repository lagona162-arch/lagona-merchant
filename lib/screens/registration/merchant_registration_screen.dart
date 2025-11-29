import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/colors.dart';
import '../../services/supabase_service.dart';
import '../../services/merchant_service.dart';
import '../../services/google_places_service.dart';
import '../../widgets/address_autocomplete_field.dart';
import '../auth/login_screen.dart';

class MerchantRegistrationScreen extends StatefulWidget {
  const MerchantRegistrationScreen({super.key});

  @override
  State<MerchantRegistrationScreen> createState() =>
      _MerchantRegistrationScreenState();
}

class _MerchantRegistrationScreenState
    extends State<MerchantRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  final _businessAddressController = TextEditingController();
  final _municipalityController = TextEditingController();
  final _emailController = TextEditingController();
  final _contactNumberController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _ownerContactController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  File? _dtiCertificate;
  File? _mayorPermit;
  String? _selectedDocumentType;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  double? _selectedLatitude;
  double? _selectedLongitude;
  String? _selectedPlaceId;
  bool _municipalityAutoFilled = false;
  String? _lastAutoFilledMunicipality;

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null) {
      setState(() {
        if (_selectedDocumentType == 'dti') {
          _dtiCertificate = File(image.path);
        } else if (_selectedDocumentType == 'mayor_permit') {
          _mayorPermit = File(image.path);
        }
      });
    }
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {

      final authResponse = await SupabaseService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _ownerNameController.text.trim(),
        phone: _ownerContactController.text.trim(),
      );

      if (authResponse.user == null) {
        throw Exception('Failed to create user account');
      }

      final hasSession = authResponse.session != null || SupabaseService.isSignedIn;
      debugPrint('Has active session after signup: $hasSession');
      debugPrint('Auth response user ID: ${authResponse.user?.id}');
      debugPrint('Current Supabase user ID: ${SupabaseService.currentUser?.id}');
      debugPrint('Session from auth response: ${authResponse.session != null}');

      if (hasSession) {
        debugPrint('Session is available - auth.uid() should match: ${SupabaseService.currentUser?.id}');
        debugPrint('Auth UID matches userId: ${SupabaseService.currentUser?.id == authResponse.user?.id}');
      } else {
        debugPrint('Warning: No session after signup - document uploads might fail due to RLS policies');
        debugPrint('This may happen if email confirmation is required');
      }

      if (_selectedLatitude == null || _selectedLongitude == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select an address from the suggestions'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      String? dtiUrl;
      String? mayorPermitUrl;

      if (_dtiCertificate != null) {
        try {
          dtiUrl = await MerchantService.uploadDocument(_dtiCertificate!, 'dti_certificates', authResponse.user!.id);
          debugPrint('DTI certificate uploaded - URL: $dtiUrl');
        } catch (e) {
          debugPrint('Warning: Failed to upload DTI certificate: $e');

        }
      }

      if (_mayorPermit != null) {
        try {
          mayorPermitUrl = await MerchantService.uploadDocument(_mayorPermit!, 'mayor_permits', authResponse.user!.id);
          debugPrint('Mayor permit uploaded - URL: $mayorPermitUrl');
        } catch (e) {
          debugPrint('Warning: Failed to upload Mayor permit: $e');

        }
      }

      await SupabaseService.savePendingMerchantData(
        userId: authResponse.user!.id,
        businessName: _businessNameController.text.trim(),
        address: _businessAddressController.text.trim(),
        municipality: _municipalityController.text.trim(),
        contactNumber: _contactNumberController.text.trim(),
        ownerName: _ownerNameController.text.trim(),
        ownerContact: _ownerContactController.text.trim(),
        latitude: _selectedLatitude!,
        longitude: _selectedLongitude!,
        placeId: _selectedPlaceId,
        dtiCertificateUrl: dtiUrl,
        mayorPermitUrl: mayorPermitUrl,
      );

      if (SupabaseService.isSignedIn) {
        debugPrint('Signing out after registration - waiting for admin approval');
        await SupabaseService.signOut();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration successful! Your account is pending admin approval. Please log in after your account is verified.'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 5),
          ),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const LoginScreen(),
          ),
          (route) => false,
        );
      }
    } catch (e) {

      if (SupabaseService.isSignedIn) {
        try {
          await SupabaseService.signOut();
        } catch (signOutError) {
          debugPrint('Error signing out: $signOutError');
        }
      }

      if (mounted) {

        String errorMessage = 'Registration failed';

        if (e.toString().contains('email')) {
          errorMessage = 'Registration failed: Email may already be in use. Please try again or sign in.';
        } else if (e.toString().contains('network') || e.toString().contains('connection')) {
          errorMessage = 'Registration failed: Network error. Please check your connection and try again.';
        } else if (e.toString().contains('timeout')) {
          errorMessage = 'Registration failed: Request timed out. Please try again.';
        } else {
          errorMessage = 'Registration failed: ${e.toString()}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _businessAddressController.dispose();
    _municipalityController.dispose();
    _emailController.dispose();
    _contactNumberController.dispose();
    _ownerNameController.dispose();
    _ownerContactController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Merchant Registration'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        color: AppColors.background,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [

                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.secondary,
                      width: 3,
                    ),
                  ),
                  child: Column(
                    children: [

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(13),
                            topRight: Radius.circular(13),
                          ),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.store_outlined, color: AppColors.secondary, size: 32),
                            SizedBox(height: 12),
                            Text(
                              'Tell Us About Your Business',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          color: AppColors.secondary,
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(13),
                            bottomRight: Radius.circular(13),
                          ),
                        ),
                        child: const Text(
                          'Fill in the details to get started',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                _buildSectionCard(
                  icon: Icons.business_outlined,
                  title: 'Business Information',
                  color: AppColors.secondary,
                  children: [
                    _buildStyledTextField(
                      controller: _businessNameController,
                      label: 'Business Name',
                      hint: 'e.g., Lagona Cafe',
                      icon: Icons.store_outlined,
                      validator: (value) =>
                          value?.isEmpty ?? true ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    AddressAutocompleteField(
                      controller: _businessAddressController,
                      label: 'Business Address',
                      hint: 'Start typing your address...',
                      icon: Icons.location_on_outlined,
                      maxLines: 2,
                      validator: (value) =>
                          value?.isEmpty ?? true ? 'Required' : null,
                      onPlaceSelected: (PlaceDetails details) {
                        setState(() {
                          _selectedLatitude = details.latitude;
                          _selectedLongitude = details.longitude;
                          _selectedPlaceId = details.placeId;

                          final municipality = details.getMunicipality();
                          debugPrint('Place selected - Municipality extracted: $municipality');
                          debugPrint('Address components: ${details.addressComponents.length}');

                          if (municipality != null && municipality.isNotEmpty) {
                            _municipalityController.text = municipality;
                            _lastAutoFilledMunicipality = municipality;
                            _municipalityAutoFilled = true;
                          } else {
                            _municipalityAutoFilled = false;
                            _lastAutoFilledMunicipality = null;

                            final formattedAddress = details.formattedAddress;
                            if (formattedAddress.isNotEmpty) {

                              final parts = formattedAddress.split(',');
                              if (parts.length >= 2) {
                                final potentialMunicipality = parts[1].trim();
                                if (potentialMunicipality.isNotEmpty) {
                                  _municipalityController.text = potentialMunicipality;
                                  _lastAutoFilledMunicipality = potentialMunicipality;
                                  _municipalityAutoFilled = true;
                                }
                              }
                            }
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildMunicipalityField(),
                    const SizedBox(height: 16),
                    _buildStyledTextField(
                      controller: _contactNumberController,
                      label: 'Business Contact Number',
                      hint: 'e.g., 09123456789 or 639123456789',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      maxLength: 11,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      validator: (value) {
                        if (value?.isEmpty ?? true) return 'Required';

                        final cleaned = value!.replaceAll(RegExp(r'[^\d]'), '');
                        if (cleaned.length != 11) {
                          return 'Must be exactly 11 digits';
                        }

                        if (!cleaned.startsWith('09') && !cleaned.startsWith('639')) {
                          return 'Must start with 09 or 639';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                _buildSectionCard(
                  icon: Icons.person_outline,
                  title: 'Owner/Manager Information',
                  color: AppColors.primary,
                  children: [
                    _buildStyledTextField(
                      controller: _ownerNameController,
                      label: 'Full Name of Owner/Manager',
                      hint: 'e.g., Juan Dela Cruz',
                      icon: Icons.badge_outlined,
                      validator: (value) =>
                          value?.isEmpty ?? true ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildStyledTextField(
                      controller: _ownerContactController,
                      label: 'Owner/Manager Contact Number',
                      hint: 'e.g., 09123456789 or 639123456789',
                      icon: Icons.phone_android_outlined,
                      keyboardType: TextInputType.phone,
                      maxLength: 11,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      validator: (value) {
                        if (value?.isEmpty ?? true) return 'Required';

                        final cleaned = value!.replaceAll(RegExp(r'[^\d]'), '');
                        if (cleaned.length != 11) {
                          return 'Must be exactly 11 digits';
                        }

                        if (!cleaned.startsWith('09') && !cleaned.startsWith('639')) {
                          return 'Must start with 09 or 639';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                _buildSectionCard(
                  icon: Icons.lock_outline,
                  title: 'Account Information',
                  color: AppColors.secondary,
                  children: [
                    _buildStyledTextField(
                      controller: _emailController,
                      label: 'Email Address',
                      hint: 'e.g., business@example.com',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value?.isEmpty ?? true) return 'Required';
                        if (!value!.contains('@')) return 'Invalid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildPasswordField(
                      controller: _passwordController,
                      label: 'Password',
                      hint: 'Minimum 6 characters',
                      obscureText: _obscurePassword,
                      onToggle: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                      validator: (value) {
                        if (value?.isEmpty ?? true) return 'Required';
                        if (value!.length < 6) return 'Min 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildPasswordField(
                      controller: _confirmPasswordController,
                      label: 'Confirm Password',
                      hint: 'Re-enter your password',
                      obscureText: _obscureConfirmPassword,
                      onToggle: () {
                        setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                      },
                      validator: (value) {
                        if (value?.isEmpty ?? true) return 'Required';
                        if (value != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                _buildSectionCard(
                  icon: Icons.upload_file_outlined,
                  title: 'Business Documents',
                  subtitle: '(Optional)',
                  color: AppColors.primary,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: AppColors.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                                children: [
                                  const TextSpan(
                                    text: 'Choose ',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  TextSpan(
                                    text: 'EITHER ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const TextSpan(text: 'DTI Certificate '),
                                  const TextSpan(
                                    text: 'OR ',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const TextSpan(
                                    text: 'Mayor\'s Permit to upload.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Expanded(
                          child: _buildDocumentTypeChoice(
                            'DTI Certificate',
                            'dti',
                            Icons.description_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDocumentTypeChoice(
                            'Mayor\'s Permit',
                            'mayor_permit',
                            Icons.assignment_outlined,
                          ),
                        ),
                      ],
                    ),

                    if (_selectedDocumentType != null) ...[
                      const SizedBox(height: 20),
                      _buildDocumentPicker(
                        _selectedDocumentType == 'dti'
                            ? 'DTI Certificate'
                            : 'Mayor\'s Permit',
                        _selectedDocumentType == 'dti'
                            ? _dtiCertificate
                            : _mayorPermit,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 32),

                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitRegistration,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: AppColors.primary,
                          width: 3,
                        ),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline, size: 24, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Text(
                                'Complete Registration',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.secondary,
          width: 2,
        ),
      ),
      child: Column(
        children: [

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondary,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    int maxLines = 1,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        maxLines: maxLines,
        maxLength: maxLength,
        inputFormatters: inputFormatters,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: AppColors.primary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildMunicipalityField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            TextFormField(
            controller: _municipalityController,
            onChanged: (value) {

              if (_municipalityAutoFilled && value != _lastAutoFilledMunicipality) {
                setState(() {
                  _municipalityAutoFilled = false;
                });
              }
            },
            validator: (value) =>
                value?.isEmpty ?? true ? 'Required' : null,
            decoration: InputDecoration(
              labelText: 'Municipality',
              hintText: 'e.g., Quezon City',
              prefixIcon: Icon(Icons.location_city_outlined, color: AppColors.primary),
              suffixIcon: _municipalityAutoFilled
                  ? Tooltip(
                      message: 'Auto-filled from address. You can edit this if needed.',
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Auto-filled',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
          if (_municipalityAutoFilled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Auto-filled from address. You can edit this if needed.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool obscureText,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(Icons.lock_outline, color: AppColors.primary),
          suffixIcon: IconButton(
            icon: Icon(
              obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: AppColors.textSecondary,
            ),
            onPressed: onToggle,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentTypeChoice(
    String label,
    String value,
    IconData icon,
  ) {
    final isSelected = _selectedDocumentType == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedDocumentType = value;

          if (value == 'dti') {
            _mayorPermit = null;
          } else {
            _dtiCertificate = null;
          }
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : Colors.white,
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentPicker(
    String label,
    File? file,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _showImageSourceDialog(),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              color: file == null ? AppColors.background : Colors.white,
              border: Border.all(
                color: file == null
                    ? AppColors.border
                    : AppColors.primary.withOpacity(0.5),
                width: file == null ? 1 : 2,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: file == null
                  ? null
                  : [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: file == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.upload_file_outlined,
                            size: 40,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tap to upload',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          file,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.close_outlined, color: Colors.white),
                            onPressed: () {
                              setState(() {
                                if (_selectedDocumentType == 'dti') {
                                  _dtiCertificate = null;
                                } else {
                                  _mayorPermit = null;
                                }
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Image Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
                            ListTile(
                              leading: const Icon(Icons.camera_alt_outlined),
                              title: const Text('Camera'),
                              onTap: () {
                                Navigator.pop(context);
                                _pickImage(ImageSource.camera);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.photo_library_outlined),
                              title: const Text('Gallery'),
                              onTap: () {
                                Navigator.pop(context);
                                _pickImage(ImageSource.gallery);
                              },
                            ),
          ],
        ),
      ),
    );
  }
}
