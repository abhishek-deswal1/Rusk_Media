sealed class UseCaseResponse<T> {
  const UseCaseResponse();
}

final class UseCaseSuccessResponse<T> extends UseCaseResponse<T> {
  const UseCaseSuccessResponse(this.data);

  final T data;
}

final class UseCaseServerError<T> extends UseCaseResponse<T> {
  const UseCaseServerError(this.message);

  final String message;
}

final class UseCaseConnectionError<T> extends UseCaseResponse<T> {
  const UseCaseConnectionError();
}

final class UseCaseUnknownError<T> extends UseCaseResponse<T> {
  const UseCaseUnknownError(this.message);

  final String message;
}
