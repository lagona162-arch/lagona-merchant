import 'product.dart';

enum DeliveryStatus {
  pending,
  accepted,
  waitingForPayment,
  paymentReceived,
  prepared,
  ready,
  pickedUp,
  inTransit,
  completed,
  cancelled,
}

extension DeliveryStatusExtension on DeliveryStatus {
  String get value {
    switch (this) {
      case DeliveryStatus.pending:
        return 'pending';
      case DeliveryStatus.accepted:
        return 'accepted';
      case DeliveryStatus.waitingForPayment:
        return 'accepted';
      case DeliveryStatus.paymentReceived:
        return 'payment_received';
      case DeliveryStatus.prepared:
        return 'prepared';
      case DeliveryStatus.ready:
        return 'ready';
      case DeliveryStatus.pickedUp:
        return 'picked_up';
      case DeliveryStatus.inTransit:
        return 'in_transit';
      case DeliveryStatus.completed:
        return 'completed';
      case DeliveryStatus.cancelled:
        return 'cancelled';
    }
  }

  static DeliveryStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return DeliveryStatus.pending;
      case 'accepted':
      case 'waiting_for_payment':
        return DeliveryStatus.waitingForPayment;
      case 'payment_received':
        return DeliveryStatus.paymentReceived;
      case 'prepared':
        return DeliveryStatus.prepared;
      case 'ready':
        return DeliveryStatus.ready;
      case 'picked_up':
        return DeliveryStatus.pickedUp;
      case 'in_transit':
        return DeliveryStatus.inTransit;
      case 'completed':
        return DeliveryStatus.completed;
      case 'cancelled':
        return DeliveryStatus.cancelled;
      default:
        return DeliveryStatus.pending;
    }
  }
}

class Delivery {
  final String id;
  final String type;
  final String? customerId;
  final String? merchantId;
  final String? riderId;
  final String? loadingStationId;
  final String? businessHubId;
  final String? pickupAddress;
  final String? dropoffAddress;
  final double? pickupLatitude;
  final double? pickupLongitude;
  final double? dropoffLatitude;
  final double? dropoffLongitude;
  final String? pickupPhotoUrl;
  final String? dropoffPhotoUrl;
  final double? distanceKm;
  final double? deliveryFee;
  final double? commissionRider;
  final double? commissionLoading;
  final double? commissionHub;
  final DeliveryStatus status;
  final String? buyerMerchantTagId;
  final String? buyerRiderTagId;
  final DateTime? completedAt;
  final DateTime createdAt;
  final List<DeliveryItem>? items;
  final bool paymentRequested;

  final String? customerName;
  final String? customerEmail;

  Delivery({
    required this.id,
    required this.type,
    this.customerId,
    this.merchantId,
    this.riderId,
    this.loadingStationId,
    this.businessHubId,
    this.pickupAddress,
    this.dropoffAddress,
    this.pickupLatitude,
    this.pickupLongitude,
    this.dropoffLatitude,
    this.dropoffLongitude,
    this.pickupPhotoUrl,
    this.dropoffPhotoUrl,
    this.distanceKm,
    this.deliveryFee,
    this.commissionRider,
    this.commissionLoading,
    this.commissionHub,
    required this.status,
    this.buyerMerchantTagId,
    this.buyerRiderTagId,
    this.completedAt,
    required this.createdAt,
    this.items,
    this.paymentRequested = false,
    this.customerName,
    this.customerEmail,
  });

  factory Delivery.fromJson(Map<String, dynamic> json) {

    Map<String, dynamic>? usersData;

    if (json['customers'] != null) {
      Map<String, dynamic>? customersData;
      if (json['customers'] is Map) {
        customersData = json['customers'] as Map<String, dynamic>;
      } else if (json['customers'] is List && (json['customers'] as List).isNotEmpty) {
        customersData = (json['customers'] as List).first as Map<String, dynamic>?;
      }

      if (customersData != null && customersData['users'] != null) {
        if (customersData['users'] is Map) {
          usersData = customersData['users'] as Map<String, dynamic>;
        } else if (customersData['users'] is List && (customersData['users'] as List).isNotEmpty) {
          usersData = (customersData['users'] as List).first as Map<String, dynamic>?;
        }
      }
    }

    if (usersData == null && json['users'] != null) {
      if (json['users'] is Map) {
        usersData = json['users'] as Map<String, dynamic>;
      } else if (json['users'] is List && (json['users'] as List).isNotEmpty) {
        usersData = (json['users'] as List).first as Map<String, dynamic>?;
      }
    }

    return Delivery(
      id: json['id'] as String,
      type: json['type'] as String,
      customerId: json['customer_id'] as String?,
      merchantId: json['merchant_id'] as String?,
      riderId: json['rider_id'] as String?,
      loadingStationId: json['loading_station_id'] as String?,
      businessHubId: json['business_hub_id'] as String?,
      pickupAddress: json['pickup_address'] as String?,
      dropoffAddress: json['dropoff_address'] as String?,
      pickupLatitude: json['pickup_latitude'] != null
          ? (json['pickup_latitude'] as num).toDouble()
          : null,
      pickupLongitude: json['pickup_longitude'] != null
          ? (json['pickup_longitude'] as num).toDouble()
          : null,
      dropoffLatitude: json['dropoff_latitude'] != null
          ? (json['dropoff_latitude'] as num).toDouble()
          : null,
      dropoffLongitude: json['dropoff_longitude'] != null
          ? (json['dropoff_longitude'] as num).toDouble()
          : null,
      pickupPhotoUrl: json['pickup_photo_url'] as String?,
      dropoffPhotoUrl: json['dropoff_photo_url'] as String?,
      distanceKm: json['distance_km'] != null
          ? (json['distance_km'] as num).toDouble()
          : null,
      deliveryFee: json['delivery_fee'] != null
          ? (json['delivery_fee'] as num).toDouble()
          : null,
      commissionRider: json['commission_rider'] != null
          ? (json['commission_rider'] as num).toDouble()
          : null,
      commissionLoading: json['commission_loading'] != null
          ? (json['commission_loading'] as num).toDouble()
          : null,
      commissionHub: json['commission_hub'] != null
          ? (json['commission_hub'] as num).toDouble()
          : null,
      status: DeliveryStatusExtension.fromString(
        json['status'] as String? ?? 'pending',
      ),
      buyerMerchantTagId: json['buyer_merchant_tag_id'] as String?,
      buyerRiderTagId: json['buyer_rider_tag_id'] as String?,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      paymentRequested: json['payment_requested'] as bool? ?? false,
      customerName: usersData?['full_name'] as String?,
      customerEmail: usersData?['email'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'customer_id': customerId,
      'merchant_id': merchantId,
      'rider_id': riderId,
      'loading_station_id': loadingStationId,
      'business_hub_id': businessHubId,
      'pickup_address': pickupAddress,
      'dropoff_address': dropoffAddress,
      'pickup_latitude': pickupLatitude,
      'pickup_longitude': pickupLongitude,
      'dropoff_latitude': dropoffLatitude,
      'dropoff_longitude': dropoffLongitude,
      'pickup_photo_url': pickupPhotoUrl,
      'dropoff_photo_url': dropoffPhotoUrl,
      'distance_km': distanceKm,
      'delivery_fee': deliveryFee,
      'commission_rider': commissionRider,
      'commission_loading': commissionLoading,
      'commission_hub': commissionHub,
      'status': status.value,
      'buyer_merchant_tag_id': buyerMerchantTagId,
      'buyer_rider_tag_id': buyerRiderTagId,
      'completed_at': completedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class DeliveryItemAddon {
  final String id;
  final String deliveryItemId;
  final String addonId;
  final String name;
  final double price;
  final int quantity;
  final double subtotal;
  final DateTime createdAt;

  DeliveryItemAddon({
    required this.id,
    required this.deliveryItemId,
    required this.addonId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.subtotal,
    required this.createdAt,
  });

  factory DeliveryItemAddon.fromJson(Map<String, dynamic> json) {
    return DeliveryItemAddon(
      id: json['id'] as String,
      deliveryItemId: json['delivery_item_id'] as String,
      addonId: json['addon_id'] as String,
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      quantity: json['quantity'] as int? ?? 1,
      subtotal: (json['subtotal'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'delivery_item_id': deliveryItemId,
      'addon_id': addonId,
      'name': name,
      'price': price,
      'quantity': quantity,
      'subtotal': subtotal,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class DeliveryItem {
  final String id;
  final String deliveryId;
  final String productId;
  final int quantity;
  final double subtotal;
  final MerchantProduct? product;
  final List<DeliveryItemAddon> addons;

  DeliveryItem({
    required this.id,
    required this.deliveryId,
    required this.productId,
    this.quantity = 1,
    required this.subtotal,
    this.product,
    this.addons = const [],
  });

  factory DeliveryItem.fromJson(Map<String, dynamic> json) {

    Map<String, dynamic>? productJson;
    if (json['merchant_products'] != null) {
      productJson = json['merchant_products'] is Map<String, dynamic>
          ? json['merchant_products'] as Map<String, dynamic>
          : null;
    } else if (json['product'] != null) {
      productJson = json['product'] is Map<String, dynamic>
          ? json['product'] as Map<String, dynamic>
          : null;
    }

    // Parse addons - handle different Supabase response formats
    List<DeliveryItemAddon> addonsList = [];
    final addonsData = json['delivery_item_addons'];
    if (addonsData != null) {
      if (addonsData is List) {
        // Supabase returns nested relations as arrays
        addonsList = (addonsData as List)
            .where((addonJson) => addonJson != null)
            .map((addonJson) {
              try {
                if (addonJson is Map<String, dynamic>) {
                  return DeliveryItemAddon.fromJson(addonJson);
                }
                return null;
              } catch (e) {
                // Silently skip invalid addon entries
                return null;
              }
            })
            .whereType<DeliveryItemAddon>()
            .toList();
      } else if (addonsData is Map<String, dynamic>) {
        // Handle case where it might be a single object (unlikely but possible)
        try {
          addonsList = [DeliveryItemAddon.fromJson(addonsData)];
        } catch (e) {
          // Silently skip if parsing fails
        }
      }
    }

    return DeliveryItem(
      id: json['id'] as String,
      deliveryId: json['delivery_id'] as String,
      productId: json['product_id'] as String,
      quantity: json['quantity'] as int? ?? 1,
      subtotal: (json['subtotal'] as num).toDouble(),
      product: productJson != null
          ? MerchantProduct.fromJson(productJson)
          : null,
      addons: addonsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'delivery_id': deliveryId,
      'product_id': productId,
      'quantity': quantity,
      'subtotal': subtotal,
      'addons': addons.map((addon) => addon.toJson()).toList(),
    };
  }
}
