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
        await File(
          '$projectPath${Platform.pathSeparator}root_agent.yaml',
        ).exists(),
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

      final String rootAgentYaml = await File(
        '$projectPath${Platform.pathSeparator}root_agent.yaml',
      ).readAsString();
      expect(
        rootAgentYaml,
        contains(
          'instruction: Answer user questions to the best of your knowledge\n',
        ),
      );
    });

    test('loads fallback config when adk.json is missing', () async {
      final String projectPath =
          '${tempDir.path}${Platform.pathSeparator}fallback_agent';
      await Directory(projectPath).create(recursive: true);

      final DevProjectConfig config = await loadDevProjectConfig(projectPath);

      expect(config.appName, 'fallback_agent');
      expect(config.agentName, 'root_agent');
    });

    test('throws when requireConfigFile is true and adk.json is missing', () {
      final String projectPath =
          '${tempDir.path}${Platform.pathSeparator}missing_config_agent';

      return expectLater(
        loadDevProjectConfig(projectPath, requireConfigFile: true),
        throwsA(
          isA<FileSystemException>().having(
            (FileSystemException error) => error.message,
            'message',
            contains('Missing adk.json in project directory.'),
          ),
        ),
      );
    });

    test('throws when validateProjectDir is true and directory is missing', () {
      final String projectPath =
          '${tempDir.path}${Platform.pathSeparator}missing_dir_agent';

      return expectLater(
        loadDevProjectConfig(projectPath, validateProjectDir: true),
        throwsA(
          isA<FileSystemException>().having(
            (FileSystemException error) => error.message,
            'message',
            contains('Project directory does not exist.'),
          ),
        ),
      );
    });
  });
}
