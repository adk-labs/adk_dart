import 'dart:io';

import 'package:adk_dart/src/dev/project.dart';
import 'package:test/test.dart';

void main() {
  group('createDevProject', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('adk_dart_project_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('creates scaffold files and loadable config', () async {
      final String projectPath =
          '${tempDir.path}${Platform.pathSeparator}my_agent';
      await createDevProject(projectDirPath: projectPath);

      expect(
        await File('$projectPath${Platform.pathSeparator}adk.json').exists(),
        isTrue,
      );
      expect(
        await File('$projectPath${Platform.pathSeparator}.env').exists(),
        isTrue,
      );
      expect(
        await File('$projectPath${Platform.pathSeparator}agent.dart').exists(),
        isTrue,
      );
      expect(
        await File('$projectPath${Platform.pathSeparator}README.md').exists(),
        isTrue,
      );

      final DevProjectConfig config = await loadDevProjectConfig(projectPath);
      expect(config.appName, 'my_agent');
      expect(config.agentName, 'root_agent');
    });
  });
}
