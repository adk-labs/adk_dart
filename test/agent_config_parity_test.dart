import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('agent config parity', () {
    test('AgentConfig defaults discriminator to LlmAgent', () {
      final AgentConfig config = AgentConfig.fromJson(<String, Object?>{
        'name': 'root',
        'instruction': 'hello',
      });
      expect(config.root, isA<LlmAgentConfig>());
    });

    test('LlmAgentConfig normalizes legacy model mapping', () {
      final LlmAgentConfig config = LlmAgentConfig.fromJson(<String, Object?>{
        'name': 'root',
        'instruction': 'hello',
        'model': <String, Object?>{'name': 'models.make'},
      });

      expect(config.model, isNull);
      expect(config.modelCode, isNotNull);
      expect(config.modelCode!.name, 'models.make');
    });

    test('LlmAgentConfig rejects model and model_code together', () {
      expect(
        () => LlmAgentConfig.fromJson(<String, Object?>{
          'name': 'root',
          'instruction': 'hello',
          'model': 'gemini-2.5-flash',
          'model_code': <String, Object?>{'name': 'models.make'},
        }),
        throwsArgumentError,
      );
    });

    test('AgentRefConfig validates exactly one reference field', () {
      expect(() => AgentRefConfig(), throwsArgumentError);
      expect(
        () => AgentRefConfig(configPath: 'a.yaml', code: 'pkg.agent'),
        throwsArgumentError,
      );
      expect(AgentRefConfig(configPath: 'a.yaml').configPath, 'a.yaml');
      expect(AgentRefConfig(code: 'pkg.agent').code, 'pkg.agent');
    });

    test('ContextCacheConfig exposes ttl string and validation', () {
      final ContextCacheConfig config = ContextCacheConfig();
      expect(config.cacheIntervals, 10);
      expect(config.ttlSeconds, 1800);
      expect(config.minTokens, 0);
      expect(config.ttlString, '1800s');
      expect(config.toString(), contains('cache_intervals=10'));
      expect(() => ContextCacheConfig(cacheIntervals: 0), throwsArgumentError);
    });

    test('TranscriptionEntry accepts Content/InlineData only', () {
      expect(
        TranscriptionEntry(
          role: 'user',
          data: Content(role: 'user', parts: <Part>[Part.text('hi')]),
        ).role,
        'user',
      );
      expect(
        TranscriptionEntry(
          data: InlineData(mimeType: 'audio/wav', data: <int>[1, 2]),
        ).data,
        isA<InlineData>(),
      );
      expect(() => TranscriptionEntry(data: 123), throwsArgumentError);
    });

    test('resolveCodeReference supports positional and named args', () {
      String formatter(Object? value, {Object? suffix}) =>
          '$value-${suffix ?? ''}';

      final CodeConfig config = CodeConfig(
        name: 'pkg.formatter',
        args: <Object?>[
          <String, Object?>{'value': 'alpha'},
          <String, Object?>{'name': 'suffix', 'value': 'beta'},
        ],
      );

      final Object? resolved = resolveCodeReference(
        config,
        resolvers: AgentConfigResolvers(
          symbols: <String, Object?>{'pkg.formatter': formatter},
        ),
      );

      expect(resolved, 'alpha-beta');
    });

    test('fromConfig builds nested agents from YAML files', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_agent_cfg_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final File child = File('${dir.path}/child.yaml');
      await child.writeAsString('''
name: child
instruction: child instruction
''');

      final File root = File('${dir.path}/root.yaml');
      await root.writeAsString('''
name: root
instruction: root instruction
sub_agents:
  - config_path: child.yaml
''');

      final BaseAgent agent = fromConfig(root.path);
      expect(agent, isA<LlmAgent>());
      expect(agent.name, 'root');
      expect(agent.subAgents, hasLength(1));
      expect(agent.subAgents.single.name, 'child');
    });

    test('fromConfig supports custom agent factory registration', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_custom_agent_cfg_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final File root = File('${dir.path}/root.yaml');
      await root.writeAsString('''
agent_class: my.CustomAgent
name: custom_root
description: from custom factory
''');

      final BaseAgent agent = fromConfig(
        root.path,
        resolvers: AgentConfigResolvers(
          customAgentFactories: <String, CustomAgentFactory>{
            'my.CustomAgent':
                (BaseAgentConfig config, String _, AgentConfigResolvers __) {
                  return SequentialAgent(
                    name: config.name,
                    description: config.description,
                  );
                },
          },
        ),
      );

      expect(agent, isA<SequentialAgent>());
      expect(agent.name, 'custom_root');
      expect(agent.description, 'from custom factory');
    });
  });
}
