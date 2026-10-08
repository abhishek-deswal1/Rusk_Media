import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:rusk_media/core/constants/app_strings.dart';
import 'package:rusk_media/core/di/app_di.dart';
import 'package:rusk_media/core/lifecycle/video_pool_lifecycle_observer.dart';
import 'package:rusk_media/core/logger/app_logger.dart';
import 'package:rusk_media/core/theme/app_theme.dart';
import 'package:rusk_media/features/launch/presentation/screens/launch_screen.dart';
import 'package:rusk_media/features/reels/presentation/screens/reels_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // prefs must be ready before any DI getter reads them, and the lifecycle
  // observer needs the pool, so keep this order
  await AppDI.init();
  VideoPoolLifecycleObserver(AppDI.videoPool).init();

  // not awaited: the sdk queues loads until it is ready, and the launch
  // screen gives it a head start before the first slot is asked for. if it
  // can't start, slots just time out and leave the feed
  unawaited(
    MobileAds.instance.initialize().then<void>(
          (_) {},
          onError: (Object e) =>
              AppLogger.logWarning('ads sdk did not start: $e'),
        ),
  );

  // posture is set once here for the whole app: video runs full-bleed under
  // the system bars and every screen keeps its ctas inside SafeArea
  await Future.wait([
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
  ]);

  runApp(const RuskApp());
}

class RuskApp extends StatelessWidget {
  const RuskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: MaterialApp(
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: LaunchScreen(next: (_) => const ReelsScreen()),
      ),
    );
  }
}
