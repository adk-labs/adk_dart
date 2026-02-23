import 'dart:convert';

import '../types/content.dart';
import 'cache_metadata.dart';
import 'llm_request.dart';
import 'llm_response.dart';

class GeminiContextCacheManager {
  const GeminiContextCacheManager();

  Future<CacheMetadata?> handleContextCaching(LlmRequest request) async {
    if (request.cacheConfig == null) {
      return null;
    }

    final String fingerprint = fingerprintCacheableContents(request);
    final int contentsCount = request.contents.length;
    final Object? rawMetadata = request.cacheMetadata;
    if (rawMetadata is CacheMetadata &&
        rawMetadata.fingerprint == fingerprint &&
        rawMetadata.cacheName != null &&
        !rawMetadata.expireSoon) {
      final CacheMetadata reused = rawMetadata.copyWith(
        invocationsUsed: (rawMetadata.invocationsUsed ?? 0) + 1,
        contentsCount: contentsCount,
      );
      request.cacheMetadata = reused;
      return reused;
    }

    final CacheMetadata fingerprintOnly = CacheMetadata(
      fingerprint: fingerprint,
      contentsCount: contentsCount,
    );
    request.cacheMetadata = fingerprintOnly;
    return fingerprintOnly;
  }

  void populateCacheMetadataInResponse(
    LlmResponse response,
    CacheMetadata cacheMetadata,
  ) {
    response.cacheMetadata = cacheMetadata;
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
    final Map<String, Object?> payload = <String, Object?>{
      'systemInstruction': request.config.systemInstruction,
      'tools': _serializeTools(request.config.tools),
      'contents': _serializeContents(request.contents),
    };
    final String serialized = jsonEncode(payload);
    return _fnv1a64Hex(serialized);
  }
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

String _fnv1a64Hex(String input) {
  const int fnvPrime = 0x100000001b3;
  int hash = 0xcbf29ce484222325;
  for (final int byte in utf8.encode(input)) {
    hash ^= byte;
    hash = (hash * fnvPrime) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
