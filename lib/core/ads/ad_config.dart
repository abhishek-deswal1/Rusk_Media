abstract final class AdConfig {
  // google's ad manager sample units; never a production unit in this app
  static const String nativeTestUnit = '/21775744923/example/native';
  static const String nativeVideoTestUnit = '/21775744923/example/native-video';

  // the slot after episode 6 carries a video creative, the one after
  // episode 3 an image one
  static String unitFor(String slotId) =>
      slotId == 'slot_2' ? nativeVideoTestUnit : nativeTestUnit;

  // a slot starts loading once it is this many pages ahead of the viewer
  static const int preloadAhead = 3;

  // a load slower than this counts as no fill and the slot is dropped
  static const Duration loadTimeout = Duration(seconds: 8);
}
