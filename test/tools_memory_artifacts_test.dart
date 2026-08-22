import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:archive/archive.dart';
import 'package:test/test.dart';

Future<Context> _newToolContext({
  required BaseMemoryService memoryService,
  required BaseArtifactService artifactService,
  Content? userContent,
}) async {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'app',
    userId: 'u1',
    sessionId: 's_tool_ctx',
  );
  return Context(
    InvocationContext(
      sessionService: sessionService,
      artifactService: artifactService,
      memoryService: memoryService,
      invocationId: 'inv_tool_ctx',
      agent: Agent(
        name: 'root_agent',
        model: _NoopModel(),
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      ),
      session: session,
      userContent: userContent,
    ),
  );
}

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

void main() {
  test(
    'LoadMemoryTool returns matched memories and appends instruction',
    () async {
      final InMemoryMemoryService memoryService = InMemoryMemoryService();
      await memoryService.addSessionToMemory(
        Session(
          id: 's_mem',
          appName: 'app',
          userId: 'u1',
          events: <Event>[
            Event(
              invocationId: 'inv_mem',
              author: 'user',
              content: Content.userText('hello memory'),
            ),
          ],
        ),
      );

      final Context toolContext = await _newToolContext(
        memoryService: memoryService,
        artifactService: InMemoryArtifactService(),
      );
      final LoadMemoryTool tool = LoadMemoryTool();
      final Object? result = await tool.run(
        args: <String, dynamic>{'query': 'hello'},
        toolContext: toolContext,
      );

      expect(result, isA<Map<String, Object?>>());
      expect((result! as Map<String, Object?>)['memories'], isNotEmpty);

      final LlmRequest request = LlmRequest();
      await tool.processLlmRequest(
        toolContext: toolContext,
        llmRequest: request,
      );
      expect(request.config.systemInstruction, contains('load_memory'));
    },
  );

  test('PreloadMemoryTool inserts past conversation instruction', () async {
    final InMemoryMemoryService memoryService = InMemoryMemoryService();
    await memoryService.addSessionToMemory(
      Session(
        id: 's_mem_preload',
        appName: 'app',
        userId: 'u1',
        events: <Event>[
          Event(
            invocationId: 'inv_mem',
            author: 'assistant',
            content: Content(role: 'model', parts: <Part>[Part.text('stored')]),
          ),
        ],
      ),
    );

    final Context toolContext = await _newToolContext(
      memoryService: memoryService,
      artifactService: InMemoryArtifactService(),
      userContent: Content.userText('stored'),
    );
    final PreloadMemoryTool tool = PreloadMemoryTool();
    final LlmRequest request = LlmRequest();

    await tool.processLlmRequest(toolContext: toolContext, llmRequest: request);
    expect(request.config.systemInstruction, contains('<PAST_CONVERSATIONS>'));
    expect(request.config.systemInstruction, contains('stored'));
    expect(request.config.systemInstruction, isNot(startsWith('\n')));
    expect(request.config.systemInstruction, isNot(contains('memory: stored')));
  });

  test(
    'LoadArtifactsTool appends requested artifacts to request contents',
    () async {
      final Context toolContext = await _newToolContext(
        memoryService: InMemoryMemoryService(),
        artifactService: InMemoryArtifactService(),
      );
      await toolContext.saveArtifact('report.txt', Part.text('artifact-body'));

      final LoadArtifactsTool tool = LoadArtifactsTool();
      final LlmRequest request = LlmRequest(
        contents: <Content>[
          Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'load_artifacts',
                response: <String, dynamic>{
                  'artifact_names': <String>['report.txt'],
                },
              ),
            ],
          ),
        ],
      );

      await tool.processLlmRequest(
        toolContext: toolContext,
        llmRequest: request,
      );

      expect(
        request.config.systemInstruction,
        startsWith('You have a list of artifacts:\n  ["report.txt"]'),
      );
      final bool hasArtifactBody = request.contents.any(
        (Content content) => content.parts.any(
          (Part part) =>
              part.text != null && part.text!.contains('artifact-body'),
        ),
      );
      expect(hasArtifactBody, isTrue);
    },
  );

  test(
    'LoadArtifactsTool converts unsupported inline mime artifacts to text',
    () async {
      final Context toolContext = await _newToolContext(
        memoryService: InMemoryMemoryService(),
        artifactService: InMemoryArtifactService(),
      );
      await toolContext.saveArtifact(
        'table.csv',
        Part.fromInlineData(
          mimeType: 'application/csv',
          data: utf8.encode('col1,col2\n1,2\n'),
        ),
      );

      final LoadArtifactsTool tool = LoadArtifactsTool();
      final LlmRequest request = LlmRequest(
        contents: <Content>[
          Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'load_artifacts',
                response: <String, dynamic>{
                  'artifact_names': <String>['table.csv'],
                },
              ),
            ],
          ),
        ],
      );

      await tool.processLlmRequest(
        toolContext: toolContext,
        llmRequest: request,
      );

      final Content appended = request.contents.last;
      expect(appended.parts.first.text, 'Artifact table.csv is:');
      expect(appended.parts[1].inlineData, isNull);
      expect(appended.parts[1].text, 'col1,col2\n1,2\n');
    },
  );

  test(
    'LoadArtifactsTool keeps supported inline and fileData artifacts',
    () async {
      final Context toolContext = await _newToolContext(
        memoryService: InMemoryMemoryService(),
        artifactService: InMemoryArtifactService(),
      );
      await toolContext.saveArtifact(
        'paper.pdf',
        Part.fromInlineData(
          mimeType: 'application/pdf',
          data: <int>[37, 80, 68, 70],
        ),
      );
      await toolContext.saveArtifact(
        'audio.ref',
        Part.fromFileData(
          fileUri: 'gs://bucket/path/audio.mp3',
          mimeType: 'audio/mpeg',
        ),
      );

      final LoadArtifactsTool tool = LoadArtifactsTool();
      final LlmRequest request = LlmRequest(
        contents: <Content>[
          Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'load_artifacts',
                response: <String, dynamic>{
                  'artifact_names': <String>['paper.pdf', 'audio.ref'],
                },
              ),
            ],
          ),
        ],
      );

      await tool.processLlmRequest(
        toolContext: toolContext,
        llmRequest: request,
      );

      final List<Content> appended = request.contents.skip(1).toList();
      expect(appended, hasLength(2));
      expect(appended[0].parts.first.text, 'Artifact paper.pdf is:');
      expect(appended[0].parts[1].inlineData, isNotNull);
      expect(appended[0].parts[1].inlineData!.mimeType, 'application/pdf');

      expect(appended[1].parts.first.text, 'Artifact audio.ref is:');
      expect(appended[1].parts[1].fileData, isNotNull);
      expect(
        appended[1].parts[1].fileData!.fileUri,
        'gs://bucket/path/audio.mp3',
      );
      expect(appended[1].parts[1].fileData!.mimeType, 'audio/mpeg');
    },
  );

  test(
    'LoadArtifactsTool extracts DOCX files successfully',
    () async {
      final Context toolContext = await _newToolContext(
        memoryService: InMemoryMemoryService(),
        artifactService: InMemoryArtifactService(),
      );

      final Archive archive = Archive();
      final String xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
          '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\n'
          '  <w:body>\n'
          '    <w:p>\n'
          '      <w:r>\n'
          '        <w:t>Hello from DOCX!</w:t>\n'
          '      </w:r>\n'
          '    </w:p>\n'
          '  </w:body>\n'
          '</w:document>';
      final List<int> xmlBytes = utf8.encode(xml);
      archive.addFile(ArchiveFile('word/document.xml', xmlBytes.length, xmlBytes));
      final List<int> zipBytes = ZipEncoder().encode(archive);

      await toolContext.saveArtifact(
        'doc.docx',
        Part.fromInlineData(
          mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          data: zipBytes,
        ),
      );

      final LoadArtifactsTool tool = LoadArtifactsTool();
      final LlmRequest request = LlmRequest(
        contents: <Content>[
          Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'load_artifacts',
                response: <String, dynamic>{
                  'artifact_names': <String>['doc.docx'],
                },
              ),
            ],
          ),
        ],
      );

      await tool.processLlmRequest(
        toolContext: toolContext,
        llmRequest: request,
      );

      final Content appended = request.contents.last;
      expect(appended.parts.first.text, 'Artifact doc.docx is:');
      expect(appended.parts[1].text, 'Hello from DOCX!');
    },
  );

  test(
    'LoadArtifactsTool extracts XLSX spreadsheet files when enabled',
    () async {
      final InvocationContext invocationContext = InvocationContext(
        invocationId: 'inv-spreadsheet',
        session: Session(id: 's-spreadsheet', appName: 'app', userId: 'user'),
        agent: LlmAgent(name: 'agent'),
        artifactService: InMemoryArtifactService(),
        sessionService: InMemorySessionService(),
      );
      final Context toolContext = Context(
        invocationContext,
        functionCallId: 'call-xlsx',
      );

      final Archive archive = Archive();
      archive.addFile(
        ArchiveFile(
          'xl/sharedStrings.xml',
          utf8.encode('<sst><si><t>Header1</t></si><si><t>Header2</t></si></sst>').length,
          utf8.encode('<sst><si><t>Header1</t></si><si><t>Header2</t></si></sst>'),
        ),
      );
      archive.addFile(
        ArchiveFile(
          'xl/worksheets/sheet1.xml',
          utf8.encode('<sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row></sheetData>').length,
          utf8.encode('<sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row></sheetData>'),
        ),
      );
      final List<int> zipBytes = ZipEncoder().encode(archive);

      await toolContext.saveArtifact(
        'data.xlsx',
        Part.fromInlineData(
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          data: zipBytes,
        ),
      );

      final LoadArtifactsTool tool = LoadArtifactsTool(
        enableSpreadsheetParsing: true,
      );
      final LlmRequest request = LlmRequest(
        contents: <Content>[
          Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'load_artifacts',
                response: <String, dynamic>{
                  'artifact_names': <String>['data.xlsx'],
                },
              ),
            ],
          ),
        ],
      );

      await tool.processLlmRequest(
        toolContext: toolContext,
        llmRequest: request,
      );

      final Content appended = request.contents.last;
      expect(appended.parts.first.text, 'Artifact data.xlsx is:');
      expect(appended.parts[1].text, equals('Header1\tHeader2'));
    },
  );

  test(
    'LoadArtifactsTool uses custom processArtifact callback when provided',
    () async {
      final InvocationContext invocationContext = InvocationContext(
        invocationId: 'inv-proc',
        session: Session(id: 's-proc', appName: 'app', userId: 'user'),
        agent: LlmAgent(name: 'agent'),
        artifactService: InMemoryArtifactService(),
        sessionService: InMemorySessionService(),
      );
      final Context toolContext = Context(
        invocationContext,
        functionCallId: 'call-proc',
      );

      await toolContext.saveArtifact(
        'custom.txt',
        Part.text('original content'),
      );

      final LoadArtifactsTool tool = LoadArtifactsTool(
        processArtifact: (Part part, String name) async {
          return Part.text('custom-processed: $name -> ${part.text}');
        },
      );

      final LlmRequest request = LlmRequest(
        contents: <Content>[
          Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'load_artifacts',
                response: <String, dynamic>{
                  'artifact_names': <String>['custom.txt'],
                },
              ),
            ],
          ),
        ],
      );

      await tool.processLlmRequest(
        toolContext: toolContext,
        llmRequest: request,
      );

      final Content appended = request.contents.last;
      expect(appended.parts.first.text, 'Artifact custom.txt is:');
      expect(appended.parts[1].text, 'custom-processed: custom.txt -> original content');
    },
  );
}
