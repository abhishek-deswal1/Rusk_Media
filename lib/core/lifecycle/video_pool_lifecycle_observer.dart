import 'package:flutter/widgets.dart';
import 'package:rusk_media/core/video_pool/presentation/bloc/video_pool_bloc.dart';

// Single owner of app-background pause/resume for the pool. Screens must not
// dispatch VideoPoolAppBackgrounded / VideoPoolAppForegrounded for app
// lifecycle, only for their own surface concerns.
class VideoPoolLifecycleObserver with WidgetsBindingObserver {
  VideoPoolLifecycleObserver(this._pool);

  final VideoPoolBloc _pool;
  bool _away = false;

  void init() => WidgetsBinding.instance.addObserver(this);

  void dispose() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      // inactive is a notification shade or a dialog, keep playing
      case AppLifecycleState.inactive:
        return;
      // android sends inactive -> hidden -> paused as a chain, react once
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (_away) return;
        _away = true;
        _pool.add(const VideoPoolAppBackgrounded());
      case AppLifecycleState.resumed:
        if (!_away) return;
        _away = false;
        _pool.add(const VideoPoolAppForegrounded());
    }
  }
}
