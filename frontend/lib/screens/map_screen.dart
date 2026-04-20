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
  final FocusNode _searchFocus = FocusNode();

  Position? _currentPosition;
  Set<Marker> _markers = {};
  List<ParkingSpot> _spots = [];
  List<ParkingSpot> _searchResults = [];
  bool _isLoading = true;
  bool _hasLocationPermission = false;
  bool _showSearchResults = false;

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
    _searchController.addListener(_onSearchChanged);
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus) {
        setState(() => _showSearchResults = false);
      }
    });
    _initLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _apiService.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _fabAnimController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }

    final filtered = _spots.where((spot) {
      return spot.streetName.toLowerCase().contains(query) ||
          spot.code.toLowerCase().contains(query) ||
          spot.zone.toLowerCase().contains(query);
    }).toList();

    // Deduplicate by street name, keep closest
    final seen = <String>{};
    final unique = <ParkingSpot>[];
    for (final spot in filtered) {
      if (seen.add(spot.streetName)) {
        unique.add(spot);
      }
    }

    setState(() {
      _searchResults = unique.take(8).toList();
      _showSearchResults = true;
    });
  }

  void _onSearchResultTap(ParkingSpot spot) {
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() => _showSearchResults = false);

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(spot.latitude, spot.longitude),
        17,
      ),
    );

    _loadSpots(spot.latitude, spot.longitude);
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

      if (_isInMacedonia(position.latitude, position.longitude)) {
        setState(() => _currentPosition = position);
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(position.latitude, position.longitude),
          ),
        );
        _loadSpots(position.latitude, position.longitude);
      } else {
        _loadSpotsAtDefault();
      }
    } on Exception {
      _loadSpotsAtDefault();
    }
  }

  bool _isInMacedonia(double lat, double lon) {
    return lat >= 40.85 && lat <= 42.40 && lon >= 20.45 && lon <= 23.05;
  }

  void _loadSpotsAtDefault() {
    _loadSpots(_skopjeCenter.latitude, _skopjeCenter.longitude);
  }

  Future<void> _loadSpots(double lat, double lon) async {
    setState(() => _isLoading = true);
    try {
      final spots = await _apiService.getNearbySpots(
        lat: lat,
        lon: lon,
        radius: 5000,
        limit: 100,
      );
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
      final lat = _currentPosition!.latitude;
      final lon = _currentPosition!.longitude;

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(lat, lon),
          16.5,
        ),
      );

      _loadSpots(lat, lon);
    } else {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_skopjeCenter, 16.5),
      );

      _loadSpotsAtDefault();
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
              zoom: 16.5,
            ),
            onMapCreated: (controller) => _mapController = controller,
            markers: _markers,
            myLocationEnabled: _hasLocationPermission,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onTap: (_) {
              _searchFocus.unfocus();
              setState(() => _showSearchResults = false);
            },
          ),

          // Search bar + results dropdown
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSearchBar(),
                if (_showSearchResults && _searchResults.isNotEmpty)
                  _buildSearchResults(),
              ],
            ),
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
        focusNode: _searchFocus,
        decoration: InputDecoration(
          hintText: 'Пребарај дестинација во Дебар Маало',
          hintStyle: const TextStyle(color: AppColors.textSecondary),
          prefixIcon: const Icon(Icons.search, color: AppColors.accent),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () {
                    _searchController.clear();
                    _searchFocus.unfocus();
                  },
                )
              : null,
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

  Widget _buildSearchResults() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _searchResults.map((spot) {
            final availableOnStreet = _spots
                .where((s) =>
                    s.streetName == spot.streetName && s.isAvailable)
                .length;

            return InkWell(
              onTap: () => _onSearchResultTap(spot),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: availableOnStreet > 0
                          ? AppColors.accent
                          : AppColors.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spot.streetName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Зона ${spot.zone} · $availableOnStreet слободни',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
