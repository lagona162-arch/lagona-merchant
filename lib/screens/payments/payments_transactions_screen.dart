import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/colors.dart';
import '../../services/merchant_service.dart';
import '../../services/supabase_service.dart';

class PaymentsTransactionsScreen extends StatefulWidget {
  const PaymentsTransactionsScreen({super.key});

  @override
  State<PaymentsTransactionsScreen> createState() =>
      _PaymentsTransactionsScreenState();
}

class _PaymentsTransactionsScreenState
    extends State<PaymentsTransactionsScreen> {
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

  Future<void> _loadGCashQR() async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return;

    final merchant = await MerchantService.getMerchantByUserId(userId);
    if (merchant != null) {
      setState(() {
        _merchantId = merchant.id;
        _currentQrUrl = merchant.gcashQrUrl;
        _currentGcashNumber = merchant.gcashNumber;
        _gcashNumberController.text = merchant.gcashNumber ?? '';

        _isEditingGcashNumber = merchant.gcashNumber == null || merchant.gcashNumber!.isEmpty;
      });
    }
  }

  @override
  void dispose() {
    _gcashNumberController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments & Transactions'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
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
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.white),
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
}
