/// Helpers for deriving function declarations from tool-like inputs.
library;

import '../models/llm_request.dart';
import '_function_tool_declarations.dart';
import '_gemini_schema_util.dart';
import 'base_tool.dart';

/// The mapping from Python-style type names to JSON schema types.
final Map<String, String> pyTypeToSchemaType = <String, String>{
  'str': 'string',
  'int': 'integer',
  'float': 'number',
  'bool': 'boolean',
  'string': 'string',
  'integer': 'integer',
  'number': 'number',
  'boolean': 'boolean',
  'list': 'array',
  'array': 'array',
  'tuple': 'array',
  'object': 'object',
  'dict': 'object',
  'any': 'TYPE_UNSPECIFIED',
};

const Map<String, String> _pydanticTypeToGeminiSchemaType = <String, String>{
  'str': 'STRING',
  'int': 'INTEGER',
  'float': 'NUMBER',
  'bool': 'BOOLEAN',
  'string': 'STRING',
  'integer': 'INTEGER',
  'number': 'NUMBER',
  'boolean': 'BOOLEAN',
  'list': 'ARRAY',
  'array': 'ARRAY',
  'tuple': 'ARRAY',
  'object': 'OBJECT',
  'dict': 'OBJECT',
  'Dict': 'OBJECT',
  'List': 'ARRAY',
  'Tuple': 'ARRAY',
  'any': 'TYPE_UNSPECIFIED',
  'Any': 'TYPE_UNSPECIFIED',
};

/// Marks properties whose `anyOf` contains a `'null'` branch as `nullable`.
void annotateNullableFields(Map<String, dynamic> schema) {
  final Object? rawProperties = schema['properties'];
  if (rawProperties is! Map) {
    return;
  }
  for (final Object? rawProperty in rawProperties.values) {
    if (rawProperty is! Map) {
      continue;
    }
    final Object? rawAnyOf = rawProperty['anyOf'];
    if (rawAnyOf is! List) {
      continue;
    }
    for (int i = 0; i < rawAnyOf.length; i += 1) {
      final Object? candidate = rawAnyOf[i];
      if (candidate is Map && candidate['type'] == 'null') {
        rawProperty['nullable'] = true;
        rawAnyOf.removeAt(i);
        break;
      }
    }
  }
}

/// Populates `schema['required']` with non-nullable fields without defaults.
void annotateRequiredFields(Map<String, dynamic> schema) {
  final Object? rawProperties = schema['properties'];
  if (rawProperties is! Map) {
    schema['required'] = <String>[];
    return;
  }
  final List<String> required = <String>[];
  rawProperties.forEach((Object? key, Object? rawFieldSchema) {
    if (rawFieldSchema is Map) {
      final bool isNullable = rawFieldSchema['nullable'] == true;
      final bool hasDefault = rawFieldSchema.containsKey('default');
      if (!isNullable && !hasDefault) {
        required.add('$key');
      }
    }
  });
  schema['required'] = required;
}

/// Collapses `anyOf` unions in `schema['properties']` to their first non-null member.
void removeAnyOf(Map<String, dynamic> schema) {
  final Object? rawProperties = schema['properties'];
  if (rawProperties is! Map) {
    return;
  }
  for (final Object? rawProperty in rawProperties.values) {
    if (rawProperty is! Map) {
      continue;
    }
    final Object? unionTypes = rawProperty.remove('anyOf');
    if (unionTypes is List && unionTypes.isNotEmpty) {
      for (final Object? candidate in unionTypes) {
        if (candidate is Map && candidate['type'] != 'null') {
          candidate.forEach((Object? k, Object? v) {
            rawProperty['$k'] = v;
          });
          break;
        }
      }
    }
  }
}

/// Removes `default` keys from top-level property schemas in [schema].
void removeDefault(Map<String, dynamic> schema) {
  final Object? rawProperties = schema['properties'];
  if (rawProperties is! Map) {
    return;
  }
  for (final Object? rawProperty in rawProperties.values) {
    if (rawProperty is Map) {
      rawProperty.remove('default');
    }
  }
}

/// Removes `nullable` keys from top-level property schemas in [schema].
void removeNullable(Map<String, dynamic> schema) {
  final Object? rawProperties = schema['properties'];
  if (rawProperties is! Map) {
    return;
  }
  for (final Object? rawProperty in rawProperties.values) {
    if (rawProperty is Map) {
      rawProperty.remove('nullable');
    }
  }
}

/// Removes `title` keys from top-level property schemas in [schema].
void removeTitle(Map<String, dynamic> schema) {
  final Object? rawProperties = schema['properties'];
  if (rawProperties is! Map) {
    return;
  }
  for (final Object? rawProperty in rawProperties.values) {
    if (rawProperty is Map) {
      rawProperty.remove('title');
    }
  }
}

/// Normalizes a Pydantic-style JSON [schema] for Gemini API or Vertex AI (`[vertexai]`).
Map<String, dynamic> processPydanticSchema(
  bool vertexai,
  Map<String, dynamic> schema,
) {
  final Map<String, dynamic> cloned = _deepCloneSchemaMap(schema);
  annotateNullableFields(cloned);
  annotateRequiredFields(cloned);
  if (!vertexai) {
    removeAnyOf(cloned);
    removeDefault(cloned);
    removeNullable(cloned);
    removeTitle(cloned);
  }
  return cloned;
}

/// Maps JSON/Pydantic types in a single [propertySchema] to Gemini `Schema` uppercase types.
void mapPydanticTypeToPropertySchema(Map<String, dynamic> propertySchema) {
  if (propertySchema.containsKey('type')) {
    final String rawType = '${propertySchema['type']}';
    final String mapped =
        _pydanticTypeToGeminiSchemaType[rawType] ?? 'TYPE_UNSPECIFIED';
    propertySchema['type'] = mapped;
    if (mapped == 'ARRAY' && propertySchema['items'] is Map) {
      final Map<String, dynamic> items = _deepCloneSchemaMap(
        propertySchema['items'] as Map,
      );
      mapPydanticTypeToPropertySchema(items);
      propertySchema['items'] = items;
    }
  }
  final Object? rawAnyOf = propertySchema['anyOf'];
  if (rawAnyOf is List) {
    for (int i = 0; i < rawAnyOf.length; i += 1) {
      final Object? entry = rawAnyOf[i];
      if (entry is Map && entry.containsKey('type')) {
        final Map<String, dynamic> entryCopy = _deepCloneSchemaMap(entry);
        final String mapped =
            _pydanticTypeToGeminiSchemaType['${entryCopy['type']}'] ??
            'TYPE_UNSPECIFIED';
        entryCopy['type'] = mapped;
        rawAnyOf[i] = entryCopy;
        propertySchema['type'] = mapped;
      }
    }
  }
}

/// Maps JSON/Pydantic types across all properties of [schema] to Gemini `Schema` uppercase types.
void mapPydanticTypeToSchemaType(Map<String, dynamic> schema) {
  final Object? rawProperties = schema['properties'];
  if (rawProperties is! Map) {
    return;
  }
  final Map<String, dynamic> normalizedProperties = <String, dynamic>{};
  rawProperties.forEach((Object? key, Object? value) {
    if (value is Map) {
      final Map<String, dynamic> propCopy = _deepCloneSchemaMap(value);
      mapPydanticTypeToPropertySchema(propCopy);
      normalizedProperties['$key'] = propCopy;
    } else {
      normalizedProperties['$key'] = value;
    }
  });
  schema['properties'] = normalizedProperties;
}

/// Builds a [FunctionDeclaration] for a LangChain tool from its `properties` map.
FunctionDeclaration buildFunctionDeclarationForLangchain(
  bool vertexai,
  String name,
  String? description,
  Object? func,
  Map<String, dynamic> paramPydanticSchema,
) {
  final Map<String, dynamic> processedSchema = processPydanticSchema(
    vertexai,
    <String, dynamic>{'properties': paramPydanticSchema},
  );
  return buildFunctionDeclarationUtil(
    vertexai,
    name,
    description,
    func,
    processedSchema,
  );
}

/// Builds a [FunctionDeclaration] for a CrewAI tool from its full Pydantic JSON schema.
FunctionDeclaration buildFunctionDeclarationForParamsForCrewai(
  bool vertexai,
  String name,
  String? description,
  Object? func,
  Map<String, dynamic> paramPydanticSchema,
) {
  final Map<String, dynamic> processedSchema = processPydanticSchema(
    vertexai,
    paramPydanticSchema,
  );
  return buildFunctionDeclarationUtil(
    vertexai,
    name,
    description,
    func,
    Map<String, dynamic>.from(processedSchema),
  );
}

/// Shared declaration builder for LangChain and CrewAI Pydantic tool schemas.
FunctionDeclaration buildFunctionDeclarationUtil(
  bool vertexai,
  String name,
  String? description,
  Object? func,
  Map<String, dynamic> beforeParamPydanticSchema,
) {
  final Map<String, dynamic> working = _deepCloneSchemaMap(
    beforeParamPydanticSchema,
  );
  mapPydanticTypeToSchemaType(working);
  final Map<String, dynamic> properties = working['properties'] is Map
      ? _deepCloneSchemaMap(working['properties'] as Map)
      : <String, dynamic>{};
  final List<String> required = working['required'] is List
      ? (working['required'] as List)
            .map((Object? item) => '$item')
            .toList(growable: false)
      : <String>[];

  final Map<String, dynamic> parameters = properties.isNotEmpty
      ? <String, dynamic>{
          'type': 'OBJECT',
          'properties': properties,
          'required': required,
        }
      : <String, dynamic>{};

  if (vertexai && func is Function) {
    final String returnSchemaType = _inferDartFunctionReturnSchemaType(func);
    parameters['x-response-json-schema'] = <String, dynamic>{
      'type': returnSchemaType,
    };
  }

  return FunctionDeclaration(
    name: name,
    description: description ?? '',
    parameters: parameters,
  );
}

String _inferDartFunctionReturnSchemaType(Function func) {
  final String runtime = '${func.runtimeType}';
  final int arrowIndex = runtime.lastIndexOf(' => ');
  if (arrowIndex < 0) {
    return 'TYPE_UNSPECIFIED';
  }
  String returnType = runtime.substring(arrowIndex + 4).trim();
  if (returnType.endsWith('?')) {
    returnType = returnType.substring(0, returnType.length - 1);
  }
  final RegExpMatch? futureMatch = RegExp(
    r'^(?:Future|FutureOr)<(.+)>$',
  ).firstMatch(returnType);
  if (futureMatch != null) {
    returnType = futureMatch.group(1)!.trim();
    if (returnType.endsWith('?')) {
      returnType = returnType.substring(0, returnType.length - 1);
    }
  }
  if (returnType == 'String') {
    return 'STRING';
  }
  if (returnType == 'int') {
    return 'INTEGER';
  }
  if (returnType == 'double' || returnType == 'num') {
    return 'NUMBER';
  }
  if (returnType == 'bool') {
    return 'BOOLEAN';
  }
  if (returnType.startsWith('List<') || returnType == 'List') {
    return 'ARRAY';
  }
  if (returnType.startsWith('Map<') || returnType == 'Map') {
    return 'OBJECT';
  }
  return 'TYPE_UNSPECIFIED';
}

Map<String, dynamic> _deepCloneSchemaMap(Map<Object?, Object?> input) {
  return input.map(
    (Object? key, Object? value) => MapEntry('$key', _deepCloneSchemaValue(value)),
  );
}

Object? _deepCloneSchemaValue(Object? value) {
  if (value is Map) {
    return _deepCloneSchemaMap(value);
  }
  if (value is List) {
    return value.map(_deepCloneSchemaValue).toList();
  }
  return value;
}

/// The [FunctionDeclaration] converted from [func] and optional schema hints.
FunctionDeclaration buildFunctionDeclaration(
  Object func, {
  List<String>? ignoreParams,
  Map<String, dynamic>? parametersJsonSchema,
  Map<String, dynamic>? responseJsonSchema,
}) {
  if (func is BaseTool) {
    final FunctionDeclaration? declaration = func.getDeclaration();
    if (declaration != null) {
      return _withoutIgnoredParams(declaration, ignoreParams);
    }
    return buildFunctionDeclarationWithJsonSchema(
      name: func.name,
      description: func.description,
      parametersJsonSchema:
          parametersJsonSchema ??
          <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
          },
      responseJsonSchema: responseJsonSchema,
    );
  }

  if (func is FunctionDeclaration) {
    return _withoutIgnoredParams(func.copyWith(), ignoreParams);
  }

  if (func is Map<String, Object?>) {
    return buildFunctionDeclarationFromSpec(func, ignoreParams: ignoreParams);
  }

  if (func is String) {
    return buildFunctionDeclarationWithJsonSchema(
      name: func,
      parametersJsonSchema:
          parametersJsonSchema ??
          <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
          },
      responseJsonSchema: responseJsonSchema,
    );
  }

  return buildFunctionDeclarationWithJsonSchema(
    name: 'function',
    parametersJsonSchema:
        parametersJsonSchema ??
        <String, dynamic>{'type': 'object', 'properties': <String, dynamic>{}},
    responseJsonSchema: responseJsonSchema,
  );
}

/// Compatibility alias for [buildFunctionDeclaration].
FunctionDeclaration fromFunctionWithOptions(
  Object func, {
  List<String>? ignoreParams,
  Map<String, dynamic>? parametersJsonSchema,
  Map<String, dynamic>? responseJsonSchema,
}) {
  return buildFunctionDeclaration(
    func,
    ignoreParams: ignoreParams,
    parametersJsonSchema: parametersJsonSchema,
    responseJsonSchema: responseJsonSchema,
  );
}

FunctionDeclaration _withoutIgnoredParams(
  FunctionDeclaration declaration,
  List<String>? ignoreParams,
) {
  final Map<String, dynamic> parameters = dereferenceSchema(<String, dynamic>{
    ...declaration.parameters,
  });
  if (ignoreParams == null || ignoreParams.isEmpty) {
    return declaration.copyWith(parameters: parameters);
  }
  final Map<String, dynamic> properties = (parameters['properties'] is Map)
      ? (parameters['properties'] as Map).map(
          (Object? key, Object? value) => MapEntry('$key', value),
        )
      : <String, dynamic>{};
  for (final String name in ignoreParams) {
    properties.remove(name);
  }
  parameters['properties'] = properties;

  if (parameters['required'] is List) {
    parameters['required'] = (parameters['required'] as List)
        .whereType<String>()
        .where((String name) => !ignoreParams.contains(name))
        .toList(growable: false);
  }
  return declaration.copyWith(parameters: parameters);
}
