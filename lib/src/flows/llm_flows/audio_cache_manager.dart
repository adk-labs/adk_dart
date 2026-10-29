/// LLM flow pipeline components and processors.
library;

import 'dart:typed_data';

import '../../agents/invocation_context.dart';
import '../../events/event.dart';
import '../../live/visual_frames.dart';
import '../../platform/time.dart';
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

/// Configuration for [RealtimeCacheManager].
class RealtimeCacheConfig {
  /// Creates realtime cache configuration.
  RealtimeCacheConfig({
    this.maxCacheSizeBytes = 10 * 1024 * 1024,
    this.maxCacheDurationSeconds = 300.0,
    this.autoFlushThreshold = 100,
    this.maxVisualCacheFrames = 600,
  }) {
    if (maxVisualCacheFrames < 1) {
      throw ArgumentError.value(
        maxVisualCacheFrames,
        'maxVisualCacheFrames',
        'maxVisualCacheFrames must be >= 1',
      );
    }
  }

  /// Max total cache size in bytes.
  final int maxCacheSizeBytes;

  /// Max cache duration in seconds.
  final double maxCacheDurationSeconds;

  /// Threshold for automatic flush triggers.
  final int autoFlushThreshold;

  /// Maximum number of visual frames buffered before oldest frames are dropped.
  final int maxVisualCacheFrames;
}

/// Backward-compatible alias for [RealtimeCacheConfig].
typedef AudioCacheConfig = RealtimeCacheConfig;

/// Backward-compatible alias for [RealtimeCacheManager].
typedef AudioCacheManager = RealtimeCacheManager;

/// Manages input/output realtime audio and visual caches for live flows.
class RealtimeCacheManager {
  /// Creates a realtime cache manager with optional [config].
  RealtimeCacheManager({RealtimeCacheConfig? config})
    : config = config ?? RealtimeCacheConfig();

  /// Active cache configuration.
  final RealtimeCacheConfig config;

  /// Routes a realtime input [blob] to the appropriate audio or visual cache.
  ///
  /// Audio blobs (`audio/*`) are added to the input audio cache. Visual blobs
  /// (`image/*` or `video/*`) with non-empty data are added to
  /// [InvocationContext.inputVisualCache], capped at
  /// [RealtimeCacheConfig.maxVisualCacheFrames]. Other MIME types are ignored.
  void cacheRealtimeBlob(
    InvocationContext invocationContext,
    InlineData blob,
  ) {
    final String normalizedMimeType = blob.mimeType
        .split(';')
        .first
        .trim()
        .toLowerCase();
    if (normalizedMimeType.startsWith('audio/')) {
      cacheAudio(invocationContext, blob, cacheType: 'input');
      return;
    }
    if (normalizedMimeType.startsWith('image/') ||
        normalizedMimeType.startsWith('video/')) {
      if (blob.data.isEmpty) {
        return;
      }
      invocationContext.inputVisualCache ??= <Object?>[];
      final List<Object?> visualCache = invocationContext.inputVisualCache!;
      visualCache.add(
        VisualFrame(blob: blob.copyWith(), timestamp: getTime()),
      );
      final int excess = visualCache.length - config.maxVisualCacheFrames;
      if (excess > 0) {
        visualCache.removeRange(0, excess);
      }
    }
  }

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
        timestamp: getTime(),
      ),
    );
  }

  /// Flushes cached audio and visual frames into artifacts/events and returns emitted events.
  Future<List<Event>> flushCaches(
    InvocationContext invocationContext, {
    bool flushUserAudio = true,
    bool flushUserVisual = true,
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

    if (flushUserVisual && invocationContext.inputVisualCache != null) {
      final Event? visualEvent = await _flushVisualCacheToServices(
        invocationContext,
        _asVisualFrames(invocationContext.inputVisualCache),
      );
      if (visualEvent != null) {
        flushedEvents.add(visualEvent);
        invocationContext.inputVisualCache = <Object?>[];
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

  Future<Event?> _flushVisualCacheToServices(
    InvocationContext invocationContext,
    List<VisualFrame> visualCache,
  ) async {
    if (invocationContext.artifactService == null || visualCache.isEmpty) {
      return null;
    }

    final List<VisualFrame> monotonicFrames = <VisualFrame>[];
    double? lastTimestamp;
    for (final VisualFrame frame in visualCache) {
      final double clampedTimestamp =
          lastTimestamp != null && frame.timestamp < lastTimestamp
          ? lastTimestamp
          : frame.timestamp;
      lastTimestamp = clampedTimestamp;
      monotonicFrames.add(
        clampedTimestamp == frame.timestamp
            ? frame
            : VisualFrame(blob: frame.blob, timestamp: clampedTimestamp),
      );
    }

    final (Uint8List archiveBytes, Map<String, Object?> artifactMetadata) =
        packVisualFrames(monotonicFrames);
    final Object? startTimestampMs = artifactMetadata['start_timestamp_ms'];
    final String filename =
        'adk_live_visual_storage_input_visual_$startTimestampMs.zip';

    final int revisionId = await invocationContext.saveArtifact(
      filename: filename,
      artifact: Part.fromInlineData(
        mimeType: visualFramesZipMimeType,
        data: archiveBytes,
      ),
      customMetadata: artifactMetadata,
    );

    final String artifactRef =
        'artifact://${invocationContext.appName}/${invocationContext.userId}/${invocationContext.session.id}/_adk_live/$filename#$revisionId';

    return Event(
      id: Event.newId(),
      invocationId: invocationContext.invocationId,
      author: 'user',
      content: Content(
        role: 'user',
        parts: <Part>[
          Part.fromFileData(
            fileUri: artifactRef,
            mimeType: visualFramesZipMimeType,
          ),
        ],
      ),
      timestamp: monotonicFrames.first.timestamp,
    );
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
    final String extension = mimeType.split(';').first.trim().split('/').last;
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
    final List<VisualFrame> visualFrames = _asVisualFrames(
      invocationContext.inputVisualCache,
    );
    final List<RealtimeCacheEntry> outputEntries = _asRealtimeCacheEntries(
      invocationContext.outputRealtimeCache,
    );

    final int inputBytes = inputEntries.fold<int>(
      0,
      (int sum, RealtimeCacheEntry entry) => sum + entry.data.data.length,
    );
    final int visualBytes = visualFrames.fold<int>(
      0,
      (int sum, VisualFrame frame) => sum + frame.blob.data.length,
    );
    final int outputBytes = outputEntries.fold<int>(
      0,
      (int sum, RealtimeCacheEntry entry) => sum + entry.data.data.length,
    );

    return <String, int>{
      'input_chunks': inputEntries.length,
      'input_visual_frames': visualFrames.length,
      'output_chunks': outputEntries.length,
      'input_bytes': inputBytes,
      'input_visual_bytes': visualBytes,
      'output_bytes': outputBytes,
      'total_chunks':
          inputEntries.length + visualFrames.length + outputEntries.length,
      'total_bytes': inputBytes + visualBytes + outputBytes,
    };
  }

  List<RealtimeCacheEntry> _asRealtimeCacheEntries(List<Object?>? cache) {
    if (cache == null || cache.isEmpty) {
      return const <RealtimeCacheEntry>[];
    }
    return cache.whereType<RealtimeCacheEntry>().toList(growable: false);
  }

  List<VisualFrame> _asVisualFrames(List<Object?>? cache) {
    if (cache == null || cache.isEmpty) {
      return const <VisualFrame>[];
    }
    return cache.whereType<VisualFrame>().toList(growable: false);
  }
}
