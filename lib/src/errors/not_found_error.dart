class NotFoundError implements Exception {
  NotFoundError([this.message = 'The requested resource was not found.']);

  final String message;

  @override
  String toString() => 'NotFoundError: $message';
}
