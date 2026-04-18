import 'dart:async';
import 'package:flutter/material.dart';
import '../models/parking_spot.dart';
import '../services/api_service.dart';
import '../theme.dart';
import 'payment_screen.dart';

class ActiveSessionScreen extends StatefulWidget {
  final ParkingSpot spot;
  final String licensePlate;
  final DateTime sessionStartTime;
  final ApiService apiService;

  const ActiveSessionScreen({
    super.key,
    required this.spot,
    required this.licensePlate,
    required this.sessionStartTime,
    required this.apiService,
  });

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen>
    with SingleTickerProviderStateMixin {
  late Timer _timer;
  Duration _elapsed = Duration.zero;
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final elapsed = now.difference(widget.sessionStartTime);
      setState(() => _elapsed = elapsed);

      if (elapsed.inMinutes >= 120) {
        _timer.cancel();
        _endParking();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  String get _formattedElapsed {
    final hours = _elapsed.inHours.toString().padLeft(2, '0');
    final minutes = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  double get _currentCost {
    final hours = _elapsed.inSeconds / 3600.0;
    return hours * widget.spot.pricePerHour;
  }

  Future<void> _endParking() async {
    try {
      final result = await widget.apiService.endParking(widget.spot.id);
      if (!mounted) return;
      final totalCost = (result['totalCost'] as num?)?.toDouble() ?? _currentCost;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PaymentScreen(
            spot: widget.spot,
            licensePlate: widget.licensePlate,
            totalCost: totalCost,
            totalTime: _elapsed,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Активно паркирање',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: FadeTransition(
        opacity: CurvedAnimation(
          parent: _fadeController,
          curve: Curves.easeIn,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),

              // Timer
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.timer,
                        color: AppColors.accent,
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _formattedElapsed,
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Моментална цена: ${_currentCost.toStringAsFixed(0)} МКД',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Session info
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
                      _infoRow('Регистарска таблица', widget.licensePlate),
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

              // End parking button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _endParking,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: const Text(
                    'Заврши паркирање',
                    style: TextStyle(fontSize: 18),
                  ),
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
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
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
