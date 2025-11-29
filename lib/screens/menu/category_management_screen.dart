import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/colors.dart';
import '../../services/product_service.dart';

class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  final _categoryController = TextEditingController();
  List<String> _categories = [];
  bool _isLoading = true;
  String? _editingCategory;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    try {
      final categories = await ProductService.getCategories();
      setState(() {
        _categories = categories;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load categories: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _addCategory() async {
    final category = _categoryController.text.trim();
    if (category.isEmpty) return;

    try {
      await ProductService.addCategory(category);
      _categoryController.clear();
      await _loadCategories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Category added successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add category: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _editCategory(String oldCategory, String newCategory) async {
    if (oldCategory.trim() == newCategory.trim()) {

      setState(() {
        _editingCategory = null;
        _categoryController.clear();
      });
      return;
    }

    try {
      await ProductService.updateCategory(oldCategory, newCategory);
      setState(() {
        _editingCategory = null;
        _categoryController.clear();
      });
      await _loadCategories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Category updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update category: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteCategory(String category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Are you sure you want to delete "$category"?'),
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
      await ProductService.deleteCategory(category);
      await _loadCategories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Category deleted successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete category: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Category Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_editingCategory != null)
            IconButton(
              icon: const Icon(Icons.close_outlined),
              onPressed: () => setState(() => _editingCategory = null),
            ),
        ],
      ),
      body: Column(
        children: [

          Container(
            color: _editingCategory != null 
                ? AppColors.primary.withOpacity(0.1)
                : Colors.transparent,
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (_editingCategory != null) ...[
                  Row(
                    children: [
                      Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Editing: $_editingCategory',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_outlined),
                        iconSize: 20,
                        onPressed: () {
                          setState(() {
                            _editingCategory = null;
                            _categoryController.clear();
                          });
                        },
                        tooltip: 'Cancel editing',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _categoryController,
                        autofocus: _editingCategory != null,
                    decoration: InputDecoration(
                          labelText: _editingCategory != null 
                              ? 'New Category Name' 
                              : 'Category Name',
                      border: const OutlineInputBorder(),
                          hintText: 'e.g., Beverages, Food, Desserts',
                          prefixIcon: const Icon(Icons.category_outlined),
                          suffixIcon: _categoryController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _categoryController.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                    ),
                        onChanged: (value) => setState(() {}),
                        textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _categoryController.text.trim().isEmpty
                          ? null
                          : () {
                              if (_editingCategory != null) {
                            _editCategory(
                              _editingCategory!,
                              _categoryController.text.trim(),
                            );
                              } else {
                                _addCategory();
                          }
                            },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                      icon: Icon(
                        _editingCategory != null ? Icons.check : Icons.add,
                      ),
                      label: Text(_editingCategory != null ? 'Save' : 'Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _categories.isEmpty
                    ? const Center(child: Text('No categories yet'))
                    : ListView.builder(
                        itemCount: _categories.length,
                        itemBuilder: (context, index) {
                          final category = _categories[index];
                          return ListTile(
                            title: Text(category),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () {
                                    setState(() {
                                      _editingCategory = category;
                                      _categoryController.text = category;
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  color: AppColors.error,
                                  onPressed: () => _deleteCategory(category),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
