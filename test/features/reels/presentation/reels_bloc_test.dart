import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rusk_media/core/communication/response_classes/use_case_response.dart';
import 'package:rusk_media/features/reels/domain/entities/feed_item.dart';
import 'package:rusk_media/features/reels/domain/entities/reel.dart';
import 'package:rusk_media/features/reels/domain/entities/reel_batch.dart';
import 'package:rusk_media/features/reels/domain/usecases/load_reels.dart';
import 'package:rusk_media/features/reels/presentation/bloc/reels_bloc.dart';

class _MockLoadReels extends Mock implements LoadReels {}

Reel _reel(String id) => Reel(
      id: id,
      handle: 'h_$id',
      caption: '',
      streamUrl: 'https://x/$id.mp4',
      avatarUrl: '',
    );

UseCaseResponse<ReelBatch> _batch(
  List<String> ids, {
  required bool more,
  int from = 0,
  int? cursor,
}) =>
    UseCaseSuccessResponse(
      ReelBatch(
        reels: [for (final id in ids) _reel(id)],
        hasMore: more,
        cursor: cursor ?? from + ids.length,
      ),
    );

void main() {
  late _MockLoadReels load;
  late Completer<UseCaseResponse<ReelBatch>> inFlight;

  ReelsBloc build({Duration retryShownFor = Duration.zero}) => ReelsBloc(
        loadReels: load,
        reconnectEvery: const Duration(milliseconds: 10),
        retryShownFor: retryShownFor,
      );

  ReelsState ready(List<String> ids, {bool more = true, int? cursor}) =>
      ReelsState(
        phase: ReelsPhase.ready,
        reels: [for (final id in ids) _reel(id)],
        canLoadMore: more,
        cursor: cursor ?? ids.length,
      );

  setUp(() {
    inFlight = Completer();
    load = _MockLoadReels();
  });

  group('opening', () {
    blocTest<ReelsBloc, ReelsState>(
      'loads the first batch',
      setUp: () => when(() => load(cursor: 0)).thenAnswer(
        (_) async => _batch(['a', 'b', 'c'], more: true),
      ),
      build: build,
      act: (bloc) => bloc.add(const ReelsOpened()),
      expect: () => [
        const ReelsState(phase: ReelsPhase.fetching),
        ready(['a', 'b', 'c']),
      ],
    );

    blocTest<ReelsBloc, ReelsState>(
      'a short first batch fetches the next one without waiting for a swipe',
      setUp: () {
        when(() => load(cursor: 0))
            .thenAnswer((_) async => _batch(['a'], more: true, cursor: 3));
        when(() => load(cursor: 3))
            .thenAnswer((_) async => _batch(['d', 'e'], more: false, from: 3));
      },
      build: build,
      act: (bloc) => bloc.add(const ReelsOpened()),
      verify: (bloc) {
        verify(() => load(cursor: 3)).called(1);
        expect(bloc.state.reels.map((r) => r.id), ['a', 'd', 'e']);
        expect(bloc.state.canLoadMore, isFalse);
      },
    );

    blocTest<ReelsBloc, ReelsState>(
      'a failed follow-up on a single reel retries by itself',
      setUp: () {
        var calls = 0;
        when(() => load(cursor: 0))
            .thenAnswer((_) async => _batch(['a'], more: true, cursor: 3));
        when(() => load(cursor: 3)).thenAnswer(
          (_) async => calls++ == 0
              ? const UseCaseConnectionError()
              : _batch(['d'], more: false, from: 3),
        );
      },
      build: build,
      act: (bloc) => bloc.add(const ReelsOpened()),
      wait: const Duration(milliseconds: 40),
      verify: (bloc) {
        verify(() => load(cursor: 3)).called(2);
        expect(bloc.state.reels.map((r) => r.id), ['a', 'd']);
        expect(bloc.state.fetchingMore, isFalse);
      },
    );

    // a closed bloc drops events anyway, so the only trace of an uncancelled
    // retry is the timer itself
    test('closing cancels a pending follow-up retry', () {
      fakeAsync((async) {
        when(() => load(cursor: 0))
            .thenAnswer((_) async => _batch(['a'], more: true, cursor: 3));
        when(() => load(cursor: 3))
            .thenAnswer((_) async => const UseCaseConnectionError());
        final bloc = build()..add(const ReelsOpened());
        async.flushMicrotasks();
        expect(async.nonPeriodicTimerCount, 1);

        unawaited(bloc.close());
        async.flushMicrotasks();
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    blocTest<ReelsBloc, ReelsState>(
      'goes offline and recovers on its own once back online',
      setUp: () {
        var calls = 0;
        when(() => load(cursor: 0)).thenAnswer(
          (_) async => calls++ == 0
              ? const UseCaseConnectionError()
              : _batch(['a'], more: false),
        );
      },
      build: build,
      act: (bloc) => bloc.add(const ReelsOpened()),
      wait: const Duration(milliseconds: 40),
      expect: () => [
        const ReelsState(phase: ReelsPhase.fetching),
        const ReelsState(phase: ReelsPhase.offline),
        ready(['a'], more: false),
      ],
    );

    blocTest<ReelsBloc, ReelsState>(
      'a server error shows the broken state and reload recovers',
      setUp: () {
        var calls = 0;
        when(() => load(cursor: 0)).thenAnswer(
          (_) async => calls++ == 0
              ? const UseCaseServerError('500')
              : _batch(['a'], more: false),
        );
      },
      build: build,
      act: (bloc) async {
        bloc.add(const ReelsOpened());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const ReelsReloadRequested());
      },
      expect: () => [
        const ReelsState(phase: ReelsPhase.fetching),
        const ReelsState(phase: ReelsPhase.broken),
        const ReelsState(phase: ReelsPhase.broken, reloading: true),
        ready(['a'], more: false),
      ],
    );

    blocTest<ReelsBloc, ReelsState>(
      'opening twice loads once',
      setUp: () => when(() => load(cursor: 0))
          .thenAnswer((_) async => _batch(['a'], more: false)),
      build: build,
      act: (bloc) => bloc
        ..add(const ReelsOpened())
        ..add(const ReelsOpened()),
      verify: (_) => verify(() => load(cursor: 0)).called(1),
    );

    blocTest<ReelsBloc, ReelsState>(
      'reload from an empty catalogue tries again',
      setUp: () {
        var calls = 0;
        when(() => load(cursor: 0)).thenAnswer(
          (_) async => calls++ == 0
              ? _batch([], more: false)
              : _batch(['a'], more: false),
        );
      },
      build: build,
      act: (bloc) async {
        bloc.add(const ReelsOpened());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const ReelsReloadRequested());
      },
      expect: () => [
        const ReelsState(phase: ReelsPhase.fetching),
        ready([], more: false),
        ready([], more: false).copyWith(reloading: true),
        ready(['a'], more: false),
      ],
    );

    blocTest<ReelsBloc, ReelsState>(
      'reload is ignored while reels are showing',
      build: build,
      seed: () => ready(['a']),
      act: (bloc) => bloc.add(const ReelsReloadRequested()),
      expect: () => <ReelsState>[],
    );

    blocTest<ReelsBloc, ReelsState>(
      'repeated offline answers keep a single reconnect timer',
      setUp: () => when(() => load(cursor: 0))
          .thenAnswer((_) async => const UseCaseConnectionError()),
      build: build,
      act: (bloc) => bloc.add(const ReelsOpened()),
      wait: const Duration(milliseconds: 55),
      // one tick per interval: the open plus about five ticks, never doubled
      verify: (_) => verify(() => load(cursor: 0)).called(lessThan(9)),
    );
  });

  group('retry', () {
    const hold = Duration(milliseconds: 1500);

    test('a check that fails at once keeps the loading screen for the hold',
        () {
      fakeAsync((async) {
        when(() => load(cursor: 0))
            .thenAnswer((_) async => const UseCaseConnectionError());
        final bloc = build(retryShownFor: hold)..add(const ReelsOpened());
        async.flushMicrotasks();
        expect(bloc.state.phase, ReelsPhase.offline);

        bloc.add(const ReelsReloadRequested());
        async
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 1499));
        expect(bloc.state.reloading, isTrue);
        expect(bloc.state.phase, ReelsPhase.offline);
        // background ticks don't start their own check meanwhile
        verify(() => load(cursor: 0)).called(2);

        async.elapse(const Duration(milliseconds: 1));
        expect(bloc.state.phase, ReelsPhase.offline);
        expect(bloc.state.reloading, isFalse);

        unawaited(bloc.close());
        async.flushMicrotasks();
      });
    });

    test('repeated taps run a single check', () {
      fakeAsync((async) {
        when(() => load(cursor: 0))
            .thenAnswer((_) async => const UseCaseConnectionError());
        final bloc = build(retryShownFor: hold)..add(const ReelsOpened());
        async.flushMicrotasks();

        bloc
          ..add(const ReelsReloadRequested())
          ..add(const ReelsReloadRequested());
        async
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 500));
        bloc.add(const ReelsReloadRequested());
        async.flushMicrotasks();

        // the open plus one retry
        verify(() => load(cursor: 0)).called(2);

        unawaited(bloc.close());
        async.flushMicrotasks();
      });
    });

    test('a tap during a background check shows loading and reuses it', () {
      fakeAsync((async) {
        final slow = Completer<UseCaseResponse<ReelBatch>>();
        var calls = 0;
        when(() => load(cursor: 0)).thenAnswer(
          (_) => calls++ == 0
              ? Future.value(const UseCaseConnectionError())
              : slow.future,
        );
        final bloc = build(retryShownFor: hold)..add(const ReelsOpened());
        async
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 10));
        expect(calls, 2);

        bloc.add(const ReelsReloadRequested());
        async.flushMicrotasks();
        expect(bloc.state.reloading, isTrue);
        expect(calls, 2);

        slow.complete(_batch(['a'], more: false));
        async
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 1499));
        expect(bloc.state.phase, ReelsPhase.offline);
        expect(bloc.state.reloading, isTrue);

        async.elapse(const Duration(milliseconds: 1));
        expect(bloc.state.phase, ReelsPhase.ready);
        expect(bloc.state.reloading, isFalse);
        expect(calls, 2);

        unawaited(bloc.close());
        async.flushMicrotasks();
      });
    });

    test('closing during the hold leaves no timer running', () {
      fakeAsync((async) {
        when(() => load(cursor: 0))
            .thenAnswer((_) async => const UseCaseConnectionError());
        final bloc = build(retryShownFor: hold)..add(const ReelsOpened());
        async.flushMicrotasks();
        bloc.add(const ReelsReloadRequested());
        async.flushMicrotasks();
        expect(async.nonPeriodicTimerCount, 1);

        unawaited(bloc.close());
        async.flushMicrotasks();
        expect(async.nonPeriodicTimerCount, 0);
        expect(async.periodicTimerCount, 0);
      });
    });
  });

  group('paging', () {
    blocTest<ReelsBloc, ReelsState>(
      'asks from the source cursor, not from the number of kept reels',
      setUp: () => when(() => load(cursor: 3))
          .thenAnswer((_) async => _batch(['c'], more: false, from: 3)),
      build: build,
      // three source items were read, one was unusable and dropped
      seed: () => ready(['a', 'b'], cursor: 3),
      act: (bloc) => bloc.add(const ReelFocused(1)),
      verify: (bloc) {
        verify(() => load(cursor: 3)).called(1);
        verifyNever(() => load(cursor: 2));
        expect(bloc.state.reels.map((r) => r.id), ['a', 'b', 'c']);
      },
    );

    blocTest<ReelsBloc, ReelsState>(
      'reads past a batch where nothing was usable',
      setUp: () {
        when(() => load(cursor: 2))
            .thenAnswer((_) async => _batch([], more: true, cursor: 4));
        when(() => load(cursor: 4))
            .thenAnswer((_) async => _batch(['e'], more: false, from: 4));
      },
      build: build,
      seed: () => ready(['a', 'b']),
      act: (bloc) => bloc.add(const ReelFocused(1)),
      verify: (bloc) {
        expect(bloc.state.reels.map((r) => r.id), ['a', 'b', 'e']);
        expect(bloc.state.canLoadMore, isFalse);
        expect(bloc.state.cursor, 5);
      },
    );

    blocTest<ReelsBloc, ReelsState>(
      'a source that claims more but never advances stops paging',
      setUp: () => when(() => load(cursor: 2))
          .thenAnswer((_) async => _batch([], more: true, cursor: 2)),
      build: build,
      seed: () => ready(['a', 'b']),
      act: (bloc) => bloc.add(const ReelFocused(1)),
      verify: (bloc) {
        verify(() => load(cursor: 2)).called(1);
        expect(bloc.state.canLoadMore, isFalse);
      },
    );

    blocTest<ReelsBloc, ReelsState>(
      'only the last two reels trigger the next batch',
      setUp: () => when(() => load(cursor: 4))
          .thenAnswer((_) async => _batch(['e'], more: false, from: 4)),
      build: build,
      seed: () => ready(['a', 'b', 'c', 'd']),
      act: (bloc) async {
        bloc.add(const ReelFocused(1));
        await Future<void>.delayed(Duration.zero);
        verifyNever(() => load(cursor: 4));
        bloc.add(const ReelFocused(2));
      },
      verify: (_) => verify(() => load(cursor: 4)).called(1),
    );

    blocTest<ReelsBloc, ReelsState>(
      'appends the next batch and stops once the source is done',
      setUp: () => when(() => load(cursor: 2))
          .thenAnswer((_) async => _batch(['c', 'd'], more: false, from: 2)),
      build: build,
      seed: () => ready(['a', 'b']),
      act: (bloc) => bloc.add(const ReelFocused(1)),
      expect: () => [
        ready(['a', 'b']).copyWith(focusedPage: 1),
        ready(['a', 'b']).copyWith(focusedPage: 1, fetchingMore: true),
        ready(['a', 'b', 'c', 'd'], more: false).copyWith(focusedPage: 1),
      ],
    );

    blocTest<ReelsBloc, ReelsState>(
      'a failed batch keeps what is there and allows another try',
      setUp: () => when(() => load(cursor: 2))
          .thenAnswer((_) async => const UseCaseConnectionError()),
      build: build,
      seed: () => ready(['a', 'b']),
      act: (bloc) => bloc.add(const ReelFocused(1)),
      expect: () => [
        ready(['a', 'b']).copyWith(focusedPage: 1),
        ready(['a', 'b']).copyWith(focusedPage: 1, fetchingMore: true),
        ready(['a', 'b']).copyWith(focusedPage: 1, tail: FeedTail.offline),
      ],
    );

    blocTest<ReelsBloc, ReelsState>(
      'fast swipes near the end ask for one batch',
      setUp: () =>
          when(() => load(cursor: 2)).thenAnswer((_) => inFlight.future),
      build: build,
      seed: () => ready(['a', 'b']),
      act: (bloc) async {
        bloc
          ..add(const ReelFocused(1))
          ..add(const ReelFocused(0))
          ..add(const ReelFocused(1));
        await Future<void>.delayed(Duration.zero);
        inFlight.complete(_batch(['c'], more: false, from: 2));
      },
      verify: (_) => verify(() => load(cursor: 2)).called(1),
    );

    test('the feed ends at the last episode, it no longer wraps', () {
      // a b c AD d
      final done = ready(['a', 'b', 'c', 'd'], more: false);
      expect(done.items, hasLength(5));
      expect(done.isValidPage(4), isTrue);
      expect(done.isValidPage(5), isFalse);
    });

    test('while more is due the feed ends in a last page, never just stops',
        () {
      // a b c then the last page; no ad slot after the last loaded episode
      final due = ready(['a', 'b', 'c']);
      expect(
        [for (final i in due.items) i.key],
        ['ep_a', 'ep_b', 'ep_c', 'more'],
      );
      expect(due.copyWith(focusedPage: 3).onTail, isTrue);
      expect(due.copyWith(focusedPage: 3).focusedEpisode, isNull);
      expect(ready(['a', 'b', 'c'], more: false).items, hasLength(3));
    });

    blocTest<ReelsBloc, ReelsState>(
      'offline at the end: the last page shows it, and quiet retries keep it',
      setUp: () => when(() => load(cursor: 3))
          .thenAnswer((_) async => const UseCaseConnectionError()),
      build: build,
      seed: () => ready(['a', 'b', 'c']).copyWith(focusedPage: 2),
      act: (bloc) async {
        bloc.add(const ReelFocused(3));
        await Future<void>.delayed(const Duration(milliseconds: 25));
      },
      verify: (bloc) {
        expect(bloc.state.focusedPage, 3);
        expect(bloc.state.tail, FeedTail.offline);
        // the quiet retries ran without ever showing loading again
        verify(() => load(cursor: 3)).called(greaterThan(1));
      },
    );

    blocTest<ReelsBloc, ReelsState>(
      'the internet coming back turns the last page into what comes next',
      setUp: () {
        var calls = 0;
        when(() => load(cursor: 3)).thenAnswer(
          (_) async => calls++ == 0
              ? const UseCaseConnectionError()
              : _batch(['d', 'e'], more: false, from: 3),
        );
      },
      build: build,
      seed: () => ready(['a', 'b', 'c']).copyWith(focusedPage: 3),
      act: (bloc) async {
        bloc.add(const ReelFocused(3));
        await Future<void>.delayed(const Duration(milliseconds: 25));
      },
      verify: (bloc) {
        final s = bloc.state;
        // a b c AD d e: the page the viewer is on is now the ad break
        expect([for (final i in s.items) i.key].last, 'ep_e');
        expect(s.items[s.focusedPage], const AdSlotItem('slot_1'));
        expect(s.tail, FeedTail.loading);
        expect(s.canLoadMore, isFalse);
      },
    );

    blocTest<ReelsBloc, ReelsState>(
      'a retry tap shows loading for a moment, then the answer',
      setUp: () => when(() => load(cursor: 3))
          .thenAnswer((_) async => const UseCaseConnectionError()),
      build: () => build(retryShownFor: const Duration(milliseconds: 40)),
      seed: () => ready(['a', 'b', 'c'])
          .copyWith(focusedPage: 3, tail: FeedTail.offline),
      act: (bloc) async {
        bloc.add(const ReelsMoreRequested());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(bloc.state.tail, FeedTail.loading);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      },
      verify: (bloc) => expect(bloc.state.tail, FeedTail.offline),
    );

    blocTest<ReelsBloc, ReelsState>(
      'a retry tap with nothing failed does nothing',
      build: build,
      seed: () => ready(['a', 'b', 'c']).copyWith(focusedPage: 3),
      act: (bloc) => bloc.add(const ReelsMoreRequested()),
      expect: () => <ReelsState>[],
    );

    blocTest<ReelsBloc, ReelsState>(
      'an empty last batch takes the last page away without stranding anyone',
      setUp: () => when(() => load(cursor: 3)).thenAnswer(
        (_) async => _batch([], more: false, from: 3),
      ),
      build: build,
      seed: () => ready(['a', 'b', 'c']).copyWith(focusedPage: 2),
      act: (bloc) => bloc.add(const ReelFocused(3)),
      verify: (bloc) {
        expect(bloc.state.items, hasLength(3));
        expect(bloc.state.focusedPage, 2);
        expect(bloc.state.pageMove?.page, 2);
      },
    );

    blocTest<ReelsBloc, ReelsState>(
      'ignores a page that is not there yet',
      build: build,
      seed: () => ready(['a', 'b']),
      act: (bloc) => bloc.add(const ReelFocused(5)),
      expect: () => <ReelsState>[],
    );
  });

  // E1 E2 E3 AD E4 E5 E6 AD E7 E8: page 6 is E6, 7 the second ad, 8 is E7
  group('focused episode', () {
    const episodes = ['e1', 'e2', 'e3', 'e4', 'e5', 'e6', 'e7', 'e8'];

    test('maps the page to its catalogue index, and an ad to none', () {
      final s = ready(episodes);
      expect(s.copyWith(focusedPage: 6).focusedEpisode, 5);
      expect(s.copyWith(focusedPage: 7).focusedEpisode, isNull);
      expect(s.copyWith(focusedPage: 8).focusedEpisode, 6);
      expect(
        s.copyWith(focusedPage: 7, removedSlots: {'slot_2'}).focusedEpisode,
        6,
      );
    });

    blocTest<ReelsBloc, ReelsState>(
      'leaving and coming back lands on the same episode',
      build: build,
      seed: () => ready(episodes, more: false).copyWith(focusedPage: 8),
      act: (bloc) => bloc
        ..add(const ReelFocused(7))
        ..add(const ReelFocused(8)),
      verify: (bloc) => expect(bloc.state.focusedEpisode, 6),
    );
  });

  group('ad slots', () {
    const episodes = ['e1', 'e2', 'e3', 'e4', 'e5', 'e6', 'e7'];
    List<String> keys(ReelsState s) => [for (final i in s.items) i.key];

    test('the feed reads E1 E2 E3 AD E4 E5 E6 AD E7', () {
      expect(keys(ready(episodes, more: false)), [
        'ep_e1', 'ep_e2', 'ep_e3', 'ad_slot_1', //
        'ep_e4', 'ep_e5', 'ep_e6', 'ad_slot_2', 'ep_e7',
      ]);
    });

    test('knows when an ad page is on screen', () {
      expect(ready(episodes).copyWith(focusedPage: 3).onAd, isTrue);
      expect(ready(episodes).copyWith(focusedPage: 4).onAd, isFalse);
    });

    blocTest<ReelsBloc, ReelsState>(
      'a slot ahead of the viewer just leaves',
      build: build,
      seed: () => ready(episodes, more: false).copyWith(focusedPage: 1),
      act: (bloc) => bloc.add(const AdSlotFailed('slot_1')),
      expect: () => [
        ready(episodes, more: false)
            .copyWith(focusedPage: 1, removedSlots: {'slot_1'}),
      ],
    );

    blocTest<ReelsBloc, ReelsState>(
      'a slot behind the viewer leaves with a same-frame page correction',
      build: build,
      // on E5, page 5
      seed: () => ready(episodes, more: false).copyWith(focusedPage: 5),
      act: (bloc) => bloc.add(const AdSlotFailed('slot_1')),
      verify: (bloc) {
        final s = bloc.state;
        expect(s.removedSlots, {'slot_1'});
        expect(s.focusedPage, 4);
        expect(s.items[s.focusedPage].key, 'ep_e5');
        expect(s.pageMove?.page, 4);
        expect(s.pageMove?.animate, isFalse);
      },
    );

    blocTest<ReelsBloc, ReelsState>(
      'nothing leaves while the feed is moving',
      build: build,
      seed: () => ready(episodes, more: false).copyWith(focusedPage: 5),
      act: (bloc) async {
        bloc
          ..add(const FeedScrollChanged(scrolling: true))
          ..add(const AdSlotFailed('slot_1'));
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.removedSlots, isEmpty);
        bloc.add(const FeedScrollChanged(scrolling: false));
      },
      verify: (bloc) => expect(bloc.state.removedSlots, {'slot_1'}),
    );

    blocTest<ReelsBloc, ReelsState>(
      'a viewer on the failing slot glides on first, then it leaves',
      build: build,
      seed: () => ready(episodes, more: false).copyWith(focusedPage: 3),
      act: (bloc) async {
        bloc.add(const AdSlotFailed('slot_1'));
        await Future<void>.delayed(Duration.zero);
        // the glide the page controller then runs
        expect(bloc.state.pageMove?.page, 4);
        expect(bloc.state.pageMove?.animate, isTrue);
        expect(bloc.state.removedSlots, isEmpty);

        // another failure mid-glide waits; it must not start a second move
        final glide = bloc.state.pageMove;
        bloc.add(const AdSlotFailed('slot_2'));
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.pageMove, glide);
        bloc
          ..add(const FeedScrollChanged(scrolling: true))
          ..add(const ReelFocused(4))
          ..add(const FeedScrollChanged(scrolling: false));
      },
      verify: (bloc) {
        final s = bloc.state;
        // the glided-off slot is now behind, the second one was ahead
        expect(s.removedSlots, {'slot_1', 'slot_2'});
        expect(s.focusedPage, 3);
        expect(s.items[s.focusedPage].key, 'ep_e4');
        expect(s.pageMove?.animate, isFalse);
      },
    );

    blocTest<ReelsBloc, ReelsState>(
      'two jumps to the same page are still two moves',
      build: build,
      seed: () => ready(
        ['e1', 'e2', 'e3', 'e4', 'e5', 'e6', 'e7', 'e8', 'e9', 'e10'],
        more: false,
        // ... E9 AD E10: E10 is page 12
      ).copyWith(focusedPage: 12),
      act: (bloc) => bloc
        ..add(const AdSlotFailed('slot_3'))
        ..add(const AdSlotFailed('slot_2')),
      verify: (bloc) {
        // E10 stays on screen as two slots behind it go
        final s = bloc.state;
        expect(s.items[s.focusedPage].key, 'ep_e10');
        expect(s.pageMove?.id, 2);
      },
    );

    blocTest<ReelsBloc, ReelsState>(
      'a dropped slot stays gone when more episodes arrive',
      setUp: () => when(() => load(cursor: 4)).thenAnswer(
        (_) async => _batch(['e5', 'e6', 'e7'], more: false, from: 4),
      ),
      build: build,
      seed: () => ready(episodes.take(4).toList(), cursor: 4)
          .copyWith(removedSlots: {'slot_1'}),
      act: (bloc) => bloc.add(const ReelFocused(3)),
      verify: (bloc) => expect(keys(bloc.state), [
        'ep_e1', 'ep_e2', 'ep_e3', 'ep_e4', //
        'ep_e5', 'ep_e6', 'ad_slot_2', 'ep_e7',
      ]),
    );
  });

  test('closing stops the reconnect timer', () async {
    var calls = 0;
    when(() => load(cursor: 0)).thenAnswer((_) async {
      calls++;
      return const UseCaseConnectionError();
    });
    final bloc = build()..add(const ReelsOpened());
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await bloc.close();
    final after = calls;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(calls, after);
  });

  // close() doesn't wait for a handler parked on a slow load; that load can
  // answer "offline" afterwards and try to start the reconnect timer
  test('a load answering after close leaves no timer running', () {
    fakeAsync((async) {
      // created in the zone so the handler resumes on the fake clock
      final slow = Completer<UseCaseResponse<ReelBatch>>();
      when(() => load(cursor: 0)).thenAnswer((_) => slow.future);
      final bloc = build()..add(const ReelsOpened());
      async.flushMicrotasks();

      unawaited(bloc.close());
      async.flushMicrotasks();
      slow.complete(const UseCaseConnectionError());
      async
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 1));

      expect(async.periodicTimerCount, 0);
    });
  });
}
