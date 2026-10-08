import 'package:rusk_media/core/communication/response_classes/repository_response.dart';
import 'package:rusk_media/core/logger/app_logger.dart';
import 'package:rusk_media/core/network/internet_checker.dart';
import 'package:rusk_media/features/reels/data/models/reel_dto.dart';
import 'package:rusk_media/features/reels/data/sources/reels_seed_source.dart';
import 'package:rusk_media/features/reels/domain/entities/reel_batch.dart';
import 'package:rusk_media/features/reels/domain/repositories/reels_repository.dart';

// no caching at this level: the list is tiny, and the media files go through
// the video pool's disk cache
class ReelsRepositoryImpl implements ReelsRepository {
  const ReelsRepositoryImpl({
    required ReelsSeedSource source,
    required InternetChecker connectivity,
  })  : _source = source,
        _connectivity = connectivity;

  final ReelsSeedSource _source;
  final InternetChecker _connectivity;

  @override
  Future<RepositoryResponse<ReelBatch>> reels({
    required int cursor,
    required int count,
  }) async {
    // every reel streams, so without a connection there is nothing to show
    if (!await _connectivity.hasInternet()) {
      return const RepositoryConnectionError();
    }
    try {
      final body = await _source.page(cursor: cursor, count: count);
      final raw = body['data'];
      final items = raw is List ? raw : const <Object?>[];
      final reels = [
        for (final item in items.whereType<Map<String, dynamic>>())
          ReelDto.fromJson(item),
      ].where((dto) => dto.isUsable).map((dto) => dto.toDomain()).toList();
      final more = body['more'];
      return RepositorySuccessResponse(
        ReelBatch(
          reels: reels,
          hasMore: more == true,
          cursor: cursor + items.length,
        ),
      );
    } on Object catch (e, stack) {
      AppLogger.logError('reels page failed', e, stack);
      return RepositoryUnknownError(e.toString());
    }
  }
}
