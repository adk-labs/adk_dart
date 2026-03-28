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

    test(
      'loads single-app root when appName alias differs from directory',
      () async {
        final Directory parent = await Directory.systemTemp.createTemp(
          'adk_agent_loader_alias_parent_',
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
        await File(
          '${appDir.path}${Platform.pathSeparator}adk.json',
        ).writeAsString('{"appName":"foo_app"}');

        final AgentLoader loader = AgentLoader(appDir.path);
        final Object loaded = loader.loadAgent('foo_app');

        expect(asBaseAgent(loaded).name, 'root_agent');
      },
    );

    test(
      'listAgents includes non-hidden directories without validating agents',
      () async {
        final Directory agentsRoot = await Directory.systemTemp.createTemp(
          'adk_agent_loader_list_root_',
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
        ).writeAsString('name: root_agent\ndescription: d\ninstruction: i\n');
        await Directory(
          '${agentsRoot.path}${Platform.pathSeparator}notes',
        ).create();
        await Directory(
          '${agentsRoot.path}${Platform.pathSeparator}__pycache__',
        ).create();
        await Directory(
          '${agentsRoot.path}${Platform.pathSeparator}.hidden',
        ).create();

        final AgentLoader loader = AgentLoader(agentsRoot.path);

        expect(loader.listAgents(), <String>['my_agent', 'notes']);
      },
    );

    test('listAgentsDetailed skips directories that fail to load', () async {
      final Directory agentsRoot = await Directory.systemTemp.createTemp(
        'adk_agent_loader_detailed_root_',
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
      ).writeAsString('name: root_agent\ndescription: d\ninstruction: i\n');
      await Directory(
        '${agentsRoot.path}${Platform.pathSeparator}notes',
      ).create();

      final AgentLoader loader = AgentLoader(agentsRoot.path);
      final List<Map<String, Object?>> detailed = loader.listAgentsDetailed();

      expect(detailed, hasLength(1));
      expect(detailed.single['name'], 'my_agent');
      expect(detailed.single['language'], 'yaml');
    });

    test('listAgents exposes configured alias for a single-app root', () async {
      final Directory parent = await Directory.systemTemp.createTemp(
        'adk_agent_loader_single_list_parent_',
      );
      addTearDown(() async {
        if (await parent.exists()) {
          await parent.delete(recursive: true);
        }
      });

      final Directory appDir = Directory(
        '${parent.path}${Platform.pathSeparator}single_agent',
      );
      await appDir.create(recursive: true);
      await File(
        '${appDir.path}${Platform.pathSeparator}root_agent.yaml',
      ).writeAsString('name: root_agent\ndescription: d\ninstruction: i\n');
      await File(
        '${appDir.path}${Platform.pathSeparator}adk.json',
      ).writeAsString('{"appName":"foo_app"}');

      final AgentLoader loader = AgentLoader(appDir.path);

      expect(loader.listAgents(), <String>['foo_app']);
    });

    test('listAgentsDetailed resolves single-app aliases', () async {
      final Directory parent = await Directory.systemTemp.createTemp(
        'adk_agent_loader_single_detail_parent_',
      );
      addTearDown(() async {
        if (await parent.exists()) {
          await parent.delete(recursive: true);
        }
      });

      final Directory appDir = Directory(
        '${parent.path}${Platform.pathSeparator}single_agent',
      );
      await appDir.create(recursive: true);
      await File(
        '${appDir.path}${Platform.pathSeparator}root_agent.yaml',
      ).writeAsString('name: root_agent\ndescription: d\ninstruction: i\n');
      await File(
        '${appDir.path}${Platform.pathSeparator}adk.json',
      ).writeAsString('{"appName":"foo_app"}');

      final AgentLoader loader = AgentLoader(appDir.path);
      final List<Map<String, Object?>> detailed = loader.listAgentsDetailed();

      expect(detailed, hasLength(1));
      expect(detailed.single['name'], 'foo_app');
      expect(detailed.single['language'], 'yaml');
    });

    test(
      'loadAgent rejects invalid agent names before resolving paths',
      () async {
        final Directory agentsRoot = await Directory.systemTemp.createTemp(
          'adk_agent_loader_invalid_name_root_',
        );
        addTearDown(() async {
          if (await agentsRoot.exists()) {
            await agentsRoot.delete(recursive: true);
          }
        });

        final AgentLoader loader = AgentLoader(agentsRoot.path);
        const List<String> invalidNames = <String>[
          '../secret',
          'foo/bar',
          'foo.bar',
          'foo bar',
          'foo-bar',
        ];

        for (final String invalidName in invalidNames) {
          expect(
            () => loader.loadAgent(invalidName),
            throwsA(isA<ArgumentError>()),
            reason: invalidName,
          );
        }
      },
    );

    test('loadAgent rejects missing agents before attempting load', () async {
      final Directory agentsRoot = await Directory.systemTemp.createTemp(
        'adk_agent_loader_missing_root_',
      );
      addTearDown(() async {
        if (await agentsRoot.exists()) {
          await agentsRoot.delete(recursive: true);
        }
      });

      final AgentLoader loader = AgentLoader(agentsRoot.path);

      expect(
        () => loader.loadAgent('missing_agent'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('loadAgent rejects unknown aliases for a single-app root', () async {
      final Directory parent = await Directory.systemTemp.createTemp(
        'adk_agent_loader_unknown_alias_parent_',
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
      ).writeAsString('name: root_agent\ndescription: d\ninstruction: i\n');
      await File(
        '${appDir.path}${Platform.pathSeparator}adk.json',
      ).writeAsString('{"appName":"foo_app"}');

      final AgentLoader loader = AgentLoader(appDir.path);

      expect(() => loader.loadAgent('bar_app'), throwsA(isA<ArgumentError>()));
    });
  });
}
