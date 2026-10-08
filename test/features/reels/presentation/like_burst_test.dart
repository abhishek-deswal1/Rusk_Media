import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rusk_media/features/reels/presentation/widgets/like_burst.dart';

void main() {
  testWidgets('the heart springs past full size, settles, fades and goes once',
      (tester) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            LikeBurst(at: const Offset(120, 300), onFinished: () => finished++),
          ],
        ),
      ),
    );

    final heart = find.byIcon(Icons.favorite_rounded);
    // the scale transform sits right around the heart; read its x scale, not
    // getMaxScaleOnAxis, which never goes under the untouched z axis's 1
    double scale() => tester
        .widget<Transform>(
          find.ancestor(of: heart, matching: find.byType(Transform)).first,
        )
        .transform
        .entry(0, 0);

    // centred on the exact touch point
    expect(tester.getCenter(heart), const Offset(120, 300));

    final scales = <double>[];
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      scales.add(scale());
    }
    // a spring overshoots, then wobbles back below full size before it
    // settles; an eased curve would never dip once it got there
    final peak = scales.reduce((a, b) => a > b ? a : b);
    final afterPeak = scales.skip(scales.indexOf(peak));
    final dip = afterPeak.reduce((a, b) => a < b ? a : b);
    expect(peak, greaterThan(1.2));
    expect(dip, lessThan(0.97));
    expect(scales.last, closeTo(1, 0.15));

    await tester.pump(const Duration(milliseconds: 400));
    expect(finished, 1);
  });
}
