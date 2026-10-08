import 'package:flutter_test/flutter_test.dart';
import 'package:rusk_media/features/reels/data/repositories/tips_repository_impl.dart';
import 'package:rusk_media/features/reels/domain/usecases/tips.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a first launch shows the tips, and the flag is read back', () async {
    SharedPreferences.setMockInitialValues({});
    final tips = TipsRepositoryImpl(await SharedPreferences.getInstance());
    expect(ShouldShowTips(tips)(), isTrue);

    await MarkTipsSeen(tips)();
    expect(tips.seen, isTrue);
    expect(ShouldShowTips(tips)(), isFalse);
  });

  test('a returning viewer does not see the tips again', () async {
    SharedPreferences.setMockInitialValues({'reels.tips_seen': true});
    final tips = TipsRepositoryImpl(await SharedPreferences.getInstance());
    expect(ShouldShowTips(tips)(), isFalse);
  });
}
