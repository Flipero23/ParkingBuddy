import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/parking_spot.dart';
import '../models/parking_session.dart';

class ApiService {
  static const String _baseUrl = 'http://10.0.2.2:8080';

  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<ParkingSpot>> getNearbySpots({
    required double lat,
    required double lon,
    int radius = 500,
    int limit = 20,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/spots/nearby?lat=$lat&lon=$lon&radius=$radius&limit=$limit',
    );


    final response = await _client.get(uri);


    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((e) => ParkingSpot.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException(
      'Грешка при вчитување на паркинг места',
      response.statusCode,
    );
  }

  Future<void> reserveSpot(String spotId) async {
    final uri = Uri.parse('$_baseUrl/api/sessions/reserve/$spotId');
    final response = await _client.post(uri);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ApiException('Грешка при резервација', response.statusCode);
    }
  }

  Future<void> cancelReservation(String spotId) async {
    final uri = Uri.parse('$_baseUrl/api/sessions/cancel/$spotId');
    final response = await _client.post(uri);

    if (response.statusCode != 200) {
      throw ApiException('Грешка при откажување', response.statusCode);
    }
  }

  Future<ParkingSession> startParking(String spotId, String licensePlate) async {
    final uri = Uri.parse('$_baseUrl/api/sessions/start/$spotId').replace(
      queryParameters: {
        'licensePlate': licensePlate,
      },
    );

    final response = await _client.post(uri);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return ParkingSession.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }

    throw ApiException('Грешка при започнување паркирање', response.statusCode);
  }

  Future<Map<String, dynamic>> endParking(String spotId) async {
    final uri = Uri.parse('$_baseUrl/api/sessions/end/$spotId');
    final response = await _client.post(uri);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw ApiException('Грешка при завршување паркирање', response.statusCode);
  }

  void dispose() {
    _client.close();
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;

  const ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException($statusCode): $message';
}