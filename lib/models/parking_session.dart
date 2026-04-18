class ParkingSession {
  final String id;
  final String spotId;
  final String licensePlate;
  final String status;
  final DateTime startTime;
  final DateTime? endTime;
  final double? totalCost;

  const ParkingSession({
    required this.id,
    required this.spotId,
    required this.licensePlate,
    required this.status,
    required this.startTime,
    this.endTime,
    this.totalCost,
  });

  factory ParkingSession.fromJson(Map<String, dynamic> json) {
    return ParkingSession(
      id: json['id']?.toString() ?? '',
      spotId: json['spotId']?.toString() ?? '',
      licensePlate: json['licensePlate']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      startTime: json['startTime'] != null
          ? DateTime.parse(json['startTime'].toString())
          : DateTime.now(),
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'].toString())
          : null,
      totalCost: (json['totalCost'] as num?)?.toDouble(),
    );
  }
}
