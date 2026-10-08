import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rusk_media/core/constants/app_strings.dart';
import 'package:rusk_media/shared/widgets/connection_state/retry_button.dart';

void main() {
  Future<void> pumpButton(
    WidgetTester tester, {
    required bool checking,
    VoidCallback? onPressed,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RetryButton(
              checking: checking,
              onPressed: onPressed ?? () {},
            ),
          ),
        ),
      );

  testWidgets('ready to retry: icon and label, a tap retries', (tester) async {
    var taps = 0;
    await pumpButton(tester, checking: false, onPressed: () => taps++);

    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.text(AppStrings.retry), findsOneWidget);
    await tester.tap(find.byType(RetryButton));
    expect(taps, 1);
  });

  testWidgets('checking uses no stock spinner and ignores taps',
      (tester) async {
    var taps = 0;
    await pumpButton(tester, checking: true, onPressed: () => taps++);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.text(AppStrings.checking), findsOneWidget);
    await tester.tap(find.byType(RetryButton));
    expect(taps, 0);
  });
}
