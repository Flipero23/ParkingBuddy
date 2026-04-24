import 'dart:async';
import 'package:flutter/material.dart';
import '../models/parking_spot.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/spot_bottom_sheet.dart';

class ReservationScreen extends StatefulWidget {
  final ParkingSpot spot;
  final ApiService apiService;
  final AuthService? authService;

  const ReservationScreen({
    super.key,
    required this.spot,
    required this.apiService,
    this.authService,
  });

  @override
  State<ReservationScreen> createState() => _ReservationScreenState();
}

class _ReservationScreenState extends State<ReservationScreen>
    with SingleTickerProviderStateMixin {
  late Timer _timer;
  int _remainingSeconds = 15 * 60; // 15 minutes
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remainingSeconds <= 0) {
        _timer.cancel();
        _autoCancel();
        return;
      }
      setState(() => _remainingSeconds--);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  String get _formattedTime {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _autoCancel() async {
    try {
      await widget.apiService.cancelReservation(widget.spot.id);
    } on Exception {
      // ignore
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Резервацијата истече'),
        backgroundColor: AppColors.warning,
      ),
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _cancelReservation() async {
    try {
      await widget.apiService.cancelReservation(widget.spot.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _startParking() async {
    await startParkingFlow(
      context: context,
      spot: widget.spot,
      apiService: widget.apiService,
      authService: widget.authService,
      onComplete: () {},
      closeBottomSheet: false,
      replacePrevious: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUrgent = _remainingSeconds < 60;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Резервација',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        centerTitle: true,
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),

              // Timer card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      const Text(
                        'Преостанато време',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _formattedTime,
                        style: TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.w700,
                          color: isUrgent ? AppColors.danger : AppColors.accent,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _remainingSeconds / (15 * 60),
                        backgroundColor: Colors.grey.shade200,
                        color: isUrgent ? AppColors.danger : AppColors.accent,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Spot info card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _infoRow('Код', widget.spot.code),
                      const Divider(height: 20),
                      _infoRow('Улица', widget.spot.streetName),
                      const Divider(height: 20),
                      _infoRow('Зона', widget.spot.zone),
                      const Divider(height: 20),
                      _infoRow(
                        'Цена по час',
                        '${widget.spot.pricePerHour.toStringAsFixed(0)} МКД',
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Action buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _startParking,
                  child: const Text('Започни паркирање'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _cancelReservation,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.danger, width: 2),
                    foregroundColor: AppColors.danger,
                  ),
                  child: const Text('Откажи резервација'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
