class AlreadyExistsError implements Exception {
  AlreadyExistsError([this.message = 'The resource already exists.']);

  final String message;

  @override
  String toString() => 'AlreadyExistsError: $message';
}
