import 'package:equatable/equatable.dart';
import 'package:rusk_media/features/reels/domain/entities/reel.dart';

class ReelBatch extends Equatable {
  const ReelBatch({
    required this.reels,
    required this.hasMore,
    required this.cursor,
  });

  final List<Reel> reels;
  final bool hasMore;

  // where the next request starts in the source; skipped items still count
  final int cursor;

  @override
  List<Object?> get props => [reels, hasMore, cursor];
}
