part of 'video_pool_bloc.dart';

class VideoPoolState extends BaseState {
  const VideoPoolState({
    this.controllers = const {},
    this.loading = const {},
    this.failed = const {},
    this.activePage,
    this.userPaused = false,
    this.backgrounded = false,
    this.held = false,
    this.volume = 1,
    this.hasStarted = false,
  });

  // only initialised controllers live here, keyed by page index
  final Map<int, VideoPlayerController> controllers;
  final Set<int> loading;
  final Set<int> failed;
  final int? activePage;
  final bool userPaused;
  final bool backgrounded;
  final bool held;
  final double volume;

  // flips once the first active video is ready, drives the startup screen
  final bool hasStarted;

  bool get shouldPlay => !userPaused && !backgrounded && !held;

  bool get isMuted => volume == 0;

  VideoPoolState copyWith({
    Map<int, VideoPlayerController>? controllers,
    Set<int>? loading,
    Set<int>? failed,
    int? activePage,
    bool? userPaused,
    bool? backgrounded,
    bool? held,
    double? volume,
    bool? hasStarted,
  }) {
    return VideoPoolState(
      controllers: controllers ?? this.controllers,
      loading: loading ?? this.loading,
      failed: failed ?? this.failed,
      activePage: activePage ?? this.activePage,
      userPaused: userPaused ?? this.userPaused,
      backgrounded: backgrounded ?? this.backgrounded,
      held: held ?? this.held,
      volume: volume ?? this.volume,
      hasStarted: hasStarted ?? this.hasStarted,
    );
  }

  @override
  List<Object?> get props => [
        controllers,
        loading,
        failed,
        activePage,
        userPaused,
        backgrounded,
        held,
        volume,
        hasStarted,
      ];
}
