import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/colors.dart';
import '../../models/order.dart';
import '../../models/payment.dart';
import '../../services/order_service.dart';
import '../../services/payment_service.dart';
import '../../services/rider_service.dart';
import '../../services/supabase_service.dart';
import '../../services/merchant_service.dart';
import '../../services/rider_wallet_service.dart';
import '../../services/merchant_rider_payment_service.dart';

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
  Map<String, Map<String, dynamic>> _customerInfo = {};
  Map<String, Map<String, dynamic>> _riderInfo = {};
  Map<String, bool> _hasMerchantRiderPayment = {};
  String? _currentMerchantId;
  late TabController _tabController;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {

      if (_tabController.indexIsChanging || _tabController.index != _tabController.previousIndex) {
        setState(() {});

        if (_tabController.index == 1 && _orders.isNotEmpty) {
          _reloadPaymentReceipts();
        }
      }
    });
    _loadMerchant();
    _loadOrders();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {

    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _paymentReceiptsSubscription?.cancel();
    _paymentReceiptsSubscription = null;

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
  StreamSubscription<List<Map<String, dynamic>>>? _paymentReceiptsSubscription;

  void _setupRealtimeSubscription() {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return;

    MerchantService.getMerchantByUserId(userId).then((merchant) {
      if (merchant != null && mounted) {

        _realtimeSubscription?.cancel();
        _realtimeSubscription = null;
        _paymentReceiptsSubscription?.cancel();
        _paymentReceiptsSubscription = null;

        _realtimeSubscription = SupabaseService.client
            .from('deliveries')
            .stream(primaryKey: ['id'])
            .eq('merchant_id', merchant.id)
            .listen((data) {
          if (mounted) {
            _loadOrders();
          }
        });


        _paymentReceiptsSubscription = SupabaseService.client
            .from('payments')
            .stream(primaryKey: ['id'])
            .listen((data) {
          if (mounted) {
            _reloadPaymentReceipts();
          }
        });
      }
    });
  }

  Future<void> _reloadPaymentReceipts() async {
    if (!mounted || _orders.isEmpty) {
      return;
    }

    try {
      final deliveryIds = _orders.map((o) => o.id).toList();
      final receiptsMap = await PaymentService.getPaymentReceipts(deliveryIds);

      if (mounted) {
        setState(() {
          _paymentReceipts = receiptsMap;
        });
      }
    } catch (e) {
      // Error reloading payment receipts
    }
  }

  Future<void> _loadOrders() async {
    if (!mounted) return;

    setState(() => _isLoading = true);
    try {
      final orders = await OrderService.getMerchantOrders();

      if (!mounted) return;

      final Set<String> riderIdsToLoad = {};
      for (var order in orders) {
        if (order.riderId != null && !_riderInfo.containsKey(order.riderId)) {
          riderIdsToLoad.add(order.riderId!);
        }
      }

      if (riderIdsToLoad.isNotEmpty) {
        final riderFutures = riderIdsToLoad.map((riderId) => _loadRiderInfo(riderId));
        await Future.wait(riderFutures);
      }

      final Map<String, List<DeliveryItem>> itemsMap = {};

      final deliveryIds = orders.map((o) => o.id).toList();
      final receiptsMap = await PaymentService.getPaymentReceipts(deliveryIds);

      for (var order in orders) {
        if (!mounted) return;

        try {
          final items = await OrderService.getOrderItems(order.id);
          itemsMap[order.id] = items;
        } catch (e) {

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

      final order = _orders.firstWhere((o) => o.id == orderId);

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

  List<Delivery> _getFilteredOrders() {
    switch (_tabController.index) {
      case 0:
        return _orders
            .where((o) => 
                o.status == DeliveryStatus.pending && 
                o.riderId == null)
            .toList();
      case 1:

        final filtered = _orders
            .where((o) => 
                o.status == DeliveryStatus.waitingForPayment && 
                o.riderId != null)
            .toList();

        for (var o in _orders) {
          final matches = o.status == DeliveryStatus.waitingForPayment && o.riderId != null;
          if (matches || o.status.value == 'accepted') {
          }
        }

        return filtered;
      case 2:
        return _orders
            .where((o) =>
                o.status == DeliveryStatus.paymentReceived ||
                o.status == DeliveryStatus.prepared ||
                o.status == DeliveryStatus.ready ||
                o.status == DeliveryStatus.pickedUp ||
                o.status == DeliveryStatus.inTransit)
            .toList();
      case 3:
        return _orders
            .where((o) => o.status == DeliveryStatus.completed)
            .toList();
      default:
        return [];
    }
  }

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

  Future<void> _findAndAssignRider(String orderId) async {
    if (_currentMerchantId == null) return;

    setState(() => _loadingStates[orderId] = true);

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

      final priorityRiders = await RiderService.getPriorityRiders(_currentMerchantId!);
      final availablePriorityRiders =
          priorityRiders.where((r) => r.isAvailable).toList();

      String? assignedRiderId;

      if (availablePriorityRiders.isNotEmpty) {

        await Future.delayed(const Duration(seconds: 30));

        for (var rider in availablePriorityRiders) {
          if (await RiderService.isRiderAvailable(rider.id)) {

            final currentOrder = _orders.firstWhere((o) => o.id == orderId);
            final shouldUpdateStatus = currentOrder.status == DeliveryStatus.pending;


            await RiderService.assignRiderToDelivery(
              deliveryId: orderId,
              riderId: rider.id,
              status: shouldUpdateStatus ? DeliveryStatus.accepted.value : null,
            );

            assignedRiderId = rider.id;
            break;
          }
        }
      }

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

            final currentOrder = _orders.firstWhere((o) => o.id == orderId);
            final shouldUpdateStatus = currentOrder.status == DeliveryStatus.pending;


            await RiderService.assignRiderToDelivery(
              deliveryId: orderId,
              riderId: rider.id,
              status: shouldUpdateStatus ? DeliveryStatus.accepted.value : null,
            );

            assignedRiderId = rider.id;
          }
        }
      }

      if (mounted) {

        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          try {
            Navigator.of(context, rootNavigator: true).pop();
          } catch (e) {

            if (mounted) {
              Navigator.pop(context);
            }
          }
        }
      }

      if (assignedRiderId != null) {




        await _loadRiderInfo(assignedRiderId);

        await Future.delayed(const Duration(milliseconds: 800));

        try {
      await _loadOrders();

      if (mounted) {
            try {
              final updatedOrder = _orders.firstWhere((o) => o.id == orderId);
              for (var o in _orders) {
                final isWaitingForPayment = o.status == DeliveryStatus.waitingForPayment;
                final hasRider = o.riderId != null;
              }

              final toApproveOrders = _orders
                  .where((o) => 
                      o.status == DeliveryStatus.waitingForPayment && 
                      o.riderId != null)
                  .toList();
            } catch (e) {
            }
          }
        } catch (e) {

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
      if (mounted) {

        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {

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

  Future<void> _silentReloadOrders() async {
    if (!mounted) return;

    try {
      final orders = await OrderService.getMerchantOrders();

      if (!mounted) return;

      final Set<String> riderIdsToLoad = {};
      for (var order in orders) {
        if (order.riderId != null && !_riderInfo.containsKey(order.riderId)) {
          riderIdsToLoad.add(order.riderId!);
        }
      }

      if (riderIdsToLoad.isNotEmpty) {
        final riderFutures = riderIdsToLoad.map((riderId) => _loadRiderInfo(riderId));
        await Future.wait(riderFutures);
      }


      if (mounted) {
        setState(() {
          _orders = orders;
        });

      }
    } catch (e) {


    }
  }

  Future<void> _requestPayment(String orderId) async {
    setState(() => _loadingStates[orderId] = true);

    try {

      await OrderService.requestPayment(orderId);

      try {
        await _silentReloadOrders();
      } catch (e) {
        // Error in silent reload
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

  Future<void> _approvePayment(String orderId) async {
    setState(() => _loadingStates[orderId] = true);

    try {
      final receipt = _paymentReceipts[orderId];
      if (receipt == null) {
        throw Exception('No payment receipt found');
      }

      final order = _orders.firstWhere((o) => o.id == orderId);

      await PaymentService.verifyPaymentReceipt(receipt.id, true);

      await OrderService.confirmPaymentReceived(orderId);

      try {
        if (order.customerId != null) {
          await SupabaseService.client.from('notifications').insert({
            'customer_id': order.customerId,
            'delivery_id': orderId,
            'type': 'payment_approved',
            'title': 'Payment Approved',
            'message': 'Your payment has been approved. Your order is now being prepared.',
            'read': false,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      } catch (e) {
      }

      try {
        if (order.riderId != null) {
          await SupabaseService.client.from('notifications').insert({
            'rider_id': order.riderId,
            'delivery_id': orderId,
            'type': 'payment_approved',
            'title': 'Payment Approved - Ready for Pickup',
            'message': 'Payment has been approved. Please proceed to merchant location for pickup.',
            'read': false,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      } catch (e) {
      }

      try {
        await _silentReloadOrders();
      } catch (e) {
        // Error in silent reload
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment approved. Notifications sent to buyer and rider. Order moved to "To Out" tab.'),
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

  Widget _buildDeliveryStatusIndicator(Delivery order) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (order.status) {
      case DeliveryStatus.prepared:
        statusColor = AppColors.primary;
        statusIcon = Icons.inventory_2;
        statusText = 'Order Prepared';
        break;
      case DeliveryStatus.ready:
        statusColor = AppColors.success;
        statusIcon = Icons.notifications_active;
        statusText = 'Rider Notified - Waiting for Pickup';
        break;
      case DeliveryStatus.pickedUp:
        statusColor = Colors.orange;
        statusIcon = Icons.check_circle_outline;
        statusText = 'Picked Up - In Transit';
        break;
      case DeliveryStatus.inTransit:
        statusColor = Colors.blue;
        statusIcon = Icons.local_shipping;
        statusText = 'In Transit to Customer';
        break;
      case DeliveryStatus.completed:
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle;
        statusText = 'Delivery Completed';
        break;
      default:
        statusColor = AppColors.textSecondary;
        statusIcon = Icons.info_outline;
        statusText = 'Processing';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor, width: 1),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _notifyRiderReadyForPickup(String orderId) async {
    setState(() => _loadingStates[orderId] = true);

    try {
      final order = _orders.firstWhere((o) => o.id == orderId);
      
      if (order.riderId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No rider assigned to this order'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      await OrderService.updateOrderStatus(orderId, DeliveryStatus.ready);

      try {
        await SupabaseService.client.from('notifications').insert({
          'rider_id': order.riderId,
          'delivery_id': orderId,
          'type': 'order_ready',
          'title': 'Order Ready for Pickup',
          'message': 'An order is ready for pickup. Please proceed to the merchant location.',
          'read': false,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
    }

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

  Future<void> _checkMerchantRiderPayment(String orderId) async {
    if (_hasMerchantRiderPayment.containsKey(orderId)) {
      return;
    }

    try {
      final hasPayment = await MerchantRiderPaymentService.hasMerchantRiderPayment(orderId);
      if (mounted) {
        setState(() {
          _hasMerchantRiderPayment[orderId] = hasPayment;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasMerchantRiderPayment[orderId] = false;
        });
      }
    }
  }

  Future<void> _showPayToRiderModal(Delivery order) async {
    final deliveryFee = order.deliveryFee ?? 0.0;
    if (deliveryFee == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery fee is not available'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (order.riderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No rider assigned to this order'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_currentMerchantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Merchant information not available'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final gcashNumberController = TextEditingController();
    final referenceNumberController = TextEditingController();
    final senderNameController = TextEditingController();
    File? paymentPhoto;
    bool isLoading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Pay to Rider'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Delivery Fee:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '₱${deliveryFee.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: gcashNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Rider GCash/E-wallet Number *',
                      hintText: '09XXXXXXXXX',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter rider GCash number';
                      }
                      if (value.trim().length < 10 || value.trim().length > 11) {
                        return 'Please enter a valid phone number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: referenceNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Reference Number *',
                      hintText: 'Transaction reference number',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter reference number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: senderNameController,
                    decoration: const InputDecoration(
                      labelText: 'Sender Name *',
                      hintText: 'Name of sender',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter sender name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Payment Proof Photo *',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
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
                                onTap: () => Navigator.pop(context, ImageSource.camera),
                              ),
                              ListTile(
                                leading: const Icon(Icons.photo_library_outlined),
                                title: const Text('Gallery'),
                                onTap: () => Navigator.pop(context, ImageSource.gallery),
                              ),
                            ],
                          ),
                        ),
                      );

                      if (source != null) {
                        final image = await _imagePicker.pickImage(source: source);
                        if (image != null) {
                          setDialogState(() {
                            paymentPhoto = File(image.path);
                          });
                        }
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.textSecondary),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: paymentPhoto == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.add_photo_alternate, size: 48, color: AppColors.textSecondary),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap to upload photo',
                                  style: TextStyle(color: AppColors.textSecondary),
                                ),
                              ],
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(paymentPhoto!, fit: BoxFit.cover),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) {
                        return;
                      }

                      if (paymentPhoto == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please upload payment proof photo'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isLoading = true);

                      try {
                        await MerchantRiderPaymentService.submitMerchantToRiderPayment(
                          deliveryId: order.id,
                          merchantId: _currentMerchantId!,
                          riderId: order.riderId!,
                          amount: deliveryFee,
                          riderGcashNumber: gcashNumberController.text.trim(),
                          referenceNumber: referenceNumberController.text.trim(),
                          senderName: senderNameController.text.trim(),
                          paymentPhoto: paymentPhoto!,
                        );

                        if (mounted) {
                          setState(() {
                            _hasMerchantRiderPayment[order.id] = true;
                          });

                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Payment submitted. Rider will be notified to confirm.'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          setDialogState(() => isLoading = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to submit payment: ${e.toString()}'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit Payment'),
            ),
          ],
        ),
      ),
    );
  }

  void _showOrderDetails(Delivery order) async {

    if (order.customerId != null) {
      await _loadCustomerInfo(order.customerId!);
    }

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

              if (order.pickupPhotoUrl != null || order.dropoffPhotoUrl != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'Rider Photos:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (order.pickupPhotoUrl != null)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pickup Photo',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: () => _showImageFullScreen(
                                order.pickupPhotoUrl!,
                                'Pickup Photo',
                              ),
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 2,
                                  ),
                                ),
                                child: ClipOval(
                                  child: Image.network(
                                    order.pickupPhotoUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Icon(
                                        Icons.error_outline,
                                        color: Colors.grey,
                                      );
                                    },
                                    loadingBuilder: (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return const Center(
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      );
            },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (order.pickupPhotoUrl != null && order.dropoffPhotoUrl != null)
                      const SizedBox(width: 16),
                    if (order.dropoffPhotoUrl != null)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Dropoff Photo',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
              ),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: () => _showImageFullScreen(
                                order.dropoffPhotoUrl!,
                                'Dropoff Photo',
                              ),
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 2,
                                  ),
                                ),
                                child: ClipOval(
                                  child: Image.network(
                                    order.dropoffPhotoUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Icon(
                                        Icons.error_outline,
                                        color: Colors.grey,
                                      );
                                    },
                                    loadingBuilder: (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return const Center(
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      );
                                    },
                                  ),
                                ),
                              ),
              ),
            ],
                        ),
          ),
        ],
      ),
              ],
              if (order.deliveryFee != null)
                _buildDetailRow('Delivery Fee', '₱${order.deliveryFee!.toStringAsFixed(2)}'),
              if (order.riderId != null) ...[
                _buildDetailRow('Rider Assigned', _getRiderName(order.riderId)),

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

  void _showImageFullScreen(String imageUrl, String title) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [

            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                  child: Column(
                        mainAxisSize: MainAxisSize.min,
                    children: [
                          Icon(Icons.error_outline, size: 64, color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'Failed to load image',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    );
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    );
                  },
                ),
              ),
            ),

            Positioned(
              top: 40,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  shape: const CircleBorder(),
                ),
              ),
            ),

            Positioned(
              top: 40,
              right: 80,
              child: IconButton(
                icon: const Icon(Icons.download, color: Colors.white, size: 28),
                onPressed: () {
                  Navigator.pop(context);
                  _downloadImage(imageUrl);
                },
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  shape: const CircleBorder(),
                ),
                tooltip: 'Download image',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentImageFullScreen(String imageUrl) {
    _showImageFullScreen(imageUrl, 'Payment Receipt');
  }

  Future<void> _downloadImage(String imageUrl) async {
    try {


      final uri = Uri.parse(imageUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Opening image in browser. You can download it from there.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        throw Exception('Could not launch URL');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download image: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

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
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        _showPaymentImageFullScreen(receipt.screenshotUrl!);
                      },
                      child: Container(
                        width: 80,
                        height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary, width: 2),
                          ),
                        child: ClipOval(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          TextButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _showPaymentImageFullScreen(receipt.screenshotUrl!);
                            },
                            icon: const Icon(Icons.zoom_in),
                            label: const Text('View Full Image'),
                          ),
                          TextButton.icon(
                            onPressed: () => _downloadImage(receipt.screenshotUrl!),
                            icon: const Icon(Icons.download),
                            label: const Text('Download'),
                              ),
                    ],
                  ),
                    ),
                  ],
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

  String _getCustomerName(Delivery order) {
    if (order.customerId == null) return 'Unknown';

    final info = _customerInfo[order.customerId];
    if (info != null && info['full_name'] != null) {
      return info['full_name'] as String;
    }

    return order.customerId!.substring(0, order.customerId!.length > 10 ? 10 : order.customerId!.length);
  }

  Future<void> _loadRiderInfo(String? riderId) async {
    if (riderId == null || riderId.isEmpty || _riderInfo.containsKey(riderId)) {
      return;
    }

    try {

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
    }
  }

  String _getRiderName(String? riderId) {
    if (riderId == null || riderId.isEmpty) return 'Not assigned';

    final info = _riderInfo[riderId];
    if (info != null && info['full_name'] != null) {
      return info['full_name'] as String;
    }

    return 'Loading...';
  }

  Widget _buildPendingOrderCard(Delivery order) {
    final total = _calculateOrderTotal(order.id);

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

  Widget _buildToApproveOrderCard(Delivery order) {
    final receipt = _paymentReceipts[order.id];
    final total = _calculateOrderTotal(order.id);
    final customerName = _getCustomerName(order);
    final riderName = order.riderId != null ? _getRiderName(order.riderId) : 'Not assigned';


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
                                  const SizedBox(height: 12),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
                          children: [

                if (receipt.screenshotUrl != null)
                            Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () => _showPaymentImageFullScreen(receipt.screenshotUrl!),
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.network(
                            receipt.screenshotUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(Icons.error_outline, size: 24, color: AppColors.error),
                              );
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.shade200,
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 24),
                    ),
                  ),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow('Reference', receipt.referenceNumber),
                      _buildDetailRow('Sender', receipt.payerName),
                      _buildDetailRow('Amount', '₱${receipt.amount.toStringAsFixed(2)}'),
                    ],
                  ),
                ),
              ],
            ),
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

              Builder(
                builder: (context) {

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _loadRiderInfo(order.riderId);
                  });
                  return const SizedBox.shrink();
                    },
              ),
            ],

            const SizedBox(height: 12),
            Center(
              child: _buildDeliveryStatusIndicator(order),
            ),
            if (order.pickupPhotoUrl != null || order.dropoffPhotoUrl != null) ...[
              const SizedBox(height: 16),
                                    const Text(
                'Rider Photos:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                  fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
              Row(
                children: [
                  if (order.pickupPhotoUrl != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pickup',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => _showImageFullScreen(
                              order.pickupPhotoUrl!,
                              'Pickup Photo',
                            ),
                            child: Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                              ),
                              child: ClipOval(
                                child: Image.network(
                                  order.pickupPhotoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.error_outline,
                                      color: Colors.grey,
                                    );
                                  },
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const Center(
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    );
                                  },
                                ),
                              ),
                              ),
                            ),
                          ],
                        ),
                    ),
                  if (order.pickupPhotoUrl != null && order.dropoffPhotoUrl != null)
                    const SizedBox(width: 16),
                  if (order.dropoffPhotoUrl != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Dropoff',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => _showImageFullScreen(
                              order.dropoffPhotoUrl!,
                              'Dropoff Photo',
                            ),
                            child: Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                              ),
                              child: ClipOval(
                                child: Image.network(
                                  order.dropoffPhotoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.error_outline,
                                      color: Colors.grey,
                                    );
                                  },
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const Center(
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            if (order.status == DeliveryStatus.prepared || order.status == DeliveryStatus.ready)
              const SizedBox(height: 12),
            if (order.status == DeliveryStatus.prepared)
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
            if (order.deliveryFee != null && order.deliveryFee! > 0 && order.riderId != null) ...[
              Builder(
                builder: (context) {
                  if (!_hasMerchantRiderPayment.containsKey(order.id)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _checkMerchantRiderPayment(order.id);
                    });
                    return const SizedBox.shrink();
                  }
                  final hasPayment = _hasMerchantRiderPayment[order.id] ?? false;
                  
                  if (!hasPayment) {
                    return Column(
                      children: [
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _loadingStates[order.id] == true
                                ? null
                                : () => _showPayToRiderModal(order),
                            icon: _loadingStates[order.id] == true
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.payment),
                            label: Text('Pay to Rider - ₱${order.deliveryFee!.toStringAsFixed(2)}'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.success),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, color: AppColors.success, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Payment submitted. Waiting for rider confirmation.',
                                  style: TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                },
              ),
            ],
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

            if (order.pickupPhotoUrl != null || order.dropoffPhotoUrl != null) ...[
              const SizedBox(height: 16),
              const Text(
                'Rider Photos:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (order.pickupPhotoUrl != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pickup',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => _showImageFullScreen(
                              order.pickupPhotoUrl!,
                              'Pickup Photo',
                            ),
                            child: Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                              ),
                              child: ClipOval(
                                child: Image.network(
                                  order.pickupPhotoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.error_outline,
                                      color: Colors.grey,
                      );
                    },
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const Center(
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (order.pickupPhotoUrl != null && order.dropoffPhotoUrl != null)
                    const SizedBox(width: 16),
                  if (order.dropoffPhotoUrl != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Dropoff',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => _showImageFullScreen(
                              order.dropoffPhotoUrl!,
                              'Dropoff Photo',
                            ),
                            child: Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                              ),
                              child: ClipOval(
                                child: Image.network(
                                  order.dropoffPhotoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.error_outline,
                                      color: Colors.grey,
                                    );
                                  },
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const Center(
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
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

  @override
  Widget build(BuildContext context) {
    final filteredOrders = _getFilteredOrders();


    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Orders'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textPrimary,
          indicatorColor: AppColors.primary,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          isScrollable: false,
          tabAlignment: TabAlignment.fill,
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
              onRefresh: () async {
                await _loadOrders();

                if (_orders.isNotEmpty) {
                  await _reloadPaymentReceipts();
                }
              },
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

                        if (!_orderItems.containsKey(order.id)) {
                          _loadOrderDetails(order.id);
                        }

                        switch (_tabController.index) {
                          case 0:
                            return _buildPendingOrderCard(order);
                          case 1:
                            return _buildToApproveOrderCard(order);
                          case 2:
                            return _buildToOutOrderCard(order);
                          case 3:
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
