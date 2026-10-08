import 'package:rusk_media/core/communication/response_classes/repository_response.dart';
import 'package:rusk_media/core/communication/response_classes/use_case_response.dart';
import 'package:rusk_media/features/reels/domain/entities/reel_batch.dart';
import 'package:rusk_media/features/reels/domain/repositories/reels_repository.dart';

class LoadReels {
  const LoadReels(this._repository, {this.batchSize = 3});

  final ReelsRepository _repository;
  final int batchSize;

  Future<UseCaseResponse<ReelBatch>> call({required int cursor}) async {
    final result = await _repository.reels(cursor: cursor, count: batchSize);
    return switch (result) {
      RepositorySuccessResponse(:final data) => UseCaseSuccessResponse(data),
      RepositoryServerError(:final message) => UseCaseServerError(message),
      RepositoryConnectionError() => const UseCaseConnectionError(),
      RepositoryUnknownError(:final message) => UseCaseUnknownError(message),
    };
  }
}
