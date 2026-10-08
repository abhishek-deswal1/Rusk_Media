import 'package:flutter/material.dart';
import 'package:rusk_media/core/constants/app_strings.dart';
import 'package:rusk_media/core/theme/app_colors.dart';
import 'package:rusk_media/core/theme/app_text_styles.dart';
import 'package:rusk_media/core/ui/components/custom_text.dart';

class TipsSheet extends StatelessWidget {
  const TipsSheet({required this.onDone, super.key});

  final VoidCallback onDone;

  static const List<String> _tips = [
    AppStrings.tipPause,
    AppStrings.tipLike,
    AppStrings.tipVolume,
    AppStrings.tipTimeline,
    AppStrings.tipProgress,
    AppStrings.tipScroll,
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0x99000000),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: AppColors.inkRaised,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(
                    AppStrings.tipsTitle,
                    semanticLocator: 'tips_title',
                    textStyle: AppTextStyles.heading,
                  ),
                  const SizedBox(height: 18),
                  for (var i = 0; i < _tips.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.lime,
                              shape: BoxShape.circle,
                            ),
                            child: CustomText(
                              '${i + 1}',
                              semanticLocator: 'tip_number',
                              textStyle: AppTextStyles.count.copyWith(
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CustomText(
                              _tips[i],
                              semanticLocator: 'tip_text',
                              textStyle: AppTextStyles.body,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Semantics(
                    button: true,
                    child: GestureDetector(
                      onTap: onDone,
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.lime,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: CustomText(
                          AppStrings.tipsCta,
                          semanticLocator: 'tips_cta',
                          textStyle: AppTextStyles.cta,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
