import 'dart:async';
import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _AgentToolStateEchoAgent extends BaseAgent {
  _AgentToolStateEchoAgent({required this.callback})
    : super(name: 'child_state_agent', description: 'Reads and mutates state.');

  final void Function(State state) callback;

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    final Map<String, Object?> delta = <String, Object?>{};
    final State state = State(
      value: context.session.state,
      delta: delta,
    );
    callback(state);
    yield Event(
      invocationId: context.invocationId,
      author: name,
      content: Content.modelText('child_ok'),
      actions: EventActions(stateDelta: Map<String, Object?>.of(delta)),
    );
  }
}

class _AlwaysFailCreateIndexesCollection implements MongoDbSessionCollection {
  _AlwaysFailCreateIndexesCollection(this._delegate, this.errorToThrow);

  final MongoDbSessionCollection _delegate;
  final Object errorToThrow;
  int createIndexesCalls = 0;

  @override
  String get name => _delegate.name;

  @override
  Future<String> createIndex(
    List<(String, int)> keys, {
    String? name,
  }) async {
    createIndexesCalls += 1;
    throw errorToThrow;
  }

  @override
  Future<int> deleteMany(Map<String, Object?> filter) =>
      _delegate.deleteMany(filter);

  @override
  Future<int> deleteOne(Map<String, Object?> filter) =>
      _delegate.deleteOne(filter);

  @override
  Future<List<Map<String, Object?>>> find(
    Map<String, Object?> filter, {
    Map<String, Object?>? projection,
    List<(String, int)>? sort,
    int? limit,
  }) => _delegate.find(
    filter,
    projection: projection,
    sort: sort,
    limit: limit,
  );

  @override
  Future<Map<String, Object?>?> findOne(
    Map<String, Object?> filter, {
    Map<String, Object?>? projection,
  }) => _delegate.findOne(filter, projection: projection);

  @override
  Future<void> insertOne(Map<String, Object?> document) =>
      _delegate.insertOne(document);

  @override
  Future<MongoDbUpdateResult> updateOne(
    Map<String, Object?> filter,
    Map<String, Object?> update, {
    bool upsert = false,
  }) => _delegate.updateOne(filter, update, upsert: upsert);
}

class _CustomMemoriesDatabase implements MongoDbSessionDatabase {
  _CustomMemoriesDatabase(this._inner, this.memoriesCollection);

  final MongoDbSessionDatabase _inner;
  final MongoDbSessionCollection memoriesCollection;

  @override
  String get name => _inner.name;

  @override
  MongoDbSessionCollection collection(String name) {
    if (name == defaultMemoriesCollection) {
      return memoriesCollection;
    }
    return _inner.collection(name);
  }
}

class _CustomMemoriesClient implements MongoDbSessionClient {
  _CustomMemoriesClient(this._inner, this.memoriesCollection);

  final InMemoryMongoDbSessionClient _inner;
  final MongoDbSessionCollection memoriesCollection;
  bool closed = false;

  @override
  MongoDbSessionDatabase database(String name) =>
      _CustomMemoriesDatabase(_inner.database(name), memoriesCollection);

  @override
  Future<void> close() async {
    closed = true;
    await _inner.close();
  }
}

InvocationContext _buildTestInvocationContext({
  String invocationId = 'inv-1',
  String appName = 'test-app',
  String userId = 'user-1',
  String sessionId = 'sess-1',
  BaseAgent? agent,
}) {
  final BaseAgent resolvedAgent =
      agent ?? LlmAgent(name: 'root_agent', instruction: 'Helpful assistant.');
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: invocationId,
    agent: resolvedAgent,
    session: Session(id: sessionId, appName: appName, userId: userId),
  );
}

void main() {
  group('1. Release version parity (ceb0627f1)', () {
    test('adkVersion is updated to 2.13.0', () {
      expect(adkVersion, '2.13.0');
    });
  });

  group('2. AgentTool temp: state forwarding (12c7bed76)', () {
    test(
      'passes caller temp: state to wrapped agent with isolated container copies and excludes temp: writes from parent state',
      () async {
        Object? seenTempScalar;
        Object? seenTempList;
        Object? seenTempAdkInternal;
        Object? seenPersistent;

        final _AgentToolStateEchoAgent childAgent = _AgentToolStateEchoAgent(
          callback: (State childState) {
            seenTempScalar = childState['temp:token'];
            seenTempList = List<Object?>.from(
              (childState['temp:items'] as List?) ?? const <Object?>[],
            );
            seenTempAdkInternal = childState['temp:_adk_secret'];
            seenPersistent = childState['shared_key'];

            // Mutate child's copy of temp:items in-place and write a new temp: key.
            (childState['temp:items'] as List<Object?>).add('mutated_in_child');
            childState['temp:child_only'] = 'ephemeral';
            childState['shared_key'] = 'updated_by_child';
          },
        );

        final AgentTool tool = AgentTool(agent: childAgent);
        final List<String> callerList = <String>['a', 'b'];
        final InvocationContext parentInvocation = _buildTestInvocationContext(
          agent: LlmAgent(name: 'parent_agent', instruction: 'Parent'),
        );
        parentInvocation.session.state.addAll(<String, Object?>{
          'shared_key': 'initial',
          'temp:token': 'caller_token_123',
          'temp:items': callerList,
          'temp:_adk_secret': 'should_not_leak',
          '_adk_internal': 'should_not_leak',
        });

        final EventActions parentActions = EventActions();
        final ToolContext toolContext = ToolContext(
          parentInvocation,
          eventActions: parentActions,
        );

        final Object? result = await tool.run(
          args: <String, dynamic>{'request': 'go'},
          toolContext: toolContext,
        );

        expect(result, 'child_ok');
        expect(seenTempScalar, 'caller_token_123');
        expect(seenTempList, <Object?>['a', 'b']);
        expect(seenTempAdkInternal, isNull);
        expect(seenPersistent, 'initial');

        // Caller's mutable list is not modified by child's in-place edit.
        expect(callerList, <String>['a', 'b']);
        // Child's temp: writes do not leak back into parent state, while non-temp writes do.
        expect(toolContext.state['temp:child_only'], isNull);
        expect(toolContext.state['shared_key'], 'updated_by_child');
      },
    );
  });

  group('3. FirestoreSessionService empty userId guard (b98125006)', () {
    test('listSessions(userId: "") returns empty list without listing all users', () async {
      final FirestoreSessionService service = FirestoreSessionService();
      await service.createSession(
        appName: 'app',
        userId: 'alice',
        sessionId: 's1',
      );
      await service.createSession(
        appName: 'app',
        userId: 'bob',
        sessionId: 's2',
      );

      final ListSessionsResponse emptyUserResult = await service.listSessions(
        appName: 'app',
        userId: '',
      );
      expect(emptyUserResult.sessions, isEmpty);

      final ListSessionsResponse allUsersResult = await service.listSessions(
        appName: 'app',
      );
      expect(allUsersResult.sessions, hasLength(2));
    });
  });

  group('4. McpTool empty OAuth2 token handling (83acbc50f)', () {
    test(
      'does not fall back to HTTP credentials when oauth2 credential has empty accessToken',
      () async {
        Map<String, String>? capturedHeaders;
        final StdioConnectionParams connectionParams = StdioConnectionParams(
          command: 'echo_mcp_empty_oauth2_test',
        );
        McpSessionManager.instance.registerToolExecutor(
          connectionParams: connectionParams,
          toolName: 'secure_tool',
          executor: (Map<String, dynamic> args, {Map<String, String>? headers}) {
            capturedHeaders = headers;
            return <String, Object?>{'ok': true};
          },
        );

        final AuthConfig authConfig = AuthConfig(
          authScheme: 'oauth2',
          rawAuthCredential: AuthCredential(
            authType: AuthCredentialTypes.oauth2,
            oauth2: OAuth2Auth(accessToken: ''),
            http: HttpAuth(
              scheme: 'bearer',
              credentials: HttpCredentials(token: 'fallback-http-secret'),
            ),
          ),
          exchangedAuthCredential: AuthCredential(
            authType: AuthCredentialTypes.oauth2,
            oauth2: OAuth2Auth(accessToken: ''),
            http: HttpAuth(
              scheme: 'bearer',
              credentials: HttpCredentials(token: 'fallback-http-secret'),
            ),
          ),
          credentialKey: 'mcp_empty_oauth2_key',
        );
        final McpTool tool = McpTool(
          mcpTool: McpBaseTool(name: 'secure_tool'),
          connectionParams: connectionParams,
          sessionManager: McpSessionManager.instance,
          authConfig: authConfig,
        );

        final InvocationContext inv = _buildTestInvocationContext();
        inv.session.state[authConfig.credentialKey] =
            authConfig.exchangedAuthCredential;
        final ToolContext toolContext = ToolContext(inv);

        await tool.run(
          args: <String, dynamic>{},
          toolContext: toolContext,
        );

        expect(capturedHeaders, isNull);
      },
    );
  });

  group('5. Failed A2A tasks marked as error events (25d191710)', () {
    test('convertA2aTaskToEvent sets errorCode and errorMessage on failed tasks', () {
      final A2aTask failedWithMessage = A2aTask(
        id: 'task-1',
        contextId: 'ctx-1',
        status: A2aTaskStatus(
          state: A2aTaskState.failed,
          message: A2aMessage(
            messageId: 'm-1',
            role: A2aRole.agent,
            parts: <A2aPart>[A2aPart.text('Database connection timed out')],
          ),
        ),
      );
      final Event eventWithMsg = convertA2aTaskToEvent(
        failedWithMessage,
        author: 'remote_agent',
      );
      expect(eventWithMsg.errorCode, a2aTaskFailedErrorCode);
      expect(eventWithMsg.errorMessage, 'Database connection timed out');

      final A2aTask failedWithoutMessage = A2aTask(
        id: 'task-2',
        contextId: 'ctx-2',
        status: A2aTaskStatus(state: A2aTaskState.failed),
      );
      final Event eventDefaultMsg = convertA2aTaskToEvent(
        failedWithoutMessage,
        author: 'remote_agent',
      );
      expect(eventDefaultMsg.errorCode, a2aTaskFailedErrorCode);
      expect(eventDefaultMsg.errorMessage, 'Remote agent task failed');
    });

    test('convertA2aStatusUpdateToEvent sets errorCode and errorMessage on failed status update', () {
      final A2aTaskStatusUpdateEvent update = A2aTaskStatusUpdateEvent(
        taskId: 'task-3',
        contextId: 'ctx-3',
        status: A2aTaskStatus(
          state: A2aTaskState.failed,
          message: A2aMessage(
            messageId: 'm-3',
            role: A2aRole.agent,
            parts: <A2aPart>[
              A2aPart.text('Part 1 failed'),
              A2aPart.text('Part 2 reason'),
            ],
          ),
        ),
      );
      final Event event = convertA2aStatusUpdateToEvent(
        update,
        author: 'remote_agent',
      );
      expect(event.errorCode, a2aTaskFailedErrorCode);
      expect(event.errorMessage, 'Part 1 failed\nPart 2 reason');
    });
  });

  group('6. Disambiguate colliding connector tool names (f08f9d677)', () {
    test('disambiguateToolNames renames duplicate IntegrationConnectorTool instances and avoids reserved names', () {
      final RestApiTool rest1 = RestApiTool(
        name: 'list_accounts',
        description: 'List accounts 1',
        endpoint: OperationEndpoint(
          baseUrl: 'https://example.com',
          path: '/v1/a',
          method: 'post',
        ),
        operation: <String, Object?>{'operationId': 'list_accounts'},
      );
      final RestApiTool rest2 = RestApiTool(
        name: 'list_accounts',
        description: 'List accounts 2',
        endpoint: OperationEndpoint(
          baseUrl: 'https://example.com',
          path: '/v1/b',
          method: 'post',
        ),
        operation: <String, Object?>{'operationId': 'list_accounts'},
      );
      final RestApiTool restReserved = RestApiTool(
        name: 'list_accounts_2',
        description: 'Already reserved',
        endpoint: OperationEndpoint(
          baseUrl: 'https://example.com',
          path: '/v1/c',
          method: 'post',
        ),
        operation: <String, Object?>{'operationId': 'list_accounts_2'},
      );

      final List<BaseTool> tools = <BaseTool>[
        IntegrationConnectorTool(
          name: 'list_accounts',
          description: 'List accounts 1',
          connectionName: 'conn',
          connectionHost: 'host',
          connectionServiceName: 'svc',
          entity: 'Accounts',
          operation: 'LIST_ENTITIES',
          restApiTool: rest1,
        ),
        IntegrationConnectorTool(
          name: 'list_accounts_2',
          description: 'Already reserved',
          connectionName: 'conn',
          connectionHost: 'host',
          connectionServiceName: 'svc',
          entity: 'Accounts2',
          operation: 'LIST_ENTITIES',
          restApiTool: restReserved,
        ),
        IntegrationConnectorTool(
          name: 'list_accounts',
          description: 'List accounts 2',
          connectionName: 'conn',
          connectionHost: 'host',
          connectionServiceName: 'svc',
          entity: 'AccountsDup',
          operation: 'LIST_ENTITIES',
          restApiTool: rest2,
        ),
      ];

      disambiguateToolNames(tools);

      expect(tools[0].name, 'list_accounts');
      expect(rest1.name, 'list_accounts');
      expect(tools[1].name, 'list_accounts_2');
      expect(restReserved.name, 'list_accounts_2');
      expect(tools[2].name, 'list_accounts_3');
      expect(rest2.name, 'list_accounts_3');
      expect(tools[2].getDeclaration()!.name, 'list_accounts_3');
    });
  });

  group('7. MongoDbMemoryService (cbca417c4)', () {
    test('extracts Latin and CJK keywords, upserts idempotently, ranks by overlap + timestamp, and deduplicates', () async {
      final InMemoryMongoDbSessionClient client =
          InMemoryMongoDbSessionClient();
      final MongoDbMemoryService memoryService = MongoDbMemoryService(
        mongoClient: client,
        databaseName: 'test_adk_mem',
        maxResults: 10,
      );

      // Verify CJK + Latin mixed-script extraction and stop-word removal.
      final Set<String> extracted = memoryService.extractKeywords(
        'The AlphaAgent2026東京タワー deployed',
      );
      expect(extracted, contains('alphaagent2026東京タワー'));
      expect(extracted, contains('alphaagent2026'));
      expect(extracted, contains('東京タワー'));
      expect(extracted, contains('deployed'));
      expect(extracted, isNot(contains('the')));

      final Session session = Session(
        id: 'sess-1',
        appName: 'app-1',
        userId: 'user-1',
        events: <Event>[
          Event(
            id: 'e-1',
            invocationId: 'inv-1',
            author: 'user',
            timestamp: 100.0,
            content: Content.userText(
              'I love drinking espresso coffee every morning',
            ),
          ),
          Event(
            id: 'e-2',
            invocationId: 'inv-1',
            author: 'assistant',
            timestamp: 200.0,
            content: Content.modelText(
              'Espresso coffee has rich crema and aroma',
            ),
          ),
          // Duplicate text/author/timestamp in another event ID to test deduplication on search.
          Event(
            id: 'e-3',
            invocationId: 'inv-2',
            author: 'assistant',
            timestamp: 200.0,
            content: Content.modelText(
              'Espresso coffee has rich crema and aroma',
            ),
          ),
          Event(
            id: 'e-4',
            invocationId: 'inv-2',
            author: 'user',
            timestamp: 300.0,
            content: Content.userText('Green tea is also nice'),
          ),
        ],
      );

      await memoryService.addSessionToMemory(session);
      // Upserting the same events again should be idempotent.
      await memoryService.addEventsToMemory(
        appName: 'app-1',
        userId: 'user-1',
        sessionId: 'sess-1',
        events: session.events,
      );

      final SearchMemoryResponse response = await memoryService.searchMemory(
        appName: 'app-1',
        userId: 'user-1',
        query: 'espresso coffee crema',
      );

      // e-2 / e-3 matches 3 keywords (espresso, coffee, crema) and is deduplicated to 1 entry;
      // e-1 matches 2 keywords (espresso, coffee).
      expect(response.memories, hasLength(2));
      expect(
        response.memories[0].content.parts.first.text,
        'Espresso coffee has rich crema and aroma',
      );
      expect(response.memories[0].author, 'assistant');
      expect(
        response.memories[1].content.parts.first.text,
        'I love drinking espresso coffee every morning',
      );

      // Calling close() when client was injected does NOT close the injected client.
      await memoryService.close();
      expect(client.isClosed, isFalse);
    });

    test('tolerates MongoDbOperationFailure on createIndexes and rethrows unexpected errors', () async {
      final InMemoryMongoDbSessionClient rawClient =
          InMemoryMongoDbSessionClient();
      final _AlwaysFailCreateIndexesCollection opFailureCol =
          _AlwaysFailCreateIndexesCollection(
            rawClient.database('db').collection(defaultMemoriesCollection),
            MongoDbOperationFailure('IndexOptionsConflict', code: 85),
          );
      final _CustomMemoriesClient client1 = _CustomMemoriesClient(
        rawClient,
        opFailureCol,
      );
      final MongoDbMemoryService service1 = MongoDbMemoryService(
        mongoClient: client1,
        databaseName: 'db',
      );

      await service1.addEventsToMemory(
        appName: 'app',
        userId: 'u1',
        events: <Event>[
          Event(
            id: 'ev1',
            invocationId: 'inv',
            author: 'user',
            timestamp: 10.0,
            content: Content.userText('hello world'),
          ),
        ],
      );
      // Subsequent call does not re-attempt index creation because _indexesEnsured is true.
      await service1.searchMemory(appName: 'app', userId: 'u1', query: 'hello');
      expect(opFailureCol.createIndexesCalls, 1);

      // Non-OperationFailure errors are rethrown and allow retry.
      final _AlwaysFailCreateIndexesCollection stateErrCol =
          _AlwaysFailCreateIndexesCollection(
            rawClient.database('db').collection(defaultMemoriesCollection),
            StateError('network down'),
          );
      final _CustomMemoriesClient client2 = _CustomMemoriesClient(
        rawClient,
        stateErrCol,
      );
      final MongoDbMemoryService service2 = MongoDbMemoryService(
        mongoClient: client2,
        databaseName: 'db',
      );
      await expectLater(
        service2.searchMemory(appName: 'app', userId: 'u1', query: 'hello'),
        throwsStateError,
      );
    });
  });

  group('8. BigQueryAgentAnalyticsPlugin workflow observations (c31856d17)', () {
    test(
      'records WORKFLOW_NODE_FIRST_OBSERVED, WORKFLOW_NODE_OBSERVATION_SUMMARY, capacity drops, and analytics views',
      () async {
        final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
        final List<String> executedViewSql = <String>[];
        final BigQueryAgentAnalyticsPlugin plugin =
            BigQueryAgentAnalyticsPlugin(
              projectId: 'proj',
              datasetId: 'ds',
              config: BigQueryLoggerConfig(
                maxObservationSummariesPerSegment: 1,
                createViews: true,
              ),
              sink: sink,
              analyticsViewExecutor: (List<String> statements) async {
                executedViewSql.addAll(statements);
              },
            );

        final InvocationContext ctx = _buildTestInvocationContext(
          invocationId: 'inv-wf',
        );
        await plugin.beforeRunCallback(invocationContext: ctx);

        // Emit two events for node_a (run 1) and one event for node_b (exceeding capacity=1).
        await plugin.onEventCallback(
          invocationContext: ctx,
          event: Event(
            id: 'e-node-a-1',
            invocationId: 'inv-wf',
            author: 'node_a',
            nodePath: 'node_a@run1',
            content: Content.modelText('step 1'),
          ),
        );
        await plugin.onEventCallback(
          invocationContext: ctx,
          event: Event(
            id: 'e-node-a-2',
            invocationId: 'inv-wf',
            author: 'node_a',
            nodePath: 'node_a@run1',
            content: Content.modelText('step 2'),
          ),
        );
        await plugin.onEventCallback(
          invocationContext: ctx,
          event: Event(
            id: 'e-node-b-1',
            invocationId: 'inv-wf',
            author: 'node_b',
            nodePath: 'node_b@run2',
            content: Content.modelText('step b'),
          ),
        );

        await plugin.afterRunCallback(invocationContext: ctx);
        await plugin.flush();

        final List<String?> eventTypes = sink.rows
            .map((Map<String, Object?> r) => r['event_type'] as String?)
            .toList();
        expect(eventTypes, contains('WORKFLOW_NODE_FIRST_OBSERVED'));
        expect(eventTypes, contains('WORKFLOW_NODE_OBSERVATION_SUMMARY'));
        expect(eventTypes, contains('INVOCATION_COMPLETED'));

        // Only 1 summary row emitted because maxObservationSummariesPerSegment = 1;
        // node_b triggered workflow_observation_capacity drop stat.
        final List<Map<String, Object?>> summaries = sink.rows
            .where(
              (Map<String, Object?> r) =>
                  r['event_type'] == 'WORKFLOW_NODE_OBSERVATION_SUMMARY',
            )
            .toList();
        expect(summaries, hasLength(1));
        final Map<String, Object?> summaryAttributes =
            (jsonDecode(summaries.first['attributes']! as String) as Map)
                .cast<String, Object?>();
        final Map<String, Object?> summaryEnvelope =
            (summaryAttributes['adk'] as Map).cast<String, Object?>();
        expect(summaryEnvelope['observed_event_count'], 2);
        expect(summaryEnvelope['truncated_node_count'], 1);

        expect(plugin.dropStats.workflowObservationCapacity, 1);
        expect(plugin.getDropStats()['workflow_observation_capacity'], 1);

        // Verify new analytics views were created.
        expect(
          executedViewSql.any(
            (String sql) => sql.contains('v_workflow_node_observation_summary'),
          ),
          isTrue,
        );
        expect(
          executedViewSql.any(
            (String sql) => sql.contains('v_workflow_node_first_observed'),
          ),
          isTrue,
        );
        expect(
          executedViewSql.any(
            (String sql) => sql.contains('v_invocation_error'),
          ),
          isTrue,
        );

        await plugin.shutdown();
      },
    );

    test('reserves terminal queue slots for INVOCATION_COMPLETED and INVOCATION_ERROR', () async {
      final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'proj',
        datasetId: 'ds',
        config: BigQueryLoggerConfig(queueMaxSize: 10),
        sink: sink,
      );
      expect(plugin.reservedTerminalQueueSlots, 2);

      // Simulate queue depth of 8 (which reaches non-terminal limit 10 - 2 = 8).
      plugin.queueSizeProvider = () => 8;
      final InvocationContext ctx = _buildTestInvocationContext(
        invocationId: 'inv-err',
      );
      await plugin.beforeRunCallback(invocationContext: ctx);
      expect(plugin.dropStats.queueFull, 1);

      // Terminal INVOCATION_ERROR can still use the reserved terminal slots (depth 8 < 10).
      await plugin.onRunErrorCallback(
        invocationContext: ctx,
        error: StateError('boom'),
      );
      expect(
        sink.rows.any(
          (Map<String, Object?> r) => r['event_type'] == 'INVOCATION_ERROR',
        ),
        isTrue,
      );
      await plugin.shutdown();
    });
  });

  group('9. LiteLlm tool calls quoted in answer text (6b00a3890)', () {
    test('ignores tool calls inside markdown code blocks, inline code, closed think blocks, and trailing prose', () {
      const String markdownQuoted = '''
Here is how a tool call is formatted:
```json
<tool_call>{"name": "delete_db", "arguments": {"confirm": true}}</tool_call>
```
And inline: `<tool_call>{"name": "rm_rf", "arguments": {}}</tool_call>`.
Also bare JSON after prose:
{"name": "delete_db", "arguments": {"confirm": true}}
''';
      final (List<Map<String, Object?>> calls, String? cleanedText) =
          parseToolCallsFromText(markdownQuoted);
      expect(calls, isEmpty);
      expect(cleanedText, markdownQuoted.trim());

      const String closedThinkBlock =
          '<think>Maybe call <tool_call>{"name": "secret_tool", "arguments": {}}</tool_call></think>'
          'Final answer without calling tools.';
      final (List<Map<String, Object?>> thinkCalls, String? thinkCleaned) =
          parseToolCallsFromText(closedThinkBlock);
      expect(thinkCalls, isEmpty);
      expect(thinkCleaned, closedThinkBlock);
    });

    test('extracts genuine <tool_call>, DeepSeek markers, and leading bare JSON after <think> or <|python_tag|>', () {
      const String xmlToolCall =
          'Let me check that for you.\n'
          '<tool_call>{"name": "get_weather", "arguments": {"city": "Seoul"}}</tool_call>';
      final (List<Map<String, Object?>> xmlCalls, String? cleanedXml) =
          parseToolCallsFromText(xmlToolCall);
      expect(xmlCalls, hasLength(1));
      final Map<String, Object?> xmlFn =
          xmlCalls.first['function'] as Map<String, Object?>;
      expect(xmlFn['name'], 'get_weather');
      expect(cleanedXml, 'Let me check that for you.');

      const String leadingBareJsonAfterThink =
          '<think>I should call search.</think>\n'
          '{"name": "search_docs", "arguments": {"query": "adk"}}';
      final (List<Map<String, Object?>> bareCalls, String? cleanedBare) =
          parseToolCallsFromText(leadingBareJsonAfterThink);
      expect(bareCalls, hasLength(1));
      final Map<String, Object?> bareFn =
          bareCalls.first['function'] as Map<String, Object?>;
      expect(bareFn['name'], 'search_docs');
      expect(cleanedBare, '<think>I should call search.</think>');

      const String deepSeekCall =
          'Checking weather...'
          '<｜tool▁calls▁begin｜>'
          '<｜tool▁call▁begin｜>function<｜tool▁sep｜>lookup_city\n'
          '```json\n{"city": "Busan"}\n```'
          '<｜tool▁call▁end｜>'
          '<｜tool▁calls▁end｜>';
      final (List<Map<String, Object?>> dsCalls, String? cleanedDs) =
          parseToolCallsFromText(deepSeekCall);
      expect(dsCalls, hasLength(1));
      final Map<String, Object?> dsFn =
          dsCalls.first['function'] as Map<String, Object?>;
      expect(dsFn['name'], 'lookup_city');
      expect(cleanedDs, 'Checking weather...');
    });

    test('streaming LiteLlm suppresses partial text when inline tool calls are parsed at stream end', () async {
      final LiteLlm llm = LiteLlm(
        model: 'openai/gpt-4o-mini',
        completionsInvoker: ({
          required Map<String, Object?> payload,
          required bool stream,
        }) async {
          return <Map<String, Object?>>[
            <String, Object?>{
              'choices': <Object?>[
                <String, Object?>{
                  'delta': <String, Object?>{
                    'content': 'Thinking... <tool_call>{"name": "calc", ',
                  },
                },
              ],
            },
            <String, Object?>{
              'choices': <Object?>[
                <String, Object?>{
                  'delta': <String, Object?>{
                    'content': '"arguments": {"x": 42}}</tool_call>',
                  },
                  'finish_reason': 'stop',
                },
              ],
            },
          ];
        },
      );

      final List<LlmResponse> responses = await llm
          .generateContent(LlmRequest(), stream: true)
          .toList();
      final LlmResponse finalResp = responses.last;
      expect(finalResp.partial, isNot(true));
      final List<Part> parts = finalResp.content?.parts ?? <Part>[];
      expect(
        parts.where((Part p) => p.text != null).map((Part p) => p.text),
        <String?>['Thinking...'],
      );
      expect(
        parts
            .where((Part p) => p.functionCall != null)
            .single
            .functionCall!
            .name,
        'calc',
      );
      expect(
        parts
            .where((Part p) => p.functionCall != null)
            .single
            .functionCall!
            .args,
        <String, dynamic>{'x': 42},
      );
    });
  });
}
