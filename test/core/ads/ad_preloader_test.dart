import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:rusk_media/core/ads/ad_config.dart';
import 'package:rusk_media/core/ads/ad_preloader.dart';
import 'package:rusk_media/core/ads/ad_slot_state.dart';

class _FakeAd extends NativeAd {
  _FakeAd(NativeAdListener listener)
      : super(
          adUnitId: 'test',
          factoryId: 'test',
          listener: listener,
          request: const AdRequest(),
        );

  bool loading = false;
  bool disposed = false;

  void answer() => listener.onAdLoaded!(this);

  void noFill() => listener.onAdFailedToLoad!(this, _NoFill());

  @override
  Future<void> load() async => loading = true;

  @override
  Future<void> dispose() async => disposed = true;
}

class _NoFill extends LoadAdError {
  _NoFill() : super(3, 'test', 'no fill', null);
}

void main() {
  late List<_FakeAd> made;
  late AdPreloader ads;
  late List<String> failed;
  late StreamSubscription<String> failures;

  // built inside each fake clock so the timeouts run on it
  void start() {
    made = [];
    failed = [];
    ads = AdPreloader(
      createAd: (slotId, listener) {
        final ad = _FakeAd(listener);
        made.add(ad);
        return ad;
      },
    );
    failures = ads.failures.listen(failed.add);
  }

  void stop(FakeAsync async) {
    unawaited(failures.cancel());
    ads.dispose();
    async.flushMicrotasks();
  }

  test('the slot after episode 6 is video, the one after episode 3 is not', () {
    expect(AdConfig.unitFor('slot_1'), AdConfig.nativeTestUnit);
    expect(AdConfig.unitFor('slot_2'), AdConfig.nativeVideoTestUnit);
    // only google's sample units, never a production one
    for (final slot in ['slot_1', 'slot_2']) {
      expect(AdConfig.unitFor(slot), startsWith('/21775744923/example/'));
    }
  });

  test('every ad is built for its own slot', () {
    fakeAsync((async) {
      final asked = <String>[];
      final ads = AdPreloader(
        createAd: (slotId, listener) {
          asked.add(slotId);
          return _FakeAd(listener);
        },
      )..load(['slot_1', 'slot_2']);
      expect(asked, ['slot_1', 'slot_2']);
      ads.dispose();
      async.flushMicrotasks();
    });
  });

  test('each slot loads once, however often it is asked for', () {
    fakeAsync((async) {
      start();
      ads
        ..load(['slot_1'])
        ..load(['slot_1', 'slot_2'])
        ..load(['slot_1']);
      expect(made, hasLength(2));
      expect(made.every((ad) => ad.loading), isTrue);
      expect(ads.stateOf('slot_1').value, isA<AdSlotLoading>());
      stop(async);
    });
  });

  test('a loaded ad is handed over and its timeout is cancelled', () {
    fakeAsync((async) {
      start();
      ads.load(['slot_1']);
      made.single.answer();
      expect(ads.stateOf('slot_1').value, isA<AdSlotLoaded>());

      async
        ..elapse(const Duration(seconds: 20))
        ..flushMicrotasks();
      expect(failed, isEmpty);
      expect(made.single.disposed, isFalse);
      stop(async);
    });
  });

  test('no fill fails the slot, reports it and frees the ad', () {
    fakeAsync((async) {
      start();
      ads.load(['slot_1']);
      made.single.noFill();
      async.flushMicrotasks();

      expect(ads.stateOf('slot_1').value, isA<AdSlotFailed>());
      expect(failed, ['slot_1']);
      expect(made.single.disposed, isTrue);
      stop(async);
    });
  });

  test('a load slower than the timeout fails, and a late answer is ignored',
      () {
    fakeAsync((async) {
      start();
      ads.load(['slot_1']);
      async.elapse(ads.loadTimeout - const Duration(milliseconds: 1));
      expect(failed, isEmpty);

      async
        ..elapse(const Duration(milliseconds: 1))
        ..flushMicrotasks();
      expect(failed, ['slot_1']);
      expect(made.single.disposed, isTrue);

      made.single.answer();
      made.single.noFill();
      async.flushMicrotasks();
      expect(ads.stateOf('slot_1').value, isA<AdSlotFailed>());
      expect(failed, ['slot_1']);
      stop(async);
    });
  });

  test('releasing a slot frees its ad, loaded or still loading', () {
    fakeAsync((async) {
      start();
      ads.load(['slot_1', 'slot_2']);
      made.first.answer();

      ads
        ..release('slot_1')
        ..release('slot_2');
      async.flushMicrotasks();
      expect(made.every((ad) => ad.disposed), isTrue);
      expect(ads.stateOf('slot_1').value, isA<AdSlotFailed>());

      // a dropped slot is not reported as a failure and never loads again,
      // even if the sdk answers for it late
      made.last.noFill();
      async.elapse(const Duration(seconds: 20));
      expect(failed, isEmpty);
      ads.load(['slot_1']);
      expect(made, hasLength(2));
      stop(async);
    });
  });

  test('disposing frees every ad and leaves no timer behind', () {
    fakeAsync((async) {
      start();
      ads.load(['slot_1', 'slot_2']);
      made.first.answer();
      expect(async.nonPeriodicTimerCount, 1);

      stop(async);
      expect(made.every((ad) => ad.disposed), isTrue);
      expect(async.nonPeriodicTimerCount, 0);

      // a late answer after dispose is ignored, and loading is a no-op
      made.last.answer();
      ads.load(['slot_3']);
      expect(made, hasLength(2));
    });
  });
}
