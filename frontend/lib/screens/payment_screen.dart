import 'dart:math';
import 'package:flutter/material.dart';
import '../models/parking_spot.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'receipt_screen.dart';

class PaymentScreen extends StatefulWidget {
  final ParkingSpot spot;
  final String licensePlate;
  final double totalCost;
  final Duration totalTime;
  final AuthService? authService;

  const PaymentScreen({
    super.key,
    required this.spot,
    required this.licensePlate,
    required this.totalCost,
    required this.totalTime,
    this.authService,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with TickerProviderStateMixin {
  int _selectedMethod = 0;
  bool _isProcessing = false;
  bool _isSuccess = false;

  late AnimationController _fadeController;
  late AnimationController _successController;
  late Animation<double> _successScale;

  List<_PaymentMethod> _methods = const [
    _PaymentMethod('Кредитна/Дебитна картичка', Icons.credit_card),
    _PaymentMethod('Apple Pay', Icons.apple),
    _PaymentMethod('Google Pay', Icons.g_mobiledata),
  ];

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

    _maybeLoadSavedCard();
  }

  Future<void> _maybeLoadSavedCard() async {
    final auth = widget.authService;
    if (auth == null || !auth.isLoggedIn) return;
    try {
      final profile = await auth.getProfile();
      final masked = profile['cardNumber']?.toString();
      if (!mounted) return;
      if (masked != null && masked.isNotEmpty) {
        setState(() {
          _methods = [
            _PaymentMethod('Зачувана картичка · $masked', Icons.credit_score),
            ..._methods,
          ];
          _selectedMethod = 0;
        });
      }
    } on Exception {
      // Non-fatal — user can still pay with other methods
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _successController.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    setState(() => _isProcessing = true);

    // Simulated delay
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    setState(() {
      _isProcessing = false;
      _isSuccess = true;
    });
    _successController.forward();

    // Navigate to receipt after animation
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    final txnId = 'TXN-${Random().nextInt(99999999).toString().padLeft(8, '0')}';
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptScreen(
          spot: widget.spot,
          licensePlate: widget.licensePlate,
          totalCost: widget.totalCost,
          totalTime: widget.totalTime,
          paymentMethod: _methods[_selectedMethod].label,
          transactionId: txnId,
        ),
      ),
    );

    Navigator.pop(context, result);
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
        title: const Text(
          'Плаќање',
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
              // Total cost card
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
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Payment methods
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

              ...List.generate(_methods.length, (index) {
                final method = _methods[index];
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
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppColors.accent.withValues(alpha: 0.15),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : [],
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
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
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

              const Spacer(),

              // Pay button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _pay,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: const Text(
                    'Плати сега',
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

  Widget _buildProcessing() {
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
            const Text(
              'Плаќањето е во тек...',
              style: TextStyle(
                fontSize: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ScaleTransition(
          scale: _successScale,
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
              const Text(
                'Успешно плаќање',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
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
