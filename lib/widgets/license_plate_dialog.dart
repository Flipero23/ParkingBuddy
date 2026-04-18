import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

class LicensePlateDialog extends StatefulWidget {
  const LicensePlateDialog({super.key});

  @override
  State<LicensePlateDialog> createState() => _LicensePlateDialogState();
}

class _LicensePlateDialogState extends State<LicensePlateDialog> {
  final _controller = TextEditingController();
  bool _isMacedonian = true;
  String? _errorText;

  static const _validCityCodes = {
    'BE', 'BT', 'DB', 'DE', 'DH', 'DK', 'GE', 'GV',
    'KA', 'KI', 'KO', 'KR', 'KP', 'KS', 'KU',
    'MB', 'MK', 'NE', 'OH', 'PP', 'PE', 'PS',
    'RA', 'RE', 'SK', 'SN', 'SR', 'ST', 'SU',
    'TE', 'VA', 'VE', 'VI', 'VV',
  };

  static final _mkPlateRegex = RegExp(
    r'^([A-Z]{2})(\d{3,4})([A-Z]{2})$',
  );

  bool get _isValid {
    final text = _controller.text.trim();
    if (text.isEmpty) return false;
    if (!_isMacedonian) return text.length >= 2;

    final match = _mkPlateRegex.firstMatch(text);
    if (match == null) return false;
    return _validCityCodes.contains(match.group(1));
  }

  void _validate() {
    final text = _controller.text.trim();
    if (!_isMacedonian || text.isEmpty) {
      setState(() => _errorText = null);
      return;
    }

    final match = _mkPlateRegex.firstMatch(text);
    if (match == null || !_validCityCodes.contains(match.group(1))) {
      setState(() => _errorText = 'Невалидна регистарска таблица');
    } else {
      setState(() => _errorText = null);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Регистарска таблица',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),

            // Toggle
            Container(
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _isMacedonian = true;
                        _errorText = null;
                        _validate();
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _isMacedonian
                              ? AppColors.accent
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Македонска таблица',
                          style: TextStyle(
                            color: _isMacedonian
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _isMacedonian = false;
                        _errorText = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !_isMacedonian
                              ? AppColors.accent
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Странска таблица',
                          style: TextStyle(
                            color: !_isMacedonian
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Input field
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                UpperCaseTextFormatter(),
                if (!_isMacedonian)
                  LengthLimitingTextInputFormatter(12),
              ],
              onChanged: (_) {
                _validate();
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: _isMacedonian ? 'пр. SK1234BN' : 'Внеси таблица',
                prefixIcon: Icon(
                  _isMacedonian ? Icons.directions_car : Icons.flag,
                  color: AppColors.accent,
                ),
                errorText: _errorText,
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.accent, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.danger, width: 1),
                ),
              ),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),

            if (!_isMacedonian) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.flag, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Странска таблица',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Confirm button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isValid
                    ? () => Navigator.of(context).pop(_controller.text.trim())
                    : null,
                style: ElevatedButton.styleFrom(
                  disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.3),
                  disabledForegroundColor: Colors.white60,
                ),
                child: const Text('Потврди'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
