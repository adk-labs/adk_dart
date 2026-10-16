import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Unit 7 Parity: Environment, Live Artifacts, and Eval Status', () {
    test('isEnvEnabled truthy values and whitespace trimming', () {
      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': '1'}), isTrue);
      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': 'true'}), isTrue);
      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': 'TRUE'}), isTrue);
      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': 'yes'}), isTrue);
      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': 'YES'}), isTrue);
      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': 'on'}), isTrue);
      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': 'ON'}), isTrue);
      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': ' true '}), isTrue);
      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': ' YES '}), isTrue);
      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': ' 1 '}), isTrue);
      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': ' on '}), isTrue);

      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': '0'}), isFalse);
      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': 'false'}), isFalse);
      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': 'FALSE'}), isFalse);
      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': 'no'}), isFalse);
      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': 'off'}), isFalse);
      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': ''}), isFalse);
      expect(isEnvEnabled('FLAG', environment: <String, String>{'FLAG': '   '}), isFalse);

      expect(isEnvEnabled('FLAG', defaultValue: 'true', environment: <String, String>{}), isTrue);
      expect(isEnvEnabled('FLAG', defaultValue: 'yes', environment: <String, String>{}), isTrue);
      expect(isEnvEnabled('FLAG', defaultValue: 'false', environment: <String, String>{}), isFalse);
    });

    test('isEnterpriseModeEnabled uses strict GenAI boolean parsing', () {
      expect(
        isEnterpriseModeEnabled(
          environment: <String, String>{'GOOGLE_GENAI_USE_ENTERPRISE': 'true'},
        ),
        isTrue,
      );
      expect(
        isEnterpriseModeEnabled(
          environment: <String, String>{'GOOGLE_GENAI_USE_ENTERPRISE': '1'},
        ),
        isTrue,
      );
      expect(
        isEnterpriseModeEnabled(
          environment: <String, String>{'GOOGLE_GENAI_USE_ENTERPRISE': 'TRUE'},
        ),
        isTrue,
      );
      expect(
        isEnterpriseModeEnabled(
          environment: <String, String>{'GOOGLE_GENAI_USE_ENTERPRISE': 'yes'},
        ),
        isFalse,
      );
      expect(
        isEnterpriseModeEnabled(
          environment: <String, String>{'GOOGLE_GENAI_USE_ENTERPRISE': 'on'},
        ),
        isFalse,
      );
      expect(
        isEnterpriseModeEnabled(
          environment: <String, String>{'GOOGLE_GENAI_USE_ENTERPRISE': ' true '},
        ),
        isFalse,
      );

      expect(
        isEnterpriseModeEnabled(
          environment: <String, String>{'GOOGLE_GENAI_USE_VERTEXAI': 'true'},
        ),
        isTrue,
      );
      expect(
        isEnterpriseModeEnabled(
          environment: <String, String>{'GOOGLE_GENAI_USE_VERTEXAI': 'yes'},
        ),
        isFalse,
      );
    });

    test('isAdkLiveArtifactPart detection and filterMediaParts', () {
      final Part liveAudio = Part(
        fileData: FileData(
          fileUri: 'artifact://app/user/session/_adk_live/audio_chunk.pcm#1',
          mimeType: 'audio/pcm',
        ),
      );
      final Part regularDoc = Part(
        fileData: FileData(
          fileUri: 'artifact://app/user/session/document.pdf#1',
          mimeType: 'application/pdf',
        ),
      );
      final Part inlineAudio = Part(
        inlineData: InlineData(mimeType: 'audio/wav', data: <int>[1, 2, 3]),
      );
      final Part textPart = Part.text('Book a table.');

      expect(isAdkLiveArtifactPart(liveAudio), isTrue);
      expect(isAdkLiveArtifactPart(regularDoc), isFalse);
      expect(isAdkLiveArtifactPart(textPart), isFalse);
      expect(isAdkLiveArtifactPart(inlineAudio), isFalse);

      final Content mixed = Content(
        role: 'user',
        parts: <Part>[liveAudio, regularDoc, inlineAudio, textPart],
      );
      final Content? filtered = filterMediaParts(mixed);
      expect(filtered, isNotNull);
      expect(filtered!.parts, hasLength(2));
      expect(filtered.parts[0].fileData?.fileUri, 'artifact://app/user/session/document.pdf#1');
      expect(filtered.parts[1].text, 'Book a table.');

      final Content onlyLive = Content(
        role: 'user',
        parts: <Part>[liveAudio, inlineAudio],
      );
      expect(filterMediaParts(onlyLive), isNull);
    });

    test('getContents excludes internal _adk_live artifact references from model input', () {
      final Part liveRecording = Part(
        fileData: FileData(
          fileUri: 'artifact://app/user/session/_adk_live/live_audio_input_1.pcm#0',
          mimeType: 'audio/pcm',
        ),
      );
      final Event liveEvent = Event(
        invocationId: 'inv-1',
        author: 'user',
        content: Content(
          role: 'user',
          parts: <Part>[liveRecording],
        ),
      );
      final Event normalUserEvent = Event(
        invocationId: 'inv-2',
        author: 'user',
        content: Content(
          role: 'user',
          parts: <Part>[Part.text('Book a table.')],
        ),
      );

      final List<Content> contents = getContents(
        currentBranch: null,
        events: <Event>[normalUserEvent, liveEvent],
      );

      expect(contents, hasLength(1));
      expect(contents.single.parts.single.text, 'Book a table.');
    });
  });
}
