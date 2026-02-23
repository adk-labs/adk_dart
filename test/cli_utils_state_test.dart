import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('createEmptyState', () {
    test('extracts placeholders from nested llm agents', () {
      final Agent sub = Agent(
        name: 'sub',
        model: 'gemini-2.5-flash',
        instruction: 'Sub instruction uses {country}',
      );
      final Agent root = Agent(
        name: 'root',
        model: 'gemini-2.5-flash',
        instruction: 'Root instruction uses {city} and {timezone}',
        subAgents: <BaseAgent>[sub],
      );

      final Map<String, Object?> state = createEmptyState(
        root,
        initializedStates: <String, Object?>{'city': 'Seoul'},
      );

      expect(state.containsKey('city'), isFalse);
      expect(state['country'], '');
      expect(state['timezone'], '');
    });
  });
}
