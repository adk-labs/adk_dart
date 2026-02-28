import 'dart:convert';
import 'dart:io';

import '../../auth/auth_credential.dart';
import '../_google_credentials.dart';
import 'config.dart';

const String gdaClientId = 'GOOGLE_ADK';

typedef BigQueryInsightsStreamProvider =
    Future<Stream<String>> Function({
      required Uri url,
      required Map<String, Object?> payload,
      required Map<String, String> headers,
    });

BigQueryInsightsStreamProvider _insightsStreamProvider =
    _defaultInsightsStreamProvider;

Future<Map<String, Object?>> askDataInsights({
  required String projectId,
  required String userQueryWithContext,
  required List<Map<String, String>> tableReferences,
  required Object credentials,
  required Object settings,
}) async {
  try {
    final BigQueryToolConfig toolSettings = BigQueryToolConfig.fromObject(
      settings,
    );

    final String? accessToken = _extractAccessToken(credentials);
    if (accessToken == null || accessToken.isEmpty) {
      return <String, Object?>{
        'status': 'ERROR',
        'error_details': 'ask_data_insights requires a valid access token.',
      };
    }

    final Map<String, String> headers = <String, String>{
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
      'X-Goog-API-Client': gdaClientId,
    };

    final Uri uri = Uri.parse(
      'https://geminidataanalytics.googleapis.com/v1alpha/projects/'
      '$projectId/locations/global:chat',
    );

    const String instructions =
        '**INSTRUCTIONS - FOLLOW THESE RULES:**\n'
        '1.  **CONTENT:** Your answer should present the supporting data and then provide a conclusion based on that data, including relevant details and observations where possible.\n'
        '2.  **ANALYSIS DEPTH:** Your analysis must go beyond surface-level observations. Crucially, you must prioritize metrics that measure impact or outcomes over metrics that simply measure volume or raw counts. For open-ended questions, explore the topic from multiple perspectives to provide a holistic view.\n'
        '3.  **OUTPUT FORMAT:** Your entire response MUST be in plain text format ONLY.\n'
        '4.  **NO CHARTS:** You are STRICTLY FORBIDDEN from generating any charts, graphs, images, or any other form of visualization.\n';

    final Map<String, Object?> payload = <String, Object?>{
      'project': 'projects/$projectId',
      'messages': <Map<String, Object?>>[
        <String, Object?>{
          'userMessage': <String, Object?>{'text': userQueryWithContext},
        },
      ],
      'inlineContext': <String, Object?>{
        'datasourceReferences': <String, Object?>{
          'bq': <String, Object?>{'tableReferences': tableReferences},
        },
        'systemInstruction': instructions,
        'options': <String, Object?>{
          'chart': <String, Object?>{
            'image': <String, Object?>{'noImage': <String, Object?>{}},
          },
        },
      },
      'clientIdEnum': gdaClientId,
    };

    final List<Map<String, Object?>> response = await _getStream(
      uri: uri,
      payload: payload,
      headers: headers,
      maxQueryResultRows: toolSettings.maxQueryResultRows,
    );

    return <String, Object?>{'status': 'SUCCESS', 'response': response};
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

Future<List<Map<String, Object?>>> _getStream({
  required Uri uri,
  required Map<String, Object?> payload,
  required Map<String, String> headers,
  required int maxQueryResultRows,
}) async {
  final Stream<String> responseStream = await _insightsStreamProvider(
    url: uri,
    payload: payload,
    headers: headers,
  );

  String accumulator = '';
  final List<Map<String, Object?>> messages = <Map<String, Object?>>[];

  await for (final String rawLine in responseStream) {
    if (rawLine.isEmpty) {
      continue;
    }
    final String decodedLine = rawLine;

    if (decodedLine == '[{') {
      accumulator = '{';
    } else if (decodedLine == '}]') {
      accumulator += '}';
    } else if (decodedLine == ',') {
      continue;
    } else {
      accumulator += decodedLine;
    }

    if (!_isJson(accumulator)) {
      continue;
    }

    final Object? decoded = jsonDecode(accumulator);
    accumulator = '';

    if (decoded is! Map) {
      continue;
    }

    final Map<String, Object?> dataJson = decoded.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );

    if (!dataJson.containsKey('systemMessage')) {
      if (dataJson['error'] is Map) {
        _appendMessage(
          messages,
          _handleError(Map<String, Object?>.from(dataJson['error'] as Map)),
        );
      }
      continue;
    }

    if (dataJson['systemMessage'] is! Map) {
      continue;
    }

    final Map<String, Object?> systemMessage = Map<String, Object?>.from(
      dataJson['systemMessage'] as Map,
    );

    if (systemMessage['text'] is Map) {
      _appendMessage(
        messages,
        _handleTextResponse(
          Map<String, Object?>.from(systemMessage['text'] as Map),
        ),
      );
    } else if (systemMessage['schema'] is Map) {
      _appendMessage(
        messages,
        _handleSchemaResponse(
          Map<String, Object?>.from(systemMessage['schema'] as Map),
        ),
      );
    } else if (systemMessage['data'] is Map) {
      _appendMessage(
        messages,
        _handleDataResponse(
          Map<String, Object?>.from(systemMessage['data'] as Map),
          maxQueryResultRows,
        ),
      );
    }
  }

  return messages;
}

bool _isJson(String source) {
  try {
    jsonDecode(source);
    return true;
  } catch (_) {
    return false;
  }
}

Object _getProperty(
  Map<String, Object?> data,
  String fieldName, {
  Object defaultValue = '',
}) {
  return data[fieldName] ?? defaultValue;
}

String _formatBqTableRef(Map<String, Object?> tableRef) {
  return '${tableRef['projectId']}.${tableRef['datasetId']}.${tableRef['tableId']}';
}

Map<String, Object?> _formatSchemaAsDict(Map<String, Object?> data) {
  final Object? rawFields = data['fields'];
  if (rawFields is! List || rawFields.isEmpty) {
    return <String, Object?>{'columns': <Object?>[]};
  }

  final List<List<String>> rows = <List<String>>[];
  for (final Object? field in rawFields) {
    if (field is! Map) {
      continue;
    }
    final Map<String, Object?> fieldMap = Map<String, Object?>.from(field);
    rows.add(<String>[
      '${_getProperty(fieldMap, 'name')}',
      '${_getProperty(fieldMap, 'type')}',
      '${_getProperty(fieldMap, 'description', defaultValue: '')}',
      '${_getProperty(fieldMap, 'mode')}',
    ]);
  }

  return <String, Object?>{
    'headers': <String>['Column', 'Type', 'Description', 'Mode'],
    'rows': rows,
  };
}

Map<String, Object?> _formatDatasourceAsDict(Map<String, Object?> datasource) {
  final Map<String, Object?> tableRef = Map<String, Object?>.from(
    datasource['bigqueryTableReference'] as Map,
  );
  final Map<String, Object?> schema = Map<String, Object?>.from(
    datasource['schema'] as Map,
  );

  return <String, Object?>{
    'source_name': _formatBqTableRef(tableRef),
    'schema': _formatSchemaAsDict(schema),
  };
}

Map<String, Object?> _handleTextResponse(Map<String, Object?> response) {
  final Object? partsRaw = response['parts'];
  final List<Object?> parts = partsRaw is List ? partsRaw : <Object?>[];
  final String answer = parts
      .where((Object? value) => value != null)
      .map((Object? part) => '$part')
      .join();
  return <String, Object?>{
    'Answer': answer,
  };
}

Map<String, Object?> _handleSchemaResponse(Map<String, Object?> response) {
  if (response['query'] is Map) {
    final Map<String, Object?> query = Map<String, Object?>.from(
      response['query'] as Map,
    );
    return <String, Object?>{'Question': '${query['question'] ?? ''}'};
  }

  if (response['result'] is Map) {
    final Map<String, Object?> result = Map<String, Object?>.from(
      response['result'] as Map,
    );
    final Object? datasourcesRaw = result['datasources'];
    final List<Map<String, Object?>> datasources = datasourcesRaw is List
        ? datasourcesRaw
              .whereType<Map>()
              .map((Map source) => Map<String, Object?>.from(source))
              .toList(growable: false)
        : <Map<String, Object?>>[];

    return <String, Object?>{
      'Schema Resolved': datasources
          .map(_formatDatasourceAsDict)
          .toList(growable: false),
    };
  }

  return <String, Object?>{};
}

Map<String, Object?> _handleDataResponse(
  Map<String, Object?> response,
  int maxQueryResultRows,
) {
  if (response['query'] is Map) {
    final Map<String, Object?> query = Map<String, Object?>.from(
      response['query'] as Map,
    );
    return <String, Object?>{
      'Retrieval Query': <String, Object?>{
        'Query Name': '${query['name'] ?? 'N/A'}',
        'Question': '${query['question'] ?? 'N/A'}',
      },
    };
  }

  if (response.containsKey('generatedSql')) {
    return <String, Object?>{'SQL Generated': '${response['generatedSql']}'};
  }

  if (response['result'] is Map) {
    final Map<String, Object?> result = Map<String, Object?>.from(
      response['result'] as Map,
    );

    final List<String> headers = <String>[];
    if (result['schema'] is Map) {
      final Map<String, Object?> schema = Map<String, Object?>.from(
        result['schema'] as Map,
      );
      if (schema['fields'] is List) {
        for (final Object? field in schema['fields'] as List) {
          if (field is Map && field['name'] != null) {
            headers.add('${field['name']}');
          }
        }
      }
    }

    final List<Map<String, Object?>> allRows = result['data'] is List
        ? (result['data'] as List)
              .whereType<Map>()
              .map((Map row) => Map<String, Object?>.from(row))
              .toList(growable: false)
        : <Map<String, Object?>>[];

    final List<List<Object?>> compactRows = allRows
        .take(maxQueryResultRows)
        .map(
          (Map<String, Object?> row) => headers
              .map((String header) => row[header])
              .toList(growable: false),
        )
        .toList(growable: false);

    final int totalRows = allRows.length;
    final String summary = totalRows > maxQueryResultRows
        ? 'Showing the first ${compactRows.length} of $totalRows total rows.'
        : 'Showing all $totalRows rows.';

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

  if (messages.isNotEmpty && messages.last.containsKey('Data Retrieved')) {
    messages.removeLast();
  }

  messages.add(newMessage);
}

String? _extractAccessToken(Object credentials) {
  if (credentials is GoogleOAuthCredential) {
    return credentials.accessToken;
  }
  if (credentials is AuthCredential) {
    final String? accessToken = credentials.oauth2?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }
    return accessToken;
  }
  if (credentials is Map) {
    final Object? rawToken =
        credentials['token'] ??
        credentials['access_token'] ??
        credentials['accessToken'];
    if (rawToken != null) {
      final String text = '$rawToken'.trim();
      return text.isEmpty ? null : text;
    }
  }
  if (credentials is String) {
    final String text = credentials.trim();
    return text.isEmpty ? null : text;
  }
  return null;
}

Future<Stream<String>> _defaultInsightsStreamProvider({
  required Uri url,
  required Map<String, Object?> payload,
  required Map<String, String> headers,
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.postUrl(url);
    headers.forEach(request.headers.set);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(payload));

    final HttpClientResponse response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String body = await utf8.decodeStream(response);
      throw HttpException(
        'POST $url failed (${response.statusCode}): $body',
      );
    }

    final String body = await utf8.decodeStream(response);
    return Stream<String>.fromIterable(
      const LineSplitter().convert(body),
    );
  } finally {
    client.close(force: true);
  }
}

void setBigQueryInsightsStreamProvider(
  BigQueryInsightsStreamProvider provider,
) {
  _insightsStreamProvider = provider;
}

void resetBigQueryInsightsStreamProvider() {
  _insightsStreamProvider = _defaultInsightsStreamProvider;
}
