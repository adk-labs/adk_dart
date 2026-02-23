class InputValidationError implements Exception {
  InputValidationError([this.message = 'Invalid input.']);

  final String message;

  @override
  String toString() => 'InputValidationError: $message';
}
