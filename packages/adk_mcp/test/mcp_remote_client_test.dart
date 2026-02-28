import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk_mcp/adk_mcp.dart';
import 'package:test/test.dart';

Future<void> _respondJsonRpc(
  HttpRequest request, {
  required Object? id,
  Object? result,
  Map<String, Object?>? error,
  Map<String, String>? headers,
  String contentType = 'application/json',
}) async {
  request.response.statusCode = HttpStatus.ok;
  request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
  if (headers != null) {
    headers.forEach(request.response.headers.set);
  }
  request.response.write(
    jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      if (id case final Object responseId) 'id': responseId,
      if (error != null) 'error': error else 'result': result,
    }),
  );
  await request.response.close();
}

void main() {
  test('does not send protocol header on initialize', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() async => server.close(force: true));

    final Map<String, String> seenHeaders = <String, String>{};
    server.listen((HttpRequest request) async {
      final String body = await utf8.decoder.bind(request).join();
      final Map<String, Object?> rpc = (jsonDecode(body) as Map).map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      final String method = '${rpc['method'] ?? ''}';
      if (method == 'initialize') {
        request.headers.forEach((String name, List<String> values) {
          seenHeaders[name.toLowerCase()] = values.join(', ');
        });
        await _respondJsonRpc(
          request,
          id: rpc['id'],
          result: <String, Object?>{
            'protocolVersion': '2025-11-25',
            'capabilities': <String, Object?>{'tools': <String, Object?>{}},
          },
          headers: <String, String>{'MCP-Session-Id': 'session-main'},
        );
        return;
      }
      if (method == 'notifications/initialized') {
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
        return;
      }
      await _respondJsonRpc(
        request,
        id: rpc['id'],
        result: <String, Object?>{'tools': <Object?>[]},
      );
    });

    final McpRemoteClient client = McpRemoteClient(
      clientInfoName: 'test_client',
      clientInfoVersion: '0.0.0',
    );
    final StreamableHTTPConnectionParams connectionParams =
        StreamableHTTPConnectionParams(
          url: 'http://${server.address.address}:${server.port}/mcp',
        );

    await client.ensureInitialized(connectionParams);

    expect(seenHeaders.containsKey('mcp-protocol-version'), isFalse);
  });

  test(
    'matches SSE responses by id and ignores prior server notifications',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async => server.close(force: true));

      server.listen((HttpRequest request) async {
        final String body = await utf8.decoder.bind(request).join();
        final Map<String, Object?> rpc = (jsonDecode(body) as Map).map(
          (Object? key, Object? value) => MapEntry('$key', value),
        );
        final String method = '${rpc['method'] ?? ''}';
        final Object? id = rpc['id'];

        switch (method) {
          case 'initialize':
            await _respondJsonRpc(
              request,
              id: id,
              result: <String, Object?>{
                'protocolVersion': '2025-11-25',
                'capabilities': <String, Object?>{'tools': <String, Object?>{}},
              },
              headers: <String, String>{'MCP-Session-Id': 'session-main'},
            );
            return;
          case 'notifications/initialized':
            request.response.statusCode = HttpStatus.accepted;
            await request.response.close();
            return;
          case 'tools/list':
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.set(
              HttpHeaders.contentTypeHeader,
              'text/event-stream',
            );
            request.response.write(
              'data: ${jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'method': 'notifications/tools/list_changed', 'params': <String, Object?>{}})}\n\n',
            );
            request.response.write(
              'data: ${jsonEncode(<String, Object?>{
                'jsonrpc': '2.0',
                'id': 9999,
                'result': <String, Object?>{'tools': <Object?>[]},
              })}\n\n',
            );
            request.response.write(
              'data: ${jsonEncode(<String, Object?>{
                'jsonrpc': '2.0',
                'id': id,
                'result': <String, Object?>{
                  'tools': <Map<String, Object?>>[
                    <String, Object?>{'name': 'remote_echo'},
                  ],
                },
              })}\n\n',
            );
            await request.response.close();
            return;
          default:
            await _respondJsonRpc(
              request,
              id: id,
              error: <String, Object?>{
                'code': -32601,
                'message': 'Method not found: $method',
              },
            );
        }
      });

      final StreamableHTTPConnectionParams connectionParams =
          StreamableHTTPConnectionParams(
            url: 'http://${server.address.address}:${server.port}/mcp',
          );
      final McpRemoteClient client = McpRemoteClient(
        clientInfoName: 'test_client',
        clientInfoVersion: '0.0.0',
      );

      final List<Map<String, Object?>> tools = await client
          .collectPaginatedMaps(
            connectionParams: connectionParams,
            method: 'tools/list',
            resultArrayField: 'tools',
          );

      expect(tools, hasLength(1));
      expect(tools.single['name'], 'remote_echo');
    },
  );

  test('sends notifications/cancelled when request times out', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() async => server.close(force: true));

    final List<String> seenMethods = <String>[];
    server.listen((HttpRequest request) async {
      final String body = await utf8.decoder.bind(request).join();
      final Map<String, Object?> rpc = (jsonDecode(body) as Map).map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      final String method = '${rpc['method'] ?? ''}';
      seenMethods.add(method);
      final Object? id = rpc['id'];

      switch (method) {
        case 'initialize':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'protocolVersion': '2025-11-25',
              'capabilities': <String, Object?>{'tools': <String, Object?>{}},
            },
            headers: <String, String>{'MCP-Session-Id': 'session-main'},
          );
          return;
        case 'notifications/initialized':
          request.response.statusCode = HttpStatus.accepted;
          await request.response.close();
          return;
        case 'tools/list':
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{'tools': <Object?>[]},
          );
          return;
        case 'notifications/cancelled':
          request.response.statusCode = HttpStatus.accepted;
          await request.response.close();
          return;
        default:
          await _respondJsonRpc(
            request,
            id: id,
            error: <String, Object?>{
              'code': -32601,
              'message': 'Method not found: $method',
            },
          );
      }
    });

    final McpRemoteClient client = McpRemoteClient(
      clientInfoName: 'test_client',
      clientInfoVersion: '0.0.0',
      requestTimeout: const Duration(milliseconds: 80),
    );
    final StreamableHTTPConnectionParams connectionParams =
        StreamableHTTPConnectionParams(
          url: 'http://${server.address.address}:${server.port}/mcp',
        );

    await expectLater(
      client.collectPaginatedMaps(
        connectionParams: connectionParams,
        method: 'tools/list',
        resultArrayField: 'tools',
      ),
      throwsA(isA<TimeoutException>()),
    );

    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(seenMethods, contains('notifications/cancelled'));
  });
}
