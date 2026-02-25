import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('LiveRequestQueue', () {
    test('get waits and resolves when a request is sent', () async {
      final LiveRequestQueue queue = LiveRequestQueue();

      final Future<LiveRequest> pending = queue.get();
      queue.sendContent(Content.userText('hello'));

      final LiveRequest request = await pending;
      expect(request.content, isNotNull);
      expect(request.content!.parts.single.text, 'hello');
      expect(request.close, isFalse);
    });

    test('close enqueues a terminal close request', () async {
      final LiveRequestQueue queue = LiveRequestQueue();

      queue.close();
      final LiveRequest request = await queue.get();

      expect(request.close, isTrue);
      expect(request.content, isNull);
      expect(request.blob, isNull);
    });

    test('preserves FIFO ordering for queued requests', () async {
      final LiveRequestQueue queue = LiveRequestQueue();
      queue.sendActivityStart();
      queue.sendRealtime(<int>[1, 2, 3]);
      queue.sendActivityEnd();

      final LiveRequest first = await queue.get();
      final LiveRequest second = await queue.get();
      final LiveRequest third = await queue.get();

      expect(first.activityStart, isNotNull);
      expect(second.blob, <int>[1, 2, 3]);
      expect(third.activityEnd, isNotNull);
    });

    test('supports structured requests carrying multiple fields', () async {
      final LiveRequestQueue queue = LiveRequestQueue();
      final LiveRequest request = LiveRequest(
        content: Content.userText('hello'),
        blob: InlineData(mimeType: 'audio/wav', data: <int>[1, 2]),
        activityStart: const LiveActivityStart(),
      );

      queue.send(request);
      final LiveRequest received = await queue.get();

      expect(received.content?.parts.single.text, 'hello');
      expect(received.blob, isA<InlineData>());
      expect(received.activityStart, isNotNull);
      expect(received.activityEnd, isNull);
      expect(received.close, isFalse);
    });
  });
}
