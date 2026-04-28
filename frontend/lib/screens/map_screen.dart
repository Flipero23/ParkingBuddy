import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/active_session.dart';
import '../models/parking_spot.dart';
import '../models/place_suggestion.dart';
import '../services/active_session_storage.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/places_service.dart';
import '../theme.dart';
import '../widgets/spot_bottom_sheet.dart';
import 'active_session_screen.dart';
import 'profile_screen.dart';
import 'welcome_screen.dart';

class MapScreen extends StatefulWidget {
  final AuthService authService;

  const MapScreen({super.key, required this.authService});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  late final ApiService _apiService = ApiService(
    authService: widget.authService,
  );
  final PlacesService _placesService = PlacesService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  Position? _currentPosition;
  Set<Marker> _markers = {};
  List<ParkingSpot> _spots = [];
  List<ParkingSpot> _searchResults = [];
  List<PlaceSuggestion> _placeSuggestions = [];
  bool _isLoading = true;
  bool _hasLocationPermission = false;
  bool _showSearchResults = false;
  bool _isSearchingPlaces = false;
  Timer? _searchDebounce;
  // Tracks the latest in-flight remote search so we can drop stale results
  // without racing — the highest seq always wins.
  int _searchSeq = 0;

  // Tracks whether the GoogleMap platform view has signalled `onMapCreated`.
  // We defer the (potentially 100-marker) initial spot load until then, so
  // marker placement doesn't compete with the platform view setup, location
  // service start, and `myLocationEnabled` for the main thread.
  bool _mapReady = false;
  bool _initialLoadStarted = false;

  ActiveSession? _activeSession;
  Timer? _activeSessionTicker;
  // ValueNotifier so the 1Hz timer tick only rebuilds the small timer text,
  // not the whole MapScreen (which would rebuild the GoogleMap tree).
  final ValueNotifier<Duration> _activeSessionElapsed = ValueNotifier(
    Duration.zero,
  );

  static const LatLng _skopjeCenter = LatLng(42.0003, 21.4177);

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
    unawaited(_restoreActiveSession());
    _initLocation();
  }

  Future<void> _restoreActiveSession() async {
    final session = await ActiveSessionStorage.load();
    if (!mounted || session == null) return;

    // Drop sessions that already ran their course while the app was closed.
    final endsAt = session.startTime.add(
      Duration(hours: session.durationHours),
    );
    if (!DateTime.now().isBefore(endsAt)) {
      unawaited(ActiveSessionStorage.clear());
      return;
    }

    _activeSessionElapsed.value = DateTime.now().difference(session.startTime);
    setState(() {
      _activeSession = session;
      _markers = {_buildActiveSessionMarker(session)};
    });
    _startActiveSessionTicker();

    if (_mapReady) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(session.spot.latitude, session.spot.longitude),
          18,
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _activeSessionTicker?.cancel();
    _activeSessionElapsed.dispose();
    _mapController?.dispose();
    _apiService.dispose();
    _placesService.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _fabAnimController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final raw = _searchController.text.trim();
    // Local DB matches stay synchronous and free — keep them snappy.
    _updateLocalResults(raw);

    _searchDebounce?.cancel();

    if (raw.isEmpty) {
      setState(() {
        _placeSuggestions = const [];
        _isSearchingPlaces = false;
        _showSearchResults = false;
      });
      return;
    }

    setState(() {
      _showSearchResults = true;
      _isSearchingPlaces = true;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_runRemoteSearch(raw));
    });
  }

  void _updateLocalResults(String raw) {
    final query = raw.toLowerCase();
    if (query.isEmpty) {
      _searchResults = const [];
      return;
    }

    final filtered = _spots.where((spot) {
      return spot.streetName.toLowerCase().contains(query) ||
          spot.code.toLowerCase().contains(query) ||
          spot.zone.toLowerCase().contains(query);
    });

    final seen = <String>{};
    final unique = <ParkingSpot>[];
    for (final spot in filtered) {
      if (seen.add(spot.streetName)) {
        unique.add(spot);
      }
    }
    _searchResults = unique.take(5).toList(growable: false);
  }

  Future<void> _runRemoteSearch(String query) async {
    final seq = ++_searchSeq;
    // Bias toward the user's current position when available so results
    // near them rank first; the service falls back to the Skopje center.
    final suggestions = await _placesService.search(
      query,
      biasLat: _currentPosition?.latitude,
      biasLng: _currentPosition?.longitude,
    );
    if (!mounted || seq != _searchSeq) return;
    // Discard if the user has cleared or moved on to a different query.
    if (_searchController.text.trim() != query) return;

    setState(() {
      _placeSuggestions = suggestions;
      _isSearchingPlaces = false;
    });
  }

  void _onLocalResultTap(ParkingSpot spot) {
    _dismissSearch();
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(spot.latitude, spot.longitude), 17),
    );
    unawaited(_loadSpots(spot.latitude, spot.longitude));
  }

  Future<void> _onPlaceSuggestionTap(PlaceSuggestion suggestion) async {
    _dismissSearch();

    // Autocomplete predictions don't carry coordinates — resolve them
    // via Place Details before we move the camera.
    final resolved =
        (suggestion.latitude != null && suggestion.longitude != null)
            ? suggestion
            : await _placesService.getDetails(suggestion);
    if (!mounted) return;

    final lat = resolved?.latitude;
    final lng = resolved?.longitude;
    if (lat == null || lng == null) {
      _showError('Не може да се вчита локацијата');
      return;
    }

    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(lat, lng), 18),
    );
    if (!mounted) return;
    unawaited(_loadSpots(lat, lng, announceEmpty: true));
  }

  void _dismissSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() {
      _showSearchResults = false;
      _searchResults = const [];
      _placeSuggestions = const [];
      _isSearchingPlaces = false;
    });
  }

  Future<void> _initLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _attemptInitialLoad();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _attemptInitialLoad();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _attemptInitialLoad();
        return;
      }

      if (!mounted) return;
      // Flip myLocationEnabled on the GoogleMap. Done in its own setState so
      // it can happen independently of position resolution.
      setState(() => _hasLocationPermission = true);

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;

      if (_isInMacedonia(position.latitude, position.longitude)) {
        _currentPosition = position;
        if (_mapReady) {
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(
              LatLng(position.latitude, position.longitude),
            ),
          );
        }
      }
      _attemptInitialLoad();
    } on Exception {
      _attemptInitialLoad();
    }
  }

  /// Called by the GoogleMap once its platform view is ready. We capture the
  /// controller, recenter on the user (if location resolved before the map),
  /// and schedule the initial spots fetch for the next frame so the map
  /// fully renders before 100 markers are pushed across the platform channel.
  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _mapReady = true;

    final session = _activeSession;
    if (session != null) {
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(session.spot.latitude, session.spot.longitude),
          17,
        ),
      );
    } else {
      final pos = _currentPosition;
      if (pos != null) {
        controller.animateCamera(
          CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
        );
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attemptInitialLoad();
    });
  }

  /// Loads the initial set of spots only once both prerequisites are met:
  /// the map is ready AND the location/permission flow has resolved (either
  /// to a real position or to "use default"). Either side calls this after
  /// it finishes; whoever arrives second triggers the actual fetch.
  void _attemptInitialLoad() {
    if (!mounted || !_mapReady || _initialLoadStarted) return;
    _initialLoadStarted = true;
    final pos = _currentPosition;
    if (pos != null) {
      _loadSpots(pos.latitude, pos.longitude);
    } else {
      _loadSpotsAtDefault();
    }
  }

  bool _isInMacedonia(double lat, double lon) {
    return lat >= 40.85 && lat <= 42.40 && lon >= 20.45 && lon <= 23.05;
  }

  void _loadSpotsAtDefault() {
    _loadSpots(_skopjeCenter.latitude, _skopjeCenter.longitude);
  }

  Future<void> _loadSpots(
    double lat,
    double lon, {
    bool announceEmpty = false,
  }) async {
    // While a session is active, the map only ever shows the parked car
    // marker — skip the spots fetch entirely.
    if (_activeSession != null) {
      setState(() {
        _isLoading = false;
        _markers = {_buildActiveSessionMarker(_activeSession!)};
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final spots = await _apiService.getNearbySpots(
        lat: lat,
        lon: lon,
        radius: 200,
        limit: 100,
      );
      if (!mounted) return;
      // Active session may have been restored while we were fetching —
      // don't clobber the parked-car marker with the spot grid.
      if (_activeSession != null) {
        setState(() {
          _spots = spots;
          _markers = {_buildActiveSessionMarker(_activeSession!)};
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _spots = spots;
        _markers = _buildMarkers(spots);
        _isLoading = false;
      });

      if (announceEmpty &&
          spots.where((s) => s.isAvailable).isEmpty) {
        _showInfo('Нема достапни паркинг места во близина');
      }
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

  /// A clearly distinct marker (azure) for the parked car. Using the
  /// default bitmap with a different hue avoids the brittleness of
  /// loading a custom image asset, while still being instantly readable
  /// against the regular green/orange/red spot markers.
  Marker _buildActiveSessionMarker(ActiveSession session) {
    return Marker(
      markerId: const MarkerId('active_session'),
      position: LatLng(session.spot.latitude, session.spot.longitude),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      infoWindow: InfoWindow(
        title: 'Вашиот автомобил',
        snippet: '${session.spot.streetName} · ${session.licensePlate}',
      ),
      onTap: _openActiveSession,
    );
  }

  void _startActiveSession(ActiveSession session) {
    _activeSessionElapsed.value = DateTime.now().difference(session.startTime);
    setState(() {
      _activeSession = session;
      _markers = {_buildActiveSessionMarker(session)};
    });
    unawaited(ActiveSessionStorage.save(session));
    _startActiveSessionTicker();

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(session.spot.latitude, session.spot.longitude),
        17,
      ),
    );

    // Push the screen now so the user sees the same active session
    // experience as before — they can minimize back to this map.
    unawaited(_openActiveSession());
  }

  void _startActiveSessionTicker() {
    _activeSessionTicker?.cancel();
    _activeSessionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _activeSession == null) return;
      // Writing to the ValueNotifier only rebuilds the timer text via its
      // ValueListenableBuilder; the GoogleMap, search bar, FAB, etc. are
      // untouched. This is what keeps the main thread free.
      _activeSessionElapsed.value = DateTime.now().difference(
        _activeSession!.startTime,
      );
    });
  }

  Future<void> _openActiveSession() async {
    final session = _activeSession;
    if (session == null) return;

    final result = await Navigator.of(context).push<ActiveSessionResult>(
      MaterialPageRoute(
        builder: (_) => ActiveSessionScreen(
          spot: session.spot,
          licensePlate: session.licensePlate,
          sessionStartTime: session.startTime,
          durationHours: session.durationHours,
          paidAmount: session.paidAmount,
          apiService: _apiService,
          authService: widget.authService,
          onSessionUpdated: (durationHours, paidAmount) {
            if (!mounted || _activeSession == null) return;
            final updated = _activeSession!.copyWith(
              durationHours: durationHours,
              paidAmount: paidAmount,
            );
            setState(() {
              _activeSession = updated;
            });
            unawaited(ActiveSessionStorage.save(updated));
          },
        ),
      ),
    );

    if (!mounted) return;
    if (result == ActiveSessionResult.ended) {
      _clearActiveSession();
    }
    // ActiveSessionResult.minimized (or null) → keep the session running.
  }

  void _clearActiveSession() {
    _activeSessionTicker?.cancel();
    _activeSessionTicker = null;
    _activeSessionElapsed.value = Duration.zero;
    setState(() {
      _activeSession = null;
    });
    unawaited(ActiveSessionStorage.clear());

    // Restore normal markers around the user's current location.
    if (_currentPosition != null) {
      _loadSpots(_currentPosition!.latitude, _currentPosition!.longitude);
    } else {
      _loadSpotsAtDefault();
    }
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void _showSpotDetails(ParkingSpot spot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SpotBottomSheet(
        spot: spot,
        apiService: _apiService,
        authService: widget.authService,
        onActionComplete: () {
          // Don't refetch spots while a session is active — the only
          // marker on the map should remain the parked car.
          if (_activeSession != null) return;
          if (_currentPosition != null) {
            _loadSpots(_currentPosition!.latitude, _currentPosition!.longitude);
          } else {
            _loadSpotsAtDefault();
          }
        },
        onActiveSessionStarted: _startActiveSession,
      ),
    );
  }

  void _recenterMap() {
    _fabAnimController.forward().then((_) => _fabAnimController.reverse());

    if (_currentPosition != null) {
      final lat = _currentPosition!.latitude;
      final lon = _currentPosition!.longitude;

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(lat, lon), 18),
      );

      _loadSpots(lat, lon);
    } else {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_skopjeCenter, 18),
      );

      _loadSpotsAtDefault();
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
    );
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _openProfileOrWelcome() async {
    _searchFocus.unfocus();
    setState(() => _showSearchResults = false);

    if (widget.authService.isLoggedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileScreen(authService: widget.authService),
        ),
      );
    } else {
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => WelcomeScreen(authService: widget.authService),
        ),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _skopjeCenter,
              zoom: 18,
            ),
            onMapCreated: _onMapCreated,
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

          // Search bar + profile button + results dropdown
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: _buildSearchBar()),
                    const SizedBox(width: 10),
                    _buildProfileButton(),
                  ],
                ),
                if (_showSearchResults) _buildSearchResults(),
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
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            ),

          // Recenter button + (optional) minimized active session card
          Positioned(
            bottom: 24,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_activeSession != null) ...[
                  _buildActiveSessionCard(),
                  const SizedBox(height: 12),
                ],
                ScaleTransition(
                  scale: _fabScaleAnim,
                  child: FloatingActionButton(
                    onPressed: _recenterMap,
                    backgroundColor: AppColors.accent,
                    child: const Icon(Icons.my_location, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSessionCard() {
    return Material(
      elevation: 6,
      shadowColor: AppColors.primary.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openActiveSession,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.directions_car,
                color: AppColors.accent,
                size: 22,
              ),
              const SizedBox(width: 10),
              ValueListenableBuilder<Duration>(
                valueListenable: _activeSessionElapsed,
                builder: (_, elapsed, _) => Text(
                  _formatElapsed(elapsed),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 1.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileButton() {
    final icon = widget.authService.isLoggedIn ? Icons.person : Icons.login;
    return Material(
      elevation: 4,
      shadowColor: AppColors.primary.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openProfileOrWelcome,
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          child: Icon(icon, color: AppColors.accent, size: 24),
        ),
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
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Пребарај локација или адреса',
          hintStyle: const TextStyle(color: AppColors.textSecondary),
          prefixIcon: const Icon(Icons.search, color: AppColors.accent),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: _dismissSearch,
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
    final hasLocal = _searchResults.isNotEmpty;
    final hasPlaces = _placeSuggestions.isNotEmpty;
    final showLoading = _isSearchingPlaces && !hasPlaces;
    final showEmpty =
        !_isSearchingPlaces && !hasLocal && !hasPlaces &&
            _searchController.text.trim().isNotEmpty;

    if (!hasLocal && !hasPlaces && !showLoading && !showEmpty) {
      return const SizedBox.shrink();
    }

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
          children: [
            if (hasLocal) ...[
              _buildSectionHeader('Паркинг места'),
              ..._searchResults.map(_buildLocalRow),
            ],
            if (hasLocal && (hasPlaces || showLoading))
              const Divider(height: 1, color: Color(0x11000000)),
            if (hasPlaces) ...[
              _buildSectionHeader('Локации'),
              ..._placeSuggestions.map(_buildPlaceRow),
            ],
            if (showLoading) _buildLoadingRow(),
            if (showEmpty) _buildEmptyRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildLocalRow(ParkingSpot spot) {
    final availableOnStreet = _spots
        .where((s) => s.streetName == spot.streetName && s.isAvailable)
        .length;

    return InkWell(
      onTap: () => _onLocalResultTap(spot),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.local_parking,
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
  }

  Widget _buildPlaceRow(PlaceSuggestion suggestion) {
    return InkWell(
      onTap: () => unawaited(_onPlaceSuggestionTap(suggestion)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.place_outlined,
                color: AppColors.accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (suggestion.secondary != null)
                    Text(
                      suggestion.secondary!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
  }

  Widget _buildLoadingRow() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accent,
            ),
          ),
          SizedBox(width: 12),
          Text(
            'Барам локации…',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyRow() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Text(
        'Нема резултати за пребарувањето',
        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    );
  }
}
