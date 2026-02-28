import 'dart:convert';
import 'dart:io';

import '../models/base_llm.dart';
import '../models/llm_request.dart';
import '../tools/base_tool.dart';
import '../tools/base_toolset.dart';
import '../tools/tool_configs.dart';
import 'agent_config.dart';
import 'base_agent.dart';
import 'base_agent_config.dart';
import 'common_configs.dart';
import 'llm_agent.dart';
import 'llm_agent_config.dart';
import 'loop_agent.dart';
import 'loop_agent_config.dart';
import 'parallel_agent.dart';
import 'parallel_agent_config.dart';
import 'sequential_agent.dart';
import 'sequential_agent_config.dart';

typedef SymbolResolver = Object? Function(String fullyQualifiedName);
typedef CustomAgentFactory =
    BaseAgent Function(
      BaseAgentConfig config,
      String configAbsPath,
      AgentConfigResolvers resolvers,
    );

const Set<String> _builtInAgentClasses = <String>{
  'LlmAgent',
  'LoopAgent',
  'ParallelAgent',
  'SequentialAgent',
};

class AgentConfigResolvers {
  AgentConfigResolvers({
    this.symbolResolver,
    Map<String, Object?>? symbols,
    Map<String, CustomAgentFactory>? customAgentFactories,
  }) : symbols = symbols ?? <String, Object?>{},
       customAgentFactories =
           customAgentFactories ?? <String, CustomAgentFactory>{};

  final SymbolResolver? symbolResolver;
  final Map<String, Object?> symbols;
  final Map<String, CustomAgentFactory> customAgentFactories;

  Object? resolveSymbol(String name) {
    if (symbols.containsKey(name)) {
      return symbols[name];
    }
    return symbolResolver?.call(name);
  }
}

BaseAgent fromConfig(String configPath, {AgentConfigResolvers? resolvers}) {
  final String absPath = File(configPath).absolute.path;
  final AgentConfig config = _loadConfigFromPath(absPath);
  final AgentConfigResolvers resolvedResolvers =
      resolvers ?? AgentConfigResolvers();
  return _buildAgentFromConfig(config.root, absPath, resolvedResolvers);
}

AgentConfig _loadConfigFromPath(String configPath) {
  final File file = File(configPath);
  if (!file.existsSync()) {
    throw FileSystemException('Config file not found', configPath);
  }

  final String content = file.readAsStringSync();
  final Object? decoded = _decodeConfigDocument(content);
  if (decoded is! Map) {
    throw ArgumentError('Agent config must decode into a mapping.');
  }
  final Map<String, Object?> json = decoded.map(
    (Object? key, Object? value) => MapEntry('$key', value),
  );
  return AgentConfig.fromJson(json);
}

Object? resolveFullyQualifiedName(
  String name, {
  required AgentConfigResolvers resolvers,
}) {
  final Object? value = resolvers.resolveSymbol(name);
  if (value == null) {
    throw ArgumentError('Invalid fully qualified name: $name');
  }
  return value;
}

BaseAgent resolveAgentReference(
  AgentRefConfig refConfig,
  String referencingAgentConfigAbsPath, {
  required AgentConfigResolvers resolvers,
}) {
  if (refConfig.configPath != null) {
    final String configuredPath = refConfig.configPath!;
    final String targetPath = _isAbsolutePath(configuredPath)
        ? configuredPath
        : _joinPath(
            File(referencingAgentConfigAbsPath).parent.path,
            configuredPath,
          );
    return fromConfig(targetPath, resolvers: resolvers);
  }

  if (refConfig.code != null) {
    return _resolveAgentCodeReference(refConfig.code!, resolvers: resolvers);
  }

  throw ArgumentError(
    'AgentRefConfig must have either `code` or `config_path`.',
  );
}

Object? resolveCodeReference(
  CodeConfig codeConfig, {
  required AgentConfigResolvers resolvers,
}) {
  if (codeConfig.name.trim().isEmpty) {
    throw ArgumentError('Invalid CodeConfig.');
  }

  final Object? obj = resolveFullyQualifiedName(
    codeConfig.name,
    resolvers: resolvers,
  );
  if (obj is Function && codeConfig.args.isNotEmpty) {
    final List<Object?> positional = <Object?>[];
    final Map<Symbol, Object?> named = <Symbol, Object?>{};
    for (final ArgumentConfig arg in codeConfig.args) {
      if (arg.name == null || arg.name!.isEmpty) {
        positional.add(arg.value);
      } else {
        named[Symbol(arg.name!)] = arg.value;
      }
    }
    return Function.apply(obj, positional, named);
  }
  return obj;
}

List<Object?> resolveCallbacks(
  List<CodeConfig> callbacksConfig, {
  required AgentConfigResolvers resolvers,
}) {
  return callbacksConfig
      .map(
        (CodeConfig config) =>
            resolveCodeReference(config, resolvers: resolvers),
      )
      .toList(growable: false);
}

BaseAgent _buildAgentFromConfig(
  BaseAgentConfig config,
  String configAbsPath,
  AgentConfigResolvers resolvers,
) {
  final String agentClass = _normalizeAgentClassName(config.agentClass);
  final BaseAgentConfig normalized = _normalizeConfigForAgentClass(
    config,
    agentClass,
  );
  return switch (agentClass) {
    'LlmAgent' => _buildLlmAgent(
      normalized as LlmAgentConfig,
      configAbsPath,
      resolvers,
    ),
    'LoopAgent' => _buildLoopAgent(
      normalized as LoopAgentConfig,
      configAbsPath,
      resolvers,
    ),
    'ParallelAgent' => _buildParallelAgent(
      normalized as ParallelAgentConfig,
      configAbsPath,
      resolvers,
    ),
    'SequentialAgent' => _buildSequentialAgent(
      normalized as SequentialAgentConfig,
      configAbsPath,
      resolvers,
    ),
    _ => _buildCustomAgent(normalized, configAbsPath, resolvers),
  };
}

BaseAgentConfig _normalizeConfigForAgentClass(
  BaseAgentConfig config,
  String agentClass,
) {
  final Map<String, Object?> json = config.toJson();
  return switch (agentClass) {
    'LlmAgent' =>
      config is LlmAgentConfig ? config : LlmAgentConfig.fromJson(json),
    'LoopAgent' =>
      config is LoopAgentConfig ? config : LoopAgentConfig.fromJson(json),
    'ParallelAgent' =>
      config is ParallelAgentConfig
          ? config
          : ParallelAgentConfig.fromJson(json),
    'SequentialAgent' =>
      config is SequentialAgentConfig
          ? config
          : SequentialAgentConfig.fromJson(json),
    _ => config,
  };
}

BaseAgent _buildCustomAgent(
  BaseAgentConfig config,
  String configAbsPath,
  AgentConfigResolvers resolvers,
) {
  final String configuredName = config.agentClass.trim().isEmpty
      ? 'LlmAgent'
      : config.agentClass.trim();
  final String shortName = configuredName.split('.').last;
  final CustomAgentFactory? factory =
      resolvers.customAgentFactories[configuredName] ??
      resolvers.customAgentFactories[shortName];
  if (factory != null) {
    return factory(config, configAbsPath, resolvers);
  }

  final Object? resolvedFactory =
      resolvers.resolveSymbol(configuredName) ??
      resolvers.resolveSymbol(shortName);
  if (resolvedFactory is CustomAgentFactory) {
    return resolvedFactory(config, configAbsPath, resolvers);
  }

  final String displayName = configuredName;
  throw ArgumentError(
    'Invalid agent class `$displayName`. Register it in AgentConfigResolvers.customAgentFactories.',
  );
}

String _normalizeAgentClassName(String agentClass) {
  final String trimmed = agentClass.trim();
  if (trimmed.isEmpty) {
    return 'LlmAgent';
  }

  if (_builtInAgentClasses.contains(trimmed)) {
    return trimmed;
  }
  final String shortName = trimmed.split('.').last;
  if (_builtInAgentClasses.contains(shortName)) {
    return shortName;
  }
  return trimmed;
}

BaseAgent _buildLoopAgent(
  LoopAgentConfig config,
  String configAbsPath,
  AgentConfigResolvers resolvers,
) {
  final _BaseAgentConstructorArgs args = _createBaseAgentArgs(
    config,
    configAbsPath,
    resolvers,
  );
  return LoopAgent(
    name: config.name,
    description: config.description,
    subAgents: args.subAgents,
    beforeAgentCallback: args.beforeAgentCallbacks,
    afterAgentCallback: args.afterAgentCallbacks,
    maxIterations: config.maxIterations,
  );
}

BaseAgent _buildParallelAgent(
  ParallelAgentConfig config,
  String configAbsPath,
  AgentConfigResolvers resolvers,
) {
  final _BaseAgentConstructorArgs args = _createBaseAgentArgs(
    config,
    configAbsPath,
    resolvers,
  );
  return ParallelAgent(
    name: config.name,
    description: config.description,
    subAgents: args.subAgents,
    beforeAgentCallback: args.beforeAgentCallbacks,
    afterAgentCallback: args.afterAgentCallbacks,
  );
}

BaseAgent _buildSequentialAgent(
  SequentialAgentConfig config,
  String configAbsPath,
  AgentConfigResolvers resolvers,
) {
  final _BaseAgentConstructorArgs args = _createBaseAgentArgs(
    config,
    configAbsPath,
    resolvers,
  );
  return SequentialAgent(
    name: config.name,
    description: config.description,
    subAgents: args.subAgents,
    beforeAgentCallback: args.beforeAgentCallbacks,
    afterAgentCallback: args.afterAgentCallbacks,
  );
}

BaseAgent _buildLlmAgent(
  LlmAgentConfig config,
  String configAbsPath,
  AgentConfigResolvers resolvers,
) {
  final _BaseAgentConstructorArgs args = _createBaseAgentArgs(
    config,
    configAbsPath,
    resolvers,
  );

  final Object model = config.modelCode != null
      ? resolveCodeReference(config.modelCode!, resolvers: resolvers) ?? ''
      : (config.model ?? '');
  if (model is! String && model is! BaseLlm) {
    throw ArgumentError(
      'Resolved model must be String or BaseLlm, got `${model.runtimeType}`.',
    );
  }

  return LlmAgent(
    name: config.name,
    description: config.description,
    subAgents: args.subAgents,
    beforeAgentCallback: args.beforeAgentCallbacks,
    afterAgentCallback: args.afterAgentCallbacks,
    model: model,
    instruction: config.instruction,
    staticInstruction: config.staticInstruction,
    disallowTransferToParent: config.disallowTransferToParent ?? false,
    disallowTransferToPeers: config.disallowTransferToPeers ?? false,
    includeContents: config.includeContents,
    inputSchema: config.inputSchema == null
        ? null
        : resolveCodeReference(config.inputSchema!, resolvers: resolvers),
    outputSchema: config.outputSchema == null
        ? null
        : resolveCodeReference(config.outputSchema!, resolvers: resolvers),
    outputKey: config.outputKey,
    tools: config.tools
        .map(
          (ToolConfig toolConfig) =>
              _resolveTool(toolConfig, configAbsPath, resolvers),
        )
        .toList(growable: false),
    beforeModelCallback: config.beforeModelCallbacks.isEmpty
        ? null
        : resolveCallbacks(config.beforeModelCallbacks, resolvers: resolvers),
    afterModelCallback: config.afterModelCallbacks.isEmpty
        ? null
        : resolveCallbacks(config.afterModelCallbacks, resolvers: resolvers),
    beforeToolCallback: config.beforeToolCallbacks.isEmpty
        ? null
        : resolveCallbacks(config.beforeToolCallbacks, resolvers: resolvers),
    afterToolCallback: config.afterToolCallbacks.isEmpty
        ? null
        : resolveCallbacks(config.afterToolCallbacks, resolvers: resolvers),
    generateContentConfig: config.generateContentConfig == null
        ? null
        : _toGenerateContentConfig(config.generateContentConfig!),
  );
}

Object _resolveTool(
  ToolConfig toolConfig,
  String configAbsPath,
  AgentConfigResolvers resolvers,
) {
  final Object obj = resolveFullyQualifiedName(
    toolConfig.name,
    resolvers: resolvers,
  )!;
  if (obj is BaseTool || obj is BaseToolset) {
    return obj;
  }
  if (obj is Function) {
    if (toolConfig.args != null) {
      return Function.apply(obj, <Object?>[toolConfig.args]);
    }
    return obj;
  }
  throw ArgumentError('Invalid tool config `${toolConfig.name}`.');
}

BaseAgent _resolveAgentCodeReference(
  String code, {
  required AgentConfigResolvers resolvers,
}) {
  if (!code.contains('.')) {
    throw ArgumentError('Invalid code reference: $code');
  }
  final Object? obj = resolveFullyQualifiedName(code, resolvers: resolvers);
  if (obj is Function) {
    throw ArgumentError('Invalid agent reference to a callable: $code');
  }
  if (obj is! BaseAgent) {
    throw ArgumentError(
      'Invalid agent reference to a non-agent instance: $code',
    );
  }
  return obj;
}

GenerateContentConfig _toGenerateContentConfig(Map<String, Object?> map) {
  final double? temperature = _readDoubleField(
    map,
    'temperature',
    'temperature',
  );
  final double? topP = _readDoubleField(map, 'topP', 'top_p');
  final int? topK = _readIntField(map, 'topK', 'top_k');
  final int? maxOutputTokens = _readIntField(
    map,
    'maxOutputTokens',
    'max_output_tokens',
  );
  final double? frequencyPenalty = _readDoubleField(
    map,
    'frequencyPenalty',
    'frequency_penalty',
  );
  final double? presencePenalty = _readDoubleField(
    map,
    'presencePenalty',
    'presence_penalty',
  );
  final int? seed = _readIntField(map, 'seed', 'seed');
  final int? candidateCount = _readIntField(
    map,
    'candidateCount',
    'candidate_count',
  );
  final bool? responseLogprobs = _readBoolField(
    map,
    'responseLogprobs',
    'response_logprobs',
  );
  final int? logprobs = _readIntField(map, 'logprobs', 'logprobs');
  final List<String> stopSequences = _readStringListField(
    map,
    'stopSequences',
    'stop_sequences',
  );

  final GenerateContentConfig config = GenerateContentConfig(
    systemInstruction:
        map['systemInstruction'] as String? ??
        map['system_instruction'] as String?,
    temperature: temperature,
    topP: topP,
    topK: topK,
    maxOutputTokens: maxOutputTokens,
    stopSequences: stopSequences,
    frequencyPenalty: frequencyPenalty,
    presencePenalty: presencePenalty,
    seed: seed,
    candidateCount: candidateCount,
    responseLogprobs: responseLogprobs,
    logprobs: logprobs,
    responseSchema: map['responseSchema'] ?? map['response_schema'],
    responseJsonSchema:
        map['responseJsonSchema'] ?? map['response_json_schema'],
    responseMimeType:
        map['responseMimeType'] as String? ??
        map['response_mime_type'] as String?,
    thinkingConfig: map['thinkingConfig'] ?? map['thinking_config'],
    cachedContent:
        map['cachedContent'] as String? ?? map['cached_content'] as String?,
  );

  final Object? labels = map['labels'];
  if (labels is Map) {
    config.labels = labels.map(
      (Object? key, Object? value) => MapEntry('$key', '$value'),
    );
  }
  return config;
}

Object? _readField(Map<String, Object?> map, String camelKey, String snakeKey) {
  if (map.containsKey(camelKey)) {
    return map[camelKey];
  }
  if (map.containsKey(snakeKey)) {
    return map[snakeKey];
  }
  return null;
}

double? _readDoubleField(
  Map<String, Object?> map,
  String camelKey,
  String snakeKey,
) {
  final Object? value = _readField(map, camelKey, snakeKey);
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

int? _readIntField(Map<String, Object?> map, String camelKey, String snakeKey) {
  final Object? value = _readField(map, camelKey, snakeKey);
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

bool? _readBoolField(
  Map<String, Object?> map,
  String camelKey,
  String snakeKey,
) {
  final Object? value = _readField(map, camelKey, snakeKey);
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final String normalized = value.trim().toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
  }
  if (value is num) {
    if (value == 0) {
      return false;
    }
    if (value == 1) {
      return true;
    }
  }
  return null;
}

List<String> _readStringListField(
  Map<String, Object?> map,
  String camelKey,
  String snakeKey,
) {
  final Object? value = _readField(map, camelKey, snakeKey);
  if (value is List) {
    return value.map((Object? item) => '$item').toList(growable: false);
  }
  return <String>[];
}

class _BaseAgentConstructorArgs {
  _BaseAgentConstructorArgs({
    required this.subAgents,
    required this.beforeAgentCallbacks,
    required this.afterAgentCallbacks,
  });

  final List<BaseAgent> subAgents;
  final Object? beforeAgentCallbacks;
  final Object? afterAgentCallbacks;
}

_BaseAgentConstructorArgs _createBaseAgentArgs(
  BaseAgentConfig config,
  String configAbsPath,
  AgentConfigResolvers resolvers,
) {
  final List<BaseAgent> subAgents = config.subAgents
      .map(
        (AgentRefConfig subAgentConfig) => resolveAgentReference(
          subAgentConfig,
          configAbsPath,
          resolvers: resolvers,
        ),
      )
      .toList(growable: false);

  final Object? beforeCallbacks = config.beforeAgentCallbacks.isEmpty
      ? null
      : resolveCallbacks(config.beforeAgentCallbacks, resolvers: resolvers);
  final Object? afterCallbacks = config.afterAgentCallbacks.isEmpty
      ? null
      : resolveCallbacks(config.afterAgentCallbacks, resolvers: resolvers);

  return _BaseAgentConstructorArgs(
    subAgents: subAgents,
    beforeAgentCallbacks: beforeCallbacks,
    afterAgentCallbacks: afterCallbacks,
  );
}

Object? _decodeConfigDocument(String content) {
  final String trimmed = content.trim();
  if (trimmed.isEmpty) {
    return <String, Object?>{};
  }

  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    return jsonDecode(trimmed);
  }

  return _SimpleYamlDecoder().decode(trimmed);
}

bool _isAbsolutePath(String path) {
  if (path.startsWith(Platform.pathSeparator)) {
    return true;
  }
  return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}

String _joinPath(String left, String right) {
  if (left.endsWith(Platform.pathSeparator)) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
}

class _SimpleYamlDecoder {
  Object? decode(String source) {
    final List<_YamlLine> lines = _toLines(source);
    if (lines.isEmpty) {
      return <String, Object?>{};
    }
    final int start = _skipIgnorableLines(lines, 0);
    if (start >= lines.length) {
      return <String, Object?>{};
    }
    final _ParseResult result = _parseBlock(lines, start, lines[start].indent);
    return result.value;
  }

  List<_YamlLine> _toLines(String source) {
    final List<_YamlLine> lines = <_YamlLine>[];
    for (String line in const LineSplitter().convert(source)) {
      final String raw = line.trimRight();
      final String text = raw.trimLeft();
      final int indent = raw.length - text.length;
      lines.add(
        _YamlLine(
          indent: indent,
          text: text,
          raw: raw,
          isBlank: text.isEmpty,
          isComment: text.startsWith('#'),
        ),
      );
    }
    return lines;
  }

  int _skipIgnorableLines(List<_YamlLine> lines, int index) {
    int cursor = index;
    while (cursor < lines.length &&
        (lines[cursor].isBlank || lines[cursor].isComment)) {
      cursor += 1;
    }
    return cursor;
  }

  _ParseResult _parseBlock(List<_YamlLine> lines, int index, int indent) {
    final int start = _skipIgnorableLines(lines, index);
    if (start >= lines.length) {
      return _ParseResult(<String, Object?>{}, index);
    }
    final _YamlLine line = lines[start];
    if (line.text.startsWith('- ')) {
      return _parseList(lines, start, indent);
    }
    return _parseMap(lines, start, indent);
  }

  _ParseResult _parseMap(List<_YamlLine> lines, int index, int indent) {
    final Map<String, Object?> map = <String, Object?>{};
    int cursor = index;

    while (cursor < lines.length) {
      cursor = _skipIgnorableLines(lines, cursor);
      if (cursor >= lines.length) {
        break;
      }
      final _YamlLine line = lines[cursor];
      if (line.indent < indent) {
        break;
      }
      if (line.indent != indent) {
        throw FormatException('Invalid YAML indentation near `${line.text}`.');
      }
      if (line.text.startsWith('- ')) {
        break;
      }
      final int split = line.text.indexOf(':');
      if (split <= 0) {
        throw FormatException('Invalid YAML mapping line `${line.text}`.');
      }
      final String key = line.text.substring(0, split).trim();
      final String rawValue = line.text.substring(split + 1).trim();
      cursor += 1;

      final _BlockScalarHeader? blockScalar = _parseBlockScalarHeader(rawValue);
      if (blockScalar != null) {
        final _ParseResult parsed = _parseBlockScalar(
          lines,
          cursor,
          indent,
          blockScalar,
        );
        map[key] = parsed.value;
        cursor = parsed.nextIndex;
        continue;
      }

      if (rawValue.isEmpty) {
        final int nestedStart = _skipIgnorableLines(lines, cursor);
        if (nestedStart < lines.length && lines[nestedStart].indent > indent) {
          final _ParseResult nested = _parseBlock(
            lines,
            nestedStart,
            lines[nestedStart].indent,
          );
          map[key] = nested.value;
          cursor = nested.nextIndex;
        } else {
          map[key] = <String, Object?>{};
        }
      } else {
        map[key] = _parseScalar(rawValue);
      }
    }

    return _ParseResult(map, cursor);
  }

  _ParseResult _parseList(List<_YamlLine> lines, int index, int indent) {
    final List<Object?> values = <Object?>[];
    int cursor = index;

    while (cursor < lines.length) {
      cursor = _skipIgnorableLines(lines, cursor);
      if (cursor >= lines.length) {
        break;
      }
      final _YamlLine line = lines[cursor];
      if (line.indent < indent) {
        break;
      }
      if (line.indent != indent || !line.text.startsWith('- ')) {
        break;
      }
      final String itemText = line.text.substring(2).trim();
      cursor += 1;

      final _BlockScalarHeader? itemBlockScalar = _parseBlockScalarHeader(
        itemText,
      );
      if (itemBlockScalar != null) {
        final _ParseResult parsed = _parseBlockScalar(
          lines,
          cursor,
          indent,
          itemBlockScalar,
        );
        values.add(parsed.value);
        cursor = parsed.nextIndex;
        continue;
      }

      if (itemText.isEmpty) {
        final int nestedStart = _skipIgnorableLines(lines, cursor);
        if (nestedStart < lines.length && lines[nestedStart].indent > indent) {
          final _ParseResult nested = _parseBlock(
            lines,
            nestedStart,
            lines[nestedStart].indent,
          );
          values.add(nested.value);
          cursor = nested.nextIndex;
        } else {
          values.add(null);
        }
        continue;
      }

      final int split = itemText.indexOf(':');
      if (split > 0) {
        final String key = itemText.substring(0, split).trim();
        final String rawValue = itemText.substring(split + 1).trim();
        final Map<String, Object?> itemMap = <String, Object?>{};

        final _BlockScalarHeader? blockScalar = _parseBlockScalarHeader(
          rawValue,
        );
        if (blockScalar != null) {
          final _ParseResult parsed = _parseBlockScalar(
            lines,
            cursor,
            indent,
            blockScalar,
          );
          itemMap[key] = parsed.value;
          cursor = parsed.nextIndex;
        } else if (rawValue.isEmpty) {
          final int nestedStart = _skipIgnorableLines(lines, cursor);
          if (nestedStart < lines.length &&
              lines[nestedStart].indent > indent) {
            final _ParseResult nested = _parseBlock(
              lines,
              nestedStart,
              lines[nestedStart].indent,
            );
            itemMap[key] = nested.value;
            cursor = nested.nextIndex;
          } else {
            itemMap[key] = <String, Object?>{};
          }
        } else {
          itemMap[key] = _parseScalar(rawValue);
        }

        final int restStart = _skipIgnorableLines(lines, cursor);
        if (restStart < lines.length &&
            lines[restStart].indent > indent &&
            !lines[restStart].text.startsWith('- ')) {
          final _ParseResult rest = _parseMap(
            lines,
            restStart,
            lines[restStart].indent,
          );
          final Object? value = rest.value;
          if (value is Map<String, Object?>) {
            itemMap.addAll(value);
            cursor = rest.nextIndex;
          }
        }

        values.add(itemMap);
        continue;
      }

      values.add(_parseScalar(itemText));
    }

    return _ParseResult(values, cursor);
  }

  _BlockScalarHeader? _parseBlockScalarHeader(String text) {
    if (text.isEmpty) {
      return null;
    }
    final bool? folded = switch (text[0]) {
      '|' => false,
      '>' => true,
      _ => null,
    };
    if (folded == null) {
      return null;
    }

    _BlockScalarChomp chomp = _BlockScalarChomp.clip;
    int? indentOffset;
    final String indicators = text.substring(1).trim();
    for (int index = 0; index < indicators.length; index += 1) {
      final String char = indicators[index];
      if (char == '-') {
        chomp = _BlockScalarChomp.strip;
        continue;
      }
      if (char == '+') {
        chomp = _BlockScalarChomp.keep;
        continue;
      }
      final int? parsedIndent = int.tryParse(char);
      if (parsedIndent != null) {
        indentOffset = parsedIndent;
        continue;
      }
      break;
    }

    return _BlockScalarHeader(
      folded: folded,
      chomp: chomp,
      indentOffset: indentOffset,
    );
  }

  _ParseResult _parseBlockScalar(
    List<_YamlLine> lines,
    int index,
    int parentIndent,
    _BlockScalarHeader header,
  ) {
    final List<String> scalarLines = <String>[];
    int cursor = index;
    int? contentIndent = header.indentOffset == null
        ? null
        : parentIndent + header.indentOffset!;

    while (cursor < lines.length) {
      final _YamlLine line = lines[cursor];
      if (!line.isBlank && line.indent <= parentIndent) {
        break;
      }
      if (line.isBlank) {
        scalarLines.add('');
        cursor += 1;
        continue;
      }

      contentIndent ??= line.indent;
      if (line.indent < contentIndent) {
        break;
      }

      if (line.raw.length <= contentIndent) {
        scalarLines.add('');
      } else {
        scalarLines.add(line.raw.substring(contentIndent));
      }
      cursor += 1;
    }

    final String body = header.folded
        ? _foldScalarLines(scalarLines)
        : scalarLines.join('\n');
    final String withTerminalNewline = scalarLines.isEmpty ? '' : '$body\n';
    final String normalized = _applyBlockScalarChomp(
      withTerminalNewline,
      header.chomp,
    );
    return _ParseResult(normalized, cursor);
  }

  String _foldScalarLines(List<String> lines) {
    if (lines.isEmpty) {
      return '';
    }
    final StringBuffer buffer = StringBuffer();
    for (int index = 0; index < lines.length; index += 1) {
      final String line = lines[index];
      buffer.write(line);
      if (index == lines.length - 1) {
        continue;
      }
      final String next = lines[index + 1];
      if (line.isEmpty || next.isEmpty) {
        buffer.write('\n');
      } else {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  String _applyBlockScalarChomp(String value, _BlockScalarChomp chomp) {
    return switch (chomp) {
      _BlockScalarChomp.keep => value,
      _BlockScalarChomp.strip => value.replaceFirst(RegExp(r'\n+$'), ''),
      _BlockScalarChomp.clip =>
        !value.endsWith('\n')
            ? value
            : '${value.replaceFirst(RegExp(r'\n+$'), '')}\n',
    };
  }

  Object? _parseScalar(String text) {
    if (text == 'null' || text == '~') {
      return null;
    }
    if (text == 'true') {
      return true;
    }
    if (text == 'false') {
      return false;
    }
    if (RegExp(r'^-?\d+$').hasMatch(text)) {
      return int.parse(text);
    }
    if (RegExp(r'^-?\d+\.\d+$').hasMatch(text)) {
      return double.parse(text);
    }
    if (text.length >= 2 &&
        ((text.startsWith('"') && text.endsWith('"')) ||
            (text.startsWith("'") && text.endsWith("'")))) {
      return text.substring(1, text.length - 1);
    }
    return text;
  }
}

class _YamlLine {
  _YamlLine({
    required this.indent,
    required this.text,
    required this.raw,
    required this.isBlank,
    required this.isComment,
  });

  final int indent;
  final String text;
  final String raw;
  final bool isBlank;
  final bool isComment;
}

enum _BlockScalarChomp { clip, strip, keep }

class _BlockScalarHeader {
  _BlockScalarHeader({
    required this.folded,
    required this.chomp,
    required this.indentOffset,
  });

  final bool folded;
  final _BlockScalarChomp chomp;
  final int? indentOffset;
}

class _ParseResult {
  _ParseResult(this.value, this.nextIndex);

  final Object? value;
  final int nextIndex;
}
