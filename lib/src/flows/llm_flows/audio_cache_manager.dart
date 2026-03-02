import 'dart:typed_data';

import '../../agents/invocation_context.dart';
import '../../events/event.dart';
import '../../types/content.dart';

/// One cached realtime audio chunk with role and timestamp metadata.
class RealtimeCacheEntry {
  /// Creates a realtime cache entry.
  RealtimeCacheEntry({
    required this.role,
    required this.data,
    required this.timestamp,
  });

  /// Speaker role associated with this chunk.
  final String role;

  /// Audio payload for this chunk.
  final InlineData data;

  /// Capture timestamp in Unix seconds.
  final double timestamp;
}

/// Configuration for [AudioCacheManager].
class AudioCacheConfig {
  /// Creates audio cache configuration.
  AudioCacheConfig({
    this.maxCacheSizeBytes = 10 * 1024 * 1024,
    this.maxCacheDurationSeconds = 300.0,
    this.autoFlushThreshold = 100,
  });

  /// Max total cache size in bytes.
  final int maxCacheSizeBytes;

  /// Max cache duration in seconds.
  final double maxCacheDurationSeconds;

  /// Threshold for automatic flush triggers.
  final int autoFlushThreshold;
}

/// Manages input/output realtime audio caches for live flows.
class AudioCacheManager {
  /// Creates an audio cache manager with optional [config].
  AudioCacheManager({AudioCacheConfig? config})
    : config = config ?? AudioCacheConfig();

  /// Active cache configuration.
  final AudioCacheConfig config;

  /// Adds [audioBlob] to the selected cache type.
  ///
  /// [cacheType] must be either `input` or `output`.
  void cacheAudio(
    InvocationContext invocationContext,
    InlineData audioBlob, {
    required String cacheType,
  }) {
    List<Object?> cache;
    String role;

    if (cacheType == 'input') {
      invocationContext.inputRealtimeCache ??= <Object?>[];
      cache = invocationContext.inputRealtimeCache!;
      role = 'user';
    } else if (cacheType == 'output') {
      invocationContext.outputRealtimeCache ??= <Object?>[];
      cache = invocationContext.outputRealtimeCache!;
      role = 'model';
    } else {
      throw ArgumentError.value(
        cacheType,
        'cacheType',
        "cacheType must be either 'input' or 'output'",
      );
    }

    cache.add(
      RealtimeCacheEntry(
        role: role,
        data: audioBlob.copyWith(),
        timestamp: DateTime.now().millisecondsSinceEpoch / 1000,
      ),
    );
  }

  /// Flushes cached audio into artifacts/events and returns emitted events.
  Future<List<Event>> flushCaches(
    InvocationContext invocationContext, {
    bool flushUserAudio = true,
    bool flushModelAudio = true,
  }) async {
    final List<Event> flushedEvents = <Event>[];

    if (flushUserAudio && invocationContext.inputRealtimeCache != null) {
      final Event? audioEvent = await _flushCacheToServices(
        invocationContext,
        _asRealtimeCacheEntries(invocationContext.inputRealtimeCache),
        'input_audio',
      );
      if (audioEvent != null) {
        flushedEvents.add(audioEvent);
        invocationContext.inputRealtimeCache = <Object?>[];
      }
    }

    if (flushModelAudio && invocationContext.outputRealtimeCache != null) {
      final Event? audioEvent = await _flushCacheToServices(
        invocationContext,
        _asRealtimeCacheEntries(invocationContext.outputRealtimeCache),
        'output_audio',
      );
      if (audioEvent != null) {
        flushedEvents.add(audioEvent);
        invocationContext.outputRealtimeCache = <Object?>[];
      }
    }

    return flushedEvents;
  }

  Future<Event?> _flushCacheToServices(
    InvocationContext invocationContext,
    List<RealtimeCacheEntry> audioCache,
    String cacheType,
  ) async {
    if (invocationContext.artifactService == null || audioCache.isEmpty) {
      return null;
    }

    final BytesBuilder builder = BytesBuilder(copy: false);
    for (final RealtimeCacheEntry entry in audioCache) {
      builder.add(entry.data.data);
    }

    final List<int> combinedAudioData = builder.takeBytes();
    final String mimeType = audioCache.first.data.mimeType;
    final int timestamp = (audioCache.first.timestamp * 1000).floor();
    final String extension = mimeType.split('/').last;
    final String filename =
        'adk_live_audio_storage_${cacheType}_$timestamp.$extension';

    final int revisionId = await invocationContext.saveArtifact(
      filename: filename,
      artifact: Part.fromInlineData(
        mimeType: mimeType,
        data: combinedAudioData,
      ),
    );

    final String artifactRef =
        'artifact://${invocationContext.appName}/${invocationContext.userId}/${invocationContext.session.id}/_adk_live/$filename#$revisionId';

    final RealtimeCacheEntry firstEntry = audioCache.first;
    final String author = firstEntry.role == 'model'
        ? invocationContext.agent.name
        : firstEntry.role;

    return Event(
      id: Event.newId(),
      invocationId: invocationContext.invocationId,
      author: author,
      content: Content(
        role: firstEntry.role,
        parts: <Part>[
          Part.fromFileData(fileUri: artifactRef, mimeType: mimeType),
        ],
      ),
      timestamp: firstEntry.timestamp,
    );
  }

  /// Returns aggregate cache statistics for [invocationContext].
  Map<String, int> getCacheStats(InvocationContext invocationContext) {
    final List<RealtimeCacheEntry> inputEntries = _asRealtimeCacheEntries(
      invocationContext.inputRealtimeCache,
    );
    final List<RealtimeCacheEntry> outputEntries = _asRealtimeCacheEntries(
      invocationContext.outputRealtimeCache,
    );

    final int inputBytes = inputEntries.fold<int>(
      0,
      (int sum, RealtimeCacheEntry entry) => sum + entry.data.data.length,
    );
    final int outputBytes = outputEntries.fold<int>(
      0,
      (int sum, RealtimeCacheEntry entry) => sum + entry.data.data.length,
    );

    return <String, int>{
      'input_chunks': inputEntries.length,
      'output_chunks': outputEntries.length,
      'input_bytes': inputBytes,
      'output_bytes': outputBytes,
      'total_chunks': inputEntries.length + outputEntries.length,
      'total_bytes': inputBytes + outputBytes,
    };
  }

  List<RealtimeCacheEntry> _asRealtimeCacheEntries(List<Object?>? cache) {
    if (cache == null || cache.isEmpty) {
      return const <RealtimeCacheEntry>[];
    }
    return cache.whereType<RealtimeCacheEntry>().toList(growable: false);
  }
}
