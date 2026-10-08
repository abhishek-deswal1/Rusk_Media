import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// the ads sdk kills the app on launch, before any dart runs, when the app id
// is missing from the platform config, so check the files themselves
void main() {
  test('android declares the sample test app id', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      manifest,
      matches(
        RegExp(
          r'android:name="com\.google\.android\.gms\.ads\.APPLICATION_ID"\s*'
          'android:value="ca-app-pub-3940256099942544~3347511713"',
        ),
      ),
    );
  });

  test('ios declares the sample test app id', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      plist,
      matches(
        RegExp(
          r'<key>GADApplicationIdentifier</key>\s*'
          '<string>ca-app-pub-3940256099942544~1458002511</string>',
        ),
      ),
    );
  });
}
