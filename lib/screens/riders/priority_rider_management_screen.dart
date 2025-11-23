import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/colors.dart';
import '../../models/rider.dart';
import '../../services/rider_service.dart';
import '../../services/merchant_service.dart';
import '../../services/supabase_service.dart';

class PriorityRiderManagementScreen extends StatefulWidget {
  const PriorityRiderManagementScreen({super.key});

  @override
  State<PriorityRiderManagementScreen> createState() =>
      _PriorityRiderManagementScreenState();
}

class _PriorityRiderManagementScreenState
    extends State<PriorityRiderManagementScreen> {
  List<Rider> _allRiders = [];
  List<Rider> _priorityRiders = [];
  Map<String, int> _priorityOrder = {};
  bool _isLoading = true;
  String? _merchantId;

  @override
  void initState() {
    super.initState();
    _loadMerchantAndRiders();
  }

  Future<void> _loadMerchantAndRiders() async {
    setState(() => _isLoading = true);

    try {
      final userId = SupabaseService.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final merchant = await MerchantService.getMerchantByUserId(userId);
      if (merchant == null) {
        throw Exception('Merchant not found');
      }

      _merchantId = merchant.id;

      // Load all riders (filtered by loading_station_id) and priority riders
      final allRiders = await RiderService.getAllRiders(
        loadingStationId: merchant.loadingStationId,
      );
      final priorityRiders = await RiderService.getPriorityRiders(_merchantId!);
      final priorityOrder =
          await RiderService.getPriorityRiderOrder(_merchantId!);

      // Filter priority riders to only include those that are in allRiders
      // (i.e., riders with the same loading_station_id)
      final validPriorityRiders = priorityRiders
          .where((pr) => allRiders.any((r) => r.id == pr.id))
          .toList();

      setState(() {
        _allRiders = allRiders;
        _priorityRiders = validPriorityRiders;
        _priorityOrder = priorityOrder;
        _isLoading = false;
      });

      // Debug: Log rider counts
      debugPrint('Loaded ${allRiders.length} total riders (filtered by loading_station_id)');
      debugPrint('Loaded ${priorityRiders.length} priority riders from DB');
      debugPrint('Filtered to ${validPriorityRiders.length} valid priority riders (with matching loading_station_id)');
      if (merchant.loadingStationId != null) {
        debugPrint('Merchant loading_station_id: ${merchant.loadingStationId}');
      } else {
        debugPrint('No loading_station_id set for merchant');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load riders: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _addPriorityRider(Rider rider) async {
    if (_merchantId == null) return;

    try {
      await RiderService.addPriorityRider(
        merchantId: _merchantId!,
        riderId: rider.id,
      );
      await _loadMerchantAndRiders();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${rider.fullName} added to priority list'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add rider: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _removePriorityRider(Rider rider) async {
    if (_merchantId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Priority Rider'),
        content: Text('Remove ${rider.fullName} from priority list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await RiderService.removePriorityRider(
        merchantId: _merchantId!,
        riderId: rider.id,
      );
      await _loadMerchantAndRiders();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${rider.fullName} removed from priority list'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove rider: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showAddRiderDialog() {
    // Check if there are any riders at all
    if (_allRiders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No riders found with the same loading station'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Get riders that are not in priority list
    final nonPriorityRiders = _allRiders
        .where((rider) => !_priorityRiders.any((pr) => pr.id == rider.id))
        .toList();

    if (nonPriorityRiders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All riders are already in priority list'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Priority Rider'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: nonPriorityRiders.length,
            itemBuilder: (context, index) {
              final rider = nonPriorityRiders[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Text(
                    rider.fullName[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(rider.fullName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (rider.phone != null) Text('Phone: ${rider.phone}'),
                    if (rider.vehicleType != null)
                      Text('Vehicle: ${rider.vehicleType}'),
                    Text(
                      rider.isAvailable ? 'Available' : 'Unavailable',
                      style: TextStyle(
                        color: rider.isAvailable
                            ? AppColors.success
                            : AppColors.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.add_circle),
                  color: AppColors.primary,
                  onPressed: () {
                    Navigator.pop(context);
                    _addPriorityRider(rider);
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Priority Riders'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddRiderDialog,
            tooltip: 'Add Priority Rider',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadMerchantAndRiders,
              child: _priorityRiders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.delivery_dining_outlined,
                            size: 64,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No priority riders',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Add riders to prioritize them for deliveries',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _showAddRiderDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Priority Rider'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // Info banner
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          color: AppColors.primary.withOpacity(0.1),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Priority riders are checked first for 30 seconds before assigning other riders.',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Priority riders list
                        Expanded(
                          child: ReorderableListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _priorityRiders.length,
                            onReorder: (oldIndex, newIndex) {
                              if (newIndex > oldIndex) {
                                newIndex -= 1;
                              }
                              setState(() {
                                final rider = _priorityRiders.removeAt(oldIndex);
                                _priorityRiders.insert(newIndex, rider);
                              });
                              _updatePriorityOrder();
                            },
                            itemBuilder: (context, index) {
                              final rider = _priorityRiders[index];
                              final priorityNumber = index + 1;
                              final isAvailable = rider.isAvailable;

                              return Card(
                                key: ValueKey(rider.id),
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  leading: Stack(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: AppColors.primary,
                                        child: Text(
                                          rider.fullName[0].toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      if (priorityNumber <= 3)
                                        Positioned(
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: const BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.star,
                                              size: 14,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  title: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '#$priorityNumber',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(rider.fullName)),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (rider.phone != null)
                                        Text('Phone: ${rider.phone}'),
                                      if (rider.vehicleType != null)
                                        Text('Vehicle: ${rider.vehicleType}'),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            isAvailable
                                                ? Icons.check_circle
                                                : Icons.cancel,
                                            size: 14,
                                            color: isAvailable
                                                ? AppColors.success
                                                : AppColors.error,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isAvailable
                                                ? 'Available'
                                                : 'Unavailable',
                                            style: TextStyle(
                                              color: isAvailable
                                                  ? AppColors.success
                                                  : AppColors.error,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    color: AppColors.error,
                                    onPressed: () => _removePriorityRider(rider),
                                  ),
                                  isThreeLine: true,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
              ),
      floatingActionButton: _priorityRiders.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _showAddRiderDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Rider'),
              backgroundColor: AppColors.primary,
            )
          : null,
    );
  }

  Future<void> _updatePriorityOrder() async {
    if (_merchantId == null) return;

    try {
      final riderIds = _priorityRiders.map((r) => r.id).toList();
      await RiderService.updatePriorityOrder(
        merchantId: _merchantId!,
        riderIds: riderIds,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Priority order updated'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      // Reload to revert changes
      _loadMerchantAndRiders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update order: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

