import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/parking_spot.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/spot_bottom_sheet.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();

  Position? _currentPosition;
  Set<Marker> _markers = {};
  List<ParkingSpot> _spots = []; // retained for future search/filter
  bool _isLoading = true;
  bool _hasLocationPermission = false;

  static const LatLng _skopjeCenter = LatLng(41.9981, 21.4254);

  late AnimationController _fabAnimController;
  late Animation<double> _fabScaleAnim;

  @override
  void initState() {
    super.initState();
    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fabScaleAnim = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _fabAnimController, curve: Curves.easeInOut),
    );
    _initLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _apiService.dispose();
    _searchController.dispose();
    _fabAnimController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _loadSpotsAtDefault();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _loadSpotsAtDefault();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _loadSpotsAtDefault();
        return;
      }

      _hasLocationPermission = true;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;
      setState(() => _currentPosition = position);

      _mapController?.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(position.latitude, position.longitude),
        ),
      );

      _loadSpots(position.latitude, position.longitude);
    } on Exception {
      _loadSpotsAtDefault();
    }
  }

  void _loadSpotsAtDefault() {
    _loadSpots(_skopjeCenter.latitude, _skopjeCenter.longitude);
  }

  Future<void> _loadSpots(double lat, double lon) async {
    setState(() => _isLoading = true);
    try {
      final spots = await _apiService.getNearbySpots(lat: lat, lon: lon);
      if (!mounted) return;
      setState(() {
        _spots = spots;
        _markers = _buildMarkers(spots);
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(e.message);
    } on Exception {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Не може да се поврзе со серверот');
    }
  }

  Set<Marker> _buildMarkers(List<ParkingSpot> spots) {
    return spots.map((spot) {
      final hue = spot.isAvailable
          ? BitmapDescriptor.hueGreen
          : spot.isReserved
              ? BitmapDescriptor.hueOrange
              : BitmapDescriptor.hueRed;

      return Marker(
        markerId: MarkerId(spot.id),
        position: LatLng(spot.latitude, spot.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        onTap: () => _showSpotDetails(spot),
      );
    }).toSet();
  }

  void _showSpotDetails(ParkingSpot spot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SpotBottomSheet(
        spot: spot,
        apiService: _apiService,
        onActionComplete: () {
          Navigator.of(ctx).pop();
          if (_currentPosition != null) {
            _loadSpots(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
            );
          } else {
            _loadSpotsAtDefault();
          }
        },
      ),
    );
  }

  void _recenterMap() {
    _fabAnimController.forward().then((_) => _fabAnimController.reverse());
    if (_currentPosition != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          16,
        ),
      );
    } else {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_skopjeCenter, 15),
      );
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _skopjeCenter,
              zoom: 15,
            ),
            onMapCreated: (controller) => _mapController = controller,
            markers: _markers,
            myLocationEnabled: _hasLocationPermission,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // Search bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: _buildSearchBar(),
          ),

          // Loading indicator
          if (_isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.accent,
                ),
              ),
            ),

          // Recenter button
          Positioned(
            bottom: 24,
            right: 16,
            child: ScaleTransition(
              scale: _fabScaleAnim,
              child: FloatingActionButton(
                onPressed: _recenterMap,
                backgroundColor: AppColors.accent,
                child: const Icon(Icons.my_location, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Material(
      elevation: 4,
      shadowColor: AppColors.primary.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(16),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Пребарај дестинација',
          hintStyle: const TextStyle(color: AppColors.textSecondary),
          prefixIcon: const Icon(Icons.search, color: AppColors.accent),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}
