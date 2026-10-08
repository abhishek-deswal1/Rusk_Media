import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rusk_media/core/constants/app_strings.dart';
import 'package:rusk_media/features/reels/presentation/widgets/tips_sheet.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('lists the six gestures in the order the guide teaches them',
      (tester) async {
    var done = 0;
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: TipsSheet(onDone: () => done++)),
    );
    tester.takeException();

    const order = [
      AppStrings.tipPause,
      AppStrings.tipLike,
      AppStrings.tipVolume,
      AppStrings.tipTimeline,
      AppStrings.tipProgress,
      AppStrings.tipScroll,
    ];
    double top(String tip) => tester.getTopLeft(find.text(tip)).dy;
    final tops = order.map(top).toList();
    expect(tops, [...tops]..sort());
    for (var n = 1; n <= order.length; n++) {
      expect(find.text('$n'), findsOneWidget);
    }

    await tester.tap(find.text(AppStrings.tipsCta));
    expect(done, 1);
  });
}
