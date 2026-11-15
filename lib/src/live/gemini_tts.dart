/// Text-to-speech transform backed by Gemini text-to-speech models.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../features/_feature_registry.dart';
import '../models/base_llm.dart';
import '../models/base_llm_connection.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../models/registry.dart';
import '../types/content.dart';
import 'cascade_live_events.dart';
import 'transforms.dart';

const String _defaultTtsModel = 'gemini-3.8-flash-lite-tts';
const String _defaultVoice = 'Kore';
const int _defaultSampleRate = 24000;
const int _defaultMinSegmentChars = 50;
const int _defaultMaxSegmentChars = 240;

const Set<int> _transientTtsStatusCodes = <int>{408, 429, 500, 502, 503, 504};

const List<Duration> _defaultRetryDelays = <Duration>[
  Duration(milliseconds: 100),
  Duration(milliseconds: 300),
];

final RegExp _sentenceEnd = RegExp(
  r'[.!?\u2026\u0964]["\x27\u201d\u2019)\]]*\s+'
  r'|[\u3002\uff01\uff1f]["\x27\u201d\u2019)\]\u300d\u300f\uff09]*\s*'
  r'|\n+',
);

final RegExp _cjkClauseEnd = RegExp(r'[\uff0c\u3001\uff1b\uff1a]');

(String?, String) _splitSegment(
  String buffer, {
  required int maxChars,
  int minChars = 0,
}) {
  if (buffer.isEmpty) {
    return (null, buffer);
  }

  for (final RegExpMatch match in _sentenceEnd.allMatches(buffer)) {
    if (match.end >= minChars) {
      return (buffer.substring(0, match.end), buffer.substring(match.end));
    }
  }

  if (buffer.length < maxChars) {
    return (null, buffer);
  }

  final String head = buffer.substring(0, maxChars);
  final int cut = head.lastIndexOf(' ');
  if (cut > 0) {
    return (buffer.substring(0, cut + 1), buffer.substring(cut + 1));
  }

  final Iterable<RegExpMatch> clauseEnds = _cjkClauseEnd.allMatches(head);
  if (clauseEnds.isNotEmpty) {
    final int cjkCut = clauseEnds.last.end;
    return (buffer.substring(0, cjkCut), buffer.substring(cjkCut));
  }

  return (head, buffer.substring(maxChars));
}

bool _hasRiffWaveMagic(List<int> bytes) {
  return bytes.length >= 12 &&
      bytes[0] == 0x52 && // 'R'
      bytes[1] == 0x49 && // 'I'
      bytes[2] == 0x46 && // 'F'
      bytes[3] == 0x46 && // 'F'
      bytes[8] == 0x57 && // 'W'
      bytes[9] == 0x41 && // 'A'
      bytes[10] == 0x56 && // 'V'
      bytes[11] == 0x45; // 'E'
}

int _readUint32Le(List<int> bytes, int offset) {
  return (bytes[offset] & 0xFF) |
      ((bytes[offset + 1] & 0xFF) << 8) |
      ((bytes[offset + 2] & 0xFF) << 16) |
      ((bytes[offset + 3] & 0xFF) << 24);
}

({List<int> pcmData, int? sampleRate})? _tryParseWav(List<int> bytes) {
  if (!_hasRiffWaveMagic(bytes)) {
    return null;
  }
  int offset = 12;
  int? fmtSampleRate;
  while (offset + 8 <= bytes.length) {
    final String chunkId = String.fromCharCodes(
      bytes.sublist(offset, offset + 4),
    );
    final int chunkSize = _readUint32Le(bytes, offset + 4);
    final int chunkDataStart = offset + 8;
    if (chunkId == 'fmt ' && chunkDataStart + 8 <= bytes.length) {
      final int parsedRate = _readUint32Le(bytes, chunkDataStart + 4);
      if (parsedRate > 0) {
        fmtSampleRate = parsedRate;
      }
    } else if (chunkId == 'data') {
      final bool unbounded =
          chunkSize <= 0 ||
          chunkSize == 0xFFFFFFFF ||
          chunkDataStart + chunkSize > bytes.length;
      final int end = unbounded ? bytes.length : chunkDataStart + chunkSize;
      return (
        pcmData: Uint8List.fromList(bytes.sublist(chunkDataStart, end)),
        sampleRate: fmtSampleRate,
      );
    }
    if (chunkSize < 0) {
      break;
    }
    final int paddedSize = chunkSize + (chunkSize.isOdd ? 1 : 0);
    final int nextOffset = chunkDataStart + paddedSize;
    if (nextOffset <= offset) {
      break;
    }
    offset = nextOffset;
  }
  if (bytes.length >= 44) {
    return (
      pcmData: Uint8List.fromList(bytes.sublist(44)),
      sampleRate: fmtSampleRate,
    );
  }
  return null;
}

/// Normalizes Gemini TTS audio [blob] (including WAV containers and `audio/L16`)
/// into raw PCM labeled `audio/pcm;rate=<rate>`.
InlineData normalizeTtsPcmAudio(
  InlineData blob, {
  int defaultSampleRate = _defaultSampleRate,
}) {
  final List<String> parts = blob.mimeType.toLowerCase().split(';');
  final String mediaType = parts.isEmpty ? '' : parts.first.trim();

  int? explicitMimeRate;
  for (int i = 1; i < parts.length; i++) {
    final String param = parts[i];
    final int eq = param.indexOf('=');
    if (eq < 0) {
      continue;
    }
    final String name = param.substring(0, eq).trim();
    final String value = param.substring(eq + 1).trim();
    final int? parsed = int.tryParse(value);
    if (name == 'rate' && parsed != null && parsed > 0) {
      explicitMimeRate = parsed;
    }
  }

  const Set<String> wavMimeTypes = <String>{
    'audio/wav',
    'audio/wave',
    'audio/x-wav',
    'audio/vnd.wave',
  };

  final ({List<int> pcmData, int? sampleRate})? wavParsed = _tryParseWav(
    blob.data,
  );
  if (wavParsed != null) {
    final int rate =
        explicitMimeRate ?? wavParsed.sampleRate ?? defaultSampleRate;
    return InlineData(
      mimeType: 'audio/pcm;rate=$rate',
      data: wavParsed.pcmData,
    );
  }

  if (wavMimeTypes.contains(mediaType)) {
    final int rate = explicitMimeRate ?? defaultSampleRate;
    return InlineData(mimeType: 'audio/pcm;rate=$rate', data: blob.data);
  }

  if (mediaType == 'audio/l16' || mediaType == 'audio/pcm') {
    final int rate = explicitMimeRate ?? defaultSampleRate;
    return InlineData(mimeType: 'audio/pcm;rate=$rate', data: blob.data);
  }

  return blob;
}

bool _isTransientTtsError(Object error) {
  if (error is TimeoutException) {
    return true;
  }
  if (error is RecoverableLiveConnectionException) {
    final int? code = error.code;
    return code == null || _transientTtsStatusCodes.contains(code);
  }

  int? extractedCode;
  try {
    final Object? rawCode = (error as dynamic).code;
    if (rawCode is int) {
      extractedCode = rawCode;
    }
  } catch (_) {}
  if (extractedCode == null) {
    try {
      final Object? rawStatus = (error as dynamic).statusCode;
      if (rawStatus is int) {
        extractedCode = rawStatus;
      }
    } catch (_) {}
  }
  if (extractedCode != null) {
    return _transientTtsStatusCodes.contains(extractedCode);
  }

  final String typeName = error.runtimeType.toString();
  if (typeName.contains('SocketException') ||
      typeName.contains('HandshakeException') ||
      typeName.contains('ClientException') ||
      typeName.contains('ConnectionError')) {
    return true;
  }

  final String lower = '$error'.toLowerCase();
  return lower.contains('connection reset') ||
      lower.contains('timed out') ||
      lower.contains('service unavailable') ||
      lower.contains('temporarily unavailable') ||
      lower.contains('too many requests') ||
      lower.contains('bad gateway');
}

class _AsyncSemaphore {
  _AsyncSemaphore(this._permits);

  int _permits;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();
  bool _closed = false;

  Future<bool> acquire() {
    if (_closed) {
      return Future<bool>.value(false);
    }
    if (_permits > 0) {
      _permits -= 1;
      return Future<bool>.value(true);
    }
    final Completer<void> completer = Completer<void>();
    _waiters.addLast(completer);
    return completer.future.then((_) => !_closed);
  }

  void release() {
    if (_closed) {
      return;
    }
    while (_waiters.isNotEmpty) {
      final Completer<void> next = _waiters.removeFirst();
      if (!next.isCompleted) {
        next.complete();
        return;
      }
    }
    _permits += 1;
  }

  void close() {
    _closed = true;
    while (_waiters.isNotEmpty) {
      final Completer<void> waiter = _waiters.removeFirst();
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }
}

final Object _queueEnd = Object();

class _AsyncItemQueue {
  final Queue<Object> _items = Queue<Object>();
  Completer<void>? _waiter;
  bool _closed = false;

  void add(Object item) {
    if (_closed) {
      return;
    }
    _items.addLast(item);
    final Completer<void>? w = _waiter;
    if (w != null && !w.isCompleted) {
      w.complete();
    }
    _waiter = null;
  }

  Future<Object> next() async {
    while (_items.isEmpty && !_closed) {
      final Completer<void> w = _waiter ??= Completer<void>();
      await w.future;
    }
    if (_items.isEmpty) {
      return _queueEnd;
    }
    return _items.removeFirst();
  }

  void close() {
    _closed = true;
    final Completer<void>? w = _waiter;
    if (w != null && !w.isCompleted) {
      w.complete();
    }
    _waiter = null;
  }
}

class _RecordedError {
  _RecordedError(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}

class _Segment {
  _Segment(this.text);

  final String text;
  final _AsyncItemQueue audio = _AsyncItemQueue();
  bool hasAudio = false;
  bool cancelled = false;
  StreamSubscription<LlmResponse>? activeSubscription;

  Future<void> abort() async {
    cancelled = true;
    audio.close();
    final StreamSubscription<LlmResponse>? sub = activeSubscription;
    activeSubscription = null;
    await sub?.cancel();
  }
}

/// Text-to-speech transform converting text deltas into speech using Gemini.
///
/// ```dart
/// final tts = GeminiTTS(
///   model: 'gemini-3.8-flash-lite-tts',
///   voiceName: 'Kore',
/// );
/// ```
class GeminiTTS extends LiveEgress {
  /// Creates a [GeminiTTS] egress transform.
  GeminiTTS({
    this.model = _defaultTtsModel,
    this.voiceName = _defaultVoice,
    this.sampleRate = _defaultSampleRate,
    this.minSegmentChars = _defaultMinSegmentChars,
    this.maxSegmentChars = _defaultMaxSegmentChars,
    this.prefetchSegments = 1,
    this.speechConfig,
    this.retryDelays = _defaultRetryDelays,
  }) {
    isFeatureEnabled(FeatureName.cascadeLive);
    if (maxSegmentChars < 1) {
      throw ArgumentError.value(
        maxSegmentChars,
        'maxSegmentChars',
        'Must be positive.',
      );
    }
    if (minSegmentChars < 0) {
      throw ArgumentError.value(
        minSegmentChars,
        'minSegmentChars',
        'Must not be negative.',
      );
    }
    if (prefetchSegments < 0) {
      throw ArgumentError.value(
        prefetchSegments,
        'prefetchSegments',
        'Must not be negative.',
      );
    }
  }

  /// Target model name or [BaseLlm] instance.
  final Object model;

  /// Default voice name.
  final String voiceName;

  /// Default PCM audio sample rate when not specified by the response.
  final int sampleRate;

  /// Minimum characters to group before cutting at sentence boundary after the first segment.
  final int minSegmentChars;

  /// Maximum characters for a single synthesis segment.
  final int maxSegmentChars;

  /// Number of segments after the active segment to prefetch concurrently.
  final int prefetchSegments;

  /// Optional speech configuration dictionary.
  final Object? speechConfig;

  /// Backoff delays for retrying transient synthesis errors before any audio is emitted.
  final List<Duration> retryDelays;

  BaseLlm _resolveModel() {
    if (model is BaseLlm) {
      return model as BaseLlm;
    }
    return LLMRegistry.newLlm('$model');
  }

  LlmRequest _buildRequest(BaseLlm llm, String segmentText) {
    return LlmRequest(
      model: llm.model,
      contents: <Content>[Content.userText(segmentText.trim())],
      config: GenerateContentConfig(
        responseModalities: <String>['AUDIO'],
        speechConfig:
            speechConfig ??
            <String, Object?>{
              'voiceConfig': <String, Object?>{
                'prebuiltVoiceConfig': <String, Object?>{
                  'voiceName': voiceName,
                },
              },
            },
      ),
    );
  }

  Future<void> _streamSegmentAttempt(BaseLlm llm, _Segment segment) async {
    final Completer<void> done = Completer<void>();
    final Stream<LlmResponse> responseStream = llm.generateContent(
      _buildRequest(llm, segment.text),
      stream: true,
    );

    final StreamSubscription<LlmResponse> sub = responseStream.listen(
      (LlmResponse response) {
        if (segment.cancelled) {
          return;
        }
        if (response.content != null) {
          for (final Part part in response.content!.parts) {
            final InlineData? inline = part.inlineData;
            if (inline != null && inline.data.isNotEmpty) {
              segment.hasAudio = true;
              segment.audio.add(
                normalizeTtsPcmAudio(inline, defaultSampleRate: sampleRate),
              );
            }
          }
        }
      },
      onError: (Object err, StackTrace stack) {
        if (!done.isCompleted) {
          done.completeError(err, stack);
        }
      },
      onDone: () {
        if (!done.isCompleted) {
          done.complete();
        }
      },
      cancelOnError: true,
    );
    segment.activeSubscription = sub;

    try {
      await done.future;
    } finally {
      if (identical(segment.activeSubscription, sub)) {
        segment.activeSubscription = null;
      }
      await sub.cancel();
    }
  }

  Future<void> _synthesizeSegment(
    BaseLlm llm,
    _Segment segment,
    CancelSignal cancel,
  ) async {
    try {
      int retries = 0;
      while (!segment.cancelled && !cancel.isSet) {
        try {
          await _streamSegmentAttempt(llm, segment);
          break;
        } catch (err, stack) {
          if (segment.cancelled || cancel.isSet) {
            return;
          }
          if (segment.hasAudio ||
              retries >= retryDelays.length ||
              !_isTransientTtsError(err)) {
            segment.audio.add(_RecordedError(err, stack));
            return;
          }
          final Duration delay = retryDelays[retries];
          retries += 1;
          if (delay > Duration.zero) {
            await Future.any(<Future<void>>[
              Future<void>.delayed(delay),
              cancel.onSet,
            ]);
          }
        }
      }
      segment.audio.add(_queueEnd);
    } catch (err, stack) {
      segment.audio.add(_RecordedError(err, stack));
    }
  }

  @override
  Stream<EgressEvent> call(
    Stream<String> text, {
    required CancelSignal cancel,
  }) {
    final _AsyncSemaphore slots = _AsyncSemaphore(prefetchSegments + 1);
    final _AsyncItemQueue segments = _AsyncItemQueue();
    final List<_Segment> startedSegments = <_Segment>[];
    bool aborted = false;
    StreamSubscription<String>? textSub;

    Future<void> abortAll() async {
      if (aborted) {
        return;
      }
      aborted = true;
      slots.close();
      segments.close();
      final StreamSubscription<String>? sub = textSub;
      textSub = null;
      try {
        await sub?.cancel();
      } catch (_) {}
      for (final _Segment segment in List<_Segment>.from(startedSegments)) {
        await segment.abort();
      }
    }

    late final StreamController<EgressEvent> outputController;

    Future<void> startSegment(BaseLlm llm, String segmentText) async {
      final bool acquired = await slots.acquire();
      if (!acquired || aborted || cancel.isSet) {
        return;
      }
      final _Segment segment = _Segment(segmentText);
      startedSegments.add(segment);
      segments.add(segment);
      unawaited(_synthesizeSegment(llm, segment, cancel));
    }

    Future<void> runSplitter(BaseLlm llm, _AsyncItemQueue textQueue) async {
      try {
        String buffer = '';
        String whitespace = '';
        int currentMinChars = 0;

        while (!aborted && !cancel.isSet) {
          final Object item = await textQueue.next();
          if (identical(item, _queueEnd) || aborted || cancel.isSet) {
            break;
          }
          if (item is _RecordedError) {
            segments.add(item);
            return;
          }
          buffer += item as String;
          while (!aborted && !cancel.isSet) {
            final (String? piece, String remainder) = _splitSegment(
              buffer,
              maxChars: maxSegmentChars,
              minChars: currentMinChars,
            );
            if (piece == null) {
              break;
            }
            buffer = remainder;
            if (piece.trim().isEmpty) {
              whitespace += piece;
              continue;
            }
            currentMinChars = minSegmentChars;
            final String combined = whitespace + piece;
            whitespace = '';
            await startSegment(llm, combined);
          }
        }

        if (!aborted && !cancel.isSet && buffer.trim().isNotEmpty) {
          await startSegment(llm, whitespace + buffer);
        }
        segments.add(_queueEnd);
      } catch (err, stack) {
        segments.add(_RecordedError(err, stack));
      } finally {
        final StreamSubscription<String>? sub = textSub;
        textSub = null;
        try {
          await sub?.cancel();
        } catch (_) {}
      }
    }

    Future<void> runDeliverer(BaseLlm llm, _AsyncItemQueue textQueue) async {
      unawaited(runSplitter(llm, textQueue));
      try {
        while (!aborted && !cancel.isSet) {
          final Object nextSeg = await segments.next();
          if (identical(nextSeg, _queueEnd) || aborted || cancel.isSet) {
            return;
          }
          if (nextSeg is _RecordedError) {
            Error.throwWithStackTrace(nextSeg.error, nextSeg.stackTrace);
          }
          final _Segment segment = nextSeg as _Segment;
          bool producedAudio = false;

          while (!aborted && !cancel.isSet) {
            final Object audioItem = await segment.audio.next();
            if (aborted || cancel.isSet) {
              return;
            }
            if (identical(audioItem, _queueEnd)) {
              break;
            }
            if (audioItem is _RecordedError) {
              Error.throwWithStackTrace(audioItem.error, audioItem.stackTrace);
            }
            producedAudio = true;
            if (!outputController.isClosed) {
              outputController.add(AudioChunk(blob: audioItem as InlineData));
            }
          }

          slots.release();
          if (aborted || cancel.isSet) {
            return;
          }
          if (producedAudio && !outputController.isClosed) {
            outputController.add(AgentSpokenOutput(text: segment.text));
          }
        }
      } catch (err, stack) {
        if (!aborted && !cancel.isSet && !outputController.isClosed) {
          outputController.addError(err, stack);
        }
      } finally {
        await abortAll();
        if (!outputController.isClosed) {
          await outputController.close();
        }
      }
    }

    outputController = StreamController<EgressEvent>(
      onListen: () {
        if (cancel.isSet) {
          unawaited(
            Future<void>(() async {
              try {
                await text.listen(null).cancel();
              } catch (_) {}
              if (!outputController.isClosed) {
                await outputController.close();
              }
            }),
          );
          return;
        }

        final BaseLlm llm;
        try {
          llm = _resolveModel();
        } catch (err, stack) {
          unawaited(
            Future<void>(() async {
              try {
                await text.listen(null).cancel();
              } catch (_) {}
              if (!outputController.isClosed) {
                outputController.addError(err, stack);
                await outputController.close();
              }
            }),
          );
          return;
        }

        final _AsyncItemQueue textQueue = _AsyncItemQueue();
        textSub = text.listen(
          (String delta) => textQueue.add(delta),
          onError: (Object err, StackTrace stack) =>
              textQueue.add(_RecordedError(err, stack)),
          onDone: () => textQueue.add(_queueEnd),
          cancelOnError: true,
        );

        unawaited(
          cancel.onSet.then((_) async {
            textQueue.close();
            await abortAll();
            if (!outputController.isClosed) {
              await outputController.close();
            }
          }),
        );

        unawaited(runDeliverer(llm, textQueue));
      },
      onCancel: () async {
        await abortAll();
      },
    );

    return outputController.stream;
  }
}
