import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('rewindBeforeInvocationId tests', () {
    test('applyRewinds filters out events correctly', () {
      final Event e1 = Event(invocationId: 'inv_1', author: 'user', content: Content.userText('hello'));
      final Event e2 = Event(invocationId: 'inv_1', author: 'agent', content: Content.modelText('response'));
      final Event e3 = Event(invocationId: 'inv_2', author: 'user', content: Content.userText('bad request'));
      final Event e4 = Event(invocationId: 'inv_2', author: 'agent', content: Content.modelText('bad response'));
      final Event e5 = Event(
        invocationId: 'inv_3',
        author: 'user',
        actions: EventActions(rewindBeforeInvocationId: 'inv_2'),
      );
      final Event e6 = Event(invocationId: 'inv_4', author: 'user', content: Content.userText('fresh request'));

      final List<Event> events = <Event>[e1, e2, e3, e4, e5, e6];
      final List<Event> kept = applyRewinds(events);

      expect(kept, containsAllInOrder(<Event>[e1, e2, e6]));
      expect(kept.contains(e3), isFalse);
      expect(kept.contains(e4), isFalse);
      expect(kept.contains(e5), isFalse);
    });
  });
}
