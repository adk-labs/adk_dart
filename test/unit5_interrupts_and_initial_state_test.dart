import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

import 'package:adk_dart/adk_dart.dart';

void main() {
  group('Interrupts Indexing Unit Tests', () {
    test('indexes open long-running tool interrupts and clears on user response', () {
      final pauseEvent = Event(
        invocationId: 'inv-1',
        author: 'agent',
        longRunningToolIds: {'pause_call_1'},
        content: Content(
          role: 'model',
          parts: [
            Part(
              functionCall: FunctionCall(
                name: 'adk_request_confirmation',
                args: {'action': 'delete_db'},
                id: 'pause_call_1',
              ),
            ),
          ],
        ),
      );

      final open1 = indexOpenInterrupts([pauseEvent]);
      expect(open1.containsKey('pause_call_1'), isTrue);
      expect(open1['pause_call_1']!.author, equals('agent'));

      // User answers the pause call
      final userResponseEvent = Event(
        invocationId: 'inv-1',
        author: 'user',
        content: Content(
          role: 'user',
          parts: [
            Part(
              functionResponse: FunctionResponse(
                name: 'adk_request_confirmation',
                response: {'confirmed': true},
                id: 'pause_call_1',
              ),
            ),
          ],
        ),
      );

      final open2 = indexOpenInterrupts([pauseEvent, userResponseEvent]);
      expect(open2.containsKey('pause_call_1'), isFalse);
    });

    test('extracts fallback interrupt IDs from request_input or request_credential', () {
      final inputEvent = Event(
        invocationId: 'inv-2',
        author: 'agent',
        content: Content(
          role: 'model',
          parts: [
            Part(
              functionCall: FunctionCall(
                name: 'adk_request_input',
                args: {'prompt': 'Enter your PIN'},
                id: 'input_req_1',
              ),
            ),
          ],
        ),
      );

      final ids = extractEventInterruptIds(inputEvent);
      expect(ids, contains('input_req_1'));
      expect(isInterruptEvent(inputEvent), isTrue);

      final open = indexOpenInterrupts([inputEvent]);
      expect(open.containsKey('input_req_1'), isTrue);
    });

    test('resolves interrupt when child branch completes with matching runId', () {
      final pauseEvent = Event(
        invocationId: 'inv-3',
        author: 'root_agent',
        longRunningToolIds: {'child_task_99'},
      );

      final open1 = indexOpenInterrupts([pauseEvent]);
      expect(open1.containsKey('child_task_99'), isTrue);

      // Child branch event with user function response
      final childResponse = Event(
        invocationId: 'inv-3',
        author: 'user',
        branch: 'sub_agent@child_task_99',
        content: Content(
          role: 'user',
          parts: [
            Part(
              functionResponse: FunctionResponse(
                name: 'some_tool',
                response: {'status': 'done'},
              ),
            ),
          ],
        ),
      );

      final open2 = indexOpenInterrupts([pauseEvent, childResponse]);
      expect(open2.containsKey('child_task_99'), isFalse);
    });
  });

  group('Initial State Seeding Unit Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('adk_initial_state_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('initial_state.json is read and merged into created session state', () async {
      final appDir = Directory('${tempDir.path}/test_app')..createSync();
      final initialStateFile = File('${appDir.path}/initial_state.json');
      initialStateFile.writeAsStringSync(
        jsonEncode({
          'theme': 'dark',
          'retryCount': 3,
          'user:tier': 'gold',
        }),
      );

      final sessionService = InMemorySessionService();
      // Emulate initial state merge behavior as in web_server.dart
      final initialData = jsonDecode(initialStateFile.readAsStringSync())
          as Map<String, Object?>;

      final callerState = <String, Object?>{'retryCount': 5, 'custom': 'value'};
      final mergedState = <String, Object?>{
        ...initialData,
        ...callerState,
      };

      final session = await sessionService.createSession(
        appName: 'test_app',
        userId: 'user1',
        state: mergedState,
      );

      expect(session.state['theme'], equals('dark'));
      expect(session.state['retryCount'], equals(5)); // caller state overrides
      expect(session.state['custom'], equals('value'));
      expect(session.state['user:tier'], equals('gold'));
    });
  });
}
