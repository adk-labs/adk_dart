import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/cli.dart';
import 'package:test/test.dart';

class _CapturedSink {
  _CapturedSink() : _controller = StreamController<List<int>>() {
    _controller.stream.listen(_bytes.addAll);
    sink = IOSink(_controller.sink);
  }

  final StreamController<List<int>> _controller;
  final List<int> _bytes = <int>[];
  late final IOSink sink;

  Future<String> closeAndRead() async {
    await sink.flush();
    await sink.close();
    await _controller.done;
    return utf8.decode(_bytes);
  }
}

class _RecordedRequest {
  _RecordedRequest({
    required this.method,
    required this.path,
    required this.queryParameters,
    required this.authorization,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> queryParameters;
  final String? authorization;
  final String body;
}

void main() {
  group('HttpAgentEngineRuntimesClient E2E over local HttpServer', () {
    const String project = 'test-gcp-project';
    const String region = 'us-central1';
    const String collectionPath =
        '/v1beta1/projects/$project/locations/$region/reasoningEngines';

    late HttpServer server;
    late List<_RecordedRequest> requests;
    late FutureOr<void> Function(HttpRequest request, String body) handler;

    setUp(() async {
      requests = <_RecordedRequest>[];
      handler = (HttpRequest request, String body) async {
        request.response
          ..statusCode = HttpStatus.notFound
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(<String, Object?>{'error': <String, Object?>{'message': 'not handled'}}));
        await request.response.close();
      };
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        final String body = await utf8.decoder.bind(request).join();
        requests.add(
          _RecordedRequest(
            method: request.method,
            path: request.uri.path,
            queryParameters: Map<String, String>.of(request.uri.queryParameters),
            authorization: request.headers.value(HttpHeaders.authorizationHeader),
            body: body,
          ),
        );
        await handler(request, body);
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    String baseUrl() => 'http://${server.address.address}:${server.port}/v1beta1';

    HttpAgentEngineRuntimesClient createClient({
      AgentEngineAccessTokenProvider? accessTokenProvider,
      Map<String, String>? environment,
    }) {
      return HttpAgentEngineRuntimesClient(
        project: project,
        region: region,
        endpointBaseUrl: baseUrl(),
        accessTokenProvider: accessTokenProvider,
        environment:
            environment ??
            const <String, String>{
              'GOOGLE_OAUTH_ACCESS_TOKEN': 'test-bearer-token',
            },
        operationPollInterval: Duration.zero,
      );
    }

    test('list sends display_name filter and follows nextPageToken pagination', () async {
      handler = (HttpRequest request, String body) async {
        expect(request.method, 'GET');
        expect(request.uri.path, collectionPath);
        final String? pageToken = request.uri.queryParameters['pageToken'];
        final Map<String, Object?> payload = pageToken == null
            ? <String, Object?>{
                'reasoningEngines': <Map<String, Object?>>[
                  <String, Object?>{
                    'name':
                        'projects/$project/locations/$region/reasoningEngines/101',
                    'displayName': 'My Agent',
                    'updateTime': '2026-11-20T01:00:00Z',
                  },
                ],
                'nextPageToken': 'page-2',
              }
            : <String, Object?>{
                'reasoningEngines': <Map<String, Object?>>[
                  <String, Object?>{
                    'name':
                        'projects/$project/locations/$region/reasoningEngines/102',
                    'displayName': 'My Agent',
                    'updateTime': '2026-11-21T02:00:00Z',
                  },
                ],
              };
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(payload));
        await request.response.close();
      };

      final HttpAgentEngineRuntimesClient client = createClient();
      addTearDown(client.close);

      final List<AgentEngineRuntimeInfo> runtimes = await client.list(
        filter: 'display_name="My Agent"',
      );

      expect(runtimes, hasLength(2));
      expect(
        runtimes.map((AgentEngineRuntimeInfo r) => r.name),
        <String>[
          'projects/$project/locations/$region/reasoningEngines/101',
          'projects/$project/locations/$region/reasoningEngines/102',
        ],
      );
      expect(runtimes.first.displayName, 'My Agent');
      expect(runtimes.first.updateTime, '2026-11-20T01:00:00Z');
      expect(runtimes.last.updateTime, '2026-11-21T02:00:00Z');

      expect(requests, hasLength(2));
      expect(requests[0].authorization, 'Bearer test-bearer-token');
      expect(requests[0].queryParameters['filter'], 'display_name="My Agent"');
      expect(requests[0].queryParameters.containsKey('pageToken'), isFalse);
      expect(requests[1].queryParameters['filter'], 'display_name="My Agent"');
      expect(requests[1].queryParameters['pageToken'], 'page-2');
    });

    test('create (with LRO polling), update (with updateMask), and delete work over HTTP', () async {
      int opPolls = 0;
      const String createdName =
          'projects/$project/locations/$region/reasoningEngines/9001';
      const String operationName =
          'projects/$project/locations/$region/operations/op-create-9001';

      handler = (HttpRequest request, String body) async {
        if (request.method == 'POST' && request.uri.path == collectionPath) {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{
                'name': operationName,
                'done': false,
              }),
            );
          await request.response.close();
          return;
        }
        if (request.method == 'GET' &&
            request.uri.path == '/v1beta1/$operationName') {
          opPolls += 1;
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(
                opPolls < 2
                    ? <String, Object?>{'name': operationName, 'done': false}
                    : <String, Object?>{
                        'name': operationName,
                        'done': true,
                        'response': <String, Object?>{
                          'name': createdName,
                          'displayName': 'Created Agent',
                          'updateTime': '2026-11-24T00:00:00Z',
                        },
                      },
              ),
            );
          await request.response.close();
          return;
        }
        if (request.method == 'PATCH' &&
            request.uri.path == '/v1beta1/$createdName') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{
                'name': createdName,
                'displayName': 'Updated Agent',
              }),
            );
          await request.response.close();
          return;
        }
        if (request.method == 'DELETE' &&
            request.uri.path == '/v1beta1/$createdName') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(<String, Object?>{'done': true}));
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      };

      final HttpAgentEngineRuntimesClient client = createClient(
        accessTokenProvider: () async => 'injected-token',
      );
      addTearDown(client.close);

      final AgentEngineRuntimeInfo created = await client.create(
        config: const <String, Object?>{'display_name': 'Created Agent'},
      );
      expect(created.name, createdName);
      expect(created.displayName, 'Created Agent');
      expect(created.updateTime, '2026-11-24T00:00:00Z');
      expect(opPolls, 2);

      // Update using short ID to verify normalization + updateMask derivation.
      final String updatedName = await client.update(
        name: '9001',
        config: const <String, Object?>{
          'display_name': 'Updated Agent',
          'description': 'New description',
        },
      );
      expect(updatedName, createdName);

      final _RecordedRequest patchReq = requests.firstWhere(
        (_RecordedRequest r) => r.method == 'PATCH',
      );
      expect(patchReq.authorization, 'Bearer injected-token');
      expect(patchReq.path, '/v1beta1/$createdName');
      expect(patchReq.queryParameters['updateMask'], 'display_name,description');
      expect(
        jsonDecode(patchReq.body),
        <String, Object?>{
          'display_name': 'Updated Agent',
          'description': 'New description',
        },
      );

      await client.delete(name: createdName);
      final _RecordedRequest deleteReq = requests.firstWhere(
        (_RecordedRequest r) => r.method == 'DELETE',
      );
      expect(deleteReq.path, '/v1beta1/$createdName');
    });

    test('HTTP 403 and 500 responses throw AgentEngineDeployException with status and message', () async {
      handler = (HttpRequest request, String body) async {
        if (request.method == 'GET') {
          request.response
            ..statusCode = HttpStatus.forbidden
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{
                'error': <String, Object?>{
                  'code': 403,
                  'status': 'PERMISSION_DENIED',
                  'message': 'Caller does not have aiplatform.reasoningEngines.list',
                },
              }),
            );
          await request.response.close();
          return;
        }
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{
                'code': 500,
                'status': 'INTERNAL',
                'message': 'Backend unavailable',
              },
            }),
          );
        await request.response.close();
      };

      final HttpAgentEngineRuntimesClient client = createClient();
      addTearDown(client.close);

      await expectLater(
        () => client.list(filter: 'display_name="My Agent"'),
        throwsA(
          isA<AgentEngineDeployException>().having(
            (AgentEngineDeployException e) => e.message,
            'message',
            allOf(
              contains('HTTP 403'),
              contains('PERMISSION_DENIED'),
              contains('aiplatform.reasoningEngines.list'),
            ),
          ),
        ),
      );

      await expectLater(
        () => client.create(),
        throwsA(
          isA<AgentEngineDeployException>().having(
            (AgentEngineDeployException e) => e.message,
            'message',
            allOf(
              contains('HTTP 500'),
              contains('INTERNAL'),
              contains('Backend unavailable'),
            ),
          ),
        ),
      );
    });

    group('deployToAgentEngine E2E flows over real HTTP', () {
      late Directory tempRoot;
      late Directory agentDir;

      setUp(() {
        tempRoot = Directory.systemTemp.createTempSync('adk_http_ae_e2e_');
        agentDir = Directory('${tempRoot.path}${Platform.pathSeparator}my_agent')
          ..createSync(recursive: true);
      });

      tearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      test('duplicate display_name warns to stderr and creates a new runtime', () async {
        const String existingName =
            'projects/$project/locations/$region/reasoningEngines/111';
        const String createdName =
            'projects/$project/locations/$region/reasoningEngines/222';

        handler = (HttpRequest request, String body) async {
          if (request.method == 'GET' && request.uri.path == collectionPath) {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode(<String, Object?>{
                  'reasoningEngines': <Map<String, Object?>>[
                    <String, Object?>{
                      'name': existingName,
                      'displayName': 'Dup Agent',
                      'updateTime': '2026-11-20T10:00:00Z',
                    },
                  ],
                }),
              );
          } else if (request.method == 'POST' &&
              request.uri.path == collectionPath) {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode(<String, Object?>{
                  'name': createdName,
                  'updateTime': '2026-11-24T10:00:00Z',
                }),
              );
          } else if (request.method == 'PATCH' &&
              request.uri.path == '/v1beta1/$createdName') {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(<String, Object?>{'name': createdName}));
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        };

        final HttpAgentEngineRuntimesClient client = createClient();
        addTearDown(client.close);
        final _CapturedSink out = _CapturedSink();
        final _CapturedSink err = _CapturedSink();

        final String result = await deployToAgentEngine(
          client: client,
          agentFolder: agentDir.path,
          project: project,
          region: region,
          displayName: 'Dup Agent',
          out: out.sink,
          err: err.sink,
        );

        final String stdoutText = await out.closeAndRead();
        final String stderrText = await err.closeAndRead();

        expect(result, createdName);
        expect(stdoutText, contains('Created a new instance: $createdName'));
        expect(stderrText, contains('WARNING: 1 Agent Runtime(s)'));
        expect(stderrText, contains(existingName));
        expect(
          requests.map((_RecordedRequest r) => r.method),
          <String>['GET', 'POST', 'PATCH'],
        );
      });

      test('--update_if_exists updates single match in place without POST', () async {
        const String existingName =
            'projects/$project/locations/$region/reasoningEngines/333';

        handler = (HttpRequest request, String body) async {
          if (request.method == 'GET' && request.uri.path == collectionPath) {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode(<String, Object?>{
                  'reasoningEngines': <Map<String, Object?>>[
                    <String, Object?>{
                      'name': existingName,
                      'displayName': 'Single Agent',
                      'updateTime': '2026-11-22T00:00:00Z',
                    },
                  ],
                }),
              );
          } else if (request.method == 'PATCH' &&
              request.uri.path == '/v1beta1/$existingName') {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(<String, Object?>{'name': existingName}));
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        };

        final HttpAgentEngineRuntimesClient client = createClient();
        addTearDown(client.close);
        final _CapturedSink out = _CapturedSink();
        final _CapturedSink err = _CapturedSink();

        final String result = await deployToAgentEngine(
          client: client,
          agentFolder: agentDir.path,
          project: project,
          region: region,
          displayName: 'Single Agent',
          updateIfExists: true,
          out: out.sink,
          err: err.sink,
        );

        final String stdoutText = await out.closeAndRead();
        final String stderrText = await err.closeAndRead();

        expect(result, existingName);
        expect(
          stdoutText,
          contains(
            'Updating existing instance with display name "Single Agent": $existingName',
          ),
        );
        expect(stderrText, isEmpty);
        expect(
          requests.map((_RecordedRequest r) => r.method),
          <String>['GET', 'PATCH'],
        );
      });

      test('--update_if_exists creates when 0 matches exist', () async {
        const String createdName =
            'projects/$project/locations/$region/reasoningEngines/444';

        handler = (HttpRequest request, String body) async {
          if (request.method == 'GET' && request.uri.path == collectionPath) {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(<String, Object?>{'reasoningEngines': <Object?>[]}));
          } else if (request.method == 'POST' &&
              request.uri.path == collectionPath) {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(<String, Object?>{'name': createdName}));
          } else if (request.method == 'PATCH' &&
              request.uri.path == '/v1beta1/$createdName') {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(<String, Object?>{'name': createdName}));
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        };

        final HttpAgentEngineRuntimesClient client = createClient();
        addTearDown(client.close);

        final String result = await deployToAgentEngine(
          client: client,
          agentFolder: agentDir.path,
          project: project,
          region: region,
          displayName: 'Fresh Agent',
          updateIfExists: true,
        );

        expect(result, createdName);
        expect(
          requests.map((_RecordedRequest r) => r.method),
          <String>['GET', 'POST', 'PATCH'],
        );
      });

      test('--update_if_exists fails on 2+ matches without POST or PATCH', () async {
        const String first =
            'projects/$project/locations/$region/reasoningEngines/501';
        const String second =
            'projects/$project/locations/$region/reasoningEngines/502';

        handler = (HttpRequest request, String body) async {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{
                'reasoningEngines': <Map<String, Object?>>[
                  <String, Object?>{
                    'name': first,
                    'displayName': 'Ambiguous Agent',
                    'updateTime': '2026-11-20T00:00:00Z',
                  },
                  <String, Object?>{
                    'name': second,
                    'displayName': 'Ambiguous Agent',
                    'updateTime': '2026-11-21T00:00:00Z',
                  },
                ],
              }),
            );
          await request.response.close();
        };

        final HttpAgentEngineRuntimesClient client = createClient();
        addTearDown(client.close);

        await expectLater(
          () => deployToAgentEngine(
            client: client,
            agentFolder: agentDir.path,
            project: project,
            region: region,
            displayName: 'Ambiguous Agent',
            updateIfExists: true,
          ),
          throwsA(
            isA<AgentEngineDeployException>().having(
              (AgentEngineDeployException e) => e.message,
              'message',
              allOf(
                contains('2 Agent Runtimes'),
                contains(first),
                contains(second),
                contains('--agent_engine_id'),
              ),
            ),
          ),
        );

        expect(requests.map((_RecordedRequest r) => r.method), <String>['GET']);
      });

      test('deletes newly created runtime when PATCH fails', () async {
        const String createdName =
            'projects/$project/locations/$region/reasoningEngines/601';

        handler = (HttpRequest request, String body) async {
          if (request.method == 'GET' && request.uri.path == collectionPath) {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(<String, Object?>{}));
          } else if (request.method == 'POST' &&
              request.uri.path == collectionPath) {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(<String, Object?>{'name': createdName}));
          } else if (request.method == 'PATCH' &&
              request.uri.path == '/v1beta1/$createdName') {
            request.response
              ..statusCode = HttpStatus.internalServerError
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode(<String, Object?>{
                  'error': <String, Object?>{
                    'code': 500,
                    'message': 'Container build failed',
                  },
                }),
              );
          } else if (request.method == 'DELETE' &&
              request.uri.path == '/v1beta1/$createdName') {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(<String, Object?>{}));
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        };

        final HttpAgentEngineRuntimesClient client = createClient();
        addTearDown(client.close);

        await expectLater(
          () => deployToAgentEngine(
            client: client,
            agentFolder: agentDir.path,
            project: project,
            region: region,
            displayName: 'Failing New Agent',
            updateIfExists: true,
          ),
          throwsA(
            isA<AgentEngineDeployException>().having(
              (AgentEngineDeployException e) => e.message,
              'message',
              allOf(contains('HTTP 500'), contains('Container build failed')),
            ),
          ),
        );

        expect(
          requests.map((_RecordedRequest r) => r.method),
          <String>['GET', 'POST', 'PATCH', 'DELETE'],
        );
        expect(requests.last.path, '/v1beta1/$createdName');
      });

      test('preserves pre-existing runtime when PATCH fails under --update_if_exists', () async {
        const String existingName =
            'projects/$project/locations/$region/reasoningEngines/701';

        handler = (HttpRequest request, String body) async {
          if (request.method == 'GET' && request.uri.path == collectionPath) {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode(<String, Object?>{
                  'reasoningEngines': <Map<String, Object?>>[
                    <String, Object?>{
                      'name': existingName,
                      'displayName': 'Existing Agent',
                    },
                  ],
                }),
              );
          } else if (request.method == 'PATCH' &&
              request.uri.path == '/v1beta1/$existingName') {
            request.response
              ..statusCode = HttpStatus.internalServerError
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode(<String, Object?>{
                  'error': <String, Object?>{
                    'code': 500,
                    'message': 'Update failed',
                  },
                }),
              );
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        };

        final HttpAgentEngineRuntimesClient client = createClient();
        addTearDown(client.close);

        await expectLater(
          () => deployToAgentEngine(
            client: client,
            agentFolder: agentDir.path,
            project: project,
            region: region,
            displayName: 'Existing Agent',
            updateIfExists: true,
          ),
          throwsA(
            isA<AgentEngineDeployException>().having(
              (AgentEngineDeployException e) => e.message,
              'message',
              allOf(contains('HTTP 500'), contains('Update failed')),
            ),
          ),
        );

        expect(
          requests.map((_RecordedRequest r) => r.method),
          <String>['GET', 'PATCH'],
        );
      });
    });
  });
}
