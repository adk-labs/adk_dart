/// Configuration model for context-cache behavior.
library;

/// Context-cache policy settings for an agent/app.
class ContextCacheConfig {
  /// Creates a context cache config.
  ContextCacheConfig({
    this.cacheIntervals = 10,
    this.ttlSeconds = 1800,
    this.minTokens = 0,
  }) {
    if (cacheIntervals < 1 || cacheIntervals > 100) {
      throw ArgumentError('cache_intervals must be within [1, 100].');
    }
    if (ttlSeconds <= 0) {
      throw ArgumentError('ttl_seconds must be > 0.');
    }
    if (minTokens < 0) {
      throw ArgumentError('min_tokens must be >= 0.');
    }
  }

  /// Interval count used before cache updates.
  final int cacheIntervals;

  /// Cache TTL in seconds.
  final int ttlSeconds;

  /// Minimum token threshold to enable caching.
  final int minTokens;

  /// TTL string representation for backend APIs.
  String get ttlString => '${ttlSeconds}s';

  /// Creates cache config from JSON.
  factory ContextCacheConfig.fromJson(Map<String, Object?> json) {
    return ContextCacheConfig(
      cacheIntervals:
          json['cache_intervals'] as int? ??
          json['cacheIntervals'] as int? ??
          10,
      ttlSeconds:
          json['ttl_seconds'] as int? ?? json['ttlSeconds'] as int? ?? 1800,
      minTokens: json['min_tokens'] as int? ?? json['minTokens'] as int? ?? 0,
    );
  }

  /// Serializes cache config to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'cache_intervals': cacheIntervals,
      'ttl_seconds': ttlSeconds,
      'min_tokens': minTokens,
    };
  }

  @override
  String toString() {
    return 'ContextCacheConfig(cache_intervals=$cacheIntervals, ttl=${ttlSeconds}s, min_tokens=$minTokens)';
  }
}
