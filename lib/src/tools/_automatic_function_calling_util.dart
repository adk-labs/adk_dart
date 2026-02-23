import '../models/llm_request.dart';
import 'base_tool.dart';
import '_function_tool_declarations.dart';

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
  if (ignoreParams == null || ignoreParams.isEmpty) {
    return declaration;
  }
  final Map<String, dynamic> parameters = <String, dynamic>{
    ...declaration.parameters,
  };
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
