import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('contents live session parity', () {
    test(
      'treats current-agent live session replies as other-agent context',
      () {
        final List<Content> contents = getContents(
          currentBranch: null,
          agentName: 'current_agent',
          events: <Event>[
            Event(
              invocationId: 'inv_live',
              author: 'current_agent',
              liveSessionId: 'live_session_1',
              content: Content.modelText('Transferred back to current agent'),
            ),
          ],
        );

        expect(contents, hasLength(1));
        expect(contents.single.role, 'user');
        expect(contents.single.parts.first.text, 'For context:');
        expect(
          contents.single.parts[1].text,
          '[current_agent] said: Transferred back to current agent',
        );
      },
    );

    test('keeps non-live current-agent replies as model output', () {
      final List<Content> contents = getContents(
        currentBranch: null,
        agentName: 'current_agent',
        events: <Event>[
          Event(
            invocationId: 'inv_non_live',
            author: 'current_agent',
            content: Content.modelText('Normal current agent response'),
          ),
        ],
      );

      expect(contents, hasLength(1));
      expect(contents.single.role, 'model');
      expect(
        contents.single.parts.single.text,
        'Normal current agent response',
      );
    });
  });
}
