import 'package:rusk_media/features/reels/domain/entities/reel.dart';

class ReelDto {
  const ReelDto._({
    required this.id,
    required this.handle,
    required this.caption,
    required this.streamUrl,
    required this.avatarUrl,
    required this.posterUrl,
    required this.likes,
    required this.comments,
    required this.shares,
  });

  // the feed is untrusted: anything missing or mistyped falls back to a
  // default, and items without an id or stream are dropped by the caller
  factory ReelDto.fromJson(Map<String, dynamic> json) {
    final creator = json['creator'];
    final stats = json['stats'];
    final c =
        creator is Map<String, dynamic> ? creator : const <String, dynamic>{};
    final s = stats is Map<String, dynamic> ? stats : const <String, dynamic>{};
    return ReelDto._(
      id: _text(json['reel_id']),
      handle: _text(c['handle']),
      avatarUrl: _text(c['avatar']),
      caption: _text(json['caption']),
      streamUrl: _text(json['stream']),
      posterUrl: _text(json['poster']),
      likes: _count(s['likes']),
      comments: _count(s['comments']),
      shares: _count(s['shares']),
    );
  }

  final String id;
  final String handle;
  final String caption;
  final String streamUrl;
  final String avatarUrl;
  final String posterUrl;
  final int likes;
  final int comments;
  final int shares;

  bool get isUsable => id.isNotEmpty && streamUrl.isNotEmpty;

  Reel toDomain() => Reel(
        id: id,
        handle: handle,
        caption: caption,
        streamUrl: streamUrl,
        avatarUrl: avatarUrl,
        posterUrl: posterUrl,
        stats: ReelStats(likes: likes, comments: comments, shares: shares),
      );

  static String _text(Object? raw) => raw is String ? raw.trim() : '';

  static int _count(Object? raw) {
    final value = switch (raw) {
      final num n => n.toInt(),
      final String t => int.tryParse(t.trim()) ?? 0,
      _ => 0,
    };
    return value < 0 ? 0 : value;
  }
}
