import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('DotAdkFolder', () {
    test('builds canonical paths', () {
      final Directory temp = Directory.systemTemp.createTempSync(
        'adk_cli_dot_',
      );
      addTearDown(() => temp.deleteSync(recursive: true));

      final DotAdkFolder folder = dotAdkFolderForAgent(
        agentsRoot: temp.path,
        appName: 'my_agent',
      );

      expect(folder.agentDir.path, contains('my_agent'));
      expect(folder.dotAdkDir.path, endsWith('${Platform.pathSeparator}.adk'));
      expect(folder.artifactsDir.path, contains('.adk'));
      expect(folder.sessionDbPath.path, endsWith('session.db'));
    });

    test('rejects path traversal', () {
      final Directory temp = Directory.systemTemp.createTempSync(
        'adk_cli_dot_',
      );
      addTearDown(() => temp.deleteSync(recursive: true));

      expect(
        () => dotAdkFolderForAgent(agentsRoot: temp.path, appName: '../escape'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
