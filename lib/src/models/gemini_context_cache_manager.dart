import 'dart:convert';

import '../agents/context_cache_config.dart';
import '../types/content.dart';
import 'cache_metadata.dart';
import 'llm_request.dart';
import 'llm_response.dart';

class GeminiCreatedCache {
  GeminiCreatedCache({required this.name});

  final String name;
}

abstract class GeminiCacheClient {
  Future<GeminiCreatedCache> createCache({
    required String model,
    required List<Content> contents,
    required String ttl,
    required String displayName,
    String? systemInstruction,
    List<ToolDeclaration>? tools,
    LlmToolConfig? toolConfig,
  });

  Future<void> deleteCache({required String cacheName});
}

class GeminiContextCacheManager {
  const GeminiContextCacheManager({this.cacheClient});

  final GeminiCacheClient? cacheClient;

  Future<CacheMetadata?> handleContextCaching(LlmRequest request) async {
    final ContextCacheConfig? cacheConfig = _coerceContextCacheConfig(
      request.cacheConfig,
    );
    if (cacheConfig == null) {
      return null;
    }

    final CacheMetadata? existing = _coerceCacheMetadata(request.cacheMetadata);
    if (existing != null) {
      if (_isCacheValid(request, cacheConfig, existing)) {
        if (existing.cacheName != null) {
          _applyCacheToRequest(
            request,
            cacheName: existing.cacheName!,
            cacheContentsCount: existing.contentsCount,
          );
        }
        final CacheMetadata reused = existing.copyWith(
          invocationsUsed: (existing.invocationsUsed ?? 0) + 1,
        );
        request.cacheMetadata = reused;
        return reused;
      }

      if (existing.cacheName != null) {
        await cleanupCache(existing.cacheName!);
      }

      final String currentFingerprint = _generateCacheFingerprint(
        request,
        existing.contentsCount,
      );
      if (currentFingerprint == existing.fingerprint) {
        final CacheMetadata? recreated = await _createNewCacheWithContents(
          request: request,
          cacheConfig: cacheConfig,
          cacheContentsCount: existing.contentsCount,
        );
        if (recreated != null && recreated.cacheName != null) {
          _applyCacheToRequest(
            request,
            cacheName: recreated.cacheName!,
            cacheContentsCount: recreated.contentsCount,
          );
          request.cacheMetadata = recreated;
          return recreated;
        }
      }

      final int totalContentsCount = request.contents.length;
      final CacheMetadata fingerprintOnly = CacheMetadata(
        fingerprint: _generateCacheFingerprint(request, totalContentsCount),
        contentsCount: totalContentsCount,
      );
      request.cacheMetadata = fingerprintOnly;
      return fingerprintOnly;
    }

    final int totalContentsCount = request.contents.length;
    final CacheMetadata fingerprintOnly = CacheMetadata(
      fingerprint: _generateCacheFingerprint(request, totalContentsCount),
      contentsCount: totalContentsCount,
    );
    request.cacheMetadata = fingerprintOnly;
    return fingerprintOnly;
  }

  void populateCacheMetadataInResponse(
    LlmResponse response,
    CacheMetadata cacheMetadata,
  ) {
    response.cacheMetadata = cacheMetadata.copyWith();
  }

  CacheMetadata activateCache({
    required CacheMetadata fingerprintMetadata,
    required String cacheName,
    int ttlSeconds = 3600,
  }) {
    final double now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    return fingerprintMetadata.copyWith(
      cacheName: cacheName,
      expireTime: now + ttlSeconds,
      invocationsUsed: 0,
      createdAt: now,
    );
  }

  String fingerprintCacheableContents(LlmRequest request) {
    return _generateCacheFingerprint(request, request.contents.length);
  }

  Future<void> cleanupCache(String cacheName) async {
    if (cacheClient == null || cacheName.isEmpty) {
      return;
    }
    try {
      await cacheClient!.deleteCache(cacheName: cacheName);
    } catch (_) {
      // No-op by design: cache cleanup is best-effort.
    }
  }

  bool _isCacheValid(
    LlmRequest request,
    ContextCacheConfig cacheConfig,
    CacheMetadata cacheMetadata,
  ) {
    if (cacheMetadata.cacheName == null) {
      return false;
    }
    final double? expiresAt = cacheMetadata.expireTime;
    if (expiresAt != null &&
        DateTime.now().millisecondsSinceEpoch / 1000.0 >= expiresAt) {
      return false;
    }
    final int used = cacheMetadata.invocationsUsed ?? 0;
    if (used > cacheConfig.cacheIntervals) {
      return false;
    }

    final String currentFingerprint = _generateCacheFingerprint(
      request,
      cacheMetadata.contentsCount,
    );
    return currentFingerprint == cacheMetadata.fingerprint;
  }

  Future<CacheMetadata?> _createNewCacheWithContents({
    required LlmRequest request,
    required ContextCacheConfig cacheConfig,
    required int cacheContentsCount,
  }) async {
    if (cacheClient == null) {
      return null;
    }
    final int? previousTokenCount = request.cacheableContentsTokenCount;
    if (previousTokenCount == null ||
        previousTokenCount < cacheConfig.minTokens) {
      return null;
    }
    final String model = request.model ?? '';
    if (model.isEmpty) {
      return null;
    }
    try {
      final List<Content> cacheContents = request.contents
          .take(cacheContentsCount)
          .map((Content content) => content.copyWith())
          .toList();
      final GeminiCreatedCache created = await cacheClient!.createCache(
        model: model,
        contents: cacheContents,
        ttl: cacheConfig.ttlString,
        displayName:
            'adk-cache-${DateTime.now().millisecondsSinceEpoch}-$cacheContentsCount',
        systemInstruction: request.config.systemInstruction,
        tools: request.config.tools
            ?.map((ToolDeclaration tool) => tool.copyWith())
            .toList(),
        toolConfig: request.config.toolConfig?.copyWith(),
      );

      final double now = DateTime.now().millisecondsSinceEpoch / 1000.0;
      return CacheMetadata(
        cacheName: created.name,
        expireTime: now + cacheConfig.ttlSeconds,
        fingerprint: _generateCacheFingerprint(request, cacheContentsCount),
        invocationsUsed: 1,
        contentsCount: cacheContentsCount,
        createdAt: now,
      );
    } catch (_) {
      return null;
    }
  }

  void _applyCacheToRequest(
    LlmRequest request, {
    required String cacheName,
    required int cacheContentsCount,
  }) {
    request.config.systemInstruction = null;
    request.config.tools = null;
    request.config.toolConfig = null;
    request.config.cachedContent = cacheName;
    request.contents = request.contents.skip(cacheContentsCount).toList();
  }

  String _generateCacheFingerprint(LlmRequest request, int cacheContentsCount) {
    final int boundedCount = cacheContentsCount < 0
        ? 0
        : cacheContentsCount > request.contents.length
        ? request.contents.length
        : cacheContentsCount;

    final Map<String, Object?> payload = <String, Object?>{
      'systemInstruction': request.config.systemInstruction,
      'tools': _serializeTools(request.config.tools),
      'toolConfig': _serializeToolConfig(request.config.toolConfig),
      'contents': _serializeContents(request.contents),
    };
    if (boundedCount < request.contents.length) {
      payload['contents'] = _serializeContents(
        request.contents.take(boundedCount).toList(),
      );
    }
    final String serialized = jsonEncode(payload);
    return _fnv1a64Hex(serialized);
  }
}

ContextCacheConfig? _coerceContextCacheConfig(Object? value) {
  if (value is ContextCacheConfig) {
    return value;
  }
  if (value is Map) {
    return ContextCacheConfig.fromJson(
      value.map((Object? key, Object? item) => MapEntry('$key', item)),
    );
  }
  return null;
}

CacheMetadata? _coerceCacheMetadata(Object? value) {
  if (value is CacheMetadata) {
    return value;
  }
  if (value is! Map) {
    return null;
  }
  final Map<String, Object?> metadata = value.map(
    (Object? key, Object? item) => MapEntry('$key', item),
  );
  final Object? fingerprint = metadata['fingerprint'];
  final Object? contentsCountRaw =
      metadata['contents_count'] ?? metadata['contentsCount'];
  final int? contentsCount = _asInt(contentsCountRaw);
  if (fingerprint is! String || contentsCount == null) {
    return null;
  }
  final Object? cacheNameRaw = metadata['cache_name'] ?? metadata['cacheName'];
  return CacheMetadata(
    cacheName: cacheNameRaw is String ? cacheNameRaw : cacheNameRaw?.toString(),
    expireTime: _asDouble(metadata['expire_time'] ?? metadata['expireTime']),
    fingerprint: fingerprint,
    invocationsUsed: _asInt(
      metadata['invocations_used'] ?? metadata['invocationsUsed'],
    ),
    contentsCount: contentsCount,
    createdAt: _asDouble(metadata['created_at'] ?? metadata['createdAt']),
  );
}

List<Map<String, Object?>> _serializeTools(List<ToolDeclaration>? tools) {
  if (tools == null) {
    return const <Map<String, Object?>>[];
  }
  return tools
      .map((ToolDeclaration tool) {
        return <String, Object?>{
          'functionDeclarations': tool.functionDeclarations
              .map((FunctionDeclaration declaration) {
                return <String, Object?>{
                  'name': declaration.name,
                  'description': declaration.description,
                  'parameters': declaration.parameters,
                };
              })
              .toList(growable: false),
        };
      })
      .toList(growable: false);
}

Map<String, Object?>? _serializeToolConfig(LlmToolConfig? toolConfig) {
  if (toolConfig == null) {
    return null;
  }
  final FunctionCallingConfig? functionCallingConfig =
      toolConfig.functionCallingConfig;
  if (functionCallingConfig == null) {
    return <String, Object?>{};
  }
  return <String, Object?>{
    'functionCallingConfig': <String, Object?>{
      'mode': functionCallingConfig.mode.name,
      'allowedFunctionNames': functionCallingConfig.allowedFunctionNames,
    },
  };
}

List<Map<String, Object?>> _serializeContents(List<Content> contents) {
  return contents
      .map((Content content) {
        return <String, Object?>{
          'role': content.role,
          'parts': content.parts
              .where((Part part) => !part.thought)
              .map(
                (Part part) => <String, Object?>{
                  if (part.text != null) 'text': part.text,
                  if (part.functionCall != null)
                    'functionCall': <String, Object?>{
                      'name': part.functionCall!.name,
                      'args': part.functionCall!.args,
                    },
                  if (part.functionResponse != null)
                    'functionResponse': <String, Object?>{
                      'name': part.functionResponse!.name,
                      'response': part.functionResponse!.response,
                    },
                  if (part.inlineData != null)
                    'inlineData': <String, Object?>{
                      'mimeType': part.inlineData!.mimeType,
                      'displayName': part.inlineData!.displayName,
                    },
                  if (part.fileData != null)
                    'fileData': <String, Object?>{
                      'fileUri': part.fileData!.fileUri,
                      'mimeType': part.fileData!.mimeType,
                    },
                  if (part.executableCode != null)
                    'executableCode': '${part.executableCode}',
                  if (part.codeExecutionResult != null)
                    'codeExecutionResult': '${part.codeExecutionResult}',
                },
              )
              .toList(growable: false),
        };
      })
      .toList(growable: false);
}

int? _asInt(Object? value) {
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

double? _asDouble(Object? value) {
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

String _fnv1a64Hex(String input) {
  const int fnvPrime = 0x100000001b3;
  int hash = 0xcbf29ce484222325;
  for (final int byte in utf8.encode(input)) {
    hash ^= byte;
    hash = (hash * fnvPrime) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
