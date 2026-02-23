import 'dart:collection';
import 'dart:convert';

import '../events/event.dart';
import '../sessions/session.dart';
import '../types/content.dart';
import '_utils.dart';
import 'base_memory_service.dart';
import 'memory_entry.dart';

class VertexRagStoreRagResource {
  VertexRagStoreRagResource({required this.ragCorpus});

  final String ragCorpus;
}

class VertexRagStore {
  VertexRagStore({
    this.ragResources,
    this.ragCorpora,
    this.similarityTopK,
    this.vectorDistanceThreshold,
  });

  final List<VertexRagStoreRagResource>? ragResources;
  final List<String>? ragCorpora;
  final int? similarityTopK;
  final double? vectorDistanceThreshold;
}

class VertexAiRagContext {
  VertexAiRagContext({
    required this.sourceDisplayName,
    required this.text,
    this.vectorDistance,
  });

  final String sourceDisplayName;
  final String text;
  final double? vectorDistance;
}

class VertexAiRagRetrievalResponse {
  VertexAiRagRetrievalResponse({List<VertexAiRagContext>? contexts})
    : contexts = contexts ?? <VertexAiRagContext>[];

  final List<VertexAiRagContext> contexts;
}

abstract class VertexAiRagClient {
  Future<void> uploadFile({
    required String corpusName,
    required String text,
    required String displayName,
  });

  Future<VertexAiRagRetrievalResponse> retrievalQuery({
    required String text,
    List<VertexRagStoreRagResource>? ragResources,
    List<String>? ragCorpora,
    int? similarityTopK,
    double? vectorDistanceThreshold,
  });
}

class InMemoryVertexAiRagClient implements VertexAiRagClient {
  final Map<String, List<_RagDocument>> _docsByCorpus =
      <String, List<_RagDocument>>{};

  @override
  Future<void> uploadFile({
    required String corpusName,
    required String text,
    required String displayName,
  }) async {
    final List<_RagDocument> docs = _docsByCorpus.putIfAbsent(
      corpusName,
      () => <_RagDocument>[],
    );
    docs.add(_RagDocument(displayName: displayName, text: text));
  }

  @override
  Future<VertexAiRagRetrievalResponse> retrievalQuery({
    required String text,
    List<VertexRagStoreRagResource>? ragResources,
    List<String>? ragCorpora,
    int? similarityTopK,
    double? vectorDistanceThreshold,
  }) async {
    final Set<String> corpusNames = <String>{
      ...?ragCorpora,
      ...?ragResources?.map(
        (VertexRagStoreRagResource resource) => resource.ragCorpus,
      ),
    };

    final List<_RankedContext> ranked = <_RankedContext>[];
    final Iterable<MapEntry<String, List<_RagDocument>>> source =
        corpusNames.isEmpty
        ? _docsByCorpus.entries
        : _docsByCorpus.entries.where((
            MapEntry<String, List<_RagDocument>> entry,
          ) {
            return corpusNames.contains(entry.key);
          });

    for (final MapEntry<String, List<_RagDocument>> entry in source) {
      for (final _RagDocument doc in entry.value) {
        final double overlap = _tokenOverlap(text, doc.text);
        final double distance = 1.0 - overlap;
        if (vectorDistanceThreshold != null &&
            distance > vectorDistanceThreshold) {
          continue;
        }
        ranked.add(
          _RankedContext(
            context: VertexAiRagContext(
              sourceDisplayName: doc.displayName,
              text: doc.text,
              vectorDistance: distance,
            ),
            distance: distance,
          ),
        );
      }
    }

    ranked.sort((_RankedContext a, _RankedContext b) {
      return a.distance.compareTo(b.distance);
    });

    final int takeCount = similarityTopK == null || similarityTopK <= 0
        ? ranked.length
        : similarityTopK;

    return VertexAiRagRetrievalResponse(
      contexts: ranked
          .take(takeCount)
          .map((_RankedContext item) => item.context)
          .toList(growable: false),
    );
  }
}

class _RagDocument {
  _RagDocument({required this.displayName, required this.text});

  final String displayName;
  final String text;
}

class _RankedContext {
  _RankedContext({required this.context, required this.distance});

  final VertexAiRagContext context;
  final double distance;
}

class VertexAiRagMemoryService extends BaseMemoryService {
  VertexAiRagMemoryService({
    String? ragCorpus,
    int? similarityTopK,
    double vectorDistanceThreshold = 10,
    VertexAiRagClient? ragClient,
  }) : _ragClient = ragClient ?? InMemoryVertexAiRagClient(),
       _vertexRagStore = VertexRagStore(
         ragResources: ragCorpus == null
             ? <VertexRagStoreRagResource>[]
             : <VertexRagStoreRagResource>[
                 VertexRagStoreRagResource(ragCorpus: ragCorpus),
               ],
         similarityTopK: similarityTopK,
         vectorDistanceThreshold: vectorDistanceThreshold,
       );

  final VertexAiRagClient _ragClient;
  final VertexRagStore _vertexRagStore;

  @override
  Future<void> addSessionToMemory(Session session) async {
    final StringBuffer output = StringBuffer();
    for (final Event event in session.events) {
      final Content? content = event.content;
      if (content == null || content.parts.isEmpty) {
        continue;
      }

      final List<String> textParts = content.parts
          .where((Part part) => part.text != null)
          .map((Part part) => part.text!.replaceAll('\n', ' '))
          .where((String value) => value.isNotEmpty)
          .toList(growable: false);

      if (textParts.isEmpty) {
        continue;
      }

      final Map<String, Object?> row = <String, Object?>{
        'author': event.author,
        'timestamp': event.timestamp,
        'text': textParts.join('.'),
      };
      if (output.isNotEmpty) {
        output.writeln();
      }
      output.write(jsonEncode(row));
    }

    final List<VertexRagStoreRagResource>? resources =
        _vertexRagStore.ragResources;
    if (resources == null || resources.isEmpty) {
      throw ArgumentError('Rag resources must be set.');
    }

    for (final VertexRagStoreRagResource ragResource in resources) {
      await _ragClient.uploadFile(
        corpusName: ragResource.ragCorpus,
        text: output.toString(),
        displayName: '${session.appName}.${session.userId}.${session.id}',
      );
    }
  }

  @override
  Future<SearchMemoryResponse> searchMemory({
    required String appName,
    required String userId,
    required String query,
  }) async {
    final VertexAiRagRetrievalResponse response = await _ragClient
        .retrievalQuery(
          text: query,
          ragResources: _vertexRagStore.ragResources,
          ragCorpora: _vertexRagStore.ragCorpora,
          similarityTopK: _vertexRagStore.similarityTopK,
          vectorDistanceThreshold: _vertexRagStore.vectorDistanceThreshold,
        );

    final LinkedHashMap<String, List<List<Event>>> sessionEventsMap =
        LinkedHashMap<String, List<List<Event>>>();

    for (final VertexAiRagContext context in response.contexts) {
      if (!context.sourceDisplayName.startsWith('$appName.$userId.')) {
        continue;
      }

      final String sessionId = context.sourceDisplayName.split('.').last;
      final List<Event> events = _eventsFromContextText(context.text);

      sessionEventsMap
          .putIfAbsent(sessionId, () => <List<Event>>[])
          .add(events);
    }

    final List<MemoryEntry> memoryResults = <MemoryEntry>[];
    sessionEventsMap.forEach((String _, List<List<Event>> eventLists) {
      for (final List<Event> events in _mergeEventLists(
        List<List<Event>>.from(eventLists),
      )) {
        events.sort((Event a, Event b) => a.timestamp.compareTo(b.timestamp));
        for (final Event event in events) {
          final Content? content = event.content;
          if (content == null) {
            continue;
          }
          memoryResults.add(
            MemoryEntry(
              author: event.author,
              content: content.copyWith(),
              timestamp: formatTimestamp(event.timestamp),
            ),
          );
        }
      }
    });

    return SearchMemoryResponse(memories: memoryResults);
  }
}

List<Event> _eventsFromContextText(String text) {
  final List<Event> events = <Event>[];
  for (final String rawLine in text.split('\n')) {
    final String line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }

    try {
      final Object? decoded = jsonDecode(line);
      if (decoded is! Map) {
        continue;
      }
      final Map<Object?, Object?> map = decoded;
      final String author = '${map['author'] ?? ''}';
      final double timestamp = _parseTimestamp(map['timestamp']);
      final String body = '${map['text'] ?? ''}';
      events.add(
        Event(
          invocationId: 'memory_retrieval',
          author: author,
          timestamp: timestamp,
          content: Content(parts: <Part>[Part.text(body)]),
        ),
      );
    } on FormatException {
      continue;
    }
  }
  return events;
}

double _parseTimestamp(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}

List<List<Event>> _mergeEventLists(List<List<Event>> eventLists) {
  final List<List<Event>> merged = <List<Event>>[];
  while (eventLists.isNotEmpty) {
    final List<Event> current = eventLists.removeAt(0);
    final Set<double> currentTs = current
        .map((Event event) => event.timestamp)
        .toSet();

    bool mergeFound = true;
    while (mergeFound) {
      mergeFound = false;
      final List<List<Event>> remaining = <List<Event>>[];
      for (final List<Event> other in eventLists) {
        final Set<double> otherTs = other
            .map((Event event) => event.timestamp)
            .toSet();
        if (currentTs.intersection(otherTs).isNotEmpty) {
          for (final Event event in other) {
            if (!currentTs.contains(event.timestamp)) {
              current.add(event);
              currentTs.add(event.timestamp);
            }
          }
          mergeFound = true;
        } else {
          remaining.add(other);
        }
      }
      eventLists = remaining;
    }

    merged.add(current);
  }
  return merged;
}

double _tokenOverlap(String query, String context) {
  final Set<String> queryTokens = _tokenize(query);
  final Set<String> contextTokens = _tokenize(context);
  if (queryTokens.isEmpty || contextTokens.isEmpty) {
    return 0.0;
  }

  int overlap = 0;
  for (final String token in queryTokens) {
    if (contextTokens.contains(token)) {
      overlap += 1;
    }
  }
  return overlap / queryTokens.length;
}

Set<String> _tokenize(String text) {
  return RegExp(r'[A-Za-z0-9]+')
      .allMatches(text.toLowerCase())
      .map((Match match) => match.group(0)!)
      .toSet();
}
