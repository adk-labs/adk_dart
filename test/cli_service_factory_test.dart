import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('service factory', () {
    setUp(resetServiceRegistryForTest);

    test('falls back to in-memory when local storage disabled', () {
      final Directory temp = Directory.systemTemp.createTempSync('adk_cli_sf_');
      addTearDown(() => temp.deleteSync(recursive: true));

      final BaseSessionService sessionService = createSessionServiceFromOptions(
        baseDir: temp.path,
        useLocalStorage: false,
      );
      final BaseArtifactService artifactService =
          createArtifactServiceFromOptions(
            baseDir: temp.path,
            useLocalStorage: false,
          );
      final BaseMemoryService memoryService = createMemoryServiceFromOptions(
        baseDir: temp.path,
      );

      expect(sessionService, isA<InMemorySessionService>());
      expect(artifactService, isA<InMemoryArtifactService>());
      expect(memoryService, isA<InMemoryMemoryService>());
    });

    test('creates local sqlite service when local storage enabled', () {
      final Directory temp = Directory.systemTemp.createTempSync('adk_cli_sf_');
      addTearDown(() => temp.deleteSync(recursive: true));

      final BaseSessionService service = createSessionServiceFromOptions(
        baseDir: temp.path,
        useLocalStorage: true,
      );

      expect(service, isA<PerAgentDatabaseSessionService>());
    });

    test('creates service from explicit URIs', () {
      final Directory temp = Directory.systemTemp.createTempSync('adk_cli_sf_');
      addTearDown(() => temp.deleteSync(recursive: true));

      final BaseSessionService sessionService = createSessionServiceFromOptions(
        baseDir: temp.path,
        sessionServiceUri: 'memory://',
      );
      final BaseArtifactService artifactService =
          createArtifactServiceFromOptions(
            baseDir: temp.path,
            artifactServiceUri: 'memory://',
          );
      final BaseMemoryService memoryService = createMemoryServiceFromOptions(
        baseDir: temp.path,
        memoryServiceUri: 'memory://',
      );

      expect(sessionService, isA<InMemorySessionService>());
      expect(artifactService, isA<InMemoryArtifactService>());
      expect(memoryService, isA<InMemoryMemoryService>());
    });
  });
}
