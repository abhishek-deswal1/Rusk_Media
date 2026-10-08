import 'dart:async';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:rusk_media/core/logger/app_logger.dart';
import 'package:video_player/video_player.dart';

abstract interface class VideoControllerFactory {
  Future<VideoPlayerController> create(String url);

  // the clips just ahead of the viewer; each call replaces the last list
  void prefetch(List<String> urls);
}

class CachedVideoControllerFactory implements VideoControllerFactory {
  CachedVideoControllerFactory(
    this._cache, {
    VideoPlayerController Function(Uri url)? stream,
    VideoPlayerController Function(File file)? local,
  })  : _stream = stream ?? VideoPlayerController.networkUrl,
        _local = local ?? VideoPlayerController.file;

  final BaseCacheManager _cache;
  final VideoPlayerController Function(Uri url) _stream;
  final VideoPlayerController Function(File file) _local;
  final Set<String> _downloading = {};

  // a download can't be stopped once it starts, so warm clips go one at a
  // time and a flick past them drops the ones still waiting
  final List<String> _warmQueue = [];
  bool _warming = false;

  // play from disk when we already have the file, otherwise stream so the
  // first frame doesn't wait for the whole mp4 to download
  @override
  Future<VideoPlayerController> create(String url) async {
    final cached = await _cache.getFileFromCache(url);
    if (cached != null) {
      try {
        return await _initialize(_local(cached.file));
      } on Object catch (e) {
        AppLogger.logWarning('cached file unplayable, streaming $url: $e');
        await _cache.removeFile(url);
      }
    }
    final streaming = await _initialize(_stream(Uri.parse(url)));
    // keep a copy for the next visit, fetched only once the stream is up so
    // it never competes with the first frame for bandwidth
    unawaited(_download(url));
    return streaming;
  }

  @override
  void prefetch(List<String> urls) {
    _warmQueue
      ..clear()
      ..addAll(urls);
    unawaited(_warmNext());
  }

  Future<void> _warmNext() async {
    if (_warming || _warmQueue.isEmpty) return;
    _warming = true;
    await _download(_warmQueue.removeAt(0));
    _warming = false;
    await _warmNext();
  }

  Future<VideoPlayerController> _initialize(
    VideoPlayerController controller,
  ) async {
    try {
      await controller.initialize();
      return controller;
    } on Object {
      await controller.dispose();
      rethrow;
    }
  }

  Future<void> _download(String url) async {
    if (!_downloading.add(url)) return;
    try {
      if (await _cache.getFileFromCache(url) == null) {
        await _cache.downloadFile(url);
      }
    } on Object catch (e) {
      AppLogger.logWarning('prefetch failed $url: $e');
    } finally {
      _downloading.remove(url);
    }
  }
}
