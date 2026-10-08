import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:rusk_media/core/network/internet_checker.dart';
import 'package:rusk_media/core/video_pool/data/video_controller_factory.dart';
import 'package:rusk_media/core/video_pool/presentation/bloc/video_pool_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class AppDI {
  static late final SharedPreferences preferences;

  static Future<void> init() async {
    preferences = await SharedPreferences.getInstance();
  }

  static const InternetChecker internetChecker = InternetChecker();

  static final BaseCacheManager videoCache = CacheManager(
    Config(
      'reels_media',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 40,
    ),
  );

  // app lifetime on purpose: one owner for every player controller
  static final VideoPoolBloc videoPool = VideoPoolBloc(
    controllerFactory: CachedVideoControllerFactory(videoCache),
  );
}
