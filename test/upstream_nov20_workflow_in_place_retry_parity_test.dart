import 'dart:async';

import 'package:adk_dart/adk_dart.dart' hide RetryConfig;
import 'package:adk_dart/src/workflow/workflow.dart' show RetryConfig;
import 'package:test/test.dart';

class _CustomError implements Exception {
  _CustomError(this.message);
  final String message;

  @override
  String toString() => '_CustomError: $message';
}

class _CustomRetryableError implements Exception {
  _CustomRetryableError(this.message);
  final String message;

  @override
  String toString() => '_CustomRetryableError: $message';
}

class _CustomNonRetryableError implements Exception {
  _CustomNonRetryableError(this.message);
  final String message;

  @override
  String toString() => '_CustomNonRetryableError: $message';
}

RetryConfig _retry(int maxAttempts, {List<Object>? exceptions}) {
  return RetryConfig(
    maxAttempts: maxAttempts,
    initialDelay: Duration.zero,
    jitter: 0.0,
    exceptions: exceptions,
  );
}

class _SimpleSubAgent extends BaseAgent {
  _SimpleSubAgent({required super.name});

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {}

  @override
  BaseAgent clone({Map<String, Object?>? update}) {
    final Map<String, Object?> normalized = normalizeCloneUpdate(update);
    final _SimpleSubAgent cloned = _SimpleSubAgent(
      name: cloneFieldValue<String>(
        update: normalized,
        fieldName: 'name',
        currentValue: name,
      ),
    );
    relinkClonedSubAgents(cloned);
    return cloned;
  }
}

class _LoopAgent extends BaseAgent {
  _LoopAgent({
    required super.name,
    required this.turnAttempts,
    required this.seenAgents,
    required this.completedTurnsRef,
  });

  final Map<int, int> turnAttempts;
  final List<BaseAgent> seenAgents;
  final List<int> completedTurnsRef;

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    seenAgents.add(this);
    final int turn = completedTurnsRef[0] + 1;
    turnAttempts[turn] = (turnAttempts[turn] ?? 0) + 1;
    if (turnAttempts[turn] == 1) {
      throw _CustomRetryableError('transient failure on turn $turn');
    }
    completedTurnsRef[0] += 1;
    yield Event(
      invocationId: context.invocationId,
      author: name,
      output: completedTurnsRef[0],
    );
  }

  @override
  BaseAgent clone({Map<String, Object?>? update}) {
    final Map<String, Object?> normalized = normalizeCloneUpdate(update);
    final _LoopAgent cloned = _LoopAgent(
      name: cloneFieldValue<String>(
        update: normalized,
        fieldName: 'name',
        currentValue: name,
      ),
      turnAttempts: turnAttempts,
      seenAgents: seenAgents,
      completedTurnsRef: completedTurnsRef,
    );
    relinkClonedSubAgents(cloned);
    return cloned;
  }
}

class _FlakyAgent extends BaseAgent {
  _FlakyAgent({
    required super.name,
    super.subAgents,
    required this.attemptsRef,
    required this.seenAgents,
    required this.seenSubParents,
    required this.seenCallbackCounts,
  }) {
    beforeAgentCallback = recordBeforeAgent;
  }

  final List<int> attemptsRef;
  final List<BaseAgent> seenAgents;
  final List<BaseAgent?> seenSubParents;
  final List<int> seenCallbackCounts;
  int callbackRuns = 0;

  Content? recordBeforeAgent(CallbackContext callbackContext) {
    callbackRuns += 1;
    return null;
  }

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    attemptsRef[0] += 1;
    seenAgents.add(this);
    seenCallbackCounts.add(callbackRuns);
    final BaseAgent? sub = findAgent('sub_agent');
    seenSubParents.add(sub?.parentAgent);
    if (attemptsRef[0] < 3) {
      throw _CustomRetryableError('transient agent failure');
    }
    yield Event(
      invocationId: context.invocationId,
      author: name,
      output: 'agent_ok',
    );
  }

  @override
  BaseAgent clone({Map<String, Object?>? update}) {
    final Map<String, Object?> normalized = normalizeCloneUpdate(update);
    final _FlakyAgent cloned = _FlakyAgent(
      name: cloneFieldValue<String>(
        update: normalized,
        fieldName: 'name',
        currentValue: name,
      ),
      subAgents: cloneSubAgentsField(normalized),
      attemptsRef: attemptsRef,
      seenAgents: seenAgents,
      seenSubParents: seenSubParents,
      seenCallbackCounts: seenCallbackCounts,
    );
    relinkClonedSubAgents(cloned);
    return cloned;
  }
}

void main() {
  group('Upstream Nov 20 workflow in-place retry parity (f04b5fe42 & c81876a49)', () {
    group('test_workflow_retry_reruns_only_failed_parallel_branch', () {
      for (final bool nested in <bool>[false, true]) {
        for (final bool siblingFinished in <bool>[false, true]) {
          final String label =
              '${nested ? 'nested' : 'flat'} / '
              '${siblingFinished ? 'sibling_finished' : 'sibling_running'}';
          test(label, () async {
            int flakyRuns = 0;
            int siblingRuns = 0;
            bool siblingCancelled = false;
            final Completer<void> siblingStarted = Completer<void>();
            final Completer<void> siblingDone = Completer<void>();
            final Completer<void> flakySucceeded = Completer<void>();
            Object? joinedOutput;

            final FunctionNode flaky = node(
              (WorkflowContext ctx, Object? input) async {
                flakyRuns += 1;
                await (siblingFinished
                    ? siblingDone.future
                    : siblingStarted.future);
                if (flakyRuns < 3) {
                  throw _CustomError('flaky failed');
                }
                if (!flakySucceeded.isCompleted) {
                  flakySucceeded.complete();
                }
                return 'flaky_ok';
              },
              name: 'flaky',
            );

            final FunctionNode sibling = node(
              (WorkflowContext ctx, Object? input) async {
                siblingRuns += 1;
                if (!siblingStarted.isCompleted) {
                  siblingStarted.complete();
                }
                if (siblingFinished) {
                  if (!siblingDone.isCompleted) {
                    siblingDone.complete();
                  }
                  return null;
                }
                await flakySucceeded.future;
                if (ctx.isCancelled) {
                  siblingCancelled = true;
                  ctx.throwIfCancelled();
                }
                return 'sibling_ok';
              },
              name: 'sibling',
            );

            final JoinNode join = JoinNode(name: 'join');
            final FunctionNode collect = node(
              (WorkflowContext ctx, Object? input) {
                joinedOutput = input;
                return input;
              },
              name: 'collect',
            );

            final RetryConfig retryConfig = _retry(3);
            final Workflow branches = Workflow(
              name: 'branches',
              nodes: <BaseNode>[flaky, sibling, join, collect],
              edges: <Edge>[
                Edge(fromNode: START, toNode: flaky),
                Edge(fromNode: START, toNode: sibling),
                Edge(fromNode: flaky, toNode: join),
                Edge(fromNode: sibling, toNode: join),
                Edge(fromNode: join, toNode: collect),
              ],
              retryConfig: nested ? null : retryConfig,
            );

            final Workflow wf = nested
                ? Workflow(
                    name: 'outer',
                    nodes: <BaseNode>[buildNode(branches)],
                    edges: <Edge>[Edge(fromNode: START, toNode: 'branches')],
                    retryConfig: retryConfig,
                  )
                : branches;

            await wf.runWorkflow(input: 'start');

            expect(siblingCancelled, isFalse);
            expect(siblingRuns, 1);
            expect(flakyRuns, 3);
            expect(joinedOutput, <String, Object?>{
              'flaky': 'flaky_ok',
              'sibling': siblingFinished ? null : 'sibling_ok',
            });
          });
        }
      }
    });

    group('test_workflow_retry_single_failing_child_attempts', () {
      test('inherited_limit', () async {
        final List<int> attempts = <int>[];
        final FunctionNode failing = node(
          (WorkflowContext ctx, Object? input) {
            attempts.add(ctx.attemptCount);
            throw _CustomRetryableError('child failure');
          },
          name: 'failing',
        );
        final Workflow wf = Workflow(
          name: 'wf',
          nodes: <BaseNode>[failing],
          edges: <Edge>[Edge(fromNode: START, toNode: failing)],
          retryConfig: _retry(3),
        );
        await expectLater(
          wf.runWorkflow(),
          throwsA(isA<_CustomRetryableError>()),
        );
        expect(attempts, <int>[1, 2, 3]);
      });

      test('outside_exceptions', () async {
        final List<int> attempts = <int>[];
        final FunctionNode failing = node(
          (WorkflowContext ctx, Object? input) {
            attempts.add(ctx.attemptCount);
            throw _CustomNonRetryableError('child failure');
          },
          name: 'failing',
        );
        final Workflow wf = Workflow(
          name: 'wf',
          nodes: <BaseNode>[failing],
          edges: <Edge>[Edge(fromNode: START, toNode: failing)],
          retryConfig: _retry(3, exceptions: <Object>[_CustomRetryableError]),
        );
        await expectLater(
          wf.runWorkflow(),
          throwsA(isA<_CustomNonRetryableError>()),
        );
        expect(attempts, <int>[1]);
      });

      test('child_own_limit', () async {
        final List<int> attempts = <int>[];
        final FunctionNode failing = node(
          (WorkflowContext ctx, Object? input) {
            attempts.add(ctx.attemptCount);
            throw _CustomRetryableError('child failure');
          },
          name: 'failing',
          retryConfig: _retry(2),
        );
        final Workflow wf = Workflow(
          name: 'wf',
          nodes: <BaseNode>[failing],
          edges: <Edge>[Edge(fromNode: START, toNode: failing)],
          retryConfig: _retry(4),
        );
        await expectLater(
          wf.runWorkflow(),
          throwsA(isA<_CustomRetryableError>()),
        );
        expect(attempts, <int>[1, 2]);
      });

      test('child_own_exceptions', () async {
        final List<int> attempts = <int>[];
        final FunctionNode failing = node(
          (WorkflowContext ctx, Object? input) {
            attempts.add(ctx.attemptCount);
            throw _CustomNonRetryableError('child failure');
          },
          name: 'failing',
          retryConfig: _retry(3, exceptions: <Object>[_CustomRetryableError]),
        );
        final Workflow wf = Workflow(
          name: 'wf',
          nodes: <BaseNode>[failing],
          edges: <Edge>[Edge(fromNode: START, toNode: failing)],
          retryConfig: _retry(3),
        );
        await expectLater(
          wf.runWorkflow(),
          throwsA(isA<_CustomNonRetryableError>()),
        );
        expect(attempts, <int>[1]);
      });

      test('nested workflow does not multiply child attempts', () async {
        final List<int> attempts = <int>[];
        final FunctionNode failing = node(
          (WorkflowContext ctx, Object? input) {
            attempts.add(ctx.attemptCount);
            throw _CustomRetryableError('nested failure');
          },
          name: 'failing',
          retryConfig: _retry(2),
        );
        final Workflow inner = Workflow(
          name: 'inner',
          nodes: <BaseNode>[failing],
          edges: <Edge>[Edge(fromNode: START, toNode: failing)],
          retryConfig: _retry(3),
        );
        final Workflow outer = Workflow(
          name: 'outer',
          nodes: <BaseNode>[buildNode(inner)],
          edges: <Edge>[Edge(fromNode: START, toNode: 'inner')],
          retryConfig: _retry(4),
        );
        await expectLater(
          outer.runWorkflow(),
          throwsA(isA<_CustomRetryableError>()),
        );
        expect(attempts, <int>[1, 2]);
      });

      test('nested workflow timeout still retries whole sub-workflow', () async {
        int innerRuns = 0;
        final FunctionNode slow = node(
          (WorkflowContext ctx, Object? input) async {
            innerRuns += 1;
            if (innerRuns == 1) {
              await Future<void>.delayed(const Duration(milliseconds: 120));
            }
            return 'recovered';
          },
          name: 'slow',
        );
        final Workflow inner = Workflow(
          name: 'inner',
          nodes: <BaseNode>[slow],
          edges: <Edge>[Edge(fromNode: START, toNode: slow)],
        );
        final Workflow outer = Workflow(
          name: 'outer',
          nodes: <BaseNode>[
            AgentNode(
              agent: inner,
              timeout: const Duration(milliseconds: 30),
              retryConfig: _retry(2),
            ),
          ],
          edges: <Edge>[Edge(fromNode: START, toNode: 'inner')],
        );
        final WorkflowResult result = await outer.runWorkflow();
        expect(innerRuns, 2);
        expect(result.outputs['inner'], 'recovered');
      });
    });

    test('test_workflow_retry_does_not_retry_detached_dynamic_child', () async {
      int runs = 0;
      final Completer<void> childStarted = Completer<void>();
      final Completer<void> spawnerDone = Completer<void>();

      final FunctionNode detachedChild = node(
        (WorkflowContext ctx, Object? input) async {
          runs += 1;
          if (!childStarted.isCompleted) {
            childStarted.complete();
          }
          await spawnerDone.future;
          throw _CustomRetryableError('detached failure');
        },
        name: 'detached_child',
      );

      final FunctionNode spawner = node(
        (WorkflowContext ctx, Object? input) async {
          final Future<Object?> task = ctx.runNode(detachedChild);
          // Prevent unhandled async error on the detached future.
          unawaited(task.then<void>((_) {}, onError: (_) {}));
          await childStarted.future;
          spawnerDone.complete();
          return 'spawned';
        },
        name: 'spawner',
        rerunOnResume: true,
      );

      final Workflow wf = Workflow(
        name: 'wf',
        nodes: <BaseNode>[spawner],
        edges: <Edge>[Edge(fromNode: START, toNode: spawner)],
        retryConfig: _retry(3),
      );

      await expectLater(
        wf.runWorkflow().timeout(const Duration(seconds: 5)),
        throwsA(isA<_CustomRetryableError>()),
      );
      expect(runs, 1);
    });

    test('test_workflow_retry_retries_each_loop_turn_on_agent_copy', () async {
      final Map<int, int> turnAttempts = <int, int>{};
      final List<BaseAgent> seenAgents = <BaseAgent>[];
      final List<int> completedTurnsRef = <int>[0];

      final _LoopAgent agent = _LoopAgent(
        name: 'loop_agent',
        turnAttempts: turnAttempts,
        seenAgents: seenAgents,
        completedTurnsRef: completedTurnsRef,
      );
      final AgentNode agentNode = AgentNode(agent: agent);

      final FunctionNode checkDone = node(
        (WorkflowContext ctx, Object? input) {
          ctx.route = (input as int) < 2 ? 'again' : 'done';
          return null;
        },
        name: 'check_done',
      );

      final FunctionNode finish = node(
        (WorkflowContext ctx, Object? input) => 'loop_complete',
        name: 'finish',
      );

      final Workflow wf = Workflow(
        name: 'wf',
        nodes: <BaseNode>[agentNode, checkDone, finish],
        edges: <Edge>[
          Edge(fromNode: START, toNode: agentNode),
          Edge(fromNode: agentNode, toNode: checkDone),
          Edge(fromNode: checkDone, toNode: agentNode, route: 'again'),
          Edge(fromNode: checkDone, toNode: finish, route: 'done'),
        ],
        retryConfig: _retry(2),
      );

      final WorkflowResult result = await wf.runWorkflow().timeout(
        const Duration(seconds: 5),
      );

      final AgentNode graphAgentNode =
          wf.nodes.firstWhere((BaseNode n) => n.name == agent.name) as AgentNode;
      expect(agentNode.retryConfig, isNull);
      expect(identical(graphAgentNode.agent, agent), isFalse);
      expect(graphAgentNode.retryConfig, wf.retryConfig);
      expect(seenAgents.length, 4);
      expect(identical(seenAgents[0], seenAgents[1]), isTrue);
      expect(identical(seenAgents[2], seenAgents[3]), isTrue);
      expect(turnAttempts, <int, int>{1: 2, 2: 2});
      expect(result.outputs['finish'], 'loop_complete');
    });

    group('test_workflow_model_copy_updates_child_retry_config', () {
      for (final String updateKind in <String>[
        'set_retry_config',
        'clear_retry_config',
        'replace_graph',
      ]) {
        test(updateKind, () async {
          final RetryConfig workflowPolicy = _retry(4);
          final RetryConfig ownPolicy = _retry(2);
          int inheritedRuns = 0;

          final FunctionNode inheritedChild = node(
            (WorkflowContext ctx, Object? input) {
              inheritedRuns += 1;
              if (inheritedRuns < 2) {
                throw _CustomRetryableError('inherited transient');
              }
              return 'ok';
            },
            name: 'inherited_child',
          );

          final FunctionNode ownPolicyChild = node(
            (WorkflowContext ctx, Object? input) => 'done',
            name: 'own_policy_child',
            retryConfig: ownPolicy,
          );

          Map<String, RetryConfig?> childPolicies(Workflow workflow) {
            return <String, RetryConfig?>{
              for (final BaseNode n in workflow.nodes)
                if (n.name != START) n.name: n.retryConfig,
            };
          }

          final List<BaseNode> nodes = <BaseNode>[
            inheritedChild,
            ownPolicyChild,
          ];
          final List<Edge> edges = <Edge>[
            Edge(fromNode: START, toNode: inheritedChild),
            Edge(fromNode: inheritedChild, toNode: ownPolicyChild),
          ];

          late final Workflow wf;
          late final Workflow copied;
          if (updateKind == 'set_retry_config') {
            wf = Workflow(name: 'wf', nodes: nodes, edges: edges);
            copied = wf.copyWith(retryConfig: workflowPolicy);
          } else if (updateKind == 'clear_retry_config') {
            wf = Workflow(
              name: 'wf',
              nodes: nodes,
              edges: edges,
              retryConfig: workflowPolicy,
            );
            copied = wf.clone(update: <String, Object?>{'retryConfig': null});
          } else {
            wf = Workflow(
              name: 'wf',
              nodes: <BaseNode>[ownPolicyChild],
              edges: <Edge>[Edge(fromNode: START, toNode: ownPolicyChild)],
              retryConfig: workflowPolicy,
            );
            final Workflow source = Workflow(
              name: 'source',
              nodes: nodes,
              edges: edges,
            );
            copied = wf.copyWith(nodes: source.nodes, edges: source.edges);
          }

          final Map<String, RetryConfig?> originalPolicies = childPolicies(wf);
          final bool inherits = updateKind != 'clear_retry_config';

          if (inherits) {
            await copied.runWorkflow().timeout(const Duration(seconds: 5));
          } else {
            await expectLater(
              copied.runWorkflow().timeout(const Duration(seconds: 5)),
              throwsA(isA<_CustomRetryableError>()),
            );
          }

          expect(childPolicies(copied), <String, RetryConfig?>{
            'inherited_child': inherits ? workflowPolicy : null,
            'own_policy_child': ownPolicy,
          });
          expect(inheritedRuns, inherits ? 2 : 1);
          expect(childPolicies(wf), originalPolicies);
        });
      }
    });

    test('test_workflow_without_retry_config_ignores_child_policies', () {
      final FunctionNode step = node(
        (WorkflowContext ctx, Object? input) => 'ok',
        name: 'step',
      );
      final Workflow wf = Workflow(
        name: 'wf',
        nodes: <BaseNode>[step],
        edges: <Edge>[Edge(fromNode: START, toNode: step)],
      );
      expect(wf.nodes.any((BaseNode n) => identical(n, step)), isTrue);
    });

    test(
      'test_in_place_retry_keeps_sibling_checkpoint_running (c81876a49)',
      () async {
        int branchARuns = 0;
        final Completer<void> branchBDone = Completer<void>();

        final FunctionNode branchA = node(
          (WorkflowContext ctx, Object? input) async {
            branchARuns += 1;
            if (branchARuns == 1) {
              throw _CustomRetryableError('transient');
            }
            await branchBDone.future;
            return 'a_ok';
          },
          name: 'branch_a',
        );

        final FunctionNode branchB = node(
          (WorkflowContext ctx, Object? input) async {
            // Let branch_a fail its first attempt before branch_b completes.
            await Future<void>.delayed(const Duration(milliseconds: 10));
            if (!branchBDone.isCompleted) {
              branchBDone.complete();
            }
            return 'b_ok';
          },
          name: 'branch_b',
        );

        final JoinNode join = JoinNode(name: 'join');
        final Workflow wf = Workflow(
          name: 'wf',
          nodes: <BaseNode>[branchA, branchB, join],
          edges: <Edge>[
            Edge(fromNode: START, toNode: branchA),
            Edge(fromNode: START, toNode: branchB),
            Edge(fromNode: branchA, toNode: join),
            Edge(fromNode: branchB, toNode: join),
          ],
          // Use maxConcurrency so a checkpoint is emitted right when branch_b
          // finishes while branch_a is still retrying / running.
          maxConcurrency: 2,
          retryConfig: _retry(2),
        );

        final InMemoryRunner runner = InMemoryRunner(
          app: App(
            name: 'checkpoint_retry_app',
            rootAgent: wf,
            resumabilityConfig: ResumabilityConfig(isResumable: true),
          ),
        );
        final Session session = await runner.sessionService.createSession(
          appName: 'checkpoint_retry_app',
          userId: 'u1',
        );
        final List<Event> events = await runner
            .runAsync(
              userId: 'u1',
              sessionId: session.id,
              newMessage: Content.userText('start'),
            )
            .toList();

        final List<Map<String, Object?>> checkpoints = <Map<String, Object?>>[
          for (final Event e in events)
            if (e.actions.agentState != null &&
                e.actions.agentState!.containsKey('nodes'))
              Map<String, Object?>.from(
                e.actions.agentState!['nodes']! as Map,
              ),
        ];

        final List<String> branchAStatusesAfterBCompleted = <String>[
          for (final Map<String, Object?> nodes in checkpoints)
            if ((nodes['branch_b'] as Map?)?['status'] ==
                NodeStatus.completed.name)
              ((nodes['branch_a'] as Map)['status'] as String),
        ];

        expect(branchAStatusesAfterBCompleted, isNotEmpty);
        expect(
          branchAStatusesAfterBCompleted.contains(NodeStatus.failed.name),
          isFalse,
        );
        expect(branchAStatusesAfterBCompleted.first, NodeStatus.running.name);
        expect(
          branchAStatusesAfterBCompleted.skip(1).toSet(),
          <String>{NodeStatus.completed.name},
        );
      },
    );

    test(
      'test_workflow_retry_skips_parallel_worker_with_own_retry_config',
      () async {
        final List<int> itemAttempts = <int>[];
        final ParallelWorker failingWorker = ParallelWorker(
          node: node(
            (WorkflowContext ctx, Object? input) {
              itemAttempts.add(ctx.attemptCount);
              throw _CustomRetryableError('worker item exhausted its own budget');
            },
            name: 'failing_worker',
          ),
          retryConfig: _retry(2),
        );
        final Workflow wf = Workflow(
          name: 'wf',
          nodes: <BaseNode>[failingWorker],
          edges: <Edge>[Edge(fromNode: START, toNode: failingWorker)],
          retryConfig: _retry(4),
        );

        await expectLater(
          wf.runWorkflow(input: <String>['only_item']),
          throwsA(isA<_CustomRetryableError>()),
        );
        expect(itemAttempts, <int>[1, 2]);
      },
    );

    test(
      'test_child_own_policy_keeps_workflow_budget_for_siblings',
      () async {
        int selfRetryingRuns = 0;
        int workflowRetriedRuns = 0;
        final List<int> workflowRetriedAttempts = <int>[];

        final FunctionNode selfRetrying = node(
          (WorkflowContext ctx, Object? input) {
            selfRetryingRuns += 1;
            if (selfRetryingRuns < 3) {
              throw _CustomRetryableError('handled by child retry_config');
            }
            return 'ok';
          },
          name: 'self_retrying',
          retryConfig: _retry(3),
        );

        final FunctionNode workflowRetried = node(
          (WorkflowContext ctx, Object? input) {
            workflowRetriedRuns += 1;
            workflowRetriedAttempts.add(ctx.attemptCount);
            if (workflowRetriedRuns == 1) {
              throw _CustomRetryableError('handled by workflow retry_config');
            }
            return 'done';
          },
          name: 'workflow_retried',
        );

        final Workflow wf = Workflow(
          name: 'wf',
          nodes: <BaseNode>[selfRetrying, workflowRetried],
          edges: <Edge>[
            Edge(fromNode: START, toNode: selfRetrying),
            Edge(fromNode: selfRetrying, toNode: workflowRetried),
          ],
          retryConfig: _retry(2),
        );

        final WorkflowResult result = await wf.runWorkflow();
        expect(selfRetryingRuns, 3);
        expect(workflowRetriedRuns, 2);
        expect(workflowRetriedAttempts, <int>[1, 2]);
        expect(result.outputs['workflow_retried'], 'done');
      },
    );

    test(
      'test_in_place_retried_node_not_rerun_on_resume_after_later_failure',
      () async {
        int firstRuns = 0;
        int secondRuns = 0;
        final List<Object?> secondInputs = <Object?>[];

        final FunctionNode firstNode = node(
          (WorkflowContext ctx, Object? input) {
            firstRuns += 1;
            if (firstRuns == 1) {
              throw _CustomRetryableError('first_node transient failure');
            }
            return 'first_ok';
          },
          name: 'first_node',
        );

        final FunctionNode secondNode = node(
          (WorkflowContext ctx, Object? input) {
            secondRuns += 1;
            secondInputs.add(input);
            if (secondRuns <= 2) {
              throw _CustomRetryableError(
                'second_node failed after budget spent',
              );
            }
            return '$input->second_ok';
          },
          name: 'second_node',
        );

        final Workflow wf = Workflow(
          name: 'wf',
          nodes: <BaseNode>[firstNode, secondNode],
          edges: <Edge>[
            Edge(fromNode: START, toNode: firstNode),
            Edge(fromNode: firstNode, toNode: secondNode),
          ],
          retryConfig: _retry(2),
        );

        final InMemoryRunner runner = InMemoryRunner(
          app: App(
            name: 'resume_after_failure_app',
            rootAgent: wf,
            resumabilityConfig: ResumabilityConfig(isResumable: true),
          ),
        );
        final Session session = await runner.sessionService.createSession(
          appName: 'resume_after_failure_app',
          userId: 'u1',
        );

        await expectLater(
          runner
              .runAsync(
                userId: 'u1',
                sessionId: session.id,
                newMessage: Content.userText('start'),
              )
              .toList(),
          throwsA(isA<_CustomRetryableError>()),
        );

        expect(firstRuns, 2);
        expect(secondRuns, 2);

        final Session? storedSession = await runner.sessionService.getSession(
          appName: 'resume_after_failure_app',
          userId: 'u1',
          sessionId: session.id,
        );
        expect(storedSession, isNotNull);
        final String invocationId = storedSession!.events.first.invocationId;

        final List<Event> resumedEvents = await runner
            .runAsync(
              userId: 'u1',
              sessionId: session.id,
              invocationId: invocationId,
            )
            .toList();

        expect(firstRuns, 2);
        expect(secondRuns, 3);
        expect(secondInputs, <String>['first_ok', 'first_ok', 'first_ok']);
        expect(
          resumedEvents.any(
            (Event e) =>
                e.nodeInfo.path == 'wf@1/second_node@1' &&
                e.content?.parts.first.text == 'first_ok->second_ok',
          ),
          isTrue,
        );
      },
    );

    test(
      'test_workflow_child_retry_runs_its_dynamic_children_again',
      () async {
        int generateRuns = 0;
        final FunctionNode generate = node(
          (WorkflowContext ctx, Object? input) {
            generateRuns += 1;
            return 'draft_$generateRuns';
          },
          name: 'generate',
        );

        final FunctionNode validate = node(
          (WorkflowContext ctx, Object? input) async {
            final Object? draft = await ctx.runNode(generate);
            if (draft == 'draft_1') {
              throw _CustomRetryableError('draft_1 rejected');
            }
            return draft;
          },
          name: 'validate',
          rerunOnResume: true,
        );

        final Workflow wf = Workflow(
          name: 'wf',
          nodes: <BaseNode>[validate],
          edges: <Edge>[Edge(fromNode: START, toNode: validate)],
          retryConfig: _retry(3),
        );

        final WorkflowResult result = await wf.runWorkflow();
        expect(generateRuns, 2);
        expect(result.outputs['validate'], 'draft_2');
      },
    );

    test('test_workflow_retry_retries_static_agent_child', () async {
      final List<int> attemptsRef = <int>[0];
      final List<BaseAgent> seenAgents = <BaseAgent>[];
      final List<BaseAgent?> seenSubParents = <BaseAgent?>[];
      final List<int> seenCallbackCounts = <int>[];

      final _FlakyAgent agent = _FlakyAgent(
        name: 'flaky_agent',
        subAgents: <BaseAgent>[_SimpleSubAgent(name: 'sub_agent')],
        attemptsRef: attemptsRef,
        seenAgents: seenAgents,
        seenSubParents: seenSubParents,
        seenCallbackCounts: seenCallbackCounts,
      );
      final AgentNode agentNode = AgentNode(agent: agent);

      final Workflow wf = Workflow(
        name: 'wf',
        nodes: <BaseNode>[agentNode],
        edges: <Edge>[Edge(fromNode: START, toNode: agentNode)],
        retryConfig: _retry(3),
      );

      final WorkflowResult result = await wf.runWorkflow().timeout(
        const Duration(seconds: 5),
      );

      expect(attemptsRef[0], 3);
      expect(agentNode.retryConfig, isNull);
      expect(agent.callbackRuns, 0);
      expect(seenCallbackCounts, <int>[1, 2, 3]);
      expect(seenAgents.length, 3);
      expect(identical(seenAgents[0], agent), isFalse);
      expect(identical(seenAgents[0], seenAgents[1]), isTrue);
      expect(identical(seenAgents[1], seenAgents[2]), isTrue);
      expect(seenSubParents, seenAgents);
      expect(result.outputs['flaky_agent'], 'agent_ok');
    });

    test(
      'test_resume_keeps_branch_retried_while_sibling_waited_for_input',
      () async {
        final Map<String, int> runs = <String, int>{
          'prep': 0,
          'flaky': 0,
          'asker': 0,
        };
        final List<int> flakyAttempts = <int>[];

        final FunctionNode prep = node(
          (WorkflowContext ctx, Object? input) {
            runs['prep'] = runs['prep']! + 1;
            return 'prepped';
          },
          name: 'prep',
        );

        final FunctionNode flaky = node(
          (WorkflowContext ctx, Object? input) {
            runs['flaky'] = runs['flaky']! + 1;
            flakyAttempts.add(ctx.attemptCount);
            if (runs['flaky'] == 1) {
              throw StateError('flaky failed');
            }
            return 'flaky_ok';
          },
          name: 'flaky',
        );

        final FunctionNode asker = node(
          (WorkflowContext ctx, Object? input) {
            runs['asker'] = runs['asker']! + 1;
            if (!ctx.resumeInputs.containsKey('proceed')) {
              return RequestInput(
                interruptId: 'proceed',
                message: 'Proceed?',
              );
            }
            final Map<String, Object?> payload = Map<String, Object?>.from(
              ctx.resumeInputs['proceed']! as Map,
            );
            return 'answered_${payload['text']}';
          },
          name: 'asker',
          rerunOnResume: true,
        );

        final JoinNode join = JoinNode(name: 'join');
        final Workflow wf = Workflow(
          name: 'retry_then_resume_wf',
          nodes: <BaseNode>[prep, flaky, asker, join],
          edges: <Edge>[
            Edge(fromNode: START, toNode: prep),
            Edge(fromNode: prep, toNode: flaky),
            Edge(fromNode: prep, toNode: asker),
            Edge(fromNode: flaky, toNode: join),
            Edge(fromNode: asker, toNode: join),
          ],
          retryConfig: _retry(2),
        );

        final WorkflowResult result1 = await wf.runWorkflow(input: 'start');
        expect(runs, <String, int>{'prep': 1, 'flaky': 2, 'asker': 1});
        expect(flakyAttempts, <int>[1, 2]);
        expect(result1.nodeStates['asker']?.status, NodeStatus.waiting);
        expect(result1.nodeStates['asker']?.interrupts, <String>['proceed']);

        final WorkflowResult result2 = await wf.runWorkflow(
          previousResult: result1,
          resumeInputs: <String, Object?>{
            'proceed': <String, Object?>{'text': 'yes'},
          },
        );
        expect(runs, <String, int>{'prep': 1, 'flaky': 2, 'asker': 2});
        expect(flakyAttempts, <int>[1, 2]);
        expect(result2.outputs['join'], <String, Object?>{
          'flaky': 'flaky_ok',
          'asker': 'answered_yes',
        });
      },
    );

    test(
      'test_workflow_retry_reruns_only_failed_worker_item (ParallelWorker)',
      () async {
        final Map<String, int> counts = <String, int>{};
        final Completer<void> item3Started = Completer<void>();
        final Completer<void> item2Succeeded = Completer<void>();
        bool item3Cancelled = false;

        final FunctionNode producer = node(
          (WorkflowContext ctx, Object? input) => <String>[
            'item1',
            'item2',
            'item3',
          ],
          name: 'Producer',
        );

        final ParallelWorker worker = ParallelWorker(
          node: node(
            (WorkflowContext ctx, Object? input) async {
              final String item = input! as String;
              counts[item] = (counts[item] ?? 0) + 1;
              if (item == 'item1') {
                return 'item1_ok';
              }
              if (item == 'item2') {
                await item3Started.future;
                if (counts['item2'] == 1) {
                  throw StateError('item2 failed once');
                }
                if (!item2Succeeded.isCompleted) {
                  item2Succeeded.complete();
                }
                return 'item2_ok';
              }
              if (item == 'item3') {
                if (!item3Started.isCompleted) {
                  item3Started.complete();
                }
                await item2Succeeded.future;
                if (ctx.isCancelled) {
                  item3Cancelled = true;
                  ctx.throwIfCancelled();
                }
                return 'item3_ok';
              }
              return '${item}_ok';
            },
            name: '_worker_fn',
          ),
        );

        final Workflow wf = Workflow(
          name: 'outer_retry_pw_wf',
          nodes: <BaseNode>[producer, worker],
          edges: <Edge>[
            Edge(fromNode: START, toNode: producer),
            Edge(fromNode: producer, toNode: worker),
          ],
          retryConfig: _retry(3),
        );

        final WorkflowResult result = await wf.runWorkflow(input: 'start');

        expect(item3Cancelled, isFalse);
        expect(counts, <String, int>{'item1': 1, 'item2': 2, 'item3': 1});
        expect(result.outputs['_worker_fn'], <String>[
          'item1_ok',
          'item2_ok',
          'item3_ok',
        ]);
      },
    );
  });
}
