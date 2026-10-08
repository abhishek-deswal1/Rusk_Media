import 'package:flutter_test/flutter_test.dart';
import 'package:rusk_media/core/communication/response_classes/repository_response.dart';
import 'package:rusk_media/core/network/internet_checker.dart';
import 'package:rusk_media/features/reels/data/repositories/reels_repository_impl.dart';
import 'package:rusk_media/features/reels/data/sources/reels_seed_source.dart';
import 'package:rusk_media/features/reels/domain/entities/reel_batch.dart';

class _Net extends InternetChecker {
  const _Net({required this.up});

  final bool up;

  @override
  Future<bool> hasInternet() async => up;
}

class _CannedSource extends ReelsSeedSource {
  const _CannedSource(this.body);

  final Map<String, dynamic> body;

  @override
  Future<Map<String, dynamic>> page({
    required int cursor,
    required int count,
  }) async =>
      body;
}

class _DeadSource extends ReelsSeedSource {
  const _DeadSource();

  @override
  Future<Map<String, dynamic>> page({
    required int cursor,
    required int count,
  }) =>
      throw StateError('down');
}

ReelBatch _ok(RepositoryResponse<ReelBatch> r) =>
    (r as RepositorySuccessResponse<ReelBatch>).data;

void main() {
  const online = _Net(up: true);

  test('offline answers with a connection error', () async {
    const repo = ReelsRepositoryImpl(
      source: ReelsSeedSource(),
      connectivity: _Net(up: false),
    );
    expect(
      await repo.reels(cursor: 0, count: 3),
      isA<RepositoryConnectionError<ReelBatch>>(),
    );
  });

  test('walks the catalogue and reports the end', () async {
    const repo = ReelsRepositoryImpl(
      source: ReelsSeedSource(),
      connectivity: online,
    );

    final first = _ok(await repo.reels(cursor: 0, count: 3));
    final last = _ok(await repo.reels(cursor: 6, count: 3));
    final past = _ok(await repo.reels(cursor: 8, count: 3));

    expect(first.reels, hasLength(3));
    expect(first.hasMore, isTrue);
    expect(first.cursor, 3);
    expect(first.reels.first.caption, 'Episode 1');
    // seven episodes plus the placeholder that sits behind the paywall
    expect(last.reels.map((r) => r.caption), ['Episode 7', 'Episode 8']);
    expect(last.hasMore, isFalse);
    expect(past.reels, isEmpty);
    expect(past.cursor, 8);
  });

  test('drops broken items and still advances past them', () async {
    const repo = ReelsRepositoryImpl(
      source: _CannedSource({
        'data': [
          'not a map',
          {'reel_id': 'no_stream'},
          {'reel_id': 'ok', 'stream': 'https://x/v.mp4'},
        ],
        'more': 'yes',
      }),
      connectivity: online,
    );

    final batch = _ok(await repo.reels(cursor: 5, count: 3));
    expect(batch.reels.map((r) => r.id), ['ok']);
    expect(batch.hasMore, isFalse);
    // skipped items still count, so the next request doesn't repeat any
    expect(batch.cursor, 8);
  });

  test('only a literal true means there is more', () async {
    const repo = ReelsRepositoryImpl(
      source: _CannedSource({
        'data': [
          {'reel_id': 'a', 'stream': 'https://x/a.mp4'},
        ],
        'more': true,
      }),
      connectivity: online,
    );
    final batch = _ok(await repo.reels(cursor: 2, count: 3));
    expect(batch.hasMore, isTrue);
    expect(batch.cursor, 3);
  });

  test('a body without data is an empty batch', () async {
    const repo = ReelsRepositoryImpl(
      source: _CannedSource({}),
      connectivity: online,
    );
    expect(_ok(await repo.reels(cursor: 0, count: 3)).reels, isEmpty);
  });

  test('a throwing source becomes an unknown error', () async {
    const repo = ReelsRepositoryImpl(
      source: _DeadSource(),
      connectivity: online,
    );
    expect(
      await repo.reels(cursor: 0, count: 3),
      isA<RepositoryUnknownError<ReelBatch>>(),
    );
  });
}
