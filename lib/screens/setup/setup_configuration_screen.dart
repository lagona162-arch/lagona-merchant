import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/colors.dart';
import '../../services/merchant_service.dart';
import '../../services/supabase_service.dart';
import '../../services/google_places_service.dart';
import '../../models/merchant.dart';
import '../../widgets/address_autocomplete_field.dart';

class SetupConfigurationScreen extends StatefulWidget {
  const SetupConfigurationScreen({super.key});

  @override
  State<SetupConfigurationScreen> createState() =>
      _SetupConfigurationScreenState();
}

class _SetupConfigurationScreenState extends State<SetupConfigurationScreen> {

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
      appBar: AppBar(
          title: const Text('Setup'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Configuration', icon: Icon(Icons.settings_outlined)),
              Tab(text: 'Payments', icon: Icon(Icons.payment_outlined)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ConfigurationTab(),
            _PaymentsTab(),
          ],
        ),
      ),
    );
  }

}

// Configuration Tab Widget
class _ConfigurationTab extends StatefulWidget {
  const _ConfigurationTab();

  @override
  State<_ConfigurationTab> createState() => _ConfigurationTabState();
}

class _ConfigurationTabState extends State<_ConfigurationTab> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  File? _logoImage;
  String? _currentLogoUrl;
  bool _isLoading = false;
  bool _isEditingBusinessName = false;
  bool _isEditingLocation = false;
  String? _currentMerchantId;
  String? _currentBusinessName;
  String? _currentAddress;
  double? _currentLatitude;
  double? _currentLongitude;
  String? _currentPlaceId;
  double? _newLatitude;
  double? _newLongitude;
  String? _newPlaceId;
  Merchant? _merchant;

  @override
  void initState() {
    super.initState();
    _loadMerchantData();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadMerchantData() async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return;

    final merchant = await MerchantService.getMerchantByUserId(userId);
    if (merchant != null) {
      setState(() {
        _currentMerchantId = merchant.id;
        _merchant = merchant;
        _currentLogoUrl = merchant.previewImage;
        _currentBusinessName = merchant.businessName;
        _businessNameController.text = merchant.businessName;
        _currentAddress = merchant.address;
        _addressController.text = merchant.address;
        _currentLatitude = merchant.latitude;
        _currentLongitude = merchant.longitude;
        _currentPlaceId = merchant.mapPlaceId;
        _isEditingBusinessName = false;
        _isEditingLocation = false;
        _newLatitude = null;
        _newLongitude = null;
        _newPlaceId = null;
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null) {
      setState(() {
          _logoImage = File(image.path);
      });
    }
  }

  Future<void> _saveConfiguration() async {
    if (_currentMerchantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Merchant profile not found'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final businessName = _businessNameController.text.trim();
    if (businessName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Business name cannot be empty'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final hasLocationChanges = _newLatitude != null && _newLongitude != null &&
        (_newLatitude != _currentLatitude || _newLongitude != _currentLongitude);
    final hasAddressChanges = _addressController.text.trim() != _currentAddress;
    
    // If location changed, we should also update the address to keep them in sync
    final shouldUpdateAddress = hasAddressChanges || hasLocationChanges;
    
    if (_logoImage == null && businessName == _currentBusinessName && !hasLocationChanges && !hasAddressChanges) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No changes to save'),
          backgroundColor: AppColors.textSecondary,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? logoUrl = _currentLogoUrl;

      if (_logoImage != null) {
        logoUrl = await MerchantService.uploadLogo(_logoImage!);
      }

      await MerchantService.updateMerchant(
        merchantId: _currentMerchantId!,
        businessName: businessName != _currentBusinessName ? businessName : null,
        previewImage: logoUrl,
        address: shouldUpdateAddress ? _addressController.text.trim() : null,
        latitude: hasLocationChanges ? _newLatitude : null,
        longitude: hasLocationChanges ? _newLongitude : null,
        placeId: hasLocationChanges ? _newPlaceId : null,
      );

      await _loadMerchantData();

      setState(() {
        _logoImage = null;
        _isEditingBusinessName = false;
        _isEditingLocation = false;
        _newLatitude = null;
        _newLongitude = null;
        _newPlaceId = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuration saved successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveBusinessNameOnly() async {
    if (_currentMerchantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Merchant profile not found'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final businessName = _businessNameController.text.trim();
    if (businessName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Business name cannot be empty'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await MerchantService.updateMerchant(
        merchantId: _currentMerchantId!,
        businessName: businessName,
      );

      await _loadMerchantData();

      setState(() {
        _isEditingBusinessName = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Business name saved successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: ${e.toString()}'),
            backgroundColor: AppColors.error,
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
  Widget build(BuildContext context) {
    return SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionHeader('Business Name'),
              const SizedBox(height: 12),
              const Text(
                'Update your business name as it appears to customers.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _businessNameController,
                      enabled: _isEditingBusinessName,
                      readOnly: !_isEditingBusinessName,
                      decoration: InputDecoration(
                        labelText: 'Business Name',
                        hintText: 'Enter your business name',
                        prefixIcon: const Icon(Icons.store_outlined),
                        border: const OutlineInputBorder(),
                        helperText: _isEditingBusinessName
                            ? 'Enter your business name'
                            : 'Tap Edit to modify',
                        suffixIcon: !_isEditingBusinessName
                            ? const Icon(Icons.lock_outline, size: 20)
                            : null,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Business name cannot be empty';
                        }
                        return null;
                      },
                    ),
                  ),
                  if (!_isEditingBusinessName) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () {
                        setState(() {
                          _isEditingBusinessName = true;
                        });
                      },
                      tooltip: 'Edit Business Name',
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.primary.withOpacity(0.1),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.save_outlined),
                      onPressed: _isLoading ? null : _saveBusinessNameOnly,
                      tooltip: 'Save Business Name',
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.success.withOpacity(0.1),
                        foregroundColor: AppColors.success,
                      ),
                    ),
                  ],
                ],
              ),
              if (_isEditingBusinessName)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel'),
                    onPressed: () {
                      setState(() {
                        _isEditingBusinessName = false;
                        _businessNameController.text = _currentBusinessName ?? '';
                      });
                    },
                  ),
                ),
              const SizedBox(height: 32),
              _buildSectionHeader('Business Location'),
              const SizedBox(height: 12),
              const Text(
                'Update your business location. This helps customers and riders find you.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              AddressAutocompleteField(
                controller: _addressController,
                label: 'Business Address',
                hint: 'Enter or select your business address',
                icon: Icons.location_on,
                initialLatitude: _currentLatitude,
                initialLongitude: _currentLongitude,
                onPlaceSelected: (placeDetails) {
                  setState(() {
                    // Update address controller with formatted address from place details
                    if (placeDetails.formattedAddress.isNotEmpty) {
                      _addressController.text = placeDetails.formattedAddress;
                    }
                    _newLatitude = placeDetails.latitude;
                    _newLongitude = placeDetails.longitude;
                    _newPlaceId = placeDetails.placeId;
                    _isEditingLocation = true;
                  });
                },
              ),
              if (_currentLatitude != null && _currentLongitude != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Current coordinates: ${_currentLatitude!.toStringAsFixed(6)}, ${_currentLongitude!.toStringAsFixed(6)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (_newLatitude != null && _newLongitude != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'New coordinates: ${_newLatitude!.toStringAsFixed(6)}, ${_newLongitude!.toStringAsFixed(6)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
              _buildSectionHeader('Logo Upload'),
              const SizedBox(height: 12),
              const Text(
                'Upload your business logo to display on your merchant profile.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              _buildImagePicker(
                'Business Logo',
                _logoImage,
                _currentLogoUrl,
                true,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveConfiguration,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Save Configuration'),
              ),
            ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
      ),
    );
  }

  Widget _buildImagePicker(String label, File? file, String? currentUrl, bool isLogo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            if ((file != null) || (currentUrl != null && currentUrl!.isNotEmpty)) {
              if (file != null) {
                _showLogoFullScreen(file: file);
              } else if (currentUrl != null && currentUrl!.isNotEmpty) {
                _showLogoFullScreen(imageUrl: currentUrl);
              }
            } else {
              _showImageSourceDialog();
            }
          },
          child: Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border.all(color: AppColors.border.withOpacity(0.5)),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
                      ],
                    ),
            child: _buildImageContent(file, currentUrl),
          ),
        ),
        if (file != null || currentUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: TextButton.icon(
              onPressed: () async {
                if (currentUrl != null && file == null && _currentMerchantId != null) {
                  try {
                    await SupabaseService.client
                        .from('merchants')
                        .update({'preview_image': null})
                        .eq('id', _currentMerchantId!);

                    await _loadMerchantData();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error removing logo: ${e.toString()}'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                    return;
                  }
                }

                setState(() {
                    _logoImage = null;
                  _currentLogoUrl = null;
                });
              },
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Remove'),
            ),
          ),
      ],
    );
  }

  Widget _buildImageContent(File? file, String? currentUrl) {
    if (file != null) {
      return Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.zoom_in, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Tap to view',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    } else if (currentUrl != null && currentUrl.isNotEmpty) {
      return Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  currentUrl,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image, size: 32, color: Colors.grey),
                          SizedBox(height: 8),
                          Text(
                            'Failed to load image',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.zoom_in, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Tap to view',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.image_outlined,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Tap to upload logo',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Recommended: Square format (1:1)',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }
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

  void _showLogoFullScreen({File? file, String? imageUrl}) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Business Logo',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 3.0,
                        child: file != null
                            ? Image.file(file, fit: BoxFit.contain)
                            : imageUrl != null
                                ? Image.network(
                                    imageUrl,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Padding(
                                        padding: EdgeInsets.all(32),
                                        child: Icon(Icons.error_outline, size: 64),
                                      );
                                    },
                                  )
                                : const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Payments Tab Widget
class _PaymentsTab extends StatefulWidget {
  const _PaymentsTab();

  @override
  State<_PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends State<_PaymentsTab> {
  final ImagePicker _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _gcashNumberController = TextEditingController();
  File? _gcashQrImage;
  bool _isLoading = false;
  bool _isEditingGcashNumber = false;
  String? _currentQrUrl;
  String? _currentGcashNumber;
  String? _merchantId;

  @override
  void initState() {
    super.initState();
    _loadGCashQR();
  }

  @override
  void dispose() {
    _gcashNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadGCashQR() async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return;

    final merchant = await MerchantService.getMerchantByUserId(userId);
    if (merchant != null && mounted) {
      setState(() {
        _merchantId = merchant.id;
        _currentQrUrl = merchant.gcashQrUrl;
        _currentGcashNumber = merchant.gcashNumber;
        _gcashNumberController.text = merchant.gcashNumber ?? '';
        _isEditingGcashNumber = merchant.gcashNumber == null || merchant.gcashNumber!.isEmpty;
      });
    }
  }

  Future<void> _pickQRImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null) {
      setState(() {
        _gcashQrImage = File(image.path);
      });
    }
  }

  Future<void> _saveGCashSettings() async {
    if (_merchantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Merchant not found'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final gcashNumber = _gcashNumberController.text.trim();

    if (gcashNumber.isEmpty && _gcashQrImage == null && _currentQrUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide GCash number or QR code'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (gcashNumber.isNotEmpty) {
      if (gcashNumber.length != 11) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GCash number must be exactly 11 digits'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      if (!gcashNumber.startsWith('09')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GCash number must start with 09'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      String? qrUrl = _currentQrUrl;

      if (_gcashQrImage != null) {
        qrUrl = await MerchantService.uploadGCashQR(_gcashQrImage!);
      }

      await MerchantService.updateGCashQR(
        merchantId: _merchantId!,
        qrUrl: qrUrl,
        gcashNumber: gcashNumber.isNotEmpty ? gcashNumber : null,
      );

      setState(() {
        _currentQrUrl = qrUrl;
        _currentGcashNumber = gcashNumber.isNotEmpty ? gcashNumber : null;
        _gcashQrImage = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GCash settings saved successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveGCashNumberOnly() async {
    if (_merchantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Merchant not found'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final gcashNumber = _gcashNumberController.text.trim();

    if (gcashNumber.isNotEmpty) {
      if (gcashNumber.length != 11) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GCash number must be exactly 11 digits'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      if (!gcashNumber.startsWith('09')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GCash number must start with 09'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      await MerchantService.updateGCashQR(
        merchantId: _merchantId!,
        qrUrl: _currentQrUrl,
        gcashNumber: gcashNumber.isNotEmpty ? gcashNumber : null,
      );

      setState(() {
        _currentGcashNumber = gcashNumber.isNotEmpty ? gcashNumber : null;
        _isEditingGcashNumber = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GCash number saved successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: ${e.toString()}'),
            backgroundColor: AppColors.error,
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
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'GCash Payment Settings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Set up your GCash QR Code and number for customer payments',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _gcashNumberController,
                                enabled: _isEditingGcashNumber,
                                readOnly: !_isEditingGcashNumber && _currentGcashNumber != null && _currentGcashNumber!.isNotEmpty,
                                decoration: InputDecoration(
                                  labelText: 'GCash Number',
                                  hintText: '09123456789',
                                  prefixIcon: const Icon(Icons.phone),
                                  border: const OutlineInputBorder(),
                                  helperText: _isEditingGcashNumber || (_currentGcashNumber == null || _currentGcashNumber!.isEmpty)
                                      ? 'Your GCash mobile number (11 digits starting with 09)'
                                      : 'Tap Edit to modify',
                                  suffixIcon: !_isEditingGcashNumber && (_currentGcashNumber != null && _currentGcashNumber!.isNotEmpty)
                                      ? const Icon(Icons.lock_outline, size: 20)
                                      : null,
                                ),
                                keyboardType: TextInputType.phone,
                                maxLength: 11,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return null;
                                  }
                                  if (value.length != 11) {
                                    return 'GCash number must be exactly 11 digits';
                                  }
                                  if (!value.startsWith('09')) {
                                    return 'GCash number must start with 09';
                                  }
                                  if (!RegExp(r'^\d+$').hasMatch(value)) {
                                    return 'GCash number must contain only digits';
                                  }
                                  return null;
                                },
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(11),
                                ],
                                onChanged: (value) {
                                  if (value.isNotEmpty && value.length == 1 && value != '0') {
                                    _gcashNumberController.value = TextEditingValue(
                                      text: '0$value',
                                      selection: TextSelection.collapsed(offset: 2),
                                    );
                                  }

                                  if (value.isNotEmpty && !value.startsWith('0')) {
                                    _gcashNumberController.value = TextEditingValue(
                                      text: '0${value.substring(0, value.length > 10 ? 10 : value.length)}',
                                      selection: TextSelection.collapsed(
                                        offset: value.length > 10 ? 11 : value.length + 1,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                            if (_currentGcashNumber != null && _currentGcashNumber!.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              if (!_isEditingGcashNumber)
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () {
                                    setState(() {
                                      _isEditingGcashNumber = true;
                                    });
                                  },
                                  tooltip: 'Edit GCash Number',
                                  style: IconButton.styleFrom(
                                    backgroundColor: AppColors.primary.withOpacity(0.1),
                                  ),
                                )
                              else
                                IconButton(
                                  icon: const Icon(Icons.save_outlined),
                                  onPressed: _isLoading ? null : _saveGCashNumberOnly,
                                  tooltip: 'Save GCash Number',
                                  style: IconButton.styleFrom(
                                    backgroundColor: AppColors.success.withOpacity(0.1),
                                    foregroundColor: AppColors.success,
                                  ),
                                ),
                            ],
                          ],
                        ),
                        if (_isEditingGcashNumber && _currentGcashNumber != null && _currentGcashNumber!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: TextButton.icon(
                              icon: const Icon(Icons.cancel_outlined),
                              label: const Text('Cancel'),
                              onPressed: () {
                                setState(() {
                                  _isEditingGcashNumber = false;
                                  _gcashNumberController.text = _currentGcashNumber ?? '';
                                });
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'GCash QR Code',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Upload your GCash QR Code image',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  if (_currentQrUrl != null) ...[
                    GestureDetector(
                      onTap: () => _showQRFullScreen(_currentQrUrl!),
                      child: Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Stack(
                          children: [
                            Image.network(
                              _currentQrUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Center(
                                  child: Icon(Icons.error_outline, size: 48),
                                );
                              },
                            ),
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.zoom_in, size: 16, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text(
                                      'Tap to view',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_gcashQrImage == null)
                    InkWell(
                      onTap: () => _showImageSourceDialog(),
                      child: Container(
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.qr_code_scanner_outlined, size: 48),
                              SizedBox(height: 8),
                              Text('Tap to upload GCash QR Code'),
                            ],
                          ),
                        ),
                      ),
                    )
                  else ...[
                    Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Stack(
                        children: [
                          Image.file(_gcashQrImage!, fit: BoxFit.cover),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              icon: const Icon(Icons.close_outlined),
                              onPressed: () {
                                setState(() => _gcashQrImage = null);
                              },
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : () => _showImageSourceDialog(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Change QR Code'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveGCashSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Save GCash Settings'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Transaction History',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long,
                          size: 64,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Transaction history will appear here',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
                _pickQRImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickQRImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showQRFullScreen(String qrUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'GCash QR Code',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 3.0,
                        child: Image.network(
                          qrUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Padding(
                              padding: EdgeInsets.all(32),
                              child: Icon(Icons.error_outline, size: 64),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
