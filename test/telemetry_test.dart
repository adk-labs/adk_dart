import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryTelemetryService', () {
    test('records span lifecycle and logs', () async {
      final InMemoryTelemetryService service = InMemoryTelemetryService();

      final TelemetrySpan root = service.startSpan(
        'agent.run',
        attributes: <String, Object?>{'app': 'demo'},
      );
      service.log(root.id, 'started');
      service.endSpan(root.id, attributes: <String, Object?>{'status': 'ok'});

      final List<TelemetrySpan> snapshot = service.snapshot();
      expect(snapshot, hasLength(1));
      expect(snapshot.first.name, 'agent.run');
      expect(snapshot.first.isOpen, isFalse);
      expect(snapshot.first.attributes['status'], 'ok');
      expect(snapshot.first.logs, hasLength(1));
      expect(snapshot.first.logs.first.message, 'started');
    });
  });
}
