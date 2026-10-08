import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rusk_media/features/reels/presentation/widgets/reels_scroll_physics.dart';

void main() {
  const height = 800.0;
  const limit = 6 * height;
  final page = ValueNotifier<int?>(6);
  final lock = PaywallLockPhysics(lockedPage: page);

  setUp(() => page.value = 6);
  tearDownAll(page.dispose);

  ScrollMetrics at(double pixels) => FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 20 * height,
        pixels: pixels,
        viewportDimension: height,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 3,
      );

  double landsAt(ScrollPhysics physics, double pixels, double velocity) {
    final sim = physics.createBallisticSimulation(at(pixels), velocity);
    return sim?.x(double.infinity) ?? pixels;
  }

  test('a hard fling toward the next episode stops on the locked one', () {
    // without the lock the same fling would carry on to episode 8
    expect(landsAt(const ReelsScrollPhysics(), limit, 6000), 7 * height);
    expect(landsAt(lock, limit, 6000), limit);
    expect(landsAt(lock, limit + 0.1 * height, 6000), limit);
    expect(landsAt(lock, 5.6 * height, 6000), limit);
  });

  test('a stretch past the locked episode springs back to it', () {
    expect(landsAt(lock, limit + 0.25 * height, 0), limit);
    expect(landsAt(lock, limit + 0.25 * height, 3000), limit);
  });

  test('going back is not affected', () {
    expect(landsAt(lock, 5.8 * height, -3000), 5 * height);
    expect(landsAt(lock, 3.4 * height, 0), 3 * height);
  });

  test('dragging past the locked episode gets heavier', () {
    // a negative offset moves forward
    expect(lock.applyPhysicsToUserOffset(at(4 * height), -100), -100);

    final first = lock.applyPhysicsToUserOffset(at(limit), -100);
    final deeper =
        lock.applyPhysicsToUserOffset(at(limit + 0.2 * height), -100);
    expect(first, inExclusiveRange(-100, 0));
    expect(deeper, inExclusiveRange(first, 0));

    // only the part beyond the lock is damped
    final crossing = lock.applyPhysicsToUserOffset(at(limit - 40), -100);
    expect(crossing, inExclusiveRange(-100, -40));

    // pulling back is never damped
    expect(lock.applyPhysicsToUserOffset(at(limit + 50), 100), 100);
  });

  test('a drag can never stretch further than the cap', () {
    const edge = limit + PaywallLockPhysics.maxStretch * height;
    expect(lock.applyBoundaryConditions(at(edge - 10), edge + 30), 30);
    expect(lock.applyBoundaryConditions(at(limit), limit + 50), 0);
    // moving back is never held, even from beyond the cap
    expect(lock.applyBoundaryConditions(at(edge + 5), edge - 20), 0);
  });

  test('follows the locked page when it moves, without new physics', () {
    // a dropped ad slot before episode 7 pulls it back one page
    page.value = 5;
    expect(landsAt(lock, 5 * height, 6000), 5 * height);
    final damped = lock.applyPhysicsToUserOffset(at(5 * height), -100);
    expect(damped, greaterThan(-100));
  });

  test('with nothing locked it behaves like the plain feed', () {
    page.value = null;
    const plain = ReelsScrollPhysics();
    expect(landsAt(lock, limit, 6000), landsAt(plain, limit, 6000));
    expect(lock.applyPhysicsToUserOffset(at(limit), -100), -100);
    expect(lock.applyBoundaryConditions(at(limit), limit + 900), 0);
  });
}
