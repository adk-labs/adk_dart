import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Event', () {
    test('isFinalResponse returns true for plain final content', () {
      final Event event = Event(
        invocationId: 'inv_1',
        author: 'agent',
        content: Content.modelText('hello'),
      );

      expect(event.isFinalResponse(), isTrue);
    });

    test('isFinalResponse returns false when function call exists', () {
      final Event event = Event(
        invocationId: 'inv_1',
        author: 'agent',
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(name: 'tool', args: {'x': 1}),
          ],
        ),
      );

      expect(event.isFinalResponse(), isFalse);
      expect(event.getFunctionCalls(), hasLength(1));
    });

    test('isFinalResponse returns true when longRunningToolIds are set', () {
      final Event event = Event(
        invocationId: 'inv_1',
        author: 'agent',
        content: Content(
          role: 'model',
          parts: <Part>[Part.fromFunctionCall(name: 'tool', args: {})],
        ),
        longRunningToolIds: <String>{'call_1'},
      );

      expect(event.isFinalResponse(), isTrue);
    });
  });
}
