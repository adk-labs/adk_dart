import 'dart:convert';
import 'dart:io';

import '../agents/readonly_context.dart';
import '../models/llm_request.dart';
import 'base_tool.dart';
import 'base_toolset.dart';
import 'tool_context.dart';

typedef AuthTokenGetter = String Function();
typedef BoundParamProvider = Object? Function();
typedef ToolboxToolsetDelegateFactory =
    ToolboxToolsetDelegate Function({
      required String serverUrl,
      String? toolsetName,
      List<String>? toolNames,
      Map<String, AuthTokenGetter>? authTokenGetters,
      Map<String, Object?>? boundParams,
      Object? credentials,
      Map<String, String>? additionalHeaders,
      Map<String, Object?>? additionalOptions,
    });

/// Delegate contract for toolbox SDK integrations.
abstract class ToolboxToolsetDelegate {
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext});

  Future<void> close();
}

class ToolboxToolset extends BaseToolset {
  static ToolboxToolsetDelegateFactory? _defaultDelegateFactory;

  /// Registers a default toolbox delegate factory used when [delegate] is not
  /// provided. Integrations can call this during startup.
  static void registerDefaultDelegateFactory(
    ToolboxToolsetDelegateFactory factory,
  ) {
    _defaultDelegateFactory = factory;
  }

  /// Clears the registered default toolbox delegate factory.
  static void clearDefaultDelegateFactory() {
    _defaultDelegateFactory = null;
  }

  ToolboxToolset({
    required this.serverUrl,
    this.toolsetName,
    this.toolNames,
    this.authTokenGetters,
    this.boundParams,
    this.credentials,
    this.additionalHeaders,
    this.additionalOptions,
    ToolboxToolsetDelegate? delegate,
  }) : _delegate =
           delegate ??
           _createDefaultDelegateOrThrow(
             serverUrl: serverUrl,
             toolsetName: toolsetName,
             toolNames: toolNames,
             authTokenGetters: authTokenGetters,
             boundParams: boundParams,
             credentials: credentials,
             additionalHeaders: additionalHeaders,
             additionalOptions: additionalOptions,
           );

  final String serverUrl;
  final String? toolsetName;
  final List<String>? toolNames;
  final Map<String, AuthTokenGetter>? authTokenGetters;
  final Map<String, Object?>? boundParams;
  final Object? credentials;
  final Map<String, String>? additionalHeaders;
  final Map<String, Object?>? additionalOptions;

  final ToolboxToolsetDelegate _delegate;

  static ToolboxToolsetDelegate _createDefaultDelegateOrThrow({
    required String serverUrl,
    String? toolsetName,
    List<String>? toolNames,
    Map<String, AuthTokenGetter>? authTokenGetters,
    Map<String, Object?>? boundParams,
    Object? credentials,
    Map<String, String>? additionalHeaders,
    Map<String, Object?>? additionalOptions,
  }) {
    final ToolboxToolsetDelegateFactory? factory = _defaultDelegateFactory;
    if (factory != null) {
      return factory(
        serverUrl: serverUrl,
        toolsetName: toolsetName,
        toolNames: toolNames == null ? null : List<String>.from(toolNames),
        authTokenGetters: authTokenGetters == null
            ? null
            : Map<String, AuthTokenGetter>.from(authTokenGetters),
        boundParams: boundParams == null
            ? null
            : Map<String, Object?>.from(boundParams),
        credentials: credentials,
        additionalHeaders: additionalHeaders == null
            ? null
            : Map<String, String>.from(additionalHeaders),
        additionalOptions: additionalOptions == null
            ? null
            : Map<String, Object?>.from(additionalOptions),
      );
    }

    return _HttpToolboxToolsetDelegate(
      serverUrl: serverUrl,
      toolsetName: toolsetName,
      toolNames: toolNames == null ? null : List<String>.from(toolNames),
      authTokenGetters: authTokenGetters == null
          ? null
          : Map<String, AuthTokenGetter>.from(authTokenGetters),
      boundParams: boundParams == null
          ? null
          : Map<String, Object?>.from(boundParams),
      credentials: credentials,
      additionalHeaders: additionalHeaders == null
          ? null
          : Map<String, String>.from(additionalHeaders),
      additionalOptions: additionalOptions == null
          ? null
          : Map<String, Object?>.from(additionalOptions),
    );
  }

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    return _delegate.getTools(readonlyContext: readonlyContext);
  }

  @override
  Future<void> close() async {
    await _delegate.close();
  }
}

class _HttpToolboxToolsetDelegate implements ToolboxToolsetDelegate {
  _HttpToolboxToolsetDelegate({
    required this.serverUrl,
    this.toolsetName,
    this.toolNames,
    this.authTokenGetters,
    this.boundParams,
    this.credentials,
    this.additionalHeaders,
    this.additionalOptions,
  });

  final String serverUrl;
  final String? toolsetName;
  final List<String>? toolNames;
  final Map<String, AuthTokenGetter>? authTokenGetters;
  final Map<String, Object?>? boundParams;
  final Object? credentials;
  final Map<String, String>? additionalHeaders;
  final Map<String, Object?>? additionalOptions;

  List<BaseTool>? _cachedTools;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    final List<BaseTool>? existing = _cachedTools;
    if (existing != null) {
      return existing;
    }

    final Uri endpoint = Uri.parse(
      '$serverUrl/api/toolset/${toolsetName ?? ''}',
    );
    final Map<String, Object?> manifest = await _requestJson(
      method: 'GET',
      uri: endpoint,
      headers: additionalHeaders,
      timeoutSeconds: _timeoutSeconds(),
    );

    final Map<String, Object?> toolsMap = _toMap(manifest['tools']);
    final Set<String>? selected = toolNames == null
        ? null
        : Set<String>.from(toolNames!);

    final List<BaseTool> tools = <BaseTool>[];
    for (final MapEntry<String, Object?> entry in toolsMap.entries) {
      if (selected != null && !selected.contains(entry.key)) {
        continue;
      }
      final Map<String, Object?> schema = _toMap(entry.value);
      final String description = '${schema['description'] ?? ''}';
      final List<Object?> parameterSchemas = _toList(schema['parameters']);
      final List<String> authRequired = _toList(
        schema['authRequired'],
      ).map((Object? value) => '$value').toList(growable: false);

      tools.add(
        _ToolboxHttpTool(
          serverUrl: serverUrl,
          toolName: entry.key,
          description: description,
          parameterSchemas: parameterSchemas,
          authRequired: authRequired,
          authTokenGetters: authTokenGetters,
          boundParams: boundParams,
          additionalHeaders: additionalHeaders,
          timeoutSeconds: _timeoutSeconds(),
        ),
      );
    }

    _cachedTools = tools;
    return tools;
  }

  int _timeoutSeconds() {
    final Object? raw = additionalOptions?['timeout'];
    if (raw is int && raw > 0) {
      return raw;
    }
    if (raw is String) {
      final int? parsed = int.tryParse(raw);
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return 30;
  }

  @override
  Future<void> close() async {}
}

class _ToolboxHttpTool extends BaseTool {
  _ToolboxHttpTool({
    required this.serverUrl,
    required String toolName,
    required super.description,
    required this.parameterSchemas,
    required this.authRequired,
    required this.authTokenGetters,
    required this.boundParams,
    required this.additionalHeaders,
    required this.timeoutSeconds,
  }) : super(name: toolName);

  final String serverUrl;
  final List<Object?> parameterSchemas;
  final List<String> authRequired;
  final Map<String, AuthTokenGetter>? authTokenGetters;
  final Map<String, Object?>? boundParams;
  final Map<String, String>? additionalHeaders;
  final int timeoutSeconds;

  @override
  FunctionDeclaration? getDeclaration() {
    final Map<String, Object?> properties = <String, Object?>{};
    final List<String> requiredFields = <String>[];

    for (final Object? item in parameterSchemas) {
      final Map<String, Object?> parameter = _toMap(item);
      final String paramName = '${parameter['name'] ?? ''}'.trim();
      if (paramName.isEmpty) {
        continue;
      }
      properties[paramName] = _toolboxParamToJsonSchema(parameter);
      if (parameter['required'] == true) {
        requiredFields.add(paramName);
      }
    }

    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, Object?>{
        'type': 'object',
        'properties': properties,
        if (requiredFields.isNotEmpty) 'required': requiredFields,
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Map<String, Object?> payload = <String, Object?>{
      for (final MapEntry<String, dynamic> entry in args.entries)
        entry.key: entry.value,
    };

    if (boundParams != null) {
      for (final MapEntry<String, Object?> entry in boundParams!.entries) {
        final Object? value = entry.value;
        payload[entry.key] = value is BoundParamProvider ? value() : value;
      }
    }

    final Map<String, String> headers = <String, String>{
      if (additionalHeaders != null) ...additionalHeaders!,
    };

    if (authTokenGetters != null) {
      for (final MapEntry<String, AuthTokenGetter> entry
          in authTokenGetters!.entries) {
        headers['${entry.key}_token'] = entry.value();
      }
    }

    final Uri endpoint = Uri.parse('$serverUrl/api/tool/$name/invoke');
    final Map<String, Object?> body = await _requestJson(
      method: 'POST',
      uri: endpoint,
      headers: <String, String>{
        ...headers,
        HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
      },
      bodyBytes: utf8.encode(jsonEncode(payload)),
      timeoutSeconds: timeoutSeconds,
    );
    if (body.containsKey('error')) {
      throw StateError('${body['error']}');
    }
    return body.containsKey('result') ? body['result'] : body;
  }
}

Future<Map<String, Object?>> _requestJson({
  required String method,
  required Uri uri,
  Map<String, String>? headers,
  List<int>? bodyBytes,
  int timeoutSeconds = 30,
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client
        .openUrl(method, uri)
        .timeout(Duration(seconds: timeoutSeconds));
    (headers ?? const <String, String>{}).forEach(request.headers.set);
    if (bodyBytes != null && bodyBytes.isNotEmpty) {
      request.add(bodyBytes);
    }

    final HttpClientResponse response = await request.close();
    final String bodyText = await utf8.decodeStream(response);
    if (response.statusCode >= 400) {
      throw StateError(
        'Toolbox API request failed (${response.statusCode}): $bodyText',
      );
    }
    if (bodyText.trim().isEmpty) {
      return <String, Object?>{};
    }

    final Object? decoded = jsonDecode(bodyText);
    return _toMap(decoded);
  } finally {
    client.close(force: true);
  }
}

Map<String, Object?> _toolboxParamToJsonSchema(Map<String, Object?> parameter) {
  final String rawType = '${parameter['type'] ?? 'string'}'.toLowerCase();
  final String type = switch (rawType) {
    'float' => 'number',
    _ => rawType,
  };
  final Map<String, Object?> schema = <String, Object?>{
    'type': type,
    if ('${parameter['description'] ?? ''}'.trim().isNotEmpty)
      'description': '${parameter['description']}',
  };

  if (type == 'array') {
    schema['items'] = _toolboxParamToJsonSchema(
      _toMap(parameter['items'] ?? const <String, Object?>{'type': 'string'}),
    );
  }
  if (type == 'object' && parameter.containsKey('additionalProperties')) {
    final Object? additional = parameter['additionalProperties'];
    if (additional is bool) {
      schema['additionalProperties'] = additional;
    } else if (additional is Map) {
      schema['additionalProperties'] = _toolboxParamToJsonSchema(
        _toMap(additional),
      );
    }
  }
  if (parameter.containsKey('default')) {
    schema['default'] = parameter['default'];
  }
  return schema;
}

Map<String, Object?> _toMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

List<Object?> _toList(Object? value) {
  if (value is List<Object?>) {
    return List<Object?>.from(value);
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return <Object?>[];
}
