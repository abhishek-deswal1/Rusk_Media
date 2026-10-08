import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rusk_media/core/video_pool/data/video_controller_factory.dart';

import '../../helpers/fake_video_controller.dart';

class _MockCache extends Mock implements BaseCacheManager {}

class _DeadStream extends FakeVideoController {
  _DeadStream(super.url);

  @override
  Future<void> initialize() async => throw Exception('no route');
}

void main() {
  late _MockCache cache;
  late List<String> events;

  Future<FileInfo> onDisk(String url) async => FileInfo(
        await MemoryCacheSystem().createFile(url),
        FileSource.Cache,
        DateTime(2100),
        url,
      );

  CachedVideoControllerFactory build({bool deadStream = false}) =>
      CachedVideoControllerFactory(
        cache,
        stream: (url) {
          events.add('stream ${url.path}');
          return deadStream
              ? _DeadStream(url.toString())
              : _Tracked(url.toString(), events);
        },
        local: (file) {
          events.add('disk');
          return FakeVideoController(file.path);
        },
      );

  setUp(() {
    cache = _MockCache();
    events = [];
    when(() => cache.getFileFromCache(any())).thenAnswer((_) async => null);
    when(() => cache.downloadFile(any())).thenAnswer((call) async {
      final url = call.positionalArguments.first as String;
      events.add('save $url');
      return onDisk(url);
    });
  });

  test('a reel not on disk streams, then is saved once it is playing',
      () async {
    final player = await build().create('ep1');
    await pumpEventQueue();

    expect(player.value.isInitialized, isTrue);
    // the copy only starts after the stream is up, never alongside it
    expect(events, ['stream ep1', 'ready ep1', 'save ep1']);
  });

  test('a reel already on disk plays from it and is not fetched again',
      () async {
    final saved = await onDisk('ep1');
    when(() => cache.getFileFromCache('ep1')).thenAnswer((_) async => saved);

    await build().create('ep1');
    await pumpEventQueue();

    expect(events, ['disk']);
    verifyNever(() => cache.downloadFile(any()));
  });

  test('the same reel streamed twice is saved once', () async {
    final saving = Completer<FileInfo>();
    when(() => cache.downloadFile(any())).thenAnswer((_) {
      events.add('save');
      return saving.future;
    });

    final factory = build();
    await Future.wait([factory.create('ep1'), factory.create('ep1')]);
    await pumpEventQueue();
    expect(events.where((e) => e == 'save'), hasLength(1));

    saving.complete(await onDisk('ep1'));
  });

  test('warm clips download one at a time and a newer window replaces the wait',
      () async {
    final first = Completer<FileInfo>();
    when(() => cache.downloadFile('w1')).thenAnswer((_) {
      events.add('save w1');
      return first.future;
    });

    final factory = build()..prefetch(['w1', 'w2']);
    await pumpEventQueue();
    expect(events, ['save w1']);

    // the viewer flicked on before w1 landed; w2 is no longer ahead of them
    factory.prefetch(['w3', 'w4']);
    await pumpEventQueue();
    expect(events, ['save w1']);

    first.complete(await onDisk('w1'));
    await pumpEventQueue();
    expect(events, ['save w1', 'save w3', 'save w4']);
  });

  test('a warm download that fails does not stall the ones behind it',
      () async {
    when(() => cache.downloadFile('w1')).thenThrow(Exception('offline'));

    build().prefetch(['w1', 'w2']);
    await pumpEventQueue();
    expect(events, ['save w2']);
  });

  test('a clip already being saved after its stream is not fetched twice',
      () async {
    final saving = Completer<FileInfo>();
    when(() => cache.downloadFile('ep1')).thenAnswer((_) {
      events.add('save ep1');
      return saving.future;
    });

    final factory = build();
    await factory.create('ep1');
    factory.prefetch(['ep1']);
    await pumpEventQueue();
    expect(events.where((e) => e == 'save ep1'), hasLength(1));

    saving.complete(await onDisk('ep1'));
  });

  test('an empty window drops whatever was still waiting', () async {
    final first = Completer<FileInfo>();
    when(() => cache.downloadFile('w1')).thenAnswer((_) {
      events.add('save w1');
      return first.future;
    });

    final factory = build()..prefetch(['w1', 'w2']);
    await pumpEventQueue();
    factory.prefetch([]);
    first.complete(await onDisk('w1'));
    await pumpEventQueue();
    expect(events, ['save w1']);
  });

  test('a stream that never starts is not saved', () async {
    await expectLater(build(deadStream: true).create('ep1'), throwsException);
    await pumpEventQueue();
    verifyNever(() => cache.downloadFile(any()));
  });
}

class _Tracked extends FakeVideoController {
  _Tracked(super.url, this.events);

  final List<String> events;

  @override
  Future<void> initialize() async {
    await super.initialize();
    events.add('ready ${Uri.parse(url).path}');
  }
}
