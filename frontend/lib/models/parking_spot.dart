class ParkingSpot {
  final String id;
  final String code;
  final String streetName;
  final String zone;
  final double latitude;
  final double longitude;
  final double distance;
  final double pricePerHour;
  final int maxDurationMinutes;
  final String status;

  const ParkingSpot({
    required this.id,
    required this.code,
    required this.streetName,
    required this.zone,
    required this.latitude,
    required this.longitude,
    required this.distance,
    required this.pricePerHour,
    required this.maxDurationMinutes,
    required this.status,
  });

  factory ParkingSpot.fromJson(Map<String, dynamic> json) {
    return ParkingSpot(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      streetName: json['streetName']?.toString() ?? '',
      zone: json['zone']?.toString() ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      pricePerHour: (json['pricePerHour'] as num?)?.toDouble() ?? 0.0,
      maxDurationMinutes: (json['maxDurationMinutes'] as num?)?.toInt() ?? 120,
      status: json['status']?.toString() ?? 'available',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'streetName': streetName,
    'zone': zone,
    'latitude': latitude,
    'longitude': longitude,
    'distance': distance,
    'pricePerHour': pricePerHour,
    'maxDurationMinutes': maxDurationMinutes,
    'status': status,
  };

  bool get isAvailable => status.toLowerCase() == 'available';
  bool get isReserved => status.toLowerCase() == 'reserved';
  bool get isOccupied => status.toLowerCase() == 'occupied';
}
