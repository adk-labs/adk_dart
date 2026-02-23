import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('error surface parity', () {
    test('AlreadyExistsError uses default/custom message', () {
      final AlreadyExistsError defaultError = AlreadyExistsError();
      final AlreadyExistsError customError = AlreadyExistsError('dup');

      expect(defaultError.message, 'The resource already exists.');
      expect(defaultError.toString(), contains('The resource already exists.'));
      expect(customError.message, 'dup');
      expect(customError.toString(), contains('dup'));
    });

    test('NotFoundError uses default/custom message', () {
      final NotFoundError defaultError = NotFoundError();
      final NotFoundError customError = NotFoundError('missing');

      expect(defaultError.message, 'The requested resource was not found.');
      expect(
        defaultError.toString(),
        contains('The requested resource was not found.'),
      );
      expect(customError.message, 'missing');
      expect(customError.toString(), contains('missing'));
    });

    test('InputValidationError default message remains stable', () {
      final InputValidationError error = InputValidationError();
      expect(error.message, 'Invalid input.');
      expect(error.toString(), 'InputValidationError: Invalid input.');
    });
  });
}
