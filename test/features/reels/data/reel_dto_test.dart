import 'package:flutter_test/flutter_test.dart';
import 'package:rusk_media/features/reels/data/models/reel_dto.dart';

void main() {
  test('reads a complete item', () {
    final dto = ReelDto.fromJson(const {
      'reel_id': 'r1',
      'caption': 'hi',
      'stream': 'https://x/r1.mp4',
      'poster': 'https://x/r1.jpg',
      'creator': {'handle': 'rusk', 'avatar': 'https://x/a.png'},
      'stats': {'likes': 12, 'comments': 3, 'shares': 1},
    });

    final reel = dto.toDomain();
    expect(reel.posterUrl, 'https://x/r1.jpg');
    expect(reel.id, 'r1');
    expect(reel.handle, 'rusk');
    expect(reel.avatarUrl, 'https://x/a.png');
    expect(reel.caption, 'hi');
    expect(reel.streamUrl, 'https://x/r1.mp4');
    expect(reel.stats.likes, 12);
    expect(reel.stats.comments, 3);
    expect(reel.stats.shares, 1);
    expect(dto.isUsable, isTrue);
  });

  test('wrong types and missing blocks fall back to defaults', () {
    final dto = ReelDto.fromJson(const {
      'reel_id': 'r1',
      'stream': 'https://x/r1.mp4',
      'creator': 'not a map',
      'stats': {'likes': '7', 'comments': -4, 'shares': 2.9},
    });

    expect(dto.handle, '');
    expect(dto.caption, '');
    expect(dto.posterUrl, '');
    expect(dto.likes, 7);
    expect(dto.comments, 0);
    expect(dto.shares, 2);
  });

  test('an item without an id or a stream is not usable', () {
    expect(ReelDto.fromJson(const {'reel_id': 'r1'}).isUsable, isFalse);
    expect(ReelDto.fromJson(const {'stream': 'https://x'}).isUsable, isFalse);
  });

  test('trims text and never lets a count go negative', () {
    final dto = ReelDto.fromJson(const {
      'reel_id': ' r1 ',
      'stream': '   ',
      'stats': {'likes': '-4', 'comments': ' 12 ', 'shares': -2.5},
    });

    expect(dto.id, 'r1');
    expect(dto.isUsable, isFalse);
    expect(dto.likes, 0);
    expect(dto.comments, 12);
    expect(dto.shares, 0);
  });
}
