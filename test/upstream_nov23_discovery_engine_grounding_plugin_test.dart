import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

const Map<String, Object?> _metadata = <String, Object?>{
  'grounding_supports': <Map<String, Object?>>[
    <String, Object?>{
      'grounding_chunk_indices': <int>[0],
    },
  ],
};

class _RecordingClient implements GroundingClient {
  _RecordingClient({
    this.result,
    GroundingLimits? limits,
    this.errorToThrow,
  }) : limits = limits ?? GroundingLimits();

  @override
  final GroundingLimits limits;

  final GroundingResult? result;
  final Object? errorToThrow;
  final List<(String, List<FactChunk>)> sent = <(String, List<FactChunk>)>[];
  bool closed = false;

  @override
  Future<GroundingResult> checkGroundingAsync({
    required String answerCandidate,
    required List<FactChunk> facts,
  }) async {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    sent.add((answerCandidate, List<FactChunk>.from(facts)));
    return result ??
        GroundingResult(
          status: GroundingStatus.ok,
          numFactsEvaluated: facts.length,
        );
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class _FixedTextLlm extends BaseLlm {
  _FixedTextLlm(this.responseText) : super(model: 'fixed-test-model');

  final String responseText;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content.modelText(responseText),
      turnComplete: true,
    );
  }
}

CallbackContext _makeCallbackContext() {
  final Session session = Session(
    id: 'session_1',
    appName: 'grounding_app',
    userId: 'user_1',
  );
  final BaseAgent agent = LlmAgent(
    name: 'assistant',
    model: _FixedTextLlm('unused'),
  );
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_1',
    agent: agent,
    session: session,
  );
  return CallbackContext(invocationContext);
}

Future<(LlmResponse, LlmResponse?)> _respond(
  GroundingPlugin plugin, {
  String text = 'An answer.',
  bool partial = false,
  List<Part>? parts,
  Map<String, Object?>? metadata,
}) async {
  final LlmResponse response = LlmResponse(
    content: Content(
      role: 'model',
      parts: parts ?? <Part>[Part.text(text)],
    ),
    partial: partial,
    groundingMetadata: metadata,
  );
  final LlmResponse? replacement = await plugin.afterModelCallback(
    callbackContext: _makeCallbackContext(),
    llmResponse: response,
  );
  return (response, replacement);
}

Future<List<FactChunk>> _sentChunks(
  GroundingPlugin plugin,
  _RecordingClient client,
) async {
  await _respond(plugin);
  return client.sent.last.$2;
}

Map<String, Object?> _support(int start, int end, String text) {
  return <String, Object?>{
    'grounding_supports': <Map<String, Object?>>[
      <String, Object?>{
        'segment': <String, Object?>{
          'start_index': start,
          'end_index': end,
          'text': text,
        },
        'grounding_chunk_indices': <int>[0],
      },
    ],
  };
}

void main() {
  group('CheckGroundingClient limits', () {
    test('limits are exposed for callers', () {
      final GroundingLimits limits = GroundingLimits(
        maxFacts: 5,
        maxFactChars: 100,
      );

      final CheckGroundingClient client = CheckGroundingClient(
        projectId: 'test-project',
        limits: limits,
      );

      expect(client.limits, equals(limits));
      expect(client.limits.maxFacts, equals(5));
      expect(client.limits.maxFactChars, equals(100));
    });

    test('GroundingLimits rejects non-positive maxFactChars', () {
      expect(
        () => GroundingLimits(maxFactChars: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => GroundingLimits(maxFactChars: -1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('GroundingPlugin facts', () {
    test('fact is sent with its metadata', () async {
      final _RecordingClient client = _RecordingClient();
      final GroundingPlugin plugin = GroundingPlugin(
        client: client,
        facts: <Fact>[
          Fact(
            text: 'Water boils at 100 C.',
            title: 'Physics',
            link: 'https://example.com',
            attributes: const <String, String>{'topic': 'heat'},
          ),
        ],
      );

      final List<FactChunk> chunks = await _sentChunks(plugin, client);

      expect(
        chunks,
        equals(<FactChunk>[
          FactChunk(
            text: 'Water boils at 100 C.',
            title: 'Physics',
            link: 'https://example.com',
            attributes: const <String, String>{'topic': 'heat'},
          ),
        ]),
      );
    });

    test('long fact is split at sentence ends', () async {
      final _RecordingClient client = _RecordingClient(
        limits: GroundingLimits(maxFactChars: 38),
      );
      final GroundingPlugin plugin = GroundingPlugin(
        client: client,
        facts: <Fact>[
          Fact(text: 'One two three. Four five six. Seven eight nine.'),
        ],
      );

      final List<FactChunk> chunks = await _sentChunks(plugin, client);

      expect(
        chunks.map((FactChunk c) => c.text).toList(),
        equals(<String>[
          'One two three. Four five six.',
          'Seven eight nine.',
        ]),
      );
    });

    test('fact without boundaries is cut at the limit', () async {
      final _RecordingClient client = _RecordingClient(
        limits: GroundingLimits(maxFactChars: 4),
      );
      final GroundingPlugin plugin = GroundingPlugin(
        client: client,
        facts: <Fact>[Fact(text: 'abcdefghij')],
      );

      final List<FactChunk> chunks = await _sentChunks(plugin, client);

      expect(
        chunks.map((FactChunk c) => c.text).toList(),
        equals(<String>['abcd', 'efgh', 'ij']),
      );
    });

    for (final (String id, String text, List<String> expected)
        in <(String, String, List<String>)>[
          ('paragraph', 'First para.\n\nSecond para.', <String>[
            'First para.',
            'Second para.',
          ]),
          ('line', 'First line\nsecond line', <String>[
            'First line',
            'second line',
          ]),
          ('word', 'alpha beta gamma delta', <String>[
            'alpha beta',
            'gamma delta',
          ]),
        ]) {
      test('long fact prefers $id breaks', () async {
        final _RecordingClient client = _RecordingClient(
          limits: GroundingLimits(maxFactChars: 14),
        );
        final GroundingPlugin plugin = GroundingPlugin(
          client: client,
          facts: <Fact>[Fact(text: text)],
        );

        final List<FactChunk> chunks = await _sentChunks(plugin, client);

        expect(
          chunks.map((FactChunk c) => c.text).toList(),
          equals(expected),
        );
      });
    }

    test('identical facts are sent once', () async {
      final _RecordingClient client = _RecordingClient();
      final Fact first = Fact(text: 'Leave is 16 weeks.', title: 'Handbook');
      final Fact second = Fact(text: 'Leave is 16 weeks.', title: 'Handbook');
      final GroundingPlugin plugin = GroundingPlugin(
        client: client,
        facts: <Fact>[first, second],
      );

      final List<FactChunk> chunks = await _sentChunks(plugin, client);

      expect(first.id, equals(second.id));
      expect(first.id, startsWith('fact_'));
      expect(
        chunks.map((FactChunk c) => c.text).toList(),
        equals(<String>['Leave is 16 weeks.']),
      );
    });

    test('same text with different attributes is kept twice', () async {
      final _RecordingClient client = _RecordingClient();
      final GroundingPlugin plugin = GroundingPlugin(
        client: client,
        facts: <Fact>[
          Fact(
            text: 'Leave is 16 weeks.',
            attributes: const <String, String>{'tenant': 'a'},
          ),
          Fact(
            text: 'Leave is 16 weeks.',
            attributes: const <String, String>{'tenant': 'b'},
          ),
        ],
      );

      final List<FactChunk> chunks = await _sentChunks(plugin, client);

      expect(
        chunks.map((FactChunk c) => c.attributes).toList(),
        equals(<Map<String, String>>[
          <String, String>{'tenant': 'a'},
          <String, String>{'tenant': 'b'},
        ]),
      );
    });

    test('later fact with the same id replaces the earlier one', () async {
      final _RecordingClient client = _RecordingClient();
      final GroundingPlugin plugin = GroundingPlugin(
        client: client,
        facts: <Fact>[
          Fact(text: 'Old policy.', id: 'policy'),
          Fact(text: 'New policy.', id: 'policy'),
        ],
      );

      final List<FactChunk> chunks = await _sentChunks(plugin, client);

      expect(
        chunks.map((FactChunk c) => c.text).toList(),
        equals(<String>['New policy.']),
      );
    });

    test(
      'facts needing more than max_facts chunks throw ArgumentError',
      () {
        final _RecordingClient client = _RecordingClient(
          limits: GroundingLimits(maxFacts: 2, maxFactChars: 4),
        );

        expect(
          () => GroundingPlugin(
            client: client,
            facts: <Fact>[Fact(text: 'abcdefghij')],
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.toString(),
              'message',
              contains('more than max_facts'),
            ),
          ),
        );
      },
    );

    test(
      'mutating input list or attributes after construction does not change what is sent',
      () async {
        final _RecordingClient client = _RecordingClient();
        final Map<String, String> attrs = <String, String>{'k': 'v1'};
        final List<Fact> facts = <Fact>[
          Fact(text: 'A fact.', attributes: attrs),
        ];
        final GroundingPlugin plugin = GroundingPlugin(
          client: client,
          facts: facts,
        );

        attrs['k'] = 'v2';
        facts.add(Fact(text: 'Another fact.'));

        final List<FactChunk> chunks = await _sentChunks(plugin, client);

        expect(
          chunks.map((FactChunk c) => c.text).toList(),
          equals(<String>['A fact.']),
        );
        expect(chunks.single.attributes, equals(<String, String>{'k': 'v1'}));
      },
    );

    test('empty fact throws ArgumentError', () {
      expect(
        () => Fact(text: '  \n'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.toString(),
            'message',
            contains('must not be empty'),
          ),
        ),
      );
    });
  });

  group('GroundingPlugin checking responses', () {
    test('citations are attached to the response', () async {
      final GroundingPlugin plugin = GroundingPlugin(
        facts: <Fact>[Fact(text: 'A fact.')],
        client: _RecordingClient(
          result: const GroundingResult(
            status: GroundingStatus.ok,
            numFactsEvaluated: 1,
            metadata: _metadata,
          ),
        ),
      );

      final (LlmResponse response, LlmResponse? replacement) = await _respond(
        plugin,
      );

      expect(replacement, isNull);
      expect(response.groundingMetadata, equals(_metadata));
    });

    test('citations are added to metadata the model attached', () async {
      final Map<String, Object?> web = <String, Object?>{
        'web_search_queries': <String>['boiling point'],
        'grounding_chunks': <Map<String, Object?>>[<String, Object?>{}],
        'grounding_supports': <Map<String, Object?>>[
          <String, Object?>{
            'grounding_chunk_indices': <int>[0],
          },
        ],
      };
      final GroundingPlugin plugin = GroundingPlugin(
        facts: <Fact>[Fact(text: 'A fact.')],
        client: _RecordingClient(
          result: const GroundingResult(
            status: GroundingStatus.ok,
            numFactsEvaluated: 1,
            metadata: <String, Object?>{
              'grounding_chunks': <Map<String, Object?>>[<String, Object?>{}],
              'grounding_supports': <Map<String, Object?>>[
                <String, Object?>{
                  'grounding_chunk_indices': <int>[0],
                },
              ],
            },
          ),
        ),
      );

      final (LlmResponse response, _) = await _respond(plugin, metadata: web);

      final Map<String, Object?> combined =
          response.groundingMetadata! as Map<String, Object?>;
      expect(combined['web_search_queries'], equals(<String>['boiling point']));
      expect(combined['grounding_chunks'] as List<Object?>, hasLength(2));
      final List<Object?> supports =
          combined['grounding_supports']! as List<Object?>;
      expect(
        supports
            .map(
              (Object? s) =>
                  (s! as Map<String, Object?>)['grounding_chunk_indices'],
            )
            .toList(),
        equals(<List<int>>[
          <int>[0],
          <int>[1],
        ]),
      );
    });

    test('answer without citations gets no metadata', () async {
      final GroundingPlugin plugin = GroundingPlugin(
        facts: <Fact>[Fact(text: 'A fact.')],
        client: _RecordingClient(
          result: const GroundingResult(
            status: GroundingStatus.ok,
            numFactsEvaluated: 1,
            metadata: <String, Object?>{},
          ),
        ),
      );

      final (LlmResponse response, _) = await _respond(plugin);

      expect(response.groundingMetadata, isNull);
    });

    test('answer text is sent unchanged', () async {
      final _RecordingClient client = _RecordingClient();
      final GroundingPlugin plugin = GroundingPlugin(
        facts: <Fact>[Fact(text: 'A fact.')],
        client: client,
      );

      await _respond(plugin, text: '\n  An answer.  ');

      expect(client.sent.single.$1, equals('\n  An answer.  '));
    });

    for (final (String id, String text, bool partial) in <(String, String, bool)>[
      ('partial', 'Water boils', true),
      ('blank', '  ', false),
    ]) {
      test('$id response is not checked', () async {
        final _RecordingClient client = _RecordingClient();
        final GroundingPlugin plugin = GroundingPlugin(
          facts: <Fact>[Fact(text: 'A fact.')],
          client: client,
        );

        final (LlmResponse response, _) = await _respond(
          plugin,
          text: text,
          partial: partial,
        );

        expect(client.sent, isEmpty);
        expect(response.groundingMetadata, isNull);
      });
    }

    test('thoughts are not sent as part of the answer', () async {
      final _RecordingClient client = _RecordingClient();
      final GroundingPlugin plugin = GroundingPlugin(
        facts: <Fact>[Fact(text: 'A fact.')],
        client: client,
      );

      await _respond(
        plugin,
        parts: <Part>[
          Part.text('Thinking hard.', thought: true),
          Part.text('Answer.'),
        ],
      );

      expect(client.sent.single.$1, equals('Answer.'));
    });

    test('response that calls a tool is not checked', () async {
      final _RecordingClient client = _RecordingClient();
      final GroundingPlugin plugin = GroundingPlugin(
        facts: <Fact>[Fact(text: 'A fact.')],
        client: client,
      );

      await _respond(
        plugin,
        parts: <Part>[
          Part.text('Let me look that up.'),
          Part.fromFunctionCall(name: 'lookup'),
        ],
      );

      expect(client.sent, isEmpty);
    });

    for (final (
      String id,
      List<Part> parts,
      Map<String, Object?> support,
      List<(int, int, int, String)> expected,
    )
        in <(
          String,
          List<Part>,
          Map<String, Object?>,
          List<(int, int, int, String)>,
        )>[
          (
            'after_thought',
            <Part>[Part.text('Hmm.', thought: true), Part.text('Yes.')],
            _support(0, 4, 'Yes.'),
            <(int, int, int, String)>[(1, 0, 4, 'Yes.')],
          ),
          (
            'after_non_ascii',
            <Part>[Part.text('Café. '), Part.text('Boils.')],
            _support(7, 13, 'Boils.'),
            <(int, int, int, String)>[(1, 0, 6, 'Boils.')],
          ),
          (
            'spans_parts',
            <Part>[Part.text('Water '), Part.text('boils.')],
            _support(0, 12, 'Water boils.'),
            <(int, int, int, String)>[
              (0, 0, 6, 'Water '),
              (1, 0, 6, 'boils.'),
            ],
          ),
        ]) {
      test('citation segments point into the part they cite ($id)', () async {
        final GroundingPlugin plugin = GroundingPlugin(
          facts: <Fact>[Fact(text: 'A fact.')],
          client: _RecordingClient(
            result: GroundingResult(
              status: GroundingStatus.ok,
              numFactsEvaluated: 1,
              metadata: support,
            ),
          ),
        );

        final (LlmResponse response, _) = await _respond(plugin, parts: parts);

        final Map<String, Object?> metadata =
            response.groundingMetadata! as Map<String, Object?>;
        final List<Object?> supports =
            metadata['grounding_supports']! as List<Object?>;
        final List<(int, int, int, String)> actual = supports.map((Object? s) {
          final Map<String, Object?> seg =
              (s! as Map<String, Object?>)['segment']! as Map<String, Object?>;
          return (
            seg['part_index']! as int,
            seg['start_index']! as int,
            seg['end_index']! as int,
            seg['text']! as String,
          );
        }).toList();

        expect(actual, equals(expected));
      });
    }

    test('client error leaves the response unchanged', () async {
      final _RecordingClient client = _RecordingClient(
        errorToThrow: StateError('boom'),
      );
      final List<GroundingResult> results = <GroundingResult>[];
      final GroundingPlugin plugin = GroundingPlugin(
        client: client,
        facts: <Fact>[Fact(text: 'A fact.')],
        onResult: ({
          required CallbackContext callbackContext,
          required LlmResponse llmResponse,
          required GroundingResult groundingResult,
        }) {
          results.add(groundingResult);
          return null;
        },
      );

      final (LlmResponse response, LlmResponse? replacement) = await _respond(
        plugin,
      );

      expect(replacement, isNull);
      expect(response.groundingMetadata, isNull);
      expect(results, hasLength(1));
      expect(results.single.status, equals(GroundingStatus.apiError));
      expect(results.single.error, contains('boom'));
    });
  });

  group('GroundingPlugin onResult hook', () {
    test(
      'onResult sees skipped check when no facts are registered',
      () async {
        final _RecordingClient client = _RecordingClient();
        final List<GroundingStatus> statuses = <GroundingStatus>[];
        final GroundingPlugin plugin = GroundingPlugin(
          client: client,
          onResult: ({
            required CallbackContext callbackContext,
            required LlmResponse llmResponse,
            required GroundingResult groundingResult,
          }) {
            statuses.add(groundingResult.status);
            return null;
          },
        );

        await _respond(plugin);

        expect(client.sent, isEmpty);
        expect(statuses, equals(<GroundingStatus>[GroundingStatus.skippedNoFacts]));
      },
    );

    test('onResult sees the response with citations attached', () async {
      final List<Object?> seen = <Object?>[];
      final GroundingPlugin plugin = GroundingPlugin(
        facts: <Fact>[Fact(text: 'A fact.')],
        client: _RecordingClient(
          result: const GroundingResult(
            status: GroundingStatus.ok,
            numFactsEvaluated: 1,
            metadata: _metadata,
          ),
        ),
        onResult: ({
          required CallbackContext callbackContext,
          required LlmResponse llmResponse,
          required GroundingResult groundingResult,
        }) {
          seen.add(llmResponse.groundingMetadata);
          return null;
        },
      );

      await _respond(plugin);

      expect(seen, equals(<Object?>[_metadata]));
    });

    for (final bool isAsync in <bool>[false, true]) {
      test(
        'onResult can replace the response (${isAsync ? 'async' : 'sync'})',
        () async {
          final LlmResponse fallback = LlmResponse(
            content: Content.modelText('Unsure.'),
          );
          final GroundingPlugin plugin = GroundingPlugin(
            facts: <Fact>[Fact(text: 'A fact.')],
            client: _RecordingClient(),
            onResult: isAsync
                ? ({
                    required CallbackContext callbackContext,
                    required LlmResponse llmResponse,
                    required GroundingResult groundingResult,
                  }) async => fallback
                : ({
                    required CallbackContext callbackContext,
                    required LlmResponse llmResponse,
                    required GroundingResult groundingResult,
                  }) => fallback,
          );

          final (_, LlmResponse? replacement) = await _respond(plugin);

          expect(identical(replacement, fallback), isTrue);
        },
      );
    }
  });

  group('GroundingPlugin lifecycle & runner integration', () {
    test('default client needs a project', () {
      expect(
        () => GroundingPlugin(environment: const <String, String>{}),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.toString(),
            'message',
            contains('project_id is required'),
          ),
        ),
      );
    });

    test('close leaves a client passed in open', () async {
      final _RecordingClient client = _RecordingClient();
      final GroundingPlugin plugin = GroundingPlugin(client: client);

      await plugin.close();

      expect(client.closed, isFalse);
    });

    test('close closes the default client without error', () async {
      final GroundingPlugin plugin = GroundingPlugin(
        environment: const <String, String>{
          'GOOGLE_CLOUD_PROJECT': 'test-project',
        },
      );

      await expectLater(plugin.close(), completes);
    });

    test('final answer carries citations in a runner', () async {
      final GroundingPlugin plugin = GroundingPlugin(
        facts: <Fact>[Fact(text: 'Water boils at 100 C.')],
        client: _RecordingClient(
          result: const GroundingResult(
            status: GroundingStatus.ok,
            numFactsEvaluated: 1,
            metadata: _metadata,
          ),
        ),
      );
      final LlmAgent agent = LlmAgent(
        name: 'assistant',
        model: _FixedTextLlm('It boils at 100 C.'),
      );
      final InMemoryRunner runner = InMemoryRunner(
        app: App(
          name: 'grounded_app',
          rootAgent: agent,
          plugins: <BasePlugin>[plugin],
        ),
      );
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
      );

      final List<Event> events = await runner
          .runAsync(
            userId: 'user_1',
            sessionId: session.id,
            newMessage: Content.userText('When does water boil?'),
          )
          .toList();

      expect(events, isNotEmpty);
      expect(events.last.groundingMetadata, equals(_metadata));
    });
  });
}
