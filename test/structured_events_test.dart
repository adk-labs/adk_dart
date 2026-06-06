import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/adk_core.dart' as core;
import 'package:test/test.dart';

void main() {
  group('toStructuredEvents', () {
    test('returns an error event when errorCode is set', () {
      final Event event = _event(errorCode: 'INTERNAL');

      final List<StructuredEvent> result = toStructuredEvents(event);

      expect(result, hasLength(1));
      expect(result.single.type, EventType.error);
      final ErrorEvent error = result.single as ErrorEvent;
      expect(error.code, 'INTERNAL');
      expect(error.message, 'INTERNAL');
      expect(error.error.toString(), contains('INTERNAL'));
    });

    test('uses errorMessage when present alongside errorCode', () {
      final Event event = _event(
        errorCode: 'INTERNAL',
        errorMessage: 'something went wrong',
      );

      final ErrorEvent error = toStructuredEvents(event).single as ErrorEvent;

      expect(error.message, 'something went wrong');
      expect(error.error.toString(), contains('something went wrong'));
    });

    test('returns a thought event for a thought text part', () {
      final Event event = _event(
        partial: true,
        content: Content(
          parts: <Part>[Part.text('I am thinking', thought: true)],
        ),
      );

      final List<StructuredEvent> result = toStructuredEvents(event);

      expect(result, hasLength(1));
      expect(result.single.type, EventType.thought);
      expect((result.single as ThoughtEvent).content, 'I am thinking');
    });

    test('returns a content event for a regular text part', () {
      final Event event = _event(
        partial: true,
        content: Content(parts: <Part>[Part.text('Hello user')]),
      );

      final List<StructuredEvent> result = toStructuredEvents(event);

      expect(result, hasLength(1));
      expect(result.single.type, EventType.content);
      expect((result.single as ContentEvent).content, 'Hello user');
    });

    test('returns a tool call event for a function call part', () {
      final Event event = _event(
        content: Content(
          parts: <Part>[
            Part.fromFunctionCall(
              name: 'my_func',
              args: <String, dynamic>{'x': 1},
            ),
          ],
        ),
      );

      final List<StructuredEvent> result = toStructuredEvents(event);
      final ToolCallEvent toolCall = result.whereType<ToolCallEvent>().single;

      expect(toolCall.call.name, 'my_func');
      expect(toolCall.call.args, <String, Object?>{'x': 1});
    });

    test('returns a tool result event for a function response part', () {
      final Event event = _event(
        content: Content(
          parts: <Part>[
            Part.fromFunctionResponse(
              name: 'my_func',
              response: <String, dynamic>{'result': 42},
            ),
          ],
        ),
      );

      final List<StructuredEvent> result = toStructuredEvents(event);

      expect(result.whereType<ToolResultEvent>(), hasLength(1));
    });

    test('returns a code call event for executable code', () {
      final Event event = _event(
        partial: true,
        content: Content(
          parts: <Part>[
            Part(
              executableCode: <String, Object?>{
                'code': 'print("hi")',
                'language': 'python',
              },
            ),
          ],
        ),
      );

      final List<StructuredEvent> result = toStructuredEvents(event);

      expect(result, hasLength(1));
      expect(result.single.type, EventType.callCode);
    });

    test('returns a code result event for code execution result', () {
      final Event event = _event(
        content: Content(
          parts: <Part>[
            Part(
              codeExecutionResult: <String, Object?>{
                'outcome': 'OUTCOME_OK',
                'output': 'hi',
              },
            ),
          ],
        ),
      );

      final List<StructuredEvent> result = toStructuredEvents(event);

      expect(result.whereType<CodeResultEvent>(), hasLength(1));
    });

    test('returns a tool confirmation event for requested confirmations', () {
      final Event event = _event(
        actions: EventActions(
          requestedToolConfirmations: <String, Object>{
            'call-1': <String, Object?>{'toolName': 'dangerous_tool'},
          },
        ),
      );

      final ToolConfirmationEvent confirmation = toStructuredEvents(
        event,
      ).whereType<ToolConfirmationEvent>().single;

      expect(confirmation.confirmations, contains('call-1'));
    });

    test('returns a finished event when event is final response', () {
      final Event event = _event(content: Content.modelText('done'));

      final List<StructuredEvent> result = toStructuredEvents(event);
      final FinishedEvent finished = result.whereType<FinishedEvent>().single;

      expect(finished.hasOutput, isFalse);
      expect(finished.output, isNull);
    });

    test('finished event preserves explicit workflow output', () {
      final Event event = _event(
        content: Content.modelText('done'),
        output: <String, Object?>{'answer': 42},
      );

      final FinishedEvent finished = toStructuredEvents(
        event,
      ).whereType<FinishedEvent>().single;

      expect(finished.hasOutput, isTrue);
      expect(finished.output, <String, Object?>{'answer': 42});
    });

    test('returns multiple structured events from a mixed-part event', () {
      final Event event = _event(
        content: Content(
          parts: <Part>[
            Part.text('thinking', thought: true),
            Part.text('Hello'),
            Part.fromFunctionCall(name: 'my_func'),
          ],
        ),
      );

      final List<EventType> types = toStructuredEvents(
        event,
      ).map((StructuredEvent event) => event.type).toList();

      expect(types, contains(EventType.thought));
      expect(types, contains(EventType.content));
      expect(types, contains(EventType.toolCall));
    });

    test('plain event with no content returns finished only', () {
      final List<StructuredEvent> result = toStructuredEvents(_event());

      expect(result, hasLength(1));
      expect(result.single.type, EventType.finished);
    });

    test('is exported through the Web-safe core entrypoint', () {
      final List<core.StructuredEvent> result = core.toStructuredEvents(
        core.Event(
          invocationId: 'inv',
          author: 'agent',
          content: core.Content.modelText('done'),
        ),
      );

      expect(
        result.whereType<core.FinishedEvent>().single.type,
        core.EventType.finished,
      );
    });
  });
}

Event _event({
  Content? content,
  EventActions? actions,
  bool? partial,
  String? errorCode,
  String? errorMessage,
  Object? output = _sentinel,
}) {
  if (identical(output, _sentinel)) {
    return Event(
      invocationId: 'inv',
      author: 'agent',
      content: content,
      actions: actions,
      partial: partial,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }
  return Event(
    invocationId: 'inv',
    author: 'agent',
    content: content,
    actions: actions,
    partial: partial,
    errorCode: errorCode,
    errorMessage: errorMessage,
    output: output,
  );
}

const Object _sentinel = Object();
