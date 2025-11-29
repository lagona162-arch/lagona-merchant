class Rider {
  final String id;
  final String? userId;
  final String? loadingStationId;
  final String fullName;
  final String? phone;
  final String? vehicleType;
  final String? vehicleNumber;
  final bool isAvailable;
  final double? latitude;
  final double? longitude;
  final DateTime? createdAt;

  Rider({
    required this.id,
    this.userId,
    this.loadingStationId,
    required this.fullName,
    this.phone,
    this.vehicleType,
    this.vehicleNumber,
    this.isAvailable = true,
    this.latitude,
    this.longitude,
    this.createdAt,
  });

  factory Rider.fromJson(Map<String, dynamic> json) {
    return Rider(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      loadingStationId: json['loading_station_id'] as String?,
      fullName: json['full_name'] as String? ?? json['name'] as String? ?? 'Unknown',
      phone: json['phone'] as String?,
      vehicleType: json['vehicle_type'] as String?,
      vehicleNumber: json['vehicle_number'] as String?,
      isAvailable: json['is_available'] as bool? ?? true,
      latitude: json['latitude'] != null
          ? (json['latitude'] as num).toDouble()
          : null,
      longitude: json['longitude'] != null
          ? (json['longitude'] as num).toDouble()
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'loading_station_id': loadingStationId,
      'full_name': fullName,
      'phone': phone,
      'vehicle_type': vehicleType,
      'vehicle_number': vehicleNumber,
      'is_available': isAvailable,
      'latitude': latitude,
      'longitude': longitude,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
