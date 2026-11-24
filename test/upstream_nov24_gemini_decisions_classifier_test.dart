import 'dart:async';
import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final Choice _route = Choice(
  instructions: 'Which team should handle this?',
  criteria: const <String, Object?>{
    'billing': 'Invoices and refunds',
    'technical': null,
  },
);

const Binary _urgent = Binary(
  instructions: 'Is this urgent?',
  criteria: 'Time-sensitive',
);

final Score _frustration = Score(
  instructions: 'How frustrated is the customer?',
  criteria: const <Object?>['Calm', 'Frustrated', 'Very angry'],
);

const Map<String, Object?> _choiceAnswer = <String, Object?>{
  'type': 'choice',
  'choice': 'billing',
  'probabilities': <String, Object?>{'billing': 0.9, 'technical': 0.1},
  'confidence': 0.9,
};

const Map<String, Object?> _noulAnswer = <String, Object?>{
  'type': 'noul',
  'noul': 0.95,
  'confidence': 0.95,
};

const Map<String, Object?> _scoreAnswer = <String, Object?>{
  'type': 'score',
  'score': 1.0,
  'probabilities': <String, Object?>{'0': 0.0, '1': 1.0, '2': 0.0},
  'confidence': 1.0,
};

class _FakeServer {
  _FakeServer(List<http.Response> responses)
    : _responses = List<http.Response>.from(responses);

  final List<http.Response> _responses;
  final List<http.Request> requests = <http.Request>[];

  http.Client createClient() {
    return MockClient((http.Request request) async {
      requests.add(request);
      return _responses.removeAt(0);
    });
  }

  Map<String, Object?> body([int index = 0]) {
    final Object? decoded = jsonDecode(requests[index].body);
    return Map<String, Object?>.from(decoded! as Map);
  }
}

http.Response _ok(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

http.Response _badRequest(String code) {
  return http.Response(
    jsonEncode(<String, Object?>{
      'error': <String, Object?>{'code': code, 'message': 'Request blocked.'},
    }),
    400,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

GeminiDecisionsClassifier _classifier(
  _FakeServer server, {
  String? apiKey = 'test-key',
  String? baseUrl,
  double? timeout,
  Map<String, String>? environment,
}) {
  return GeminiDecisionsClassifier(
    apiKey: apiKey,
    baseUrl: baseUrl,
    timeout: timeout,
    httpClient: server.createClient(),
    environment: environment,
  );
}

class _CountingClient extends http.BaseClient {
  _CountingClient(this._inner);

  final http.Client _inner;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request);
  }

  @override
  void close() {
    closed = true;
    _inner.close();
  }
}

void main() {
  group('GeminiDecisionsClassifier', () {
    test('sends every question type in one request', () async {
      final _FakeServer server = _FakeServer(<http.Response>[
        _ok(<String, Object?>{
          'answers': <String, Object?>{
            'route': _choiceAnswer,
            'urgent': _noulAnswer,
            'frustration': <String, Object?>{
              'type': 'score',
              'score': 1.05,
              'legend': <String, Object?>{
                '0': 'Calm',
                '1': 'Frustrated',
                '2': 'Very angry',
              },
              'probabilities': <String, Object?>{
                '0': 0.0,
                '1': 0.95,
                '2': 0.05,
              },
              'confidence': 0.95,
            },
          },
          'usage': <String, Object?>{
            'total_input_tokens': 100,
            'total_output_tokens': 0,
          },
        }),
      ]);

      final ClassifierResponse response = await _classifier(server).classify(
        input: 'I was charged twice!',
        questions: <String, ClassifierQuestion>{
          'route': _route,
          'urgent': _urgent,
          'frustration': _frustration,
        },
      );

      expect(server.requests, hasLength(1));
      final http.Request request = server.requests.single;
      expect(
        request.url.toString(),
        equals(
          '${GeminiDecisionsClassifier.defaultBaseUrl}'
          '${GeminiDecisionsClassifier.decisionsPath}',
        ),
      );
      expect(request.headers['x-goog-api-key'], equals('test-key'));
      expect(
        request.headers['x-goog-api-client']!.split(' '),
        contains(classifierClientLabel('gemini')),
      );

      final Map<String, Object?> body = server.body();
      expect(body['model'], equals('gemini-decision-1'));
      expect(body['input'], equals('I was charged twice!'));
      expect(
        body['questions'],
        equals(<String, Object?>{
          'route': <String, Object?>{
            'type': 'choice',
            'instructions': 'Which team should handle this?',
            'criteria': <String, Object?>{
              'billing': 'Invoices and refunds',
              'technical': '',
            },
          },
          'urgent': <String, Object?>{
            'type': 'noul',
            'instructions': 'Is this urgent?',
            'criteria': <String, Object?>{'true_description': 'Time-sensitive'},
          },
          'frustration': <String, Object?>{
            'type': 'score',
            'instructions': 'How frustrated is the customer?',
            'criteria': <String>['Calm', 'Frustrated', 'Very angry'],
          },
        }),
      );
      expect(
        response.answers,
        equals(<String, ClassifierAnswer>{
          'route': ChoiceAnswer(
            choice: 'billing',
            probabilities: const <String, double>{
              'billing': 0.9,
              'technical': 0.1,
            },
            confidence: 0.9,
          ),
          'urgent': BinaryAnswer(probability: 0.95, confidence: 0.95),
          'frustration': ScoreAnswer(
            score: 1.05,
            probabilities: const <int, double>{0: 0.0, 1: 0.95, 2: 0.05},
            confidence: 0.95,
          ),
        }),
      );
    });

    test('sends JSON input and criteria as JSON text', () async {
      final _FakeServer server = _FakeServer(<http.Response>[
        _ok(<String, Object?>{
          'answers': <String, Object?>{'urgent': _noulAnswer},
        }),
      ]);

      await _classifier(server).classify(
        input: const <String, Object?>{'message': 'Héllo', 'priority': 2},
        questions: const <String, ClassifierQuestion>{
          'urgent': Binary(
            instructions: 'Is this urgent?',
            criteria: <String>['p0', 'p1'],
          ),
        },
      );

      final Map<String, Object?> body = server.body();
      expect(body['input'], equals('{"message":"Héllo","priority":2}'));
      expect(
        body['questions'],
        equals(<String, Object?>{
          'urgent': <String, Object?>{
            'type': 'noul',
            'instructions': 'Is this urgent?',
            'criteria': <String, Object?>{'true_description': '["p0","p1"]'},
          },
        }),
      );
    });

    test('sends multimodal Content as typed parts', () async {
      final _FakeServer server = _FakeServer(<http.Response>[
        _ok(<String, Object?>{
          'answers': <String, Object?>{'urgent': _noulAnswer},
        }),
      ]);

      await _classifier(server).classify(
        input: Content(
          role: 'user',
          parts: <Part>[
            Part.text('What is in this photo?'),
            Part.fromInlineData(
              mimeType: 'image/png',
              data: utf8.encode('png-bytes'),
            ),
            Part.fromFileData(
              fileUri: 'https://example.com/clip.mp4',
              mimeType: 'video/mp4',
            ),
            Part.fromInlineData(
              mimeType: 'audio/wav',
              data: utf8.encode('wav'),
            ),
            Part.fromInlineData(
              mimeType: 'application/pdf',
              data: utf8.encode('%PDF'),
            ),
          ],
        ),
        questions: const <String, ClassifierQuestion>{
          'urgent': Binary(instructions: 'Is this urgent?'),
        },
      );

      expect(
        server.body()['input'],
        equals(<Map<String, Object?>>[
          <String, Object?>{'type': 'text', 'text': 'What is in this photo?'},
          <String, Object?>{
            'type': 'image',
            'data': 'cG5nLWJ5dGVz',
            'mime_type': 'image/png',
          },
          <String, Object?>{
            'type': 'video',
            'uri': 'https://example.com/clip.mp4',
            'mime_type': 'video/mp4',
          },
          <String, Object?>{
            'type': 'audio',
            'data': 'd2F2',
            'mime_type': 'audio/wav',
          },
          <String, Object?>{
            'type': 'document',
            'data': 'JVBERg==',
            'mime_type': 'application/pdf',
          },
        ]),
      );
    });

    test('skips thought parts', () async {
      final _FakeServer server = _FakeServer(<http.Response>[
        _ok(<String, Object?>{
          'answers': <String, Object?>{'urgent': _noulAnswer},
        }),
      ]);

      await _classifier(server).classify(
        input: Content(
          role: 'model',
          parts: <Part>[
            Part.text('Let me think.', thought: true),
            Part.text('Answer'),
          ],
        ),
        questions: const <String, ClassifierQuestion>{'urgent': _urgent},
      );

      expect(
        server.body()['input'],
        equals(<Map<String, Object?>>[
          <String, Object?>{'type': 'text', 'text': 'Answer'},
        ]),
      );
    });

    test('lowercases the MIME type', () async {
      final _FakeServer server = _FakeServer(<http.Response>[
        _ok(<String, Object?>{
          'answers': <String, Object?>{'urgent': _noulAnswer},
        }),
      ]);

      await _classifier(server).classify(
        input: Content(
          role: 'user',
          parts: <Part>[
            Part.fromInlineData(
              mimeType: 'IMAGE/PNG',
              data: utf8.encode('png'),
            ),
          ],
        ),
        questions: const <String, ClassifierQuestion>{'urgent': _urgent},
      );

      expect(
        server.body()['input'],
        equals(<Map<String, Object?>>[
          <String, Object?>{
            'type': 'image',
            'mime_type': 'image/png',
            'data': 'cG5n',
          },
        ]),
      );
    });

    test('rejects inline data part without a MIME type', () async {
      final _FakeServer server = _FakeServer(const <http.Response>[]);
      final Content content = Content(
        role: 'user',
        parts: <Part>[
          Part.fromInlineData(mimeType: '', data: utf8.encode('x')),
        ],
      );

      await expectLater(
        () => _classifier(server).classify(
          input: content,
          questions: const <String, ClassifierQuestion>{'urgent': _urgent},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'message',
            contains('MIME type'),
          ),
        ),
      );
      expect(server.requests, isEmpty);
    });

    test('rejects file part without a MIME type', () async {
      final _FakeServer server = _FakeServer(const <http.Response>[]);
      final Content content = Content(
        role: 'user',
        parts: <Part>[Part.fromFileData(fileUri: 'https://example.com/a.bin')],
      );

      await expectLater(
        () => _classifier(server).classify(
          input: content,
          questions: const <String, ClassifierQuestion>{'urgent': _urgent},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'message',
            contains('MIME type'),
          ),
        ),
      );
      expect(server.requests, isEmpty);
    });

    for (final (String label, http.Response reply) in <(String, http.Response)>[
      (
        'prompt_feedback block_reason',
        _ok(<String, Object?>{
          'prompt_feedback': <String, Object?>{'block_reason': 'safety'},
        }),
      ),
      ('HTTP 400 safety', _badRequest('safety')),
      ('HTTP 400 jailbreak', _badRequest('jailbreak')),
      ('HTTP 400 model_armor', _badRequest('model_armor')),
      ('HTTP 400 prohibited_content', _badRequest('prohibited_content')),
      ('HTTP 400 blocklist', _badRequest('blocklist')),
      ('HTTP 400 image_safety', _badRequest('image_safety')),
      ('HTTP 400 content_blocked', _badRequest('content_blocked')),
    ]) {
      test('blocked input refuses every question ($label)', () async {
        final _FakeServer server = _FakeServer(<http.Response>[reply]);

        final ClassifierResponse response = await _classifier(server).classify(
          input: 'bad input',
          questions: <String, ClassifierQuestion>{
            'route': _route,
            'urgent': _urgent,
          },
        );

        expect(
          response.answers,
          equals(<String, ClassifierAnswer>{
            'route': RefusalAnswer(),
            'urgent': RefusalAnswer(),
          }),
        );
      });
    }

    for (final (String label, http.Response reply) in <(String, http.Response)>[
      ('HTTP 400 invalid_argument', _badRequest('invalid_argument')),
      ('HTTP 500 boom', http.Response('boom', 500)),
    ]) {
      test('raises other errors ($label)', () async {
        final _FakeServer server = _FakeServer(<http.Response>[reply]);

        await expectLater(
          () => _classifier(server).classify(
            input: 'x',
            questions: const <String, ClassifierQuestion>{'urgent': _urgent},
          ),
          throwsA(
            isA<StateError>().having(
              (StateError e) => e.message,
              'message',
              contains('${reply.statusCode}'),
            ),
          ),
        );
      });
    }

    test('reads API key from GEMINI_API_KEY in the environment', () async {
      final _FakeServer server = _FakeServer(<http.Response>[
        _ok(<String, Object?>{
          'answers': <String, Object?>{'urgent': _noulAnswer},
        }),
      ]);
      final GeminiDecisionsClassifier classifier = _classifier(
        server,
        apiKey: null,
        environment: const <String, String>{'GEMINI_API_KEY': 'env-key'},
      );

      await classifier.classify(
        input: 'x',
        questions: const <String, ClassifierQuestion>{'urgent': _urgent},
      );

      expect(server.requests.single.headers['x-goog-api-key'], equals('env-key'));
    });

    test('prefers GOOGLE_API_KEY over GEMINI_API_KEY', () async {
      final _FakeServer server = _FakeServer(<http.Response>[
        _ok(<String, Object?>{
          'answers': <String, Object?>{'urgent': _noulAnswer},
        }),
      ]);
      final GeminiDecisionsClassifier classifier = _classifier(
        server,
        apiKey: null,
        environment: const <String, String>{
          'GOOGLE_API_KEY': 'google-key',
          'GEMINI_API_KEY': 'gemini-key',
        },
      );

      await classifier.classify(
        input: 'x',
        questions: const <String, ClassifierQuestion>{'urgent': _urgent},
      );

      expect(
        server.requests.single.headers['x-goog-api-key'],
        equals('google-key'),
      );
    });

    test('requires an API key before constructing a default client', () async {
      bool builtClient = false;
      final GeminiDecisionsClassifier classifier = GeminiDecisionsClassifier(
        environment: const <String, String>{},
        httpClientFactory: () {
          builtClient = true;
          return MockClient((_) async => _ok(const <String, Object?>{}));
        },
      );

      await expectLater(
        () => classifier.classify(
          input: 'x',
          questions: const <String, ClassifierQuestion>{'urgent': _urgent},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'message',
            contains('GOOGLE_API_KEY'),
          ),
        ),
      );
      expect(builtClient, isFalse);
    });

    test('baseUrl overrides default URL and trims trailing slashes', () async {
      final _FakeServer server = _FakeServer(<http.Response>[
        _ok(<String, Object?>{
          'answers': <String, Object?>{'urgent': _noulAnswer},
        }),
        _ok(<String, Object?>{
          'answers': <String, Object?>{'urgent': _noulAnswer},
        }),
      ]);

      await _classifier(
        server,
        baseUrl: 'https://other.example/',
      ).classify(
        input: 'x',
        questions: const <String, ClassifierQuestion>{'urgent': _urgent},
      );
      await _classifier(
        server,
        baseUrl: 'https://proxy.example/gemini',
      ).classify(
        input: 'x',
        questions: const <String, ClassifierQuestion>{'urgent': _urgent},
      );

      expect(
        server.requests[0].url.toString(),
        equals('https://other.example/v1beta/decisions'),
      );
      expect(
        server.requests[1].url.toString(),
        equals('https://proxy.example/gemini/v1beta/decisions'),
      );
    });

    test('validates timeout and enforces request timeout', () async {
      expect(
        () => GeminiDecisionsClassifier(apiKey: 'k', timeout: 0),
        throwsArgumentError,
      );
      expect(
        () => GeminiDecisionsClassifier(apiKey: 'k', timeout: -1),
        throwsArgumentError,
      );
      expect(
        () => GeminiDecisionsClassifier(apiKey: 'k', timeout: double.nan),
        throwsArgumentError,
      );
      expect(
        () => GeminiDecisionsClassifier(apiKey: 'k', timeout: double.infinity),
        throwsArgumentError,
      );

      final GeminiDecisionsClassifier classifier = GeminiDecisionsClassifier(
        apiKey: 'k',
        timeout: 0.01,
        httpClient: MockClient((http.Request request) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return _ok(<String, Object?>{
            'answers': <String, Object?>{'urgent': _noulAnswer},
          });
        }),
      );

      await expectLater(
        () => classifier.classify(
          input: 'x',
          questions: const <String, ClassifierQuestion>{'urgent': _urgent},
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('default client is reused across calls and closed via close()', () async {
      final _FakeServer server = _FakeServer(<http.Response>[
        _ok(<String, Object?>{
          'answers': <String, Object?>{'urgent': _noulAnswer},
        }),
        _ok(<String, Object?>{
          'answers': <String, Object?>{'urgent': _noulAnswer},
        }),
      ]);
      final List<_CountingClient> createdClients = <_CountingClient>[];
      final GeminiDecisionsClassifier classifier = GeminiDecisionsClassifier(
        apiKey: 'k',
        httpClientFactory: () {
          final _CountingClient client = _CountingClient(server.createClient());
          createdClients.add(client);
          return client;
        },
      );

      await classifier.classify(
        input: 'x',
        questions: const <String, ClassifierQuestion>{'urgent': _urgent},
      );
      await classifier.classify(
        input: 'x',
        questions: const <String, ClassifierQuestion>{'urgent': _urgent},
      );

      expect(server.requests, hasLength(2));
      expect(createdClients, hasLength(1));
      expect(createdClients.single.closed, isFalse);

      classifier.close();
      expect(createdClients.single.closed, isTrue);
    });

    test('rejects empty questions before sending a request', () async {
      final _FakeServer server = _FakeServer(const <http.Response>[]);

      await expectLater(
        () => _classifier(server).classify(
          input: 'x',
          questions: const <String, ClassifierQuestion>{},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'message',
            contains('at least one question'),
          ),
        ),
      );
      expect(server.requests, isEmpty);
    });

    test('rejects a question without instructions before sending a request', () async {
      final _FakeServer server = _FakeServer(const <http.Response>[]);

      await expectLater(
        () => _classifier(server).classify(
          input: 'x',
          questions: const <String, ClassifierQuestion>{'urgent': Binary()},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'message',
            contains('needs instructions'),
          ),
        ),
      );
      expect(server.requests, isEmpty);
    });

    test('rejects unsupported parts before sending a request', () async {
      final _FakeServer server = _FakeServer(const <http.Response>[]);
      final Content content = Content(
        role: 'user',
        parts: <Part>[
          Part.fromFunctionCall(name: 'f', args: <String, dynamic>{}),
        ],
      );

      await expectLater(
        () => _classifier(server).classify(
          input: content,
          questions: const <String, ClassifierQuestion>{'urgent': _urgent},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'message',
            contains('another kind of part'),
          ),
        ),
      );
      expect(server.requests, isEmpty);
    });

    for (final (
      String description,
      Map<String, Object?> answers,
      String expectedMessage,
    ) in <(String, Map<String, Object?>, String)>[
      ('missing answer', const <String, Object?>{}, "Null for 'route'"),
      (
        'wrong answer type',
        const <String, Object?>{'route': _noulAnswer},
        "_NoulAnswer for 'route'",
      ),
      (
        'unknown choice label',
        <String, Object?>{
          'route': <String, Object?>{..._choiceAnswer, 'choice': 'sales'},
        },
        "chose 'sales'",
      ),
      (
        'choice probabilities for wrong options',
        <String, Object?>{
          'route': <String, Object?>{
            ..._choiceAnswer,
            'probabilities': <String, Object?>{'billing': 0.9, 'sales': 0.1},
          },
        },
        'not for its options',
      ),
      (
        'confidence outside [0, 1]',
        <String, Object?>{
          'route': <String, Object?>{..._choiceAnswer, 'confidence': 1.1},
        },
        'confidence 1.1',
      ),
      (
        'score outside [0, top]',
        <String, Object?>{
          'frustration': <String, Object?>{..._scoreAnswer, 'score': 2.5},
        },
        'score 2.5',
      ),
      (
        'score probabilities for wrong levels',
        <String, Object?>{
          'frustration': <String, Object?>{
            ..._scoreAnswer,
            'probabilities': <String, Object?>{'0': 0.5, '1': 0.5},
          },
        },
        'not for its options',
      ),
    ]) {
      test('rejects answers that do not match the question ($description)', () async {
        final _FakeServer server = _FakeServer(<http.Response>[
          _ok(<String, Object?>{'answers': answers}),
        ]);
        final String name = answers.isEmpty ? 'route' : answers.keys.first;
        final ClassifierQuestion question = name == 'frustration'
            ? _frustration
            : _route;

        await expectLater(
          () => _classifier(server).classify(
            input: 'x',
            questions: <String, ClassifierQuestion>{name: question},
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.message.toString(),
              'message',
              contains(expectedMessage),
            ),
          ),
        );
      });
    }

    test('clamps rounding errors within tolerance', () async {
      final _FakeServer server = _FakeServer(<http.Response>[
        _ok(<String, Object?>{
          'answers': <String, Object?>{
            'urgent': const <String, Object?>{
              'type': 'noul',
              'noul': 1.0000004,
              'confidence': 1.0,
            },
            'frustration': <String, Object?>{
              ..._scoreAnswer,
              'score': -0.0000002,
              'probabilities': const <String, Object?>{
                '0': 1.0000003,
                '1': -0.0000001,
                '2': 0.0,
              },
            },
          },
        }),
      ]);

      final ClassifierResponse response = await _classifier(server).classify(
        input: 'x',
        questions: <String, ClassifierQuestion>{
          'urgent': _urgent,
          'frustration': _frustration,
        },
      );

      expect(
        response.answers,
        equals(<String, ClassifierAnswer>{
          'urgent': BinaryAnswer(probability: 1.0, confidence: 1.0),
          'frustration': ScoreAnswer(
            score: 0.0,
            probabilities: const <int, double>{0: 1.0, 1: 0.0, 2: 0.0},
            confidence: 1.0,
          ),
        }),
      );
    });
  });
}
