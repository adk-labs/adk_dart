import 'dart:convert';

import '../../_gemini_schema_util.dart';
import '../common/common.dart';

class OperationSignatureParameter {
  OperationSignatureParameter({required this.name, required this.annotation});

  final String name;
  final Type annotation;
}

class OperationParser {
  OperationParser(Object operation, {bool shouldParse = true})
    : _operation = _parseOperation(operation) {
    if (shouldParse) {
      _processOperationParameters();
      _processRequestBody();
      _processReturnValue();
      _dedupeParamNames();
    }
  }

  factory OperationParser.load(
    Object operation,
    List<ApiParameter> params,
    ApiParameter? returnValue,
  ) {
    final OperationParser parser = OperationParser(
      operation,
      shouldParse: false,
    );
    parser._params
      ..clear()
      ..addAll(params.map((ApiParameter value) => value.copyWith()));
    parser._returnValue = returnValue?.copyWith();
    return parser;
  }

  final Map<String, Object?> _operation;
  final List<ApiParameter> _params = <ApiParameter>[];
  ApiParameter? _returnValue;

  void _processOperationParameters() {
    final List<Object?> parameters = _readList(_operation['parameters']);
    for (final Object? item in parameters) {
      final Map<String, Object?> param = _readMap(item);
      if (param.isEmpty) {
        continue;
      }
      final String originalName = _readString(param['name']) ?? '';
      if (originalName.isEmpty) {
        continue;
      }
      final String description = _readString(param['description']) ?? '';
      final String location = _readString(param['in']) ?? '';
      final Map<String, Object?> schema = _readMap(param['schema']);
      if (_readString(schema['description']) == null &&
          description.isNotEmpty) {
        schema['description'] = description;
      }
      final bool required = _readBool(param['required']);

      _params.add(
        ApiParameter(
          originalName: originalName,
          paramLocation: location,
          paramSchema: schema,
          description: description,
          required: required,
        ),
      );
    }
  }

  void _processRequestBody() {
    final Map<String, Object?> requestBody = _readMap(
      _operation['requestBody'],
    );
    if (requestBody.isEmpty) {
      return;
    }
    final Map<String, Object?> content = _readMap(requestBody['content']);
    if (content.isEmpty) {
      return;
    }

    for (final Object? mediaValue in content.values) {
      final Map<String, Object?> mediaType = _readMap(mediaValue);
      final Map<String, Object?> schema = _readMap(mediaType['schema']);
      final String description = _readString(requestBody['description']) ?? '';
      final String type = (_readString(schema['type']) ?? '').toLowerCase();

      if (type == 'object') {
        final Map<String, Object?> properties = _readMap(schema['properties']);
        final List<Object?> requiredFields = _readList(schema['required']);
        final Set<String> requiredNames = requiredFields
            .map((Object? item) => '$item')
            .toSet();

        for (final MapEntry<String, Object?> entry in properties.entries) {
          final Map<String, Object?> property = _readMap(entry.value);
          _params.add(
            ApiParameter(
              originalName: entry.key,
              paramLocation: 'body',
              paramSchema: property,
              description: _readString(property['description']) ?? description,
              required: requiredNames.contains(entry.key),
            ),
          );
        }
      } else if (type == 'array') {
        _params.add(
          ApiParameter(
            originalName: 'array',
            paramLocation: 'body',
            paramSchema: schema,
            description: description,
          ),
        );
      } else {
        final bool hasComplexStructure =
            schema.containsKey('oneOf') ||
            schema.containsKey('anyOf') ||
            schema.containsKey('allOf');
        final bool missingSchemaType =
            schema.isEmpty || _readString(schema['type']) == null;
        final String paramName = hasComplexStructure || missingSchemaType
            ? 'body'
            : '';
        _params.add(
          ApiParameter(
            originalName: paramName,
            paramLocation: 'body',
            paramSchema: schema,
            description: description,
          ),
        );
      }
      break;
    }
  }

  void _dedupeParamNames() {
    final Map<String, int> seen = <String, int>{};
    for (int i = 0; i < _params.length; i += 1) {
      final ApiParameter current = _params[i];
      final int count = seen[current.pyName] ?? 0;
      if (count == 0) {
        seen[current.pyName] = 1;
        continue;
      }
      seen[current.pyName] = count + 1;
      _params[i] = current.copyWith(pyName: '${current.pyName}_${count - 1}');
    }
  }

  void _processReturnValue() {
    final Map<String, Object?> responses = _readMap(_operation['responses']);
    final List<String> successCodes =
        responses.keys.where((String code) => code.startsWith('2')).toList()
          ..sort();

    Map<String, Object?> returnSchema = <String, Object?>{};
    if (successCodes.isNotEmpty) {
      final Map<String, Object?> response = _readMap(
        responses[successCodes.first],
      );
      final Map<String, Object?> content = _readMap(response['content']);
      for (final Object? mediaType in content.values) {
        final Map<String, Object?> media = _readMap(mediaType);
        final Map<String, Object?> schema = _readMap(media['schema']);
        if (schema.isNotEmpty) {
          returnSchema = schema;
          break;
        }
      }
    }

    _returnValue = ApiParameter(
      originalName: '',
      paramLocation: '',
      paramSchema: returnSchema,
    );
  }

  String getFunctionName() {
    final String? operationId = _readString(_operation['operationId']);
    if (operationId == null || operationId.isEmpty) {
      throw ArgumentError('Operation ID is missing');
    }
    final String snake = toSnakeCase(operationId);
    return snake.length > 60 ? snake.substring(0, 60) : snake;
  }

  String getReturnTypeHint() {
    return _returnValue?.typeHint ?? 'Object?';
  }

  Type getReturnTypeValue() {
    return _returnValue?.typeValue ?? Object;
  }

  List<ApiParameter> getParameters() {
    return _params
        .map((ApiParameter parameter) => parameter.copyWith())
        .toList();
  }

  ApiParameter? getReturnValue() {
    return _returnValue?.copyWith();
  }

  String getAuthSchemeName() {
    final List<Object?> security = _readList(_operation['security']);
    if (security.isEmpty) {
      return '';
    }
    final Map<String, Object?> first = _readMap(security.first);
    if (first.isEmpty) {
      return '';
    }
    return first.keys.first;
  }

  String getPydocString() {
    final List<String> docs = _params
        .map((ApiParameter parameter) => parameter.toPydocString())
        .toList();
    final String description =
        _readString(_operation['summary']) ??
        _readString(_operation['description']) ??
        '';
    final String returnDoc = PydocHelper.generateReturnDoc(
      _readMap(_operation['responses']),
    );

    final StringBuffer buffer = StringBuffer();
    buffer.writeln('"""$description');
    buffer.writeln();
    buffer.writeln('Args:');
    for (final String doc in docs) {
      buffer.writeln('  $doc');
    }
    if (returnDoc.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(returnDoc);
    }
    buffer.write('"""');
    return buffer.toString();
  }

  Map<String, Object?> getJsonSchema() {
    final Map<String, Object?> properties = <String, Object?>{
      for (final ApiParameter parameter in _params)
        parameter.pyName: Map<String, Object?>.from(parameter.paramSchema),
    };
    final List<String> required = _params
        .where((ApiParameter parameter) => parameter.required)
        .map((ApiParameter parameter) => parameter.pyName)
        .toList();

    final String title =
        '${_readString(_operation['operationId']) ?? 'unnamed'}_Arguments';
    return <String, Object?>{
      'type': 'object',
      'title': title,
      'properties': properties,
      'required': required,
    };
  }

  List<OperationSignatureParameter> getSignatureParameters() {
    return _params
        .map(
          (ApiParameter parameter) => OperationSignatureParameter(
            name: parameter.pyName,
            annotation: parameter.typeValue,
          ),
        )
        .toList();
  }

  Map<String, Object?> getAnnotations() {
    final Map<String, Object?> annotations = <String, Object?>{
      for (final ApiParameter parameter in _params)
        parameter.pyName: parameter.typeValue,
    };
    annotations['return'] = getReturnTypeValue();
    return annotations;
  }
}

Map<String, Object?> _parseOperation(Object operation) {
  if (operation is String) {
    final Object? decoded = jsonDecode(operation);
    return _readMap(decoded);
  }
  return _readMap(operation);
}

Map<String, Object?> _readMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

List<Object?> _readList(Object? value) {
  if (value is List<Object?>) {
    return List<Object?>.from(value);
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return <Object?>[];
}

String? _readString(Object? value) {
  if (value == null) {
    return null;
  }
  final String text = '$value';
  return text.isEmpty ? null : text;
}

bool _readBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    return value.toLowerCase() == 'true';
  }
  return false;
}
