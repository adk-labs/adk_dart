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

    test('copyWith preserves and overrides isolationScope', () {
      final Event event = Event(
        invocationId: 'inv_1',
        author: 'agent',
        isolationScope: 'call_1',
      );

      expect(event.copyWith().isolationScope, 'call_1');
      expect(event.copyWith(isolationScope: 'call_2').isolationScope, 'call_2');
      expect(event.copyWith(isolationScope: null).isolationScope, isNull);
    });

    test('storage event data round-trips isolationScope', () {
      final Event event = Event(
        invocationId: 'inv_1',
        author: 'agent',
        isolationScope: 'task_scope_1',
        content: Content.modelText('scoped'),
      );

      final Map<String, Object?> encoded = encodeEventData(event);
      final Event decoded = decodeEventData(encoded);

      expect(encoded['isolation_scope'], 'task_scope_1');
      expect(decoded.isolationScope, 'task_scope_1');
      expect(decoded.content?.parts.single.text, 'scoped');
    });

    test('storage event data round-trips workflow route actions', () {
      final Event event = Event(
        invocationId: 'inv_1',
        author: 'agent',
        actions: EventActions(route: <Object>['next', true]),
      );

      final Map<String, Object?> encoded = encodeEventData(event);
      final Event decoded = decodeEventData(encoded);

      final Map<String, Object?> actions = Map<String, Object?>.from(
        encoded['actions']! as Map,
      );
      expect(actions['route'], <Object>['next', true]);
      expect(decoded.actions.route, <Object>['next', true]);
      expect(decoded.actions.copyWith().route, <Object>['next', true]);
      expect(decoded.actions.copyWith(route: 'fallback').route, 'fallback');
      expect(decoded.actions.copyWith(route: null).route, isNull);
    });
  });
}
