import 'dart:convert';
import 'dart:io';

import 'package:adk/cli.dart';
import 'package:adk/src/cli/cli_tools_click.dart' as click_cli;
import 'package:adk/src/dev/cli.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/tools/base_tool.dart';
import 'package:adk_dart/src/tools/tool_context.dart';
import 'package:test/test.dart';

class _TitledTestTool extends BaseTool {
  _TitledTestTool({required super.name, super.title})
    : super(description: 'Titled test tool');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return 'ok';
  }
}

class _StringSinkAdapter implements IOSink {
  final StringBuffer _buffer = StringBuffer();

  String get text => _buffer.toString();

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) => _buffer.write(utf8.decode(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) async {
    await for (final List<int> chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<dynamic> close() async {}

  @override
  Future<dynamic> get done async {}

  @override
  Future<dynamic> flush() async {}

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('adk_cli_parity_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('adk generate_agent_card', () {
    test('generates agent.json from agent directory and via CLI command', () async {
      final Directory agentDir = Directory('${tempDir.path}/weather_agent')
        ..createSync(recursive: true);
      File('${agentDir.path}/root_agent.yaml').writeAsStringSync('''
name: weather_agent
description: Weather forecasting assistant
instruction: Provide accurate weather reports.
model: gemini-2.5-flash
''');

      final _StringSinkAdapter out = _StringSinkAdapter();
      final _StringSinkAdapter err = _StringSinkAdapter();
      final int exitCode = await runAdkCli(
        <String>[
          'generate_agent_card',
          agentDir.path,
          '--card_url',
          'https://agents.example.com/a2a',
        ],
        outSink: out,
        errSink: err,
      );
      expect(exitCode, 0);
      expect(out.text, contains('Agent card generated successfully at'));

      final File cardFile = File('${agentDir.path}/agent.json');
      expect(cardFile.existsSync(), isTrue);
      final Map<String, Object?> cardJson =
          jsonDecode(cardFile.readAsStringSync()) as Map<String, Object?>;
      expect(cardJson['name'], 'weather_agent');
      expect(cardJson['description'], 'Weather forecasting assistant');
      expect(cardJson['url'], 'https://agents.example.com/a2a');
      expect(cardJson['skills'], isA<List<Object?>>());
    });

    test('CliToolsClickDispatcher routes generate_agent_card', () async {
      final Directory agentDir = Directory('${tempDir.path}/click_agent')
        ..createSync(recursive: true);
      File('${agentDir.path}/root_agent.yaml').writeAsStringSync('''
name: click_agent
description: Click test agent
instruction: Help users.
model: gemini-2.5-flash
''');
      final File customOut = File('${tempDir.path}/custom_card.json');
      final int code = await click_cli.main(<String>[
        'generate_agent_card',
        agentDir.path,
        '-o',
        customOut.path,
      ]);
      expect(code, 0);
      expect(customOut.existsSync(), isTrue);
    });
  });

  group('agent_graph displayTitle & tool highlightPairs', () {
    test('uses BaseTool.displayTitle for node label and highlights tool call/response pairs by tool.name', () async {
      final _TitledTestTool tool = _TitledTestTool(
        name: 'get_weather_v2',
        title: 'Weather Forecast Tool',
      );
      final LlmAgent agent = LlmAgent(
        name: 'root_agent',
        model: 'gemini-2.5-flash',
        tools: <Object>[tool],
      );

      final AgentGraph graph = await buildGraph(agent);
      final AgentGraphNode toolNode = graph.nodes.firstWhere(
        (AgentGraphNode node) => node.id == 'tool:get_weather_v2',
      );
      expect(toolNode.caption, '🧰 Weather Forecast Tool');

      final String mermaidSource = await getAgentGraph(
        agent,
        highlightPairs: <(String, String)>{
          ('root_agent', 'get_weather_v2'),
        },
      );
      expect(mermaidSource, contains('🧰 Weather Forecast Tool'));
      expect(mermaidSource, contains('root_agent ==> tool_get_weather_v2'));
    });
  });

  group('adk run --reload_agents & adk eval --parallelism', () {
    test('parseAdkCliArgs parses --reload_agents and --no-reload_agents on run command', () {
      final ParsedAdkCommand defaultRun = parseAdkCliArgs(<String>[
        'run',
        './my_agent',
      ]);
      expect(defaultRun.reloadAgents, isFalse);

      final ParsedAdkCommand enabledRun = parseAdkCliArgs(<String>[
        'run',
        '--reload_agents',
        './my_agent',
      ]);
      expect(enabledRun.reloadAgents, isTrue);

      final ParsedAdkCommand disabledRun = parseAdkCliArgs(<String>[
        'run',
        '--reload_agents',
        '--no-reload_agents',
        './my_agent',
      ]);
      expect(disabledRun.reloadAgents, isFalse);
    });

    test('adk eval rejects invalid --parallelism values', () async {
      final _StringSinkAdapter out = _StringSinkAdapter();
      final _StringSinkAdapter err = _StringSinkAdapter();
      final int exitCode = await runAdkCli(
        <String>[
          'eval',
          tempDir.path,
          'some_eval_set',
          '--parallelism=0',
        ],
        outSink: out,
        errSink: err,
      );
      expect(exitCode, 64);
      expect(err.text, contains("Invalid value for '--parallelism'"));
    });
  });

  group('DockerDeployer & cli_deploy extraPackages', () {
    test('validates extra package names and stages plain + installable packages into Dockerfile', () async {
      expect(() => validateExtraPackageName('../evil'), throwsArgumentError);
      expect(() => validateExtraPackageName('agents'), throwsArgumentError);
      expect(validateExtraPackageName('shared_utils'), 'shared_utils');

      final Directory agentDir = Directory('${tempDir.path}/my_agent')
        ..createSync(recursive: true);
      File('${agentDir.path}/requirements.txt').writeAsStringSync('pydantic\n');

      final Directory plainPkg = Directory('${tempDir.path}/plain_utils')
        ..createSync(recursive: true);
      File('${plainPkg.path}/helper.py').writeAsStringSync('X = 1\n');

      final Directory installablePkg = Directory('${tempDir.path}/install_pkg')
        ..createSync(recursive: true);
      File('${installablePkg.path}/pyproject.toml').writeAsStringSync(
        '[project]\nname = "install_pkg"\nversion = "0.1.0"\n',
      );

      final Directory stagingDir = Directory('${tempDir.path}/staging');
      final DockerDeployer deployer = DockerDeployer();
      await deployer.deploy(
        agentFolder: agentDir.path,
        tempFolder: stagingDir.path,
        extraPackages: <String>[plainPkg.path, installablePkg.path],
      );

      expect(Directory('${stagingDir.path}/plain_utils').existsSync(), isTrue);
      expect(Directory('${stagingDir.path}/install_pkg').existsSync(), isTrue);

      final String dockerfile =
          File('${stagingDir.path}/Dockerfile').readAsStringSync();
      expect(dockerfile, contains('# Copy extra packages - Start'));
      expect(
        dockerfile,
        contains('COPY --chown=myuser:myuser "plain_utils" "/app/plain_utils"'),
      );
      expect(
        dockerfile,
        contains('COPY --chown=myuser:myuser "install_pkg" "/app/install_pkg"'),
      );
      expect(
        dockerfile,
        contains('RUN pip install --no-cache-dir "/app/install_pkg"'),
      );
      expect(dockerfile, contains(r'ENV PYTHONPATH="/app:$PYTHONPATH"'));
      expect(dockerfile, contains('# Copy extra packages - End'));
    });
  });
}
