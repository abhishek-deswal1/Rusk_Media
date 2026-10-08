import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rusk_media/core/constants/app_strings.dart';
import 'package:rusk_media/core/theme/app_colors.dart';
import 'package:rusk_media/core/theme/app_text_styles.dart';
import 'package:rusk_media/core/ui/components/custom_text.dart';
import 'package:rusk_media/core/video_pool/presentation/bloc/video_pool_bloc.dart';
import 'package:rusk_media/shared/widgets/connection_state/connection_state_view.dart';
import 'package:video_player/video_player.dart';

typedef _Slot = ({VideoPlayerController? player, bool failed, bool animate});

class ReelSurface extends StatelessWidget {
  const ReelSurface({required this.page, super.key});

  final int page;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<VideoPoolBloc, VideoPoolState, _Slot>(
      selector: (pool) => (
        player: pool.controllers[page],
        failed: pool.failed.contains(page),
        // neighbours are built offscreen, and until the first reel starts
        // the full-screen cover already sits on top, so only animate then
        animate: pool.hasStarted &&
            pool.activePage == page &&
            !pool.controllers.containsKey(page),
      ),
      builder: (context, slot) {
        final player = slot.player;
        // buffering mid-play is shown by the bottom bar (ReelProgressBar)
        if (player != null) {
          return ColoredBox(
            color: AppColors.ink,
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox.fromSize(
                size: player.value.size,
                child: VideoPlayer(player),
              ),
            ),
          );
        }
        if (slot.failed) {
          return _LoadFailed(
            onRetry: () => context
                .read<VideoPoolBloc>()
                .add(VideoPoolRetryRequested(page)),
          );
        }
        return TickerMode(
          enabled: slot.animate,
          child: const ConnectionStateView(mode: ConnectionViewMode.loading),
        );
      },
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.ink,
      child: Center(
        child: GestureDetector(
          onTap: onRetry,
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            decoration: BoxDecoration(
              color: AppColors.inkRaised,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.inkLine),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: AppColors.lime,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.replay_rounded,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomText(
                        AppStrings.reelFailed,
                        semanticLocator: 'reel_failed_title',
                        textStyle: AppTextStyles.handle,
                      ),
                      const SizedBox(height: 2),
                      CustomText(
                        AppStrings.reelRetry,
                        semanticLocator: 'reel_failed_retry',
                        textStyle: AppTextStyles.muted,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
