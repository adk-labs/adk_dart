import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('AgentRegistry parity', () {
    test('throws when projectId or location is missing', () {
      expect(
        () => AgentRegistry(projectId: '', location: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('resolves connection URIs from top-level and nested interfaces', () {
      final AgentRegistry registry = AgentRegistry(
        projectId: 'test-project',
        location: 'global',
        httpGetProvider: _unexpectedHttpGet,
        authHeadersProvider: _staticAuthHeadersProvider,
      );

      expect(
        registry.getConnectionUri(<String, Object?>{
          'interfaces': <Map<String, Object?>>[
            <String, Object?>{
              'url': 'https://mcp-v1main.com',
              'protocolBinding': 'JSONRPC',
            },
          ],
        }, protocolBinding: 'JSONRPC'),
        'https://mcp-v1main.com',
      );
      expect(
        registry.getConnectionUri(<String, Object?>{
          'protocols': <Map<String, Object?>>[
            <String, Object?>{
              'type': 'A2A_AGENT',
              'interfaces': <Map<String, Object?>>[
                <String, Object?>{
                  'url': 'https://my-agent.com',
                  'protocolBinding': 'HTTP_JSON',
                },
              ],
            },
          ],
        }, protocolType: AgentRegistryProtocolType.a2aAgent),
        'https://my-agent.com',
      );
    });

    test('builds MCP toolset with cleaned prefix and auth headers', () async {
      final List<Uri> requestedUris = <Uri>[];
      final AgentRegistry registry = AgentRegistry(
        projectId: 'test-project',
        location: 'global',
        httpGetProvider:
            (Uri uri, {required Map<String, String> headers}) async {
              requestedUris.add(uri);
              expect(headers, containsPair('Authorization', 'Bearer token'));
              return AgentRegistryHttpResponse(
                statusCode: 200,
                body: <String, Object?>{
                  'displayName': 'Test Prefix',
                  'interfaces': <Map<String, Object?>>[
                    <String, Object?>{
                      'url': 'https://mcp.example.com',
                      'protocolBinding': 'JSONRPC',
                    },
                  ],
                },
              );
            },
        authHeadersProvider: _staticAuthHeadersProvider,
      );

      final McpToolset toolset = await registry.getMcpToolset(
        'projects/p/locations/l/mcpServers/test',
      );
      final StreamableHTTPConnectionParams params =
          toolset.connectionParams as StreamableHTTPConnectionParams;

      expect(
        requestedUris.single.toString(),
        contains('/v1alpha/projects/p/locations/l/mcpServers/test'),
      );
      expect(toolset.toolNamePrefix, 'Test_Prefix');
      expect(params.url, 'https://mcp.example.com');
      expect(params.headers, containsPair('Authorization', 'Bearer token'));
    });

    test('builds fallback RemoteA2aAgent from registry metadata', () async {
      final AgentRegistry registry = AgentRegistry(
        projectId: 'test-project',
        location: 'global',
        httpGetProvider:
            (Uri uri, {required Map<String, String> headers}) async {
              return AgentRegistryHttpResponse(
                statusCode: 200,
                body: <String, Object?>{
                  'displayName': 'Test Agent',
                  'description': 'Test Desc',
                  'version': '1.0',
                  'protocols': <Map<String, Object?>>[
                    <String, Object?>{
                      'type': 'A2A_AGENT',
                      'interfaces': <Map<String, Object?>>[
                        <String, Object?>{
                          'url': 'https://my-agent.com',
                          'protocolBinding': 'JSONRPC',
                        },
                      ],
                    },
                  ],
                  'skills': <Map<String, Object?>>[
                    <String, Object?>{
                      'id': 's1',
                      'name': 'Skill 1',
                      'description': 'Desc 1',
                    },
                  ],
                },
              );
            },
        authHeadersProvider: _staticAuthHeadersProvider,
      );

      final RemoteA2aAgent agent = await registry.getRemoteA2aAgent(
        'projects/p/locations/l/agents/test',
      );

      expect(agent.name, 'Test_Agent');
      expect(agent.description, 'Test Desc');
      expect(agent.resolvedAgentCard, isNotNull);
      expect(agent.resolvedAgentCard?.url, 'https://my-agent.com');
      expect(agent.resolvedAgentCard?.version, '1.0');
      expect(agent.resolvedAgentCard?.skills.single.name, 'Skill 1');
      expect(
        agent.resolvedAgentCard?.capabilities.values['streaming'],
        isFalse,
      );
    });

    test('prefers full stored agent card when present', () async {
      final AgentRegistry registry = AgentRegistry(
        projectId: 'test-project',
        location: 'global',
        httpGetProvider:
            (Uri uri, {required Map<String, String> headers}) async {
              return AgentRegistryHttpResponse(
                statusCode: 200,
                body: <String, Object?>{
                  'name': 'projects/p/locations/l/agents/a',
                  'card': <String, Object?>{
                    'type': 'A2A_AGENT_CARD',
                    'content': <String, Object?>{
                      'name': 'CardName',
                      'description': 'CardDesc',
                      'version': '2.0',
                      'url': 'https://card-url.com',
                      'skills': <Map<String, Object?>>[
                        <String, Object?>{
                          'id': 's1',
                          'name': 'S1',
                          'description': 'D1',
                          'tags': <String>['t1'],
                        },
                      ],
                      'capabilities': <String, Object?>{
                        'streaming': true,
                        'polling': false,
                      },
                      'defaultInputModes': <String>['text'],
                      'defaultOutputModes': <String>['text'],
                    },
                  },
                },
              );
            },
        authHeadersProvider: _staticAuthHeadersProvider,
      );

      final RemoteA2aAgent agent = await registry.getRemoteA2aAgent(
        'projects/p/locations/l/agents/a',
      );

      expect(agent.name, 'CardName');
      expect(agent.description, 'CardDesc');
      expect(agent.resolvedAgentCard?.version, '2.0');
      expect(agent.resolvedAgentCard?.url, 'https://card-url.com');
      expect(agent.resolvedAgentCard?.defaultInputModes, <String>['text']);
      expect(agent.resolvedAgentCard?.defaultOutputModes, <String>['text']);
      expect(agent.resolvedAgentCard?.capabilities.values['streaming'], isTrue);
      expect(agent.resolvedAgentCard?.skills.single.name, 'S1');
    });
  });
}

Future<AgentRegistryHttpResponse> _unexpectedHttpGet(
  Uri uri, {
  required Map<String, String> headers,
}) async {
  fail('Unexpected HTTP GET: $uri');
}

Future<Map<String, String>> _staticAuthHeadersProvider() async {
  return <String, String>{'Authorization': 'Bearer token'};
}
