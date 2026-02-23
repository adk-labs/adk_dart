import '../events/event.dart';
import '../models/cache_metadata.dart';
import '../sessions/base_session_service.dart';
import '../sessions/session.dart';

class CachePerformanceAnalyzer {
  CachePerformanceAnalyzer(this.sessionService);

  final BaseSessionService sessionService;

  Future<List<CacheMetadata>> _getAgentCacheHistory({
    required String sessionId,
    required String userId,
    required String appName,
    String? agentName,
  }) async {
    final Session? session = await sessionService.getSession(
      sessionId: sessionId,
      appName: appName,
      userId: userId,
    );
    if (session == null) {
      return const <CacheMetadata>[];
    }

    final List<CacheMetadata> cacheHistory = <CacheMetadata>[];
    for (final Event event in session.events) {
      final CacheMetadata? cacheMetadata = _toCacheMetadata(
        event.cacheMetadata,
      );
      if (cacheMetadata == null) {
        continue;
      }
      if (agentName == null || event.author == agentName) {
        cacheHistory.add(cacheMetadata);
      }
    }
    return cacheHistory;
  }

  Future<Map<String, Object?>> analyzeAgentCachePerformance({
    required String sessionId,
    required String userId,
    required String appName,
    required String agentName,
  }) async {
    final List<CacheMetadata> cacheHistory = await _getAgentCacheHistory(
      sessionId: sessionId,
      userId: userId,
      appName: appName,
      agentName: agentName,
    );

    if (cacheHistory.isEmpty) {
      return <String, Object?>{'status': 'no_cache_data'};
    }

    final Session? session = await sessionService.getSession(
      sessionId: sessionId,
      appName: appName,
      userId: userId,
    );
    if (session == null) {
      return <String, Object?>{'status': 'no_cache_data'};
    }

    int totalPromptTokens = 0;
    int totalCachedTokens = 0;
    int requestsWithCacheHits = 0;
    int totalRequests = 0;

    for (final Event event in session.events) {
      if (event.author != agentName || event.usageMetadata == null) {
        continue;
      }
      final Map<String, Object?>? usage = _toMap(event.usageMetadata);
      if (usage == null) {
        continue;
      }
      totalRequests += 1;
      totalPromptTokens += _readInt(usage, const <String>[
        'promptTokenCount',
        'prompt_token_count',
      ]);
      final int cachedTokens = _readInt(usage, const <String>[
        'cachedContentTokenCount',
        'cached_content_token_count',
      ]);
      totalCachedTokens += cachedTokens;
      if (cachedTokens > 0) {
        requestsWithCacheHits += 1;
      }
    }

    final double cacheHitRatioPercent = totalPromptTokens > 0
        ? (totalCachedTokens / totalPromptTokens) * 100
        : 0.0;
    final double cacheUtilizationRatioPercent = totalRequests > 0
        ? (requestsWithCacheHits / totalRequests) * 100
        : 0.0;
    final double avgCachedTokensPerRequest = totalRequests > 0
        ? totalCachedTokens / totalRequests
        : 0.0;

    final List<int> invocationsUsed = cacheHistory
        .map((CacheMetadata metadata) => metadata.invocationsUsed ?? 0)
        .toList(growable: false);
    final int totalInvocations = invocationsUsed.fold(
      0,
      (int acc, int value) => acc + value,
    );
    final int cacheRefreshes = cacheHistory
        .map((CacheMetadata metadata) => metadata.cacheName)
        .toSet()
        .length;

    return <String, Object?>{
      'status': 'active',
      'requests_with_cache': cacheHistory.length,
      'avg_invocations_used': invocationsUsed.isEmpty
          ? 0.0
          : totalInvocations / invocationsUsed.length,
      'latest_cache': cacheHistory.last.cacheName,
      'cache_refreshes': cacheRefreshes,
      'total_invocations': totalInvocations,
      'total_prompt_tokens': totalPromptTokens,
      'total_cached_tokens': totalCachedTokens,
      'cache_hit_ratio_percent': cacheHitRatioPercent,
      'cache_utilization_ratio_percent': cacheUtilizationRatioPercent,
      'avg_cached_tokens_per_request': avgCachedTokensPerRequest,
      'total_requests': totalRequests,
      'requests_with_cache_hits': requestsWithCacheHits,
    };
  }
}

Map<String, Object?>? _toMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return null;
}

int _readInt(Map<String, Object?> map, List<String> keys) {
  for (final String key in keys) {
    final Object? value = map[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final int? parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return 0;
}

CacheMetadata? _toCacheMetadata(Object? value) {
  if (value is CacheMetadata) {
    return value;
  }
  final Map<String, Object?>? asMap = _toMap(value);
  if (asMap == null) {
    return null;
  }

  final Object? fingerprint = asMap['fingerprint'];
  if (fingerprint == null || '$fingerprint'.isEmpty) {
    return null;
  }

  return CacheMetadata(
    cacheName:
        asMap['cacheName']?.toString() ?? asMap['cache_name']?.toString(),
    expireTime: _toDouble(asMap['expireTime'] ?? asMap['expire_time']),
    fingerprint: '$fingerprint',
    invocationsUsed: _toInt(
      asMap['invocationsUsed'] ?? asMap['invocations_used'],
    ),
    contentsCount:
        _toInt(asMap['contentsCount'] ?? asMap['contents_count']) ?? 0,
    createdAt: _toDouble(asMap['createdAt'] ?? asMap['created_at']),
  );
}

double? _toDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

int? _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
