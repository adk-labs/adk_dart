/// Audio helpers for feeding synthesized speech into a Live API session.
///
/// TTS backends commonly emit 24 kHz PCM (or RIFF/WAV-wrapped PCM), while the
/// Live API expects 16 kHz 16-bit mono PCM input (`audio/pcm;rate=16000`).
library;

import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import '../types/content.dart';

/// Alias for [InlineData] matching `google.genai.types.Blob`.
typedef Blob = InlineData;

/// Live API input sample rate in Hz (16-bit mono PCM).
const int liveInputRateHz = 16000;

/// Common Live/TTS output sample rate in Hz (16-bit mono PCM).
const int liveOutputRateHz = 24000;

/// Canonical MIME type for 16 kHz PCM Live API input.
const String liveInputMimeType = 'audio/pcm;rate=16000';

final RegExp _ratePattern = RegExp(
  r'(?:^|;)\s*rate\s*=\s*(\d+)\s*(?=;|$)',
  caseSensitive: false,
);

/// Extracts the sample rate from a MIME type such as `'audio/pcm;rate=24000'`.
///
/// Falls back to [defaultRate] when [mimeType] is `null`, empty, or carries no
/// standalone `rate=` parameter.
int parseSampleRate(String? mimeType, {int defaultRate = liveOutputRateHz}) {
  if (mimeType == null || mimeType.isEmpty) {
    return defaultRate;
  }
  final RegExpMatch? match = _ratePattern.firstMatch(mimeType);
  if (match == null) {
    return defaultRate;
  }
  return int.tryParse(match.group(1)!) ?? defaultRate;
}

/// Resamples 16-bit signed little-endian mono PCM via linear interpolation.
///
/// Returns [pcmBytes] unchanged when [fromRate] equals [toRate] or when the
/// buffer has fewer than 2 samples. Throws an [ArgumentError] when [fromRate]
/// or [toRate] is not positive. If [pcmBytes] begins with a valid RIFF/WAVE
/// header, strips the WAV header (and uses the WAV header sample rate when
/// [fromRate] was not overridden or resamples from the WAV header rate if it
/// differs).
Uint8List resamplePcm16(
  Uint8List pcmBytes, {
  required int fromRate,
  int toRate = liveInputRateHz,
}) {
  if (fromRate <= 0 || toRate <= 0) {
    throw ArgumentError('Sample rates must be positive');
  }
  if (pcmBytes.isEmpty) {
    return Uint8List(0);
  }

  final _ParsedWav? wav = _tryParseWavPcm16(pcmBytes);
  final Uint8List rawPcm = wav?.pcm16MonoBytes ?? pcmBytes;
  final int effectiveFromRate = wav?.sampleRate ?? fromRate;

  if (rawPcm.isEmpty || effectiveFromRate == toRate) {
    return Uint8List.fromList(rawPcm);
  }

  // Drop a trailing odd byte so the buffer is a whole number of 16-bit samples.
  final int evenLength = rawPcm.length - (rawPcm.length % 2);
  final int sampleCount = evenLength ~/ 2;
  if (sampleCount < 2) {
    return Uint8List.fromList(rawPcm);
  }

  final ByteData inView = ByteData.sublistView(rawPcm, 0, evenLength);
  final double ratio = effectiveFromRate / toRate;
  final int outLen = math.max(1, (sampleCount / ratio).truncate());
  final Uint8List outBytes = Uint8List(outLen * 2);
  final ByteData outView = ByteData.sublistView(outBytes);
  final int lastIndex = sampleCount - 1;

  for (int i = 0; i < outLen; i += 1) {
    final double srcPos = i * ratio;
    final int left = srcPos.truncate();
    final int right = math.min(left + 1, lastIndex);
    final double frac = srcPos - left;
    final int leftSample = inView.getInt16(left * 2, Endian.little);
    final int rightSample = inView.getInt16(right * 2, Endian.little);
    final int interpolated =
        (leftSample * (1.0 - frac) + rightSample * frac)
            .truncate()
            .clamp(-32768, 32767);
    outView.setInt16(i * 2, interpolated, Endian.little);
  }

  return outBytes;
}

/// Converts synthesized speech [audioBlob] into a 16-bit mono PCM [Blob] at
/// [targetRate] (`'audio/pcm;rate=$targetRate'`) for Live API input.
Blob toLiveInput(Blob audioBlob, {int targetRate = liveInputRateHz}) {
  if (targetRate <= 0) {
    throw ArgumentError('Sample rates must be positive');
  }
  final Uint8List inputBytes = audioBlob.data is Uint8List
      ? audioBlob.data as Uint8List
      : Uint8List.fromList(audioBlob.data);

  final _ParsedWav? wav = _tryParseWavPcm16(inputBytes);
  if (wav != null) {
    final int declaredOrWavRate = _ratePattern.hasMatch(audioBlob.mimeType)
        ? parseSampleRate(audioBlob.mimeType, defaultRate: wav.sampleRate)
        : wav.sampleRate;
    final Uint8List resampled = resamplePcm16(
      wav.pcm16MonoBytes,
      fromRate: declaredOrWavRate,
      toRate: targetRate,
    );
    return Blob(mimeType: 'audio/pcm;rate=$targetRate', data: resampled);
  }

  final String mimeType = audioBlob.mimeType;
  if (mimeType.isEmpty || !_ratePattern.hasMatch(mimeType)) {
    developer.log(
      'Audio mime type "$mimeType" has no `rate=`; assuming '
      '$liveOutputRateHz Hz before resampling to the Live API input rate. '
      'Mislabeled audio will be resampled incorrectly.',
      name: 'adk_dart.evaluation.audio_utils',
      level: 900,
    );
  }
  final int srcRate = parseSampleRate(mimeType, defaultRate: liveOutputRateHz);
  final Uint8List resampled = resamplePcm16(
    inputBytes,
    fromRate: srcRate,
    toRate: targetRate,
  );
  return Blob(mimeType: 'audio/pcm;rate=$targetRate', data: resampled);
}

class _ParsedWav {
  const _ParsedWav({required this.sampleRate, required this.pcm16MonoBytes});

  final int sampleRate;
  final Uint8List pcm16MonoBytes;
}

_ParsedWav? _tryParseWavPcm16(Uint8List bytes) {
  if (bytes.length < 44) {
    return null;
  }
  // Check ASCII 'RIFF' at 0..4 and 'WAVE' at 8..12.
  if (bytes[0] != 0x52 ||
      bytes[1] != 0x49 ||
      bytes[2] != 0x46 ||
      bytes[3] != 0x46 ||
      bytes[8] != 0x57 ||
      bytes[9] != 0x41 ||
      bytes[10] != 0x56 ||
      bytes[11] != 0x45) {
    return null;
  }

  final ByteData view = ByteData.sublistView(bytes);
  int offset = 12;
  int? sampleRate;
  int numChannels = 1;
  int bitsPerSample = 16;
  int audioFormat = 1;
  Uint8List? dataChunk;

  while (offset + 8 <= bytes.length) {
    final int id0 = bytes[offset];
    final int id1 = bytes[offset + 1];
    final int id2 = bytes[offset + 2];
    final int id3 = bytes[offset + 3];
    final int chunkSize = view.getUint32(offset + 4, Endian.little);
    final int payloadStart = offset + 8;
    final int availableEnd = math.min(payloadStart + chunkSize, bytes.length);

    // 'fmt '
    if (id0 == 0x66 && id1 == 0x6D && id2 == 0x74 && id3 == 0x20) {
      if (availableEnd - payloadStart < 16) {
        return null;
      }
      audioFormat = view.getUint16(payloadStart, Endian.little);
      numChannels = view.getUint16(payloadStart + 2, Endian.little);
      sampleRate = view.getUint32(payloadStart + 4, Endian.little);
      bitsPerSample = view.getUint16(payloadStart + 14, Endian.little);
    } else if (id0 == 0x64 && id1 == 0x61 && id2 == 0x74 && id3 == 0x61) {
      // 'data'
      dataChunk = Uint8List.sublistView(bytes, payloadStart, availableEnd);
      break;
    }

    final int paddedSize = chunkSize + (chunkSize.isOdd ? 1 : 0);
    if (paddedSize < 0 || payloadStart + paddedSize <= offset) {
      break;
    }
    offset = payloadStart + paddedSize;
  }

  if (sampleRate == null ||
      sampleRate <= 0 ||
      dataChunk == null ||
      audioFormat != 1 ||
      bitsPerSample != 16 ||
      numChannels < 1) {
    return null;
  }

  if (numChannels == 1) {
    return _ParsedWav(
      sampleRate: sampleRate,
      pcm16MonoBytes: Uint8List.fromList(dataChunk),
    );
  }

  // Downmix multi-channel 16-bit PCM frames to mono by averaging channels.
  final int bytesPerFrame = numChannels * 2;
  final int frameCount = dataChunk.length ~/ bytesPerFrame;
  final ByteData dataView = ByteData.sublistView(dataChunk);
  final Uint8List mono = Uint8List(frameCount * 2);
  final ByteData monoView = ByteData.sublistView(mono);
  for (int f = 0; f < frameCount; f += 1) {
    int sum = 0;
    final int frameBase = f * bytesPerFrame;
    for (int ch = 0; ch < numChannels; ch += 1) {
      sum += dataView.getInt16(frameBase + ch * 2, Endian.little);
    }
    monoView.setInt16(
      f * 2,
      (sum ~/ numChannels).clamp(-32768, 32767),
      Endian.little,
    );
  }
  return _ParsedWav(sampleRate: sampleRate, pcm16MonoBytes: mono);
}
