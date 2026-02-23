import '../models/llm_request.dart';

FunctionDeclaration buildFunctionDeclarationWithJsonSchema({
  required String name,
  String? description,
  Map<String, dynamic>? parametersJsonSchema,
  Map<String, dynamic>? responseJsonSchema,
}) {
  final Map<String, dynamic> parameters = <String, dynamic>{
    ...?parametersJsonSchema,
  };
  if (responseJsonSchema != null) {
    parameters['x-response-json-schema'] = responseJsonSchema;
  }
  return FunctionDeclaration(
    name: name,
    description: description ?? '',
    parameters: parameters,
  );
}

FunctionDeclaration buildFunctionDeclarationFromSpec(
  Map<String, Object?> spec, {
  List<String>? ignoreParams,
}) {
  final String name = (spec['name'] ?? 'function') as String;
  final String description = (spec['description'] ?? '') as String;
  final Object? rawParameters =
      spec['parametersJsonSchema'] ?? spec['parameters'];
  final Map<String, dynamic> parameters = _castSchema(
    rawParameters is Map ? rawParameters : null,
  );
  if (ignoreParams != null && ignoreParams.isNotEmpty) {
    final Map<String, dynamic> properties = _castSchema(
      parameters['properties'] as Map? ?? <String, dynamic>{},
    );
    for (final String key in ignoreParams) {
      properties.remove(key);
    }
    parameters['properties'] = properties;

    final List<String> required = <String>[
      for (final Object? value
          in (parameters['required'] as List? ?? <Object?>[]))
        if (value is String && !ignoreParams.contains(value)) value,
    ];
    if (required.isNotEmpty) {
      parameters['required'] = required;
    } else {
      parameters.remove('required');
    }
  }
  return FunctionDeclaration(
    name: name,
    description: description,
    parameters: parameters,
  );
}

Map<String, dynamic> _castSchema(Map? value) {
  if (value == null) {
    return <String, dynamic>{};
  }
  return value.map((Object? key, Object? item) {
    return MapEntry('$key', item);
  });
}
