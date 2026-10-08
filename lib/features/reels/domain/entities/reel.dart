import 'package:equatable/equatable.dart';

class Reel extends Equatable {
  const Reel({
    required this.id,
    required this.handle,
    required this.caption,
    required this.streamUrl,
    required this.avatarUrl,
    this.posterUrl = '',
    this.stats = const ReelStats(),
  });

  final String id;
  final String handle;
  final String caption;
  final String streamUrl;
  final String avatarUrl;
  final String posterUrl;
  final ReelStats stats;

  @override
  List<Object?> get props =>
      [id, handle, caption, streamUrl, avatarUrl, posterUrl, stats];
}

class ReelStats extends Equatable {
  const ReelStats({this.likes = 0, this.comments = 0, this.shares = 0});

  final int likes;
  final int comments;
  final int shares;

  @override
  List<Object?> get props => [likes, comments, shares];
}
