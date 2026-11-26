/// Vertex AI Agent Engine telemetry context propagation and span helpers.
library;

import 'dart:io';

import 'setup.dart';
import 'sqlite_span_exporter.dart';

/// Header set by Agent Engine carrying the caller's original `traceparent`.
const String googleAeTraceparentHeader = 'Google-Agent-Engine-Traceparent';

/// Baggage key storing the active parent `traceparent` string.
const String traceparentBaggageKey = 'traceparent';

/// Standard W3C `traceparent` header name.
const String googleTraceparentHeader = 'traceparent';

/// Baggage key storing the inbound `traceparent` header for `supportID`.
const String googleTraceparentBaggageKey = 'google_traceparent';

/// Span attribute key recording Agent Engine's internal `traceparent`.
const String googleTraceparentSupportAttributeKey = 'supportID';

/// Environment variable set when running inside Vertex AI Agent Engine.
const String googleCloudAgentEngineIdEnvVar = 'GOOGLE_CLOUD_AGENT_ENGINE_ID';

/// Environment variable enabling Agent Engine telemetry user-agent headers.
const String googleCloudAgentEngineEnableTelemetryEnvVar =
    'GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY';

/// Default W3C `traceparent` version handled as 4-part context.
const String _w3cTraceparentVersion00 = '00';

/// Invalid W3C `traceparent` version reserved by specification.
const String _w3cTraceparentVersionInvalid = 'ff';

final RegExp _traceparentPattern = RegExp(
  r'^[ \t]*([0-9a-f]{2})-([0-9a-f]{32})-([0-9a-f]{16})-([0-9a-f]{2})(?:[ \t]*|-.+)$',
);

/// Parsed W3C traceparent and tracestate context extracted from headers.
class PropagatedTraceContext {
  /// Creates a propagated trace context.
  const PropagatedTraceContext({
    required this.traceIdHex,
    required this.spanIdHex,
    required this.traceFlags,
    this.isRemote = true,
    this.traceState = const TraceState(),
  });

  /// 32-character lowercase hexadecimal trace ID.
  final String traceIdHex;

  /// 16-character lowercase hexadecimal parent span ID.
  final String spanIdHex;

  /// W3C trace flags byte (bit `0x01` indicates sampled).
  final TraceFlags traceFlags;

  /// Whether this context originated from a remote carrier.
  final bool isRemote;

  /// Parsed W3C `tracestate` entries.
  final TraceState traceState;

  /// Full 128-bit unsigned trace ID.
  BigInt get traceIdValue => BigInt.parse(traceIdHex, radix: 16);

  /// Full 64-bit unsigned span ID.
  BigInt get spanIdValue => BigInt.parse(spanIdHex, radix: 16);

  /// Whether both [traceIdHex] and [spanIdHex] are non-zero.
  bool get isValid =>
      traceIdValue != BigInt.zero && spanIdValue != BigInt.zero;

  /// Whether the sampled trace flag (`0x01`) is set.
  bool get isSampled => (traceFlags.value & 0x01) != 0;

  /// Parses a W3C `traceparent` header and optional `tracestate` header.
  ///
  /// Returns `null` if the header fails W3C Trace Context validation.
  static PropagatedTraceContext? parse(
    String traceparent, {
    String? tracestate,
  }) {
    final RegExpMatch? match = _traceparentPattern.firstMatch(traceparent);
    if (match == null) {
      return null;
    }

    final String version = match.group(1)!;
    final String traceIdHex = match.group(2)!;
    final String spanIdHex = match.group(3)!;
    final String flagsHex = match.group(4)!;

    if (version == _w3cTraceparentVersionInvalid) {
      return null;
    }

    // Version 00 forbids extra trailing subfields after trace-flags.
    if (version == _w3cTraceparentVersion00) {
      final String remainder = traceparent.substring(
        match.group(1)!.length +
            1 +
            match.group(2)!.length +
            1 +
            match.group(3)!.length +
            1 +
            match.group(4)!.length +
            (traceparent.length - traceparent.trimLeft().length),
      );
      if (remainder.trim().isNotEmpty) {
        return null;
      }
    }

    final BigInt? traceId = BigInt.tryParse(traceIdHex, radix: 16);
    final BigInt? spanId = BigInt.tryParse(spanIdHex, radix: 16);
    final int? flags = int.tryParse(flagsHex, radix: 16);
    if (traceId == null ||
        traceId == BigInt.zero ||
        spanId == null ||
        spanId == BigInt.zero ||
        flags == null) {
      return null;
    }

    return PropagatedTraceContext(
      traceIdHex: traceIdHex,
      spanIdHex: spanIdHex,
      traceFlags: TraceFlags(flags),
      isRemote: true,
      traceState: _parseTraceState(tracestate),
    );
  }
}

TraceState _parseTraceState(String? headerValue) {
  if (headerValue == null || headerValue.trim().isEmpty) {
    return const TraceState();
  }
  final Map<String, String> entries = <String, String>{};
  for (final String member in headerValue.split(',')) {
    final String trimmed = member.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final int eqIndex = trimmed.indexOf('=');
    if (eqIndex <= 0) {
      continue;
    }
    final String key = trimmed.substring(0, eqIndex).trim();
    final String value = trimmed.substring(eqIndex + 1).trim();
    if (key.isEmpty) {
      continue;
    }
    entries[key] = value;
  }
  return TraceState(Map<String, String>.unmodifiable(entries));
}

Map<String, String> _parseW3CBaggage(String? headerValue) {
  if (headerValue == null || headerValue.trim().isEmpty) {
    return const <String, String>{};
  }
  final Map<String, String> entries = <String, String>{};
  for (final String rawMember in headerValue.split(',')) {
    final String member = rawMember.trim();
    if (member.isEmpty) {
      continue;
    }
    final int semicolonIndex = member.indexOf(';');
    final String keyValuePart = semicolonIndex >= 0
        ? member.substring(0, semicolonIndex)
        : member;
    final int eqIndex = keyValuePart.indexOf('=');
    if (eqIndex <= 0) {
      continue;
    }
    final String rawKey = keyValuePart.substring(0, eqIndex).trim();
    final String rawValue = keyValuePart.substring(eqIndex + 1).trim();
    if (rawKey.isEmpty) {
      continue;
    }
    final String key = _decodeBaggageComponent(rawKey);
    final String value = _decodeBaggageComponent(rawValue);
    if (key.isNotEmpty) {
      entries[key] = value;
    }
  }
  return entries;
}

String _decodeBaggageComponent(String value) {
  try {
    return Uri.decodeComponent(value);
  } on ArgumentError {
    return value;
  }
}

String? _findHeader(Map<String, String> headers, String name) {
  if (headers.containsKey(name)) {
    return headers[name];
  }
  final String lower = name.toLowerCase();
  for (final MapEntry<String, String> entry in headers.entries) {
    if (entry.key.toLowerCase() == lower) {
      return entry.value;
    }
  }
  return null;
}

bool _hasHeader(Map<String, String> headers, String name) {
  if (headers.containsKey(name)) {
    return true;
  }
  final String lower = name.toLowerCase();
  for (final String key in headers.keys) {
    if (key.toLowerCase() == lower) {
      return true;
    }
  }
  return false;
}

/// Immutable OpenTelemetry-style propagation context holding W3C baggage and
/// an optional parent [spanContext].
class AgentEngineTelemetryContext {
  /// Creates a telemetry propagation context.
  AgentEngineTelemetryContext({
    Map<String, String>? baggage,
    this.spanContext,
  }) : baggage = Map<String, String>.unmodifiable(
         baggage ?? const <String, String>{},
       );

  /// Empty propagation context.
  factory AgentEngineTelemetryContext.empty() => AgentEngineTelemetryContext();

  /// W3C baggage entries.
  final Map<String, String> baggage;

  /// Extracted or active span context, if any.
  final PropagatedTraceContext? spanContext;

  /// Whether [spanContext] carries a valid non-zero trace and span ID.
  bool get hasValidSpanContext => spanContext?.isValid ?? false;

  /// Returns a copy with [key] set to [value] in [baggage].
  AgentEngineTelemetryContext setBaggage(String key, String value) {
    final Map<String, String> updated = Map<String, String>.from(baggage)
      ..[key] = value;
    return AgentEngineTelemetryContext(
      baggage: updated,
      spanContext: spanContext,
    );
  }

  /// Returns a copy with [key] removed from [baggage].
  AgentEngineTelemetryContext removeBaggage(String key) {
    if (!baggage.containsKey(key)) {
      return this;
    }
    final Map<String, String> updated = Map<String, String>.from(baggage)
      ..remove(key);
    return AgentEngineTelemetryContext(
      baggage: updated,
      spanContext: spanContext,
    );
  }

  /// Returns the baggage value for [key], or `null` if absent.
  String? getBaggage(String key) => baggage[key];

  /// Returns a copy with [spanContext] replaced.
  AgentEngineTelemetryContext withSpanContext(
    PropagatedTraceContext? nextSpanContext,
  ) {
    return AgentEngineTelemetryContext(
      baggage: baggage,
      spanContext: nextSpanContext,
    );
  }
}

/// Extracts propagated W3C `baggage`, `traceparent`, `tracestate`, and
/// `Google-Agent-Engine-Traceparent` context from HTTP request [headers].
///
/// Mirrors Python `google.adk.telemetry._agent_engine.get_propagated_context`:
/// - Extracts W3C `baggage` headers and strips caller-supplied
///   `google_traceparent` and `traceparent` baggage keys (both from inbound
///   `baggage` headers and from [baseContext]).
/// - Records inbound `traceparent` header in `google_traceparent` baggage so
///   [TopSpanProcessor] can attach it as `supportID`.
/// - Prefers `Google-Agent-Engine-Traceparent` when present and valid.
/// - Otherwise, when `GOOGLE_CLOUD_AGENT_ENGINE_ID` is unset and [baseContext]
///   does not already carry a valid active span context, extracts standard
///   `traceparent` and `tracestate` headers.
AgentEngineTelemetryContext getPropagatedContext(
  Map<String, String> headers, {
  AgentEngineTelemetryContext? baseContext,
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? Platform.environment;
  AgentEngineTelemetryContext ctx =
      baseContext ?? AgentEngineTelemetryContext.empty();

  final String? baggageHeader = _findHeader(headers, 'baggage');
  if (baggageHeader != null) {
    final Map<String, String> extractedBaggage = _parseW3CBaggage(
      baggageHeader,
    );
    if (extractedBaggage.isNotEmpty) {
      final Map<String, String> merged = Map<String, String>.from(ctx.baggage)
        ..addAll(extractedBaggage);
      ctx = AgentEngineTelemetryContext(
        baggage: merged,
        spanContext: ctx.spanContext,
      );
    }
  }

  // Only the headers handled below may set these keys. Upstream
  // instrumentation may already have copied caller baggage into ctx.
  for (final String reservedKey in const <String>[
    googleTraceparentBaggageKey,
    traceparentBaggageKey,
  ]) {
    ctx = ctx.removeBaggage(reservedKey);
  }

  if (_hasHeader(headers, googleTraceparentHeader)) {
    final String originalTraceparent =
        _findHeader(headers, googleTraceparentHeader) ?? '';
    ctx = ctx.setBaggage(googleTraceparentBaggageKey, originalTraceparent);
  }

  if (_hasHeader(headers, googleAeTraceparentHeader)) {
    final String aeTraceparent =
        _findHeader(headers, googleAeTraceparentHeader) ?? '';
    final PropagatedTraceContext? extracted = PropagatedTraceContext.parse(
      aeTraceparent,
    );
    if (extracted != null) {
      ctx = ctx
          .withSpanContext(extracted)
          .setBaggage(traceparentBaggageKey, aeTraceparent);
    }
  } else if (_hasHeader(headers, googleTraceparentHeader) &&
      (env[googleCloudAgentEngineIdEnvVar] ?? '').isEmpty &&
      !ctx.hasValidSpanContext) {
    final String originalTraceparent =
        _findHeader(headers, googleTraceparentHeader) ?? '';
    final String? tracestate = _findHeader(headers, 'tracestate');
    final PropagatedTraceContext? extracted = PropagatedTraceContext.parse(
      originalTraceparent,
      tracestate: tracestate,
    );
    if (extracted != null) {
      ctx = ctx
          .withSpanContext(extracted)
          .setBaggage(traceparentBaggageKey, originalTraceparent);
    }
  }

  return ctx;
}

/// Span representation used by [TopSpanProcessor] to evaluate parent context
/// and record the `supportID` attribute.
class AgentEngineSpan {
  /// Creates an [AgentEngineSpan].
  AgentEngineSpan({
    required this.name,
    required this.context,
    this.parent,
    Map<String, Object?>? attributes,
  }) : attributes = attributes ?? <String, Object?>{};

  /// Span name.
  final String name;

  /// This span's own context.
  final PropagatedTraceContext context;

  /// Parent span context, or `null` for a root span.
  final PropagatedTraceContext? parent;

  /// Mutable span attributes.
  final Map<String, Object?> attributes;

  /// Sets [key] to [value] in [attributes].
  void setAttribute(String key, Object? value) {
    attributes[key] = value;
  }
}

/// Span processor that attaches Agent Engine's `supportID` attribute to the
/// top-most span of a request.
class TopSpanProcessor implements SpanProcessor {
  /// Creates a [TopSpanProcessor].
  const TopSpanProcessor();

  @override
  String get kind => 'top_span_processor';

  @override
  Object get exporter => this;

  /// Called when [span] starts under [parentContext].
  void onStart(
    AgentEngineSpan span, {
    AgentEngineTelemetryContext? parentContext,
  }) {
    final Map<String, String> baggageItems =
        parentContext?.baggage ?? const <String, String>{};
    final String? baggageTraceHeader =
        baggageItems[googleTraceparentBaggageKey];
    if (isTopSpan(span, baggageItems) && baggageTraceHeader != null) {
      span.setAttribute(
        googleTraceparentSupportAttributeKey,
        baggageTraceHeader,
      );
    }
  }

  /// Called when [span] ends.
  void onEnd(AgentEngineSpan span) {}

  /// Shuts down the processor.
  void shutdown() {}

  /// Flushes buffered state.
  bool forceFlush({int timeoutMillis = 30000}) => true;

  /// Returns `true` if [span] is the top span in the trace.
  ///
  /// A top span either has no parent (or a zero parent span ID), or its parent
  /// span ID matches the span ID encoded in the `traceparent` baggage key.
  bool isTopSpan(AgentEngineSpan span, Map<String, String> baggageItems) {
    final PropagatedTraceContext? parent = span.parent;
    if (parent == null || parent.spanIdValue == BigInt.zero) {
      return true;
    }
    final String? traceparent = baggageItems[traceparentBaggageKey];
    if (traceparent == null) {
      return false;
    }
    final List<String> parts = traceparent.split('-');
    if (parts.length < 3) {
      return false;
    }
    final BigInt? parentSpanId = BigInt.tryParse(parts[2], radix: 16);
    if (parentSpanId == null) {
      return false;
    }
    return parent.spanIdValue == parentSpanId;
  }
}

/// Returns the Vertex Agent Engine `User-Agent` header map when telemetry is
/// enabled via `GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY`, or `null`.
Map<String, String>? telemetryUserAgentHeaders({
  Map<String, String>? environment,
  String agentPlatformVersion = '0.1.0',
  String? otlpExporterVersion,
}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final String? enabled = env[googleCloudAgentEngineEnableTelemetryEnvVar];
  if (enabled == null || enabled.isEmpty) {
    return null;
  }
  String userAgent = 'Vertex-Agent-Engine/$agentPlatformVersion';
  if (otlpExporterVersion != null && otlpExporterVersion.isNotEmpty) {
    userAgent += ' OTel-OTLP-Exporter-Dart/$otlpExporterVersion';
  }
  return <String, String>{'User-Agent': userAgent};
}
