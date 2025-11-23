import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/colors.dart';
import '../../models/order.dart';
import '../../models/payment.dart';
import '../../services/order_service.dart';
import '../../services/payment_service.dart';
import '../../services/rider_service.dart';
import '../../services/supabase_service.dart';
import '../../services/merchant_service.dart';

class OrderManagementScreen extends StatefulWidget {
  const OrderManagementScreen({super.key});

  @override
  State<OrderManagementScreen> createState() => _OrderManagementScreenState();
}

class _OrderManagementScreenState extends State<OrderManagementScreen>
    with SingleTickerProviderStateMixin {
  List<Delivery> _orders = [];
  bool _isLoading = true;
  Map<String, List<DeliveryItem>> _orderItems = {};
  Map<String, PaymentReceipt?> _paymentReceipts = {};
  Map<String, bool> _loadingStates = {};
  Map<String, Map<String, dynamic>> _customerInfo = {}; // Cache customer info by customer_id
  Map<String, Map<String, dynamic>> _riderInfo = {}; // Cache rider info by rider_id
  String? _currentMerchantId;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      // Force rebuild when tab changes
      if (_tabController.indexIsChanging || _tabController.index != _tabController.previousIndex) {
        setState(() {
          debugPrint('Tab changed to index: ${_tabController.index}');
        });
      }
    });
    _loadMerchant();
    _loadOrders();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    // Cancel realtime subscription
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMerchant() async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null || !mounted) return;

    final merchant = await MerchantService.getMerchantByUserId(userId);
    if (merchant != null && mounted) {
      setState(() {
        _currentMerchantId = merchant.id;
      });
    }
  }

  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSubscription;

  void _setupRealtimeSubscription() {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return;

    MerchantService.getMerchantByUserId(userId).then((merchant) {
      if (merchant != null && mounted) {
        // Cancel existing subscription if any
        _realtimeSubscription?.cancel();
        _realtimeSubscription = null;

        // Set up new subscription
        _realtimeSubscription = SupabaseService.client
            .from('deliveries')
            .stream(primaryKey: ['id'])
            .eq('merchant_id', merchant.id)
            .listen((data) {
          if (mounted) {
            _loadOrders();
          }
        });
      }
    });
  }

  Future<void> _loadOrders() async {
    if (!mounted) return;
    
    setState(() => _isLoading = true);
    try {
      final orders = await OrderService.getMerchantOrders();

      if (!mounted) return;

      // Collect unique rider IDs to load in batch
      final Set<String> riderIdsToLoad = {};
      for (var order in orders) {
        if (order.riderId != null && !_riderInfo.containsKey(order.riderId)) {
          riderIdsToLoad.add(order.riderId!);
        }
      }

      // Load rider info in parallel
      if (riderIdsToLoad.isNotEmpty) {
        final riderFutures = riderIdsToLoad.map((riderId) => _loadRiderInfo(riderId));
        await Future.wait(riderFutures);
      }

      // Load order items and payment receipts for each order
      final Map<String, List<DeliveryItem>> itemsMap = {};
      final Map<String, PaymentReceipt?> receiptsMap = {};

      for (var order in orders) {
        if (!mounted) return;
        
        try {
          final items = await OrderService.getOrderItems(order.id);
          itemsMap[order.id] = items;

          final receipt = await PaymentService.getPaymentReceipt(order.id);
          receiptsMap[order.id] = receipt;
        } catch (e) {
          // Continue loading other orders even if one fails
          debugPrint('Error loading details for order ${order.id}: $e');
        }
      }

      if (!mounted) return;

      setState(() {
        _orders = orders;
        _orderItems = itemsMap;
        _paymentReceipts = receiptsMap;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load orders: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _loadOrderDetails(String orderId) async {
    try {
      final items = await OrderService.getOrderItems(orderId);
      final receipt = await PaymentService.getPaymentReceipt(orderId);

      // Find the order to get rider ID
      final order = _orders.firstWhere((o) => o.id == orderId);
      
      // Load rider info if rider is assigned
      if (order.riderId != null) {
        await _loadRiderInfo(order.riderId);
      }

      if (mounted) {
        setState(() {
          _orderItems[orderId] = items;
          _paymentReceipts[orderId] = receipt;
        });
      }
    } catch (e) {
      debugPrint('Error loading order details for $orderId: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load order items: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // Get orders filtered by tab
  List<Delivery> _getFilteredOrders() {
    switch (_tabController.index) {
      case 0: // Pending - only show orders without rider assigned
        return _orders
            .where((o) => 
                o.status == DeliveryStatus.pending && 
                o.riderId == null)
            .toList();
      case 1: // To Approve - orders waiting for payment (rider assigned, waiting for buyer payment)
        // Orders with 'accepted' status in DB are parsed as waitingForPayment
        final filtered = _orders
            .where((o) => 
                o.status == DeliveryStatus.waitingForPayment && 
                o.riderId != null)
            .toList();
        
        // Debug: log filter results
        debugPrint('To Approve tab filter - Total orders: ${_orders.length}, Filtered: ${filtered.length}');
        for (var o in _orders) {
          final matches = o.status == DeliveryStatus.waitingForPayment && o.riderId != null;
          if (matches || o.status.value == 'accepted') {
            debugPrint('  Order ${o.id.substring(0, 6)}: enum=${o.status}, value=${o.status.value}, rider=${o.riderId != null}, matches=$matches');
          }
        }
        
        return filtered;
      case 2: // To Out - orders with payment received, ready for merchant to prepare and notify rider
        return _orders
            .where((o) =>
                o.status == DeliveryStatus.paymentReceived ||
                o.status == DeliveryStatus.prepared ||
                o.status == DeliveryStatus.ready)
            .toList();
      case 3: // Completed
        return _orders
            .where((o) => o.status == DeliveryStatus.completed)
            .toList();
      default:
        return [];
    }
  }

  // Calculate order total
  double _calculateOrderTotal(String orderId) {
    final items = _orderItems[orderId] ?? [];
    double total = 0;
    for (var item in items) {
      total += item.subtotal;
    }
    final order = _orders.firstWhere((o) => o.id == orderId);
    if (order.deliveryFee != null) {
      total += order.deliveryFee!;
    }
    return total;
  }

  // Find and assign rider
  Future<void> _findAndAssignRider(String orderId) async {
    if (_currentMerchantId == null) return;

    setState(() => _loadingStates[orderId] = true);

    // Show loading dialog (don't await - we'll close it manually)
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Finding rider...'),
              SizedBox(height: 8),
              Text(
                'Checking priority riders first',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    
    try {

      // Try priority riders first
      final priorityRiders = await RiderService.getPriorityRiders(_currentMerchantId!);
      final availablePriorityRiders =
          priorityRiders.where((r) => r.isAvailable).toList();

      String? assignedRiderId;

      if (availablePriorityRiders.isNotEmpty) {
        // Wait 30 seconds for priority rider
        await Future.delayed(const Duration(seconds: 30));

        // Check again if priority rider is still available
        for (var rider in availablePriorityRiders) {
          if (await RiderService.isRiderAvailable(rider.id)) {
            // Get current order status to determine if we should update status
            final currentOrder = _orders.firstWhere((o) => o.id == orderId);
            final shouldUpdateStatus = currentOrder.status == DeliveryStatus.pending;
            
            debugPrint('Assigning rider $rider.id to order $orderId, current status: ${currentOrder.status.value}, should update: $shouldUpdateStatus');
            
            await RiderService.assignRiderToDelivery(
              deliveryId: orderId,
              riderId: rider.id,
              status: shouldUpdateStatus ? DeliveryStatus.accepted.value : null,
            );
            
            debugPrint('Rider assignment completed for order $orderId');
            assignedRiderId = rider.id;
            break;
          }
        }
      }

      // If no priority rider assigned, get other available riders
      if (assignedRiderId == null) {
        final allRiders = await RiderService.getAvailableRiders();
        final nonPriorityRiders = allRiders
            .where((r) =>
                !availablePriorityRiders.any((pr) => pr.id == r.id) &&
                r.isAvailable)
            .toList();

        if (nonPriorityRiders.isNotEmpty) {
          final rider = nonPriorityRiders.first;
          if (await RiderService.isRiderAvailable(rider.id)) {
            // Get current order status to determine if we should update status
            final currentOrder = _orders.firstWhere((o) => o.id == orderId);
            final shouldUpdateStatus = currentOrder.status == DeliveryStatus.pending;
            
            debugPrint('Assigning rider ${rider.id} to order $orderId, current status: ${currentOrder.status.value}, should update: $shouldUpdateStatus');
            
            await RiderService.assignRiderToDelivery(
              deliveryId: orderId,
              riderId: rider.id,
              status: shouldUpdateStatus ? DeliveryStatus.accepted.value : null,
            );
            
            debugPrint('Rider assignment completed for order $orderId');
            assignedRiderId = rider.id;
          }
        }
      }

      // Close loading dialog before doing other operations
      if (mounted) {
        // Use a small delay to ensure dialog is fully rendered before closing
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          try {
            Navigator.of(context, rootNavigator: true).pop();
          } catch (e) {
            debugPrint('Error closing dialog: $e');
            // Try alternative method
            if (mounted) {
              Navigator.pop(context);
            }
          }
        }
      }

      if (assignedRiderId != null) {
        // Status should already be updated by assignRiderToDelivery if order was pending
        // But let's verify and reload rider info
        
        debugPrint('Rider $assignedRiderId assigned to order $orderId');
        
        // Load rider info for the newly assigned rider
        await _loadRiderInfo(assignedRiderId);
        
        // Small delay to ensure database has fully updated
        await Future.delayed(const Duration(milliseconds: 800));
        
        // Use full reload to ensure we get the latest data
        // This is important to see the order in the correct tab
        try {
          await _loadOrders();
          
          // Verify the order is now in the correct status
          if (mounted) {
            try {
              final updatedOrder = _orders.firstWhere((o) => o.id == orderId);
              debugPrint('Order $orderId after reload - status enum: ${updatedOrder.status}, status value: ${updatedOrder.status.value}, rider_id: ${updatedOrder.riderId}');
              debugPrint('Is waitingForPayment enum? ${updatedOrder.status == DeliveryStatus.waitingForPayment}');
              debugPrint('Has rider? ${updatedOrder.riderId != null}');
              debugPrint('Should appear in To Approve tab: ${updatedOrder.status == DeliveryStatus.waitingForPayment && updatedOrder.riderId != null}');
              
              // Debug: show all orders and their statuses with enum values
              debugPrint('Total orders: ${_orders.length}');
              for (var o in _orders) {
                final isWaitingForPayment = o.status == DeliveryStatus.waitingForPayment;
                final hasRider = o.riderId != null;
                debugPrint('  Order ${o.id.substring(0, 6)}: enum=${o.status}, value=${o.status.value}, rider=${o.riderId != null ? o.riderId!.substring(0, 6) : "null"}, matches filter: ${isWaitingForPayment && hasRider}');
              }
              
              // Debug: show filtered orders for To Approve tab
              final toApproveOrders = _orders
                  .where((o) => 
                      o.status == DeliveryStatus.waitingForPayment && 
                      o.riderId != null)
                  .toList();
              debugPrint('To Approve tab filtered orders: ${toApproveOrders.length}');
              for (var o in toApproveOrders) {
                debugPrint('  To Approve order: ${o.id.substring(0, 6)}');
              }
            } catch (e) {
              debugPrint('Order $orderId not found after reload: $e');
              debugPrint('Available order IDs: ${_orders.map((o) => o.id.substring(0, 6)).join(", ")}');
            }
          }
        } catch (e) {
          debugPrint('Error in reload: $e');
          // Re-throw to show error to user
          rethrow;
        }

        if (mounted) {
          setState(() => _loadingStates[orderId] = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rider assigned successfully. Order moved to "To Approve" for payment request.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() => _loadingStates[orderId] = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No available riders at the moment'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error in _findAndAssignRider: $e');
      if (mounted) {
        // Make sure dialog is closed even on error
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {
          // Dialog might already be closed
        }
        setState(() => _loadingStates[orderId] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error assigning rider: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // Silently reload orders without showing full-screen loading
  Future<void> _silentReloadOrders() async {
    if (!mounted) return;
    
    try {
      final orders = await OrderService.getMerchantOrders();
      
      if (!mounted) return;

      // Collect unique rider IDs to load in batch
      final Set<String> riderIdsToLoad = {};
      for (var order in orders) {
        if (order.riderId != null && !_riderInfo.containsKey(order.riderId)) {
          riderIdsToLoad.add(order.riderId!);
        }
      }

      // Load rider info in parallel if needed
      if (riderIdsToLoad.isNotEmpty) {
        final riderFutures = riderIdsToLoad.map((riderId) => _loadRiderInfo(riderId));
        await Future.wait(riderFutures);
      }

      // Only update orders list, don't reload items/receipts (saves time and avoids black screen)
      if (mounted) {
        setState(() {
          _orders = orders;
        });
        
        // Debug: log order counts by status
        debugPrint('Orders reloaded - Total: ${orders.length}');
        debugPrint('  Pending: ${orders.where((o) => o.status == DeliveryStatus.pending && o.riderId == null).length}');
        debugPrint('  Accepted (To Approve): ${orders.where((o) => o.status == DeliveryStatus.waitingForPayment && o.riderId != null).length}');
        debugPrint('  Payment Received (To Out): ${orders.where((o) => o.status == DeliveryStatus.paymentReceived).length}');
      }
    } catch (e) {
      debugPrint('Error silently reloading orders: $e');
      // Don't call _loadOrders() here as it sets _isLoading = true and causes black screen
      // Just log the error and keep the existing orders
      // The realtime subscription will eventually update the orders
    }
  }

  // Request payment from buyer
  Future<void> _requestPayment(String orderId) async {
    setState(() => _loadingStates[orderId] = true);

    try {
      // Request payment - this notifies the buyer to send payment
      await OrderService.requestPayment(orderId);
      
      // Silently reload orders
      try {
        await _silentReloadOrders();
      } catch (e) {
        debugPrint('Error in silent reload: $e');
      }

      if (mounted) {
        setState(() => _loadingStates[orderId] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment request sent to buyer. Waiting for payment receipt.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingStates[orderId] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to request payment: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // Approve payment (rider should already be assigned at this point)
  Future<void> _approvePayment(String orderId) async {
    setState(() => _loadingStates[orderId] = true);

    try {
      final receipt = _paymentReceipts[orderId];
      if (receipt == null) {
        throw Exception('No payment receipt found');
      }

      // Verify payment receipt
      await PaymentService.verifyPaymentReceipt(receipt.id, true);

      // Update order status to payment received (moves to "To Out" tab)
      await OrderService.confirmPaymentReceived(orderId);

      // Silently reload orders without showing full-screen loading
      try {
        await _silentReloadOrders();
      } catch (e) {
        debugPrint('Error in silent reload: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment approved. Order moved to "To Out" tab.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to approve payment: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => _loadingStates[orderId] = false);
    }
  }

  // Notify rider that order is ready for pickup (To Out)
  Future<void> _notifyRiderReadyForPickup(String orderId) async {
    setState(() => _loadingStates[orderId] = true);

    try {
      // Update order status to ready
      await OrderService.updateOrderStatus(orderId, DeliveryStatus.ready);
      await _loadOrders();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rider notified that order is ready for pickup'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to notify rider: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => _loadingStates[orderId] = false);
    }
  }

  // View order details
  void _showOrderDetails(Delivery order) async {
    // Load customer info when viewing details
    if (order.customerId != null) {
      await _loadCustomerInfo(order.customerId!);
    }
    
    // Load order items if not already loaded
    if (!_orderItems.containsKey(order.id) || (_orderItems[order.id]?.isEmpty ?? true)) {
      await _loadOrderDetails(order.id);
    }
    
    if (!mounted) return;
    
    final items = _orderItems[order.id] ?? [];
    final total = _calculateOrderTotal(order.id);
    final customerInfo = order.customerId != null ? _customerInfo[order.customerId] : null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Order #${order.id.substring(0, 8)}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (order.customerId != null) ...[
                if (customerInfo != null && customerInfo['full_name'] != null)
                  _buildDetailRow('Customer Name', customerInfo['full_name'] as String),
                _buildDetailRow('Customer ID', order.customerId!),
              ],
              if (order.pickupAddress != null)
                _buildDetailRow('Pickup Address', order.pickupAddress!),
              if (order.dropoffAddress != null)
                _buildDetailRow('Delivery Address', order.dropoffAddress!),
              if (order.deliveryFee != null)
                _buildDetailRow('Delivery Fee', '₱${order.deliveryFee!.toStringAsFixed(2)}'),
              if (order.riderId != null) ...[
                _buildDetailRow('Rider Assigned', _getRiderName(order.riderId)),
                // Load rider info if not cached
                Builder(
                  builder: (context) {
                    // Trigger loading rider info
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _loadRiderInfo(order.riderId);
                    });
                    return const SizedBox.shrink();
                  },
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Order Items:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'No items found',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ),
                )
              else
                ...items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${item.product?.name ?? "Product ${item.productId}"} x${item.quantity}',
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ),
                            Text(
                              '₱${item.subtotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
              const SizedBox(height: 8),
              const Divider(),
              Text(
                'Total: ₱${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
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

  // View payment receipt details
  void _showPaymentDetails(PaymentReceipt receipt) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Payment Details'),
        content: SingleChildScrollView(
                  child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              _buildDetailRow('Reference Number', receipt.referenceNumber),
              _buildDetailRow('Payer Name', receipt.payerName),
              _buildDetailRow('Amount', '₱${receipt.amount.toStringAsFixed(2)}'),
              _buildDetailRow(
                'Status',
                receipt.status.value.toUpperCase(),
              ),
              if (receipt.screenshotUrl != null) ...[
                      const SizedBox(height: 16),
                const Text(
                  'Payment Screenshot:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (context) => Dialog(
                        child: Image.network(
                          receipt.screenshotUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Icon(Icons.error_outline, size: 48),
                            );
                          },
                        ),
                      ),
                    );
                  },
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        receipt.screenshotUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(Icons.error_outline, size: 32),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ],
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // Load customer info for an order (call this when viewing order details)
  Future<void> _loadCustomerInfo(String customerId) async {
    if (customerId.isEmpty || _customerInfo.containsKey(customerId)) {
      return;
    }

    final customerInfo = await OrderService.getCustomerInfo(customerId);
    if (customerInfo != null && mounted) {
      setState(() {
        _customerInfo[customerId] = customerInfo;
      });
    }
  }

  // Get customer name from cache or return customer ID
  String _getCustomerName(Delivery order) {
    if (order.customerId == null) return 'Unknown';
    
    final info = _customerInfo[order.customerId];
    if (info != null && info['full_name'] != null) {
      return info['full_name'] as String;
    }
    
    // Return first 10 chars of customer ID as placeholder
    return order.customerId!.substring(0, order.customerId!.length > 10 ? 10 : order.customerId!.length);
  }

  // Load rider info for an order (call this when viewing order details)
  Future<void> _loadRiderInfo(String? riderId) async {
    if (riderId == null || riderId.isEmpty || _riderInfo.containsKey(riderId)) {
      return;
    }

    try {
      // Fetch rider info from users table (since riders.id = users.id)
      final riderInfo = await SupabaseService.client
          .from('users')
          .select('id, full_name, phone, email')
          .eq('id', riderId)
          .maybeSingle();

      if (riderInfo != null && mounted) {
        setState(() {
          _riderInfo[riderId] = riderInfo;
        });
      }
    } catch (e) {
      debugPrint('Error loading rider info: $e');
    }
  }

  // Get rider name from cache or return placeholder
  String _getRiderName(String? riderId) {
    if (riderId == null || riderId.isEmpty) return 'Not assigned';
    
    final info = _riderInfo[riderId];
    if (info != null && info['full_name'] != null) {
      return info['full_name'] as String;
    }
    
    // Return placeholder while loading
    return 'Loading...';
  }

  // Build order card for Pending tab
  Widget _buildPendingOrderCard(Delivery order) {
    final total = _calculateOrderTotal(order.id);
    // Show customer ID (will load name when viewing details)
    final customerName = order.customerId?.substring(0, 10) ?? 'Unknown';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order No: ${order.id.substring(0, 6)}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  customerName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                const Text('Total:'),
                              Text(
                  '₱${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                              ),
                            ],
                          ),
            const SizedBox(height: 16),
            Row(
                          children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showOrderDetails(order),
                    icon: const Icon(Icons.visibility),
                    label: const Text('View'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loadingStates[order.id] == true
                        ? null
                        : () => _findAndAssignRider(order.id),
                    icon: _loadingStates[order.id] == true
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delivery_dining),
                    label: const Text('Find Rider'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Build order card for To Approve tab
  Widget _buildToApproveOrderCard(Delivery order) {
    final receipt = _paymentReceipts[order.id];
    final total = _calculateOrderTotal(order.id);
    final customerName = _getCustomerName(order);
    final riderName = order.riderId != null ? _getRiderName(order.riderId) : 'Not assigned';

    // If no receipt, show order with "Request Payment" button
    if (receipt == null) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Order No: ${order.id.substring(0, 6)}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    customerName,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total:'),
                  Text(
                    '₱${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              if (order.riderId != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.delivery_dining, size: 16, color: AppColors.success),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Rider: $riderName',
                        style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                // Load rider info if not cached
                Builder(
                  builder: (context) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _loadRiderInfo(order.riderId);
                    });
                    return const SizedBox.shrink();
                  },
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loadingStates[order.id] == true
                      ? null
                      : () => _requestPayment(order.id),
                  icon: _loadingStates[order.id] == true
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.payment),
                  label: const Text('Request Payment from Buyer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showOrderDetails(order),
                  icon: const Icon(Icons.visibility),
                  label: const Text('View Order Details'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order No: ${order.id.substring(0, 6)}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  customerName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
                                    ),
                                  const SizedBox(height: 16),
            // Payment receipt preview
            if (receipt.screenshotUrl != null)
              GestureDetector(
                onTap: () => _showPaymentDetails(receipt),
                child: Container(
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      receipt.screenshotUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(Icons.error_outline, size: 32),
                        );
                      },
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            _buildDetailRow('Reference', receipt.referenceNumber),
            _buildDetailRow('Sender', receipt.payerName),
            _buildDetailRow('Amount', '₱${receipt.amount.toStringAsFixed(2)}'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loadingStates[order.id] == true
                    ? null
                    : () => _approvePayment(order.id),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _loadingStates[order.id] == true
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Approve Payment'),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _showPaymentDetails(receipt),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('View Details'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build order card for To Out tab
  Widget _buildToOutOrderCard(Delivery order) {
    final total = _calculateOrderTotal(order.id);
    final customerName = _getCustomerName(order);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order No: ${order.id.substring(0, 6)}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  customerName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total:'),
                Text(
                  '₱${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                              ),
                            ),
                          ],
                        ),
            if (order.riderId != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.delivery_dining, size: 16, color: AppColors.success),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Rider: ${_getRiderName(order.riderId)}',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              // Load rider info if not cached
              Builder(
                builder: (context) {
                  // Trigger loading rider info
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _loadRiderInfo(order.riderId);
                  });
                  return const SizedBox.shrink();
                },
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loadingStates[order.id] == true
                    ? null
                    : () => _notifyRiderReadyForPickup(order.id),
                icon: _loadingStates[order.id] == true
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.notifications_active),
                label: const Text('Notify Rider - Ready for Pickup'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
                  ),
                ),
    );
  }

  // Build order card for Completed tab
  Widget _buildCompletedOrderCard(Delivery order) {
    final total = _calculateOrderTotal(order.id);
    final customerName = _getCustomerName(order);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
                Text(
                  'Order No: ${order.id.substring(0, 6)}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
          Text(
                  customerName,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total:'),
                Text(
                  '₱${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            if (order.completedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Completed: ${order.completedAt!.toString().substring(0, 16)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredOrders = _getFilteredOrders();
    
    // Debug: log build info
    debugPrint('Build - Tab index: ${_tabController.index}, Filtered orders: ${filteredOrders.length}, Total orders: ${_orders.length}');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          SupabaseService.currentUser?.email?.split('@').first ?? 'Orders',
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'To Approve'),
            Tab(text: 'To Out'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadOrders,
              child: filteredOrders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shopping_bag_outlined,
                            size: 64,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No orders in this section',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredOrders.length,
                      itemBuilder: (context, index) {
                        final order = filteredOrders[index];
                        debugPrint('Building order card for index $index: ${order.id.substring(0, 6)}, status: ${order.status}, tab: ${_tabController.index}');
                        
                        // Load order details if not already loaded
                        if (!_orderItems.containsKey(order.id)) {
                          _loadOrderDetails(order.id);
                        }

                        switch (_tabController.index) {
                          case 0: // Pending
                            return _buildPendingOrderCard(order);
                          case 1: // To Approve
                            debugPrint('Building To Approve card for order ${order.id.substring(0, 6)}');
                            return _buildToApproveOrderCard(order);
                          case 2: // To Out
                            return _buildToOutOrderCard(order);
                          case 3: // Completed
                            return _buildCompletedOrderCard(order);
                          default:
                            return const SizedBox.shrink();
                        }
                      },
                    ),
      ),
    );
  }
}
