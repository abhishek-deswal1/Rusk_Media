import 'package:flutter/material.dart';
import 'package:rusk_media/core/constants/app_strings.dart';
import 'package:rusk_media/core/theme/app_colors.dart';
import 'package:rusk_media/core/theme/app_text_styles.dart';
import 'package:rusk_media/core/ui/components/custom_text.dart';

class RetryButton extends StatefulWidget {
  const RetryButton({
    required this.onPressed,
    super.key,
    this.checking = false,
  });

  final VoidCallback onPressed;
  final bool checking;

  @override
  State<RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<RetryButton> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !widget.checking;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: () => _setPressed(false),
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.signalRaised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withOpacity(enabled ? 0.85 : 0.4),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.signalMagenta
                      .withOpacity(_pressed ? 0.8 : 0.55),
                  offset: const Offset(-3, 0),
                  blurRadius: 14,
                ),
                BoxShadow(
                  color: AppColors.signalCyan.withOpacity(_pressed ? 0.8 : 0.5),
                  offset: const Offset(3, 0),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // no stock spinner while checking: the dimmed edge and the
                // label already say it, and the screen itself shows loading
                const SizedBox.square(
                  dimension: 18,
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                CustomText(
                  widget.checking ? AppStrings.checking : AppStrings.retry,
                  semanticLocator: 'retry_button_label',
                  textStyle: AppTextStyles.signalButton,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
