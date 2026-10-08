import 'package:flutter/material.dart';
import 'package:rusk_media/core/theme/app_text_styles.dart';
import 'package:rusk_media/core/ui/components/custom_text.dart';
import 'package:rusk_media/features/reels/domain/entities/reel.dart';

class ReelInfoPanel extends StatelessWidget {
  const ReelInfoPanel({required this.reel, super.key});

  final Reel reel;

  static const _shade = [Shadow(blurRadius: 8, color: Colors.black54)];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomText(
          reel.handle,
          semanticLocator: 'reel_handle',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textStyle: AppTextStyles.handle.copyWith(shadows: _shade),
        ),
        const SizedBox(height: 6),
        // ellipsis cuts on whole graphemes, emoji stay intact
        CustomText(
          reel.caption,
          semanticLocator: 'reel_caption',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textStyle: AppTextStyles.body.copyWith(shadows: _shade),
        ),
      ],
    );
  }
}
