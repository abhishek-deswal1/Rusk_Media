import 'package:rusk_media/core/ads/ad_preloader.dart';
import 'package:rusk_media/core/di/app_di.dart';
import 'package:rusk_media/features/reels/data/repositories/reels_repository_impl.dart';
import 'package:rusk_media/features/reels/data/repositories/tips_repository_impl.dart';
import 'package:rusk_media/features/reels/data/sources/reels_seed_source.dart';
import 'package:rusk_media/features/reels/domain/usecases/load_reels.dart';
import 'package:rusk_media/features/reels/domain/usecases/tips.dart';
import 'package:rusk_media/features/reels/presentation/bloc/engagement_bloc.dart';
import 'package:rusk_media/features/reels/presentation/bloc/onboarding_bloc.dart';
import 'package:rusk_media/features/reels/presentation/bloc/paywall_bloc.dart';
import 'package:rusk_media/features/reels/presentation/bloc/reels_bloc.dart';

// one set of blocs per screen visit; they hold feed position, likes and the
// unlock, and must not outlive it
abstract final class ReelsDI {
  static ReelsBloc makeReelsBloc() {
    const repository = ReelsRepositoryImpl(
      source: ReelsSeedSource(),
      connectivity: AppDI.internetChecker,
    );
    return ReelsBloc(loadReels: const LoadReels(repository));
  }

  // scoped like the bloc: loaded ads belong to one visit of the feed
  static AdPreloader makeAdPreloader() => AdPreloader();

  static EngagementBloc makeEngagementBloc() => EngagementBloc();

  static PaywallBloc makePaywallBloc() => PaywallBloc();

  static OnboardingBloc makeOnboardingBloc() {
    final tips = TipsRepositoryImpl(AppDI.preferences);
    return OnboardingBloc(
      shouldShowTips: ShouldShowTips(tips),
      markTipsSeen: MarkTipsSeen(tips),
    );
  }
}
