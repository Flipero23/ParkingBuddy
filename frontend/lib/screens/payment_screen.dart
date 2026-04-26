import 'dart:math';
import 'package:flutter/material.dart';
import '../models/parking_spot.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'receipt_screen.dart';

/// Upfront payment for a selected parking duration.
/// - Logged-in users pay from their wallet balance.
/// - Guests pay via a mock payment method.
///
/// On success returns a [PaymentResult] via Navigator.pop so the caller
/// (spot bottom sheet / reservation screen) can then start the parking
/// session with the paid [durationHours].
class PaymentResult {
  final String paymentMethod;
  final String transactionId;

  const PaymentResult({
    required this.paymentMethod,
    required this.transactionId,
  });
}

class PaymentScreen extends StatefulWidget {
  final ParkingSpot spot;
  final String licensePlate;
  final int durationHours;
  final double totalCost;
  final AuthService? authService;

  /// When true, the receipt screen is shown after a successful payment.
  /// Used by the extend-session flow where no new session start follows.
  final bool showReceiptOnSuccess;

  const PaymentScreen({
    super.key,
    required this.spot,
    required this.licensePlate,
    required this.durationHours,
    required this.totalCost,
    this.authService,
    this.showReceiptOnSuccess = false,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with TickerProviderStateMixin {
  int _selectedMethod = 0;
  bool _isProcessing = false;
  bool _isSuccess = false;
  String? _errorMessage;

  late AnimationController _fadeController;
  late AnimationController _successController;
  late Animation<double> _successScale;

  // Guest mock methods. Logged-in users use wallet only.
  final List<_PaymentMethod> _guestMethods = const [
    _PaymentMethod('Кредитна/Дебитна картичка', Icons.credit_card),
    _PaymentMethod('Apple Pay', Icons.apple),
    _PaymentMethod('Google Pay', Icons.g_mobiledata),
  ];

  bool get _isLoggedIn => widget.authService?.isLoggedIn == true;

  double get _balance => widget.authService?.balance ?? 0.0;

  bool get _hasSufficientBalance => _balance >= widget.totalCost;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _successScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _successController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _successController.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    if (_isLoggedIn && !_hasSufficientBalance) {
      setState(() {
        _errorMessage =
            'Немате доволно средства во паричникот. Надополнете прво.';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    // Simulated payment delay — no real gateway.
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    setState(() {
      _isProcessing = false;
      _isSuccess = true;
    });
    _successController.forward();

    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    final method = _isLoggedIn
        ? 'Паричник'
        : _guestMethods[_selectedMethod].label;
    final txnId =
        'TXN-${Random().nextInt(99999999).toString().padLeft(8, '0')}';
    final result = PaymentResult(
      paymentMethod: method,
      transactionId: txnId,
    );

    if (widget.showReceiptOnSuccess) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReceiptScreen(
            spot: widget.spot,
            licensePlate: widget.licensePlate,
            totalCost: widget.totalCost,
            totalTime: Duration(hours: widget.durationHours),
            paymentMethod: method,
            transactionId: txnId,
          ),
        ),
      );
      if (!mounted) return;
    }

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    if (_isProcessing) return _buildProcessing();
    if (_isSuccess) return _buildSuccess();

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
          'Плаќање',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        centerTitle: true,
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
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      const Text(
                        'Вкупно за плаќање',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${widget.totalCost.toStringAsFixed(0)} МКД',
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Траење: ${widget.durationHours} ч',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_isLoggedIn) _buildWalletSection() else _buildGuestMethods(),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                _buildErrorBanner(_errorMessage!),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isLoggedIn && !_hasSufficientBalance)
                      ? null
                      : _pay,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    disabledBackgroundColor:
                        AppColors.accent.withValues(alpha: 0.3),
                    disabledForegroundColor: Colors.white60,
                  ),
                  child: Text(
                    _isLoggedIn ? 'Плати од паричник' : 'Плати сега',
                    style: const TextStyle(fontSize: 18),
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

  Widget _buildWalletSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _hasSufficientBalance
              ? AppColors.accent
              : AppColors.danger.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Паричник',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_balance.toStringAsFixed(0)} МКД',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (_hasSufficientBalance)
            const Icon(Icons.check_circle, color: AppColors.accent)
          else
            const Icon(Icons.error_outline, color: AppColors.danger),
        ],
      ),
    );
  }

  Widget _buildGuestMethods() {
    return Column(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Начин на плаќање',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(_guestMethods.length, (index) {
          final method = _guestMethods[index];
          final isSelected = _selectedMethod == index;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => setState(() => _selectedMethod = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.accent
                        : Colors.grey.shade200,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      method.icon,
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.textSecondary,
                      size: 28,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        method.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        Icons.check_circle,
                        color: AppColors.accent,
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessing() {
    return const PaymentProcessingView();
  }

  Widget _buildSuccess() {
    return PaymentSuccessView(scale: _successScale);
  }
}

class PaymentProcessingView extends StatelessWidget {
  final String message;

  const PaymentProcessingView({
    super.key,
    this.message = 'Плаќањето е во тек...',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                color: AppColors.accent,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: const TextStyle(
                fontSize: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PaymentSuccessView extends StatelessWidget {
  final Animation<double> scale;
  final String title;
  final String? subtitle;

  const PaymentSuccessView({
    super.key,
    required this.scale,
    this.title = 'Успешно плаќање',
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ScaleTransition(
          scale: scale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 44,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentMethod {
  final String label;
  final IconData icon;
  const _PaymentMethod(this.label, this.icon);
}
