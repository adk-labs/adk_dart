import 'dart:convert';
import 'dart:io';

import '../../auth/auth_credential.dart';
import '../_google_credentials.dart';
import '../tool_context.dart';
import 'config.dart';

const String dataAgentBaseUrl =
    'https://geminidataanalytics.googleapis.com/v1beta';
const String dataAgentClientId = 'GOOGLE_ADK';

typedef DataAgentHttpGet =
    Future<Map<String, Object?>> Function({
      required Uri uri,
      required Map<String, String> headers,
    });

typedef DataAgentStreamPost =
    Future<List<String>> Function({
      required Uri uri,
      required Map<String, Object?> payload,
      required Map<String, String> headers,
    });

Future<Map<String, Object?>> listAccessibleDataAgents({
  required String projectId,
  required Object credentials,
  Object? settings,
  ToolContext? toolContext,
  DataAgentHttpGet? httpGet,
}) async {
  try {
    final Map<String, String> headers = _getHttpHeaders(credentials);
    final Uri uri = Uri.parse(
      '$dataAgentBaseUrl/projects/$projectId/locations/global/dataAgents:listAccessible',
    );
    final Map<String, Object?> response = await (httpGet ?? _defaultHttpGet)(
      uri: uri,
      headers: headers,
    );
    final List<Object?> agents = _readList(response['dataAgents']);
    return <String, Object?>{'status': 'SUCCESS', 'response': agents};
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

Future<Map<String, Object?>> getDataAgentInfo({
  required String dataAgentName,
  required Object credentials,
  Object? settings,
  ToolContext? toolContext,
  DataAgentHttpGet? httpGet,
}) async {
  try {
    final Map<String, String> headers = _getHttpHeaders(credentials);
    final Uri uri = Uri.parse('$dataAgentBaseUrl/$dataAgentName');
    final Map<String, Object?> response = await (httpGet ?? _defaultHttpGet)(
      uri: uri,
      headers: headers,
    );
    return <String, Object?>{'status': 'SUCCESS', 'response': response};
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

Future<Map<String, Object?>> askDataAgent({
  required String dataAgentName,
  required String query,
  required Object credentials,
  Object? settings,
  required ToolContext toolContext,
  DataAgentHttpGet? httpGet,
  DataAgentStreamPost? streamPost,
}) async {
  try {
    final DataAgentToolConfig config = DataAgentToolConfig.fromObject(settings);
    final Map<String, String> headers = _getHttpHeaders(credentials);

    final Map<String, Object?> agentInfo = await getDataAgentInfo(
      dataAgentName: dataAgentName,
      credentials: credentials,
      httpGet: httpGet,
    );
    if (agentInfo['status'] == 'ERROR') {
      return agentInfo;
    }

    final String parent = _extractParentResource(dataAgentName);
    final Uri chatUri = Uri.parse('$dataAgentBaseUrl/$parent:chat');
    final Map<String, Object?> chatPayload = <String, Object?>{
      'messages': <Object?>[
        <String, Object?>{
          'userMessage': <String, Object?>{'text': query},
        },
      ],
      'dataAgentContext': <String, Object?>{'dataAgent': dataAgentName},
      'clientIdEnum': dataAgentClientId,
    };

    final List<String> lines = await (streamPost ?? _defaultStreamPost)(
      uri: chatUri,
      payload: chatPayload,
      headers: headers,
    );
    final List<Map<String, Object?>> response = _getStream(
      lines: lines,
      maxQueryResultRows: config.maxQueryResultRows,
    );
    return <String, Object?>{'status': 'SUCCESS', 'response': response};
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

Map<String, String> _getHttpHeaders(Object credentials) {
  final String? token = _extractAccessToken(credentials);
  if (token == null || token.isEmpty) {
    throw ArgumentError(
      'The provided credentials object does not have a valid access token.',
    );
  }
  return <String, String>{
    'authorization': 'Bearer $token',
    'content-type': 'application/json',
    'x-goog-api-client': dataAgentClientId,
  };
}

String _extractParentResource(String dataAgentName) {
  final int marker = dataAgentName.lastIndexOf('/dataAgents/');
  if (marker <= 0) {
    return dataAgentName;
  }
  return dataAgentName.substring(0, marker);
}

List<Map<String, Object?>> _getStream({
  required List<String> lines,
  required int maxQueryResultRows,
}) {
  String accumulator = '';
  final List<Map<String, Object?>> messages = <Map<String, Object?>>[];

  for (final String rawLine in lines) {
    final String decodedLine = rawLine.trim();
    if (decodedLine.isEmpty) {
      continue;
    }

    if (decodedLine == '[{') {
      accumulator = '{';
    } else if (decodedLine == '}]') {
      accumulator = '$accumulator}';
    } else if (decodedLine == ',') {
      continue;
    } else {
      accumulator += decodedLine;
    }

    final Object? decoded = _tryDecodeJson(accumulator);
    if (decoded is! Map) {
      continue;
    }
    final Map<String, Object?> dataJson = _readMap(decoded);
    if (!dataJson.containsKey('systemMessage')) {
      if (dataJson.containsKey('error')) {
        _appendMessage(messages, _handleError(_readMap(dataJson['error'])));
      }
      continue;
    }

    final Map<String, Object?> systemMessage = _readMap(
      dataJson['systemMessage'],
    );
    if (systemMessage.containsKey('text')) {
      _appendMessage(
        messages,
        _handleTextResponse(_readMap(systemMessage['text'])),
      );
    } else if (systemMessage.containsKey('schema')) {
      _appendMessage(
        messages,
        _handleSchemaResponse(_readMap(systemMessage['schema'])),
      );
    } else if (systemMessage.containsKey('data')) {
      _appendMessage(
        messages,
        _handleDataResponse(
          _readMap(systemMessage['data']),
          maxQueryResultRows,
        ),
      );
    }
    accumulator = '';
  }

  return messages;
}

String _formatBqTableRef(Map<String, Object?> tableRef) {
  final String projectId = _readString(tableRef['projectId']) ?? '';
  final String datasetId = _readString(tableRef['datasetId']) ?? '';
  final String tableId = _readString(tableRef['tableId']) ?? '';
  return '$projectId.$datasetId.$tableId';
}

Map<String, Object?> _formatSchemaAsDict(Map<String, Object?> data) {
  final List<Object?> fields = _readList(data['fields']);
  if (fields.isEmpty) {
    return <String, Object?>{'columns': <Object?>[]};
  }

  final List<List<String>> rows = <List<String>>[];
  for (final Object? item in fields) {
    final Map<String, Object?> field = _readMap(item);
    rows.add(<String>[
      _readString(field['name']) ?? '',
      _readString(field['type']) ?? '',
      _readString(field['description']) ?? '',
      _readString(field['mode']) ?? '',
    ]);
  }
  return <String, Object?>{
    'headers': const <String>['Column', 'Type', 'Description', 'Mode'],
    'rows': rows,
  };
}

Map<String, Object?> _formatDatasourceAsDict(Map<String, Object?> datasource) {
  final Map<String, Object?> tableRef = _readMap(
    datasource['bigqueryTableReference'],
  );
  final Map<String, Object?> schema = _formatSchemaAsDict(
    _readMap(datasource['schema']),
  );
  return <String, Object?>{
    'source_name': _formatBqTableRef(tableRef),
    'schema': schema,
  };
}

Map<String, Object?> _handleTextResponse(Map<String, Object?> response) {
  final List<Object?> parts = _readList(response['parts']);
  return <String, Object?>{
    'Answer': parts.map((Object? part) => '$part').join(),
  };
}

Map<String, Object?> _handleSchemaResponse(Map<String, Object?> response) {
  if (response.containsKey('query')) {
    final Map<String, Object?> query = _readMap(response['query']);
    return <String, Object?>{'Question': _readString(query['question']) ?? ''};
  }

  if (response.containsKey('result')) {
    final Map<String, Object?> result = _readMap(response['result']);
    final List<Object?> datasources = _readList(result['datasources']);
    final List<Map<String, Object?>> formattedSources = datasources
        .map((Object? item) => _formatDatasourceAsDict(_readMap(item)))
        .toList();
    return <String, Object?>{'Schema Resolved': formattedSources};
  }

  return <String, Object?>{};
}

Map<String, Object?> _handleDataResponse(
  Map<String, Object?> response,
  int maxQueryResultRows,
) {
  if (response.containsKey('query')) {
    final Map<String, Object?> query = _readMap(response['query']);
    return <String, Object?>{
      'Retrieval Query': <String, Object?>{
        'Query Name': _readString(query['name']) ?? 'N/A',
        'Question': _readString(query['question']) ?? 'N/A',
      },
    };
  }

  if (response.containsKey('generatedSql')) {
    return <String, Object?>{
      'SQL Generated': _readString(response['generatedSql']) ?? '',
    };
  }

  if (response.containsKey('result')) {
    final Map<String, Object?> result = _readMap(response['result']);
    final Map<String, Object?> schema = _readMap(result['schema']);
    final List<Object?> schemaFields = _readList(schema['fields']);
    final List<String> headers = schemaFields
        .map((Object? field) => _readString(_readMap(field)['name']) ?? '')
        .toList();

    final List<Object?> allRows = _readList(result['data']);
    final int totalRows = allRows.length;
    final int cap = maxQueryResultRows < 0 ? 0 : maxQueryResultRows;
    final List<List<Object?>> compactRows = <List<Object?>>[];
    for (final Object? rowValue in allRows.take(cap)) {
      final Map<String, Object?> row = _readMap(rowValue);
      compactRows.add(
        headers.map((String header) => row[header]).toList(growable: false),
      );
    }

    String summary = 'Showing all $totalRows rows.';
    if (totalRows > maxQueryResultRows) {
      summary =
          'Showing the first ${compactRows.length} of $totalRows total rows.';
    }
    return <String, Object?>{
      'Data Retrieved': <String, Object?>{
        'headers': headers,
        'rows': compactRows,
        'summary': summary,
      },
    };
  }

  return <String, Object?>{};
}

Map<String, Object?> _handleError(Map<String, Object?> response) {
  return <String, Object?>{
    'Error': <String, Object?>{
      'Code': response['code'] ?? 'N/A',
      'Message': response['message'] ?? 'No message provided.',
    },
  };
}

void _appendMessage(
  List<Map<String, Object?>> messages,
  Map<String, Object?> newMessage,
) {
  if (newMessage.isEmpty) {
    return;
  }
  messages.add(newMessage);
}

Future<Map<String, Object?>> _defaultHttpGet({
  required Uri uri,
  required Map<String, String> headers,
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final HttpClientResponse response = await request.close();
    final String body = await utf8.decodeStream(response);
    if (response.statusCode >= 400) {
      throw HttpException('GET $uri failed (${response.statusCode}): $body');
    }
    final Object? decoded = body.isEmpty
        ? <String, Object?>{}
        : jsonDecode(body);
    return _readMap(decoded);
  } finally {
    client.close(force: true);
  }
}

Future<List<String>> _defaultStreamPost({
  required Uri uri,
  required Map<String, Object?> payload,
  required Map<String, String> headers,
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.postUrl(uri);
    headers.forEach(request.headers.set);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(payload));

    final HttpClientResponse response = await request.close();
    final String body = await utf8.decodeStream(response);
    if (response.statusCode >= 400) {
      throw HttpException('POST $uri failed (${response.statusCode}): $body');
    }

    final List<String> lines = <String>[];
    for (final String line in const LineSplitter().convert(body)) {
      if (line.startsWith('data:')) {
        final String content = line.substring(5).trimLeft();
        if (content == '[DONE]') {
          continue;
        }
        lines.add(content);
      } else {
        lines.add(line);
      }
    }
    return lines;
  } finally {
    client.close(force: true);
  }
}

String? _extractAccessToken(Object credentials) {
  if (credentials is GoogleOAuthCredential) {
    return credentials.accessToken;
  }
  if (credentials is AuthCredential) {
    return credentials.oauth2?.accessToken;
  }
  if (credentials is Map) {
    return _readString(credentials['token']) ??
        _readString(credentials['access_token']);
  }
  if (credentials is String && credentials.isNotEmpty) {
    return credentials;
  }
  return null;
}

Object? _tryDecodeJson(String value) {
  try {
    return jsonDecode(value);
  } catch (_) {
    return null;
  }
}

Map<String, Object?> _readMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

List<Object?> _readList(Object? value) {
  if (value is List<Object?>) {
    return value;
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
  return '$value';
}
