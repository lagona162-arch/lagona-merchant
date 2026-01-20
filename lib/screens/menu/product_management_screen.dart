import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/colors.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';

class ProductManagementScreen extends StatefulWidget {
  const ProductManagementScreen({super.key});

  @override
  State<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

class _ProductManagementScreenState extends State<ProductManagementScreen> {
  List<MerchantProduct> _products = [];
  List<String> _categories = [];
  bool _isLoading = true;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ProductService.getProducts(),
        ProductService.getCategories(),
      ]);
      setState(() {
        _products = results[0] as List<MerchantProduct>;
        _categories = results[1] as List<String>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load data: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _addProduct() async {
    await _showProductDialog();
  }

  Future<void> _editProduct(MerchantProduct product) async {
    await _showProductDialog(product: product);
  }

  Future<void> _deleteProduct(String productId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: const Text('Are you sure you want to delete this product?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ProductService.deleteProduct(productId);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product deleted successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete product: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _showProductDialog({MerchantProduct? product}) async {
    final nameController = TextEditingController(text: product?.name ?? '');

    final priceValue = product?.price ?? 0.0;
    final priceController = TextEditingController(
      text: priceValue > 0 ? priceValue.toStringAsFixed(2) : '',
    );
    final stockController =
        TextEditingController(text: product?.stock.toString() ?? '0');
    String? selectedCategory = product?.category;
    File? imageFile;
    bool isAvailable = product?.isAvailable ?? true;
    bool isSubmitting = false; // Local flag for dialog
    bool isBatchMode = false; // Batch mode flag (only for new products)
    int batchCount = 0; // Count of products added in batch mode

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product == null ? 'Add Product' : 'Edit Product'),
              if (product == null && isBatchMode && batchCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Added $batchCount product${batchCount > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.success,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (product == null) ...[
                  CheckboxListTile(
                    title: const Text('Add Multiple Products (Batch Mode)'),
                    subtitle: const Text('Keep form open after adding to add more products'),
                    value: isBatchMode,
                    onChanged: (value) =>
                        setDialogState(() => isBatchMode = value ?? false),
                  ),
                  const SizedBox(height: 8),
                ],
                GestureDetector(
                  onTap: () async {
                    final source = await showDialog<ImageSource>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Select Image Source'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.camera_alt_outlined),
                              title: const Text('Camera'),
                              onTap: () =>
                                  Navigator.pop(context, ImageSource.camera),
                            ),
                            ListTile(
                              leading: const Icon(Icons.photo_library_outlined),
                              title: const Text('Gallery'),
                              onTap: () =>
                                  Navigator.pop(context, ImageSource.gallery),
                            ),
                          ],
                        ),
                      ),
                    );

                    if (source != null) {
                      final image =
                          await _picker.pickImage(source: source);
                      if (image != null) {
                        setDialogState(() {
                          imageFile = File(image.path);
                        });
                      }
                    }
                  },
                  child: Container(
                    height: 100,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: imageFile != null
                        ? Image.file(imageFile!, fit: BoxFit.cover)
                        : const Icon(Icons.add_photo_alternate_outlined),
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Product Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: _categories
                      .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedCategory = value),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: priceController,
                  decoration: InputDecoration(
                    labelText: 'Price',
                    hintText: '0.00',
                    border: const OutlineInputBorder(),
                    prefixText: '₱',
                    prefixStyle: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: stockController,
                  decoration: const InputDecoration(
                    labelText: 'Stock',
                    hintText: '0',
                    border: OutlineInputBorder(),
                    suffixText: 'units',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                ),
                const SizedBox(height: 16),

                CheckboxListTile(
                  title: const Text('Available'),
                  value: isAvailable,
                  onChanged: (value) =>
                      setDialogState(() => isAvailable = value ?? false),
                ),
              ],
            ),
          ),
          actions: [
            if (product == null && isBatchMode && batchCount > 0)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Batch complete! Added $batchCount product${batchCount > 1 ? 's' : ''}.'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                },
                child: const Text('Done'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSubmitting ? null : () async {
                if (isSubmitting) return;
                
                setDialogState(() {
                  isSubmitting = true;
                });

                if (nameController.text.trim().isEmpty) {
                  setDialogState(() {
                    isSubmitting = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a product name'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }

                if (priceController.text.trim().isEmpty || 
                    double.tryParse(priceController.text.trim()) == null ||
                    double.parse(priceController.text.trim()) <= 0) {
                  setDialogState(() {
                    isSubmitting = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid price (greater than 0)'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }

                final stockValue = int.tryParse(stockController.text.trim()) ?? 0;
                if (stockValue < 0) {
                  setDialogState(() {
                    isSubmitting = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Stock cannot be negative'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }

                try {
                  final price = double.parse(priceController.text.trim());

                  if (product == null) {
                    await ProductService.addProduct(
                      name: nameController.text.trim(),
                      category: selectedCategory,
                      price: price,
                      stock: stockValue,
                      isAvailable: isAvailable,
                      imageFile: imageFile,
                    );
                    
                    // Update batch count
                    setDialogState(() {
                      batchCount++;
                    });
                    
                    // Reload data to show new product
                    await _loadData();
                    
                    if (mounted) {
                      setDialogState(() {
                        isSubmitting = false;
                      });
                      
                      if (isBatchMode) {
                        // Batch mode: reset form but keep dialog open
                        setDialogState(() {
                          nameController.clear();
                          priceController.clear();
                          stockController.text = '0';
                          imageFile = null;
                          isAvailable = true;
                          // Keep selectedCategory for convenience
                        });
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Product added! Form cleared for next product.'),
                            backgroundColor: AppColors.success,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      } else {
                        // Single mode: close dialog
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Product added successfully'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    }
                  } else {
                    await ProductService.updateProduct(
                      productId: product!.id,
                      name: nameController.text.trim(),
                      category: selectedCategory,
                      price: price,
                      stock: stockValue,
                      isAvailable: isAvailable,
                      imageFile: imageFile,
                    );
                    if (mounted) {
                      setDialogState(() {
                        isSubmitting = false;
                      });
                      Navigator.pop(context);
                      await _loadData();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Product updated successfully'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  setDialogState(() {
                    isSubmitting = false;
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: ${e.toString()}'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              child: isSubmitting 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      product == null
                          ? (isBatchMode ? 'Add & Continue' : 'Add')
                          : 'Update',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _manageAddons(MerchantProduct product) async {
    List<ProductAddon> addons = await ProductService.getProductAddons(product.id);
    
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Manage Add-ons: ${product.name}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListView.builder(
                  shrinkWrap: true,
                  itemCount: addons.length,
                  itemBuilder: (context, index) {
                    final addon = addons[index];
                    return ListTile(
                      title: Text(addon.name),
                      subtitle: Text('₱${addon.price.toStringAsFixed(2)} - Stock: ${addon.stock}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () async {
                              await _showAddonDialog(
                                productId: product.id,
                                addon: addon,
                                onSave: () async {
                                  final updatedAddons = await ProductService.getProductAddons(product.id);
                                  setDialogState(() {
                                    addons = updatedAddons;
                                  });
                                },
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            color: AppColors.error,
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Add-on'),
                                  content: Text('Are you sure you want to delete "${addon.name}"?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: TextButton.styleFrom(foregroundColor: AppColors.error),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              
                              if (confirmed == true) {
                                try {
                                  await ProductService.deleteProductAddon(addon.id);
                                  final updatedAddons = await ProductService.getProductAddons(product.id);
                                  setDialogState(() {
                                    addons = updatedAddons;
                                  });
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Add-on deleted successfully'),
                                        backgroundColor: AppColors.success,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Failed to delete add-on: ${e.toString()}'),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
                if (addons.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No add-ons yet. Add one below.'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await _showAddonDialog(
                  productId: product.id,
                  onSave: () async {
                    final updatedAddons = await ProductService.getProductAddons(product.id);
                    setDialogState(() {
                      addons = updatedAddons;
                    });
                  },
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Add-on'),
            ),
          ],
        ),
      ),
    );
    
    await _loadData();
  }

  Future<void> _showAddonDialog({
    required String productId,
    ProductAddon? addon,
    required VoidCallback onSave,
  }) async {
    final nameController = TextEditingController(text: addon?.name ?? '');
    final priceController = TextEditingController(
      text: addon != null ? addon.price.toStringAsFixed(2) : '',
    );
    final stockController = TextEditingController(
      text: addon?.stock.toString() ?? '0',
    );
    bool isAvailable = addon?.isAvailable ?? true;
    bool isSubmitting = false; // Local flag for dialog

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(addon == null ? 'Add Add-on' : 'Edit Add-on'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Add-on Name (e.g., Ketchup, Gravy, Rice)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceController,
                  decoration: InputDecoration(
                    labelText: 'Price',
                    hintText: '0.00',
                    border: const OutlineInputBorder(),
                    prefixText: '₱',
                    prefixStyle: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: stockController,
                  decoration: const InputDecoration(
                    labelText: 'Stock',
                    hintText: '0',
                    border: OutlineInputBorder(),
                    suffixText: 'units',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Available'),
                  value: isAvailable,
                  onChanged: (value) =>
                      setDialogState(() => isAvailable = value ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSubmitting ? null : () async {
                if (isSubmitting) return;
                
                setDialogState(() {
                  isSubmitting = true;
                });

                if (nameController.text.trim().isEmpty) {
                  setDialogState(() {
                    isSubmitting = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter an add-on name'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }

                final priceValue = double.tryParse(priceController.text.trim());
                if (priceValue == null || priceValue < 0) {
                  setDialogState(() {
                    isSubmitting = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid price (0 or greater)'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }

                final stockValue = int.tryParse(stockController.text.trim()) ?? 0;
                if (stockValue < 0) {
                  setDialogState(() {
                    isSubmitting = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Stock cannot be negative'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }

                try {
                  if (addon == null) {
                    await ProductService.addProductAddon(
                      productId: productId,
                      name: nameController.text.trim(),
                      price: priceValue,
                      stock: stockValue,
                      isAvailable: isAvailable,
                    );
                  } else {
                    await ProductService.updateProductAddon(
                      addonId: addon.id,
                      name: nameController.text.trim(),
                      price: priceValue,
                      stock: stockValue,
                      isAvailable: isAvailable,
                    );
                  }
                  
                  if (mounted) {
                    setDialogState(() {
                      isSubmitting = false;
                    });
                    Navigator.pop(context);
                    onSave();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(addon == null
                            ? 'Add-on added successfully'
                            : 'Add-on updated successfully'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                } catch (e) {
                  setDialogState(() {
                    isSubmitting = false;
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: ${e.toString()}'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(addon == null ? 'Add' : 'Update'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.restaurant_menu_outlined,
                          size: 64, color: AppColors.textSecondary),
                      const SizedBox(height: 16),
                      const Text('No products yet'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _addProduct,
                        child: const Text('Add Product'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _products.length,
                  itemBuilder: (context, index) {
                    final product = _products[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: product.imageUrl != null
                            ? Image.network(
                                product.imageUrl!,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                              )
                            : const Icon(Icons.image_outlined, size: 50),
                        title: Text(product.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('₱${product.price.toStringAsFixed(2)}'),
                            Text(
                              'Stock: ${product.stock}',
                              style: TextStyle(
                                color: product.stock > 0
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                            ),
                            if (product.addons.isNotEmpty)
                              Text(
                                'Add-ons: ${product.addons.length}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.add_box_outlined),
                              tooltip: 'Manage Add-ons',
                              onPressed: () => _manageAddons(product),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editProduct(product),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              color: AppColors.error,
                              onPressed: () => _deleteProduct(product.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addProduct,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_outlined),
      ),
    );
  }
}
