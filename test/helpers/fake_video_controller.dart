import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:rusk_media/core/video_pool/data/video_controller_factory.dart';
import 'package:video_player/video_player.dart';

class FakeVideoController extends VideoPlayerController {
  FakeVideoController(this.url) : super.networkUrl(Uri.parse(url));

  final String url;
  bool disposed = false;
  int pauses = 0;
  double? volume;
  Duration? lastSeek;

  // false plays a slow native seek: asked for, but the position not moved yet
  bool seekLands = true;

  void ready() {
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(seconds: 30),
      size: const Size(720, 1280),
    );
  }

  // what the plugin reports when the stream dies mid-play
  void fail(String reason) => value = value.copyWith(errorDescription: reason);

  // the native side stopped on its own (audio focus lost, buffering)
  void suppress() => value = value.copyWith(isPlaying: false);

  @override
  Future<void> initialize() async => ready();

  @override
  Future<void> play() async => value = value.copyWith(isPlaying: true);

  @override
  Future<void> pause() async {
    pauses++;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    lastSeek = position;
    if (seekLands) value = value.copyWith(position: position);
  }

  @override
  Future<void> setVolume(double volume) async => this.volume = volume;

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

// every create() waits until the test completes or fails it
class FakeControllerFactory implements VideoControllerFactory {
  final List<(String, Completer<VideoPlayerController>)> requests = [];
  final List<List<String>> prefetched = [];

  List<String> get requestedUrls => [for (final (url, _) in requests) url];

  @override
  Future<VideoPlayerController> create(String url) {
    final completer = Completer<VideoPlayerController>();
    requests.add((url, completer));
    return completer.future;
  }

  @override
  void prefetch(List<String> urls) => prefetched.add(urls);

  FakeVideoController complete(int index) {
    final (url, completer) = requests[index];
    final controller = FakeVideoController(url)..ready();
    completer.complete(controller);
    return controller;
  }

  void fail(int index) => requests[index].$2.completeError(Exception('boom'));
}
