import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// close to critically damped: lands on the next reel without overshoot
class ReelsScrollPhysics extends PageScrollPhysics {
  const ReelsScrollPhysics({super.parent});

  @override
  ReelsScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      ReelsScrollPhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring =>
      const SpringDescription(mass: 0.6, stiffness: 260, damping: 26);

  @override
  double get minFlingVelocity => 80;

  @override
  double get minFlingDistance => 18;
}

// holds the feed on a locked page: pulling past it gets heavier the further
// it goes and always springs back, while going back stays untouched. the
// page is read live because Scrollable keeps the first physics it was given
// until their type changes, and the locked page moves when an ad slot before
// it is dropped
class PaywallLockPhysics extends ReelsScrollPhysics {
  const PaywallLockPhysics({required this.lockedPage, super.parent});

  final ValueListenable<int?> lockedPage;

  // how far past the locked page a drag can stretch, in viewports
  static const double maxStretch = 0.3;

  @override
  PaywallLockPhysics applyTo(ScrollPhysics? ancestor) =>
      PaywallLockPhysics(lockedPage: lockedPage, parent: buildParent(ancestor));

  double? _limit(ScrollMetrics position) {
    final page = lockedPage.value;
    return page == null ? null : page * position.viewportDimension;
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    final limit = _limit(position);
    // a negative offset moves forward
    if (limit == null || offset >= 0 || position.pixels - offset <= limit) {
      return super.applyPhysicsToUserOffset(position, offset);
    }
    final forward = -offset;
    final free = math.max<double>(0, limit - position.pixels);
    final past = math.max<double>(0, position.pixels - limit);
    final room = position.viewportDimension * maxStretch;
    final stretch = math.min<double>(1, past / room);
    final resistance = 0.5 * (1 - stretch) * (1 - stretch);
    return -(free + (forward - free) * resistance);
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final limit = _limit(position);
    if (limit != null) {
      final edge = limit + position.viewportDimension * maxStretch;
      if (value > edge && value > position.pixels) {
        return value - math.max(edge, position.pixels);
      }
    }
    return super.applyBoundaryConditions(position, value);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final limit = _limit(position);
    final settle = super.createBallisticSimulation(position, velocity);
    if (limit == null) return settle;
    final lands = settle?.x(double.infinity) ?? position.pixels;
    if (lands <= limit) return settle;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      limit,
      math.min<double>(0, velocity),
      tolerance: toleranceFor(position),
    );
  }
}
