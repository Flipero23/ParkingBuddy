import 'dart:async';
import 'package:flutter/material.dart';
import '../models/active_session.dart';
import '../models/parking_spot.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'active_session_screen.dart';
import 'receipt_screen.dart';

/// Reservation timer screen shown AFTER mock payment + spot reservation.
///
/// The user has already chosen plate + duration and completed (mock) payment
/// in the bottom sheet flow, so this screen no longer prompts for any of
/// those when the user clicks "Start parking" — it just calls the backend
/// to flip the reservation into an active session for the prepaid duration.
class ReservationScreen extends StatefulWidget {
  final ParkingSpot spot;
  final ApiService apiService;
  final AuthService? authService;

  // Prepaid context — collected before reservation, replayed on start.
  final String licensePlate;
  final int durationHours;
  final double paidAmount;
  final String paymentMethod;
  final String transactionId;

  /// Optional hook used by [MapScreen] when start-parking should hand the
  /// active session back to the map so it can show the minimized timer card
  /// instead of pushing the full active session screen.
  final void Function(ActiveSession session)? onActiveSessionStarted;

  const ReservationScreen({
    super.key,
    required this.spot,
    required this.apiService,
    required this.licensePlate,
    required this.durationHours,
    required this.paidAmount,
    required this.paymentMethod,
    required this.transactionId,
    this.authService,
    this.onActiveSessionStarted,
  });

  @override
  State<ReservationScreen> createState() => _ReservationScreenState();
}

class _ReservationScreenState extends State<ReservationScreen>
    with SingleTickerProviderStateMixin {
  late Timer _timer;
  int _remainingSeconds = 15 * 60; // 15 minutes
  bool _isStarting = false;
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
      // Ignore — best-effort release; the spot will eventually be reclaimed.
    }
    if (!mounted) return;
    // Spec: after 15 min the reservation expires and the prepaid amount is
    // non-refundable, so no refund message here.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Резервацијата истече'),
        backgroundColor: AppColors.warning,
      ),
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _cancelReservation() async {
    if (_isStarting) return;
    try {
      await widget.apiService.cancelReservation(widget.spot.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
      return;
    }

    if (!mounted) return;
    // Mock refund — no real charge happened (the wallet is only debited on
    // start-parking), but the user perceived a payment, so confirm refund.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Резервацијата е откажана. Средствата се вратени.'),
        backgroundColor: AppColors.accent,
      ),
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _startParking() async {
    if (_isStarting) return;
    setState(() => _isStarting = true);

    try {
      final session = await widget.apiService.startParking(
        widget.spot.id,
        widget.licensePlate,
        durationHours: widget.durationHours,
      );
      if (!mounted) return;

      // Backend has now actually deducted wallet balance — refresh cache.
      if (widget.authService?.isLoggedIn == true) {
        try {
          await widget.authService!.getProfile();
        } on AuthException {
          // Non-fatal — keep stale cached balance.
        }
        if (!mounted) return;
      }

      _timer.cancel();

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReceiptScreen(
            spot: widget.spot,
            licensePlate: widget.licensePlate,
            totalCost: widget.paidAmount,
            totalTime: Duration(hours: widget.durationHours),
            paymentMethod: widget.paymentMethod,
            transactionId: widget.transactionId,
          ),
        ),
      );
      if (!mounted) return;

      // Use the backend's session.startTime so the paid duration counts
      // from the moment payment was confirmed (session creation), not from
      // when the user dismisses the receipt.
      final activeSession = ActiveSession(
        spot: widget.spot,
        licensePlate: widget.licensePlate,
        startTime: session.startTime,
        durationHours: session.durationHours ?? widget.durationHours,
        paidAmount: session.paidAmount ?? widget.paidAmount,
      );

      if (widget.onActiveSessionStarted != null) {
        // Pop the reservation screen FIRST, then hand the session over.
        // MapScreen's callback synchronously pushes ActiveSessionScreen on
        // top of the navigator; popping AFTER the callback would remove
        // that just-pushed screen instead of this reservation screen and
        // leave the user stuck on a stale, timer-cancelled reservation.
        Navigator.of(context).pop(true);
        widget.onActiveSessionStarted!(activeSession);
        return;
      }

      // Replace reservation in the stack so back from active session goes
      // straight to the map.
      await Navigator.of(context).pushReplacement<ActiveSessionResult, bool>(
        MaterialPageRoute<ActiveSessionResult>(
          builder: (_) => ActiveSessionScreen(
            spot: widget.spot,
            licensePlate: widget.licensePlate,
            sessionStartTime: activeSession.startTime,
            durationHours: activeSession.durationHours,
            paidAmount: activeSession.paidAmount,
            apiService: widget.apiService,
            authService: widget.authService,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;

      if (e.statusCode == 409) {
        // Spot was somehow lost (shouldn't happen — we hold the reservation).
        // Treat it like an expiry: show error and pop.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Местото веќе не е достапно'),
            backgroundColor: AppColors.danger,
          ),
        );
        Navigator.of(context).pop(true);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
      setState(() => _isStarting = false);
    }
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

              // Spot + prepaid info card
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
                        'Платено однапред',
                        '${widget.paidAmount.toStringAsFixed(0)} МКД · ${widget.durationHours} ч',
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
                  onPressed: _isStarting ? null : _startParking,
                  child: _isStarting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Започни паркирање'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isStarting ? null : _cancelReservation,
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
