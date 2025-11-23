class Merchant {
  final String id;
  final String? userId;
  final String? loadingStationId;
  final String businessName;
  final String? dtiNumber;
  final String? mayorPermit;
  final String? gcashQrUrl;
  final String? gcashNumber;
  final String address;
  final double latitude;
  final double longitude;
  final String? mapPlaceId;
  final bool verified;
  final DateTime createdAt;
  final String? previewImage;
  final int? rating;
  final String? status;
  final String? slogan;

  Merchant({
    required this.id,
    this.userId,
    this.loadingStationId,
    required this.businessName,
    this.dtiNumber,
    this.mayorPermit,
    this.gcashQrUrl,
    this.gcashNumber,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.mapPlaceId,
    this.verified = false,
    required this.createdAt,
    this.previewImage,
    this.rating,
    this.status,
    this.slogan,
  });

  factory Merchant.fromJson(Map<String, dynamic> json) {
    return Merchant(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      loadingStationId: json['loading_station_id'] as String?,
      businessName: json['business_name'] as String,
      dtiNumber: json['dti_number'] as String?,
      mayorPermit: json['mayor_permit'] as String?,
      gcashQrUrl: json['gcash_qr_url'] as String?,
      gcashNumber: json['gcash_number'] as String?,
      address: json['address'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      mapPlaceId: json['map_place_id'] as String?,
      verified: json['verified'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      previewImage: json['preview_image'] as String?,
      rating: json['rating'] as int?,
      status: json['status'] as String?,
      slogan: json['slogan'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'loading_station_id': loadingStationId,
      'business_name': businessName,
      'dti_number': dtiNumber,
      'mayor_permit': mayorPermit,
      'gcash_qr_url': gcashQrUrl,
      'gcash_number': gcashNumber,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'map_place_id': mapPlaceId,
      'verified': verified,
      'created_at': createdAt.toIso8601String(),
      'preview_image': previewImage,
      'rating': rating,
      'status': status,
      'slogan': slogan,
    };
  }
}

