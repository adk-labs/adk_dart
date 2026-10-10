/// ElevenLabs speech-to-text ([ElevenLabsSTT]) and text-to-speech
/// ([ElevenLabsTTS]) transforms for [CascadeLive].
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import '../../features/_feature_decorator.dart';
import '../../features/_feature_registry.dart';
import '../../live/cascade_live_events.dart';
import '../../live/transforms.dart';
import '../../types/content.dart';

/// Environment variable read when no explicit API key is passed.
const String elevenLabsApiKeyEnv = 'ELEVENLABS_API_KEY';

/// Default ElevenLabs voice ID ("George").
const String defaultElevenLabsVoiceId = 'JBFqnCBsd6RMkjVDRZzb';

/// Maximum characters buffered before forcing a sentence split in [ElevenLabsTTS].
const int maxElevenLabsSentenceChars = 240;

/// Supported PCM sample rates (in Hz) for [ElevenLabsSTT].
const Set<int> supportedElevenLabsSttSampleRates = <int>{
  8000,
  16000,
  22050,
  24000,
  44100,
  48000,
};

/// Supported PCM sample rates (in Hz) for [ElevenLabsTTS].
const Set<int> supportedElevenLabsTtsSampleRates = <int>{
  8000,
  16000,
  22050,
  24000,
  32000,
  44100,
  48000,
};

/// Event names emitted by an [ElevenLabsRealtimeSttConnection].
abstract final class ElevenLabsRealtimeEvents {
  /// Session started event.
  static const String sessionStarted = 'session_started';

  /// Interim transcript event.
  static const String partialTranscript = 'partial_transcript';

  /// Finalized transcript event (without timestamps).
  static const String committedTranscript = 'committed_transcript';

  /// Finalized transcript event with word timestamps.
  static const String committedTranscriptWithTimestamps =
      'committed_transcript_with_timestamps';

  /// General error event.
  static const String error = 'error';

  /// Authentication error event.
  static const String authError = 'auth_error';

  /// Quota exceeded error event.
  static const String quotaExceeded = 'quota_exceeded';

  /// Benign commit-throttled warning event.
  static const String commitThrottled = 'commit_throttled';

  /// Transcriber failure event.
  static const String transcriberError = 'transcriber_error';

  /// Unaccepted terms error event.
  static const String unacceptedTerms = 'unaccepted_terms';

  /// Rate limited error event.
  static const String rateLimited = 'rate_limited';

  /// Invalid input error event.
  static const String inputError = 'input_error';

  /// Queue overflow error event.
  static const String queueOverflow = 'queue_overflow';

  /// Resource exhausted error event.
  static const String resourceExhausted = 'resource_exhausted';

  /// Session time limit exceeded error event.
  static const String sessionTimeLimitExceeded = 'session_time_limit_exceeded';

  /// Chunk size exceeded error event.
  static const String chunkSizeExceeded = 'chunk_size_exceeded';

  /// Benign insufficient audio activity warning event.
  static const String insufficientAudioActivity = 'insufficient_audio_activity';

  /// Connection closed event.
  static const String close = 'close';
}

const List<String> _fatalSttEvents = <String>[
  ElevenLabsRealtimeEvents.error,
  ElevenLabsRealtimeEvents.authError,
  ElevenLabsRealtimeEvents.quotaExceeded,
  ElevenLabsRealtimeEvents.transcriberError,
  ElevenLabsRealtimeEvents.unacceptedTerms,
  ElevenLabsRealtimeEvents.rateLimited,
  ElevenLabsRealtimeEvents.inputError,
  ElevenLabsRealtimeEvents.queueOverflow,
  ElevenLabsRealtimeEvents.resourceExhausted,
  ElevenLabsRealtimeEvents.sessionTimeLimitExceeded,
  ElevenLabsRealtimeEvents.chunkSizeExceeded,
];

const List<String> _benignSttEvents = <String>[
  ElevenLabsRealtimeEvents.commitThrottled,
  ElevenLabsRealtimeEvents.insufficientAudioActivity,
];

/// Resolves an ElevenLabs API key from [apiKey] or [elevenLabsApiKeyEnv].
///
/// Throws an [ArgumentError] if no key is provided or found in the environment.
String resolveElevenLabsApiKey(
  String? apiKey, {
  Map<String, String>? environment,
}) {
  if (apiKey != null && apiKey.isNotEmpty) {
    return apiKey;
  }
  final Map<String, String> env = environment ?? Platform.environment;
  final String? fromEnv = env[elevenLabsApiKeyEnv];
  if (fromEnv != null && fromEnv.isNotEmpty) {
    return fromEnv;
  }
  throw ArgumentError(
    'ElevenLabs API key not found. Pass apiKey=... or set the '
    '$elevenLabsApiKeyEnv environment variable.',
  );
}

/// Active realtime speech-to-text WebSocket session with ElevenLabs.
///
/// ```dart
/// connection.on(ElevenLabsRealtimeEvents.partialTranscript, (data) {
///   print(data['text']);
/// });
/// ```
abstract class ElevenLabsRealtimeSttConnection {
  /// Creates an [ElevenLabsRealtimeSttConnection].
  const ElevenLabsRealtimeSttConnection();

  /// Registers an event [handler] for [eventName].
  void on(
    String eventName,
    void Function(Map<String, Object?> data) handler,
  );

  /// Sends an audio chunk [payload] (`audio_base_64`, `sample_rate`).
  Future<void> send(Map<String, Object?> payload);

  /// Commits the current audio buffer to force transcript finalization.
  Future<void> commit();

  /// Closes the underlying realtime connection.
  Future<void> close();
}

/// Transport client interface for ElevenLabs STT and TTS APIs.
///
/// ```dart
/// final client = getElevenLabsClient(apiKey: 'my-api-key');
/// ```
abstract class ElevenLabsSpeechClient {
  /// Creates an [ElevenLabsSpeechClient].
  const ElevenLabsSpeechClient();

  /// Connects to the ElevenLabs realtime speech-to-text endpoint with [options].
  Future<ElevenLabsRealtimeSttConnection> connectRealtimeStt(
    Map<String, Object?> options,
  );

  /// Streams synthesized audio bytes for [text] using [voiceId].
  Stream<List<int>> convertTextToSpeech({
    required String voiceId,
    required String text,
    required String modelId,
    required String outputFormat,
    String? languageCode,
    String? previousText,
    Map<String, Object?>? voiceSettings,
    Map<String, Object?>? requestOptions,
  });
}

/// Default HTTP and WebSocket implementation of [ElevenLabsSpeechClient].
///
/// ```dart
/// final client = DefaultElevenLabsSpeechClient(apiKey: 'xi-key');
/// ```
class DefaultElevenLabsSpeechClient extends ElevenLabsSpeechClient {
  /// Creates a default ElevenLabs speech client.
  DefaultElevenLabsSpeechClient({
    required this.apiKey,
    String? baseUrl,
    this.timeout,
  }) : baseUrl = baseUrl ?? 'https://api.elevenlabs.io';

  /// ElevenLabs API key sent via `xi-api-key`.
  final String apiKey;

  /// Base URL for ElevenLabs REST and WebSocket endpoints.
  final String baseUrl;

  /// Optional default request timeout in seconds.
  final double? timeout;

  @override
  Future<ElevenLabsRealtimeSttConnection> connectRealtimeStt(
    Map<String, Object?> options,
  ) async {
    final Uri httpUri = Uri.parse(baseUrl);
    final String wsScheme = httpUri.scheme == 'http' ? 'ws' : 'wss';
    final Map<String, String> queryParams = <String, String>{};
    for (final MapEntry<String, Object?> entry in options.entries) {
      if (entry.value != null) {
        queryParams[entry.key] = '${entry.value}';
      }
    }
    final Uri wsUri = httpUri.replace(
      scheme: wsScheme,
      path: '${httpUri.path.replaceAll(RegExp(r'/$'), '')}/v1/speech-to-text/realtime',
      queryParameters: queryParams,
    );
    final WebSocket ws = await WebSocket.connect(
      wsUri.toString(),
      headers: <String, dynamic>{'xi-api-key': apiKey},
    );
    return _WebSocketElevenLabsSttConnection(ws);
  }

  @override
  Stream<List<int>> convertTextToSpeech({
    required String voiceId,
    required String text,
    required String modelId,
    required String outputFormat,
    String? languageCode,
    String? previousText,
    Map<String, Object?>? voiceSettings,
    Map<String, Object?>? requestOptions,
  }) async* {
    final HttpClient httpClient = HttpClient();
    final Object? timeoutSec = requestOptions?['timeout_in_seconds'] ?? timeout;
    if (timeoutSec is num && timeoutSec > 0) {
      httpClient.connectionTimeout = Duration(
        milliseconds: (timeoutSec * 1000).round(),
      );
    }
    try {
      final Uri baseUri = Uri.parse(baseUrl);
      final Uri uri = baseUri.replace(
        path:
            '${baseUri.path.replaceAll(RegExp(r'/$'), '')}/v1/text-to-speech/$voiceId/stream',
        queryParameters: <String, String>{'output_format': outputFormat},
      );
      final HttpClientRequest request = await httpClient.postUrl(uri);
      request.headers.set('xi-api-key', apiKey);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      final Map<String, Object?> body = <String, Object?>{
        'text': text,
        'model_id': modelId,
        'language_code': ?languageCode,
        'previous_text': ?previousText,
        'voice_settings': ?voiceSettings,
      };
      request.add(utf8.encode(jsonEncode(body)));
      final HttpClientResponse response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String errBody = await utf8.decodeStream(response);
        throw HttpException(
          'ElevenLabs TTS failed with status ${response.statusCode}: $errBody',
          uri: uri,
        );
      }
      await for (final List<int> chunk in response) {
        if (chunk.isNotEmpty) {
          yield chunk;
        }
      }
    } finally {
      httpClient.close(force: false);
    }
  }
}

class _WebSocketElevenLabsSttConnection
    extends ElevenLabsRealtimeSttConnection {
  _WebSocketElevenLabsSttConnection(this._ws) {
    _sub = _ws.listen(
      (dynamic raw) {
        if (raw is! String) {
          return;
        }
        try {
          final Object? decoded = jsonDecode(raw);
          if (decoded is Map) {
            final Map<String, Object?> map = decoded.map(
              (Object? k, Object? v) => MapEntry('$k', v),
            );
            final String eventType =
                (map['message_type'] ?? map['type'] ?? '') as String;
            _dispatch(eventType, map);
          }
        } catch (e) {
          _dispatch(
            ElevenLabsRealtimeEvents.error,
            <String, Object?>{'error': '$e'},
          );
        }
      },
      onError: (Object error) {
        _dispatch(
          ElevenLabsRealtimeEvents.error,
          <String, Object?>{'error': '$error'},
        );
      },
      onDone: () {
        _dispatch(ElevenLabsRealtimeEvents.close, const <String, Object?>{});
      },
    );
  }

  final WebSocket _ws;
  StreamSubscription<dynamic>? _sub;
  final Map<String, List<void Function(Map<String, Object?> data)>> _handlers =
      <String, List<void Function(Map<String, Object?> data)>>{};

  void _dispatch(String eventName, Map<String, Object?> data) {
    final List<void Function(Map<String, Object?> data)>? list =
        _handlers[eventName];
    if (list == null) {
      return;
    }
    for (final void Function(Map<String, Object?> data) handler
        in List<void Function(Map<String, Object?> data)>.from(list)) {
      handler(data);
    }
  }

  @override
  void on(
    String eventName,
    void Function(Map<String, Object?> data) handler,
  ) {
    _handlers
        .putIfAbsent(
          eventName,
          () => <void Function(Map<String, Object?> data)>[],
        )
        .add(handler);
  }

  @override
  Future<void> send(Map<String, Object?> payload) async {
    _ws.add(
      jsonEncode(<String, Object?>{
        'message_type': 'input_audio_chunk',
        ...payload,
      }),
    );
  }

  @override
  Future<void> commit() async {
    _ws.add(
      jsonEncode(<String, Object?>{
        'message_type': 'input_audio_chunk',
        'audio_base_64': '',
        'commit': true,
      }),
    );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _ws.close();
    _dispatch(ElevenLabsRealtimeEvents.close, const <String, Object?>{});
  }
}

/// Builds a configured [DefaultElevenLabsSpeechClient].
///
/// Resolves [apiKey] from [elevenLabsApiKeyEnv] when omitted.
DefaultElevenLabsSpeechClient getElevenLabsClient({
  String? apiKey,
  String? baseUrl,
  double? timeout,
  Map<String, String>? environment,
}) {
  final String resolvedKey = resolveElevenLabsApiKey(
    apiKey,
    environment: environment,
  );
  return DefaultElevenLabsSpeechClient(
    apiKey: resolvedKey,
    baseUrl: baseUrl,
    timeout: timeout,
  );
}

/// Parses a `rate=...` parameter from an `audio/pcm` or `audio/l16` [mime] type.
///
/// Defaults to `16000` Hz if no `rate=` parameter is present.
/// Throws an [ArgumentError] if [mime] is not `audio/pcm` or `audio/l16`, or if
/// the parsed rate is not in [supportedElevenLabsSttSampleRates].
int parseElevenLabsSttAudioMime(String mime) {
  final List<String> parts = mime
      .split(';')
      .map((String p) => p.trim().toLowerCase())
      .toList();
  final String base = parts.isEmpty ? '' : parts.first;
  if (base != 'audio/pcm' && base != 'audio/l16') {
    throw ArgumentError(
      'ElevenLabsSTT expects audio/pcm or audio/l16 input, got '
      'mimeType=$mime. Resample or transcode before calling sendRealtime().',
    );
  }
  int rate = 16000;
  for (final String param in parts.skip(1)) {
    if (param.startsWith('rate=')) {
      final int? parsed = int.tryParse(param.substring('rate='.length));
      if (parsed == null) {
        throw ArgumentError('Invalid rate parameter in mimeType=$mime');
      }
      rate = parsed;
    }
  }
  if (!supportedElevenLabsSttSampleRates.contains(rate)) {
    final List<int> sorted = supportedElevenLabsSttSampleRates.toList()..sort();
    throw ArgumentError(
      'Unsupported PCM sample rate $rate Hz in mimeType=$mime; '
      'ElevenLabs Realtime STT supports $sorted.',
    );
  }
  return rate;
}

class _SttQueueItem {
  const _SttQueueItem.event(this.event) : error = null, isSentinel = false;
  const _SttQueueItem.error(this.error) : event = null, isSentinel = false;
  const _SttQueueItem.sentinel() : event = null, error = null, isSentinel = true;

  final IngressEvent? event;
  final Object? error;
  final bool isSentinel;
}

class _SttAsyncQueue {
  final Queue<_SttQueueItem> _items = Queue<_SttQueueItem>();
  final Queue<Completer<_SttQueueItem>> _waiters =
      Queue<Completer<_SttQueueItem>>();

  void add(_SttQueueItem item) {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(item);
      return;
    }
    _items.addLast(item);
  }

  Future<_SttQueueItem> get() {
    if (_items.isNotEmpty) {
      return Future<_SttQueueItem>.value(_items.removeFirst());
    }
    final Completer<_SttQueueItem> waiter = Completer<_SttQueueItem>();
    _waiters.addLast(waiter);
    return waiter.future;
  }
}

/// ElevenLabs Realtime speech-to-text [LiveIngress] transform.
///
/// Opens a WebSocket session to the ElevenLabs Realtime Speech-to-Text API,
/// forwards incoming PCM audio chunks, and yields [PartialTranscript],
/// [UserSpeechStarted], and [UserTurnFinished] events.
///
/// ```dart
/// final stt = ElevenLabsSTT(
///   apiKey: 'xi-api-key',
///   sampleRate: 16000,
/// );
/// ```
class ElevenLabsSTT extends LiveIngress {
  /// Creates an ElevenLabs speech-to-text transform.
  ElevenLabsSTT({
    this.modelId = 'scribe_v2_realtime',
    this.languageCode,
    this.sampleRate = 16000,
    this.vadSilenceThresholdSecs = 1.0,
    this.vadThreshold = 0.4,
    this.minSpeechDurationMs = 100,
    this.minSilenceDurationMs = 100,
    this.minChunkMs = 100,
    this.flushTimeoutSecs = 1.0,
    this.includeTimestamps = false,
    String? apiKey,
    String? baseUrl,
    ElevenLabsSpeechClient? client,
    Map<String, String>? environment,
  }) : _apiKey = apiKey,
       _baseUrl = baseUrl,
       _client = client,
       _environment = environment {
    experimental(FeatureName.elevenLabs).checkEnabled();
    if (!supportedElevenLabsSttSampleRates.contains(sampleRate)) {
      final List<int> sorted = supportedElevenLabsSttSampleRates.toList()
        ..sort();
      throw ArgumentError(
        'Unsupported sampleRate=$sampleRate; '
        'ElevenLabs Realtime STT supports $sorted.',
      );
    }
  }

  /// ElevenLabs realtime STT model identifier.
  final String modelId;

  /// Optional ISO-639-1 or ISO-639-3 language code hint.
  final String? languageCode;

  /// Default PCM sample rate in Hz when not specified in the audio MIME type.
  final int sampleRate;

  /// Seconds of silence before VAD commits the transcript.
  final double vadSilenceThresholdSecs;

  /// Voice activity detection sensitivity threshold.
  final double vadThreshold;

  /// Minimum speech duration in milliseconds before triggering VAD.
  final int minSpeechDurationMs;

  /// Minimum silence duration in milliseconds during speech.
  final int minSilenceDurationMs;

  /// Minimum audio chunk duration in milliseconds buffered before sending.
  final int minChunkMs;

  /// Seconds to wait for a final transcript after committing on stream end.
  final double flushTimeoutSecs;

  /// Whether to subscribe to timestamped committed transcript events.
  final bool includeTimestamps;

  final String? _apiKey;
  final String? _baseUrl;
  ElevenLabsSpeechClient? _client;
  final Map<String, String>? _environment;

  ElevenLabsSpeechClient _getClient() {
    return _client ??= getElevenLabsClient(
      apiKey: _apiKey,
      baseUrl: _baseUrl,
      environment: _environment,
    );
  }

  @override
  Stream<IngressEvent> call(Stream<InlineData> audio) async* {
    final StreamIterator<InlineData> iterator = StreamIterator<InlineData>(
      audio,
    );
    InlineData? firstBlob;
    try {
      while (await iterator.moveNext()) {
        final InlineData candidate = iterator.current;
        if (candidate.data.isNotEmpty) {
          firstBlob = candidate;
          break;
        }
      }
    } catch (_) {
      await iterator.cancel();
      rethrow;
    }

    if (firstBlob == null) {
      await iterator.cancel();
      return;
    }

    final int rate = firstBlob.mimeType.isNotEmpty
        ? parseElevenLabsSttAudioMime(firstBlob.mimeType)
        : sampleRate;

    final Map<String, Object?> options = <String, Object?>{
      'model_id': modelId,
      'audio_format': 'pcm_$rate',
      'sample_rate': rate,
      'commit_strategy': 'vad',
      'vad_silence_threshold_secs': vadSilenceThresholdSecs,
      'vad_threshold': vadThreshold,
      'min_speech_duration_ms': minSpeechDurationMs,
      'min_silence_duration_ms': minSilenceDurationMs,
      'include_timestamps': includeTimestamps,
      if (languageCode != null) 'language_code': languageCode,
    };

    final ElevenLabsSpeechClient client = _getClient();
    final ElevenLabsRealtimeSttConnection connection = await client
        .connectRealtimeStt(options);

    final _SttAsyncQueue eventQueue = _SttAsyncQueue();
    bool inSpeech = false;

    connection.on(ElevenLabsRealtimeEvents.sessionStarted, (
      Map<String, Object?> data,
    ) {
      developer.log('ElevenLabs STT session started: $data', name: 'adk_dart.eleven_labs');
    });

    connection.on(ElevenLabsRealtimeEvents.partialTranscript, (
      Map<String, Object?> data,
    ) {
      final Object? text = data['text'];
      if (text is String && text.isNotEmpty) {
        if (!inSpeech) {
          inSpeech = true;
          eventQueue.add(const _SttQueueItem.event(UserSpeechStarted()));
        }
        eventQueue.add(_SttQueueItem.event(PartialTranscript(text: text)));
      }
    });

    final String commitEvent = includeTimestamps
        ? ElevenLabsRealtimeEvents.committedTranscriptWithTimestamps
        : ElevenLabsRealtimeEvents.committedTranscript;
    connection.on(commitEvent, (Map<String, Object?> data) {
      inSpeech = false;
      final Object? text = data['text'];
      if (text is String && text.isNotEmpty) {
        eventQueue.add(_SttQueueItem.event(UserTurnFinished(text: text)));
      }
    });

    for (final String errEvent in _fatalSttEvents) {
      connection.on(errEvent, (Map<String, Object?> data) {
        final Object detail = data['error'] ?? data['message'] ?? data;
        developer.log(
          'ElevenLabs STT fatal error ($errEvent): $detail',
          name: 'adk_dart.eleven_labs',
        );
        eventQueue.add(
          _SttQueueItem.error(
            StateError('ElevenLabs STT error ($errEvent): $detail'),
          ),
        );
      });
    }

    for (final String benignEvent in _benignSttEvents) {
      connection.on(benignEvent, (Map<String, Object?> data) {
        developer.log(
          'ElevenLabs STT notice ($benignEvent): $data',
          name: 'adk_dart.eleven_labs',
        );
      });
    }

    connection.on(ElevenLabsRealtimeEvents.close, (Map<String, Object?> data) {
      eventQueue.add(const _SttQueueItem.sentinel());
    });

    int minBytes = (rate * 2 * minChunkMs) ~/ 1000;
    if (minBytes < 2) {
      minBytes = 2;
    }

    bool stopForwarding = false;

    Future<void> forwardAudio() async {
      final BytesBuilder buf = BytesBuilder(copy: false);

      Future<void> drainBuffer({bool force = false}) async {
        Uint8List current = buf.takeBytes();
        int offset = 0;
        while (current.length - offset >= minBytes) {
          final Uint8List chunk = Uint8List.sublistView(
            current,
            offset,
            offset + minBytes,
          );
          offset += minBytes;
          await connection.send(<String, Object?>{
            'audio_base_64': base64Encode(chunk),
            'sample_rate': rate,
          });
        }
        if (offset < current.length) {
          final Uint8List remainder = Uint8List.sublistView(current, offset);
          if (force && remainder.isNotEmpty) {
            await connection.send(<String, Object?>{
              'audio_base_64': base64Encode(remainder),
              'sample_rate': rate,
            });
          } else {
            buf.add(remainder);
          }
        }
      }

      try {
        buf.add(firstBlob!.data);
        await drainBuffer();

        while (!stopForwarding && await iterator.moveNext()) {
          final InlineData blob = iterator.current;
          if (blob.data.isEmpty) {
            continue;
          }
          if (blob.mimeType.isNotEmpty) {
            final int chunkRate = parseElevenLabsSttAudioMime(blob.mimeType);
            if (chunkRate != rate) {
              developer.log(
                'Dropping audio chunk: sample rate changed mid-session '
                '($chunkRate Hz != initial $rate Hz).',
                name: 'adk_dart.eleven_labs',
              );
              continue;
            }
          }
          buf.add(blob.data);
          await drainBuffer();
        }

        if (!stopForwarding) {
          await drainBuffer(force: true);
          await connection.commit();
          if (flushTimeoutSecs > 0) {
            await Future<void>.delayed(
              Duration(milliseconds: (flushTimeoutSecs * 1000).round()),
            );
          }
          await connection.close();
        }
      } catch (e) {
        if (!stopForwarding) {
          developer.log(
            'ElevenLabs STT audio forwarding failed: $e',
            name: 'adk_dart.eleven_labs',
          );
          eventQueue.add(_SttQueueItem.error(e));
        }
      }
    }

    final Future<void> sendTask = forwardAudio();
    try {
      while (true) {
        final _SttQueueItem item = await eventQueue.get();
        if (item.isSentinel) {
          break;
        }
        if (item.error != null) {
          throw item.error!;
        }
        if (item.event != null) {
          yield item.event!;
        }
      }
    } finally {
      stopForwarding = true;
      await iterator.cancel();
      try {
        await connection.close();
      } catch (_) {}
      try {
        await sendTask;
      } catch (_) {}
    }
  }
}

final RegExp _sentenceEndPattern = RegExp(
  r'[.!?\u2026]["\x27\u201d\u2019)\]]*\s+|\n+',
);

/// Splits a stream of [text] deltas into sentence-sized pieces suitable for
/// low-latency text-to-speech synthesis.
Stream<String> splitElevenLabsTtsSentences(Stream<String> text) async* {
  String buf = '';
  await for (final String delta in text) {
    buf += delta;
    while (true) {
      final RegExpMatch? match = _sentenceEndPattern.firstMatch(buf);
      if (match != null) {
        final String piece = buf.substring(0, match.end);
        buf = buf.substring(match.end);
        if (piece.trim().isNotEmpty) {
          yield piece;
        }
        continue;
      }
      if (buf.length >= maxElevenLabsSentenceChars) {
        final String head = buf.substring(0, maxElevenLabsSentenceChars);
        final int cut = head.lastIndexOf(' ');
        String piece;
        if (cut > 0) {
          piece = buf.substring(0, cut + 1);
          buf = buf.substring(cut + 1);
        } else {
          piece = head;
          buf = buf.substring(maxElevenLabsSentenceChars);
        }
        if (piece.trim().isNotEmpty) {
          yield piece;
        }
        continue;
      }
      break;
    }
  }
  if (buf.trim().isNotEmpty) {
    yield buf;
  }
}

/// ElevenLabs streaming text-to-speech [LiveEgress] transform.
///
/// Accumulates incoming LLM text deltas into sentences, synthesizes each
/// sentence via ElevenLabs streaming TTS, and emits [AudioChunk] events
/// followed by an [AgentSpokenOutput] event once all audio chunks for that
/// sentence have been emitted without cancellation.
///
/// ```dart
/// final tts = ElevenLabsTTS(
///   voiceId: 'JBFqnCBsd6RMkjVDRZzb',
///   apiKey: 'xi-api-key',
/// );
/// ```
class ElevenLabsTTS extends LiveEgress {
  /// Creates an ElevenLabs text-to-speech transform.
  ElevenLabsTTS({
    this.voiceId = defaultElevenLabsVoiceId,
    this.modelId = 'eleven_flash_v2_5',
    this.sampleRate = 24000,
    String? outputFormat,
    this.languageCode,
    this.stability,
    this.similarityBoost,
    this.style,
    this.useSpeakerBoost,
    this.speed,
    this.timeout = 30.0,
    String? apiKey,
    String? baseUrl,
    ElevenLabsSpeechClient? client,
    Map<String, String>? environment,
  }) : _apiKey = apiKey,
       _baseUrl = baseUrl,
       _client = client,
       _environment = environment {
    experimental(FeatureName.elevenLabs).checkEnabled();
    if (outputFormat != null) {
      this.outputFormat = outputFormat;
      final RegExpMatch? match = RegExp(r'^pcm_(\d+)$').firstMatch(outputFormat);
      if (match != null) {
        outputMimeType = 'audio/pcm;rate=${match.group(1)}';
      } else {
        outputMimeType = 'audio/mpeg';
      }
    } else {
      if (!supportedElevenLabsTtsSampleRates.contains(sampleRate)) {
        final List<int> sorted = supportedElevenLabsTtsSampleRates.toList()
          ..sort();
        throw ArgumentError(
          'Unsupported sampleRate=$sampleRate; '
          'ElevenLabs PCM TTS supports $sorted.',
        );
      }
      this.outputFormat = 'pcm_$sampleRate';
      outputMimeType = 'audio/pcm;rate=$sampleRate';
    }

    final Map<String, Object?> settings = <String, Object?>{
      if (stability != null) 'stability': stability,
      if (similarityBoost != null) 'similarity_boost': similarityBoost,
      if (style != null) 'style': style,
      if (useSpeakerBoost != null) 'use_speaker_boost': useSpeakerBoost,
      if (speed != null) 'speed': speed,
    };
    voiceSettings = settings.isEmpty
        ? null
        : Map<String, Object?>.unmodifiable(settings);
    requestOptions = Map<String, Object?>.unmodifiable(<String, Object?>{
      'timeout_in_seconds': timeout.round(),
    });
  }

  /// ElevenLabs voice identifier.
  final String voiceId;

  /// ElevenLabs TTS model identifier.
  final String modelId;

  /// Output PCM sample rate in Hz when [outputFormat] is not overridden.
  final int sampleRate;

  /// Resolved ElevenLabs `output_format` query parameter (e.g. `pcm_24000`).
  late final String outputFormat;

  /// Resolved MIME type attached to emitted [AudioChunk] blobs.
  late final String outputMimeType;

  /// Optional ISO-639-1 language code.
  final String? languageCode;

  /// Optional voice stability setting (`0.0` to `1.0`).
  final double? stability;

  /// Optional voice similarity boost setting (`0.0` to `1.0`).
  final double? similarityBoost;

  /// Optional voice style setting (`0.0` to `1.0`).
  final double? style;

  /// Optional speaker boost flag.
  final bool? useSpeakerBoost;

  /// Optional speech speed multiplier.
  final double? speed;

  /// Request timeout in seconds.
  final double timeout;

  /// Resolved voice settings map passed to ElevenLabs, or `null` if default.
  late final Map<String, Object?>? voiceSettings;

  /// Request options map passed to the client.
  late final Map<String, Object?> requestOptions;

  final String? _apiKey;
  final String? _baseUrl;
  ElevenLabsSpeechClient? _client;
  final Map<String, String>? _environment;

  ElevenLabsSpeechClient _getClient() {
    return _client ??= getElevenLabsClient(
      apiKey: _apiKey,
      baseUrl: _baseUrl,
      timeout: timeout,
      environment: _environment,
    );
  }

  @override
  Stream<EgressEvent> call(
    Stream<String> text, {
    required CancelSignal cancel,
  }) async* {
    final ElevenLabsSpeechClient client = _getClient();
    String? previousText;

    final StreamIterator<String> sentenceIterator = StreamIterator<String>(
      splitElevenLabsTtsSentences(text),
    );

    try {
      while (!cancel.isSet) {
        final Future<bool> hasNextFuture = sentenceIterator.moveNext();
        final Object? raceResult = await Future.any<Object?>(<Future<Object?>>[
          hasNextFuture,
          cancel.onSet.then((_) => null),
        ]);
        if (cancel.isSet || raceResult != true) {
          break;
        }

        final String piece = sentenceIterator.current;
        final String clean = piece.trim();
        if (clean.isEmpty) {
          continue;
        }

        final Stream<List<int>> audioStream = client.convertTextToSpeech(
          voiceId: voiceId,
          text: clean,
          modelId: modelId,
          outputFormat: outputFormat,
          languageCode: languageCode,
          previousText: previousText,
          voiceSettings: voiceSettings,
          requestOptions: requestOptions,
        );
        final StreamIterator<List<int>> chunkIterator =
            StreamIterator<List<int>>(audioStream);
        try {
          while (!cancel.isSet) {
            final Future<bool> nextChunkFuture = chunkIterator.moveNext();
            final Object? chunkRace = await Future.any<Object?>(
              <Future<Object?>>[
                nextChunkFuture,
                cancel.onSet.then((_) => null),
              ],
            );
            if (cancel.isSet || chunkRace != true) {
              break;
            }
            final List<int> chunk = chunkIterator.current;
            if (chunk.isNotEmpty) {
              yield AudioChunk(
                blob: InlineData(
                  mimeType: outputMimeType,
                  data: List<int>.from(chunk),
                ),
              );
            }
          }
        } finally {
          await chunkIterator.cancel();
        }

        if (cancel.isSet) {
          return;
        }

        yield AgentSpokenOutput(text: piece);
        previousText = clean;
      }
    } finally {
      await sentenceIterator.cancel();
    }
  }
}
