import '../tools/tool_configs.dart';
import 'base_agent_config.dart';
import 'common_configs.dart';

class LlmAgentConfig extends BaseAgentConfig {
  LlmAgentConfig({
    super.agentClass = 'LlmAgent',
    required super.name,
    super.description,
    super.subAgents,
    super.beforeAgentCallbacks,
    super.afterAgentCallbacks,
    super.extras,
    this.model,
    this.modelCode,
    required this.instruction,
    this.staticInstruction,
    this.disallowTransferToParent,
    this.disallowTransferToPeers,
    this.inputSchema,
    this.outputSchema,
    this.outputKey,
    this.includeContents = 'default',
    List<ToolConfig>? tools,
    List<CodeConfig>? beforeModelCallbacks,
    List<CodeConfig>? afterModelCallbacks,
    List<CodeConfig>? beforeToolCallbacks,
    List<CodeConfig>? afterToolCallbacks,
    this.generateContentConfig,
  }) : tools = tools ?? <ToolConfig>[],
       beforeModelCallbacks = beforeModelCallbacks ?? <CodeConfig>[],
       afterModelCallbacks = afterModelCallbacks ?? <CodeConfig>[],
       beforeToolCallbacks = beforeToolCallbacks ?? <CodeConfig>[],
       afterToolCallbacks = afterToolCallbacks ?? <CodeConfig>[] {
    if (model != null && modelCode != null) {
      throw ArgumentError('Only one of `model` or `model_code` should be set.');
    }
    if (includeContents != 'default' && includeContents != 'none') {
      throw ArgumentError(
        'include_contents must be either `default` or `none`.',
      );
    }
  }

  final String? model;
  final CodeConfig? modelCode;
  final String instruction;
  final Object? staticInstruction;
  final bool? disallowTransferToParent;
  final bool? disallowTransferToPeers;
  final CodeConfig? inputSchema;
  final CodeConfig? outputSchema;
  final String? outputKey;
  final String includeContents;
  final List<ToolConfig> tools;
  final List<CodeConfig> beforeModelCallbacks;
  final List<CodeConfig> afterModelCallbacks;
  final List<CodeConfig> beforeToolCallbacks;
  final List<CodeConfig> afterToolCallbacks;
  final Map<String, Object?>? generateContentConfig;

  static const Set<String> _knownLlmKeys = <String>{
    'model',
    'model_code',
    'modelCode',
    'instruction',
    'static_instruction',
    'staticInstruction',
    'disallow_transfer_to_parent',
    'disallowTransferToParent',
    'disallow_transfer_to_peers',
    'disallowTransferToPeers',
    'input_schema',
    'inputSchema',
    'output_schema',
    'outputSchema',
    'output_key',
    'outputKey',
    'include_contents',
    'includeContents',
    'tools',
    'before_model_callbacks',
    'beforeModelCallbacks',
    'after_model_callbacks',
    'afterModelCallbacks',
    'before_tool_callbacks',
    'beforeToolCallbacks',
    'after_tool_callbacks',
    'afterToolCallbacks',
    'generate_content_config',
    'generateContentConfig',
  };

  factory LlmAgentConfig.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> normalized = Map<String, Object?>.from(json);
    final Object? modelValue = normalized['model'];
    if (modelValue is Map && normalized['model_code'] == null) {
      normalized['model_code'] = modelValue;
      normalized['model'] = null;
    }

    final BaseAgentConfig base = BaseAgentConfig.fromJson(normalized);
    final Map<String, Object?> extras = Map<String, Object?>.from(base.extras)
      ..removeWhere((String key, Object? _) => _knownLlmKeys.contains(key));
    if (extras.isNotEmpty) {
      throw ArgumentError(
        'Unexpected fields for LlmAgentConfig: ${extras.keys.join(', ')}',
      );
    }

    final String? instruction = (normalized['instruction'] as String?)?.trim();
    if (instruction == null || instruction.isEmpty) {
      throw ArgumentError('LlmAgentConfig requires non-empty `instruction`.');
    }

    final Object? generateContentRaw =
        normalized['generate_content_config'] ??
        normalized['generateContentConfig'];

    return LlmAgentConfig(
      agentClass:
          (normalized['agent_class'] as String?) ??
          (normalized['agentClass'] as String?) ??
          'LlmAgent',
      name: base.name,
      description: base.description,
      subAgents: base.subAgents,
      beforeAgentCallbacks: base.beforeAgentCallbacks,
      afterAgentCallbacks: base.afterAgentCallbacks,
      model: normalized['model'] as String?,
      modelCode: _toCodeConfig(
        normalized['model_code'] ?? normalized['modelCode'],
      ),
      instruction: instruction,
      staticInstruction:
          normalized['static_instruction'] ?? normalized['staticInstruction'],
      disallowTransferToParent:
          normalized['disallow_transfer_to_parent'] as bool? ??
          normalized['disallowTransferToParent'] as bool?,
      disallowTransferToPeers:
          normalized['disallow_transfer_to_peers'] as bool? ??
          normalized['disallowTransferToPeers'] as bool?,
      inputSchema: _toCodeConfig(
        normalized['input_schema'] ?? normalized['inputSchema'],
      ),
      outputSchema: _toCodeConfig(
        normalized['output_schema'] ?? normalized['outputSchema'],
      ),
      outputKey:
          normalized['output_key'] as String? ??
          normalized['outputKey'] as String?,
      includeContents:
          (normalized['include_contents'] as String?) ??
          (normalized['includeContents'] as String?) ??
          'default',
      tools: _decodeTools(normalized['tools']),
      beforeModelCallbacks: _decodeCodeConfigs(
        normalized['before_model_callbacks'] ??
            normalized['beforeModelCallbacks'],
      ),
      afterModelCallbacks: _decodeCodeConfigs(
        normalized['after_model_callbacks'] ??
            normalized['afterModelCallbacks'],
      ),
      beforeToolCallbacks: _decodeCodeConfigs(
        normalized['before_tool_callbacks'] ??
            normalized['beforeToolCallbacks'],
      ),
      afterToolCallbacks: _decodeCodeConfigs(
        normalized['after_tool_callbacks'] ?? normalized['afterToolCallbacks'],
      ),
      generateContentConfig: generateContentRaw is Map
          ? generateContentRaw.map(
              (Object? key, Object? value) => MapEntry('$key', value),
            )
          : null,
    );
  }

  static CodeConfig? _toCodeConfig(Object? value) {
    if (value is! Map) {
      return null;
    }
    return CodeConfig.fromJson(
      value.map((Object? key, Object? value) => MapEntry('$key', value)),
    );
  }

  static List<CodeConfig> _decodeCodeConfigs(Object? value) {
    if (value is! List) {
      return <CodeConfig>[];
    }
    return value
        .map((Object? item) {
          if (item is! Map) {
            throw ArgumentError('CodeConfig entry must be a map.');
          }
          return CodeConfig.fromJson(
            item.map((Object? key, Object? value) => MapEntry('$key', value)),
          );
        })
        .toList(growable: false);
  }

  static List<ToolConfig> _decodeTools(Object? value) {
    if (value is! List) {
      return <ToolConfig>[];
    }
    return value
        .map((Object? item) {
          if (item is! Map) {
            throw ArgumentError('Tool config entry must be a map.');
          }
          return ToolConfig.fromJson(
            item.map((Object? key, Object? value) => MapEntry('$key', value)),
          );
        })
        .toList(growable: false);
  }

  @override
  Map<String, Object?> toJson() {
    final Map<String, Object?> json = super.toJson();
    json
      ..['agent_class'] = 'LlmAgent'
      ..['instruction'] = instruction;
    if (model != null) {
      json['model'] = model;
    }
    if (modelCode != null) {
      json['model_code'] = modelCode!.toJson();
    }
    if (staticInstruction != null) {
      json['static_instruction'] = staticInstruction;
    }
    if (disallowTransferToParent != null) {
      json['disallow_transfer_to_parent'] = disallowTransferToParent;
    }
    if (disallowTransferToPeers != null) {
      json['disallow_transfer_to_peers'] = disallowTransferToPeers;
    }
    if (inputSchema != null) {
      json['input_schema'] = inputSchema!.toJson();
    }
    if (outputSchema != null) {
      json['output_schema'] = outputSchema!.toJson();
    }
    if (outputKey != null) {
      json['output_key'] = outputKey;
    }
    if (includeContents != 'default') {
      json['include_contents'] = includeContents;
    }
    if (tools.isNotEmpty) {
      json['tools'] = tools.map((ToolConfig e) => e.toJson()).toList();
    }
    if (beforeModelCallbacks.isNotEmpty) {
      json['before_model_callbacks'] = beforeModelCallbacks
          .map((CodeConfig e) => e.toJson())
          .toList();
    }
    if (afterModelCallbacks.isNotEmpty) {
      json['after_model_callbacks'] = afterModelCallbacks
          .map((CodeConfig e) => e.toJson())
          .toList();
    }
    if (beforeToolCallbacks.isNotEmpty) {
      json['before_tool_callbacks'] = beforeToolCallbacks
          .map((CodeConfig e) => e.toJson())
          .toList();
    }
    if (afterToolCallbacks.isNotEmpty) {
      json['after_tool_callbacks'] = afterToolCallbacks
          .map((CodeConfig e) => e.toJson())
          .toList();
    }
    if (generateContentConfig != null) {
      json['generate_content_config'] = Map<String, Object?>.from(
        generateContentConfig!,
      );
    }
    return json;
  }
}
