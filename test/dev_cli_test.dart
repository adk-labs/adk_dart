import 'dart:io';

import 'package:adk_dart/src/dev/cli.dart';
import 'package:test/test.dart';

void main() {
  group('parseAdkCliArgs', () {
    test('parses create command', () {
      final ParsedAdkCommand command = parseAdkCliArgs(<String>[
        'create',
        'my_agent',
      ]);

      expect(command.type, AdkCommandType.create);
      expect(command.projectDir, 'my_agent');
    });

    test('parses run command with project dir and message', () {
      final ParsedAdkCommand command = parseAdkCliArgs(<String>[
        'run',
        'my_agent',
        '--message',
        'hello',
      ]);

      expect(command.type, AdkCommandType.run);
      expect(command.projectDir, 'my_agent');
      expect(command.message, 'hello');
    });

    test('parses web command with default options', () {
      final ParsedAdkCommand command = parseAdkCliArgs(<String>['web']);

      expect(command.type, AdkCommandType.web);
      expect(command.port, 8000);
      expect(command.host?.address, InternetAddress.loopbackIPv4.address);
    });

    test('parses api_server command as web alias', () {
      final ParsedAdkCommand command = parseAdkCliArgs(<String>[
        'api_server',
        '--port',
        '8100',
      ]);

      expect(command.type, AdkCommandType.web);
      expect(command.port, 8100);
      expect(command.enableWebUi, isFalse);
    });

    test('parses parity web options', () {
      final ParsedAdkCommand command = parseAdkCliArgs(<String>[
        'web',
        '--allow_origins',
        'https://example.com,regex:https://.*\\.example\\.org',
        '--url_prefix',
        '/adk',
        '--session_service_uri',
        'memory://',
        '--artifact_service_uri',
        'memory://',
        '--memory_service_uri',
        'memory://',
        '--no-use_local_storage',
        '--auto_create_session',
      ]);

      expect(command.allowOrigins, <String>[
        'https://example.com',
        'regex:https://.*\\.example\\.org',
      ]);
      expect(command.urlPrefix, '/adk');
      expect(command.sessionServiceUri, 'memory://');
      expect(command.artifactServiceUri, 'memory://');
      expect(command.memoryServiceUri, 'memory://');
      expect(command.useLocalStorage, isFalse);
      expect(command.autoCreateSession, isTrue);
      expect(command.enableWebUi, isTrue);
    });

    test('parses web command with explicit port', () {
      final ParsedAdkCommand command = parseAdkCliArgs(<String>[
        'web',
        '--port',
        '9000',
      ]);

      expect(command.port, 9000);
      expect(command.projectDir, '.');
    });

    test('parses web command with --port=value syntax', () {
      final ParsedAdkCommand command = parseAdkCliArgs(<String>[
        'web',
        '--port=9100',
      ]);

      expect(command.port, 9100);
    });

    test('throws usage error for invalid port', () {
      expect(
        () => parseAdkCliArgs(<String>['web', '--port', 'bad']),
        throwsA(isA<CliUsageError>()),
      );
    });

    test('throws usage error for unknown command', () {
      expect(
        () => parseAdkCliArgs(<String>['unknown']),
        throwsA(isA<CliUsageError>()),
      );
    });
  });
}
