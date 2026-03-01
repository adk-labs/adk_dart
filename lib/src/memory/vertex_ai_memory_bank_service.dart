import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../events/event.dart';
import '../sessions/session.dart';
import '../types/content.dart';
import '../utils/vertex_ai_utils.dart';
import 'base_memory_service.dart';
import 'memory_entry.dart';

const Set<String> _generateMemoriesConfigFallbackKeys = <String>{
  'disable_consolidation',
  'disable_memory_revisions',
  'http_options',
  'metadata',
  'metadata_merge_strategy',
  'revision_expire_time',
  'revision_labels',
  'revision_ttl',
  'wait_for_completion',
};

const Set<String> _createMemoryConfigFallbackKeys = <String>{
  'description',
  'disable_memory_revisions',
  'display_name',
  'expire_time',
  'http_options',
  'metadata',
  'revision_labels',
  'revision_expire_time',
  'revision_ttl',
  'topics',
  'ttl',
  'wait_for_completion',
};

const String _enableConsolidationKey = 'enable_consolidation';
const int _maxDirectMemoriesPerGenerateCall = 5;

bool _supportsGenerateMemoriesMetadata() => true;

bool _supportsCreateMemoryMetadata() => true;

Set<String> _getGenerateMemoriesConfigKeys() {
  return _generateMemoriesConfigFallbackKeys;
}

Set<String> _getCreateMemoryConfigKeys() {
  return _createMemoryConfigFallbackKeys;
}

class VertexAiRetrievedMemory {
  VertexAiRetrievedMemory({required this.fact, required this.updateTime});

  final String fact;
  final DateTime updateTime;
}

abstract class VertexAiMemoryBankApiClient {
  Future<void> generateFromEvents({
    required String agentEngineId,
    required String appName,
    required String userId,
    required List<Map<String, Object?>> events,
    required Map<String, Object?> config,
  });

  Future<void> createMemory({
    required String agentEngineId,
    required String appName,
    required String userId,
    required String fact,
    required Map<String, Object?> config,
  });

  Future<void> generateFromDirectMemories({
    required String agentEngineId,
    required String appName,
    required String userId,
    required List<String> directMemories,
    required Map<String, Object?> config,
  });

  Stream<VertexAiRetrievedMemory> retrieve({
    required String agentEngineId,
    required String appName,
    required String userId,
    required String query,
  });
}

typedef VertexAiMemoryBankApiClientFactory =
    VertexAiMemoryBankApiClient Function({
      String? project,
      String? location,
      String? apiKey,
    });

VertexAiMemoryBankApiClient _defaultMemoryBankApiClientFactory({
  String? project,
  String? location,
  String? apiKey,
}) {
  final bool hasProjectAndLocation =
      (project?.isNotEmpty ?? false) && (location?.isNotEmpty ?? false);
  if (hasProjectAndLocation || (apiKey?.isNotEmpty ?? false)) {
    return VertexAiMemoryBankHttpApiClient(
      project: project,
      location: location,
      apiKey: apiKey,
    );
  }
  throw ArgumentError(
    'VertexAiMemoryBankService requires either project/location or '
    'expressModeApiKey.',
  );
}

typedef VertexAiMemoryBankAccessTokenProvider = Future<String?> Function();

typedef VertexAiMemoryBankUriBuilder =
    Uri Function({
      required String operation,
      required String agentEngineId,
      required String? project,
      required String? location,
      required String apiVersion,
      required String? apiKey,
    });

class VertexAiMemoryBankHttpApiClient implements VertexAiMemoryBankApiClient {
  VertexAiMemoryBankHttpApiClient({
    this.project,
    this.location,
    this.apiKey,
    String apiVersion = 'v1beta1',
    http.Client? httpClient,
    VertexAiMemoryBankAccessTokenProvider? accessTokenProvider,
    VertexAiMemoryBankUriBuilder? uriBuilder,
  }) : _apiVersion = apiVersion,
       _httpClient = httpClient ?? http.Client(),
       _accessTokenProvider =
           accessTokenProvider ?? _defaultVertexAiAccessTokenProvider,
       _uriBuilder = uriBuilder ?? _defaultVertexAiMemoryUriBuilder;

  final String? project;
  final String? location;
  final String? apiKey;
  final String _apiVersion;
  final http.Client _httpClient;
  final VertexAiMemoryBankAccessTokenProvider _accessTokenProvider;
  final VertexAiMemoryBankUriBuilder _uriBuilder;

  @override
  Future<void> generateFromEvents({
    required String agentEngineId,
    required String appName,
    required String userId,
    required List<Map<String, Object?>> events,
    required Map<String, Object?> config,
  }) async {
    final List<Map<String, Object?>> normalizedEvents = events
        .map(_normalizeVertexGenerateEvent)
        .where((Map<String, Object?> event) => event.isNotEmpty)
        .toList(growable: false);
    if (normalizedEvents.isEmpty) {
      return;
    }

    await _postJson(
      operation: 'generate',
      agentEngineId: agentEngineId,
      payload: <String, Object?>{
        'scope': <String, Object?>{'app_name': appName, 'user_id': userId},
        'direct_contents_source': <String, Object?>{'events': normalizedEvents},
        'config': Map<String, Object?>.from(config),
      },
    );
  }

  @override
  Future<void> createMemory({
    required String agentEngineId,
    required String appName,
    required String userId,
    required String fact,
    required Map<String, Object?> config,
  }) async {
    await _postJson(
      operation: 'create',
      agentEngineId: agentEngineId,
      payload: <String, Object?>{
        'scope': <String, Object?>{'app_name': appName, 'user_id': userId},
        'fact': fact,
        'config': Map<String, Object?>.from(config),
      },
    );
  }

  @override
  Future<void> generateFromDirectMemories({
    required String agentEngineId,
    required String appName,
    required String userId,
    required List<String> directMemories,
    required Map<String, Object?> config,
  }) async {
    final List<Map<String, Object?>> normalizedDirectMemories = directMemories
        .where((String fact) => fact.trim().isNotEmpty)
        .map((String fact) => <String, Object?>{'fact': fact})
        .toList(growable: false);
    if (normalizedDirectMemories.isEmpty) {
      return;
    }

    await _postJson(
      operation: 'generate',
      agentEngineId: agentEngineId,
      payload: <String, Object?>{
        'scope': <String, Object?>{'app_name': appName, 'user_id': userId},
        'direct_memories_source': <String, Object?>{
          'direct_memories': normalizedDirectMemories,
        },
        'config': Map<String, Object?>.from(config),
      },
    );
  }

  @override
  Stream<VertexAiRetrievedMemory> retrieve({
    required String agentEngineId,
    required String appName,
    required String userId,
    required String query,
  }) async* {
    final Map<String, Object?> json = await _postJson(
      operation: 'retrieve',
      agentEngineId: agentEngineId,
      payload: <String, Object?>{
        'scope': <String, Object?>{'app_name': appName, 'user_id': userId},
        'similarity_search_params': <String, Object?>{'search_query': query},
      },
    );

    for (final Map<String, Object?> memoryJson in _extractMemoryRows(json)) {
      final String? fact = _readStringByKeys(memoryJson, const <String>[
        'fact',
        'memory_fact',
        'text',
      ]);
      if (fact == null || fact.trim().isEmpty) {
        continue;
      }
      final DateTime updateTime =
          _readDateTimeByKeys(memoryJson, const <String>[
            'update_time',
            'updateTime',
            'create_time',
            'createTime',
          ]) ??
          DateTime.now().toUtc();
      yield VertexAiRetrievedMemory(fact: fact, updateTime: updateTime);
    }
  }

  Future<Map<String, Object?>> _postJson({
    required String operation,
    required String agentEngineId,
    required Map<String, Object?> payload,
  }) async {
    final Uri uri = _uriBuilder(
      operation: operation,
      agentEngineId: agentEngineId,
      project: project,
      location: location,
      apiVersion: _apiVersion,
      apiKey: apiKey,
    );
    final String? accessToken = await _accessTokenProvider();
    final Map<String, String> headers = <String, String>{
      'content-type': 'application/json',
      'accept': 'application/json',
    };
    if (accessToken != null && accessToken.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $accessToken';
    }

    final http.Response response = await _httpClient.post(
      uri,
      headers: headers,
      body: jsonEncode(payload),
    );
    if (response.statusCode >= 400) {
      throw HttpException(
        'Vertex Memory Bank API call failed (${response.statusCode}): '
        '${response.body}',
      );
    }
    final String body = response.body.trim();
    if (body.isEmpty) {
      return <String, Object?>{};
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map) {
      return <String, Object?>{};
    }
    return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
  }
}

Future<String?> _defaultVertexAiAccessTokenProvider() async {
  final Map<String, String> environment = Platform.environment;
  return environment['GOOGLE_OAUTH_ACCESS_TOKEN'] ??
      environment['GOOGLE_ACCESS_TOKEN'] ??
      environment['ACCESS_TOKEN'];
}

Uri _defaultVertexAiMemoryUriBuilder({
  required String operation,
  required String agentEngineId,
  required String? project,
  required String? location,
  required String apiVersion,
  required String? apiKey,
}) {
  final bool hasProjectAndLocation =
      (project?.isNotEmpty ?? false) && (location?.isNotEmpty ?? false);
  final String baseUrl = (location?.isNotEmpty ?? false)
      ? 'https://$location-aiplatform.googleapis.com/'
      : 'https://aiplatform.googleapis.com/';
  final String engineResource = hasProjectAndLocation
      ? 'projects/$project/locations/$location/reasoningEngines/$agentEngineId'
      : 'reasoningEngines/$agentEngineId';

  final String operationPath;
  switch (operation) {
    case 'generate':
      operationPath = '$apiVersion/$engineResource:generateMemories';
      break;
    case 'create':
      operationPath = '$apiVersion/$engineResource/memories';
      break;
    case 'retrieve':
      operationPath = '$apiVersion/$engineResource:retrieveMemories';
      break;
    default:
      throw ArgumentError.value(
        operation,
        'operation',
        'Unsupported Vertex memory bank operation.',
      );
  }

  final Uri uri = Uri.parse(baseUrl).resolve(operationPath);
  final String? resolvedApiKey = apiKey?.trim();
  if (resolvedApiKey == null || resolvedApiKey.isEmpty) {
    return uri;
  }
  return uri.replace(
    queryParameters: <String, String>{
      ...uri.queryParameters,
      'key': resolvedApiKey,
    },
  );
}

Iterable<Map<String, Object?>> _extractMemoryRows(
  Map<String, Object?> json,
) sync* {
  final List<Object?> buckets = <Object?>[
    json['memories'],
    json['retrieved_memories'],
    json['retrievedMemories'],
    json['items'],
    json['results'],
  ];
  for (final Object? bucket in buckets) {
    if (bucket is! List) {
      continue;
    }
    for (final Object? item in bucket) {
      final Map<String, Object?> row = _asStringMap(item);
      if (row.isEmpty) {
        continue;
      }
      final Map<String, Object?> nestedMemory = _asStringMap(row['memory']);
      if (nestedMemory.isNotEmpty) {
        yield nestedMemory;
      } else {
        yield row;
      }
    }
  }
}

Map<String, Object?> _asStringMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

String? _readStringByKeys(Map<String, Object?> json, List<String> keys) {
  for (final String key in keys) {
    final Object? value = json[key];
    if (value == null) {
      continue;
    }
    final String text = '$value';
    if (text.trim().isNotEmpty) {
      return text;
    }
  }
  return null;
}

DateTime? _readDateTimeByKeys(Map<String, Object?> json, List<String> keys) {
  for (final String key in keys) {
    final Object? value = json[key];
    if (value == null) {
      continue;
    }
    if (value is num) {
      final int millis = (value.toDouble() * 1000).round();
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    }
    if (value is String && value.isNotEmpty) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed.toUtc();
      }
    }
  }
  return null;
}

class InMemoryVertexAiMemoryBankApiClient
    implements VertexAiMemoryBankApiClient {
  static final Map<String, List<_StoredMemory>> _storeByScope =
      <String, List<_StoredMemory>>{};

  static String _scopeKey({
    required String agentEngineId,
    required String appName,
    required String userId,
  }) {
    return '$agentEngineId::$appName::$userId';
  }

  @override
  Future<void> createMemory({
    required String agentEngineId,
    required String appName,
    required String userId,
    required String fact,
    required Map<String, Object?> config,
  }) async {
    final String key = _scopeKey(
      agentEngineId: agentEngineId,
      appName: appName,
      userId: userId,
    );
    final List<_StoredMemory> bucket = _storeByScope.putIfAbsent(
      key,
      () => <_StoredMemory>[],
    );
    bucket.add(
      _StoredMemory(
        fact: fact,
        updateTime: DateTime.now().toUtc(),
        metadata: Map<String, Object?>.from(config),
      ),
    );
  }

  @override
  Future<void> generateFromDirectMemories({
    required String agentEngineId,
    required String appName,
    required String userId,
    required List<String> directMemories,
    required Map<String, Object?> config,
  }) async {
    final String key = _scopeKey(
      agentEngineId: agentEngineId,
      appName: appName,
      userId: userId,
    );
    final List<_StoredMemory> bucket = _storeByScope.putIfAbsent(
      key,
      () => <_StoredMemory>[],
    );
    for (final String memory in directMemories) {
      bucket.add(
        _StoredMemory(
          fact: memory,
          updateTime: DateTime.now().toUtc(),
          metadata: Map<String, Object?>.from(config),
        ),
      );
    }
  }

  @override
  Future<void> generateFromEvents({
    required String agentEngineId,
    required String appName,
    required String userId,
    required List<Map<String, Object?>> events,
    required Map<String, Object?> config,
  }) async {
    final String key = _scopeKey(
      agentEngineId: agentEngineId,
      appName: appName,
      userId: userId,
    );
    final List<_StoredMemory> bucket = _storeByScope.putIfAbsent(
      key,
      () => <_StoredMemory>[],
    );
    for (final Map<String, Object?> event in events) {
      final String fact = _extractFactFromGenerateEvent(event);
      if (fact.isEmpty) {
        continue;
      }
      bucket.add(
        _StoredMemory(
          fact: fact,
          updateTime: DateTime.now().toUtc(),
          metadata: Map<String, Object?>.from(config),
        ),
      );
    }
  }

  @override
  Stream<VertexAiRetrievedMemory> retrieve({
    required String agentEngineId,
    required String appName,
    required String userId,
    required String query,
  }) async* {
    final String key = _scopeKey(
      agentEngineId: agentEngineId,
      appName: appName,
      userId: userId,
    );
    final List<_StoredMemory> bucket =
        _storeByScope[key] ?? const <_StoredMemory>[];

    final Set<String> queryTokens = _tokenize(query);

    final List<_StoredMemory> sorted = List<_StoredMemory>.from(bucket)
      ..sort(
        (_StoredMemory a, _StoredMemory b) =>
            b.updateTime.compareTo(a.updateTime),
      );

    for (final _StoredMemory stored in sorted) {
      if (queryTokens.isNotEmpty && !_sharesToken(stored.fact, queryTokens)) {
        continue;
      }
      yield VertexAiRetrievedMemory(
        fact: stored.fact,
        updateTime: stored.updateTime,
      );
    }
  }
}

class _StoredMemory {
  _StoredMemory({
    required this.fact,
    required this.updateTime,
    required this.metadata,
  });

  final String fact;
  final DateTime updateTime;
  final Map<String, Object?> metadata;
}

class VertexAiMemoryBankService extends BaseMemoryService {
  VertexAiMemoryBankService({
    String? project,
    String? location,
    required String agentEngineId,
    String? expressModeApiKey,
    VertexAiMemoryBankApiClientFactory? clientFactory,
  }) : _project = project,
       _location = location,
       _agentEngineId = agentEngineId,
       _expressModeApiKey = getExpressModeApiKey(
         project: project,
         location: location,
         expressModeApiKey: expressModeApiKey,
       ),
       _clientFactory = clientFactory ?? _defaultMemoryBankApiClientFactory {
    if (agentEngineId.isEmpty) {
      throw ArgumentError(
        'agent_engine_id is required for VertexAiMemoryBankService.',
      );
    }

    if (agentEngineId.contains('/')) {
      print(
        "agent_engine_id appears to be a full resource path: '$agentEngineId'. "
        "Expected just the ID (e.g., '456').",
      );
    }
  }

  final String? _project;
  final String? _location;
  final String _agentEngineId;
  final String? _expressModeApiKey;
  final VertexAiMemoryBankApiClientFactory _clientFactory;

  VertexAiMemoryBankApiClient? _client;

  VertexAiMemoryBankApiClient _getApiClient() {
    final VertexAiMemoryBankApiClient? existing = _client;
    if (existing != null) {
      return existing;
    }
    final VertexAiMemoryBankApiClient created = _clientFactory(
      project: _project,
      location: _location,
      apiKey: _expressModeApiKey,
    );
    _client = created;
    return created;
  }

  @override
  Future<void> addSessionToMemory(Session session) async {
    await _addEventsToMemoryFromEvents(
      appName: session.appName,
      userId: session.userId,
      eventsToProcess: session.events,
    );
  }

  @override
  Future<void> addEventsToMemory({
    required String appName,
    required String userId,
    required List<Event> events,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) async {
    await _addEventsToMemoryFromEvents(
      appName: appName,
      userId: userId,
      eventsToProcess: events,
      customMetadata: customMetadata,
    );
  }

  @override
  Future<void> addMemory({
    required String appName,
    required String userId,
    required List<MemoryEntry> memories,
    Map<String, Object?>? customMetadata,
  }) async {
    if (_isConsolidationEnabled(customMetadata)) {
      await _addMemoriesViaGenerateDirectMemoriesSource(
        appName: appName,
        userId: userId,
        memories: memories,
        customMetadata: customMetadata,
      );
      return;
    }

    await _addMemoriesViaCreate(
      appName: appName,
      userId: userId,
      memories: memories,
      customMetadata: customMetadata,
    );
  }

  Future<void> _addEventsToMemoryFromEvents({
    required String appName,
    required String userId,
    required List<Event> eventsToProcess,
    Map<String, Object?>? customMetadata,
  }) async {
    final List<Map<String, Object?>> directEvents = <Map<String, Object?>>[];
    for (final Event event in eventsToProcess) {
      if (_shouldFilterOutEvent(event.content)) {
        continue;
      }
      final Content? content = event.content;
      if (content == null) {
        continue;
      }
      directEvents.add(<String, Object?>{'content': _contentToVertexJson(content)});
    }

    if (directEvents.isEmpty) {
      return;
    }

    final VertexAiMemoryBankApiClient apiClient = _getApiClient();
    final Map<String, Object?> config = _buildGenerateMemoriesConfig(
      customMetadata,
    );
    await apiClient.generateFromEvents(
      agentEngineId: _agentEngineId,
      appName: appName,
      userId: userId,
      events: directEvents,
      config: config,
    );
  }

  Future<void> _addMemoriesViaCreate({
    required String appName,
    required String userId,
    required List<MemoryEntry> memories,
    Map<String, Object?>? customMetadata,
  }) async {
    final List<MemoryEntry> normalizedMemories = _normalizeMemoriesForCreate(
      memories,
    );
    final VertexAiMemoryBankApiClient apiClient = _getApiClient();

    for (int index = 0; index < normalizedMemories.length; index += 1) {
      final MemoryEntry memory = normalizedMemories[index];
      final String memoryFact = _memoryEntryToFact(memory, index: index);
      final Map<String, Object?>? memoryMetadata =
          _mergeCustomMetadataForMemory(
            customMetadata: customMetadata,
            memory: memory,
          );
      final Map<String, String>? memoryRevisionLabels =
          _revisionLabelsForMemory(memory);
      final Map<String, Object?> config = _buildCreateMemoryConfig(
        memoryMetadata,
        memoryRevisionLabels: memoryRevisionLabels,
      );

      await apiClient.createMemory(
        agentEngineId: _agentEngineId,
        appName: appName,
        userId: userId,
        fact: memoryFact,
        config: config,
      );
    }
  }

  Future<void> _addMemoriesViaGenerateDirectMemoriesSource({
    required String appName,
    required String userId,
    required List<MemoryEntry> memories,
    Map<String, Object?>? customMetadata,
  }) async {
    final List<MemoryEntry> normalizedMemories = _normalizeMemoriesForCreate(
      memories,
    );
    final List<String> memoryTexts = <String>[];
    for (int i = 0; i < normalizedMemories.length; i += 1) {
      memoryTexts.add(_memoryEntryToFact(normalizedMemories[i], index: i));
    }

    final VertexAiMemoryBankApiClient apiClient = _getApiClient();
    final Map<String, Object?> config = _buildGenerateMemoriesConfig(
      customMetadata,
    );
    for (final List<String> memoryBatch in _iterMemoryBatches(memoryTexts)) {
      await apiClient.generateFromDirectMemories(
        agentEngineId: _agentEngineId,
        appName: appName,
        userId: userId,
        directMemories: memoryBatch,
        config: config,
      );
    }
  }

  @override
  Future<SearchMemoryResponse> searchMemory({
    required String appName,
    required String userId,
    required String query,
  }) async {
    final VertexAiMemoryBankApiClient apiClient = _getApiClient();
    final List<MemoryEntry> memoryEvents = <MemoryEntry>[];

    await for (final VertexAiRetrievedMemory retrievedMemory
        in apiClient.retrieve(
          agentEngineId: _agentEngineId,
          appName: appName,
          userId: userId,
          query: query,
        )) {
      memoryEvents.add(
        MemoryEntry(
          author: 'user',
          content: Content(
            role: 'user',
            parts: <Part>[Part.text(retrievedMemory.fact)],
          ),
          timestamp: retrievedMemory.updateTime.toIso8601String(),
        ),
      );
    }

    return SearchMemoryResponse(memories: memoryEvents);
  }
}

bool _shouldFilterOutEvent(Content? content) {
  if (content == null || content.parts.isEmpty) {
    return true;
  }
  for (final Part part in content.parts) {
    if ((part.text != null && part.text!.isNotEmpty) ||
        part.inlineData != null ||
        part.fileData != null) {
      return false;
    }
  }
  return true;
}

Map<String, Object?> _buildGenerateMemoriesConfig(
  Map<String, Object?>? customMetadata,
) {
  final Map<String, Object?> config = <String, Object?>{
    'wait_for_completion': false,
  };
  final bool supportsMetadata = _supportsGenerateMemoriesMetadata();
  final Set<String> configKeys = _getGenerateMemoriesConfigKeys();
  if (customMetadata == null || customMetadata.isEmpty) {
    return config;
  }

  final Map<String, Object?> metadataByKey = <String, Object?>{};
  customMetadata.forEach((String key, Object? value) {
    if (key == _enableConsolidationKey) {
      return;
    }

    if (key == 'ttl') {
      if (value == null) {
        return;
      }
      if (customMetadata['revision_ttl'] == null) {
        config['revision_ttl'] = value;
      }
      return;
    }

    if (key == 'metadata') {
      if (value == null) {
        return;
      }
      if (!supportsMetadata) {
        return;
      }
      if (value is Map) {
        config['metadata'] = _buildVertexMetadata(
          value.map((Object? k, Object? v) => MapEntry('$k', v)),
        );
      }
      return;
    }

    if (configKeys.contains(key)) {
      if (value == null) {
        return;
      }
      config[key] = value;
      return;
    }

    metadataByKey[key] = value;
  });

  if (metadataByKey.isEmpty || !supportsMetadata) {
    return config;
  }

  final Object? existingMetadata = config['metadata'];
  if (existingMetadata == null) {
    config['metadata'] = _buildVertexMetadata(metadataByKey);
    return config;
  }

  if (existingMetadata is Map) {
    final Map<String, Object?> mergedMetadata = existingMetadata.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
    mergedMetadata.addAll(_buildVertexMetadata(metadataByKey));
    config['metadata'] = mergedMetadata;
  }

  return config;
}

Map<String, Object?> _buildCreateMemoryConfig(
  Map<String, Object?>? customMetadata, {
  Map<String, String>? memoryRevisionLabels,
}) {
  final Map<String, Object?> config = <String, Object?>{
    'wait_for_completion': false,
  };
  final bool supportsMetadata = _supportsCreateMemoryMetadata();
  final Set<String> configKeys = _getCreateMemoryConfigKeys();
  final bool supportsRevisionLabels = configKeys.contains('revision_labels');

  final Map<String, Object?> metadataByKey = <String, Object?>{};
  final Map<String, String> customRevisionLabels = <String, String>{};

  customMetadata?.forEach((String key, Object? value) {
    if (key == _enableConsolidationKey) {
      return;
    }

    if (key == 'metadata') {
      if (value == null || !supportsMetadata) {
        return;
      }
      if (value is Map) {
        config['metadata'] = _buildVertexMetadata(
          value.map((Object? k, Object? v) => MapEntry('$k', v)),
        );
      }
      return;
    }

    if (key == 'revision_labels') {
      if (value == null) {
        return;
      }
      final Map<String, String>? extracted = _extractRevisionLabels(
        value,
        source: 'custom_metadata["revision_labels"]',
      );
      if (extracted != null) {
        customRevisionLabels.addAll(extracted);
      }
      return;
    }

    if (configKeys.contains(key)) {
      if (value == null) {
        return;
      }
      config[key] = value;
      return;
    }

    metadataByKey[key] = value;
  });

  if (metadataByKey.isNotEmpty && supportsMetadata) {
    final Object? existingMetadata = config['metadata'];
    if (existingMetadata == null) {
      config['metadata'] = _buildVertexMetadata(metadataByKey);
    } else if (existingMetadata is Map) {
      final Map<String, Object?> mergedMetadata = existingMetadata.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      mergedMetadata.addAll(_buildVertexMetadata(metadataByKey));
      config['metadata'] = mergedMetadata;
    }
  }

  final Map<String, String> revisionLabels = <String, String>{
    ...customRevisionLabels,
    ...?memoryRevisionLabels,
  };
  if (revisionLabels.isNotEmpty && supportsRevisionLabels) {
    config['revision_labels'] = revisionLabels;
  }

  return config;
}

List<MemoryEntry> _normalizeMemoriesForCreate(List<MemoryEntry> memories) {
  if (memories.isEmpty) {
    throw ArgumentError('memories must contain at least one entry.');
  }
  return List<MemoryEntry>.from(memories);
}

String _memoryEntryToFact(MemoryEntry memory, {required int index}) {
  if (_shouldFilterOutEvent(memory.content)) {
    throw ArgumentError('memories[$index] must include text.');
  }

  final List<String> textParts = <String>[];
  for (final Part part in memory.content.parts) {
    if (part.inlineData != null || part.fileData != null) {
      throw ArgumentError(
        'memories[$index] must include text only; inline_data and '
        'file_data are not supported.',
      );
    }

    final String? rawText = part.text;
    if (rawText == null) {
      continue;
    }
    final String strippedText = rawText.trim();
    if (strippedText.isNotEmpty) {
      textParts.add(strippedText);
    }
  }

  if (textParts.isEmpty) {
    throw ArgumentError('memories[$index] must include non-whitespace text.');
  }
  return textParts.join('\n');
}

Map<String, Object?>? _mergeCustomMetadataForMemory({
  required Map<String, Object?>? customMetadata,
  required MemoryEntry memory,
}) {
  final Map<String, Object?> mergedMetadata = <String, Object?>{};
  if (customMetadata != null) {
    mergedMetadata.addAll(customMetadata);
  }
  mergedMetadata.addAll(memory.customMetadata);

  if (mergedMetadata.isEmpty) {
    return null;
  }
  return mergedMetadata;
}

Map<String, String>? _revisionLabelsForMemory(MemoryEntry memory) {
  final Map<String, String> revisionLabels = <String, String>{};
  if (memory.author != null) {
    revisionLabels['author'] = memory.author!;
  }
  if (memory.timestamp != null) {
    revisionLabels['timestamp'] = memory.timestamp!;
  }

  if (revisionLabels.isEmpty) {
    return null;
  }
  return revisionLabels;
}

Map<String, String>? _extractRevisionLabels(
  Object value, {
  required String source,
}) {
  if (value is! Map) {
    return null;
  }

  final Map<String, String> revisionLabels = <String, String>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    final Object? key = entry.key;
    final Object? labelValue = entry.value;
    if (key is! String || labelValue is! String) {
      continue;
    }
    revisionLabels[key] = labelValue;
  }

  if (revisionLabels.isEmpty) {
    return null;
  }
  return revisionLabels;
}

bool _isConsolidationEnabled(Map<String, Object?>? customMetadata) {
  if (customMetadata == null || customMetadata.isEmpty) {
    return false;
  }
  final Object? enableConsolidation = customMetadata[_enableConsolidationKey];
  if (enableConsolidation == null) {
    return false;
  }
  if (enableConsolidation is! bool) {
    throw ArgumentError(
      'custom_metadata["$_enableConsolidationKey"] must be a bool.',
    );
  }
  return enableConsolidation;
}

List<List<String>> _iterMemoryBatches(List<String> memories) {
  final List<List<String>> memoryBatches = <List<String>>[];
  for (
    int index = 0;
    index < memories.length;
    index += _maxDirectMemoriesPerGenerateCall
  ) {
    memoryBatches.add(
      memories.sublist(
        index,
        index + _maxDirectMemoriesPerGenerateCall > memories.length
            ? memories.length
            : index + _maxDirectMemoriesPerGenerateCall,
      ),
    );
  }
  return memoryBatches;
}

Map<String, Object?> _buildVertexMetadata(Map<String, Object?> metadataByKey) {
  final Map<String, Object?> vertexMetadata = <String, Object?>{};
  metadataByKey.forEach((String key, Object? value) {
    final Map<String, Object?>? converted = _toVertexMetadataValue(key, value);
    if (converted == null) {
      return;
    }
    vertexMetadata[key] = converted;
  });
  return vertexMetadata;
}

Map<String, Object?>? _toVertexMetadataValue(String key, Object? value) {
  if (value is bool) {
    return <String, Object?>{'bool_value': value};
  }
  if (value is num) {
    return <String, Object?>{'double_value': value.toDouble()};
  }
  if (value is String) {
    return <String, Object?>{'string_value': value};
  }
  if (value is DateTime) {
    return <String, Object?>{
      'timestamp_value': value.toUtc().toIso8601String(),
    };
  }
  if (value is Map) {
    final Map<String, Object?> normalized = <String, Object?>{};
    value.forEach((Object? mapKey, Object? mapValue) {
      normalized['$mapKey'] = mapValue;
    });

    const Set<String> allowed = <String>{
      'bool_value',
      'double_value',
      'string_value',
      'timestamp_value',
    };
    if (normalized.keys.every(allowed.contains)) {
      return normalized;
    }
    return <String, Object?>{'string_value': normalized.toString()};
  }
  if (value == null) {
    return null;
  }
  return <String, Object?>{'string_value': '$value'};
}

Map<String, Object?> _contentToVertexJson(Content content) {
  final Map<String, Object?> payload = <String, Object?>{
    'parts': content.parts.map(_partToVertexJson).toList(growable: false),
  };
  if (content.role != null) {
    payload['role'] = content.role!;
  }
  return payload;
}

Map<String, Object?> _partToVertexJson(Part part) {
  final Map<String, Object?> payload = <String, Object?>{};
  if (part.text != null) {
    payload['text'] = part.text!;
  }
  if (part.thought) {
    payload['thought'] = true;
  }
  if (part.thoughtSignature != null) {
    payload['thought_signature'] = base64Encode(part.thoughtSignature!);
  }
  if (part.functionCall != null) {
    payload['function_call'] = <String, Object?>{
      'name': part.functionCall!.name,
      if (part.functionCall!.args.isNotEmpty)
        'args': Map<String, dynamic>.from(part.functionCall!.args),
      if (part.functionCall!.id != null) 'id': part.functionCall!.id!,
      if (part.functionCall!.partialArgs != null)
        'partial_args': part.functionCall!.partialArgs!
            .map((Map<String, Object?> item) => Map<String, Object?>.from(item))
            .toList(growable: false),
      if (part.functionCall!.willContinue != null)
        'will_continue': part.functionCall!.willContinue!,
    };
  }
  if (part.functionResponse != null) {
    payload['function_response'] = <String, Object?>{
      'name': part.functionResponse!.name,
      if (part.functionResponse!.response.isNotEmpty)
        'response': Map<String, dynamic>.from(part.functionResponse!.response),
      if (part.functionResponse!.id != null) 'id': part.functionResponse!.id!,
    };
  }
  if (part.inlineData != null) {
    payload['inline_data'] = <String, Object?>{
      'mime_type': part.inlineData!.mimeType,
      'data': base64Encode(part.inlineData!.data),
      if (part.inlineData!.displayName != null)
        'display_name': part.inlineData!.displayName!,
    };
  }
  if (part.fileData != null) {
    payload['file_data'] = <String, Object?>{
      'file_uri': part.fileData!.fileUri,
      if (part.fileData!.mimeType != null) 'mime_type': part.fileData!.mimeType!,
      if (part.fileData!.displayName != null)
        'display_name': part.fileData!.displayName!,
    };
  }
  if (part.executableCode != null) {
    payload['executable_code'] = part.executableCode;
  }
  if (part.codeExecutionResult != null) {
    payload['code_execution_result'] = part.codeExecutionResult;
  }
  return payload;
}

Map<String, Object?> _normalizeVertexGenerateEvent(Map<String, Object?> event) {
  final Map<String, Object?> normalizedEvent = _asStringMap(event);
  final Map<String, Object?> content = _asStringMap(normalizedEvent['content']);
  if (content.isEmpty) {
    return <String, Object?>{};
  }
  final Object? partsRaw = content['parts'];
  if (partsRaw is! List) {
    return <String, Object?>{};
  }
  final List<Map<String, Object?>> parts = partsRaw
      .map(_asStringMap)
      .map(_normalizeVertexPartPayload)
      .where((Map<String, Object?> part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return <String, Object?>{};
  }
  final Map<String, Object?> normalizedContent = <String, Object?>{
    'parts': parts,
  };
  if (content['role'] != null) {
    normalizedContent['role'] = '${content['role']}';
  }
  return <String, Object?>{'content': normalizedContent};
}

Map<String, Object?> _normalizeVertexPartPayload(Map<String, Object?> part) {
  final Map<String, Object?> normalized = Map<String, Object?>.from(part);
  final Object? thoughtSignature = normalized['thought_signature'];
  if (thoughtSignature is List<int>) {
    normalized['thought_signature'] = base64Encode(thoughtSignature);
  } else if (thoughtSignature is List) {
    normalized['thought_signature'] = base64Encode(
      thoughtSignature.map((Object? value) => (value as num).toInt()).toList(),
    );
  }

  final Map<String, Object?> inlineData = _asStringMap(normalized['inline_data']);
  if (inlineData.isNotEmpty) {
    final Object? rawData = inlineData['data'];
    if (rawData is List<int>) {
      inlineData['data'] = base64Encode(rawData);
      normalized['inline_data'] = inlineData;
    } else if (rawData is List) {
      inlineData['data'] = base64Encode(
        rawData.map((Object? value) => (value as num).toInt()).toList(),
      );
      normalized['inline_data'] = inlineData;
    }
  }
  return normalized;
}

String _extractFactFromGenerateEvent(Map<String, Object?> event) {
  final Map<String, Object?> normalized = _normalizeVertexGenerateEvent(event);
  if (normalized.isEmpty) {
    return '';
  }
  final Map<String, Object?> content = _asStringMap(normalized['content']);
  final Object? partsRaw = content['parts'];
  if (partsRaw is! List) {
    return '';
  }
  final List<String> segments = <String>[];
  for (final Object? partRaw in partsRaw) {
    final Map<String, Object?> part = _asStringMap(partRaw);
    final String? text = _readStringByKeys(part, const <String>['text']);
    if (text != null && text.trim().isNotEmpty) {
      segments.add(text.trim());
      continue;
    }
    final Map<String, Object?> inlineData = _asStringMap(part['inline_data']);
    if (inlineData.isNotEmpty) {
      final String mimeType = '${inlineData['mime_type'] ?? ''}'.trim();
      if (mimeType.isNotEmpty) {
        segments.add('[inline_data:$mimeType]');
        continue;
      }
    }
    final Map<String, Object?> fileData = _asStringMap(part['file_data']);
    if (fileData.isNotEmpty) {
      final String fileUri = '${fileData['file_uri'] ?? ''}'.trim();
      if (fileUri.isNotEmpty) {
        segments.add('[file_data:$fileUri]');
      }
    }
  }
  return segments.join('\n');
}

Set<String> _tokenize(String text) {
  return RegExp(r'[A-Za-z0-9]+')
      .allMatches(text.toLowerCase())
      .map((Match match) => match.group(0)!)
      .toSet();
}

bool _sharesToken(String fact, Set<String> queryTokens) {
  if (queryTokens.isEmpty) {
    return true;
  }
  final Set<String> factTokens = _tokenize(fact);
  for (final String token in queryTokens) {
    if (factTokens.contains(token)) {
      return true;
    }
  }
  return false;
}
