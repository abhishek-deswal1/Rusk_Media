part of 'video_pool_bloc.dart';

sealed class VideoPoolEvent extends BaseEvent {
  const VideoPoolEvent();
}

final class VideoPoolWindowChanged extends VideoPoolEvent {
  const VideoPoolWindowChanged({
    required this.activePage,
    required this.slots,
    this.prefetchUrls = const [],
  });

  final int activePage;
  final List<VideoSlot> slots;
  final List<String> prefetchUrls;

  @override
  List<Object?> get props => [activePage, slots, prefetchUrls];
}

final class VideoPoolRetryRequested extends VideoPoolEvent {
  const VideoPoolRetryRequested(this.page);

  final int page;

  @override
  List<Object?> get props => [page];
}

final class VideoPoolPlaybackToggled extends VideoPoolEvent {
  const VideoPoolPlaybackToggled();
}

// overlays like the paywall or first-run hints hold playback
final class VideoPoolHoldChanged extends VideoPoolEvent {
  const VideoPoolHoldChanged({required this.held});

  final bool held;

  @override
  List<Object?> get props => [held];
}

final class VideoPoolAppBackgrounded extends VideoPoolEvent {
  const VideoPoolAppBackgrounded();
}

final class VideoPoolAppForegrounded extends VideoPoolEvent {
  const VideoPoolAppForegrounded();
}

final class VideoPoolVolumeChanged extends VideoPoolEvent {
  const VideoPoolVolumeChanged(this.volume);

  final double volume;

  @override
  List<Object?> get props => [volume];
}

final class VideoPoolMuteToggled extends VideoPoolEvent {
  const VideoPoolMuteToggled();
}

final class VideoPoolSeekRequested extends VideoPoolEvent {
  const VideoPoolSeekRequested({required this.page, required this.position});

  final int page;
  final Duration position;

  @override
  List<Object?> get props => [page, position];
}
