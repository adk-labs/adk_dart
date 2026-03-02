import 'dart:io';

import 'package:adk_dart/src/cli/utils/agent_loader.dart';
import 'package:adk_dart/src/cli/utils/base_agent_loader.dart';
import 'package:test/test.dart';

void main() {
  group('AgentLoader', () {
    test('loads root_agent.yaml from a single-app root directory', () async {
      final Directory parent = await Directory.systemTemp.createTemp(
        'adk_agent_loader_single_parent_',
      );
      addTearDown(() async {
        if (await parent.exists()) {
          await parent.delete(recursive: true);
        }
      });

      final Directory appDir = Directory(
        '${parent.path}${Platform.pathSeparator}my_agent',
      );
      await appDir.create(recursive: true);
      await File(
        '${appDir.path}${Platform.pathSeparator}root_agent.yaml',
      ).writeAsString('''
name: root_agent
description: A helpful assistant for user questions.
instruction: Answer user questions to the best of your knowledge
model: gemini-2.5-flash
''');

      final AgentLoader loader = AgentLoader(appDir.path);
      final Object loaded = loader.loadAgent('my_agent');

      expect(asBaseAgent(loaded).name, 'root_agent');
    });

    test('loads root_agent.yaml from a nested app directory', () async {
      final Directory agentsRoot = await Directory.systemTemp.createTemp(
        'adk_agent_loader_multi_root_',
      );
      addTearDown(() async {
        if (await agentsRoot.exists()) {
          await agentsRoot.delete(recursive: true);
        }
      });

      final Directory appDir = Directory(
        '${agentsRoot.path}${Platform.pathSeparator}my_agent',
      );
      await appDir.create(recursive: true);
      await File(
        '${appDir.path}${Platform.pathSeparator}root_agent.yaml',
      ).writeAsString('''
name: root_agent
description: A helpful assistant for user questions.
instruction: Answer user questions to the best of your knowledge
model: gemini-2.5-flash
''');

      final AgentLoader loader = AgentLoader(agentsRoot.path);
      final Object loaded = loader.loadAgent('my_agent');

      expect(asBaseAgent(loaded).name, 'root_agent');
    });
  });
}
