import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

class _AccessibleArtifactService extends InMemoryArtifactService {
  @override
  Future<ArtifactVersion?> getArtifactVersion({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    final ArtifactVersion? value = await super.getArtifactVersion(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
      version: version,
    );
    if (value == null) {
      return null;
    }
    return value.copyWith(
      canonicalUri:
          'https://example.com/$filename?v=${version ?? value.version}',
    );
  }
}

InvocationContext _newContext({BaseArtifactService? artifactService}) {
  return InvocationContext(
    artifactService: artifactService,
    sessionService: InMemorySessionService(),
    invocationId: 'inv_save_files',
    agent: LlmAgent(
      name: 'root_agent',
      model: _NoopModel(),
      disallowTransferToParent: true,
      disallowTransferToPeers: true,
    ),
    session: Session(id: 's1', appName: 'app', userId: 'u1'),
  );
}

void main() {
  test(
    'returns user message untouched when artifact service is absent',
    () async {
      final SaveFilesAsArtifactsPlugin plugin = SaveFilesAsArtifactsPlugin();
      final Content message = Content.userText('hello');

      final Content? output = await plugin.onUserMessageCallback(
        invocationContext: _newContext(),
        userMessage: message,
      );

      expect(output, isNotNull);
      expect(output?.parts.single.text, 'hello');
    },
  );

  test(
    'saves inline file and inserts placeholder when URI is not model-accessible',
    () async {
      final InMemoryArtifactService artifacts = InMemoryArtifactService();
      final SaveFilesAsArtifactsPlugin plugin = SaveFilesAsArtifactsPlugin();
      final InvocationContext context = _newContext(artifactService: artifacts);
      final Content message = Content(
        role: 'user',
        parts: <Part>[
          Part.fromInlineData(
            mimeType: 'text/plain',
            data: <int>[1, 2, 3],
            displayName: 'notes.txt',
          ),
        ],
      );

      final Content? output = await plugin.onUserMessageCallback(
        invocationContext: context,
        userMessage: message,
      );

      expect(output, isNotNull);
      expect(output!.parts, hasLength(1));
      expect(output.parts.single.text, '[Uploaded Artifact: "notes.txt"]');

      final List<String> keys = await artifacts.listArtifactKeys(
        appName: context.appName,
        userId: context.userId,
        sessionId: context.session.id,
      );
      expect(keys, contains('notes.txt'));
    },
  );

  test(
    'adds file reference part when artifact URI is model-accessible',
    () async {
      final _AccessibleArtifactService artifacts = _AccessibleArtifactService();
      final SaveFilesAsArtifactsPlugin plugin = SaveFilesAsArtifactsPlugin();
      final InvocationContext context = _newContext(artifactService: artifacts);
      final Content message = Content(
        role: 'user',
        parts: <Part>[
          Part.fromInlineData(
            mimeType: 'application/pdf',
            data: <int>[7, 8],
            displayName: 'doc.pdf',
          ),
        ],
      );

      final Content? output = await plugin.onUserMessageCallback(
        invocationContext: context,
        userMessage: message,
      );

      expect(output, isNotNull);
      expect(output!.parts, hasLength(2));
      expect(output.parts.first.text, '[Uploaded Artifact: "doc.pdf"]');
      final FileData? fileData = output.parts[1].fileData;
      expect(fileData, isNotNull);
      expect(fileData!.fileUri, startsWith('https://example.com/doc.pdf'));
      expect(fileData.mimeType, 'application/pdf');
      expect(fileData.displayName, 'doc.pdf');
    },
  );

  test(
    'generates fallback artifact filename when display name is absent',
    () async {
      final InMemoryArtifactService artifacts = InMemoryArtifactService();
      final SaveFilesAsArtifactsPlugin plugin = SaveFilesAsArtifactsPlugin();
      final InvocationContext context = _newContext(artifactService: artifacts);
      final Content message = Content(
        role: 'user',
        parts: <Part>[
          Part.fromInlineData(mimeType: 'text/plain', data: <int>[1]),
        ],
      );

      final Content? output = await plugin.onUserMessageCallback(
        invocationContext: context,
        userMessage: message,
      );

      expect(output, isNotNull);
      expect(output!.parts.single.text, contains('artifact_inv_save_files_0'));

      final List<String> keys = await artifacts.listArtifactKeys(
        appName: context.appName,
        userId: context.userId,
        sessionId: context.session.id,
      );
      expect(keys.single, 'artifact_inv_save_files_0');
    },
  );
}
