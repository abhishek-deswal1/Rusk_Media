sealed class RepositoryResponse<T> {
  const RepositoryResponse();
}

final class RepositorySuccessResponse<T> extends RepositoryResponse<T> {
  const RepositorySuccessResponse(this.data);

  final T data;
}

final class RepositoryServerError<T> extends RepositoryResponse<T> {
  const RepositoryServerError(this.message);

  final String message;
}

final class RepositoryConnectionError<T> extends RepositoryResponse<T> {
  const RepositoryConnectionError();
}

final class RepositoryUnknownError<T> extends RepositoryResponse<T> {
  const RepositoryUnknownError(this.message);

  final String message;
}
