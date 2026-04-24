import 'package:flutter/material.dart';
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

class SpotBottomSheet extends StatelessWidget {
  final ParkingSpot spot;
  final ApiService apiService;
  final AuthService? authService;
  final VoidCallback onActionComplete;

  const SpotBottomSheet({
    super.key,
    required this.spot,
    required this.apiService,
    required this.onActionComplete,
    this.authService,
  });

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
                  spot.code,
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
              spot.streetName,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildInfoItem(Icons.location_on_outlined, 'Зона', spot.zone),
              _buildInfoItem(
                Icons.straighten,
                'Растојание',
                '${spot.distance.toStringAsFixed(0)} м',
              ),
              _buildInfoItem(
                Icons.attach_money,
                'Цена по час',
                '${spot.pricePerHour.toStringAsFixed(0)} МКД',
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
              'Максимално траење: ${spot.maxDurationMinutes} мин',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          if (spot.isAvailable) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _handleReserve(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: AppColors.warning, width: 2),
                      foregroundColor: AppColors.warning,
                    ),
                    child: const Text('Резервирај'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _handleStartParking(context),
                    child: const Text('Започни паркирање'),
                  ),
                ),
              ],
            ),
          ] else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: spot.isReserved
                    ? AppColors.warning.withValues(alpha: 0.1)
                    : AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                spot.isReserved ? 'Резервирано' : 'Зафатено',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: spot.isReserved ? AppColors.warning : AppColors.danger,
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
    if (spot.isAvailable) {
      color = AppColors.accent;
      label = 'Слободно';
    } else if (spot.isReserved) {
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

  Future<void> _handleReserve(BuildContext context) async {
    try {
      await apiService.reserveSpot(spot.id);
      if (!context.mounted) return;

      Navigator.of(context).pop();

      final shouldRefresh = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ReservationScreen(
            spot: spot,
            apiService: apiService,
            authService: authService,
          ),
        ),
      );

      if (shouldRefresh == true) {
        onActionComplete();
      }
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _handleStartParking(BuildContext context) async {
    await startParkingFlow(
      context: context,
      spot: spot,
      apiService: apiService,
      authService: authService,
      onComplete: () {
        onActionComplete();
      },
    );
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
}) async {
  final licensePlate = await showDialog<String>(
    context: context,
    builder: (_) => const LicensePlateDialog(),
  );
  if (licensePlate == null || !context.mounted) return;

  final durationHours = await showDialog<int>(
    context: context,
    builder: (_) => DurationPickerDialog(pricePerHour: spot.pricePerHour),
  );
  if (durationHours == null || !context.mounted) return;

  final totalCost = spot.pricePerHour * durationHours;

  final paymentResult = await Navigator.of(context).push<PaymentResult>(
    MaterialPageRoute(
      builder: (_) => PaymentScreen(
        spot: spot,
        licensePlate: licensePlate,
        durationHours: durationHours,
        totalCost: totalCost,
        authService: authService,
      ),
    ),
  );
  if (paymentResult == null || !context.mounted) return;

  try {
    final session = await apiService.startParking(
      spot.id,
      licensePlate,
      durationHours: durationHours,
    );
    if (!context.mounted) return;

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

    final route = MaterialPageRoute<bool>(
      builder: (_) => ActiveSessionScreen(
        spot: spot,
        licensePlate: licensePlate,
        sessionStartTime: session.startTime,
        durationHours: session.durationHours ?? durationHours,
        paidAmount: session.paidAmount ?? totalCost,
        apiService: apiService,
        authService: authService,
      ),
    );

    final shouldRefresh = replacePrevious
        ? await Navigator.of(context).pushReplacement<bool, bool>(route)
        : await Navigator.of(context).push<bool>(route);

    onComplete();
    // shouldRefresh is currently informational — listeners always refresh.
    if (shouldRefresh == false) return;
  } on ApiException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
    );
  }
}
