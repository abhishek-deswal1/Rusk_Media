import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rusk_media/core/constants/app_strings.dart';
import 'package:rusk_media/core/theme/app_colors.dart';
import 'package:rusk_media/core/theme/app_text_styles.dart';
import 'package:rusk_media/core/ui/components/custom_text.dart';
import 'package:rusk_media/core/video_pool/presentation/bloc/video_pool_bloc.dart';

class ReelsTopBar extends StatelessWidget {
  const ReelsTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 14, 0),
      child: Row(
        children: [
          CustomText(
            AppStrings.wordmark,
            semanticLocator: 'top_bar_wordmark',
            textStyle: AppTextStyles.wordmark.copyWith(
              shadows: const [Shadow(blurRadius: 10, color: Colors.black54)],
            ),
          ),
          const Spacer(),
          const _SoundToggle(),
        ],
      ),
    );
  }
}

class _SoundToggle extends StatelessWidget {
  const _SoundToggle();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<VideoPoolBloc, VideoPoolState, bool>(
      selector: (pool) => pool.isMuted,
      builder: (context, muted) {
        return Semantics(
          button: true,
          label: muted ? 'Sound on' : 'Sound off',
          child: GestureDetector(
            onTap: () =>
                context.read<VideoPoolBloc>().add(const VideoPoolMuteToggled()),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: muted ? AppColors.lime : AppColors.glass,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                muted ? Icons.volume_off_rounded : Icons.graphic_eq_rounded,
                size: 18,
                color: muted ? AppColors.ink : AppColors.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }
}
