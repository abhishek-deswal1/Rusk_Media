import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rusk_media/core/base/base_bloc.dart';
import 'package:rusk_media/core/logger/app_logger.dart';
import 'package:rusk_media/core/platform/system_volume_service.dart';
import 'package:rusk_media/core/video_pool/data/video_controller_factory.dart';
import 'package:rusk_media/core/video_pool/domain/video_slot.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

part 'video_pool_event.dart';
part 'video_pool_state.dart';

typedef AfterFrame = Future<void> Function();
typedef ScreenAwakeSetter = Future<void> Function({required bool enable});

final class _VideoPoolControllerReady extends VideoPoolEvent {
  const _VideoPoolControllerReady(this.page, this.token, this.controller);

  final int page;
  final int token;
  final VideoPlayerController controller;

  @override
  List<Object?> get props => [page, token, controller];
}

final class _VideoPoolSystemVolume extends VideoPoolEvent {
  const _VideoPoolSystemVolume(this.level);

  final double level;

  @override
  List<Object?> get props => [level];
}

final class _VideoPoolControllerFailed extends VideoPoolEvent {
  const _VideoPoolControllerFailed(this.page, this.token, this.error);

  final int page;
  final int token;
  final Object error;

  @override
  List<Object?> get props => [page, token, error];
}

class VideoPoolBloc extends BaseBloc<VideoPoolEvent, VideoPoolState> {
  VideoPoolBloc({
    required VideoControllerFactory controllerFactory,
    AfterFrame? afterFrame,
    ScreenAwakeSetter? setScreenAwake,
    SystemVolumeService? systemVolume,
  })  : _factory = controllerFactory,
        _afterFrame = afterFrame ?? _endOfFrame,
        _setScreenAwake = setScreenAwake ?? _wakelock,
        _systemVolume = systemVolume,
        super(const VideoPoolState()) {
    on<VideoPoolWindowChanged>(_onWindowChanged);
    on<_VideoPoolControllerReady>(_onControllerReady);
    on<_VideoPoolControllerFailed>(_onControllerFailed);
    on<VideoPoolRetryRequested>(_onRetryRequested);
    on<VideoPoolPlaybackToggled>(_onPlaybackToggled);
    on<VideoPoolHoldChanged>(_onHoldChanged);
    on<VideoPoolAppBackgrounded>(_onAppBackgrounded);
    on<VideoPoolAppForegrounded>(_onAppForegrounded);
    on<VideoPoolVolumeChanged>(_onVolumeChanged);
    on<VideoPoolMuteToggled>(_onMuteToggled);
    on<VideoPoolSeekRequested>(_onSeekRequested);
    on<_VideoPoolSystemVolume>(_onSystemVolume);

    if (systemVolume != null) {
      _systemChanges = systemVolume.changes
          .listen((level) => add(_VideoPoolSystemVolume(level)));
      unawaited(
        systemVolume.read().then((level) {
          if (level != null) add(_VideoPoolSystemVolume(level));
        }),
      );
    }
  }

  // set once the phone answers; until then, and on platforms that never
  // do, the hold gesture moves the app's own volume as before
  final SystemVolumeService? _systemVolume;
  StreamSubscription<double>? _systemChanges;
  bool _followsSystem = false;
  double _systemLevelBeforeSilence = 0.5;

  double get _playerVolume =>
      _followsSystem ? (state.muted ? 0 : 1) : state.volume;

  final VideoControllerFactory _factory;
  final AfterFrame _afterFrame;
  final ScreenAwakeSetter _setScreenAwake;

  final Map<int, String> _slots = {};

  // one token per in-flight load; a result whose token no longer matches
  // belongs to a page that left the window (or was re-requested) and is dropped
  final Map<int, int> _tokens = {};
  int _nextToken = 0;

  // an initialize can't be called off once started and holds a decoder the
  // whole time, so neighbours wait for a turn; the focused page never waits.
  // a page that leaves while still waiting is simply never started
  static const int _maxLoading = 2;
  final Set<int> _loadingTokens = {};
  final List<int> _waiting = [];

  double _volumeBeforeMute = 1;
  bool _screenAwake = false;

  static Future<void> _endOfFrame() => WidgetsBinding.instance.endOfFrame;

  static Future<void> _wakelock({required bool enable}) =>
      WakelockPlus.toggle(enable: enable);

  void _onWindowChanged(
    VideoPoolWindowChanged event,
    Emitter<VideoPoolState> emit,
  ) {
    final wanted = {for (final slot in event.slots) slot.page: slot.url};
    final controllers = Map.of(state.controllers);
    final loading = Set.of(state.loading);
    final failed = Set.of(state.failed);
    final stale = <VideoPlayerController>[];

    for (final page in _slots.keys.toList()) {
      if (wanted[page] == _slots[page]) continue;
      _slots.remove(page);
      // its load still lands and is thrown away, but it no longer holds a
      // turn the pages around the viewer need
      _loadingTokens.remove(_tokens.remove(page));
      loading.remove(page);
      failed.remove(page);
      final controller = controllers.remove(page);
      if (controller != null) stale.add(controller);
    }
    _waiting.removeWhere((page) => !_slots.containsKey(page));
    if (_waiting.remove(event.activePage)) {
      _request(event.activePage, _slots[event.activePage]!);
    }

    final activeChanged = event.activePage != state.activePage;
    if (activeChanged) {
      final next = controllers[event.activePage];
      if (next != null && next.value.position > Duration.zero) {
        unawaited(next.seekTo(Duration.zero));
      }
    }

    // the reel ahead first: that is where the next swipe usually goes
    final order = [
      if (wanted.containsKey(event.activePage)) event.activePage,
      ...wanted.keys.where((page) => page > event.activePage),
      ...wanted.keys.where((page) => page < event.activePage),
    ];
    for (final page in order) {
      final url = wanted[page]!;
      _slots[page] = url;
      if (controllers.containsKey(page) ||
          loading.contains(page) ||
          failed.contains(page)) {
        continue;
      }
      loading.add(page);
      if (page == event.activePage) {
        _request(page, url);
      } else {
        _waiting.add(page);
      }
    }
    _startWaiting();

    emit(
      state.copyWith(
        controllers: controllers,
        loading: loading,
        failed: failed,
        activePage: event.activePage,
        userPaused: !activeChanged && state.userPaused,
        // a neighbour can finish loading before it becomes the active page,
        // in which case no ready event will ever arrive for it as active
        hasStarted:
            state.hasStarted || controllers.containsKey(event.activePage),
      ),
    );
    _applyPlayback();

    _factory.prefetch(event.prefetchUrls);
    if (stale.isNotEmpty) _disposeAfterFrame(stale);
  }

  void _onControllerReady(
    _VideoPoolControllerReady event,
    Emitter<VideoPoolState> emit,
  ) {
    _loadSettled(event.token);
    if (_tokens[event.page] != event.token) {
      unawaited(event.controller.dispose());
      return;
    }
    final controller = event.controller;
    unawaited(controller.setLooping(true));
    unawaited(controller.setVolume(_playerVolume));
    _watchForErrors(event.page, event.token, controller);

    emit(
      state.copyWith(
        controllers: {...state.controllers, event.page: controller},
        loading: {...state.loading}..remove(event.page),
        hasStarted: state.hasStarted || event.page == state.activePage,
      ),
    );
    _applyPlayback();
  }

  void _onControllerFailed(
    _VideoPoolControllerFailed event,
    Emitter<VideoPoolState> emit,
  ) {
    _loadSettled(event.token);
    if (_tokens[event.page] != event.token) return;
    AppLogger.logError('video load failed on page ${event.page}', event.error);
    // a player can also die after it was ready; it leaves so the page shows
    // its retry card and a revisit asks for a fresh one
    final dead = state.controllers[event.page];
    emit(
      state.copyWith(
        controllers: {...state.controllers}..remove(event.page),
        loading: {...state.loading}..remove(event.page),
        failed: {...state.failed, event.page},
      ),
    );
    if (dead != null) {
      _disposeAfterFrame([dead]);
      _applyPlayback();
    }
  }

  void _onRetryRequested(
    VideoPoolRetryRequested event,
    Emitter<VideoPoolState> emit,
  ) {
    final url = _slots[event.page];
    if (url == null || !state.failed.contains(event.page)) return;
    _request(event.page, url);
    emit(
      state.copyWith(
        failed: {...state.failed}..remove(event.page),
        loading: {...state.loading, event.page},
      ),
    );
  }

  void _onPlaybackToggled(
    VideoPoolPlaybackToggled event,
    Emitter<VideoPoolState> emit,
  ) {
    if (state.controllers[state.activePage] == null) return;
    emit(state.copyWith(userPaused: !state.userPaused));
    _applyPlayback();
  }

  void _onHoldChanged(
    VideoPoolHoldChanged event,
    Emitter<VideoPoolState> emit,
  ) {
    emit(state.copyWith(held: event.held));
    _applyPlayback();
  }

  void _onAppBackgrounded(
    VideoPoolAppBackgrounded event,
    Emitter<VideoPoolState> emit,
  ) {
    emit(state.copyWith(backgrounded: true));
    _applyPlayback();
  }

  void _onAppForegrounded(
    VideoPoolAppForegrounded event,
    Emitter<VideoPoolState> emit,
  ) {
    emit(state.copyWith(backgrounded: false));
    _applyPlayback();
  }

  void _onVolumeChanged(
    VideoPoolVolumeChanged event,
    Emitter<VideoPoolState> emit,
  ) {
    final volume = event.volume.clamp(0.0, 1.0);
    if (_followsSystem) {
      unawaited(_systemVolume!.set(volume).then(_phoneTook));
      // turning it up is a clear sign they want to hear it
      final unmute = state.muted && volume > state.volume;
      emit(state.copyWith(volume: volume, muted: unmute ? false : null));
      if (unmute) _applyPlayerVolume();
      return;
    }
    if (volume > 0) _volumeBeforeMute = volume;
    _emitVolume(volume, emit);
  }

  void _onSystemVolume(
    _VideoPoolSystemVolume event,
    Emitter<VideoPoolState> emit,
  ) {
    final level = event.level.clamp(0.0, 1.0);
    if (level > 0) _systemLevelBeforeSilence = level;
    final first = !_followsSystem;
    _followsSystem = true;
    emit(state.copyWith(volume: level));
    // players drop the app volume they had and play at full under the phone's
    if (first) _applyPlayerVolume();
  }

  // the phone snaps to its own steps, or refuses under do not disturb; the
  // meter's next start follows what it really took
  void _phoneTook(double? level) {
    if (level != null) add(_VideoPoolSystemVolume(level));
  }

  void _applyPlayerVolume() {
    for (final controller in state.controllers.values) {
      unawaited(controller.setVolume(_playerVolume));
    }
  }

  void _onMuteToggled(
    VideoPoolMuteToggled event,
    Emitter<VideoPoolState> emit,
  ) {
    if (_followsSystem) {
      final muted = !state.isMuted;
      if (!muted && state.volume == 0) {
        // the phone itself was silent; bring back the level it last had
        unawaited(
          _systemVolume!.set(_systemLevelBeforeSilence).then(_phoneTook),
        );
        emit(state.copyWith(volume: _systemLevelBeforeSilence));
      }
      emit(state.copyWith(muted: muted));
      _applyPlayerVolume();
      return;
    }
    if (state.isMuted) {
      _emitVolume(_volumeBeforeMute, emit);
    } else {
      _volumeBeforeMute = state.volume;
      _emitVolume(0, emit);
    }
  }

  void _onSeekRequested(
    VideoPoolSeekRequested event,
    Emitter<VideoPoolState> emit,
  ) {
    final controller = state.controllers[event.page];
    if (controller == null) return;
    final duration = controller.value.duration;
    final target = event.position < Duration.zero
        ? Duration.zero
        : (event.position > duration ? duration : event.position);
    unawaited(controller.seekTo(target));
  }

  void _emitVolume(double volume, Emitter<VideoPoolState> emit) {
    if (volume == state.volume) return;
    for (final controller in state.controllers.values) {
      unawaited(controller.setVolume(volume));
    }
    emit(state.copyWith(volume: volume));
  }

  // a player that dies after it was ready reports here too; its token is
  // long gone from the set, so it frees nothing
  void _loadSettled(int token) {
    if (_loadingTokens.remove(token)) _startWaiting();
  }

  void _startWaiting() {
    while (_loadingTokens.length < _maxLoading && _waiting.isNotEmpty) {
      final page = _waiting.removeAt(0);
      _request(page, _slots[page]!);
    }
  }

  void _request(int page, String url) {
    final token = ++_nextToken;
    _tokens[page] = token;
    _loadingTokens.add(token);
    unawaited(
      _factory.create(url).then(
        (controller) {
          if (isClosed) {
            unawaited(controller.dispose());
            return;
          }
          add(_VideoPoolControllerReady(page, token, controller));
        },
        onError: (Object error) =>
            add(_VideoPoolControllerFailed(page, token, error)),
      ),
    );
  }

  // the stream can die after initialize; the plugin only flips the value, so
  // nothing else would ever notice
  void _watchForErrors(int page, int token, VideoPlayerController controller) {
    void onChange() {
      if (!controller.value.hasError) return;
      controller.removeListener(onChange);
      add(
        _VideoPoolControllerFailed(
          page,
          token,
          controller.value.errorDescription ?? 'player error',
        ),
      );
    }

    controller.addListener(onChange);
    // it may have died between initialize finishing and this handler running
    onChange();
  }

  // pause is never gated on isPlaying: exoplayer reports stopped while it
  // waits on audio focus or a buffer, yet resumes by itself afterwards, so a
  // gated pause here would let a reel play on in the background
  void _applyPlayback() {
    final active = state.controllers[state.activePage];
    for (final controller in state.controllers.values) {
      if (controller != active) unawaited(controller.pause());
    }

    final play = active != null && state.shouldPlay;
    if (active != null) {
      if (!play) {
        unawaited(active.pause());
      } else if (!active.value.isPlaying) {
        unawaited(active.play());
      }
    }
    _updateScreenAwake(play);
  }

  void _updateScreenAwake(bool awake) {
    if (awake == _screenAwake) return;
    _screenAwake = awake;
    unawaited(
      _setScreenAwake(enable: awake).catchError(
        (Object e) => AppLogger.logWarning('wakelock failed: $e'),
      ),
    );
  }

  // the item widgets still hold these controllers until the next frame
  // rebuilds them out, so disposing right away would hit a dead controller
  void _disposeAfterFrame(List<VideoPlayerController> controllers) {
    unawaited(
      _afterFrame().then((_) {
        for (final controller in controllers) {
          unawaited(controller.dispose());
        }
      }),
    );
  }

  @override
  Future<void> close() async {
    await _systemChanges?.cancel();
    _tokens.clear();
    _updateScreenAwake(false);
    final controllers = state.controllers.values.toList();
    await super.close();
    for (final controller in controllers) {
      await controller.dispose();
    }
  }
}
