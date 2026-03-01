import 'dart:typed_data';

import '../../agents/invocation_context.dart';
import '../../agents/transcription_entry.dart';
import '../../types/content.dart';

typedef AudioRecognizer = Future<List<String>> Function(List<int> audioData);

class AudioTranscriber {
  AudioTranscriber({this.recognizer});

  static AudioRecognizer? _defaultRecognizer;

  static void registerDefaultRecognizer(AudioRecognizer recognizer) {
    _defaultRecognizer = recognizer;
  }

  static void clearDefaultRecognizer() {
    _defaultRecognizer = null;
  }

  final AudioRecognizer? recognizer;

  Future<List<Content>> transcribeFile(
    InvocationContext invocationContext,
  ) async {
    final List<({String speaker, Object data})> bundledAudio =
        <({String speaker, Object data})>[];
    String? currentSpeaker;
    final BytesBuilder currentAudioData = BytesBuilder(copy: false);

    for (final Object? entry
        in invocationContext.transcriptionCache ?? const <Object?>[]) {
      if (entry is! TranscriptionEntry) {
        continue;
      }

      final String speaker = (entry.role ?? 'user').toLowerCase();
      final Object data = entry.data;

      if (data is Content) {
        if (currentSpeaker != null) {
          bundledAudio.add((
            speaker: currentSpeaker,
            data: currentAudioData.takeBytes(),
          ));
          currentSpeaker = null;
        }
        bundledAudio.add((speaker: speaker, data: data.copyWith()));
        continue;
      }

      if (data is! InlineData || data.data.isEmpty) {
        continue;
      }

      if (speaker == currentSpeaker) {
        currentAudioData.add(data.data);
      } else {
        if (currentSpeaker != null) {
          bundledAudio.add((
            speaker: currentSpeaker,
            data: currentAudioData.takeBytes(),
          ));
        }
        currentSpeaker = speaker;
        currentAudioData.add(data.data);
      }
    }

    if (currentSpeaker != null) {
      bundledAudio.add((
        speaker: currentSpeaker,
        data: currentAudioData.takeBytes(),
      ));
    }

    invocationContext.transcriptionCache = <Object?>[];

    final List<Content> contents = <Content>[];
    for (final ({String speaker, Object data}) bundle in bundledAudio) {
      if (bundle.data is Content) {
        contents.add((bundle.data as Content).copyWith());
        continue;
      }

      final AudioRecognizer? resolvedRecognizer =
          recognizer ?? _defaultRecognizer;
      if (resolvedRecognizer == null) {
        throw StateError('AudioTranscriber recognizer is not configured.');
      }

      final List<String> transcripts = await resolvedRecognizer(
        bundle.data as List<int>,
      );
      for (final String transcript in transcripts) {
        contents.add(
          Content(role: bundle.speaker, parts: <Part>[Part.text(transcript)]),
        );
      }
    }

    return contents;
  }
}
