/// CLI command implementation for `adk generate_agent_card`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/src/a2a/protocol.dart';
import 'package:adk_dart/src/a2a/utils/agent_card_builder.dart';
import 'package:adk_dart/src/agents/base_agent.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';

import 'utils/agent_loader.dart';
import 'utils/base_agent_loader.dart';

/// Usage text for `adk generate_agent_card`.
const String generateAgentCardUsage = '''
Usage: adk generate_agent_card [options] <agent>

Generates an A2A AgentCard JSON file from an agent directory.

Options:
  -o, --output_file <path>   Output file path (default: <agent>/agent.json)
      --card_url <url>       RPC URL in the generated card (default: http://localhost:8000/a2a/<agent_name>)
  -h, --help                 Show this help message
''';

/// Generates an A2A [AgentCard] JSON file from [agent] (either a directory path
/// or a [BaseAgent] instance) and writes it to [outputFile] (or `<agent>/agent.json`).
Future<File> generateAgentCard({
  required Object agent,
  String? outputFile,
  String? cardUrl,
  BaseAgentLoader? agentLoader,
  IOSink? outSink,
}) async {
  final BaseAgent rootAgent;
  final String agentName;
  final Directory? agentDir;

  if (agent is BaseAgent) {
    rootAgent = agent;
    agentName = agent.name.isEmpty ? 'root_agent' : agent.name;
    agentDir = null;
  } else {
    final String rawPath = '$agent'.trim();
    if (rawPath.isEmpty) {
      throw ArgumentError('Agent directory path is required.');
    }
    final Directory resolvedDir = Directory(rawPath).absolute;
    if (!resolvedDir.existsSync()) {
      throw FileSystemException(
        'Agent directory does not exist.',
        resolvedDir.path,
      );
    }
    agentDir = resolvedDir;
    final String dirPath = resolvedDir.path.replaceAll(RegExp(r'[/\\]+$'), '');
    agentName = dirPath.split(RegExp(r'[/\\]')).last;
    rootAgent = _loadRootAgentFromDirectory(
      resolvedDir,
      agentName: agentName,
      agentLoader: agentLoader,
    );
  }

  final String resolvedUrl = (cardUrl != null && cardUrl.trim().isNotEmpty)
      ? cardUrl.trim()
      : 'http://localhost:8000/a2a/$agentName';

  final AgentCardBuilder builder = AgentCardBuilder(
    agent: rootAgent,
    rpcUrl: resolvedUrl,
  );
  final AgentCard agentCard = await builder.build();

  final String resolvedOutputPath;
  if (outputFile != null && outputFile.trim().isNotEmpty) {
    resolvedOutputPath = File(outputFile.trim()).absolute.path;
  } else if (agentDir != null) {
    resolvedOutputPath =
        '${agentDir.path}${Platform.pathSeparator}agent.json';
  } else {
    throw ArgumentError(
      'outputFile must be provided when generating a card directly from a BaseAgent.',
    );
  }

  final File targetFile = File(resolvedOutputPath);
  await targetFile.parent.create(recursive: true);

  final Map<String, Object?> sortedJson = _sortMapKeysRecursively(
    agentCard.toJson(),
  );
  final String formattedJson =
      '${const JsonEncoder.withIndent('  ').convert(sortedJson)}\n';
  await targetFile.writeAsString(formattedJson);

  outSink?.writeln('Agent card generated successfully at ${targetFile.path}');
  return targetFile;
}

/// Runs the `adk generate_agent_card` CLI command.
Future<int> runGenerateAgentCardCommand(
  List<String> args, {
  IOSink? outSink,
  IOSink? errSink,
  BaseAgentLoader? agentLoader,
}) async {
  final IOSink out = outSink ?? stdout;
  final IOSink err = errSink ?? stderr;

  if (args.any((String arg) => arg == '--help' || arg == '-h')) {
    out.writeln(generateAgentCardUsage);
    return 0;
  }

  String? agentPath;
  String? outputFile;
  String? cardUrl;

  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '-o' || arg == '--output_file' || arg == '--output-file') {
      if (i + 1 >= args.length) {
        err.writeln('Missing value for $arg.');
        err.writeln(generateAgentCardUsage);
        return 64;
      }
      outputFile = args[i + 1];
      i += 1;
      continue;
    }
    if (arg.startsWith('--output_file=')) {
      outputFile = arg.substring('--output_file='.length);
      continue;
    }
    if (arg.startsWith('--output-file=')) {
      outputFile = arg.substring('--output-file='.length);
      continue;
    }
    if (arg == '--card_url' || arg == '--card-url') {
      if (i + 1 >= args.length) {
        err.writeln('Missing value for $arg.');
        err.writeln(generateAgentCardUsage);
        return 64;
      }
      cardUrl = args[i + 1];
      i += 1;
      continue;
    }
    if (arg.startsWith('--card_url=')) {
      cardUrl = arg.substring('--card_url='.length);
      continue;
    }
    if (arg.startsWith('--card-url=')) {
      cardUrl = arg.substring('--card-url='.length);
      continue;
    }
    if (arg.startsWith('-')) {
      err.writeln('Unknown option for generate_agent_card: $arg');
      err.writeln(generateAgentCardUsage);
      return 64;
    }
    if (agentPath != null) {
      err.writeln('Unexpected extra positional argument: $arg');
      err.writeln(generateAgentCardUsage);
      return 64;
    }
    agentPath = arg;
  }

  if (agentPath == null || agentPath.trim().isEmpty) {
    err.writeln('Missing required <agent> directory argument.');
    err.writeln(generateAgentCardUsage);
    return 64;
  }

  try {
    await generateAgentCard(
      agent: agentPath,
      outputFile: outputFile,
      cardUrl: cardUrl,
      agentLoader: agentLoader,
      outSink: out,
    );
    return 0;
  } catch (error) {
    err.writeln('Error generating agent card: $error');
    return 1;
  }
}

BaseAgent _loadRootAgentFromDirectory(
  Directory agentDir, {
  required String agentName,
  BaseAgentLoader? agentLoader,
}) {
  final BaseAgentLoader loader =
      agentLoader ?? AgentLoader(agentDir.parent.path);
  try {
    final AgentOrApp loaded = loader.loadAgent(agentName);
    return asBaseAgent(loaded);
  } catch (_) {
    // Fallback for Python-only agent directories containing agent.py or __init__.py.
    final String sep = Platform.pathSeparator;
    final File agentPy = File('${agentDir.path}${sep}agent.py');
    final File initPy = File('${agentDir.path}$sep' '__init__.py');
    if (agentPy.existsSync() || initPy.existsSync()) {
      final String source = agentPy.existsSync()
          ? agentPy.readAsStringSync()
          : initPy.readAsStringSync();
      final RegExp nameMatch = RegExp(
        r'''name\s*=\s*['"]([^'"]+)['"]''',
      );
      final RegExp descMatch = RegExp(
        r'''description\s*=\s*['"]([^'"]*)['"]''',
      );
      final RegExp instrMatch = RegExp(
        r'''instruction\s*=\s*['"]([^'"]*)['"]''',
      );
      final String resolvedName =
          nameMatch.firstMatch(source)?.group(1) ?? agentName;
      final String resolvedDescription =
          descMatch.firstMatch(source)?.group(1) ?? '';
      final String resolvedInstruction =
          instrMatch.firstMatch(source)?.group(1) ?? '';
      return Agent(
        name: resolvedName,
        description: resolvedDescription,
        instruction: resolvedInstruction,
        model: 'gemini-2.5-flash',
      );
    }
    rethrow;
  }
}

Map<String, Object?> _sortMapKeysRecursively(Map<String, Object?> map) {
  final List<String> keys = map.keys.toList()..sort();
  final Map<String, Object?> result = <String, Object?>{};
  for (final String key in keys) {
    result[key] = _sortValueRecursively(map[key]);
  }
  return result;
}

Object? _sortValueRecursively(Object? value) {
  if (value is Map) {
    final Map<String, Object?> stringMap = value.map(
      (Object? k, Object? v) => MapEntry('$k', v),
    );
    return _sortMapKeysRecursively(stringMap);
  }
  if (value is List) {
    return value.map(_sortValueRecursively).toList(growable: false);
  }
  return value;
}
