import 'package:flutter_test/flutter_test.dart';
import 'package:rusk_media/core/communication/response_classes/repository_response.dart';
import 'package:rusk_media/core/communication/response_classes/use_case_response.dart';
import 'package:rusk_media/features/reels/domain/entities/reel.dart';
import 'package:rusk_media/features/reels/domain/entities/reel_batch.dart';
import 'package:rusk_media/features/reels/domain/repositories/reels_repository.dart';
import 'package:rusk_media/features/reels/domain/usecases/load_reels.dart';

class _Repo implements ReelsRepository {
  _Repo(this.answer);

  final RepositoryResponse<ReelBatch> answer;
  (int, int)? asked;

  @override
  Future<RepositoryResponse<ReelBatch>> reels({
    required int cursor,
    required int count,
  }) async {
    asked = (cursor, count);
    return answer;
  }
}

void main() {
  Future<UseCaseResponse<ReelBatch>> run(RepositoryResponse<ReelBatch> r) =>
      LoadReels(_Repo(r))(cursor: 0);

  test('passes the cursor and its batch size through', () async {
    final repo = _Repo(
      const RepositorySuccessResponse(
        ReelBatch(reels: [], hasMore: false, cursor: 0),
      ),
    );
    await LoadReels(repo, batchSize: 5)(cursor: 4);
    expect(repo.asked, (4, 5));
  });

  test('a success hands the same batch through', () async {
    const batch = ReelBatch(
      reels: [
        Reel(
          id: 'a',
          handle: 'h',
          caption: '',
          streamUrl: 'https://x/a.mp4',
          avatarUrl: '',
        ),
      ],
      hasMore: true,
      cursor: 3,
    );
    final result = await run(const RepositorySuccessResponse(batch));
    expect((result as UseCaseSuccessResponse<ReelBatch>).data, batch);
  });

  test('errors keep their kind and message', () async {
    final server = await run(const RepositoryServerError('500'));
    final unknown = await run(const RepositoryUnknownError('boom'));

    expect((server as UseCaseServerError<ReelBatch>).message, '500');
    expect((unknown as UseCaseUnknownError<ReelBatch>).message, 'boom');
    expect(
      await run(const RepositoryConnectionError()),
      isA<UseCaseConnectionError<ReelBatch>>(),
    );
  });
}
