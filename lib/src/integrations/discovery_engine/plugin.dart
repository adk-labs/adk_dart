/// Plugin that verifies model responses against registered facts.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import '../../agents/callback_context.dart';
import '../../models/llm_response.dart';
import '../../plugins/base_plugin.dart';
import '../../types/content.dart';
import 'check_grounding_client.dart';
import 'types.dart';

export 'types.dart' show GroundingClient;

// Tried in order, so a chunk ends at the coarsest boundary that fits.
final List<RegExp> _boundaries = <RegExp>[
  RegExp(r'\n\s*\n'),
  RegExp(r'\n'),
  RegExp(r'(?<=[.!?])\s+'),
  RegExp(r'\s+'),
];

/// Hook called with the result of every grounding check.
///
/// Return `null` to keep the model response, which already carries any
/// grounding metadata, or an [LlmResponse] to replace it. Replacing it skips
/// later plugins and agent `afterModelCallback` hooks, as in ADK's own
/// `afterModelCallback`.
///
/// When the agent has a tool with `propagateGroundingMetadata: true`, ADK
/// replaces the response's grounding metadata with that tool's after this hook
/// runs, so `groundingResult` is the only place the check's citations appear.
typedef OnResult =
    FutureOr<LlmResponse?> Function({
      required CallbackContext callbackContext,
      required LlmResponse llmResponse,
      required GroundingResult groundingResult,
    });

/// Verifies final model responses against a fixed set of facts.
///
/// For every final text response, the plugin sends the response and the facts
/// to a [GroundingClient], then attaches the returned citations to the
/// response as `groundingMetadata`. A failed check leaves the response
/// unchanged.
class GroundingPlugin extends BasePlugin {
  /// Initializes the plugin.
  ///
  /// Facts are fixed here and apply to every session and user the plugin
  /// serves, so pass only knowledge shared by all of them.
  ///
  /// [client] defaults to a [CheckGroundingClient] for the
  /// `GOOGLE_CLOUD_PROJECT` project.
  /// [facts] are checked against every final text response. Text longer than
  /// `client.limits.maxFactChars` is split into several chunks. A later fact
  /// with the same [Fact.id] replaces an earlier one.
  /// [onResult] is an optional hook called with each check's result, including
  /// skipped and failed checks.
  ///
  /// Throws an [ArgumentError] if the facts need more chunks than
  /// `client.limits.maxFacts`.
  GroundingPlugin({
    GroundingClient? client,
    Iterable<Fact> facts = const <Fact>[],
    OnResult? onResult,
    super.name = 'grounding_plugin',
    Map<String, String>? environment,
  }) : _ownsClient = client == null,
       _client = client ?? CheckGroundingClient(environment: environment),
       _onResult = onResult {
    final GroundingLimits limits = _client.limits;
    final Map<String, Fact> byId = <String, Fact>{
      for (final Fact fact in facts) fact.id: fact,
    };
    final List<FactChunk> chunks = <FactChunk>[
      for (final Fact fact in byId.values)
        ..._toChunks(fact, limits.maxFactChars),
    ];
    if (chunks.length > limits.maxFacts) {
      throw ArgumentError(
        'Facts need ${chunks.length} chunks, more than max_facts '
        '(${limits.maxFacts}).',
      );
    }
    _chunks = List<FactChunk>.unmodifiable(chunks);
  }

  final bool _ownsClient;
  final GroundingClient _client;
  final OnResult? _onResult;
  late final List<FactChunk> _chunks;

  /// Checks a final text response and attaches its citations.
  @override
  Future<LlmResponse?> afterModelCallback({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
  }) async {
    // Streamed partial responses would yield offsets into incomplete text.
    if ((llmResponse.partial ?? false) || llmResponse.content == null) {
      return null;
    }
    final List<Part> parts = llmResponse.content!.parts;
    // A response that calls a tool is not the final answer.
    if (parts.any((Part part) => part.functionCall != null)) {
      return null;
    }
    // Thoughts are the model's reasoning, not part of the answer.
    final List<({int index, String text})> answerParts =
        <({int index, String text})>[];
    for (int i = 0; i < parts.length; i += 1) {
      final Part part = parts[i];
      if (part.text != null && part.text!.isNotEmpty && !part.thought) {
        answerParts.add((index: i, text: part.text!));
      }
    }
    // Not stripped: citation offsets index into this exact text.
    final String answer = answerParts
        .map((({int index, String text}) entry) => entry.text)
        .join();
    if (answer.trim().isEmpty) {
      return null;
    }

    final GroundingResult rawResult = _chunks.isNotEmpty
        ? await _check(answer, _chunks)
        : const GroundingResult(
            status: GroundingStatus.skippedNoFacts,
            numFactsEvaluated: 0,
          );
    developer.log(
      'Grounding check finished with status ${rawResult.status.value} '
      'for invocation ${callbackContext.invocationId}',
      name: 'adk_dart.discovery_engine',
    );

    GroundingResult result = rawResult;
    if (result.metadata != null) {
      final Map<String, Object?> citations = _mapToParts(
        result.metadata!,
        answerParts,
      );
      result = result.copyWith(metadata: citations);
      // Empty metadata is truthy, so attaching it would mark an uncited answer
      // as grounded.
      if (_hasCitations(citations)) {
        llmResponse.groundingMetadata = _combine(
          llmResponse.groundingMetadata,
          citations,
        );
      }
    }

    if (_onResult == null) {
      return null;
    }
    return await _onResult(
      callbackContext: callbackContext,
      llmResponse: llmResponse,
      groundingResult: result,
    );
  }

  /// Runs the check, reporting any client error as [GroundingStatus.apiError].
  Future<GroundingResult> _check(String answer, List<FactChunk> facts) async {
    try {
      return await _client.checkGroundingAsync(
        answerCandidate: answer,
        facts: facts,
      );
    } catch (e, stackTrace) {
      // A verification failure must not fail the turn; onResult still sees it.
      developer.log(
        'Grounding check failed; response left unchanged.',
        name: 'adk_dart.discovery_engine',
        error: e,
        stackTrace: stackTrace,
      );
      return GroundingResult(
        status: GroundingStatus.apiError,
        numFactsEvaluated: facts.length,
        error: '$e',
      );
    }
  }

  /// Closes the default client; a client passed in is left to its owner.
  @override
  Future<void> close() async {
    if (_ownsClient) {
      await _client.close();
    }
  }
}

bool _hasCitations(Map<String, Object?> metadata) {
  final Object? chunks =
      metadata['grounding_chunks'] ?? metadata['groundingChunks'];
  final Object? supports =
      metadata['grounding_supports'] ?? metadata['groundingSupports'];
  return (chunks is List && chunks.isNotEmpty) ||
      (supports is List && supports.isNotEmpty);
}

/// Moves support segments from the joined answer onto its parts.
///
/// The client checks the answer parts joined into one string, but a `segment`
/// holds byte offsets within the part that `part_index` names. A support that
/// spans parts becomes one support per part.
Map<String, Object?> _mapToParts(
  Map<String, Object?> metadata,
  List<({int index, String text})> answerParts,
) {
  final List<int> joined = utf8.encode(
    answerParts.map((({int index, String text}) entry) => entry.text).join(),
  );
  final List<({int index, int start, int end})> ranges =
      <({int index, int start, int end})>[];
  int start = 0;
  for (final ({int index, String text}) entry in answerParts) {
    final int end = start + utf8.encode(entry.text).length;
    ranges.add((index: entry.index, start: start, end: end));
    start = end;
  }

  final List<Map<String, Object?>> rawSupports = _readMapList(
    metadata['grounding_supports'] ?? metadata['groundingSupports'],
  );
  final List<Map<String, Object?>> supports = <Map<String, Object?>>[];

  for (final Map<String, Object?> support in rawSupports) {
    final Object? rawSegment = support['segment'];
    if (rawSegment is! Map) {
      supports.add(_copyMap(support));
      continue;
    }
    final Map<String, Object?> segment = _toStringKeyMap(rawSegment);
    final int? startIndex = _readOptionalInt(
      segment,
      'start_index',
      'startIndex',
    );
    final int? endIndex = _readOptionalInt(segment, 'end_index', 'endIndex');
    if (startIndex == null || endIndex == null) {
      supports.add(_copyMap(support));
      continue;
    }

    for (final ({int index, int start, int end}) range in ranges) {
      final int low = math.max(startIndex, range.start);
      final int high = math.min(endIndex, range.end);
      if (low >= high) {
        continue;
      }
      final bool whole = low == startIndex && high == endIndex;
      final Map<String, Object?> mapped = _copyMap(support);
      final String? segmentText = whole
          ? segment['text'] as String?
          : utf8.decode(joined.sublist(low, high), allowMalformed: true);
      mapped['segment'] = <String, Object?>{
        'part_index': range.index,
        'start_index': low - range.start,
        'end_index': high - range.start,
        'text': ?segmentText,
      };
      supports.add(mapped);
    }
  }

  final Map<String, Object?> rebased = _copyMap(metadata);
  rebased.remove('groundingSupports');
  if (supports.isNotEmpty) {
    rebased['grounding_supports'] = supports;
  } else {
    rebased.remove('grounding_supports');
  }
  return rebased;
}

/// Adds the check's citations to metadata the model already attached.
///
/// The added chunks go after the existing ones, so the added supports' chunk
/// indices shift by the number of existing chunks. Other fields, such as search
/// queries, are kept from the existing metadata.
Map<String, Object?> _combine(Object? existing, Map<String, Object?> added) {
  if (existing == null || existing is! Map) {
    return added;
  }
  final Map<String, Object?> combined = _toStringKeyMap(existing);
  final List<Object?> existingChunks = _readList(
    combined['grounding_chunks'] ?? combined['groundingChunks'],
  );
  final List<Object?> existingSupports = _readList(
    combined['grounding_supports'] ?? combined['groundingSupports'],
  );
  final List<Object?> addedChunks = _readList(
    added['grounding_chunks'] ?? added['groundingChunks'],
  );
  final List<Map<String, Object?>> addedSupports = _readMapList(
    added['grounding_supports'] ?? added['groundingSupports'],
  );

  final int offset = existingChunks.length;
  final List<Map<String, Object?>> shifted = <Map<String, Object?>>[];
  for (final Map<String, Object?> support in addedSupports) {
    final Map<String, Object?> moved = _copyMap(support);
    final List<int> indices = _readIntList(
      support['grounding_chunk_indices'] ?? support['groundingChunkIndices'],
    );
    moved.remove('groundingChunkIndices');
    moved['grounding_chunk_indices'] = <int>[
      for (final int i in indices) i + offset,
    ];
    shifted.add(moved);
  }

  final List<Object?> mergedChunks = <Object?>[
    ...existingChunks,
    ...addedChunks,
  ];
  final List<Object?> mergedSupports = <Object?>[
    ...existingSupports,
    ...shifted,
  ];

  combined.remove('groundingChunks');
  combined.remove('groundingSupports');
  if (mergedChunks.isNotEmpty) {
    combined['grounding_chunks'] = mergedChunks;
  } else {
    combined.remove('grounding_chunks');
  }
  if (mergedSupports.isNotEmpty) {
    combined['grounding_supports'] = mergedSupports;
  } else {
    combined.remove('grounding_supports');
  }
  return combined;
}

List<FactChunk> _toChunks(Fact fact, int maxChars) {
  return <FactChunk>[
    for (final String text in _splitFactText(fact.text, maxChars))
      FactChunk(
        text: text,
        title: fact.title,
        link: fact.link,
        attributes: Map<String, String>.from(fact.attributes),
      ),
  ];
}

/// Splits [text] into chunks of at most [maxChars] characters.
///
/// Chunks end at paragraph, line, sentence or word boundaries where one falls
/// inside the limit, and are cut at exactly [maxChars] otherwise.
List<String> _splitFactText(String text, int maxChars) {
  final List<String> chunks = <String>[];
  String remaining = text.trim();
  while (remaining.length > maxChars) {
    final String window = remaining.substring(0, maxChars);
    int end = maxChars;
    for (final RegExp boundary in _boundaries) {
      final List<RegExpMatch> matches = boundary.allMatches(window).toList();
      if (matches.isNotEmpty) {
        end = matches.last.end;
        break;
      }
    }
    final String chunk = remaining.substring(0, end).trim();
    if (chunk.isNotEmpty) {
      chunks.add(chunk);
    }
    remaining = remaining.substring(end).trimLeft();
  }
  if (remaining.isNotEmpty) {
    chunks.add(remaining);
  }
  return chunks;
}

Map<String, Object?> _toStringKeyMap(Map<Object?, Object?> raw) {
  return <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in raw.entries)
      '${entry.key}': entry.value,
  };
}

Map<String, Object?> _copyMap(Map<String, Object?> source) {
  return Map<String, Object?>.from(source);
}

List<Object?> _readList(Object? raw) {
  if (raw is! List) return const <Object?>[];
  return List<Object?>.from(raw);
}

List<Map<String, Object?>> _readMapList(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final Object? item in raw)
      if (item is Map) _toStringKeyMap(item),
  ];
}

List<int> _readIntList(Object? raw) {
  if (raw is! List) return const <int>[];
  return <int>[
    for (final Object? item in raw)
      if (item is int) item else if (item is num) item.toInt(),
  ];
}

int? _readOptionalInt(
  Map<String, Object?> map,
  String primaryKey,
  String secondaryKey,
) {
  final Object? raw = map.containsKey(primaryKey)
      ? map[primaryKey]
      : map[secondaryKey];
  if (raw is int) return raw;
  if (raw is num && raw is! bool) return raw.toInt();
  return null;
}
