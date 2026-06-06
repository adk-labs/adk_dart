/// Tool used by task-mode LLM agents to signal task completion.
library;

import '../../../models/llm_request.dart';
import '../../../tools/base_tool.dart';
import '../../../tools/tool_context.dart';

/// Function name used by task agents to signal completion.
const String finishTaskToolName = 'finish_task';

/// Success result returned by [FinishTaskTool.run].
const String finishTaskSuccessResult = 'Task completed.';

/// Tool that validates final task output and signals completion.
class FinishTaskTool extends BaseTool {
  /// Creates a finish-task tool from an agent-like object.
  ///
  /// The object must expose `name` and may expose `outputSchema`.
  factory FinishTaskTool({required Object taskAgent}) {
    return FinishTaskTool.fromSchema(
      taskAgentName: _readTaskAgentName(taskAgent),
      outputSchema: _readTaskAgentOutputSchema(taskAgent),
    );
  }

  /// Creates a finish-task tool with explicit schema metadata.
  factory FinishTaskTool.fromSchema({
    required String taskAgentName,
    Object? outputSchema,
  }) {
    final Map<String, dynamic> schema = _schemaForOutput(outputSchema);
    return FinishTaskTool._(
      taskAgentName: taskAgentName,
      outputSchema: outputSchema,
      outputSchemaJson: schema,
      wrapperKey: _isObjectSchema(schema) ? null : 'result',
    );
  }

  FinishTaskTool._({
    required this.taskAgentName,
    required this.outputSchema,
    required Map<String, dynamic> outputSchemaJson,
    required String? wrapperKey,
  }) : _outputSchemaJson = outputSchemaJson,
       _wrapperKey = wrapperKey,
       super(
         name: finishTaskToolName,
         description:
             'Signal that this agent has completed its delegated task. '
             'Call this when you have finished your delegated task.'
             '${outputSchema == null ? '' : ' Pass the required output data in the parameters.'}',
       );

  /// Agent name this finish-task tool belongs to.
  final String taskAgentName;

  /// Raw output schema supplied by the task agent.
  final Object? outputSchema;

  final Map<String, dynamic> _outputSchemaJson;
  final String? _wrapperKey;

  /// Instruction appended to model requests when this tool is available.
  String buildInstruction() {
    return '''Do NOT call `finish_task` prematurely. Use your available tools to
fully complete every aspect of the delegated task first. If the
task is unclear, ask the user for clarification before proceeding.
Once the task is fully complete, call `finish_task` by itself with
no accompanying text output.''';
  }

  @override
  FunctionDeclaration getDeclaration() {
    final Map<String, dynamic> rawSchema = _deepCopyMap(_outputSchemaJson);
    final String? wrapperKey = _wrapperKey;
    final Map<String, dynamic> parameters;

    if (wrapperKey == null) {
      parameters = rawSchema;
    } else {
      final Object? defs = rawSchema.remove(r'$defs');
      parameters = <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{wrapperKey: rawSchema},
        'required': <String>[wrapperKey],
      };
      if (defs != null) {
        parameters[r'$defs'] = defs;
      }
    }

    return FunctionDeclaration(
      name: finishTaskToolName,
      description: description,
      parameters: parameters,
    );
  }

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    await super.processLlmRequest(
      toolContext: toolContext,
      llmRequest: llmRequest,
    );
    llmRequest.appendInstructions(<String>[buildInstruction()]);
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final List<String> errors = <String>[];
    final String? wrapperKey = _wrapperKey;
    final Object? rawValue;

    if (wrapperKey == null) {
      rawValue = args;
    } else if (args.containsKey(wrapperKey)) {
      rawValue = args[wrapperKey];
    } else {
      rawValue = null;
      errors.add('$wrapperKey: missing required field');
    }

    if (errors.isEmpty) {
      _validateValue(
        rawValue,
        _outputSchemaJson,
        path: wrapperKey ?? r'$',
        errors: errors,
      );
    }

    if (errors.isNotEmpty) {
      return <String, String>{
        'error':
            'Invoking `$name()` failed due to validation errors:\n'
            '${errors.join('\n')}\n'
            'You could retry calling this tool, but it is IMPORTANT for you '
            'to provide all the mandatory parameters with correct types.',
      };
    }

    return finishTaskSuccessResult;
  }

  @override
  String? detectErrorInResponse(Object? response) {
    if (response is Map && response['error'] != null) {
      return 'TOOL_ERROR';
    }
    return null;
  }
}

Map<String, dynamic> _defaultTaskOutputSchema() {
  return <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'result': <String, dynamic>{
        'type': 'string',
        'description': 'A brief summary of what the agent accomplished.',
      },
    },
    'required': <String>['result'],
    'additionalProperties': false,
  };
}

Map<String, dynamic> _schemaForOutput(Object? schema) {
  if (schema == null) {
    return _defaultTaskOutputSchema();
  }
  if (schema is Map<String, dynamic>) {
    return _deepCopyMap(schema);
  }
  if (schema is Map) {
    return _deepCopyMap(
      schema.map((Object? key, Object? value) => MapEntry('$key', value)),
    );
  }
  if (schema is String && _jsonSchemaTypes.contains(schema.toLowerCase())) {
    return <String, dynamic>{'type': schema.toLowerCase()};
  }
  if (schema is Type) {
    if (schema == String) {
      return <String, dynamic>{'type': 'string'};
    }
    if (schema == int) {
      return <String, dynamic>{'type': 'integer'};
    }
    if (schema == double || schema == num) {
      return <String, dynamic>{'type': 'number'};
    }
    if (schema == bool) {
      return <String, dynamic>{'type': 'boolean'};
    }
    if (schema == List) {
      return <String, dynamic>{'type': 'array'};
    }
    if (schema == Map || schema == Object) {
      return <String, dynamic>{'type': 'object'};
    }
  }

  throw ArgumentError(
    'Unsupported finish_task output schema `${schema.runtimeType}`. '
    'Use a JSON schema map or a core Dart Type.',
  );
}

const Set<String> _jsonSchemaTypes = <String>{
  'object',
  'string',
  'integer',
  'number',
  'boolean',
  'array',
  'null',
};

bool _isObjectSchema(Map<String, dynamic> schema) {
  return _schemaType(schema) == 'object';
}

String? _schemaType(Map<String, dynamic> schema) {
  final Object? rawType = schema['type'];
  if (rawType is String) {
    return rawType.toLowerCase();
  }
  if (rawType is List) {
    for (final Object? item in rawType) {
      if (item is String && item.toLowerCase() != 'null') {
        return item.toLowerCase();
      }
    }
  }
  if (schema.containsKey('properties')) {
    return 'object';
  }
  if (schema.containsKey('items')) {
    return 'array';
  }
  return null;
}

void _validateValue(
  Object? value,
  Map<String, dynamic> schema, {
  required String path,
  required List<String> errors,
}) {
  if (value == null && _schemaAllowsNull(schema)) {
    return;
  }

  final Object? anyOf = schema['anyOf'];
  if (anyOf is List && anyOf.isNotEmpty) {
    _validateAgainstAlternatives(value, anyOf, path: path, errors: errors);
    return;
  }
  final Object? oneOf = schema['oneOf'];
  if (oneOf is List && oneOf.isNotEmpty) {
    _validateAgainstAlternatives(value, oneOf, path: path, errors: errors);
    return;
  }

  final Object? enumValues = schema['enum'];
  if (enumValues is List && !enumValues.contains(value)) {
    errors.add('$path: value must be one of ${enumValues.join(', ')}');
    return;
  }

  final String? type = _schemaType(schema);
  switch (type) {
    case 'object':
      _validateObject(value, schema, path: path, errors: errors);
      return;
    case 'string':
      if (value is! String) {
        errors.add('$path: expected string');
      }
      return;
    case 'integer':
      if (value is! int) {
        errors.add('$path: expected integer');
      }
      return;
    case 'number':
      if (value is! num) {
        errors.add('$path: expected number');
      }
      return;
    case 'boolean':
      if (value is! bool) {
        errors.add('$path: expected boolean');
      }
      return;
    case 'array':
      _validateArray(value, schema, path: path, errors: errors);
      return;
    case 'null':
      if (value != null) {
        errors.add('$path: expected null');
      }
      return;
  }
}

bool _schemaAllowsNull(Map<String, dynamic> schema) {
  if (schema['nullable'] == true) {
    return true;
  }
  final Object? type = schema['type'];
  return type is List &&
      type.any(
        (Object? item) => item is String && item.toLowerCase() == 'null',
      );
}

void _validateAgainstAlternatives(
  Object? value,
  List alternatives, {
  required String path,
  required List<String> errors,
}) {
  for (final Object? alternative in alternatives) {
    if (alternative is! Map) {
      continue;
    }
    final List<String> nestedErrors = <String>[];
    _validateValue(
      value,
      alternative.map((Object? key, Object? item) => MapEntry('$key', item)),
      path: path,
      errors: nestedErrors,
    );
    if (nestedErrors.isEmpty) {
      return;
    }
  }
  errors.add('$path: value did not match any allowed schema');
}

void _validateObject(
  Object? value,
  Map<String, dynamic> schema, {
  required String path,
  required List<String> errors,
}) {
  if (value is! Map) {
    errors.add('$path: expected object');
    return;
  }

  final Map<String, Object?> object = value.map(
    (Object? key, Object? item) => MapEntry('$key', item),
  );
  final Map<String, dynamic> properties = _objectProperties(schema);

  for (final String key in _requiredKeys(schema)) {
    if (!object.containsKey(key)) {
      errors.add('$path.$key: missing required field');
    }
  }

  for (final MapEntry<String, dynamic> entry in properties.entries) {
    if (!object.containsKey(entry.key) || entry.value is! Map) {
      continue;
    }
    _validateValue(
      object[entry.key],
      (entry.value as Map).map(
        (Object? key, Object? item) => MapEntry('$key', item),
      ),
      path: '$path.${entry.key}',
      errors: errors,
    );
  }

  final Object? additionalProperties = schema['additionalProperties'];
  if (additionalProperties == false) {
    for (final String key in object.keys) {
      if (!properties.containsKey(key)) {
        errors.add('$path.$key: unexpected field');
      }
    }
  } else if (additionalProperties is Map) {
    final Map<String, dynamic> additionalSchema = additionalProperties.map(
      (Object? key, Object? item) => MapEntry('$key', item),
    );
    for (final MapEntry<String, Object?> entry in object.entries) {
      if (properties.containsKey(entry.key)) {
        continue;
      }
      _validateValue(
        entry.value,
        additionalSchema,
        path: '$path.${entry.key}',
        errors: errors,
      );
    }
  }
}

void _validateArray(
  Object? value,
  Map<String, dynamic> schema, {
  required String path,
  required List<String> errors,
}) {
  if (value is! List) {
    errors.add('$path: expected array');
    return;
  }
  final Object? items = schema['items'];
  if (items is! Map) {
    return;
  }
  final Map<String, dynamic> itemSchema = items.map(
    (Object? key, Object? item) => MapEntry('$key', item),
  );
  for (int i = 0; i < value.length; i += 1) {
    _validateValue(value[i], itemSchema, path: '$path[$i]', errors: errors);
  }
}

Map<String, dynamic> _objectProperties(Map<String, dynamic> schema) {
  final Object? raw = schema['properties'];
  if (raw is! Map) {
    return <String, dynamic>{};
  }
  return raw.map((Object? key, Object? item) => MapEntry('$key', item));
}

List<String> _requiredKeys(Map<String, dynamic> schema) {
  final Object? raw = schema['required'];
  if (raw is! List) {
    return const <String>[];
  }
  return <String>[
    for (final Object? item in raw)
      if (item is String) item,
  ];
}

Map<String, dynamic> _deepCopyMap(Map<String, dynamic> value) {
  return value.map(
    (String key, dynamic item) => MapEntry(key, _deepCopyJsonValue(item)),
  );
}

dynamic _deepCopyJsonValue(dynamic value) {
  if (value is Map<String, dynamic>) {
    return _deepCopyMap(value);
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) => MapEntry('$key', _deepCopyJsonValue(item)),
    );
  }
  if (value is List) {
    return value.map(_deepCopyJsonValue).toList(growable: false);
  }
  return value;
}

String _readTaskAgentName(Object taskAgent) {
  try {
    final dynamic dynamicAgent = taskAgent;
    final Object? value = dynamicAgent.name;
    if (value is String && value.isNotEmpty) {
      return value;
    }
  } catch (_) {
    // Fall through to the explicit error below.
  }
  throw ArgumentError('taskAgent must expose a non-empty String name.');
}

Object? _readTaskAgentOutputSchema(Object taskAgent) {
  try {
    final dynamic dynamicAgent = taskAgent;
    return dynamicAgent.outputSchema;
  } catch (_) {
    return null;
  }
}
