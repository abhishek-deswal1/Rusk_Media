import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rusk_media/core/constants/app_strings.dart';
import 'package:rusk_media/core/theme/app_colors.dart';
import 'package:rusk_media/core/theme/app_text_styles.dart';
import 'package:rusk_media/core/ui/components/custom_text.dart';
import 'package:rusk_media/core/ui/components/network_image_widget.dart';
import 'package:rusk_media/features/reels/domain/entities/reel.dart';
import 'package:rusk_media/features/reels/presentation/bloc/engagement_bloc.dart';

// frosted column on the right: creator, like, comment, share
class ReelActionRail extends StatelessWidget {
  const ReelActionRail({required this.reel, super.key});

  final Reel reel;

  void _soon(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1800),
          content: CustomText(
            message,
            semanticLocator: 'rail_soon',
            textStyle: AppTextStyles.body,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CreatorBadge(reel: reel),
          const SizedBox(height: 10),
          BlocSelector<EngagementBloc, EngagementState, bool>(
            selector: (s) => s.liked.contains(reel.id),
            builder: (context, liked) => _RailButton(
              icon: liked ? Icons.favorite_rounded : Icons.favorite_outline,
              tint: liked ? AppColors.rose : AppColors.textPrimary,
              value: reel.stats.likes + (liked ? 1 : 0),
              locator: 'rail_likes',
              popOnChange: liked,
              onTap: () =>
                  context.read<EngagementBloc>().add(ReelLikeToggled(reel.id)),
            ),
          ),
          _RailButton(
            icon: Icons.chat_bubble_outline_rounded,
            value: reel.stats.comments,
            locator: 'rail_comments',
            onTap: () => _soon(context, AppStrings.commentsSoon),
          ),
          _RailButton(
            icon: Icons.ios_share_rounded,
            value: reel.stats.shares,
            locator: 'rail_shares',
            onTap: () => _soon(context, AppStrings.sharingSoon),
          ),
        ],
      ),
    );
  }
}

class _CreatorBadge extends StatelessWidget {
  const _CreatorBadge({required this.reel});

  final Reel reel;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<EngagementBloc, EngagementState, bool>(
      selector: (s) => s.following.contains(reel.handle),
      builder: (context, following) {
        return Semantics(
          button: true,
          label: following ? AppStrings.following : AppStrings.follow,
          child: GestureDetector(
            onTap: () => context
                .read<EngagementBloc>()
                .add(CreatorFollowToggled(reel.handle)),
            child: SizedBox(
              width: 46,
              height: 54,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: NetworkImageWidget(url: reel.avatarUrl, size: 44),
                  ),
                  Positioned(
                    bottom: 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: following ? AppColors.teal : AppColors.lime,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.ink, width: 2),
                      ),
                      child: Icon(
                        following ? Icons.check_rounded : Icons.add_rounded,
                        size: 13,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.value,
    required this.locator,
    required this.onTap,
    this.tint = AppColors.textPrimary,
    this.popOnChange = false,
  });

  final IconData icon;
  final int value;
  final String locator;
  final VoidCallback onTap;
  final Color tint;
  final bool popOnChange;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            children: [
              TweenAnimationBuilder<double>(
                key: ValueKey(popOnChange),
                tween: Tween(begin: popOnChange ? 0.6 : 1, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Icon(icon, size: 28, color: tint),
              ),
              const SizedBox(height: 3),
              CustomText(
                shortCount(value),
                semanticLocator: locator,
                textStyle: AppTextStyles.count,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String shortCount(int n) {
  if (n < 1000) return '$n';
  final (scaled, unit) = n < 1000000 ? (n / 1000, 'k') : (n / 1000000, 'm');
  final fixed =
      scaled >= 10 ? scaled.round().toString() : scaled.toStringAsFixed(1);
  final trimmed =
      fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  return '$trimmed$unit';
}
