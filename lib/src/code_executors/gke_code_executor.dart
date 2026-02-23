import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../agents/invocation_context.dart';
import 'base_code_executor.dart';
import 'code_execution_utils.dart';

class GkeCodeExecutor extends BaseCodeExecutor {
  GkeCodeExecutor({
    this.namespace = 'default',
    this.image = 'python:3.11-slim',
    this.timeoutSeconds = 300,
    this.cpuRequested = '200m',
    this.memRequested = '256Mi',
    this.cpuLimit = '500m',
    this.memLimit = '512Mi',
    this.kubeconfigPath,
    this.kubeconfigContext,
  });

  final String namespace;
  final String image;
  final int timeoutSeconds;
  final String cpuRequested;
  final String memRequested;
  final String cpuLimit;
  final String memLimit;
  final String? kubeconfigPath;
  final String? kubeconfigContext;

  Map<String, Object?> createJobManifest({
    required String jobName,
    required String configMapName,
    required InvocationContext invocationContext,
  }) {
    return <String, Object?>{
      'apiVersion': 'batch/v1',
      'kind': 'Job',
      'metadata': <String, Object?>{
        'name': jobName,
        'annotations': <String, Object?>{
          'adk.agent.google.com/invocation-id': invocationContext.invocationId,
        },
      },
      'spec': <String, Object?>{
        'backoffLimit': 0,
        'ttlSecondsAfterFinished': 600,
        'template': <String, Object?>{
          'spec': <String, Object?>{
            'restartPolicy': 'Never',
            'runtimeClassName': 'gvisor',
            'tolerations': <Map<String, Object?>>[
              <String, Object?>{
                'key': 'sandbox.gke.io/runtime',
                'operator': 'Equal',
                'value': 'gvisor',
                'effect': 'NoSchedule',
              },
            ],
            'volumes': <Map<String, Object?>>[
              <String, Object?>{
                'name': 'code-volume',
                'configMap': <String, Object?>{'name': configMapName},
              },
            ],
            'containers': <Map<String, Object?>>[
              <String, Object?>{
                'name': 'code-runner',
                'image': image,
                'command': <String>['python3', '/app/code.py'],
                'volumeMounts': <Map<String, Object?>>[
                  <String, Object?>{'name': 'code-volume', 'mountPath': '/app'},
                ],
                'securityContext': <String, Object?>{
                  'runAsNonRoot': true,
                  'runAsUser': 1001,
                  'allowPrivilegeEscalation': false,
                  'readOnlyRootFilesystem': true,
                  'capabilities': <String, Object?>{
                    'drop': <String>['ALL'],
                  },
                },
                'resources': <String, Object?>{
                  'requests': <String, String>{
                    'cpu': cpuRequested,
                    'memory': memRequested,
                  },
                  'limits': <String, String>{
                    'cpu': cpuLimit,
                    'memory': memLimit,
                  },
                },
              },
            ],
          },
        },
      },
    };
  }

  @override
  Future<CodeExecutionResult> execute(CodeExecutionRequest request) async {
    // Baseline behavior for environments without Kubernetes SDK bindings.
    final ProcessResult result = await Process.run(
      _pythonBinary(),
      <String>['-c', request.command],
      workingDirectory: request.workingDirectory,
      environment: request.environment,
    ).timeout(Duration(seconds: timeoutSeconds));

    final String note =
        '[GKE executor local fallback] Job manifest submission is not available in this runtime.\n';
    if (result.exitCode == 0) {
      return CodeExecutionResult(
        exitCode: result.exitCode,
        stdout: '$note${result.stdout}',
      );
    }
    return CodeExecutionResult(
      exitCode: result.exitCode,
      stderr: '$note${result.stderr}',
    );
  }

  @override
  Future<CodeExecutionResult> executeCode(
    InvocationContext invocationContext,
    CodeExecutionInput codeExecutionInput,
  ) async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'adk_gke_exec_',
    );
    try {
      for (final CodeExecutionFile file in codeExecutionInput.inputFiles) {
        final File out = File('${tempDir.path}/${file.name}');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(_toBytes(file.content));
      }

      return execute(
        CodeExecutionRequest(
          command: codeExecutionInput.code,
          workingDirectory: tempDir.path,
        ),
      );
    } on TimeoutException {
      return CodeExecutionResult(
        exitCode: -1,
        timedOut: true,
        stderr: 'Executor timed out after ${timeoutSeconds}s.',
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  Map<String, Object?> createCodeConfigMapBody(String name, String code) {
    return <String, Object?>{
      'metadata': <String, Object?>{'name': name},
      'data': <String, String>{'code.py': code},
    };
  }

  Map<String, Object?> addOwnerReferencePatch({
    required String ownerApiVersion,
    required String ownerKind,
    required String ownerName,
    required String ownerUid,
  }) {
    return <String, Object?>{
      'metadata': <String, Object?>{
        'ownerReferences': <Map<String, Object?>>[
          <String, Object?>{
            'apiVersion': ownerApiVersion,
            'kind': ownerKind,
            'name': ownerName,
            'uid': ownerUid,
            'controller': true,
          },
        ],
      },
    };
  }

  String _pythonBinary() {
    for (final String candidate in <String>['python3', 'python']) {
      try {
        final ProcessResult probe = Process.runSync(candidate, <String>[
          '--version',
        ]);
        if (probe.exitCode == 0) {
          return candidate;
        }
      } catch (_) {
        // Try next candidate.
      }
    }
    return 'python3';
  }
}

List<int> _toBytes(Object value) {
  if (value is List<int>) {
    return value;
  }
  if (value is String) {
    try {
      return base64Decode(value);
    } catch (_) {
      return utf8.encode(value);
    }
  }
  return utf8.encode('$value');
}
