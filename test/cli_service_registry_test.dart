import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _CustomSessionService extends BaseSessionService {
  _CustomSessionService() : _delegate = InMemorySessionService();

  final InMemorySessionService _delegate;

  @override
  Future<Event> appendEvent({required Session session, required Event event}) {
    return _delegate.appendEvent(session: session, event: event);
  }

  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) {
    return _delegate.createSession(
      appName: appName,
      userId: userId,
      state: state,
      sessionId: sessionId,
    );
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) {
    return _delegate.deleteSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
  }

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) {
    return _delegate.getSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      config: config,
    );
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) {
    return _delegate.listSessions(appName: appName, userId: userId);
  }
}

void main() {
  group('ServiceRegistry', () {
    setUp(resetServiceRegistryForTest);
    tearDown(DatabaseSessionService.resetCustomResolversAndFactories);

    test('creates built-in session/artifact/memory services', () {
      final ServiceRegistry registry = getServiceRegistry();

      expect(
        registry.createSessionService('memory://'),
        isA<InMemorySessionService>(),
      );
      expect(
        registry.createSessionService('sqlite:///tmp/session.db'),
        isA<SqliteSessionService>(),
      );
      expect(
        registry.createArtifactService('memory://'),
        isA<InMemoryArtifactService>(),
      );
      expect(
        registry.createMemoryService('memory://'),
        isA<InMemoryMemoryService>(),
      );
    });

    test('loads yaml-registered services from services.yaml', () {
      registerServiceClassFactory('test.CustomSessionService', (
        String uri, {
        Map<String, Object?>? kwargs,
      }) {
        return _CustomSessionService();
      });

      final Directory temp = Directory.systemTemp.createTempSync(
        'adk_service_registry_',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final File yaml = File(
        '${temp.path}${Platform.pathSeparator}services.yaml',
      );
      yaml.writeAsStringSync('''
services:
  - scheme: custom
    type: session
    class: test.CustomSessionService
''');

      loadServicesModule(temp.path);
      final BaseSessionService? service = getServiceRegistry()
          .createSessionService('custom://endpoint');
      expect(service, isA<_CustomSessionService>());
    });

    test('postgresql uri resolves to built-in database session service', () {
      final ServiceRegistry registry = getServiceRegistry();
      final BaseSessionService? service = registry.createSessionService(
        'postgresql://localhost/app',
      );
      expect(service, isA<DatabaseSessionService>());
    });

    test('mysql uri resolves to built-in database session service', () {
      final ServiceRegistry registry = getServiceRegistry();
      final BaseSessionService? service = registry.createSessionService(
        'mysql://localhost/app',
      );
      expect(service, isA<DatabaseSessionService>());
    });

    test('gs uri resolves to built-in gcs artifact service', () {
      final ServiceRegistry registry = getServiceRegistry();
      final BaseArtifactService? service = registry.createArtifactService(
        'gs://demo-bucket',
      );
      expect(service, isA<GcsArtifactService>());
    });

    test('postgresql uri uses registered DatabaseSessionService adapter', () {
      DatabaseSessionService.registerCustomFactory(
        scheme: 'postgresql',
        factory: (_) => InMemorySessionService(),
      );

      final ServiceRegistry registry = getServiceRegistry();
      final BaseSessionService? service = registry.createSessionService(
        'postgresql://localhost/app',
      );
      expect(service, isA<DatabaseSessionService>());
    });
  });
}
