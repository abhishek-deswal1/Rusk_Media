import 'package:rusk_media/core/communication/response_classes/repository_response.dart';
import 'package:rusk_media/features/reels/domain/entities/reel_batch.dart';

abstract interface class ReelsRepository {
  Future<RepositoryResponse<ReelBatch>> reels({
    required int cursor,
    required int count,
  });
}
