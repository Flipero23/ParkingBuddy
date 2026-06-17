import 'package:flutter/material.dart';
import '../models/active_session.dart';
import '../models/parking_session.dart';
import '../models/parking_spot.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../screens/reservation_screen.dart';
import '../screens/payment_screen.dart';
import '../screens/receipt_screen.dart';
import '../widgets/license_plate_dialog.dart';
import '../widgets/duration_picker_dialog.dart';
import '../screens/active_session_screen.dart';

class SpotBottomSheet extends StatefulWidget {
  final ParkingSpot spot;
  final ApiService apiService;
  final AuthService? authService;
  final VoidCallback onActionComplete;

  /// Optional hook used by [MapScreen] to take over the active-session
  /// navigation so it can render the minimized timer card and a single
  /// car marker on the map. If null, the legacy flow is used (the bottom
  /// sheet pushes [ActiveSessionScreen] itself).
  final void Function(ActiveSession session)? onActiveSessionStarted;

  const SpotBottomSheet({
    super.key,
    required this.spot,
    required this.apiService,
    required this.onActionComplete,
    this.authService,
    this.onActiveSessionStarted,
  });

  @override
  State<SpotBottomSheet> createState() => _SpotBottomSheetState();
}

class _SpotBottomSheetState extends State<SpotBottomSheet> {
  // Disables both action buttons while a reserve/start request is in flight.
  // Prevents double-taps from racing each other on the same spot.
  bool _isProcessing = false;

  ParkingSpot get _spot => widget.spot;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  _spot.code,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _buildStatusChip(),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _spot.streetName,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildInfoItem(Icons.location_on_outlined, 'Зона', _spot.zone),
              _buildInfoItem(
                Icons.straighten,
                'Растојание',
                '${_spot.distance.toStringAsFixed(0)} м',
              ),
              _buildInfoItem(
                Icons.attach_money,
                'Цена по час',
                '${_spot.pricePerHour.toStringAsFixed(0)} МКД',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Максимално траење: ${_spot.maxDurationMinutes} мин',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          if (_spot.isAvailable) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isProcessing ? null : _handleReserve,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: AppColors.warning,
                        width: 2,
                      ),
                      foregroundColor: AppColors.warning,
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.warning,
                            ),
                          )
                        : const Text('Резервирај'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _handleStartParking,
                    child: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Започни паркирање'),
                  ),
                ),
              ],
            ),
          ] else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: _spot.isReserved
                    ? AppColors.warning.withValues(alpha: 0.1)
                    : AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _spot.isReserved ? 'Резервирано' : 'Зафатено',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _spot.isReserved ? AppColors.warning : AppColors.danger,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusChip() {
    final Color color;
    final String label;
    if (_spot.isAvailable) {
      color = AppColors.accent;
      label = 'Слободно';
    } else if (_spot.isReserved) {
      color = AppColors.warning;
      label = 'Резервирано';
    } else {
      color = AppColors.danger;
      label = 'Зафатено';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: AppColors.accent, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleReserve() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // Collect plate + duration + (mock) payment BEFORE reserving the spot.
    // The backend reservation is only created after payment succeeds, so a
    // user who bails out of any of the dialogs does not hold the spot.
    // Prefill the plate input from the user's saved profile plate if any
    // (only valid MK plates flow through, foreign saved values are skipped
    // to avoid wedging the dialog into the wrong mode).
    final savedPlate = widget.authService?.licensePlate;
    final licensePlate = await showDialog<String>(
      context: context,
      builder: (_) => LicensePlateDialog(initialValue: savedPlate),
    );
    if (licensePlate == null) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }
    if (!mounted) return;

    final durationHours = await showDialog<int>(
      context: context,
      builder: (_) => DurationPickerDialog(pricePerHour: _spot.pricePerHour),
    );
    if (durationHours == null) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }
    if (!mounted) return;

    final totalCost = _spot.pricePerHour * durationHours;

    // Reserve the spot on the backend as part of the payment confirmation
    // step so a 409 (spot already claimed) is caught BEFORE the success
    // view is rendered — the user sees only the conflict snackbar, never a
    // "Successful payment" screen for a payment that didn't go through.
    final outcome = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          spot: _spot,
          licensePlate: licensePlate,
          durationHours: durationHours,
          totalCost: totalCost,
          authService: widget.authService,
          onConfirm: (_, _) => widget.apiService.reserveSpot(_spot.id),
        ),
      ),
    );
    if (!mounted) return;

    if (outcome == null) {
      setState(() => _isProcessing = false);
      return;
    }

    if (outcome is ApiException) {
      setState(() => _isProcessing = false);
      if (outcome.statusCode == 409) {
        // Spot was just claimed by someone else. Close the stale sheet,
        // tell the user, and refresh the map.
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Местото веќе не е достапно. Средствата се вратени.',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
        widget.onActionComplete();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(outcome.message),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final paymentResult = outcome as PaymentResult;
    Navigator.of(context).pop();

    final shouldRefresh = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReservationScreen(
          spot: _spot,
          apiService: widget.apiService,
          authService: widget.authService,
          licensePlate: licensePlate,
          durationHours: durationHours,
          paidAmount: totalCost,
          paymentMethod: paymentResult.paymentMethod,
          transactionId: paymentResult.transactionId,
          onActiveSessionStarted: widget.onActiveSessionStarted,
        ),
      ),
    );

    if (shouldRefresh == true) {
      widget.onActionComplete();
    }
  }

  Future<void> _handleStartParking() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      await startParkingFlow(
        context: context,
        spot: _spot,
        apiService: widget.apiService,
        authService: widget.authService,
        onComplete: widget.onActionComplete,
        onSessionStarted: widget.onActiveSessionStarted,
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
}

/// Shared prepaid parking flow:
/// 1. License plate dialog
/// 2. Duration picker (1h or 2h)
/// 3. Payment screen (wallet for logged-in, mock for guests)
/// 4. Receipt screen
/// 5. Start parking on backend
/// 6. Navigate to active session
Future<void> startParkingFlow({
  required BuildContext context,
  required ParkingSpot spot,
  required ApiService apiService,
  required AuthService? authService,
  required VoidCallback onComplete,
  bool closeBottomSheet = true,
  bool replacePrevious = false,
  void Function(ActiveSession session)? onSessionStarted,
}) async {
  final savedPlate = authService?.licensePlate;
  final licensePlate = await showDialog<String>(
    context: context,
    builder: (_) => LicensePlateDialog(initialValue: savedPlate),
  );
  if (licensePlate == null || !context.mounted) return;

  final durationHours = await showDialog<int>(
    context: context,
    builder: (_) => DurationPickerDialog(pricePerHour: spot.pricePerHour),
  );
  if (durationHours == null || !context.mounted) return;

  final totalCost = spot.pricePerHour * durationHours;

  // Start the parking session on the backend as part of the payment
  // confirmation step. If the spot was just claimed by another user, the
  // backend returns 409 and the PaymentScreen pops with the exception —
  // the success view never renders, so the user only sees the conflict
  // snackbar.
  ParkingSession? startedSession;
  final outcome = await Navigator.of(context).push<Object>(
    MaterialPageRoute(
      builder: (_) => PaymentScreen(
        spot: spot,
        licensePlate: licensePlate,
        durationHours: durationHours,
        totalCost: totalCost,
        authService: authService,
        onConfirm: (_, _) async {
          startedSession = await apiService.startParking(
            spot.id,
            licensePlate,
            durationHours: durationHours,
          );
        },
      ),
    ),
  );
  if (!context.mounted) return;

  if (outcome == null) return; // user cancelled before paying

  if (outcome is ApiException) {
    if (outcome.statusCode == 409) {
      // Backend rejected the start because another user just claimed the
      // spot. Close the source sheet/screen, surface the conflict, and
      // refresh nearby spots so the user immediately sees the updated
      // state.
      if (closeBottomSheet && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Местото веќе не е достапно'),
          backgroundColor: AppColors.danger,
        ),
      );
      onComplete();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(outcome.message),
        backgroundColor: AppColors.danger,
      ),
    );
    return;
  }

  final paymentResult = outcome as PaymentResult;
  final session = startedSession!;

  // Backend may have deducted wallet balance — refresh cached profile.
  if (authService?.isLoggedIn == true) {
    try {
      await authService!.getProfile();
    } on AuthException {
      // Non-fatal — continue with stale cached balance.
    }
    if (!context.mounted) return;
  }

  // Show receipt for the prepaid amount.
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ReceiptScreen(
        spot: spot,
        licensePlate: licensePlate,
        totalCost: totalCost,
        totalTime: Duration(hours: durationHours),
        paymentMethod: paymentResult.paymentMethod,
        transactionId: paymentResult.transactionId,
      ),
    ),
  );
  if (!context.mounted) return;

  if (closeBottomSheet && Navigator.of(context).canPop()) {
    Navigator.of(context).pop(); // close source (bottom sheet / reservation)
  }

  // Use the backend's session.startTime so the paid duration counts from
  // the moment payment was confirmed (session creation), not from when
  // the user dismisses the receipt.
  final activeSession = ActiveSession(
    spot: spot,
    licensePlate: licensePlate,
    startTime: session.startTime,
    durationHours: session.durationHours ?? durationHours,
    paidAmount: session.paidAmount ?? totalCost,
  );

  if (onSessionStarted != null) {
    onSessionStarted(activeSession);
    onComplete();
    return;
  }

  final route = MaterialPageRoute<ActiveSessionResult>(
    builder: (_) => ActiveSessionScreen(
      spot: spot,
      licensePlate: licensePlate,
      sessionStartTime: activeSession.startTime,
      durationHours: activeSession.durationHours,
      paidAmount: activeSession.paidAmount,
      apiService: apiService,
      authService: authService,
    ),
  );

  if (replacePrevious) {
    await Navigator.of(
      context,
    ).pushReplacement<ActiveSessionResult, ActiveSessionResult>(route);
  } else {
    await Navigator.of(context).push<ActiveSessionResult>(route);
  }

  onComplete();
}
