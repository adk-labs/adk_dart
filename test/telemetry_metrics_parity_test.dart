import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

AdkMetricRecord _recordByName(
  InMemoryAdkMetricsRecorder recorder,
  String name,
) {
  return recorder.records.firstWhere((AdkMetricRecord record) {
    return record.name == name;
  });
}

void main() {
  group('Java-compatible telemetry metrics', () {
    late InMemoryAdkMetricsRecorder recorder;

    setUp(() {
      recorder = InMemoryAdkMetricsRecorder();
    });

    test('records agent invocation duration with error attributes', () {
      recordAgentInvocationDuration(
        'my-agent',
        const Duration(milliseconds: 123),
        error: StateError('bad arg'),
        recorder: recorder,
      );

      final AdkMetricRecord record = _recordByName(
        recorder,
        genAiAgentInvocationDurationMetric,
      );
      expect(record.value, 123.0);
      expect(record.unit, 'ms');
      expect(record.description, 'Duration of agent invocations.');
      expect(record.attributes['gen_ai.agent.name'], 'my-agent');
      expect(record.attributes['error.type'], 'StateError');
    });

    test('computes content size from UTF-8 text and inline bytes', () {
      final Content content = Content(
        parts: <Part>[
          Part.text('hello'),
          Part.text('안녕'),
          Part.fromInlineData(mimeType: 'text/plain', data: <int>[1, 2, 3]),
        ],
      );

      recordAgentRequestSize('my-agent', content, recorder: recorder);

      final AdkMetricRecord record = _recordByName(
        recorder,
        genAiAgentRequestSizeMetric,
      );
      expect(record.value, utf8.encode('hello안녕').length + 3);
      expect(record.unit, 'By');
      expect(record.attributes['gen_ai.agent.name'], 'my-agent');
    });

    test('uses the latest content event authored by the target agent', () {
      final List<Event> events = <Event>[
        Event(
          invocationId: 'inv',
          author: 'my-agent',
          content: Content.modelText('old'),
        ),
        Event(
          invocationId: 'inv',
          author: 'user',
          content: Content.userText('ignored'),
        ),
        Event(
          invocationId: 'inv',
          author: 'my-agent',
          content: Content.modelText('response'),
        ),
      ];

      recordAgentResponseSize('my-agent', events, recorder: recorder);

      expect(
        _recordByName(recorder, genAiAgentResponseSizeMetric).value,
        utf8.encode('response').length,
      );
    });

    test('counts only string-valued tool request arguments', () {
      recordToolRequestSize('my-tool', 'my-agent', <String, Object?>{
        'arg1': 'value1',
        'arg2': 10,
        'arg3': true,
      }, recorder: recorder);

      final AdkMetricRecord record = _recordByName(
        recorder,
        genAiToolRequestSizeMetric,
      );
      expect(record.value, utf8.encode('value1').length);
      expect(record.attributes['gen_ai.agent.name'], 'my-agent');
      expect(record.attributes['gen_ai.tool.name'], 'my-tool');
    });

    test('records tool duration and response event sizes', () {
      recordToolExecutionDuration(
        'my-tool',
        'my-agent',
        const Duration(milliseconds: 45),
        error: const FormatException('bad'),
        recorder: recorder,
      );
      recordToolResponseSize(
        'my-tool',
        'my-agent',
        Event(
          invocationId: 'inv',
          author: 'my-agent',
          content: Content(
            parts: <Part>[
              Part.fromFunctionResponse(name: 'my-tool'),
              Part.fromInlineData(mimeType: 'image/png', data: <int>[1, 2]),
              Part.text('ok'),
            ],
          ),
        ),
        recorder: recorder,
      );

      final AdkMetricRecord duration = _recordByName(
        recorder,
        genAiToolExecutionDurationMetric,
      );
      expect(duration.value, 45.0);
      expect(duration.attributes['error.type'], 'FormatException');

      final AdkMetricRecord response = _recordByName(
        recorder,
        genAiToolResponseSizeMetric,
      );
      expect(response.value, 4);
      expect(response.unit, 'By');
    });
  });
}
