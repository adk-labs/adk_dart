/// Plugin that verifies tool calls match HMAC-signed session history.
library;

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../agents/base_agent.dart';
import '../agents/invocation_context.dart';
import '../events/event.dart';
import '../events/internal_metadata.dart';
import '../tools/base_tool.dart';
import '../tools/tool_context.dart';
import '../types/content.dart';
import 'base_plugin.dart';

/// Custom metadata key under which per-call HMAC stamps are stored on [Event].
const String hmacMetaKey = '${internalMetadataPrefix}fc_hmac';

/// Version prefix applied to all tool-call HMAC stamps.
const String stampPrefix = 'v1:';

/// Error raised when a tool call fails integrity verification.
///
/// Extends [StateError] and implements [Exception] so callers catching either
/// [StateError], [ArgumentError]-style errors, or [Exception] can handle it.
class ToolCallIntegrityError extends StateError implements Exception {
  /// Creates a tool-call integrity error with [message].
  ToolCallIntegrityError(super.message);

  @override
  String toString() => 'ToolCallIntegrityError: $message';
}

bool _isRestored(Event event) {
  final Map<String, dynamic>? meta = event.customMetadata;
  return meta != null && meta[restoredEventKey] == true;
}

Object? _validateAndSortJsonValue(Object? value) {
  if (value == null || value is bool || value is String || value is int) {
    return value;
  }
  if (value is double) {
    if (value.isNaN || value.isInfinite) {
      throw const FormatException('Out of range float values are not JSON compliant');
    }
    return value;
  }
  if (value is num) {
    final double asDouble = value.toDouble();
    if (asDouble.isNaN || asDouble.isInfinite) {
      throw const FormatException('Out of range float values are not JSON compliant');
    }
    return value;
  }
  if (value is List) {
    return value.map<Object?>(_validateAndSortJsonValue).toList(growable: false);
  }
  if (value is Map) {
    final List<String> keys = <String>[];
    final Map<String, Object?> stringKeyed = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final Object? rawKey = entry.key;
      if (rawKey is! String) {
        throw FormatException('JSON object keys must be strings, got ${rawKey.runtimeType}');
      }
      keys.add(rawKey);
      stringKeyed[rawKey] = _validateAndSortJsonValue(entry.value);
    }
    keys.sort();
    return <String, Object?>{
      for (final String key in keys) key: stringKeyed[key],
    };
  }
  throw FormatException('Object of type ${value.runtimeType} is not JSON serializable');
}

String _canonicalJson(Object? payload) {
  final Object? normalized = _validateAndSortJsonValue(payload);
  return jsonEncode(normalized);
}

Map<String, Object?> _jsonArgs(FunctionCall fc) {
  final Map<String, dynamic> argsMap = fc.args;
  try {
    final Object? decoded = jsonDecode(_canonicalJson(argsMap));
    if (decoded is! Map) {
      throw ToolCallIntegrityError(
        "Function call '${fc.name}' (id=${fc.id}) has non-dict args after JSON round-trip.",
      );
    }
    return decoded.map<String, Object?>(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
  } catch (error) {
    if (error is ToolCallIntegrityError) {
      rethrow;
    }
    throw ToolCallIntegrityError(
      "Function call '${fc.name}' (id=${fc.id}) has non-JSON-serializable args.",
    );
  }
}

Uint8List _fcPayload(FunctionCall fc) {
  if (fc.name.isEmpty) {
    throw ToolCallIntegrityError(
      'Function call (id=${fc.id}) is missing a name.',
    );
  }
  final Map<String, Object?> canonicalMap = <String, Object?>{
    'args': _jsonArgs(fc),
    'id': fc.id,
    'name': fc.name,
  };
  return Uint8List.fromList(utf8.encode(_canonicalJson(canonicalMap)));
}

String _computeStamp(Uint8List key, Uint8List payload) {
  final Hmac hmac = Hmac(sha256, key);
  final Digest digest = hmac.convert(payload);
  return '$stampPrefix$digest';
}

bool _constantTimeEquals(String a, String b) {
  final List<int> aBytes = utf8.encode(a);
  final List<int> bBytes = utf8.encode(b);
  if (aBytes.length != bBytes.length) {
    return false;
  }
  int diff = 0;
  for (int i = 0; i < aBytes.length; i++) {
    diff |= aBytes[i] ^ bBytes[i];
  }
  return diff == 0;
}

List<Uint8List> _normalizeSecretKeys(Object secretKey) {
  if (secretKey is Uint8List) {
    if (secretKey.isEmpty) {
      throw ArgumentError('secret_key must be non-empty bytes.');
    }
    return <Uint8List>[Uint8List.fromList(secretKey)];
  }
  if (secretKey is String) {
    final Uint8List encoded = Uint8List.fromList(utf8.encode(secretKey));
    if (encoded.isEmpty) {
      throw ArgumentError('secret_key must be non-empty bytes.');
    }
    return <Uint8List>[encoded];
  }
  if (secretKey is List<int>) {
    if (secretKey.isEmpty) {
      throw ArgumentError('secret_key must be non-empty bytes.');
    }
    return <Uint8List>[Uint8List.fromList(secretKey)];
  }
  if (secretKey is Iterable) {
    final List<Object?> items = secretKey.toList(growable: false);
    if (items.isEmpty) {
      throw ArgumentError(
        'secret_key must be non-empty bytes or a non-empty sequence of non-empty bytes.',
      );
    }
    if (items.every((Object? item) => item is int)) {
      return <Uint8List>[
        Uint8List.fromList(items.cast<int>()),
      ];
    }
    final List<Uint8List> keys = <Uint8List>[];
    for (final Object? item in items) {
      if (item is Uint8List) {
        if (item.isEmpty) {
          throw ArgumentError(
            'secret_key must be non-empty bytes or a non-empty sequence of non-empty bytes.',
          );
        }
        keys.add(Uint8List.fromList(item));
      } else if (item is List<int>) {
        if (item.isEmpty) {
          throw ArgumentError(
            'secret_key must be non-empty bytes or a non-empty sequence of non-empty bytes.',
          );
        }
        keys.add(Uint8List.fromList(item));
      } else if (item is String) {
        final Uint8List encoded = Uint8List.fromList(utf8.encode(item));
        if (encoded.isEmpty) {
          throw ArgumentError(
            'secret_key must be non-empty bytes or a non-empty sequence of non-empty bytes.',
          );
        }
        keys.add(encoded);
      } else {
        throw ArgumentError(
          'secret_key must be non-empty bytes or a non-empty sequence of non-empty bytes.',
        );
      }
    }
    return keys;
  }
  throw ArgumentError(
    'secret_key must be non-empty bytes or a non-empty sequence of non-empty bytes.',
  );
}

/// Plugin that stamps model function calls with an HMAC and verifies them
/// before session execution and before tool invocation.
///
/// ```dart
/// final plugin = ToolCallIntegrityPlugin(
///   utf8.encode('my-32-byte-secret-key-for-hmac!!'),
/// );
/// ```
class ToolCallIntegrityPlugin extends BasePlugin {
  /// Creates a tool-call integrity plugin with [secretKey].
  ///
  /// [secretKey] may be a non-empty `Uint8List`/`List<int>`/`String`, or an
  /// `Iterable` of keys for key rotation (the first key stamps new events; all
  /// keys are accepted during verification).
  ToolCallIntegrityPlugin(
    Object secretKey, {
    this.allowUnstampedCalls = false,
    super.name = 'tool_call_integrity',
  }) : _keys = List<Uint8List>.unmodifiable(_normalizeSecretKeys(secretKey));

  final List<Uint8List> _keys;

  /// Whether unstamped calls are permitted with a warning instead of throwing.
  final bool allowUnstampedCalls;

  Uint8List get _primaryKey => _keys.first;

  /// Returns a shallow copy of [event] marked as restored from external history.
  ///
  /// Restored events are skipped during [beforeRunCallback] verification and
  /// cannot be executed as pending tool calls in [beforeToolCallback].
  static Event prepareRestoredEvent(Event event) {
    final Event copy = event.copyWith(
      customMetadata: event.customMetadata == null
          ? null
          : Map<String, dynamic>.from(event.customMetadata!),
    );
    return markRestored(copy);
  }

  bool _verifyFc(FunctionCall fc, String stamp) {
    if (!stamp.startsWith(stampPrefix)) {
      return false;
    }
    final Uint8List payload = _fcPayload(fc);
    for (final Uint8List key in _keys) {
      if (_constantTimeEquals(stamp, _computeStamp(key, payload))) {
        return true;
      }
    }
    return false;
  }

  void _unstamped(String name, String? callId) {
    final String msg =
        "Tool call '$name' (id=$callId) has no integrity stamp.";
    if (allowUnstampedCalls) {
      developer.log(
        '$msg Proceeding because allow_unstamped_calls=True.',
        name: 'adk_dart.tool_call_integrity_plugin',
      );
      return;
    }
    throw ToolCallIntegrityError(msg);
  }

  @override
  Future<Event?> onEventCallback({
    required InvocationContext invocationContext,
    required Event event,
  }) async {
    final List<FunctionCall> calls = event.getFunctionCalls();
    if (calls.isEmpty) {
      return null;
    }

    final Map<String, String> stamps = <String, String>{};
    final Set<String> seenIds = <String>{};
    for (final FunctionCall fc in calls) {
      final String? callId = fc.id;
      if (callId == null || callId.isEmpty) {
        continue;
      }
      if (event.partial != true) {
        if (seenIds.contains(callId)) {
          throw ToolCallIntegrityError(
            'Event contains duplicate function call id $callId.',
          );
        }
        seenIds.add(callId);
      }
      stamps[callId] = _computeStamp(_primaryKey, _fcPayload(fc));
    }

    if (stamps.isEmpty) {
      return null;
    }

    final Map<String, dynamic> meta = event.customMetadata == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(event.customMetadata!);
    final Object? existing = meta[hmacMetaKey];
    final Map<String, String> mergedStamps = <String, String>{};
    if (existing is Map) {
      existing.forEach((Object? key, Object? value) {
        if (key is String && value is String) {
          mergedStamps[key] = value;
        }
      });
    }
    mergedStamps.addAll(stamps);
    meta[hmacMetaKey] = mergedStamps;
    event.customMetadata = meta;
    return event;
  }

  @override
  Future<Content?> beforeRunCallback({
    required InvocationContext invocationContext,
  }) async {
    for (final Event event in invocationContext.session.events) {
      final List<FunctionCall> calls = event.getFunctionCalls();
      if (calls.isEmpty || _isRestored(event)) {
        continue;
      }

      final Object? stamps = event.customMetadata?[hmacMetaKey];
      if (stamps != null &&
          (stamps is! Map ||
              !stamps.keys.every((Object? k) => k is String) ||
              !stamps.values.every((Object? v) => v is String))) {
        throw ToolCallIntegrityError(
          'Session contains malformed tool call integrity metadata.',
        );
      }
      final Map<String, String>? stampMap = stamps is Map
          ? stamps.map<String, String>(
              (Object? k, Object? v) => MapEntry(k as String, v as String),
            )
          : null;

      final Set<String> seenInEvent = <String>{};
      for (final FunctionCall fc in calls) {
        final String? callId = fc.id;
        if (callId == null || callId.isEmpty) {
          if (!allowUnstampedCalls) {
            throw ToolCallIntegrityError(
              "Session contains tool call '${fc.name}' without an id.",
            );
          }
          continue;
        }
        if (seenInEvent.contains(callId)) {
          throw ToolCallIntegrityError(
            'Session event contains duplicate function call id $callId.',
          );
        }
        seenInEvent.add(callId);

        final String? stamp = stampMap?[callId];
        if (stamp == null) {
          _unstamped(fc.name, callId);
        } else if (!_verifyFc(fc, stamp)) {
          throw ToolCallIntegrityError(
            "Integrity check failed for session tool call '${fc.name}' (id=$callId).",
          );
        }
      }

      if (stampMap != null) {
        final Set<String> unmatched = stampMap.keys.toSet().difference(
          seenInEvent,
        );
        if (unmatched.isNotEmpty) {
          throw ToolCallIntegrityError(
            'Session contains unmatched tool call integrity metadata.',
          );
        }
      }
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> beforeToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
  }) async {
    final InvocationContext invCtx = toolContext.invocationContext;
    final BaseAgent? currentNode = invCtx.agent.rootAgent.findAgent(
      toolContext.agentName,
    );
    if (currentNode != null && currentNode.runtimeType.toString() == 'ToolNode') {
      return null;
    }

    final String? callId = toolContext.functionCallId;
    if (callId == null || callId.isEmpty) {
      throw ToolCallIntegrityError(
        "Tool '${tool.name}' invoked without a function_call_id; cannot verify tool call integrity.",
      );
    }

    final List<(Event, FunctionCall)> matches = <(Event, FunctionCall)>[];
    bool restored = false;
    for (final Event event in invCtx.session.events) {
      for (final FunctionCall fc in event.getFunctionCalls()) {
        if (fc.id == callId) {
          if (_isRestored(event)) {
            restored = true;
            continue;
          }
          matches.add((event, fc));
        }
      }
    }

    if (matches.isEmpty) {
      if (restored) {
        throw ToolCallIntegrityError(
          "Tool call '${tool.name}' (id=$callId) comes from restored history and cannot be executed.",
        );
      }
      _unstamped(tool.name, callId);
      return null;
    }

    final String executed;
    try {
      executed = _canonicalJson(jsonDecode(_canonicalJson(toolArgs)));
    } catch (_) {
      throw ToolCallIntegrityError(
        "Tool '${tool.name}' (id=$callId) received non-JSON-serializable tool_args.",
      );
    }

    for (final (Event event, FunctionCall fc) in matches) {
      final Object? stamps = event.customMetadata?[hmacMetaKey];
      if (stamps != null &&
          (stamps is! Map ||
              !stamps.keys.every((Object? k) => k is String) ||
              !stamps.values.every((Object? v) => v is String))) {
        throw ToolCallIntegrityError(
          'Session contains malformed tool call integrity metadata.',
        );
      }
      final Map<String, String>? stampMap = stamps is Map
          ? stamps.map<String, String>(
              (Object? k, Object? v) => MapEntry(k as String, v as String),
            )
          : null;
      final String? stamp = stampMap?[callId];
      if (stamp == null) {
        _unstamped(tool.name, callId);
      } else if (!_verifyFc(fc, stamp)) {
        throw ToolCallIntegrityError(
          "HMAC mismatch for tool call '${tool.name}' (id=$callId): session history may have been tampered with.",
        );
      }

      if (fc.name != tool.name || _canonicalJson(_jsonArgs(fc)) != executed) {
        throw ToolCallIntegrityError(
          "Tool call '${tool.name}' (id=$callId) does not match recorded call '${fc.name}'.",
        );
      }
    }

    return null;
  }
}
