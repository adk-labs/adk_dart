import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adk_dart/src/agents/context.dart';
import 'package:adk_dart/src/agents/invocation_context.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/artifacts/base_artifact_service.dart';
import 'package:adk_dart/src/errors/input_validation_error.dart';
import 'package:adk_dart/src/events/event.dart';
import 'package:adk_dart/src/features/_feature_registry.dart';
import 'package:adk_dart/src/integrations/daytona/daytona_environment.dart';
import 'package:adk_dart/src/integrations/e2b/e2b_environment.dart';
import 'package:adk_dart/src/integrations/fsspec/fsspec.dart';
import 'package:adk_dart/src/integrations/oci/oci.dart';
import 'package:adk_dart/src/integrations/opensandbox/opensandbox_environment.dart';
import 'package:adk_dart/src/integrations/vmaas/agent_engine_environment.dart';
import 'package:adk_dart/src/labs/antigravity/antigravity.dart';
import 'package:adk_dart/src/live/live.dart';
import 'package:adk_dart/src/memory/base_memory_service.dart';
import 'package:adk_dart/src/memory/in_memory_memory_service.dart';
import 'package:adk_dart/src/memory/memory_entry.dart';
import 'package:adk_dart/src/memory/vertex_ai_rag_memory_service.dart';
import 'package:adk_dart/src/models/anthropic_llm.dart';
import 'package:adk_dart/src/models/base_llm.dart';
import 'package:adk_dart/src/models/google_llm.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/models/llm_response.dart';
import 'package:adk_dart/src/optimization/data_types.dart';
import 'package:adk_dart/src/optimization/local_eval_sampler.dart';
import 'package:adk_dart/src/sessions/in_memory_session_service.dart';
import 'package:adk_dart/src/sessions/session.dart';
import 'package:adk_dart/src/tools/base_tool.dart';
import 'package:adk_dart/src/tools/environment/environment.dart';
import 'package:adk_dart/src/tools/retrieval/vertex_ai_rag_retrieval.dart';
import 'package:adk_dart/src/types/content.dart';
import 'package:adk_dart/src/utils/client_labels_utils.dart';
import 'package:adk_dart/src/version.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Shared helpers & fakes
// ---------------------------------------------------------------------------

Context _makeContext({String invocationId = 'inv_nov12'}) {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: invocationId,
    agent: LlmAgent(name: 'root', instruction: 'root'),
    session: Session(id: 'session_1', appName: 'app', userId: 'user_1'),
  );
  return Context(invocationContext);
}

class _ContextCapturingEnvironment extends BaseEnvironment {
  _ContextCapturingEnvironment({Directory? workingDirectory})
    : super(workingDirectory: workingDirectory ?? Directory('/workspace'));

  final List<(String, Context?)> calls = <(String, Context?)>[];
  int initCount = 0;
  int closeCount = 0;
  Completer<void>? initGate;
  Object? initError;
  final Map<String, List<int>> files = <String, List<int>>{};

  @override
  Future<void> initialize({Context? ctx}) async {
    calls.add(('initialize', ctx));
    initCount += 1;
    if (initGate != null) {
      await initGate!.future;
    }
    if (initError != null) {
      throw initError!;
    }
    isInitialized = true;
  }

  @override
  Future<void> close() async {
    calls.add(('close', null));
    closeCount += 1;
    isInitialized = false;
  }

  @override
  Future<EnvironmentExecutionResult> execute(
    String command, {
    Duration? timeout,
    Context? ctx,
  }) async {
    calls.add(('execute:$command', ctx));
    return EnvironmentExecutionResult(
      exitCode: 0,
      stdout: 'ran:$command',
      stderr: '',
    );
  }

  @override
  Future<List<int>> readFile(Object path, {Context? ctx}) async {
    final String key = path is File ? path.path : '$path';
    calls.add(('readFile:$key', ctx));
    final List<int>? bytes = files[key];
    if (bytes == null) {
      throw FileSystemException('File not found', key);
    }
    return List<int>.from(bytes);
  }

  @override
  Future<void> writeFile(
    Object path,
    Object content, {
    Context? ctx,
  }) async {
    final String key = path is File ? path.path : '$path';
    calls.add(('writeFile:$key', ctx));
    if (content is String) {
      files[key] = utf8.encode(content);
    } else if (content is List<int>) {
      files[key] = List<int>.from(content);
    } else {
      throw ArgumentError.value(content, 'content');
    }
  }
}

class _FakeHttpClient extends http.BaseClient {
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final String path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/file')) {
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('daytona-file')),
        200,
      );
    }
    Map<String, Object?> payload = <String, Object?>{'id': 'daytona-sbx-1'};
    if (path.endsWith('/execute')) {
      payload = <String, Object?>{'exitCode': 0, 'stdout': 'daytona-ok'};
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(payload))),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}

class _FakeOpenSandboxClient implements OpenSandboxClient {
  final Map<String, Uint8List> files = <String, Uint8List>{};

  @override
  Future<String> createOrAttachSandbox({
    required String image,
    Duration? timeout,
    Map<String, String>? envVars,
  }) async => 'sbx-open-1';

  @override
  Future<EnvironmentExecutionResult> execute({
    required String sandboxId,
    required String command,
    String? workingDir,
    Duration? timeout,
    Map<String, String>? envVars,
  }) async =>
      const EnvironmentExecutionResult(exitCode: 0, stdout: 'open-ok');

  @override
  Future<Uint8List> readFile({
    required String sandboxId,
    required String path,
  }) async => files[path] ?? Uint8List(0);

  @override
  Future<void> writeFile({
    required String sandboxId,
    required String path,
    required List<int> bytes,
  }) async {
    files[path] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> closeSandbox(String sandboxId) async {}
}

ShellBackedAgentEngineSandboxClient _makeFakeAgentEngineClient() {
  final Map<String, Uint8List> files = <String, Uint8List>{};
  return ShellBackedAgentEngineSandboxClient(
    commandRunner: ({
      required String sandboxResourceName,
      required String command,
      String? workingDir,
      Duration? timeout,
      Map<String, String>? envVars,
    }) async {
      if (command.contains('base64 -d >')) {
        files['/workspace/ae.txt'] = Uint8List.fromList(utf8.encode('ae-data'));
        return const EnvironmentExecutionResult(exitCode: 0);
      }
      if (command.contains('stat -L -c %s')) {
        final int len = files['/workspace/ae.txt']?.length ?? 0;
        return EnvironmentExecutionResult(exitCode: 0, stdout: '$len\n');
      }
      if (command.startsWith('dd if=') || command.startsWith('base64 <')) {
        return EnvironmentExecutionResult(
          exitCode: 0,
          stdout: base64Encode(files['/workspace/ae.txt'] ?? const <int>[]),
        );
      }
      return const EnvironmentExecutionResult(exitCode: 0, stdout: 'ae-ok');
    },
  );
}

class _FakeWindowsFileStore extends InMemoryFsspecFilesystem {
  _FakeWindowsFileStore() : super(protocol: const <String>['file', 'local']);

  @override
  bool get autoMkdir => false;

  @override
  String stripProtocol(String path) {
    String stripped = path;
    if (stripped.startsWith('file:///')) {
      stripped = stripped.substring('file:///'.length);
    } else if (stripped.startsWith('file://')) {
      stripped = stripped.substring('file://'.length);
    }
    return stripped.replaceAll(r'\', '/').replaceAll(RegExp(r'/+$'), '');
  }

  @override
  String unstripProtocol(String path) {
    final String stripped = stripProtocol(path);
    return 'file://$stripped';
  }
}

class _FakeRapidStream extends FsspecWriteStream {
  _FakeRapidStream({
    required this.store,
    required this.key,
  });

  final InMemoryFsspecFilesystem store;
  final String key;

  Object? _aaow;
  final BytesBuilder _buf = BytesBuilder(copy: false);

  @override
  Object? get aaow => _aaow;

  void _ensureCreated() {
    if (_aaow != null) {
      return;
    }
    if (store.objects.containsKey(key)) {
      throw const GcsPreconditionError('generation=0 precondition failed');
    }
    _aaow = Object();
    store.putFile(key, const <int>[]);
  }

  @override
  void write(List<int> bytes) {
    _ensureCreated();
    _buf.add(bytes);
  }

  @override
  void close() {
    if (closed) {
      return;
    }
    _ensureCreated();
    closed = true;
    store.putFile(key, _buf.takeBytes());
  }
}

class _FakeRapidGcsStore extends InMemoryFsspecFilesystem {
  _FakeRapidGcsStore({
    this.setxattrsError,
    this.rmError,
    this.prepopulateOnFirstOpen = false,
  }) : super(protocol: const <String>['gs', 'gcs']);

  final Object? setxattrsError;
  final Object? rmError;
  final bool prepopulateOnFirstOpen;

  int openCalls = 0;
  int pipeFileCalls = 0;
  final List<(String, int?, bool)> openArgs = <(String, int?, bool)>[];
  final List<(String, String?, Map<String, String>?)> setxattrsCalls =
      <(String, String?, Map<String, String>?)>[];

  @override
  (String, String, Object?)? splitPath(String path) {
    final String stripped = stripProtocol(path);
    final int slash = stripped.indexOf('/');
    if (slash < 0) {
      return (stripped, '', null);
    }
    return (stripped.substring(0, slash), stripped.substring(slash + 1), null);
  }

  @override
  String? syncLookupBucketType(String bucket) => 'ZONAL_HIERARCHICAL';

  @override
  void pipeFile(
    String path,
    List<int> data, {
    String mode = 'overwrite',
    String? contentType,
    Map<String, String>? metadata,
  }) {
    pipeFileCalls += 1;
    super.pipeFile(
      path,
      data,
      mode: mode,
      contentType: contentType,
      metadata: metadata,
    );
  }

  @override
  FsspecWriteStream openWrite(
    String path, {
    String mode = 'wb',
    int? generation,
    bool finalizeOnClose = false,
  }) {
    openCalls += 1;
    final String normalized = stripProtocol(path);
    openArgs.add((normalized, generation, finalizeOnClose));
    if (prepopulateOnFirstOpen && openCalls == 1) {
      putFile(normalized, utf8.encode('concurrent-winner'));
    }
    return _FakeRapidStream(store: this, key: normalized);
  }

  @override
  void setxattrs(
    String path, {
    String? contentType,
    Map<String, String>? metadata,
  }) {
    setxattrsCalls.add((stripProtocol(path), contentType, metadata));
    if (setxattrsError != null) {
      throw setxattrsError!;
    }
    super.setxattrs(path, contentType: contentType, metadata: metadata);
  }

  @override
  void rmFile(String path) {
    if (rmError != null) {
      throw rmError!;
    }
    super.rmFile(path);
  }
}

class _FakeStreamOciClient implements OciGenAiClient {
  _FakeStreamOciClient(this.events);

  final List<Map<String, Object?>> events;

  @override
  Future<Map<String, Object?>> chat(Map<String, Object?> chatDetails) {
    throw UnimplementedError();
  }

  @override
  Stream<Map<String, Object?>> chatStream(
    Map<String, Object?> chatDetails,
  ) async* {
    for (final Map<String, Object?> event in events) {
      yield event;
    }
  }
}

class _RecordingCascadeLlm extends BaseLlm {
  _RecordingCascadeLlm({super.model = 'custom-llm', List<String>? replies})
    : _replies = replies ?? <String>['ok'];

  final List<String> _replies;
  final List<LlmRequest> requests = <LlmRequest>[];
  final List<List<String>> zoneLabelsPerCall = <List<String>>[];
  int _callIdx = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    requests.add(request);
    zoneLabelsPerCall.add(getClientLabels(environment: const <String, String>{}));
    final String text = _replies[_callIdx < _replies.length ? _callIdx : 0];
    _callIdx += 1;
    yield LlmResponse(
      content: Content.modelText(text),
      partial: true,
    );
    yield LlmResponse(
      content: Content.modelText(text),
      turnComplete: true,
    );
  }
}

class _IdleStt extends LiveIngress {
  @override
  Stream<IngressEvent> call(Stream<InlineData> audio) async* {
    await for (final InlineData _ in audio) {
      // Drain until audio input closes.
    }
  }
}

class _EchoTts extends LiveEgress {
  @override
  Stream<EgressEvent> call(
    Stream<String> text, {
    required CancelSignal cancel,
  }) async* {
    final StringBuffer full = StringBuffer();
    await for (final String chunk in text) {
      if (cancel.isSet) {
        return;
      }
      full.write(chunk);
    }
    if (!cancel.isSet && full.isNotEmpty) {
      yield AudioChunk(
        blob: InlineData(
          mimeType: 'audio/pcm;rate=24000',
          data: List<int>.filled(480, 0),
        ),
      );
      yield AgentSpokenOutput(text: full.toString());
    }
  }
}

class _FakeRagClient implements VertexAiRagClient {
  int closeCalls = 0;
  final List<String?> corporaQueried = <String?>[];

  @override
  Future<void> uploadFile({
    required String corpusName,
    required String text,
    required String displayName,
  }) async {}

  @override
  Future<VertexAiRagRetrievalResponse> retrievalQuery({
    required String text,
    List<VertexRagStoreRagResource>? ragResources,
    List<String>? ragCorpora,
    int? similarityTopK,
    double? vectorDistanceThreshold,
  }) async {
    corporaQueried.add(
      ragResources?.firstOrNull?.ragCorpus ?? ragCorpora?.firstOrNull,
    );
    return VertexAiRagRetrievalResponse(
      contexts: <VertexAiRagContext>[
        VertexAiRagContext(
          text: '1700000000.0:{"author":"agent","text":"matched $text"}',
          sourceDisplayName: 'app.user.session',
        ),
      ],
    );
  }

  void close() {
    closeCalls += 1;
  }
}

class _StubAnthropicTransport implements AnthropicRestTransport {
  _StubAnthropicTransport({
    this.nonStreamResponse,
    this.streamEvents = const <Map<String, Object?>>[],
  });

  final Map<String, Object?>? nonStreamResponse;
  final List<Map<String, Object?>> streamEvents;

  @override
  Future<Map<String, Object?>> createMessage({
    required Map<String, Object?> request,
    required String apiKey,
    required String baseUrl,
    required String apiVersion,
    required Map<String, String> headers,
  }) async {
    return nonStreamResponse ?? <String, Object?>{};
  }

  @override
  Stream<Map<String, Object?>> streamMessage({
    required Map<String, Object?> request,
    required String apiKey,
    required String baseUrl,
    required String apiVersion,
    required Map<String, String> headers,
  }) async* {
    for (final Map<String, Object?> event in streamEvents) {
      yield event;
    }
  }
}

void _assertNoPropertyLevelRequiredTrue(Object? schemaNode, [String path = '']) {
  if (schemaNode is Map) {
    final Object? props = schemaNode['properties'];
    if (props is Map) {
      props.forEach((Object? propName, Object? propSchema) {
        if (propSchema is Map) {
          expect(
            propSchema.containsKey('required') && propSchema['required'] is bool,
            isFalse,
            reason:
                'Property "$path.$propName" must not emit boolean required: true inside field schema.',
          );
        }
        _assertNoPropertyLevelRequiredTrue(propSchema, '$path.$propName');
      });
    }
    schemaNode.forEach((Object? key, Object? value) {
      if (key != 'properties') {
        _assertNoPropertyLevelRequiredTrue(value, '$path/$key');
      }
    });
  } else if (schemaNode is List) {
    for (int i = 0; i < schemaNode.length; i++) {
      _assertNoPropertyLevelRequiredTrue(schemaNode[i], '$path[$i]');
    }
  }
}

void main() {
  // =========================================================================
  // 1. Environments & Environment Toolset (1bd22e34d, 61efa3003)
  // =========================================================================
  group('1. Environments & Environment Toolset (1bd22e34d, 61efa3003)', () {
    test(
      'BaseEnvironment and all built-in/sandbox environments accept {Context? ctx}',
      () async {
        final Context ctx = _makeContext(invocationId: 'inv_ctx_pass');
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'adk_local_env_',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        // LocalEnvironment
        final LocalEnvironment localEnv = LocalEnvironment(
          workingDirectory: tempDir,
        );
        expect(localEnv.isInitialized, isFalse);
        await localEnv.initialize(ctx: ctx);
        expect(localEnv.isInitialized, isTrue);
        await localEnv.writeFile('hello.txt', 'local-ctx', ctx: ctx);
        final List<int> localBytes = await localEnv.readFile(
          'hello.txt',
          ctx: ctx,
        );
        expect(utf8.decode(localBytes), 'local-ctx');
        final List<int> streamedBytes = await localEnv
            .readFileStream('hello.txt', ctx: ctx)
            .expand((List<int> chunk) => chunk)
            .toList();
        expect(utf8.decode(streamedBytes), 'local-ctx');
        final EnvironmentExecutionResult localExec = await localEnv.execute(
          'echo hi',
          ctx: ctx,
        );
        expect(localExec.exitCode, 0);
        await localEnv.close();
        expect(localEnv.isInitialized, isFalse);

        // DaytonaEnvironment
        final _FakeHttpClient httpClient = _FakeHttpClient();
        final DaytonaEnvironment daytonaEnv = DaytonaEnvironment(
          apiKey: 'test-key',
          httpClient: httpClient,
        );
        await daytonaEnv.initialize(ctx: ctx);
        expect(daytonaEnv.isInitialized, isTrue);
        await daytonaEnv.writeFile('/home/daytona/a.txt', 'abc', ctx: ctx);
        expect(
          utf8.decode(
            await daytonaEnv.readFile('/home/daytona/a.txt', ctx: ctx),
          ),
          'daytona-file',
        );
        expect((await daytonaEnv.execute('ls', ctx: ctx)).exitCode, 0);
        await daytonaEnv.close();
        expect(daytonaEnv.isInitialized, isFalse);

        // E2BEnvironment (in-memory default client)
        final E2BEnvironment e2bEnv = E2BEnvironment(apiKey: 'e2b-key');
        await e2bEnv.initialize(ctx: ctx);
        expect(e2bEnv.isInitialized, isTrue);
        await e2bEnv.writeFile('/home/user/f.txt', 'e2b-data', ctx: ctx);
        expect(
          utf8.decode(await e2bEnv.readFile('/home/user/f.txt', ctx: ctx)),
          'e2b-data',
        );
        expect((await e2bEnv.execute('pwd', ctx: ctx)).exitCode, 0);
        await e2bEnv.close();
        expect(e2bEnv.isInitialized, isFalse);

        // OpenSandboxEnvironment
        final OpenSandboxEnvironment openEnv = OpenSandboxEnvironment(
          sandboxId: 'sbx-1',
          client: _FakeOpenSandboxClient(),
        );
        await openEnv.initialize(ctx: ctx);
        expect(openEnv.isInitialized, isTrue);
        await openEnv.writeFile('/workspace/o.txt', 'open-data', ctx: ctx);
        expect(
          utf8.decode(await openEnv.readFile('/workspace/o.txt', ctx: ctx)),
          'open-data',
        );
        expect((await openEnv.execute('ls', ctx: ctx)).exitCode, 0);
        await openEnv.close();
        expect(openEnv.isInitialized, isFalse);

        // AgentEngineEnvironment
        final AgentEngineEnvironment aeEnv = AgentEngineEnvironment(
          agentEngineResourceName: 'projects/p/locations/l/reasoningEngines/1',
          client: _makeFakeAgentEngineClient(),
        );
        await aeEnv.initialize(ctx: ctx);
        expect(aeEnv.isInitialized, isTrue);
        await aeEnv.writeFile('/workspace/ae.txt', 'ae-data', ctx: ctx);
        expect(
          utf8.decode(await aeEnv.readFile('/workspace/ae.txt', ctx: ctx)),
          'ae-data',
        );
        expect((await aeEnv.execute('ls', ctx: ctx)).exitCode, 0);
        await aeEnv.close();
        expect(aeEnv.isInitialized, isFalse);
      },
    );

    test(
      'ensureInitialized serializes concurrent calls, supports cancellation, and retries after error',
      () async {
        final _ContextCapturingEnvironment env = _ContextCapturingEnvironment();
        final Context ctx1 = _makeContext(invocationId: 'inv_1');
        final Context ctx2 = _makeContext(invocationId: 'inv_2');

        env.initGate = Completer<void>();
        final Future<void> first = ensureInitialized(env, ctx1);
        expect(hasEnvironmentLock(env), isTrue);

        // Cancelled waiter leaves lock usable for subsequent callers.
        final Completer<void> cancel = Completer<void>();
        final Future<void> cancelledWaiter = ensureInitialized(
          env,
          ctx2,
          cancel.future,
        );
        cancel.complete();
        await expectLater(
          cancelledWaiter,
          throwsA(isA<EnvironmentLockCancelledException>()),
        );

        final Future<void> third = ensureInitialized(env, ctx2);
        env.initGate!.complete();
        await Future.wait(<Future<void>>[first, third]);
        expect(env.initCount, 2);
        expect(env.isInitialized, isTrue);

        await closeIfInitialized(env);
        expect(env.closeCount, 1);
        expect(env.isInitialized, isFalse);

        // Calling closeIfInitialized again is a no-op.
        await closeIfInitialized(env);
        expect(env.closeCount, 1);

        // Failed initialization allows retry.
        env.initGate = null;
        env.initError = StateError('transient init failure');
        await expectLater(ensureInitialized(env, ctx1), throwsStateError);
        expect(env.isInitialized, isFalse);

        env.initError = null;
        await ensureInitialized(env, ctx2);
        expect(env.isInitialized, isTrue);
      },
    );

    test(
      'EnvironmentToolset defers initialization to tool calls and injects working_dir only after init',
      () async {
        final _ContextCapturingEnvironment env = _ContextCapturingEnvironment(
          workingDirectory: Directory('/workspace/proj'),
        );
        final EnvironmentToolset toolset = EnvironmentToolset(environment: env);
        final Context ctx = _makeContext(invocationId: 'inv_lazy_tools');

        // getTools() and processLlmRequest() BEFORE tool calls do NOT initialize.
        final List<BaseTool> tools = await toolset.getTools(
          readonlyContext: ctx,
        );
        expect(env.initCount, 0);
        expect(env.isInitialized, isFalse);

        final LlmRequest reqBefore = LlmRequest(model: 'gemini-2.5-flash');
        await toolset.processLlmRequest(
          toolContext: ctx,
          llmRequest: reqBefore,
        );
        expect(env.initCount, 0);
        expect(reqBefore.config.systemInstruction, environmentInstruction);
        expect(
          reqBefore.config.systemInstruction,
          isNot(contains('Your environment is at')),
        );

        final Map<String, BaseTool> byName = <String, BaseTool>{
          for (final BaseTool t in tools) t.name: t,
        };

        // Invalid input validation happens BEFORE ensureInitialized!
        final Object? badExec = await byName['Execute']!.run(
          args: <String, dynamic>{},
          toolContext: ctx,
        );
        expect((badExec as Map<String, Object?>)['status'], 'error');
        expect(env.initCount, 0);

        // Valid WriteFile initializes environment with calling ctx and writes file.
        final Object? writeRes = await byName['WriteFile']!.run(
          args: <String, dynamic>{
            'path': '/workspace/proj/notes.txt',
            'content': 'hello world\n',
          },
          toolContext: ctx,
        );
        expect((writeRes as Map<String, Object?>)['status'], 'ok');
        expect(env.initCount, 1);
        expect(env.isInitialized, isTrue);
        expect(env.calls.first, ('initialize', ctx));
        expect(env.calls.last, ('writeFile:/workspace/proj/notes.txt', ctx));

        // EditFile, ReadFile, and Execute all pass ctx through.
        final Object? editRes = await byName['EditFile']!.run(
          args: <String, dynamic>{
            'path': '/workspace/proj/notes.txt',
            'old_string': 'world',
            'new_string': 'dart',
          },
          toolContext: ctx,
        );
        expect((editRes as Map<String, Object?>)['status'], 'ok');

        final Object? readRes = await byName['ReadFile']!.run(
          args: <String, dynamic>{'path': '/workspace/proj/notes.txt'},
          toolContext: ctx,
        );
        expect((readRes as Map<String, Object?>)['content'], contains('dart'));

        final Object? execRes = await byName['Execute']!.run(
          args: <String, dynamic>{'command': 'pwd'},
          toolContext: ctx,
        );
        expect((execRes as Map<String, Object?>)['stdout'], 'ran:pwd');
        expect(env.calls.last, ('execute:pwd', ctx));

        // Now that env.isInitialized is true, processLlmRequest prepends working_dir header.
        final LlmRequest reqAfter = LlmRequest(model: 'gemini-2.5-flash');
        await toolset.processLlmRequest(toolContext: ctx, llmRequest: reqAfter);
        expect(
          reqAfter.config.systemInstruction,
          startsWith('Your environment is at /workspace/proj/\n'),
        );

        await toolset.close();
        expect(env.closeCount, 1);
        expect(env.isInitialized, isFalse);
      },
    );
  });

  // =========================================================================
  // 2. Fsspec Artifact Service (df9f9d045)
  // =========================================================================
  group('2. FsspecArtifactService CRUD, metadata, Rapid GCS & validation (df9f9d045)', () {
    setUp(() {
      overrideFeatureEnabled(FeatureName.fsspecArtifactService, true);
    });

    tearDown(() {
      resetFeatureRegistryForTest();
    });

    test('feature gate rejects construction when disabled and validates init args', () {
      overrideFeatureEnabled(FeatureName.fsspecArtifactService, false);
      expect(
        () => FsspecArtifactService('memory://test'),
        throwsStateError,
      );

      overrideFeatureEnabled(FeatureName.fsspecArtifactService, true);
      expect(() => FsspecArtifactService(''), throwsArgumentError);

      final InMemoryFsspecFilesystem gcs = InMemoryFsspecFilesystem(
        protocol: const <String>['gs', 'gcs'],
      );
      expect(
        () => FsspecArtifactService(
          'gs://b',
          fs: gcs,
          storageOptions: const <String, Object?>{'token': 'anon'},
        ),
        throwsArgumentError,
      );

      final InMemoryFsspecFilesystem posix = InMemoryFsspecFilesystem(
        protocol: 'sftp',
        rootMarker: '/',
      );
      expect(
        () => FsspecArtifactService('gs://b', fs: posix),
        throwsArgumentError,
      );

      final InMemoryFsspecFilesystem asyncFs = InMemoryFsspecFilesystem(
        protocol: 'gs',
        asyncImpl: true,
        asynchronous: true,
      );
      expect(
        () => FsspecArtifactService('gs://b', fs: asyncFs),
        throwsArgumentError,
      );

      Map<String, Object?>? capturedOptions;
      FsspecArtifactService(
        'gs://bucket/prefix',
        urlToFsResolver: (String url, [Map<String, Object?>? opts]) {
          capturedOptions = opts;
          return (gcs, 'bucket/prefix');
        },
      );
      expect(capturedOptions, containsPair('use_listings_cache', false));
    });

    test('root and canonical URI normalization across GCS, POSIX, and Windows layouts', () async {
      final List<(FilesystemProtocol Function(), String, String, String)> cases =
          <(FilesystemProtocol Function(), String, String, String)>[
            (
              () => InMemoryFsspecFilesystem(
                protocol: const <String>['gs', 'gcs'],
              ),
              'gs://b/root/',
              'b/root/app/u/s/f.txt/0',
              'gs://b/root/app/u/s/f.txt/0',
            ),
            (
              () => InMemoryFsspecFilesystem(
                protocol: const <String>['gs', 'gcs'],
              ),
              'gcs://b/root',
              'b/root/app/u/s/f.txt/0',
              'gcs://b/root/app/u/s/f.txt/0',
            ),
            (
              () => InMemoryFsspecFilesystem(
                protocol: const <String>['gs', 'gcs'],
              ),
              'b/root',
              'b/root/app/u/s/f.txt/0',
              'gs://b/root/app/u/s/f.txt/0',
            ),
            (
              () => InMemoryFsspecFilesystem(protocol: 'sftp', rootMarker: '/'),
              'sftp:///data',
              '/data/app/u/s/f.txt/0',
              'sftp:///data/app/u/s/f.txt/0',
            ),
            (
              () => InMemoryFsspecFilesystem(protocol: 'sftp', rootMarker: '/'),
              'sftp:///',
              '/app/u/s/f.txt/0',
              'sftp:///app/u/s/f.txt/0',
            ),
            (
              _FakeWindowsFileStore.new,
              'file:///C:/data',
              'C:/data/app/u/s/f.txt/0',
              'file:///C:/data/app/u/s/f.txt/0',
            ),
            (
              _FakeWindowsFileStore.new,
              'C:/data',
              'C:/data/app/u/s/f.txt/0',
              'file:///C:/data/app/u/s/f.txt/0',
            ),
          ];

      for (final (
            FilesystemProtocol Function() makeFs,
            String baseUrl,
            String expectedKey,
            String expectedUri,
          )
          in cases) {
        final InMemoryFsspecFilesystem store =
            makeFs() as InMemoryFsspecFilesystem;
        final FsspecArtifactService svc = FsspecArtifactService(
          baseUrl,
          fs: store,
        );
        await svc.saveArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'f.txt',
          artifact: Part.fromInlineData(
            mimeType: 'text/plain',
            data: utf8.encode('data'),
          ),
        );
        final ArtifactVersion? meta = await svc.getArtifactVersion(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'f.txt',
        );
        expect(store.objects.keys, contains(expectedKey), reason: baseUrl);
        expect(meta?.canonicalUri, expectedUri, reason: baseUrl);
      }
    });

    test('validates unsafe filenames, scopes, reserved session_id, and allows nested reserved words', () async {
      final InMemoryFsspecFilesystem store = InMemoryFsspecFilesystem(
        protocol: const <String>['gs', 'gcs'],
      );
      final FsspecArtifactService svc = FsspecArtifactService(
        'gs://b',
        fs: store,
      );

      for (final String bad in const <String>[
        '',
        'user:',
        'a\x00b',
        '/abs.txt',
        r'\abs.txt',
        'C:/abs.txt',
        'user:/abs.txt',
        '..',
        'a/../b',
        r'a\..\b',
        './a',
        'user:../escape.txt',
        'doc/',
        r'doc\',
        'a//b',
        'user:doc/',
      ]) {
        await expectLater(
          svc.saveArtifact(
            appName: 'app',
            userId: 'u',
            sessionId: 's',
            filename: bad,
            artifact: Part.text('x'),
          ),
          throwsA(isA<InputValidationError>()),
          reason: 'filename=$bad',
        );
      }

      // Nested filenames containing reserved words round-trip cleanly.
      for (final String nested in const <String>[
        'docs/versions/v2.md',
        'user:apps/sessions.txt',
      ]) {
        await svc.saveArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: nested,
          artifact: Part.text('ok'),
        );
        final Part? loaded = await svc.loadArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: nested,
        );
        expect(loaded?.text, 'ok');
      }

      // Session-scoped requires sessionId; user-scoped ignores invalid sessionId.
      await expectLater(
        svc.loadArtifact(appName: 'app', userId: 'u', filename: 'f.txt'),
        throwsA(isA<InputValidationError>()),
      );
      for (final String? ignoredSession in const <String?>[
        '',
        '../ignored',
        'user',
        null,
      ]) {
        final int v = await svc.saveArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: ignoredSession,
          filename: 'user:cfg.json',
          artifact: Part.text('{}'),
        );
        expect(v, greaterThanOrEqualTo(0));
      }

      // Session-scoped save rejects sessionId starting with 'user', while reads stay permissive.
      await expectLater(
        svc.saveArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 'user',
          filename: 'f.txt',
          artifact: Part.text('x'),
        ),
        throwsA(isA<InputValidationError>()),
      );
      expect(
        await svc.getArtifactVersion(
          appName: 'app',
          userId: 'u',
          sessionId: 'user',
          filename: 'f.txt',
        ),
        isNull,
      );
    });

    test('GCS metadata parity, internal key stripping, artifact:// references, and timestamps', () async {
      final InMemoryFsspecFilesystem store = InMemoryFsspecFilesystem(
        protocol: const <String>['gs', 'gcs'],
      );
      final FsspecArtifactService svc = FsspecArtifactService(
        'gs://b',
        fs: store,
        clock: () => 9876.5,
      );

      // Strip spoofed internal ADK keys on save.
      await svc.saveArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'data.bin',
        artifact: Part.fromInlineData(
          mimeType: 'application/octet-stream',
          data: utf8.encode('REAL BYTES'),
        ),
        customMetadata: const <String, Object?>{
          'adkIsText': 'true',
          'adkFileUri': 'gs://attacker/other.bin',
          'adkFileMimeType': 'text/plain',
          'adkDisplayName': 'spoofed',
          'file_uri': 'gs://attacker/legacy.bin',
          'origin': 'unit-test',
        },
      );
      final Part? loadedBin = await svc.loadArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'data.bin',
      );
      expect(loadedBin?.text, isNull);
      expect(utf8.decode(loadedBin!.inlineData!.data), 'REAL BYTES');
      final ArtifactVersion? binMeta = await svc.getArtifactVersion(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'data.bin',
      );
      expect(binMeta?.customMetadata, <String, Object?>{'origin': 'unit-test'});

      // Untyped file_data preserves null mimeType.
      await svc.saveArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'untyped.bin',
        artifact: Part.fromFileData(fileUri: 'gs://other/raw.bin'),
      );
      final Part? loadedUntyped = await svc.loadArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'untyped.bin',
      );
      expect(loadedUntyped?.fileData?.fileUri, 'gs://other/raw.bin');
      expect(loadedUntyped?.fileData?.mimeType, isNull);
      expect(
        (await svc.getArtifactVersion(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'untyped.bin',
        ))?.mimeType,
        isNull,
      );

      // artifact:// reference chain resolution + cross-scope + cycle guard.
      await svc.saveArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'target.txt',
        artifact: Part.text('resolved-target'),
      );
      await svc.saveArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'ref.txt',
        artifact: Part.fromFileData(
          fileUri:
              'artifact://apps/app/users/u/sessions/s/artifacts/target.txt/versions/0',
        ),
      );
      expect(
        (await svc.loadArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'ref.txt',
        ))?.text,
        'resolved-target',
      );

      await expectLater(
        svc.saveArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'bad_ref.txt',
          artifact: Part.fromFileData(
            fileUri:
                'artifact://apps/app/users/other/sessions/s/artifacts/target.txt/versions/0',
          ),
        ),
        throwsA(isA<InputValidationError>()),
      );

      // Self-referential cycle hits max depth 5.
      store.putFile(
        'b/app/u/s/self.txt/0',
        const <int>[],
        info: <String, Object?>{
          'metadata': <String, String>{
            'adkFileUri':
                'artifact://apps/app/users/u/sessions/s/artifacts/self.txt/versions/0',
          },
        },
      );
      await expectLater(
        svc.loadArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'self.txt',
        ),
        throwsA(isA<InputValidationError>()),
      );

      // Corrupt UTF-8 in adkIsText raises FormatException (does not silently coerce).
      store.putFile(
        'b/app/u/s/corrupt.txt/0',
        const <int>[0xFF, 0xFE],
        info: <String, Object?>{
          'contentType': 'text/plain',
          'metadata': <String, String>{'adkIsText': 'true'},
        },
      );
      await expectLater(
        svc.loadArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'corrupt.txt',
        ),
        throwsFormatException,
      );

      // Timestamp fallback to clock when timeCreated is null.
      store.putFile(
        'b/app/u/s/ts.txt/0',
        utf8.encode('x'),
        info: <String, Object?>{'timeCreated': null},
      );
      expect(
        (await svc.getArtifactVersion(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'ts.txt',
        ))?.createTime,
        9876.5,
      );
    });

    test('Rapid GCS bucket uses generation=0 openWrite + setxattrs, retries collisions, and cleans up failed writes', () async {
      // 1. Happy path + collision retry on generation=0 precondition failure.
      final _FakeRapidGcsStore rapid = _FakeRapidGcsStore(
        prepopulateOnFirstOpen: true,
      );
      final FsspecArtifactService svc = FsspecArtifactService(
        'gs://rapid-bucket',
        fs: rapid,
      );
      final int savedVersion = await svc.saveArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'doc.txt',
        artifact: Part.text('hello rapid'),
        customMetadata: const <String, Object?>{'tag': 'v1'},
      );
      expect(savedVersion, 1);
      expect(rapid.pipeFileCalls, 0);
      expect(rapid.openCalls, 2);
      expect(rapid.openArgs.first.$2, 0);
      expect(rapid.openArgs.first.$3, isTrue);
      expect(
        (await svc.loadArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'doc.txt',
          version: 1,
        ))?.text,
        'hello rapid',
      );

      // 2. Reserved setxattrs metadata key rejected before creating object.
      await expectLater(
        svc.saveArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'reserved.txt',
          artifact: Part.text('x'),
          customMetadata: const <String, Object?>{'timeout': '5'},
        ),
        throwsA(isA<InputValidationError>()),
      );
      expect(rapid.objects.containsKey('rapid-bucket/app/u/s/reserved.txt/0'), isFalse);

      // 3. setxattrs failure removes unmetadata'd version and preserves original error even if rmFile fails.
      final _FakeRapidGcsStore failingSetxattrs = _FakeRapidGcsStore(
        setxattrsError: StateError('setxattrs boom'),
        rmError: StateError('cleanup boom'),
      );
      final FsspecArtifactService failingSvc = FsspecArtifactService(
        'gs://rapid-bucket',
        fs: failingSetxattrs,
      );
      await expectLater(
        failingSvc.saveArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'orphan.txt',
          artifact: Part.text('x'),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            'setxattrs boom',
          ),
        ),
      );
    });

    test('memory:// and file:// backends support CRUD, reject metadata, honor tombstones, and treat file ancestors as absent', () async {
      // memory://
      final FsspecArtifactService memSvc = FsspecArtifactService(
        'memory://nov12-mem-${DateTime.now().microsecondsSinceEpoch}',
      );
      await expectLater(
        memSvc.saveArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'notes.txt',
          artifact: Part.text('unsupported on memory'),
        ),
        throwsA(isA<InputValidationError>()),
      );
      expect(
        await memSvc.saveArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'notes.txt',
          artifact: Part.fromInlineData(
            mimeType: 'text/plain',
            data: utf8.encode('before'),
          ),
        ),
        0,
      );
      expect(
        await memSvc.saveArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'notes.txt',
          artifact: newRewindTombstone(),
        ),
        1,
      );
      expect(
        await memSvc.loadArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'notes.txt',
        ),
        isNull,
      );
      expect(
        utf8.decode(
          (await memSvc.loadArtifact(
            appName: 'app',
            userId: 'u',
            sessionId: 's',
            filename: 'notes.txt',
            version: 0,
          ))!.inlineData!.data,
        ),
        'before',
      );

      // file://
      final Directory tmpDir = await Directory.systemTemp.createTemp(
        'adk_fsspec_file_',
      );
      addTearDown(() => tmpDir.delete(recursive: true));
      final String baseUri = tmpDir.uri.toString().replaceAll(
        RegExp(r'/+$'),
        '',
      );
      final FsspecArtifactService fileSvc = FsspecArtifactService(baseUri);

      final int v0 = await fileSvc.saveArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'docs/data.json',
        artifact: Part.fromInlineData(
          mimeType: 'application/json',
          data: utf8.encode('{}'),
        ),
      );
      expect(v0, 0);
      final ArtifactVersion? vMeta = await fileSvc.getArtifactVersion(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'docs/data.json',
        version: 0,
      );
      expect(vMeta?.canonicalUri, '$baseUri/app/u/s/docs/data.json/0');

      // Querying beneath regular file `docs/data.json/0` avoids ENOTDIR and treats as absent.
      for (final String descendant in const <String>[
        'docs/data.json/0',
        'docs/data.json/0/child',
      ]) {
        expect(
          await fileSvc.loadArtifact(
            appName: 'app',
            userId: 'u',
            sessionId: 's',
            filename: descendant,
            version: 0,
          ),
          isNull,
        );
        expect(
          await fileSvc.listVersions(
            appName: 'app',
            userId: 'u',
            sessionId: 's',
            filename: descendant,
          ),
          isEmpty,
        );
      }

      await fileSvc.deleteArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'docs/data.json',
      );
      expect(
        await fileSvc.loadArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'docs/data.json',
        ),
        isNull,
      );
    });
  });

  // =========================================================================
  // 3. OCI GenAI LLM Streaming Parallel Tool Calls (353a771d7)
  // =========================================================================
  group('3. OCIGenAILlm streamed parallel tool calls (353a771d7)', () {
    test('keeps parallel tool calls separate in arrival order including empty IDs and split deltas', () async {
      // Case A: Parallel calls arriving in separate chunks without index and with empty IDs.
      final OCIGenAILlm llmSeparate = OCIGenAILlm(
        model: 'meta.llama-3.3-70b-instruct',
        compartmentId: 'ocid1.compartment.oc1..test',
        client: _FakeStreamOciClient(<Map<String, Object?>>[
          <String, Object?>{
            'message': <String, Object?>{
              'toolCalls': <Object?>[
                <String, Object?>{
                  'id': '',
                  'name': 'z_lookup',
                  'arguments': '{"city":"Seoul"}',
                },
              ],
            },
          },
          <String, Object?>{
            'message': <String, Object?>{
              'toolCalls': <Object?>[
                <String, Object?>{
                  'id': '',
                  'name': 'a_lookup',
                  'arguments': '{"city":"Tokyo"}',
                },
              ],
            },
            'finishReason': 'TOOL_CALLS',
          },
        ]),
      );

      final List<LlmResponse> separateResponses = await llmSeparate
          .generateContent(
            LlmRequest(
              model: 'meta.llama-3.3-70b-instruct',
              contents: <Content>[Content.userText('weather')],
            ),
            stream: true,
          )
          .toList();
      final List<FunctionCall> separateCalls = separateResponses.last.content!
          .parts
          .where((Part p) => p.functionCall != null)
          .map((Part p) => p.functionCall!)
          .toList();
      expect(separateCalls, hasLength(2));
      // Preserves arrival order (z_lookup then a_lookup), NOT alphabetical order!
      expect(separateCalls[0].name, 'z_lookup');
      expect(separateCalls[0].id, '');
      expect(separateCalls[0].args, <String, Object?>{'city': 'Seoul'});
      expect(separateCalls[1].name, 'a_lookup');
      expect(separateCalls[1].id, '');
      expect(separateCalls[1].args, <String, Object?>{'city': 'Tokyo'});

      // Case B: Split arguments across chunks by index, by id, and continuation without id/name/index.
      final OCIGenAILlm llmSplit = OCIGenAILlm(
        model: 'meta.llama-3.3-70b-instruct',
        compartmentId: 'ocid1.compartment.oc1..test',
        client: _FakeStreamOciClient(<Map<String, Object?>>[
          <String, Object?>{
            'message': <String, Object?>{
              'toolCalls': <Object?>[
                <String, Object?>{
                  'index': 0,
                  'id': 'call_first',
                  'name': 'tool_one',
                  'arguments': '{"a":',
                },
              ],
            },
          },
          <String, Object?>{
            'message': <String, Object?>{
              'toolCalls': <Object?>[
                <String, Object?>{'index': 0, 'arguments': '1}'},
                <String, Object?>{
                  'id': 'call_second',
                  'name': 'tool_two',
                  'arguments': '{"b":',
                },
              ],
            },
          },
          <String, Object?>{
            'message': <String, Object?>{
              'toolCalls': <Object?>[
                // Continuation piece with neither index, id, nor name appends to last resolved call.
                <String, Object?>{'arguments': '2}'},
              ],
            },
            'finishReason': 'TOOL_CALLS',
          },
        ]),
      );

      final List<LlmResponse> splitResponses = await llmSplit
          .generateContent(
            LlmRequest(
              model: 'meta.llama-3.3-70b-instruct',
              contents: <Content>[Content.userText('run both')],
            ),
            stream: true,
          )
          .toList();
      final List<FunctionCall> splitCalls = splitResponses.last.content!.parts
          .where((Part p) => p.functionCall != null)
          .map((Part p) => p.functionCall!)
          .toList();
      expect(splitCalls, hasLength(2));
      expect(splitCalls[0].id, 'call_first');
      expect(splitCalls[0].name, 'tool_one');
      expect(splitCalls[0].args, <String, Object?>{'a': 1});
      expect(splitCalls[1].id, 'call_second');
      expect(splitCalls[1].name, 'tool_two');
      expect(splitCalls[1].args, <String, Object?>{'b': 2});
    });
  });

  // =========================================================================
  // 4. Antigravity Lab Agent Cached Token Count (cd8debd2e)
  // =========================================================================
  group('4. AntigravityAgent cached_content_token_count (cd8debd2e)', () {
    test('propagates cachedContentTokenCount (40 vs null) on trailing turn usage Event', () async {
      Future<Event> runTurnWithUsage(AntigravityTurnUsage usage) async {
        final InMemorySdkConversation conv = InMemorySdkConversation(
          conversationId: 'conv_usage',
        )..lastTurnUsage = usage;
        final AntigravityAgent agent = AntigravityAgent(
          name: 'ag_agent',
          description: 'Antigravity test agent',
          sdkAgentFactory: (dynamic cfg) =>
              InMemorySdkAgent(config: cfg, conversation: conv),
        );
        final Session session = Session(
          id: 'sess_ag',
          appName: 'app',
          userId: 'u',
          events: <Event>[
            Event(
              invocationId: 'inv_ag',
              author: 'user',
              content: Content.userText('hello antigravity'),
            ),
          ],
        );
        final InvocationContext inv = InvocationContext(
          sessionService: InMemorySessionService(),
          invocationId: 'inv_ag',
          agent: agent,
          session: session,
        );
        final List<Event> events = await agent.runAsync(inv).toList();
        return events.last;
      }

      final Event populated = await runTurnWithUsage(
        const AntigravityTurnUsage(
          promptTokenCount: 100,
          cachedContentTokenCount: 40,
          candidatesTokenCount: 25,
          totalTokenCount: 130,
          thoughtsTokenCount: 5,
        ),
      );
      expect(populated.usageMetadata, <String, Object?>{
        'prompt_token_count': 100,
        'cached_content_token_count': 40,
        'candidates_token_count': 25,
        'total_token_count': 130,
        'thoughts_token_count': 5,
      });

      final Event omitted = await runTurnWithUsage(
        const AntigravityTurnUsage(
          promptTokenCount: 80,
          candidatesTokenCount: 20,
          totalTokenCount: 100,
        ),
      );
      expect(
        omitted.usageMetadata,
        containsPair('cached_content_token_count', null),
      );
    });
  });

  // =========================================================================
  // 5. CascadeLive Telemetry & Client Labels (9620b4296)
  // =========================================================================
  group('5. CascadeLive telemetry client label (9620b4296)', () {
    setUp(() {
      overrideFeatureEnabled(FeatureName.cascadeLive, true);
    });

    tearDown(() {
      resetFeatureRegistryForTest();
    });

    test('cascadeLiveClientLabel format, sendsGoogleTrackingHeaders, and withClientLabel header merging', () {
      expect(cascadeLiveClientLabel, 'google-adk-cascade-live/$adkVersion');

      final Gemini gemini = Gemini(model: 'gemini-2.5-flash');
      final _RecordingCascadeLlm customLlm = _RecordingCascadeLlm();
      expect(sendsGoogleTrackingHeaders(gemini), isTrue);
      expect(sendsGoogleTrackingHeaders(customLlm), isFalse);

      final GenerateContentConfig initial = GenerateContentConfig(
        httpOptions: HttpOptions(
          headers: <String, String>{
            'X-Goog-Api-Client': 'existing-client/1.0',
            'custom-header': 'keep',
          },
        ),
      );
      final GenerateContentConfig labeled = withClientLabel(
        initial,
        cascadeLiveClientLabel,
      );
      expect(
        labeled.httpOptions?.headers['x-goog-api-client'],
        'existing-client/1.0 $cascadeLiveClientLabel',
      );
      expect(
        labeled.httpOptions?.headers['user-agent'],
        cascadeLiveClientLabel,
      );
      expect(labeled.httpOptions?.headers['custom-header'], 'keep');
    });

    test('CascadeLiveConnection attaches label per turn for Google LLMs without mutating base request or clashing with outer clientLabelContext', () async {
      final _RecordingCascadeLlm googleTrackedLlm = _RecordingCascadeLlm(
        model: 'gemini-2.5-flash',
        replies: <String>['turn one', 'turn two'],
      );
      final LlmRequest baseRequest = LlmRequest(model: 'gemini-2.5-flash');

      await clientLabelContext(evalClientLabel, () async {
        final CascadeLiveConnection conn = CascadeLiveConnection(
          baseRequest,
          googleTrackedLlm,
          _IdleStt(),
          _EchoTts(),
          sendsGoogleTrackingHeadersPredicate: (_) => true,
        );

        await conn.sendContent(Content.userText('first question'));
        await for (final LlmResponse resp in conn.receive()) {
          if (resp.turnComplete == true) {
            break;
          }
        }

        await conn.sendContent(Content.userText('second question'));
        await for (final LlmResponse resp in conn.receive()) {
          if (resp.turnComplete == true) {
            break;
          }
        }
        await conn.close();
      });

      expect(googleTrackedLlm.requests, hasLength(2));
      // Label does NOT accumulate across turns!
      for (final LlmRequest req in googleTrackedLlm.requests) {
        expect(
          req.config.httpOptions?.headers['x-goog-api-client'],
          cascadeLiveClientLabel,
        );
        expect(
          req.config.httpOptions?.headers['user-agent'],
          cascadeLiveClientLabel,
        );
      }
      // Outer evalClientLabel remained intact in zone during both reasoning turns!
      expect(
        googleTrackedLlm.zoneLabelsPerCall.first,
        contains(evalClientLabel),
      );
      // Original baseRequest was never mutated.
      expect(baseRequest.config.httpOptions, isNull);

      // Non-Google LLM does NOT get Google tracking headers injected.
      final _RecordingCascadeLlm thirdPartyLlm = _RecordingCascadeLlm(
        model: 'claude-sonnet-4-20250514',
      );
      final CascadeLiveConnection nonGoogleConn = CascadeLiveConnection(
        LlmRequest(model: 'claude-sonnet-4-20250514'),
        thirdPartyLlm,
        _IdleStt(),
        _EchoTts(),
      );
      await nonGoogleConn.sendContent(Content.userText('hi'));
      await for (final LlmResponse resp in nonGoogleConn.receive()) {
        if (resp.turnComplete == true) {
          break;
        }
      }
      await nonGoogleConn.close();
      expect(thirdPartyLlm.requests.single.config.httpOptions, isNull);
    });
  });

  // =========================================================================
  // 6. Memory & Vertex AI RAG Client Reuse (e9f9790f9, 112491db8)
  // =========================================================================
  group('6. InMemoryMemoryService mixed-script search & Vertex RAG client reuse (e9f9790f9, 112491db8)', () {
    test('InMemoryMemoryService splits mixed Latin/non-Latin tokens without splitting Turkish dotted İ or matching split-out non-ASCII particles', () async {
      final InMemoryMemoryService memory = InMemoryMemoryService();
      final Session sPython = Session(
        id: 's_py',
        appName: 'app',
        userId: 'u',
        events: <Event>[
          Event(
            invocationId: 'i1',
            author: 'user',
            content: Content.userText('I love Python programming.'),
          ),
        ],
      );
      final Session sIstanbul = Session(
        id: 's_ist',
        appName: 'app',
        userId: 'u',
        events: <Event>[
          Event(
            invocationId: 'i2',
            author: 'user',
            content: Content.userText('I visited İstanbul last year.'),
          ),
        ],
      );
      final Session sCats = Session(
        id: 's_cats',
        appName: 'app',
        userId: 'u',
        events: <Event>[
          Event(
            invocationId: 'i3',
            author: 'user',
            content: Content.userText('I like cats.'),
          ),
        ],
      );
      final Session sDog = Session(
        id: 's_dog',
        appName: 'app',
        userId: 'u',
        events: <Event>[
          Event(
            invocationId: 'i4',
            author: 'user',
            content: Content.userText('私と犬'),
          ),
        ],
      );
      await memory.addSessionToMemory(sPython);
      await memory.addSessionToMemory(sIstanbul);
      await memory.addSessionToMemory(sCats);
      await memory.addSessionToMemory(sDog);

      // Mixed Latin + Japanese / CJK queries match 'Python'.
      final SearchMemoryResponse jaRes = await memory.searchMemory(
        appName: 'app',
        userId: 'u',
        query: 'Pythonについて教えて',
      );
      expect(jaRes.memories, hasLength(1));
      expect(jaRes.memories.single.content.parts.single.text, contains('Python'));

      final SearchMemoryResponse zhRes = await memory.searchMemory(
        appName: 'app',
        userId: 'u',
        query: '我用Python写代码',
      );
      expect(zhRes.memories, hasLength(1));

      // Turkish capital 'İ' in 'İstanbul旅行' stays intact as Latin run before lowercasing:
      // matches 'İstanbul', does NOT split into standalone 'i' matching 'I like cats.'!
      final SearchMemoryResponse trRes = await memory.searchMemory(
        appName: 'app',
        userId: 'u',
        query: 'İstanbul旅行',
      );
      expect(
        trRes.memories.map((MemoryEntry m) => m.content.parts.single.text),
        <String>['I visited İstanbul last year.'],
      );

      // Split-out non-ASCII particle 'と' from 'Pythonと' must NOT substring-match '私と犬'!
      final SearchMemoryResponse particleRes = await memory.searchMemory(
        appName: 'app',
        userId: 'u',
        query: 'Pythonと',
      );
      expect(
        particleRes.memories.map((MemoryEntry m) => m.content.parts.single.text),
        <String>['I love Python programming.'],
      );

      // Partial ASCII word 'thon' still does NOT match 'Python'.
      final SearchMemoryResponse partialRes = await memory.searchMemory(
        appName: 'app',
        userId: 'u',
        query: 'thon',
      );
      expect(partialRes.memories, isEmpty);
    });

    test('VertexAiRagMemoryService and VertexAiRagRetrieval reuse clients per Zone and per (project, location) without closing per call', () async {
      final List<(String?, String?)> memoryFactoryCalls = <(String?, String?)>[];
      final List<_FakeRagClient> createdMemoryClients = <_FakeRagClient>[];

      final VertexAiRagMemoryService ragMemory = VertexAiRagMemoryService(
        ragCorpus: 'projects/proj-a/locations/us-central1/ragCorpora/123',
        environment: const <String, String>{},
        ragClientFactory: ({String? project, String? location}) {
          memoryFactoryCalls.add((project, location));
          final _FakeRagClient client = _FakeRagClient();
          createdMemoryClients.add(client);
          return client;
        },
      );

      await ragMemory.searchMemory(appName: 'app', userId: 'u', query: 'first');
      await ragMemory.searchMemory(appName: 'app', userId: 'u', query: 'second');
      expect(memoryFactoryCalls, <(String?, String?)>[
        ('proj-a', 'us-central1'),
      ]);
      expect(createdMemoryClients.single.closeCalls, 0);

      // Running in a distinct Zone creates a separate client for that Zone.
      await runZoned(() async {
        await ragMemory.searchMemory(
          appName: 'app',
          userId: 'u',
          query: 'zoned',
        );
      });
      expect(memoryFactoryCalls, hasLength(2));

      // VertexAiRagRetrieval caches per Zone AND per resolved (project, location).
      final List<(String?, String?)> retrievalFactoryCalls =
          <(String?, String?)>[];
      final VertexAiRagRetrieval toolUs = VertexAiRagRetrieval(
        name: 'rag_us',
        description: 'US RAG',
        ragCorpora: <String>[
          'projects/proj-1/locations/us-central1/ragCorpora/c1',
        ],
        clientFactory: ({String? project, String? location}) {
          retrievalFactoryCalls.add((project, location));
          return _FakeRagClient();
        },
      );
      final VertexAiRagRetrieval toolEu = VertexAiRagRetrieval(
        name: 'rag_eu',
        description: 'EU RAG',
        ragCorpora: <String>[
          'projects/proj-1/locations/europe-west4/ragCorpora/c2',
        ],
        clientFactory: ({String? project, String? location}) {
          retrievalFactoryCalls.add((project, location));
          return _FakeRagClient();
        },
      );

      final Context ctx = _makeContext();
      await toolUs.run(
        args: <String, dynamic>{'query': 'q1'},
        toolContext: ctx,
      );
      await toolUs.run(
        args: <String, dynamic>{'query': 'q2'},
        toolContext: ctx,
      );
      await toolEu.run(
        args: <String, dynamic>{'query': 'q3'},
        toolContext: ctx,
      );

      expect(retrievalFactoryCalls, <(String?, String?)>[
        ('proj-1', 'us-central1'),
        ('proj-1', 'europe-west4'),
      ]);
    });
  });

  // =========================================================================
  // 7. Anthropic Claude LLM Empty Response Error Reporting (583900785)
  // =========================================================================
  group('7. AnthropicLlm empty non-STOP response error reporting (583900785)', () {
    test('reports errorCode and errorMessage when non-STOP response has no actionable content (non-streaming & streaming)', () async {
      final List<(String?, String, bool)> cases = <(String?, String, bool)>[
        ('end_turn', 'STOP', false),
        ('max_tokens', 'MAX_TOKENS', true),
        ('refusal', 'SAFETY', true),
        ('something_new', 'FINISH_REASON_UNSPECIFIED', true),
      ];

      for (final (
            String? stopReason,
            String expectedFinish,
            bool expectError,
          )
          in cases) {
        final AnthropicLlm nonStreamLlm = AnthropicLlm(
          model: 'claude-sonnet-4-20250514',
          environment: const <String, String>{'ANTHROPIC_API_KEY': 'k'},
          restTransport: _StubAnthropicTransport(
            nonStreamResponse: <String, Object?>{
              'content': <Object?>[
                <String, Object?>{
                  'type': 'thinking',
                  'thinking': 'deep internal thought',
                  'signature': 'sig1',
                },
                <String, Object?>{'type': 'redacted_thinking', 'data': 'enc'},
                <String, Object?>{'type': 'text', 'text': ''},
              ],
              'stop_reason': stopReason,
              'usage': <String, Object?>{'input_tokens': 10, 'output_tokens': 5},
            },
          ),
        );

        final LlmResponse resp = (await nonStreamLlm
                .generateContent(
                  LlmRequest(
                    model: 'claude-sonnet-4-20250514',
                    contents: <Content>[Content.userText('hi')],
                  ),
                )
                .toList())
            .single;

        expect(resp.finishReason, expectedFinish);
        if (expectError) {
          expect(resp.errorCode, expectedFinish);
          expect(
            resp.errorMessage,
            "Claude stopped with $expectedFinish ('$stopReason') and no content.",
          );
        } else {
          expect(resp.errorCode, isNull);
          expect(resp.errorMessage, isNull);
        }
      }

      // Streaming: thinking + redacted_thinking + empty text block ending in max_tokens.
      final AnthropicLlm streamLlm = AnthropicLlm(
        model: 'claude-sonnet-4-20250514',
        environment: const <String, String>{'ANTHROPIC_API_KEY': 'k'},
        restTransport: _StubAnthropicTransport(
          streamEvents: <Map<String, Object?>>[
            <String, Object?>{
              'type': 'message_start',
              'message': <String, Object?>{
                'usage': <String, Object?>{'input_tokens': 12},
              },
            },
            <String, Object?>{
              'type': 'content_block_start',
              'index': 0,
              'content_block': <String, Object?>{
                'type': 'thinking',
                'thinking': '',
              },
            },
            <String, Object?>{
              'type': 'content_block_delta',
              'index': 0,
              'delta': <String, Object?>{
                'type': 'thinking_delta',
                'thinking': 'pondering...',
              },
            },
            <String, Object?>{
              'type': 'content_block_stop',
              'index': 0,
            },
            <String, Object?>{
              'type': 'content_block_start',
              'index': 1,
              'content_block': <String, Object?>{
                'type': 'redacted_thinking',
                'data': 'redacted_blob',
              },
            },
            <String, Object?>{
              'type': 'content_block_stop',
              'index': 1,
            },
            <String, Object?>{
              'type': 'content_block_start',
              'index': 2,
              'content_block': <String, Object?>{'type': 'text', 'text': ''},
            },
            <String, Object?>{
              'type': 'content_block_stop',
              'index': 2,
            },
            <String, Object?>{
              'type': 'message_delta',
              'delta': <String, Object?>{'stop_reason': 'max_tokens'},
              'usage': <String, Object?>{'output_tokens': 64},
            },
            <String, Object?>{'type': 'message_stop'},
          ],
        ),
      );

      final List<LlmResponse> streamed = await streamLlm
          .generateContent(
            LlmRequest(
              model: 'claude-sonnet-4-20250514',
              contents: <Content>[Content.userText('solve')],
            ),
            stream: true,
          )
          .toList();
      final LlmResponse finalResp = streamed.last;
      expect(finalResp.finishReason, 'MAX_TOKENS');
      expect(finalResp.errorCode, 'MAX_TOKENS');
      expect(
        finalResp.errorMessage,
        "Claude stopped with MAX_TOKENS ('max_tokens') and no content.",
      );
      expect(finalResp.content?.parts.last.text, '');
    });
  });

  // =========================================================================
  // 8. Optimization Schemas & Required-Field Validation (3bb410c90)
  // =========================================================================
  group('8. Optimization schemas & required fields (3bb410c90)', () {
    test('jsonSchema() emits object-level required lists without property-level required: true and fromJson({}) rejects missing required fields', () {
      final List<(Map<String, Object?>, List<String>)> schemas =
          <(Map<String, Object?>, List<String>)>[
            (SamplingResult.jsonSchema(), <String>['scores']),
            (UnstructuredSamplingResult.jsonSchema(), <String>['scores']),
            (AgentWithScores.jsonSchema(), <String>['optimized_agent']),
            (OptimizerResult.jsonSchema(), <String>['optimized_agents']),
            (
              LocalEvalSamplerConfig.jsonSchema(),
              <String>['eval_config', 'app_name', 'train_eval_set'],
            ),
          ];

      for (final (
            Map<String, Object?> schema,
            List<String> expectedRequired,
          )
          in schemas) {
        expect(schema['required'], expectedRequired);
        _assertNoPropertyLevelRequiredTrue(schema, '${schema['title']}');
      }

      expect(
        () => SamplingResult.fromJson(const <String, Object?>{}),
        throwsFormatException,
      );
      expect(
        () => UnstructuredSamplingResult.fromJson(const <String, Object?>{}),
        throwsFormatException,
      );
      expect(
        () => AgentWithScores.fromJson(const <String, Object?>{}),
        throwsFormatException,
      );
      expect(
        () => OptimizerResult<AgentWithScores>.fromJson(
          const <String, Object?>{},
          itemFromJson: AgentWithScores.fromJson,
        ),
        throwsFormatException,
      );
      expect(
        () => LocalEvalSamplerConfig.fromJson(const <String, Object?>{}),
        throwsFormatException,
      );
    });
  });
}
