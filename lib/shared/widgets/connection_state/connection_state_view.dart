import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rusk_media/core/constants/app_images.dart';
import 'package:rusk_media/core/constants/app_strings.dart';
import 'package:rusk_media/core/theme/app_colors.dart';
import 'package:rusk_media/core/theme/app_text_styles.dart';
import 'package:rusk_media/core/ui/components/custom_text.dart';
import 'package:rusk_media/core/ui/components/local_image_widget.dart';
import 'package:rusk_media/shared/widgets/connection_state/glitch_text.dart';
import 'package:rusk_media/shared/widgets/connection_state/glow_background.dart';
import 'package:rusk_media/shared/widgets/connection_state/retry_button.dart';
import 'package:rusk_media/shared/widgets/connection_state/swimming_loader.dart';

enum ConnectionViewMode { loading, offline, error, empty }

// full-screen retro tv state: loading while the feed comes in, no-signal
// art with retry when offline or failed
class ConnectionStateView extends StatefulWidget {
  const ConnectionStateView({
    required this.mode,
    super.key,
    this.isRetrying = false,
    this.onRetry,
  });

  final ConnectionViewMode mode;
  final bool isRetrying;
  final VoidCallback? onRetry;

  @override
  State<ConnectionStateView> createState() => _ConnectionStateViewState();
}

class _ConnectionStateViewState extends State<ConnectionStateView> {
  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    // both states are warmed up so the swap never shows a blank frame
    final width = (MediaQuery.sizeOf(context).width * 0.82).clamp(0.0, 360.0);
    final cacheWidth = (width * MediaQuery.devicePixelRatioOf(context)).round();
    for (final asset in [AppWebpImages.loadingTv, AppWebpImages.noInternet]) {
      unawaited(
        precacheImage(
          ResizeImage(AssetImage(asset), width: cacheWidth),
          context,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = widget.mode == ConnectionViewMode.loading;
    return ColoredBox(
      color: AppColors.signalBase,
      child: GlowBackground(
        primaryGlow: loading ? AppColors.signalGreen : AppColors.signalRed,
        secondaryGlow: AppColors.signalCyan,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    switchInCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.94, end: 1)
                            .animate(animation),
                        child: child,
                      ),
                    ),
                    child: _content(),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: loading
                    ? const SwimmingLoader(key: ValueKey('swimmer'))
                    : const SizedBox(key: ValueKey('none')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    final retry = widget.onRetry == null
        ? null
        : RetryButton(checking: widget.isRetrying, onPressed: widget.onRetry!);

    return switch (widget.mode) {
      ConnectionViewMode.loading => const _StateContent(
          key: ValueKey('loading'),
          image: AppWebpImages.loadingTv,
          imageAspect: 420 / 340,
          heading: GlitchText(
            AppStrings.loadingHeading,
            semanticLocator: 'loading_heading',
            color: AppColors.signalGreen,
            style: AppTextStyles.signalHeading,
          ),
          message: AppStrings.loadingMessage,
        ),
      ConnectionViewMode.offline => _StateContent(
          key: const ValueKey('offline'),
          image: AppWebpImages.noInternet,
          imageAspect: 900 / 600,
          heading: const GlitchText(
            AppStrings.offlineHeading,
            semanticLocator: 'offline_heading',
            style: AppTextStyles.signalHeading,
          ),
          message: AppStrings.offlineMessage,
          action: retry,
        ),
      ConnectionViewMode.error => _StateContent(
          key: const ValueKey('error'),
          image: AppWebpImages.noInternet,
          imageAspect: 900 / 600,
          heading: const GlitchText(
            AppStrings.errorHeading,
            semanticLocator: 'error_heading',
            style: AppTextStyles.signalHeading,
          ),
          message: AppStrings.errorMessage,
          action: retry,
        ),
      ConnectionViewMode.empty => _StateContent(
          key: const ValueKey('empty'),
          image: AppWebpImages.noInternet,
          imageAspect: 900 / 600,
          heading: const GlitchText(
            AppStrings.emptyHeading,
            semanticLocator: 'empty_heading',
            style: AppTextStyles.signalHeading,
          ),
          message: AppStrings.emptyMessage,
          action: retry,
        ),
    };
  }
}

class _StateContent extends StatelessWidget {
  const _StateContent({
    required this.image,
    required this.imageAspect,
    required this.heading,
    required this.message,
    super.key,
    this.action,
  });

  final String image;
  final double imageAspect;
  final Widget heading;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageWidth = (constraints.maxWidth * 0.82).clamp(0.0, 360.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LocalImageWidget(
                asset: image,
                width: imageWidth,
                height: imageWidth / imageAspect,
              ),
              const SizedBox(height: 28),
              heading,
              const SizedBox(height: 12),
              CustomText(
                message,
                semanticLocator: 'connection_state_message',
                textAlign: TextAlign.center,
                textStyle: AppTextStyles.signalBody,
              ),
              if (action != null) ...[
                const SizedBox(height: 32),
                action!,
              ],
            ],
          ),
        );
      },
    );
  }
}
