import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rusk_media/core/lifecycle/video_pool_lifecycle_observer.dart';
import 'package:rusk_media/core/video_pool/presentation/bloc/video_pool_bloc.dart';

class _MockPool extends MockBloc<VideoPoolEvent, VideoPoolState>
    implements VideoPoolBloc {}

void main() {
  late _MockPool pool;
  late VideoPoolLifecycleObserver observer;

  setUpAll(() => registerFallbackValue(const VideoPoolAppBackgrounded()));

  setUp(() {
    pool = _MockPool();
    observer = VideoPoolLifecycleObserver(pool);
  });

  test('a shade or dialog over the app keeps playing', () {
    observer.didChangeAppLifecycleState(AppLifecycleState.inactive);
    verifyNever(() => pool.add(any()));
  });

  test('hidden on its own already counts as away', () {
    observer.didChangeAppLifecycleState(AppLifecycleState.hidden);
    verify(() => pool.add(const VideoPoolAppBackgrounded())).called(1);
  });

  // android sends inactive -> hidden -> paused as a chain
  test('going away pauses once, however many states android sends', () {
    observer
      ..didChangeAppLifecycleState(AppLifecycleState.inactive)
      ..didChangeAppLifecycleState(AppLifecycleState.hidden)
      ..didChangeAppLifecycleState(AppLifecycleState.paused);
    verify(() => pool.add(const VideoPoolAppBackgrounded())).called(1);
    verifyNever(() => pool.add(const VideoPoolAppForegrounded()));
  });

  test('coming back resumes once, and only after going away', () {
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    verifyNever(() => pool.add(any()));

    observer
      ..didChangeAppLifecycleState(AppLifecycleState.paused)
      ..didChangeAppLifecycleState(AppLifecycleState.resumed)
      ..didChangeAppLifecycleState(AppLifecycleState.resumed);
    verify(() => pool.add(const VideoPoolAppForegrounded())).called(1);
  });

  test('a second trip away pauses again', () {
    observer
      ..didChangeAppLifecycleState(AppLifecycleState.paused)
      ..didChangeAppLifecycleState(AppLifecycleState.resumed)
      ..didChangeAppLifecycleState(AppLifecycleState.detached);
    verify(() => pool.add(const VideoPoolAppBackgrounded())).called(2);
  });
}
