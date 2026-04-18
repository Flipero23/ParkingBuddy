import 'package:flutter/material.dart';
import '../models/parking_spot.dart';
import '../theme.dart';

class ReceiptScreen extends StatefulWidget {
  final ParkingSpot spot;
  final String licensePlate;
  final double totalCost;
  final Duration totalTime;
  final String paymentMethod;
  final String transactionId;

  const ReceiptScreen({
    super.key,
    required this.spot,
    required this.licensePlate,
    required this.totalCost,
    required this.totalTime,
    required this.paymentMethod,
    required this.transactionId,
  });

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  String get _formattedTime {
    final hours = widget.totalTime.inHours;
    final minutes = widget.totalTime.inMinutes % 60;
    if (hours > 0) {
      return '$hours ч $minutes мин';
    }
    return '$minutes мин';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: _fadeController,
            curve: Curves.easeIn,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),

                // Receipt card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        // Green checkmark
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accent.withValues(alpha: 0.25),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Потврда за плаќање',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Receipt details
                        _receiptRow('Време на паркирање', _formattedTime),
                        _divider(),
                        _receiptRow(
                          'Вкупна цена',
                          '${widget.totalCost.toStringAsFixed(0)} МКД',
                          bold: true,
                        ),
                        _divider(),
                        _receiptRow('Код на паркинг место', widget.spot.code),
                        _divider(),
                        _receiptRow(
                          'Регистарска таблица',
                          widget.licensePlate,
                        ),
                        _divider(),
                        _receiptRow('Начин на плаќање', widget.paymentMethod),
                        _divider(),
                        _receiptRow('ID на трансакција', widget.transactionId),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // Done button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).popUntil(
                        (route) => route.isFirst,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: const Text(
                      'Готово',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: bold ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Divider(height: 1, color: Colors.grey.shade200);
  }
}
