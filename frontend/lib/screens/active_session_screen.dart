import 'dart:async';
import 'package:flutter/material.dart';
import '../models/parking_spot.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'payment_screen.dart';

class ActiveSessionScreen extends StatefulWidget {
  final ParkingSpot spot;
  final String licensePlate;
  final DateTime sessionStartTime;
  final int durationHours;
  final double paidAmount;
  final ApiService apiService;
  final AuthService? authService;

  const ActiveSessionScreen({
    super.key,
    required this.spot,
    required this.licensePlate,
    required this.sessionStartTime,
    required this.durationHours,
    required this.paidAmount,
    required this.apiService,
    this.authService,
  });

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen>
    with SingleTickerProviderStateMixin {
  late Timer _timer;
  Duration _elapsed = Duration.zero;
  late AnimationController _fadeController;
  late int _durationHours;
  late double _paidAmount;
  bool _extending = false;

  @override
  void initState() {
    super.initState();
    _durationHours = widget.durationHours;
    _paidAmount = widget.paidAmount;

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final elapsed = now.difference(widget.sessionStartTime);
      setState(() => _elapsed = elapsed);

      if (elapsed.inSeconds >= _durationHours * 3600) {
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

  Duration get _remaining {
    final total = Duration(hours: _durationHours);
    final left = total - _elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  String get _formattedRemaining {
    final h = _remaining.inHours.toString().padLeft(2, '0');
    final m = (_remaining.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  bool get _canExtend => _durationHours < 2 && !_extending;

  Future<void> _endParking() async {
    try {
      await widget.apiService.endParking(widget.spot.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _extendParking() async {
    if (!_canExtend) return;

    final extraCost = widget.spot.pricePerHour;
    final paymentResult = await Navigator.of(context).push<PaymentResult>(
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          spot: widget.spot,
          licensePlate: widget.licensePlate,
          durationHours: 1,
          totalCost: extraCost,
          authService: widget.authService,
          showReceiptOnSuccess: true,
        ),
      ),
    );
    if (paymentResult == null || !mounted) return;

    setState(() => _extending = true);
    try {
      final updated = await widget.apiService.extendParking(widget.spot.id);
      if (!mounted) return;
      setState(() {
        _durationHours = updated.durationHours ?? _durationHours + 1;
        _paidAmount = updated.paidAmount ?? _paidAmount + extraCost;
      });
      if (widget.authService?.isLoggedIn == true) {
        try {
          await widget.authService!.getProfile();
        } on AuthException {
          // non-fatal — cached balance stays
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Паркирањето е продолжено за 1 час'),
          backgroundColor: AppColors.accent,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _extending = false);
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
                          fontSize: 48,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Преостанато: $_formattedRemaining',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
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
                          'Платено однапред: ${_paidAmount.toStringAsFixed(0)} МКД · $_durationHours ч',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
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

              if (_canExtend) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _extending ? null : _extendParking,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(
                        color: AppColors.accent,
                        width: 2,
                      ),
                      foregroundColor: AppColors.accent,
                    ),
                    icon: const Icon(Icons.add_alarm),
                    label: Text(
                      _extending
                          ? 'Продолжување...'
                          : 'Продолжи за 1 час (+${widget.spot.pricePerHour.toStringAsFixed(0)} МКД)',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

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
