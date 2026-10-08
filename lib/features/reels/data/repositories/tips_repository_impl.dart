import 'package:rusk_media/features/reels/domain/repositories/tips_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

// a single flag, nothing that identifies the user
class TipsRepositoryImpl implements TipsRepository {
  const TipsRepositoryImpl(this._prefs);

  static const String _key = 'reels.tips_seen';

  final SharedPreferences _prefs;

  @override
  bool get seen => _prefs.getBool(_key) ?? false;

  @override
  Future<void> markSeen() => _prefs.setBool(_key, true);
}
