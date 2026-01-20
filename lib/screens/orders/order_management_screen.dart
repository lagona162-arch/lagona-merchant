import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/colors.dart';
import '../../models/order.dart';
import '../../models/payment.dart';
import '../../models/rider.dart';
import '../../services/order_service.dart';
import '../../services/payment_service.dart';
import '../../services/rider_service.dart';
import '../../services/supabase_service.dart';
import '../../services/merchant_service.dart';
import '../../services/rider_wallet_service.dart';
import '../../services/merchant_rider_payment_service.dart';
import '../../core/timezone_helper.dart';

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
  Map<String, String?> _paymentMethods = {}; // Store payment_method for each order
  Map<String, String?> _paymentStatuses = {}; // Store payment status for each order
  Map<String, bool> _paymentRequested = {}; // Track if payment has been requested for each order
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
        
        // Refresh payment statuses when switching tabs
        if (_orders.isNotEmpty) {
          final ordersNeedingPaymentCheck = _orders.where((o) => 
            o.riderId != null && 
            o.deliveryFee != null && 
            o.deliveryFee! > 0
          ).toList();
          
          for (var order in ordersNeedingPaymentCheck) {
            _checkMerchantRiderPayment(order.id, forceRefresh: true);
          }
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
    _merchantRiderPaymentSubscription?.cancel();
    _merchantRiderPaymentSubscription = null;

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
  StreamSubscription<List<Map<String, dynamic>>>? _merchantRiderPaymentSubscription;

  void _setupRealtimeSubscription() {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return;

    MerchantService.getMerchantByUserId(userId).then((merchant) {
      if (merchant != null && mounted) {

        _realtimeSubscription?.cancel();
        _realtimeSubscription = null;
        _paymentReceiptsSubscription?.cancel();
        _paymentReceiptsSubscription = null;
        _merchantRiderPaymentSubscription?.cancel();
        _merchantRiderPaymentSubscription = null;

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

        // Subscribe to merchant_rider_payments changes
        _merchantRiderPaymentSubscription = SupabaseService.client
            .from('merchant_rider_payments')
            .stream(primaryKey: ['id'])
            .eq('merchant_id', merchant.id)
            .listen((data) {
          if (mounted && data.isNotEmpty) {
            debugPrint('Realtime update received for merchant_rider_payments: ${data.length} record(s)');
            // Refresh payment status for affected orders
            final deliveryIds = data
                .map((payment) => payment['delivery_id'] as String?)
                .whereType<String>()
                .toSet();
            
            for (var payment in data) {
              final deliveryId = payment['delivery_id'] as String?;
              final status = payment['status'] as String?;
              final method = payment['payment_method'] as String?;
              debugPrint('Payment update - delivery: $deliveryId, status: $status, method: $method');
            }
            
            for (var deliveryId in deliveryIds) {
              _checkMerchantRiderPayment(deliveryId, forceRefresh: true);
            }
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

      // Check payment status for orders with riders and delivery fees
      final ordersNeedingPaymentCheck = orders.where((o) => 
        o.riderId != null && 
        o.deliveryFee != null && 
        o.deliveryFee! > 0 &&
        !_hasMerchantRiderPayment.containsKey(o.id)
      ).toList();
      
      // Check payment status asynchronously (don't await to avoid blocking UI)
      for (var order in ordersNeedingPaymentCheck) {
        _checkMerchantRiderPayment(order.id);
      }

      // Initialize payment requested tracking from orders
      final paymentRequestedMap = <String, bool>{};
      for (var order in orders) {
        paymentRequestedMap[order.id] = order.paymentRequested;
      }

      setState(() {
        _orders = orders;
        _orderItems = itemsMap;
        _paymentReceipts = receiptsMap;
        _paymentRequested = paymentRequestedMap;
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
        // Show all waitingForPayment orders (confirmed orders) regardless of rider status
        // This ensures merchants can always see order details for active orders
        return _orders
            .where((o) => 
                o.status == DeliveryStatus.waitingForPayment)
            .toList();
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
      // Add item subtotal
      total += item.subtotal;
      // Add addon subtotals
      for (var addon in item.addons) {
        total += addon.subtotal;
      }
    }
    final order = _orders.firstWhere((o) => o.id == orderId);
    if (order.deliveryFee != null) {
      total += order.deliveryFee!;
    }
    return total;
  }

  Future<void> _findAndAssignRider(String orderId) async {
    if (_currentMerchantId == null) return;

    // Prevent multiple simultaneous calls for the same order
    if (_loadingStates[orderId] == true) {
      debugPrint('Find rider already in progress for order $orderId, ignoring duplicate call');
      return;
    }

    setState(() => _loadingStates[orderId] = true);

    // Get order details for location
    final order = _orders.firstWhere((o) => o.id == orderId);
    if (order.pickupLatitude == null || order.pickupLongitude == null) {
      if (mounted) {
        setState(() => _loadingStates[orderId] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order location not available'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    // Clean up any existing offers before starting a new search
    try {
      await RiderService.expireAllPendingOffers(orderId);
      // Small delay to ensure database has processed the expiration
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      debugPrint('Error expiring old offers before new search: $e');
      // Continue anyway - don't block the new search
    }

    // Initialize variables
    final startTime = DateTime.now();
    BuildContext? dialogContext;
    String currentPhase = 'Offering to priority riders...';
    int secondsElapsed = 0;
    int totalSeconds = 600; // 10 minutes
    bool isCancelled = false;
    bool isDialogClosed = false;
    Timer? progressTimer;
    ValueNotifier<String> phaseNotifier = ValueNotifier<String>('Offering to priority riders...');
    ValueNotifier<int> elapsedNotifier = ValueNotifier<int>(0);
    
    // Show dialog with progress updates
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: true, // Allow dismissing by tapping outside
        builder: (dialogCtx) {
          dialogContext = dialogCtx;
          
          // Start timer to update progress
          progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (isCancelled || !mounted) {
              timer.cancel();
              return;
            }
            final elapsed = DateTime.now().difference(startTime);
            elapsedNotifier.value = elapsed.inSeconds;
          });
          
          return PopScope(
            canPop: true,
            onPopInvoked: (didPop) {
              if (didPop) {
                // Dialog is being dismissed (by tapping outside or back button)
                isCancelled = true;
                progressTimer?.cancel();
                isDialogClosed = true;
                // Reset loading state immediately
                if (mounted) {
                  setState(() => _loadingStates[orderId] = false);
                }
              }
            },
            child: ValueListenableBuilder<String>(
            valueListenable: phaseNotifier,
            builder: (context, phase, _) {
              return ValueListenableBuilder<int>(
                valueListenable: elapsedNotifier,
                builder: (context, elapsed, _) {
                  return AlertDialog(
                    title: const Text('Finding Rider'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          phase,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Time elapsed: ${(elapsed ~/ 60).toString().padLeft(2, '0')}:${(elapsed % 60).toString().padLeft(2, '0')} / 10:00',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: elapsed / totalSeconds,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          elapsed < 60
                              ? 'Priority riders have exclusive access'
                              : 'All nearby riders can now accept',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          isCancelled = true;
                          progressTimer?.cancel();
                            // Reset loading state immediately
                            if (mounted) {
                              setState(() => _loadingStates[orderId] = false);
                            }
                            // Close dialog only if not already closed
                            if (mounted && dialogContext != null && !isDialogClosed) {
                              isDialogClosed = true;
                              Navigator.of(dialogContext!, rootNavigator: true).pop();
                          }
                        },
                        child: const Text('Cancel'),
                      ),
                    ],
                  );
                },
              );
            },
            ),
          );
        },
      );
    }

    try {
      String? assignedRiderId;
      const totalWindow = Duration(minutes: 10); // Total 10-minute window
      const priorityExclusiveWindow = Duration(minutes: 1); // First minute for priority only

      // Step 1: Send offers to priority riders (expires after 10 minutes total)
      List<Rider> priorityRiders = [];
      List<Rider> availablePriorityRiders = [];
      
      try {
        priorityRiders = await RiderService.getPriorityRiders(_currentMerchantId!);
        availablePriorityRiders =
          priorityRiders.where((r) => r.isAvailable).toList();
      } catch (e) {
        debugPrint('Error fetching priority riders: $e');
        // Continue with broadcast phase if priority riders fail
        priorityRiders = [];
        availablePriorityRiders = [];
      }

      if (availablePriorityRiders.isNotEmpty && !isCancelled) {
        // Send offers to all priority riders (expire after total 10-minute window)
        for (var rider in availablePriorityRiders) {
          if (isCancelled) break; // Stop if cancelled
          try {
            await RiderService.sendDeliveryOffer(
              deliveryId: orderId,
              riderId: rider.id,
              offerType: 'priority',
              expiresIn: totalWindow, // Expires after 10 minutes total
            );
          } catch (e) {
            debugPrint('Error sending offer to priority rider ${rider.id}: $e');
            // Continue with other riders even if one fails
          }
        }

        // Wait 1 minute (exclusive window for priority riders) and check for acceptances
        const checkInterval = Duration(seconds: 2);
        int checksRemaining = priorityExclusiveWindow.inSeconds ~/ checkInterval.inSeconds;
        
        while (checksRemaining > 0 && assignedRiderId == null && !isCancelled) {
          await Future.delayed(checkInterval);
          checksRemaining--;

          // Update dialog phase
          if (mounted && !isCancelled) {
            phaseNotifier.value = 'Waiting for priority riders... (${availablePriorityRiders.length} riders)';
          }

          // Check if any priority rider accepted
          for (var rider in availablePriorityRiders) {
            if (await RiderService.checkRiderAcceptedOffer(
              deliveryId: orderId,
              riderId: rider.id,
            )) {
            assignedRiderId = rider.id;
              break;
            }
          }
        }
      }

      // Step 2: After 1 minute, if no priority rider accepted, broadcast to ALL nearby riders
      if (assignedRiderId == null && !isCancelled) {
        // Update dialog to show broadcast phase
        if (mounted && !isCancelled) {
          phaseNotifier.value = 'Broadcasting to nearby riders...';
        }

        // Get ALL nearby riders within 5km (including priority riders - they can still accept)
        List<Rider> nearbyRiders = [];
        try {
          nearbyRiders = await RiderService.getRidersWithinRadius(
          latitude: order.pickupLatitude!,
          longitude: order.pickupLongitude!,
          radiusKm: 5.0,
          excludeRiderIds: null, // Don't exclude priority riders - they can still accept
        );
        } catch (e) {
          debugPrint('Error fetching nearby riders: $e');
          // Continue anyway - might still have priority riders
          nearbyRiders = [];
        }

        if (nearbyRiders.isNotEmpty) {
          // Calculate remaining time until total 10-minute window expires
          final elapsed = DateTime.now().difference(startTime);
          final remainingTime = totalWindow - elapsed;
          
          // Only send broadcast offers to riders who don't already have a priority offer
          final ridersToBroadcast = nearbyRiders.where((rider) {
            return !availablePriorityRiders.any((pr) => pr.id == rider.id);
          }).toList();

          debugPrint('Sending broadcast offers to ${ridersToBroadcast.length} riders');

          // Send broadcast offers to non-priority riders (expires at end of 10-minute window)
          for (var rider in ridersToBroadcast) {
            if (isCancelled) break; // Stop if cancelled
            try {
              await RiderService.sendDeliveryOffer(
                deliveryId: orderId,
                riderId: rider.id,
                offerType: 'broadcast',
                expiresIn: remainingTime, // Expires at end of 10-minute total window
              );
            } catch (e) {
              debugPrint('Error sending broadcast offer to rider ${rider.id}: $e');
              // Continue with other riders even if one fails
            }
          }

          // Wait and check for acceptances from ANY rider (priority or broadcast) until 10 minutes total
          const broadcastCheckInterval = Duration(seconds: 2);
          int broadcastChecksRemaining = remainingTime.inSeconds ~/ broadcastCheckInterval.inSeconds;

          while (broadcastChecksRemaining > 0 && assignedRiderId == null && !isCancelled) {
            await Future.delayed(broadcastCheckInterval);
            broadcastChecksRemaining--;

            // Update dialog phase
            if (mounted && !isCancelled) {
              phaseNotifier.value = 'Waiting for riders to accept... (${availablePriorityRiders.length} priority, ${ridersToBroadcast.length} nearby)';
            }

            // Check if ANY rider accepted (more efficient - single query)
            final acceptedRiderId = await RiderService.checkAnyRiderAccepted(orderId);
            if (acceptedRiderId != null) {
              assignedRiderId = acceptedRiderId;
              break;
            }

            // Check if we've exceeded the total 10-minute window
            final currentElapsed = DateTime.now().difference(startTime);
            if (currentElapsed >= totalWindow) {
              break;
            }
          }

          // Expire all remaining offers after 10-minute window
          await RiderService.expireOldOffers(orderId);
        } else {
          // No nearby riders found, but keep the dialog open and continue checking
          if (mounted && !isCancelled) {
            phaseNotifier.value = 'No nearby riders found. Waiting for priority riders...';
          }

          // Wait and check for acceptances from priority riders until 10 minutes total
          final elapsed = DateTime.now().difference(startTime);
          final remainingTime = totalWindow - elapsed;
          const broadcastCheckInterval = Duration(seconds: 2);
          int broadcastChecksRemaining = remainingTime.inSeconds ~/ broadcastCheckInterval.inSeconds;

          while (broadcastChecksRemaining > 0 && assignedRiderId == null && !isCancelled) {
            await Future.delayed(broadcastCheckInterval);
            broadcastChecksRemaining--;

            // Update dialog phase
            if (mounted && !isCancelled) {
              phaseNotifier.value = 'No nearby riders found. Waiting for priority riders...';
            }

            // Check if ANY rider accepted (more efficient - single query)
            final acceptedRiderId = await RiderService.checkAnyRiderAccepted(orderId);
            if (acceptedRiderId != null) {
              assignedRiderId = acceptedRiderId;
              break;
            }

            // Check if we've exceeded the total 10-minute window
            final currentElapsed = DateTime.now().difference(startTime);
            if (currentElapsed >= totalWindow) {
              break;
            }
          }

          // Expire all remaining offers after 10-minute window
          await RiderService.expireOldOffers(orderId);
        }
      }

      // Stop progress timer
      progressTimer?.cancel();

      // If cancelled, stop the process and clean up offers
      if (isCancelled) {
        // Clean up any offers that were sent before cancellation
        try {
          await RiderService.expireAllPendingOffers(orderId);
        } catch (e) {
          debugPrint('Error expiring offers on cancellation: $e');
          // Continue with cleanup even if this fails
        }
        
        // Dialog should already be closed by cancel button, but ensure it's closed
        if (mounted && dialogContext != null && !isDialogClosed) {
            try {
            isDialogClosed = true;
            Navigator.of(dialogContext!, rootNavigator: true).pop();
          } catch (e) {
            // Dialog already closed, ignore
          }
        }
        if (mounted) {
          setState(() => _loadingStates[orderId] = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Finding rider cancelled'),
              backgroundColor: AppColors.textSecondary,
            ),
          );
        }
        return;
      }

      // Close dialog if not already closed
      if (mounted && dialogContext != null && !isDialogClosed) {
        try {
          isDialogClosed = true;
          Navigator.of(dialogContext!, rootNavigator: true).pop();
        } catch (e) {
          if (mounted) {
            try {
              Navigator.pop(context);
            } catch (_) {
              // Dialog already closed, ignore
            }
          }
        }
      }

      // Step 3: Assign rider if one accepted
      if (assignedRiderId != null) {
        final currentOrder = _orders.firstWhere((o) => o.id == orderId);
        final shouldUpdateStatus = currentOrder.status == DeliveryStatus.pending;

        await RiderService.assignRiderToDelivery(
          deliveryId: orderId,
          riderId: assignedRiderId!,
          status: shouldUpdateStatus ? DeliveryStatus.accepted.value : null,
        );

        await _loadRiderInfo(assignedRiderId!);
        await Future.delayed(const Duration(milliseconds: 800));
        await _loadOrders();

        if (mounted) {
          setState(() => _loadingStates[orderId] = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rider accepted the offer! Order moved to "To Approve" for payment request.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() => _loadingStates[orderId] = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No riders accepted the offer. Please try again later.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      // Stop progress timer on error
      progressTimer?.cancel();
      
      // Clean up offers on error
      try {
        await RiderService.expireAllPendingOffers(orderId);
      } catch (cleanupError) {
        debugPrint('Error expiring offers on exception: $cleanupError');
      }
      
      if (mounted) {
        try {
          if (dialogContext != null && !isDialogClosed) {
            isDialogClosed = true;
            Navigator.of(dialogContext!, rootNavigator: true).pop();
          } else if (!isDialogClosed) {
            Navigator.pop(context);
            isDialogClosed = true;
          }
        } catch (_) {
          // Dialog already closed
        }
        setState(() => _loadingStates[orderId] = false);
        debugPrint('Error in _findAndAssignRider: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error finding rider: ${e.toString()}'),
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
    // Prevent multiple clicks
    if (_paymentRequested[orderId] == true) {
      return;
    }

    setState(() {
      _loadingStates[orderId] = true;
      _paymentRequested[orderId] = true; // Mark as requested immediately
    });

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
        setState(() {
          _loadingStates[orderId] = false;
          _paymentRequested[orderId] = false; // Reset on error so user can try again
        });
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
            'created_at': TimezoneHelper.nowUTC().toIso8601String(),
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
            'created_at': TimezoneHelper.nowUTC().toIso8601String(),
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

  Future<void> _checkMerchantRiderPayment(String orderId, {bool forceRefresh = false}) async {
    // Skip if already checked and not forcing refresh
    if (!forceRefresh && _hasMerchantRiderPayment.containsKey(orderId)) {
      return;
    }

    try {
      final payment = await MerchantRiderPaymentService.getMerchantRiderPayment(orderId);
      final hasPayment = payment != null;
      final paymentMethod = payment?['payment_method'] as String?;
      final paymentStatus = payment?['status'] as String?;

      if (mounted) {
        setState(() {
          _hasMerchantRiderPayment[orderId] = hasPayment;
          _paymentMethods[orderId] = paymentMethod;
          _paymentStatuses[orderId] = paymentStatus;
        });
      }
    } catch (e) {
      debugPrint('Error checking merchant rider payment for $orderId: $e');
      if (mounted) {
        setState(() {
          _hasMerchantRiderPayment[orderId] = false;
          _paymentMethods[orderId] = null;
          _paymentStatuses[orderId] = null;
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
    String selectedPaymentMethod = 'e_wallet'; // Default to e-wallet

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
                  const Text(
                    'Payment Method *',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  RadioListTile<String>(
                    title: const Text('E-wallet (GCash)'),
                    subtitle: const Text('Transfer via GCash or other e-wallet'),
                    value: 'e_wallet',
                    groupValue: selectedPaymentMethod,
                    onChanged: (value) {
                      setDialogState(() {
                        selectedPaymentMethod = value!;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    title: const Text('In-Person (Cash)'),
                    subtitle: const Text('Pay directly to the rider'),
                    value: 'in_person',
                    groupValue: selectedPaymentMethod,
                    onChanged: (value) {
                      setDialogState(() {
                        selectedPaymentMethod = value!;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 16),
                  // E-wallet fields (only show when e_wallet is selected)
                  if (selectedPaymentMethod == 'e_wallet') ...[
                    TextFormField(
                      controller: gcashNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Rider GCash/E-wallet Number *',
                        hintText: '09XXXXXXXXX',
                        border: OutlineInputBorder(),
                        helperText: '11 digits starting with 09',
                      ),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      validator: (value) {
                        if (selectedPaymentMethod == 'e_wallet') {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter rider GCash number';
                          }
                          final trimmed = value.trim();
                          if (trimmed.length != 11) {
                            return 'GCash number must be exactly 11 digits';
                          }
                          if (!trimmed.startsWith('09')) {
                            return 'GCash number must start with 09';
                          }
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
                        if (selectedPaymentMethod == 'e_wallet') {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter reference number';
                          }
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
                        if (selectedPaymentMethod == 'e_wallet') {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter sender name';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Payment Proof Photo (only show for e-wallet)
                  if (selectedPaymentMethod == 'e_wallet') ...[
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

                      // Payment photo is required for e-wallet, optional for in-person
                      if (selectedPaymentMethod == 'e_wallet' && paymentPhoto == null) {
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
                          paymentMethod: selectedPaymentMethod,
                          riderGcashNumber: selectedPaymentMethod == 'e_wallet'
                              ? gcashNumberController.text.trim()
                              : null,
                          referenceNumber: selectedPaymentMethod == 'e_wallet'
                              ? referenceNumberController.text.trim()
                              : null,
                          senderName: selectedPaymentMethod == 'e_wallet'
                              ? senderNameController.text.trim()
                              : null,
                          paymentPhoto: paymentPhoto,
                        );

                        if (mounted) {
                          Navigator.pop(context);
                          
                          // Force refresh payment status from database after submission
                          // This ensures the UI shows the updated payment record
                          await _checkMerchantRiderPayment(order.id, forceRefresh: true);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                selectedPaymentMethod == 'in_person'
                                    ? 'In-person payment offer sent. Rider will be notified to collect cash payment.'
                                    : 'Payment submitted. Rider will be notified to confirm.',
                              ),
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
                  : Text(
                      selectedPaymentMethod == 'in_person'
                          ? 'Offer In-Person Payment with Rider'
                          : 'Submit Payment',
                    ),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
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
                            if (item.addons.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              ...item.addons.map((addon) => Padding(
                                    padding: const EdgeInsets.only(left: 16, top: 4),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '  + ${addon.name} x${addon.quantity}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '₱${addon.subtotal.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )),
                            ],
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
                  onPressed: (_loadingStates[order.id] == true || _paymentRequested[order.id] == true)
                      ? null
                      : () => _requestPayment(order.id),
                  icon: _loadingStates[order.id] == true
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.payment),
                  label: Text(
                    _paymentRequested[order.id] == true
                        ? 'Payment Request Sent'
                        : 'Request Payment from Buyer'
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _paymentRequested[order.id] == true
                        ? AppColors.textSecondary
                        : AppColors.primary,
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
                  final paymentStatus = _paymentStatuses[order.id];
                  final isRejected = paymentStatus == 'rejected';
                  final isConfirmed = paymentStatus == 'confirmed';
                  
                  // Periodically refresh payment status if it's pending (to catch rider acceptance)
                  if (hasPayment && paymentStatus == 'pending_confirmation') {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      // Refresh after a delay to catch status changes
                      Future.delayed(const Duration(seconds: 3), () {
                        if (mounted) {
                          _checkMerchantRiderPayment(order.id, forceRefresh: true);
                        }
                      });
                    });
                  }
                  
                  // Step 1: Show "Notify Rider" button if order is not yet ready (status is prepared or earlier)
                  // Step 2: After rider is notified (status becomes ready), show "Pay to Rider" button
                  // Step 3: After payment is confirmed, show payment confirmation message
                  
                  final isOrderReady = order.status == DeliveryStatus.ready;
                  
                  // Step 1: Show "Notify Rider" button if order is not yet ready
                  if (!isOrderReady && order.status != DeliveryStatus.pickedUp && order.status != DeliveryStatus.inTransit) {
                    return Column(
                      children: [
                        const SizedBox(height: 8),
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
                    );
                  }
                  
                  // Step 2: Order is ready, show "Pay to Rider" button if payment is not confirmed
                  if (isOrderReady && (!hasPayment || isRejected || !isConfirmed)) {
                    return Column(
                      children: [
                        if (isRejected) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.error),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.cancel, color: AppColors.error, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Previous payment offer was declined. You can offer again.',
                                    style: TextStyle(
                                      color: AppColors.error,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                            label: Text(
                              isRejected 
                                  ? 'Re-offer Payment - ₱${order.deliveryFee!.toStringAsFixed(2)}'
                                  : 'Pay to Rider - ₱${order.deliveryFee!.toStringAsFixed(2)}'
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  
                  // Step 3: Payment is confirmed - show confirmation message
                  if (isOrderReady && isConfirmed) {
                    final paymentMethod = _paymentMethods[order.id];
                    final isInPerson = paymentMethod == 'in_person';
                    
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
                                  isInPerson
                                      ? 'Payment confirmed by rider. Order is ready for pickup.'
                                      : 'Payment confirmed by rider. Order is ready for pickup.',
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
                  
                  // Payment is pending confirmation - show status message
                  if (isOrderReady && hasPayment && !isConfirmed && !isRejected) {
                    final paymentMethod = _paymentMethods[order.id];
                    final isInPerson = paymentMethod == 'in_person';
                    String statusMessage;
                    if (isInPerson) {
                      statusMessage = 'In-person payment offer sent. Waiting for rider to confirm the offer.';
                    } else {
                      statusMessage = 'Payment submitted. Waiting for rider confirmation.';
                    }
                    
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
                                  statusMessage,
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
                  
                  return const SizedBox.shrink();
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
