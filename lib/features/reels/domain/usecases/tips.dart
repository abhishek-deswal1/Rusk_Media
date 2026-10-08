import 'package:rusk_media/features/reels/domain/repositories/tips_repository.dart';

class ShouldShowTips {
  const ShouldShowTips(this._repository);

  final TipsRepository _repository;

  bool call() => !_repository.seen;
}

class MarkTipsSeen {
  const MarkTipsSeen(this._repository);

  final TipsRepository _repository;

  Future<void> call() => _repository.markSeen();
}
