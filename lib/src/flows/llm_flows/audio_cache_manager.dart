import 'dart:typed_data';

import '../../agents/invocation_context.dart';
import '../../events/event.dart';
import '../../types/content.dart';

class RealtimeCacheEntry {
  RealtimeCacheEntry({
    required this.role,
    required this.data,
    required this.timestamp,
  });

  final String role;
  final InlineData data;
  final double timestamp;
}

class AudioCacheConfig {
  AudioCacheConfig({
    this.maxCacheSizeBytes = 10 * 1024 * 1024,
    this.maxCacheDurationSeconds = 300.0,
    this.autoFlushThreshold = 100,
  });

  final int maxCacheSizeBytes;
  final double maxCacheDurationSeconds;
  final int autoFlushThreshold;
}

class AudioCacheManager {
  AudioCacheManager({AudioCacheConfig? config})
    : config = config ?? AudioCacheConfig();

  final AudioCacheConfig config;

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
        'adk_live_audio_storage_${cacheType}_${timestamp}.$extension';

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
