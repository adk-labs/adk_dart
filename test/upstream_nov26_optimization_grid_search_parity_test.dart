import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _StubBaseLlm extends BaseLlm {
  _StubBaseLlm({
    super.model = 'openai/gpt-4o',
    Map<String, Object?>? additionalArgs,
  }) : additionalArgs = Map<String, Object?>.from(
         additionalArgs ?? const <String, Object?>{},
       );

  final Map<String, Object?> additionalArgs;

  _StubBaseLlm clone() =>
      _StubBaseLlm(model: model, additionalArgs: additionalArgs);

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

String _noopTool(String query) => query;

class _FakeEvalSampler extends Sampler<UnstructuredSamplingResult> {
  _FakeEvalSampler({
    List<String>? exampleIds,
    Set<String> modelsWithoutTokens = const <String>{},
  }) : _exampleIds = List<String>.from(
         exampleIds ?? const <String>['case_1', 'case_2', 'case_3', 'case_4'],
       ),
       _modelsWithoutTokens = Set<String>.from(modelsWithoutTokens);

  final List<String> _exampleIds;
  final Set<String> _modelsWithoutTokens;
  final List<(String, List<String>)> recordedBatches =
      <(String, List<String>)>[];

  @override
  List<String> getTrainExampleIds() => List<String>.from(_exampleIds);

  @override
  List<String> getValidationExampleIds() => List<String>.from(_exampleIds);

  @override
  Future<UnstructuredSamplingResult> sampleAndScore(
    BaseAgent candidate, {
    ExampleSet exampleSet = ExampleSet.validation,
    List<String>? batch,
    bool captureFullEvalData = false,
  }) async {
    final List<String> evalIds = batch ?? _exampleIds;
    final String modelStr = candidate is LlmAgent && '${candidate.model}'.isNotEmpty
        ? '${candidate.model}'
        : 'gemini-2.5-flash';
    recordedBatches.add((modelStr, List<String>.from(evalIds)));
    final double temperature = candidate is LlmAgent
        ? (candidate.generateContentConfig?.temperature ?? 0.0)
        : 0.0;

    final double baseScore;
    final double latencyS;
    final double tokens;
    if (modelStr.contains('pro')) {
      baseScore = 0.95;
      latencyS = 2.0;
      tokens = 500.0;
    } else if (modelStr.contains('flash-lite')) {
      baseScore = 0.75;
      latencyS = 0.5;
      tokens = 80.0;
    } else {
      baseScore = 0.85;
      latencyS = 1.0;
      tokens = 200.0;
    }

    final double quality = baseScore - temperature * 0.05;
    final double f1Score = quality * 0.9;
    if (!captureFullEvalData) {
      return UnstructuredSamplingResult(
        scores: <String, double>{for (final String uid in evalIds) uid: quality},
      );
    }

    final List<Map<String, Object?>> metricResults = <Map<String, Object?>>[
      <String, Object?>{
        'metric_name': 'quality',
        'score': quality,
        'eval_status': 'PASSED',
      },
      <String, Object?>{
        'metric_name': 'f1',
        'score': f1Score,
        'eval_status': 'PASSED',
      },
      <String, Object?>{
        'metric_name': 'invocation_duration_v1',
        'score': latencyS,
        'eval_status': 'NOT_EVALUATED',
      },
      if (!_modelsWithoutTokens.contains(modelStr))
        <String, Object?>{
          'metric_name': 'token_usage_v1',
          'score': tokens * 2,
          'eval_status': 'NOT_EVALUATED',
          'details': <String, Object?>{
            'token_usage_details': <String, Object?>{
              'input_tokens': tokens,
              'output_tokens': tokens,
              'cached_tokens': 0,
              'reasoning_tokens': 0,
            },
          },
        },
    ];

    return UnstructuredSamplingResult(
      scores: <String, double>{for (final String uid in evalIds) uid: 1.0},
      data: <String, Map<String, Object?>>{
        for (final String uid in evalIds)
          uid: <String, Object?>{
            'invocations': <Map<String, Object?>>[
              <String, Object?>{'eval_metric_results': metricResults},
            ],
          },
      },
    );
  }
}

class _TokenResultSampler extends Sampler<UnstructuredSamplingResult> {
  _TokenResultSampler(this._tokenResult);

  final Map<String, Object?> _tokenResult;

  @override
  List<String> getTrainExampleIds() => <String>['c1', 'c2'];

  @override
  List<String> getValidationExampleIds() => <String>['c1', 'c2'];

  @override
  Future<UnstructuredSamplingResult> sampleAndScore(
    BaseAgent candidate, {
    ExampleSet exampleSet = ExampleSet.validation,
    List<String>? batch,
    bool captureFullEvalData = false,
  }) async {
    final List<String> evalIds = batch ?? const <String>['c1', 'c2'];
    final List<Map<String, Object?>> metricResults = <Map<String, Object?>>[
      <String, Object?>{
        'metric_name': 'token_usage_v1',
        'eval_status': 'NOT_EVALUATED',
        ..._tokenResult,
      },
    ];
    return UnstructuredSamplingResult(
      scores: <String, double>{for (final String uid in evalIds) uid: 1.0},
      data: <String, Map<String, Object?>>{
        for (final String uid in evalIds)
          uid: <String, Object?>{
            'invocations': <Map<String, Object?>>[
              <String, Object?>{'eval_metric_results': metricResults},
            ],
          },
      },
    );
  }
}

class _ScriptedSampler extends Sampler<UnstructuredSamplingResult> {
  _ScriptedSampler(
    this._script, {
    List<String> trainIds = const <String>['c1', 'c2'],
    List<String> validationIds = const <String>['v1', 'v2'],
    this.delay = Duration.zero,
  }) : _trainIds = List<String>.from(trainIds),
       _validationIds = List<String>.from(validationIds);

  final List<Map<String, Object?>?>? Function(String model, String uid) _script;
  final List<String> _trainIds;
  final List<String> _validationIds;
  final Duration delay;
  final List<(String, ExampleSet, List<String>)> calls =
      <(String, ExampleSet, List<String>)>[];
  final List<BaseAgent> candidates = <BaseAgent>[];
  int inFlight = 0;
  int peakInFlight = 0;

  @override
  List<String> getTrainExampleIds() => List<String>.from(_trainIds);

  @override
  List<String> getValidationExampleIds() => List<String>.from(_validationIds);

  @override
  Future<UnstructuredSamplingResult> sampleAndScore(
    BaseAgent candidate, {
    ExampleSet exampleSet = ExampleSet.train,
    List<String>? batch,
    bool captureFullEvalData = false,
  }) async {
    final String model = candidate is LlmAgent ? '${candidate.model}' : '';
    final List<String> defaultIds =
        exampleSet == ExampleSet.train ? _trainIds : _validationIds;
    final List<String> evalIds = List<String>.from(batch ?? defaultIds);
    calls.add((model, exampleSet, evalIds));
    candidates.add(candidate);
    inFlight += 1;
    if (inFlight > peakInFlight) {
      peakInFlight = inFlight;
    }
    try {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      } else {
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      inFlight -= 1;
    }
    final Map<String, double> scores = <String, double>{};
    final Map<String, Map<String, Object?>> data =
        <String, Map<String, Object?>>{};
    for (final String uid in evalIds) {
      final List<Map<String, Object?>?>? results = _script(model, uid);
      scores[uid] = results == null ? 0.0 : 1.0;
      data[uid] = <String, Object?>{
        'invocations': results == null
            ? <Object?>[]
            : <Map<String, Object?>>[
                <String, Object?>{'eval_metric_results': results},
              ],
      };
    }
    return UnstructuredSamplingResult(scores: scores, data: data);
  }
}

class _FailingScriptedSampler extends _ScriptedSampler {
  _FailingScriptedSampler(super.script)
    : super(delay: const Duration(milliseconds: 10));

  @override
  Future<UnstructuredSamplingResult> sampleAndScore(
    BaseAgent candidate, {
    ExampleSet exampleSet = ExampleSet.train,
    List<String>? batch,
    bool captureFullEvalData = false,
  }) async {
    if (candidate is LlmAgent && candidate.model == 'gemini-2.5-pro') {
      throw StateError('429 RESOURCE_EXHAUSTED');
    }
    return super.sampleAndScore(
      candidate,
      exampleSet: exampleSet,
      batch: batch,
      captureFullEvalData: captureFullEvalData,
    );
  }
}

class _MultiTurnSampler extends Sampler<UnstructuredSamplingResult> {
  _MultiTurnSampler(this._cases);

  final Map<String, List<Map<String, Object?>>> _cases;

  @override
  List<String> getTrainExampleIds() => _cases.keys.toList();

  @override
  List<String> getValidationExampleIds() => <String>[];

  @override
  Future<UnstructuredSamplingResult> sampleAndScore(
    BaseAgent candidate, {
    ExampleSet exampleSet = ExampleSet.train,
    List<String>? batch,
    bool captureFullEvalData = false,
  }) async {
    final List<String> ids = List<String>.from(batch ?? _cases.keys);
    return UnstructuredSamplingResult(
      scores: <String, double>{for (final String uid in ids) uid: 1.0},
      data: <String, Map<String, Object?>>{
        for (final String uid in ids)
          uid: <String, Object?>{'invocations': _cases[uid]!},
      },
    );
  }
}

class _EchoModel extends BaseLlm {
  _EchoModel(String model) : super(model: model);

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    if (model == 'broken-model') {
      throw StateError('Model crashed');
    }
    yield LlmResponse(content: Content.modelText('ok from $model'));
  }
}

Map<String, Object?> _metric(String name, double? score) {
  return <String, Object?>{
    'metric_name': name,
    'score': score,
    'eval_status': 'PASSED',
  };
}

Map<String, Object?> _detailedTokenMetric(
  double inputTokens,
  double outputTokens, {
  double? cachedTokens,
  double? reasoningTokens,
}) {
  final double total = inputTokens + outputTokens;
  return <String, Object?>{
    'metric_name': 'token_usage_v1',
    'score': total,
    'eval_status': 'NOT_EVALUATED',
    'details': <String, Object?>{
      'token_usage_details': <String, Object?>{
        'total_tokens': total,
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
        'cached_tokens': cachedTokens,
        'reasoning_tokens': reasoningTokens,
      },
    },
  };
}

List<String> _modelsOnFront(OptimizerResult<GridSearchAgentWithScores> result) {
  return <String>[
    for (final GridSearchAgentWithScores item in result.optimizedAgents)
      item.optimizedAgent is LlmAgent
          ? '${(item.optimizedAgent as LlmAgent).model}'
          : '',
  ];
}

void main() {
  setUp(() {
    resetFeatureRegistryForTest();
    setFeatureWarningEmitter((String _) {});
  });

  group('agent_tree_cloner parity', () {
    test('empty params clones tree and isolates mutable state', () {
      final LlmAgent sub = LlmAgent(
        name: 'Sub',
        model: 'gemini-2.5-flash',
        generateContentConfig: GenerateContentConfig(temperature: 0.2),
      );
      final LlmAgent helper = LlmAgent(
        name: 'Helper',
        model: 'gemini-2.5-flash-lite',
      );
      final LlmAgent root = LlmAgent(
        name: 'Root',
        model: 'gemini-2.5-pro',
        instruction: 'Original instruction',
        generateContentConfig: GenerateContentConfig(temperature: 0.5),
        subAgents: <BaseAgent>[sub],
        tools: <Object>[_noopTool, AgentTool(agent: helper)],
      );

      final BaseAgent cloned = cloneAgentWithParams(root, <String, Object?>{});

      expect(cloned, isA<LlmAgent>());
      expect(cloned, isNot(same(root)));
      final LlmAgent clonedLlm = cloned as LlmAgent;
      expect(clonedLlm.name, 'Root');
      expect(clonedLlm.model, 'gemini-2.5-pro');
      expect(clonedLlm.instruction, 'Original instruction');
      expect(clonedLlm.parentAgent, isNull);
      expect(
        clonedLlm.generateContentConfig,
        isNot(same(root.generateContentConfig)),
      );
      expect(clonedLlm.generateContentConfig?.temperature, closeTo(0.5, 1e-9));

      // Mutating the cloned config must not affect the original agent.
      clonedLlm.generateContentConfig!.temperature = 0.9;
      expect(root.generateContentConfig?.temperature, closeTo(0.5, 1e-9));

      // Sub-agent is cloned and re-parented to cloned, leaving original intact.
      expect(clonedLlm.subAgents, hasLength(1));
      final BaseAgent clonedSub = clonedLlm.subAgents.single;
      expect(clonedSub, isA<LlmAgent>());
      expect(clonedSub, isNot(same(sub)));
      expect(clonedSub.parentAgent, same(clonedLlm));
      expect(sub.parentAgent, same(root));
      expect(
        (clonedSub as LlmAgent).generateContentConfig,
        isNot(same(sub.generateContentConfig)),
      );

      // Plain function tool is preserved; AgentTool and its child are cloned.
      expect(clonedLlm.tools[0], same(_noopTool));
      final Object clonedToolObj = clonedLlm.tools[1];
      expect(clonedToolObj, isA<AgentTool>());
      final AgentTool clonedTool = clonedToolObj as AgentTool;
      expect(clonedTool, isNot(same(root.tools[1])));
      expect(clonedTool.agent, isNot(same(helper)));
      expect(clonedTool.agent.parentAgent, isNull);
    });

    test('updates direct LlmAgent fields without mutating original', () {
      final LlmAgent root = LlmAgent(
        name: 'Root',
        model: 'gemini-2.5-flash',
        instruction: 'Initial',
        description: 'Initial description',
        outputKey: 'initial_out',
      );

      final LlmAgent cloned =
          cloneAgentWithParams(root, <String, Object?>{
                'model': 'gemini-2.5-pro',
                'instruction': 'Updated',
                'description': 'Updated description',
                'output_key': 'updated_out',
                'disallow_transfer_to_parent': true,
                'disallow_transfer_to_peers': true,
              })
              as LlmAgent;

      expect(cloned.model, 'gemini-2.5-pro');
      expect(cloned.instruction, 'Updated');
      expect(cloned.description, 'Updated description');
      expect(cloned.outputKey, 'updated_out');
      expect(cloned.disallowTransferToParent, isTrue);
      expect(cloned.disallowTransferToPeers, isTrue);

      expect(root.model, 'gemini-2.5-flash');
      expect(root.instruction, 'Initial');
      expect(root.description, 'Initial description');
      expect(root.outputKey, 'initial_out');
      expect(root.disallowTransferToParent, isFalse);
      expect(root.disallowTransferToPeers, isFalse);
    });

    test('clones BaseLlm model when swept or inherited', () {
      final _StubBaseLlm baselineLlm = _StubBaseLlm(
        model: 'openai/gpt-4o-mini',
        additionalArgs: <String, Object?>{'api_base': 'https://a.test'},
      );
      final _StubBaseLlm sweptLlm = _StubBaseLlm(
        model: 'openai/gpt-4o',
        additionalArgs: <String, Object?>{'api_base': 'https://b.test'},
      );
      final LlmAgent root = LlmAgent(name: 'Root', model: baselineLlm);

      final LlmAgent cloneInherited =
          cloneAgentWithParams(root, <String, Object?>{
                'instruction': 'Changed',
              })
              as LlmAgent;
      expect(cloneInherited.model, isA<_StubBaseLlm>());
      final _StubBaseLlm inheritedModel = cloneInherited.model as _StubBaseLlm;
      expect(inheritedModel, isNot(same(baselineLlm)));
      expect(inheritedModel.additionalArgs, isNot(same(baselineLlm.additionalArgs)));
      inheritedModel.additionalArgs['api_base'] = 'https://mutated.test';
      expect(baselineLlm.additionalArgs['api_base'], 'https://a.test');

      final LlmAgent cloneA =
          cloneAgentWithParams(root, <String, Object?>{'model': sweptLlm})
              as LlmAgent;
      final LlmAgent cloneB =
          cloneAgentWithParams(root, <String, Object?>{'model': sweptLlm})
              as LlmAgent;
      final _StubBaseLlm modelA = cloneA.model as _StubBaseLlm;
      final _StubBaseLlm modelB = cloneB.model as _StubBaseLlm;
      expect(modelA, isNot(same(sweptLlm)));
      expect(modelA, isNot(same(modelB)));
      modelA.additionalArgs['timeout'] = 30;
      expect(sweptLlm.additionalArgs.containsKey('timeout'), isFalse);
      expect(modelB.additionalArgs.containsKey('timeout'), isFalse);
    });

    test('dotted generate_content_config scalars and nested thinking', () {
      final LlmAgent root = LlmAgent(
        name: 'Root',
        model: 'gemini-2.5-flash',
        generateContentConfig: GenerateContentConfig(
          temperature: 0.1,
          topP: 0.95,
          thinkingConfig: <String, Object?>{
            'include_thoughts': true,
            'thinking_budget': 128,
          },
        ),
      );

      final LlmAgent cloned =
          cloneAgentWithParams(root, <String, Object?>{
                'generate_content_config.temperature': 0.7,
                'generate_content_config.top_k': 40,
                'generate_content_config.max_output_tokens': 1024,
                'generate_content_config.seed': 42,
                'generate_content_config.thinking_config.thinking_budget': 2048,
              })
              as LlmAgent;

      final GenerateContentConfig cfg = cloned.generateContentConfig!;
      expect(cfg.temperature, closeTo(0.7, 1e-9));
      expect(cfg.topP, closeTo(0.95, 1e-9));
      expect(cfg.topK, 40);
      expect(cfg.maxOutputTokens, 1024);
      expect(cfg.seed, 42);
      final Map<String, Object?> tc =
          cfg.thinkingConfig! as Map<String, Object?>;
      expect(tc['include_thoughts'], isTrue);
      expect(tc['thinking_budget'], 2048);

      // Baseline remains untouched.
      expect(root.generateContentConfig!.temperature, closeTo(0.1, 1e-9));
      expect(root.generateContentConfig!.topK, isNull);
      expect(
        (root.generateContentConfig!.thinkingConfig!
            as Map<String, Object?>)['thinking_budget'],
        128,
      );
    });

    test('dotted generate_content_config when baseline config is null', () {
      final LlmAgent root = LlmAgent(name: 'Root', model: 'gemini-2.5-flash');
      root.generateContentConfig = null;

      final LlmAgent cloned =
          cloneAgentWithParams(root, <String, Object?>{
                'generate_content_config.temperature': 0.3,
                'generate_content_config.thinking_config.thinking_budget': 512,
              })
              as LlmAgent;

      expect(root.generateContentConfig, isNull);
      expect(cloned.generateContentConfig, isNotNull);
      expect(cloned.generateContentConfig!.temperature, closeTo(0.3, 1e-9));
      expect(
        (cloned.generateContentConfig!.thinkingConfig!
            as Map<String, Object?>)['thinking_budget'],
        512,
      );
    });

    test('whole generate_content_config object, map, and null', () {
      final LlmAgent root = LlmAgent(
        name: 'Root',
        model: 'gemini-2.5-flash',
        generateContentConfig: GenerateContentConfig(temperature: 0.2),
      );

      final GenerateContentConfig providedCfg = GenerateContentConfig(
        temperature: 0.8,
        topP: 0.9,
      );
      final LlmAgent cloneObj =
          cloneAgentWithParams(root, <String, Object?>{
                'generate_content_config': providedCfg,
              })
              as LlmAgent;
      expect(cloneObj.generateContentConfig, isNotNull);
      expect(cloneObj.generateContentConfig, isNot(same(providedCfg)));
      expect(cloneObj.generateContentConfig!.temperature, closeTo(0.8, 1e-9));
      providedCfg.temperature = 0.0;
      expect(cloneObj.generateContentConfig!.temperature, closeTo(0.8, 1e-9));

      final LlmAgent cloneDict =
          cloneAgentWithParams(root, <String, Object?>{
                'generate_content_config': <String, Object?>{
                  'temperature': 0.4,
                  'thinking_config': <String, Object?>{'thinking_budget': 256},
                },
              })
              as LlmAgent;
      expect(cloneDict.generateContentConfig!.temperature, closeTo(0.4, 1e-9));
      expect(
        (cloneDict.generateContentConfig!.thinkingConfig!
            as Map<String, Object?>)['thinking_budget'],
        256,
      );

      final LlmAgent cloneNone =
          cloneAgentWithParams(root, <String, Object?>{
                'generate_content_config': null,
              })
              as LlmAgent;
      expect(cloneNone.generateContentConfig, isNull);
      expect(root.generateContentConfig!.temperature, closeTo(0.2, 1e-9));
    });

    test('BuiltInPlanner stays synced with thinking_config', () {
      final LlmAgent root = LlmAgent(
        name: 'Root',
        model: 'gemini-2.5-flash',
        planner: BuiltInPlanner(
          thinkingConfig: <String, Object?>{
            'include_thoughts': true,
            'thinking_budget': 128,
          },
        ),
      );

      final LlmAgent untouched =
          cloneAgentWithParams(root, <String, Object?>{
                'generate_content_config.temperature': 0.6,
              })
              as LlmAgent;
      expect(untouched.planner, isA<BuiltInPlanner>());
      expect(untouched.planner, isNot(same(root.planner)));
      final BuiltInPlanner untouchedPlanner =
          untouched.planner! as BuiltInPlanner;
      final BuiltInPlanner rootPlanner = root.planner! as BuiltInPlanner;
      expect(
        untouchedPlanner.thinkingConfig,
        isNot(same(rootPlanner.thinkingConfig)),
      );
      expect(
        (untouchedPlanner.thinkingConfig
            as Map<String, Object?>)['thinking_budget'],
        128,
      );

      final LlmAgent cloned =
          cloneAgentWithParams(root, <String, Object?>{
                'generate_content_config.thinking_config.thinking_budget': 1024,
              })
              as LlmAgent;
      expect(cloned.planner, isA<BuiltInPlanner>());
      final BuiltInPlanner clonedPlanner = cloned.planner! as BuiltInPlanner;
      expect(
        (clonedPlanner.thinkingConfig
            as Map<String, Object?>)['thinking_budget'],
        1024,
      );
      expect(
        (clonedPlanner.thinkingConfig
            as Map<String, Object?>)['include_thoughts'],
        isTrue,
      );
      final Map<String, Object?> clonedTc =
          cloned.generateContentConfig!.thinkingConfig! as Map<String, Object?>;
      expect(clonedTc['thinking_budget'], 1024);
      expect(clonedTc['include_thoughts'], isTrue);
      expect(
        (rootPlanner.thinkingConfig as Map<String, Object?>)['thinking_budget'],
        128,
      );

      final LlmAgent cleared =
          cloneAgentWithParams(root, <String, Object?>{
                'generate_content_config': null,
              })
              as LlmAgent;
      expect(cleared.planner, isNull);

      final LlmAgent noThinking =
          cloneAgentWithParams(root, <String, Object?>{
                'generate_content_config': GenerateContentConfig(
                  temperature: 0.5,
                  thinkingConfig: null,
                ),
              })
              as LlmAgent;
      expect(noThinking.planner, isNull);

      final BuiltInPlanner explicitPlanner = BuiltInPlanner(
        thinkingConfig: <String, Object?>{'thinking_budget': 4096},
      );
      final LlmAgent withExplicit =
          cloneAgentWithParams(root, <String, Object?>{
                'planner': explicitPlanner,
                'generate_content_config.thinking_config.thinking_budget': 512,
              })
              as LlmAgent;
      expect(
        ((withExplicit.planner! as BuiltInPlanner).thinkingConfig
            as Map<String, Object?>)['thinking_budget'],
        4096,
      );
    });

    test('http_options isolates headers and merges nested retry_options', () {
      final HttpOptions httpOptions = HttpOptions(
        apiVersion: 'v1beta',
        headers: <String, String>{'x-env': 'prod'},
        retryOptions: HttpRetryOptions(attempts: 3, initialDelay: 1.5),
      );
      final LlmAgent root = LlmAgent(
        name: 'Root',
        model: 'gemini-2.5-flash',
        generateContentConfig: GenerateContentConfig(
          temperature: 0.2,
          httpOptions: httpOptions,
        ),
      );

      final LlmAgent cloned =
          cloneAgentWithParams(root, <String, Object?>{
                'generate_content_config.temperature': 0.6,
              })
              as LlmAgent;
      final HttpOptions clonedHttp =
          cloned.generateContentConfig!.httpOptions!;
      expect(clonedHttp, isNot(same(httpOptions)));
      expect(clonedHttp.headers, isNot(same(httpOptions.headers)));
      expect(clonedHttp.retryOptions, isNot(same(httpOptions.retryOptions)));
      clonedHttp.headers['x-env'] = 'staging';
      expect(httpOptions.headers['x-env'], 'prod');

      final LlmAgent merged =
          cloneAgentWithParams(root, <String, Object?>{
                'generate_content_config.http_options.api_version': 'v1',
              })
              as LlmAgent;
      final HttpOptions mergedHttp =
          merged.generateContentConfig!.httpOptions!;
      expect(mergedHttp.apiVersion, 'v1');
      expect(mergedHttp.headers, <String, String>{'x-env': 'prod'});
      expect(mergedHttp.retryOptions!.attempts, 3);

      final LlmAgent bare = LlmAgent(name: 'Bare', model: 'gemini-2.5-flash');
      final LlmAgent withHttp =
          cloneAgentWithParams(bare, <String, Object?>{
                'generate_content_config.http_options': <String, Object?>{
                  'api_version': 'v1alpha',
                },
              })
              as LlmAgent;
      expect(withHttp.generateContentConfig!.httpOptions!.apiVersion, 'v1alpha');
    });

    test('clones four-level composite workflow tree and reparents', () {
      final LlmAgent leafA = LlmAgent(
        name: 'DraftWriter',
        model: 'gemini-2.5-flash',
        instruction: 'Draft v1',
      );
      final LlmAgent leafB = LlmAgent(
        name: 'FactChecker',
        model: 'gemini-2.5-flash',
        instruction: 'Check facts',
      );
      final LoopAgent loop = LoopAgent(
        name: 'RefinementLoop',
        maxIterations: 2,
        subAgents: <BaseAgent>[leafA],
      );
      final ParallelAgent parallel = ParallelAgent(
        name: 'FanOut',
        subAgents: <BaseAgent>[loop, leafB],
      );
      final SequentialAgent pipeline = SequentialAgent(
        name: 'Pipeline',
        description: 'Original pipeline',
        subAgents: <BaseAgent>[parallel],
      );
      final LlmAgent root = LlmAgent(
        name: 'Orchestrator',
        model: 'gemini-2.5-flash',
        subAgents: <BaseAgent>[pipeline],
      );

      final LlmAgent cloned =
          cloneAgentWithParams(root, <String, Object?>{
                'model': 'gemini-2.5-pro',
                'sub_agents.Pipeline.description': 'Optimized pipeline',
                'sub_agents.Pipeline.sub_agents.FanOut.sub_agents.'
                    'RefinementLoop.max_iterations': 5,
                'sub_agents.Pipeline.sub_agents.FanOut.sub_agents.'
                    'RefinementLoop.sub_agents.DraftWriter.model':
                    'gemini-2.5-pro',
                'sub_agents.Pipeline.sub_agents.FanOut.sub_agents.'
                    'RefinementLoop.sub_agents.DraftWriter.'
                    'generate_content_config.temperature': 0.3,
                'sub_agents.Pipeline.sub_agents.FanOut.sub_agents.'
                    'FactChecker.model': 'gemini-2.5-flash-lite',
              })
              as LlmAgent;

      expect(cloned.model, 'gemini-2.5-pro');
      final SequentialAgent cPipeline =
          cloned.subAgents[0] as SequentialAgent;
      expect(cPipeline.description, 'Optimized pipeline');
      expect(cPipeline.parentAgent, same(cloned));

      final ParallelAgent cParallel = cPipeline.subAgents[0] as ParallelAgent;
      expect(cParallel.parentAgent, same(cPipeline));

      final LoopAgent cLoop = cParallel.subAgents[0] as LoopAgent;
      final LlmAgent cChecker = cParallel.subAgents[1] as LlmAgent;
      expect(cLoop.maxIterations, 5);
      expect(cLoop.parentAgent, same(cParallel));
      expect(cChecker.model, 'gemini-2.5-flash-lite');
      expect(cChecker.parentAgent, same(cParallel));

      final LlmAgent cWriter = cLoop.subAgents[0] as LlmAgent;
      expect(cWriter.model, 'gemini-2.5-pro');
      expect(cWriter.generateContentConfig!.temperature, closeTo(0.3, 1e-9));
      expect(cWriter.parentAgent, same(cLoop));

      // Verify original hierarchy and parent pointers were never modified.
      expect(root.model, 'gemini-2.5-flash');
      expect(pipeline.description, 'Original pipeline');
      expect(pipeline.parentAgent, same(root));
      expect(parallel.parentAgent, same(pipeline));
      expect(loop.maxIterations, 2);
      expect(loop.parentAgent, same(parallel));
      expect(leafA.model, 'gemini-2.5-flash');
      expect(leafA.generateContentConfig, isNull);
      expect(leafA.parentAgent, same(loop));
      expect(leafB.model, 'gemini-2.5-flash');
      expect(leafB.parentAgent, same(parallel));
    });

    test('sweeping sub_agents list clones supplied children', () {
      final LlmAgent originalChild = LlmAgent(
        name: 'OriginalChild',
        model: 'gemini-2.5-flash',
      );
      final LlmAgent root = LlmAgent(
        name: 'Root',
        model: 'gemini-2.5-flash',
        subAgents: <BaseAgent>[originalChild],
      );
      final LlmAgent replacementChild = LlmAgent(
        name: 'Replacement',
        model: 'gemini-2.5-flash',
      );

      final BaseAgent cloneA = cloneAgentWithParams(root, <String, Object?>{
        'sub_agents': <BaseAgent>[replacementChild],
        'sub_agents.Replacement.model': 'gemini-2.5-pro',
      });
      final BaseAgent cloneB = cloneAgentWithParams(root, <String, Object?>{
        'sub_agents': <BaseAgent>[replacementChild],
        'sub_agents.Replacement.model': 'gemini-2.5-flash-lite',
      });

      expect(replacementChild.parentAgent, isNull);
      expect(replacementChild.model, 'gemini-2.5-flash');
      expect(cloneA.subAgents[0], isNot(same(replacementChild)));
      expect(cloneB.subAgents[0], isNot(same(replacementChild)));
      expect(cloneA.subAgents[0], isNot(same(cloneB.subAgents[0])));
      expect(cloneA.subAgents[0].parentAgent, same(cloneA));
      expect(cloneB.subAgents[0].parentAgent, same(cloneB));
      expect((cloneA.subAgents[0] as LlmAgent).model, 'gemini-2.5-pro');
      expect((cloneB.subAgents[0] as LlmAgent).model, 'gemini-2.5-flash-lite');
    });

    test('clones nested AgentTools and sub_agents inside AgentTools', () {
      final LlmAgent innerToolAgent = LlmAgent(
        name: 'SqlTool',
        model: 'gemini-2.5-flash',
      );
      final LlmAgent subWithTool = LlmAgent(
        name: 'Analyst',
        model: 'gemini-2.5-flash',
        tools: <Object>[_noopTool, AgentTool(agent: innerToolAgent)],
      );

      final LlmAgent leafInTool = LlmAgent(
        name: 'Fetcher',
        model: 'gemini-2.5-flash',
      );
      final LlmAgent toolWithSub = LlmAgent(
        name: 'RouterTool',
        model: 'gemini-2.5-flash',
        subAgents: <BaseAgent>[leafInTool],
      );
      final LlmAgent root = LlmAgent(
        name: 'Coordinator',
        model: 'gemini-2.5-flash',
        subAgents: <BaseAgent>[subWithTool],
        tools: <Object>[AgentTool(agent: toolWithSub)],
      );

      final LlmAgent cloned =
          cloneAgentWithParams(root, <String, Object?>{
                'sub_agents.Analyst.tools.SqlTool.model': 'gemini-2.5-pro',
                'tools.RouterTool.model': 'gemini-2.5-flash-lite',
                'tools.RouterTool.sub_agents.Fetcher.model': 'gemini-2.5-pro',
              })
              as LlmAgent;

      final LlmAgent cAnalyst = cloned.subAgents[0] as LlmAgent;
      expect(cAnalyst.tools[0], same(_noopTool));
      final AgentTool cSqlTool = cAnalyst.tools[1] as AgentTool;
      expect((cSqlTool.agent as LlmAgent).model, 'gemini-2.5-pro');
      expect(cSqlTool.agent.parentAgent, isNull);
      expect(innerToolAgent.model, 'gemini-2.5-flash');

      final AgentTool cRouterTool = cloned.tools[0] as AgentTool;
      expect((cRouterTool.agent as LlmAgent).model, 'gemini-2.5-flash-lite');
      expect(cRouterTool.agent.parentAgent, isNull);
      final LlmAgent cFetcher = cRouterTool.agent.subAgents[0] as LlmAgent;
      expect(cFetcher.model, 'gemini-2.5-pro');
      expect(cFetcher.parentAgent, same(cRouterTool.agent));
      expect(leafInTool.model, 'gemini-2.5-flash');
    });

    test(
      'single_turn and dual-bound sub_agents rebind and reject tools path',
      () {
        final LlmAgent specialist = LlmAgent(
          name: 'Specialist',
          model: 'gemini-2.5-flash',
          mode: 'single_turn',
        );
        final LlmAgent root = LlmAgent(
          name: 'Coordinator',
          model: 'gemini-2.5-flash',
          subAgents: <BaseAgent>[specialist],
        );

        final LlmAgent first =
            cloneAgentWithParams(root, <String, Object?>{
                  'sub_agents.Specialist.model': 'gemini-2.5-pro',
                })
                as LlmAgent;
        final LlmAgent second =
            cloneAgentWithParams(first, <String, Object?>{
                  'sub_agents.Specialist.model': 'gemini-2.5-flash-lite',
                })
                as LlmAgent;
        final List<AgentTool> agentTools = second.tools
            .whereType<AgentTool>()
            .toList();
        expect(agentTools, hasLength(1));
        expect(agentTools[0].agent, same(second.subAgents[0]));
        expect(
          (second.subAgents[0] as LlmAgent).model,
          'gemini-2.5-flash-lite',
        );

        expect(
          () => cloneAgentWithParams(root, <String, Object?>{
            'tools.Specialist.model': 'gemini-2.5-pro',
          }),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '${e.message}',
              'message',
              allOf(
                contains("has no AgentTool agent named 'Specialist'"),
                contains("use 'sub_agents.Specialist.model'"),
              ),
            ),
          ),
        );

        final LlmAgent manualSub = LlmAgent(
          name: 'Helper',
          model: 'gemini-2.5-flash',
        );
        final LlmAgent manualRoot = LlmAgent(
          name: 'Coordinator',
          model: 'gemini-2.5-flash',
        );
        manualRoot.subAgents = <BaseAgent>[manualSub];
        manualRoot.tools = <Object>[AgentTool(agent: manualSub)];

        final LlmAgent rebound =
            cloneAgentWithParams(manualRoot, <String, Object?>{
                  'sub_agents.Helper.model': 'gemini-2.5-pro',
                })
                as LlmAgent;
        expect(rebound.tools[0], isA<AgentTool>());
        expect(
          (rebound.tools[0] as AgentTool).agent,
          same(rebound.subAgents[0]),
        );
        expect((rebound.subAgents[0] as LlmAgent).model, 'gemini-2.5-pro');

        expect(
          () => cloneAgentWithParams(manualRoot, <String, Object?>{
            'tools.Helper.model': 'gemini-2.5-pro',
          }),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '${e.message}',
              'message',
              allOf(
                contains("has no AgentTool agent named 'Helper'"),
                contains("use 'sub_agents.Helper.model'"),
              ),
            ),
          ),
        );
      },
    );

    test(
      'canonical prefixes disambiguate collisions and preserve caller maps',
      () {
        final LlmAgent plannerSub = LlmAgent(
          name: 'planner',
          model: 'gemini-2.5-flash',
        );
        final LlmAgent subHelper = LlmAgent(
          name: 'Helper',
          model: 'gemini-2.5-flash',
        );
        final LlmAgent toolHelper = LlmAgent(
          name: 'Helper',
          model: 'gemini-2.5-flash',
        );
        final LlmAgent root = LlmAgent(
          name: 'Coordinator',
          model: 'gemini-2.5-flash',
          generateContentConfig: GenerateContentConfig(
            temperature: 0.1,
            thinkingConfig: <String, Object?>{'thinking_budget': 256},
          ),
          subAgents: <BaseAgent>[plannerSub, subHelper],
          tools: <Object>[AgentTool(agent: toolHelper)],
        );
        final Map<String, Object?> sharedThinking = <String, Object?>{
          'include_thoughts': true,
        };

        final LlmAgent cloneA =
            cloneAgentWithParams(root, <String, Object?>{
                  'generate_content_config.thinking_config': sharedThinking,
                  'generate_content_config.top_p': 0.5,
                  'sub_agents.planner.model': 'gemini-2.5-pro',
                  'sub_agents.Helper.model': 'gemini-2.5-flash-lite',
                  'tools.Helper.model': 'gemini-2.5-pro',
                })
                as LlmAgent;
        final LlmAgent cloneB =
            cloneAgentWithParams(root, <String, Object?>{
                  'generate_content_config.thinking_config': sharedThinking,
                  'generate_content_config.top_p': 0.9,
                })
                as LlmAgent;

        expect(sharedThinking, <String, Object?>{'include_thoughts': true});
        expect((cloneA.subAgents[0] as LlmAgent).model, 'gemini-2.5-pro');
        expect((cloneA.subAgents[1] as LlmAgent).model, 'gemini-2.5-flash-lite');
        expect(
          ((cloneA.tools[0] as AgentTool).agent as LlmAgent).model,
          'gemini-2.5-pro',
        );
        for (final (LlmAgent cloned, double expectedTopP) in <(LlmAgent, double)>[
          (cloneA, 0.5),
          (cloneB, 0.9),
        ]) {
          expect(cloned.generateContentConfig!.topP, closeTo(expectedTopP, 1e-9));
          expect(cloned.generateContentConfig!.thinkingConfig, <String, Object?>{
            'include_thoughts': true,
            'thinking_budget': 256,
          });
        }
      },
    );

    test('invalid parameter paths fail fast', () {
      final LlmAgent worker = LlmAgent(name: 'Worker', model: 'gemini-2.5-flash');
      final SequentialAgent pipeline = SequentialAgent(
        name: 'Pipeline',
        subAgents: <BaseAgent>[],
      );
      final LlmAgent helper = LlmAgent(name: 'Helper', model: 'gemini-2.5-flash');
      final LlmAgent root = LlmAgent(
        name: 'Root',
        model: 'gemini-2.5-flash',
        subAgents: <BaseAgent>[worker, pipeline],
        tools: <Object>[AgentTool(agent: helper)],
      );

      final List<(Map<String, Object?>, Pattern)> cases =
          <(Map<String, Object?>, Pattern)>[
            (
              <String, Object?>{'sub_agents.Ghost.model': 'gemini-2.5-pro'},
              RegExp(
                r"has no sub-agent named 'Ghost'\. Sub-agents: \['Pipeline', 'Worker'\]",
              ),
            ),
            (
              <String, Object?>{'sub_agents.Worker': 'gemini-2.5-pro'},
              RegExp(r"names sub-agent 'Worker' but no field"),
            ),
            (
              <String, Object?>{'sub_agents.Worker.': 'gemini-2.5-pro'},
              RegExp(r"names sub-agent 'Worker' but no field"),
            ),
            (
              <String, Object?>{'tools.Ghost.model': 'gemini-2.5-pro'},
              RegExp(
                r"has no AgentTool agent named 'Ghost'\. AgentTools: \['Helper'\]",
              ),
            ),
            (
              <String, Object?>{'tools.Helper': 'gemini-2.5-pro'},
              RegExp(r"names AgentTool 'Helper' but no field"),
            ),
            (
              <String, Object?>{'tools.Helper.': 'gemini-2.5-pro'},
              RegExp(r"names AgentTool 'Helper' but no field"),
            ),
            (
              <String, Object?>{'generate_content_config.': 0.5},
              RegExp(r'names no config field'),
            ),
            (
              <String, Object?>{
                'sub_agents.Pipeline.generate_content_config.temperature': 0.5,
              },
              RegExp(r"SequentialAgent \('Pipeline'\) has no generate_content_config"),
            ),
            (
              <String, Object?>{
                'generate_content_config': GenerateContentConfig(temperature: 0.2),
                'generate_content_config.temperature': 0.7,
              },
              RegExp(r"Cannot set both 'generate_content_config' as a whole and"),
            ),
            (
              <String, Object?>{
                'generate_content_config.thinking_config': <String, Object?>{
                  'thinking_budget': 128,
                },
                'generate_content_config.thinking_config.thinking_budget': 512,
              },
              RegExp(
                r"sets a field inside 'generate_content_config\.thinking_config'",
              ),
            ),
            (
              <String, Object?>{
                'generate_content_config.thinking_config.thinking_budget': 512,
                'generate_content_config.thinking_config': <String, Object?>{
                  'thinking_budget': 128,
                },
              },
              RegExp(
                r"sets a field inside 'generate_content_config\.thinking_config'",
              ),
            ),
            (
              <String, Object?>{'planner.thinking_config': null},
              RegExp(r"sets a field inside 'planner'; only 'generate_content_config\."),
            ),
            (
              <String, Object?>{'Worker.model': 'gemini-2.5-pro'},
              RegExp(r"is not valid on 'Root'\. Prefix child agents with 'sub_agents\.'"),
            ),
            (
              <String, Object?>{'temperature': 0.5},
              RegExp(
                r"is not a field of LlmAgent \('Root'\); use 'generate_content_config\.temperature'",
              ),
            ),
          ];

      for (final (Map<String, Object?> badParams, Pattern pattern) in cases) {
        expect(
          () => cloneAgentWithParams(root, badParams),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '${e.message}',
              'message',
              matches(pattern),
            ),
          ),
        );
      }
    });

    test('unknown GenerateContentConfig subfield raises ArgumentError', () {
      final LlmAgent root = LlmAgent(name: 'Root', model: 'gemini-2.5-flash');
      expect(
        () => cloneAgentWithParams(root, <String, Object?>{
          'generate_content_config.not_a_real_field': 123,
        }),
        throwsArgumentError,
      );
    });

    test('config updates are deep copied across clones', () {
      final Map<String, Object?> sharedThinking = <String, Object?>{
        'thinking_budget': 512,
      };
      final LlmAgent root = LlmAgent(
        name: 'Root',
        model: 'gemini-2.5-flash',
        generateContentConfig: GenerateContentConfig(temperature: 0.2),
      );

      final LlmAgent cloneA =
          cloneAgentWithParams(root, <String, Object?>{
                'generate_content_config.thinking_config': sharedThinking,
              })
              as LlmAgent;
      final LlmAgent cloneB =
          cloneAgentWithParams(root, <String, Object?>{
                'generate_content_config.thinking_config': sharedThinking,
              })
              as LlmAgent;

      final Map<String, Object?> tcA =
          cloneA.generateContentConfig!.thinkingConfig! as Map<String, Object?>;
      final Map<String, Object?> tcB =
          cloneB.generateContentConfig!.thinkingConfig! as Map<String, Object?>;
      expect(tcA, isNot(same(sharedThinking)));
      expect(tcA, isNot(same(tcB)));
      tcA['thinking_budget'] = 2048;
      expect(sharedThinking['thinking_budget'], 512);
      expect(tcB['thinking_budget'], 512);
    });

    test(
      'recursive merge preserves nested model, dict, and http_options siblings',
      () {
        final GenerateContentConfig baseCfg = GenerateContentConfig(
          labels: <String, String>{'env': 'prod', 'team': 'adk'},
          toolConfig: LlmToolConfig(
            functionCallingConfig: FunctionCallingConfig(
              mode: FunctionCallingConfigMode.auto,
              allowedFunctionNames: <String>['search'],
            ),
          ),
          httpOptions: HttpOptions(
            headers: <String, String>{'x-env': 'prod', 'x-team': 'adk'},
            retryOptions: HttpRetryOptions(attempts: 3, initialDelay: 1.5),
          ),
        );
        final LlmAgent root = LlmAgent(
          name: 'Root',
          model: 'gemini-2.5-flash',
          generateContentConfig: baseCfg,
        );

        final LlmAgent cloned =
            cloneAgentWithParams(root, <String, Object?>{
                  'generate_content_config.labels.env': 'staging',
                  'generate_content_config.tool_config.function_calling_config.mode':
                      FunctionCallingConfigMode.any,
                  'generate_content_config.http_options.headers.x-env':
                      'staging',
                  'generate_content_config.http_options.retry_options.attempts':
                      5,
                })
                as LlmAgent;

        final GenerateContentConfig cfg = cloned.generateContentConfig!;
        expect(cfg.labels, <String, String>{'env': 'staging', 'team': 'adk'});
        expect(baseCfg.labels, <String, String>{'env': 'prod', 'team': 'adk'});
        expect(
          cfg.toolConfig!.functionCallingConfig!.mode,
          FunctionCallingConfigMode.any,
        );
        expect(
          cfg.toolConfig!.functionCallingConfig!.allowedFunctionNames,
          <String>['search'],
        );
        expect(
          baseCfg.toolConfig!.functionCallingConfig!.mode,
          FunctionCallingConfigMode.auto,
        );
        expect(cfg.httpOptions!.headers, <String, String>{
          'x-env': 'staging',
          'x-team': 'adk',
        });
        expect(cfg.httpOptions!.retryOptions!.attempts, 5);
        expect(cfg.httpOptions!.retryOptions!.initialDelay, 1.5);
        expect(baseCfg.httpOptions!.headers, <String, String>{
          'x-env': 'prod',
          'x-team': 'adk',
        });
        expect(baseCfg.httpOptions!.retryOptions!.attempts, 3);
      },
    );

    test('GenerateContentConfig subclass is preserved and validated', () {
      final LlmAgent root = LlmAgent(
        name: 'Root',
        model: 'gemini-2.5-flash',
        generateContentConfig: AnthropicGenerateContentConfig(
          effort: 'low',
          temperature: 0.2,
        ),
      );

      final LlmAgent dottedClone =
          cloneAgentWithParams(root, <String, Object?>{
                'generate_content_config.effort': 'high',
              })
              as LlmAgent;
      final LlmAgent wholeClone =
          cloneAgentWithParams(root, <String, Object?>{
                'generate_content_config': <String, Object?>{'effort': 'medium'},
              })
              as LlmAgent;

      expect(
        dottedClone.generateContentConfig,
        isA<AnthropicGenerateContentConfig>(),
      );
      expect(
        (dottedClone.generateContentConfig! as AnthropicGenerateContentConfig)
            .effort,
        'high',
      );
      expect(dottedClone.generateContentConfig!.temperature, closeTo(0.2, 1e-9));
      expect(
        wholeClone.generateContentConfig,
        isA<AnthropicGenerateContentConfig>(),
      );
      expect(
        (wholeClone.generateContentConfig! as AnthropicGenerateContentConfig)
            .effort,
        'medium',
      );

      expect(
        () => cloneAgentWithParams(root, <String, Object?>{
          'generate_content_config.thinking_config.thinking_level': 'HIGH',
        }),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            contains('thinking_level is not supported'),
          ),
        ),
      );
    });

    test('camelCase config aliases apply and sync planner', () {
      final LlmAgent root = LlmAgent(
        name: 'Root',
        model: 'gemini-2.5-flash',
        planner: BuiltInPlanner(
          thinkingConfig: <String, Object?>{
            'include_thoughts': true,
            'thinking_budget': 1024,
          },
        ),
        generateContentConfig: GenerateContentConfig(
          temperature: 0.3,
          httpOptions: HttpOptions(headers: <String, String>{'x-a': '1'}),
        ),
      );

      final LlmAgent cloned =
          cloneAgentWithParams(root, <String, Object?>{
                'generate_content_config.maxOutputTokens': 512,
                'generate_content_config.httpOptions.apiVersion': 'v1',
                'generate_content_config.thinkingConfig.thinkingBudget': 256,
              })
              as LlmAgent;

      final GenerateContentConfig cfg = cloned.generateContentConfig!;
      expect(cfg.maxOutputTokens, 512);
      expect(cfg.temperature, closeTo(0.3, 1e-9));
      expect(cfg.httpOptions!.apiVersion, 'v1');
      expect(cfg.httpOptions!.headers, <String, String>{'x-a': '1'});
      final Map<String, Object?> expectedTc = <String, Object?>{
        'include_thoughts': true,
        'thinking_budget': 256,
      };
      expect(cfg.thinkingConfig, expectedTc);
      expect((cloned.planner! as BuiltInPlanner).thinkingConfig, expectedTc);

      expect(
        () => cloneAgentWithParams(root, <String, Object?>{
          'generate_content_config.max_output_tokens': 128,
          'generate_content_config.maxOutputTokens': 256,
        }),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            contains('Duplicate override'),
          ),
        ),
      );
    });

    test('swept BuiltInPlanner is isolated across clones', () {
      final BuiltInPlanner sharedPlanner = BuiltInPlanner(
        thinkingConfig: <String, Object?>{'thinking_budget': 1024},
      );
      final LlmAgent root = LlmAgent(name: 'Root', model: 'gemini-2.5-flash');

      final LlmAgent cloneA =
          cloneAgentWithParams(root, <String, Object?>{'planner': sharedPlanner})
              as LlmAgent;
      final LlmAgent cloneB =
          cloneAgentWithParams(root, <String, Object?>{'planner': sharedPlanner})
              as LlmAgent;

      final BuiltInPlanner plannerA = cloneA.planner! as BuiltInPlanner;
      final BuiltInPlanner plannerB = cloneB.planner! as BuiltInPlanner;
      expect(plannerA, isNot(same(sharedPlanner)));
      expect(plannerA, isNot(same(plannerB)));
      expect(
        plannerA.thinkingConfig,
        isNot(same(sharedPlanner.thinkingConfig)),
      );
      expect(plannerA.thinkingConfig, isNot(same(plannerB.thinkingConfig)));
      (plannerA.thinkingConfig as Map<String, Object?>)['thinking_budget'] =
          256;
      expect(
        (sharedPlanner.thinkingConfig
            as Map<String, Object?>)['thinking_budget'],
        1024,
      );
      expect(
        (plannerB.thinkingConfig as Map<String, Object?>)['thinking_budget'],
        1024,
      );
    });

    test('forbidden LlmAgent config fields fail fast', () {
      final LlmAgent root = LlmAgent(name: 'Root', model: 'gemini-2.5-flash');
      final List<(Map<String, Object?>, String)> cases =
          <(Map<String, Object?>, String)>[
            (
              <String, Object?>{
                'generate_content_config.system_instruction': 'Be brief.',
              },
              'LlmAgent.instruction',
            ),
            (
              <String, Object?>{
                'generate_content_config': <String, Object?>{
                  'system_instruction': 'Be brief.',
                },
              },
              'LlmAgent.instruction',
            ),
            (
              <String, Object?>{
                'generate_content_config.tools': <ToolDeclaration>[
                  ToolDeclaration(
                    functionDeclarations: <FunctionDeclaration>[
                      FunctionDeclaration(name: 'ping'),
                    ],
                  ),
                ],
              },
              'LlmAgent.tools',
            ),
            (
              <String, Object?>{
                'generate_content_config.response_schema': <String, Object?>{
                  'type': 'STRING',
                },
              },
              'LlmAgent.outputSchema',
            ),
          ];

      for (final (Map<String, Object?> badParams, String expected) in cases) {
        expect(
          () => cloneAgentWithParams(root, badParams),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '${e.message}',
              'message',
              contains(expected),
            ),
          ),
        );
      }
    });

    test('AgentTool metadata syncs with cloned agent', () {
      final LlmAgent helper = LlmAgent(
        name: 'Helper',
        model: 'gemini-2.5-flash',
        description: 'Old helper',
      );
      final LlmAgent aliased = LlmAgent(
        name: 'Aliased',
        model: 'gemini-2.5-flash',
        description: 'Old aliased',
      );
      final AgentTool aliasedTool = AgentTool(agent: aliased)
        ..name = 'custom_tool_alias';
      final LlmAgent root = LlmAgent(
        name: 'Root',
        model: 'gemini-2.5-flash',
        tools: <Object>[AgentTool(agent: helper), aliasedTool],
      );

      final LlmAgent cloned =
          cloneAgentWithParams(root, <String, Object?>{
                'tools.Helper.name': 'HelperV2',
                'tools.Helper.description': 'New helper',
                'tools.Aliased.name': 'AliasedV2',
                'tools.Aliased.description': 'New aliased',
              })
              as LlmAgent;

      final AgentTool tool0 = cloned.tools[0] as AgentTool;
      final AgentTool tool1 = cloned.tools[1] as AgentTool;
      expect(tool0.name, 'HelperV2');
      expect(tool0.description, 'New helper');
      expect(tool1.name, 'custom_tool_alias');
      expect(tool1.description, 'New aliased');
      expect((root.tools[0] as AgentTool).name, 'Helper');
      expect((root.tools[0] as AgentTool).description, 'Old helper');
    });
  });

  group('grid_search_agent_optimizer parity', () {
    test('feature registry registers gridSearchAgentOptimizer and gates usage', () {
      final FeatureConfig? cfg = getFeatureConfig(
        FeatureName.gridSearchAgentOptimizer,
      );
      expect(cfg, isNotNull);
      expect(cfg!.stage, FeatureStage.experimental);
      expect(cfg.defaultOn, isTrue);
      expect(
        FeatureName.gridSearchAgentOptimizer.value,
        'GRID_SEARCH_AGENT_OPTIMIZER',
      );

      overrideFeatureEnabled(FeatureName.gridSearchAgentOptimizer, false);
      expect(
        () => GridSearchAgentOptimizer(
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash'],
            },
          ),
        ),
        throwsStateError,
      );
    });

    test('optimize evaluates candidates and returns Pareto front', () async {
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>[
                'gemini-2.5-flash-lite',
                'gemini-2.5-flash',
                'gemini-2.5-pro',
              ],
              'generate_content_config.temperature': <Object?>[0.0, 0.5],
            },
          );
      final GridSearchAgentOptimizer optimizer = GridSearchAgentOptimizer(
        config,
      );
      final LlmAgent initialAgent = LlmAgent(
        name: 'Worker',
        model: 'gemini-2.5-flash',
      );
      final _FakeEvalSampler sampler = _FakeEvalSampler(
        exampleIds: <String>['c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7', 'c8'],
      );

      final OptimizerResult<GridSearchAgentWithScores> result = await optimizer
          .optimize(initialAgent, sampler);

      final Set<String> modelsOnFront = _modelsOnFront(result).toSet();
      expect(modelsOnFront, <String>{
        'gemini-2.5-flash-lite',
        'gemini-2.5-flash',
        'gemini-2.5-pro',
      });
      expect(result.optimizedAgents, hasLength(3));
      const double expectedProMean = (0.95 + 0.95 * 0.9) / 2.0;
      expect(
        result.optimizedAgents[0].overallScore,
        closeTo(expectedProMean, 1e-9),
      );
      expect(result.optimizedAgents[0].tokenUsage['total_tokens'], 1000.0);
      expect(result.optimizedAgents[0].latencySec, closeTo(2.0, 1e-9));
    });

    test('every candidate is scored on the same full example set', () async {
      final List<String> exampleIds = List<String>.generate(
        9,
        (int i) => 'ex_$i',
      );
      final _FakeEvalSampler sampler = _FakeEvalSampler(exampleIds: exampleIds);
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>[
                'gemini-2.5-flash-lite',
                'gemini-2.5-flash',
                'gemini-2.5-pro',
              ],
              'generate_content_config.temperature': <Object?>[0.0, 0.5],
            },
            maxConcurrentCandidates: 2,
          );

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(config).optimize(
            LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
            sampler,
          );

      expect(sampler.recordedBatches, hasLength(6));
      for (final (String _, List<String> batch) in sampler.recordedBatches) {
        expect(batch, exampleIds);
      }
      expect(result.optimizedAgents, isNotEmpty);
      for (final GridSearchAgentWithScores item in result.optimizedAgents) {
        expect(item.metadata['num_cases_evaluated'], exampleIds.length);
      }
    });

    test('optimize clones SequentialAgent and ParallelAgent without mutation', () async {
      final LlmAgent weather = LlmAgent(
        name: 'WeatherSpecialist',
        model: 'gemini-2.5-flash',
      );
      final LlmAgent traffic = LlmAgent(
        name: 'TrafficSpecialist',
        model: 'gemini-2.5-flash',
      );
      final ParallelAgent fanOut = ParallelAgent(
        name: 'FanOut',
        subAgents: <BaseAgent>[weather, traffic],
      );
      final LlmAgent aggregator = LlmAgent(
        name: 'Aggregator',
        model: 'gemini-2.5-flash',
      );
      final SequentialAgent pipeline = SequentialAgent(
        name: 'ParallelPipeline',
        subAgents: <BaseAgent>[fanOut, aggregator],
      );
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'sub_agents.FanOut.sub_agents.WeatherSpecialist.model': <Object?>[
                'gemini-2.5-flash-lite',
              ],
              'sub_agents.FanOut.sub_agents.TrafficSpecialist.model': <Object?>[
                'gemini-2.5-pro',
              ],
              'sub_agents.Aggregator.model': <Object?>['gemini-2.5-pro'],
            },
          );
      final _FakeEvalSampler sampler = _FakeEvalSampler(
        exampleIds: <String>['c1', 'c2'],
      );

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(config).optimize(pipeline, sampler);

      final BaseAgent clonedPipeline =
          result.optimizedAgents[0].optimizedAgent;
      final BaseAgent clonedFanOut = clonedPipeline.subAgents[0];
      expect(
        (clonedFanOut.subAgents[0] as LlmAgent).model,
        'gemini-2.5-flash-lite',
      );
      expect((clonedFanOut.subAgents[1] as LlmAgent).model, 'gemini-2.5-pro');
      expect((clonedPipeline.subAgents[1] as LlmAgent).model, 'gemini-2.5-pro');
      expect((weather).model, 'gemini-2.5-flash');
      expect((traffic).model, 'gemini-2.5-flash');
      expect((aggregator).model, 'gemini-2.5-flash');
    });

    test('optimize clones AgentTool children without mutation', () async {
      final LlmAgent analyst = LlmAgent(
        name: 'SqlAnalystAgent',
        instruction: 'Analyze SQL queries.',
        model: 'gemini-2.5-flash',
      );
      final AgentTool tool = AgentTool(agent: analyst);
      final LlmAgent manager = LlmAgent(
        name: 'ManagerAgent',
        instruction: 'Coordinate queries.',
        model: 'gemini-2.5-flash',
        tools: <Object>[tool],
      );
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'tools.SqlAnalystAgent.model': <Object?>['gemini-2.5-pro'],
            },
          );
      final _FakeEvalSampler sampler = _FakeEvalSampler(
        exampleIds: <String>['c1', 'c2'],
      );

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(config).optimize(manager, sampler);

      final LlmAgent clonedManager =
          result.optimizedAgents[0].optimizedAgent as LlmAgent;
      final AgentTool clonedTool = clonedManager.tools[0] as AgentTool;
      expect(clonedTool, isNot(same(tool)));
      expect(clonedTool.agent, isNot(same(analyst)));
      expect(clonedTool.agent.parentAgent, isNull);
      expect((clonedTool.agent as LlmAgent).model, 'gemini-2.5-pro');
      expect(analyst.model, 'gemini-2.5-flash');
    });

    test(
      'unknown or unprefixed path raises before any sampler call',
      () async {
        final LlmAgent traffic = LlmAgent(
          name: 'TrafficSpecialist',
          model: 'gemini-2.5-flash',
        );
        final ParallelAgent fanOut = ParallelAgent(
          name: 'FanOut',
          subAgents: <BaseAgent>[traffic],
        );
        final SequentialAgent pipeline = SequentialAgent(
          name: 'Pipeline',
          subAgents: <BaseAgent>[fanOut],
        );

        final List<(String, String)> cases = <(String, String)>[
          ('sub_agents.Nonexistent.model', 'has no sub-agent named'),
          ('tools.Nonexistent.model', 'has no AgentTool agent named'),
          ('sub_agents.TrafficSpecialist.model', 'has no sub-agent named'),
          ('TrafficSpecialist.model', 'Prefix child agents'),
          ('temperature', 'generate_content_config.temperature'),
          ('thinking_config.thinking_budget', 'Prefix child agents'),
        ];

        for (final (String path, String message) in cases) {
          final _FakeEvalSampler sampler = _FakeEvalSampler(
            exampleIds: <String>['c1'],
          );
          final GridSearchAgentOptimizerConfig config =
              GridSearchAgentOptimizerConfig(
                paramGrid: <String, List<Object?>>{
                  path: <Object?>['gemini-2.5-pro'],
                },
              );
          await expectLater(
            () => GridSearchAgentOptimizer(config).optimize(pipeline, sampler),
            throwsA(
              isA<ArgumentError>().having(
                (ArgumentError e) => '${e.message}',
                'message',
                contains(message),
              ),
            ),
          );
          expect(sampler.recordedBatches, isEmpty);
        }
      },
    );

    test('optimize supports string quality_metric', () async {
      final LlmAgent agent = LlmAgent(
        name: 'Worker',
        model: 'gemini-2.5-flash',
      );
      final _FakeEvalSampler sampler = _FakeEvalSampler(
        exampleIds: <String>['c1', 'c2'],
      );
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash'],
            },
            qualityMetric: 'f1',
          );

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(config).optimize(agent, sampler);

      expect(result.optimizedAgents[0].overallScore, closeTo(0.765, 1e-9));
    });

    test('optimize supports weighted mapping quality_metric', () async {
      final LlmAgent agent = LlmAgent(
        name: 'Worker',
        model: 'gemini-2.5-flash',
      );
      final _FakeEvalSampler sampler = _FakeEvalSampler(
        exampleIds: <String>['c1', 'c2'],
      );
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash'],
            },
            qualityMetric: <String, double>{'quality': 0.5, 'f1': 0.5},
          );

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(config).optimize(agent, sampler);

      const double expected = 0.5 * 0.85 + 0.5 * 0.765;
      expect(result.optimizedAgents[0].overallScore, closeTo(expected, 1e-9));
    });

    test('optimize supports callable quality_metric', () async {
      final LlmAgent agent = LlmAgent(
        name: 'Worker',
        model: 'gemini-2.5-flash',
      );
      final _FakeEvalSampler sampler = _FakeEvalSampler(
        exampleIds: <String>['c1', 'c2'],
      );
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash'],
            },
            qualityMetric: (Map<String, double> scores) =>
                (scores['quality'] ?? 0.0) * 2.0,
          );

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(config).optimize(agent, sampler);

      expect(result.optimizedAgents[0].overallScore, closeTo(1.70, 1e-9));
    });

    test('empty quality_metric mapping averages quality metrics', () async {
      final LlmAgent agent = LlmAgent(
        name: 'Worker',
        model: 'gemini-2.5-flash',
      );
      final _FakeEvalSampler sampler = _FakeEvalSampler(
        exampleIds: <String>['c1', 'c2'],
      );
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash'],
            },
            qualityMetric: const <String, double>{},
          );

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(config).optimize(agent, sampler);

      const double expected = (0.85 + 0.765) / 2.0;
      expect(result.optimizedAgents[0].overallScore, closeTo(expected, 1e-9));
    });

    test('misnamed quality_metric raises', () async {
      for (final Object qualityMetric in <Object>[
        'f_1',
        <String, double>{'quality': 0.5, 'f_1': 0.5},
      ]) {
        final GridSearchAgentOptimizerConfig config =
            GridSearchAgentOptimizerConfig(
              paramGrid: <String, List<Object?>>{
                'model': <Object?>['gemini-2.5-flash'],
              },
              qualityMetric: qualityMetric,
            );
        await expectLater(
          () => GridSearchAgentOptimizer(config).optimize(
            LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
            _FakeEvalSampler(exampleIds: <String>['c1']),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '${e.message}',
              'message',
              contains('did not report'),
            ),
          ),
        );
      }
    });

    test('optimize filters infeasible candidates by thresholds', () async {
      final LlmAgent agent = LlmAgent(
        name: 'Worker',
        model: 'gemini-2.5-flash',
      );
      final _FakeEvalSampler sampler = _FakeEvalSampler(
        exampleIds: <String>['c1', 'c2'],
      );
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>[
                'gemini-2.5-flash-lite',
                'gemini-2.5-flash',
                'gemini-2.5-pro',
              ],
            },
            minQualityScore: 0.80,
            maxLatencySec: 1.5,
            maxTotalTokens: 600,
          );

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(config).optimize(agent, sampler);

      expect(result.optimizedAgents, hasLength(1));
      expect(
        (result.optimizedAgents[0].optimizedAgent as LlmAgent).model,
        'gemini-2.5-flash',
      );
    });

    test('optimize supports conditional sub-grids', () async {
      final LlmAgent agent = LlmAgent(
        name: 'Worker',
        model: 'gemini-2.5-flash',
      );
      final _FakeEvalSampler sampler = _FakeEvalSampler(
        exampleIds: <String>['c1', 'c2'],
      );
      const String budgetKey =
          'generate_content_config.thinking_config.thinking_budget';
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <Map<String, List<Object?>>>[
              <String, List<Object?>>{
                'model': <Object?>['gemini-2.5-flash-lite'],
                budgetKey: <Object?>[0],
              },
              <String, List<Object?>>{
                'model': <Object?>['gemini-2.5-pro'],
                budgetKey: <Object?>[512],
              },
            ],
          );

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(config).optimize(agent, sampler);

      expect(_modelsOnFront(result).toSet(), <String>{
        'gemini-2.5-flash-lite',
        'gemini-2.5-pro',
      });
    });

    test('token total counts reasoning_tokens once', () async {
      final _TokenResultSampler sampler = _TokenResultSampler(
        <String, Object?>{
          'score': 1500.0,
          'details': <String, Object?>{
            'token_usage_details': <String, Object?>{
              'input_tokens': 1000.0,
              'output_tokens': 500.0,
              'reasoning_tokens': 400.0,
            },
          },
        },
      );
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash'],
            },
          );

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(config).optimize(
            LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
            sampler,
          );

      expect(result.optimizedAgents[0].tokenUsage, <String, double>{
        'total_tokens': 1500.0,
        'input_tokens': 1000.0,
        'output_tokens': 500.0,
        'reasoning_tokens': 400.0,
      });
    });

    test('score-only token usage is reported as total_tokens only', () async {
      final _TokenResultSampler sampler = _TokenResultSampler(
        <String, Object?>{'score': 1500.0},
      );
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash'],
            },
          );

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(config).optimize(
            LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
            sampler,
          );

      expect(result.optimizedAgents[0].tokenUsage, <String, double>{
        'total_tokens': 1500.0,
      });
    });

    test('unreported token usage is unknown not zero and warns', () async {
      final _FakeEvalSampler sampler = _FakeEvalSampler(
        exampleIds: <String>['c1', 'c2'],
        modelsWithoutTokens: <String>{'gemini-2.5-flash-lite'},
      );
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash-lite', 'gemini-2.5-flash'],
            },
          );
      final List<String> warnings = <String>[];

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(
            config,
            onWarning: warnings.add,
          ).optimize(
            LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
            sampler,
          );

      final Map<String, Map<String, double>> usageByModel =
          <String, Map<String, double>>{
            for (final GridSearchAgentWithScores item in result.optimizedAgents)
              '${(item.optimizedAgent as LlmAgent).model}': item.tokenUsage,
          };
      expect(usageByModel['gemini-2.5-flash-lite'], isEmpty);
      expect(usageByModel['gemini-2.5-flash']!['total_tokens'], 400.0);
      expect(
        warnings.join('\n'),
        contains('1 of 2 scored candidates reported no token usage'),
      );
    });

    test('max_total_tokens excludes candidates without token usage', () async {
      final _FakeEvalSampler sampler = _FakeEvalSampler(
        exampleIds: <String>['c1', 'c2'],
        modelsWithoutTokens: <String>{'gemini-2.5-flash-lite'},
      );
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash-lite', 'gemini-2.5-flash'],
            },
            maxTotalTokens: 1000,
          );
      final List<String> warnings = <String>[];

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(
            config,
            onWarning: warnings.add,
          ).optimize(
            LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
            sampler,
          );

      expect(_modelsOnFront(result), <String>['gemini-2.5-flash']);
      expect(warnings.join('\n'), contains('fails max_total_tokens if set'));
    });

    test('no candidate reporting tokens still returns the front', () async {
      final List<String> models = <String>[
        'gemini-2.5-flash-lite',
        'gemini-2.5-flash',
      ];
      final _FakeEvalSampler sampler = _FakeEvalSampler(
        exampleIds: <String>['c1', 'c2'],
        modelsWithoutTokens: models.toSet(),
      );
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{'model': models},
          );
      final List<String> warnings = <String>[];

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(
            config,
            onWarning: warnings.add,
          ).optimize(
            LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
            sampler,
          );

      expect(result.optimizedAgents, hasLength(2));
      expect(
        warnings.join('\n'),
        contains('2 of 2 scored candidates reported no token usage'),
      );
    });

    test('token ceiling without token usage excludes every candidate', () async {
      final List<String> models = <String>[
        'gemini-2.5-flash-lite',
        'gemini-2.5-flash',
      ];
      final _FakeEvalSampler sampler = _FakeEvalSampler(
        exampleIds: <String>['c1', 'c2'],
        modelsWithoutTokens: models.toSet(),
      );
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{'model': models},
            maxTotalTokens: 1000,
          );
      final List<String> warnings = <String>[];

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(
            config,
            onWarning: warnings.add,
          ).optimize(
            LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
            sampler,
          );

      expect(result.optimizedAgents, isEmpty);
      expect(
        warnings.join('\n'),
        contains('all 2 scored candidates failed feasibility thresholds'),
      );
    });

    test('param_grid rejects values that cannot be swept', () {
      final List<(Object, String)> cases = <(Object, String)>[
        (<String, Object?>{'model': 'gemini-2.5-pro'}, 'must be a list of values'),
        (<String, Object?>{'model': <Object?>[]}, 'has no values'),
        (<String, Object?>{}, 'empty grid'),
        (<Object?>[], 'no sub-grids'),
        (
          <Map<String, Object?>>[
            <String, Object?>{
              'model': <Object?>['gemini-2.5-pro'],
            },
            <String, Object?>{},
          ],
          'empty grid',
        ),
      ];

      for (final (Object badGrid, String message) in cases) {
        expect(
          () => GridSearchAgentOptimizerConfig(paramGrid: badGrid),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '${e.message}',
              'message',
              contains(message),
            ),
          ),
        );
      }
    });

    test('quality_metric rejects efficiency metrics', () {
      for (final Object qualityMetric in <Object>[
        'token_usage_v1',
        <String, double>{'quality': 1.0, 'tool_call_count_v1': 0.1},
      ]) {
        expect(
          () => GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash'],
            },
            qualityMetric: qualityMetric,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '${e.message}',
              'message',
              contains('efficiency metrics'),
            ),
          ),
        );
      }
    });

    test('quality_metric rejects invalid weights', () {
      for (final double weight in <double>[
        -1.0,
        double.nan,
        double.infinity,
      ]) {
        expect(
          () => GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash'],
            },
            qualityMetric: <String, double>{'quality': 1.0, 'penalty': weight},
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '${e.message}',
              'message',
              contains('invalid weights'),
            ),
          ),
        );
      }
    });

    test('unscored examples count as zero quality', () async {
      final _ScriptedSampler sampler = _ScriptedSampler(
        (String model, String uid) {
          if (model == 'gemini-2.5-flash-lite' && uid != 'c1') {
            return null;
          }
          final double score = model == 'gemini-2.5-flash-lite' ? 1.0 : 0.8;
          return <Map<String, Object?>>[_metric('judge', score)];
        },
        trainIds: <String>['c1', 'c2', 'c3', 'c4'],
      );
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash', 'gemini-2.5-flash-lite'],
            },
            qualityMetric: 'judge',
          );
      final List<String> warnings = <String>[];

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(
            config,
            onWarning: warnings.add,
          ).optimize(
            LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
            sampler,
          );

      expect(_modelsOnFront(result), <String>['gemini-2.5-flash']);
      expect(result.optimizedAgents[0].overallScore, closeTo(0.8, 1e-9));
      expect(
        warnings.join('\n'),
        contains('1 of 2 candidates could not be scored on every example'),
      );
    });

    test('quality_metric without a score does not stop the search', () async {
      final _ScriptedSampler sampler = _ScriptedSampler((String model, String uid) {
        final double? judge = model == 'gemini-2.5-flash' ? 0.9 : null;
        return <Map<String, Object?>>[
          _metric('judge', judge),
          _metric('tool_call_count_v1', 1.0),
        ];
      });
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash', 'gemini-2.5-flash-lite'],
            },
            qualityMetric: 'judge',
          );
      final List<String> warnings = <String>[];

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(
            config,
            onWarning: warnings.add,
          ).optimize(
            LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
            sampler,
          );

      expect(_modelsOnFront(result), <String>['gemini-2.5-flash']);
      expect(
        warnings.join('\n'),
        contains('1 of 2 candidates produced no scored examples'),
      );
    });

    test('non-finite metric values count as unreported', () async {
      final Map<String, List<double>> resultsByModel = <String, List<double>>{
        'gemini-2.5-flash': <double>[0.9, 1.0, 100.0],
        'nan-tokens': <double>[0.8, 0.5, double.nan],
        'nan-latency': <double>[0.95, double.nan, 50.0],
        'nan-quality': <double>[double.nan, 0.5, 50.0],
      };
      final _ScriptedSampler sampler = _ScriptedSampler((String model, String uid) {
        final List<double> values = resultsByModel[model]!;
        return <Map<String, Object?>>[
          _metric('quality', values[0]),
          _metric('invocation_duration_v1', values[1]),
          _metric('token_usage_v1', values[2]),
        ];
      });
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': resultsByModel.keys.toList(),
            },
            qualityMetric: 'quality',
            minQualityScore: 0.5,
            maxLatencySec: 2.0,
            maxTotalTokens: 1000,
          );

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(config).optimize(
            LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
            sampler,
          );

      expect(_modelsOnFront(result), <String>['gemini-2.5-flash']);
    });

    test('unreported latency fails max_latency_sec', () async {
      final _ScriptedSampler sampler = _ScriptedSampler((String model, String uid) {
        if (model == 'gemini-2.5-flash') {
          return <Map<String, Object?>>[
            _metric('quality', 0.9),
            _metric('invocation_duration_v1', 1.0),
          ];
        }
        return <Map<String, Object?>>[_metric('quality', 0.95)];
      });
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash', 'gemini-2.5-flash-lite'],
            },
            qualityMetric: 'quality',
            maxLatencySec: 5.0,
          );

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(config).optimize(
            LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
            sampler,
          );

      expect(_modelsOnFront(result), <String>['gemini-2.5-flash']);
    });

    test('max_concurrent_candidates bounds in-flight evaluations', () async {
      final _ScriptedSampler sampler = _ScriptedSampler(
        (String model, String uid) => <Map<String, Object?>>[
          _metric('quality', 1.0),
        ],
        delay: const Duration(milliseconds: 15),
      );
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'generate_content_config.temperature': <Object?>[
                0.0,
                0.1,
                0.2,
                0.3,
              ],
            },
            maxConcurrentCandidates: 2,
          );

      await GridSearchAgentOptimizer(config).optimize(
        LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
        sampler,
      );

      expect(sampler.calls, hasLength(4));
      expect(sampler.peakInFlight, 2);
    });

    test('failing candidate stops the remaining evaluations', () async {
      final _FailingScriptedSampler sampler = _FailingScriptedSampler(
        (String model, String uid) => <Map<String, Object?>>[
          _metric('quality', 1.0),
        ],
      );
      final List<String> models = <String>[
        'gemini-2.5-pro',
        for (int i = 0; i < 4; i += 1) 'gemini-2.5-flash-$i',
      ];
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{'model': models},
            maxConcurrentCandidates: 1,
          );

      await expectLater(
        () => GridSearchAgentOptimizer(config).optimize(
          LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
          sampler,
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('RESOURCE_EXHAUSTED'),
          ),
        ),
      );
      expect(sampler.calls.length, lessThanOrEqualTo(1));
    });

    test('empty example_set falls back to other split with warning', () async {
      final List<(ExampleSet, List<String>, List<String>, ExampleSet, List<String>)>
      cases =
          <(ExampleSet, List<String>, List<String>, ExampleSet, List<String>)>[
            (
              ExampleSet.train,
              <String>[],
              <String>['v1', 'v2'],
              ExampleSet.validation,
              <String>['v1', 'v2'],
            ),
            (
              ExampleSet.validation,
              <String>['t1', 't2'],
              <String>[],
              ExampleSet.train,
              <String>['t1', 't2'],
            ),
          ];

      for (final (
            ExampleSet requested,
            List<String> trainIds,
            List<String> validationIds,
            ExampleSet expectedSet,
            List<String> ids,
          )
          in cases) {
        final _ScriptedSampler sampler = _ScriptedSampler(
          (String model, String uid) => <Map<String, Object?>>[
            _metric('quality', 1.0),
          ],
          trainIds: trainIds,
          validationIds: validationIds,
        );
        final GridSearchAgentOptimizerConfig config =
            GridSearchAgentOptimizerConfig(
              paramGrid: <String, List<Object?>>{
                'model': <Object?>['gemini-2.5-flash'],
              },
              exampleSet: requested,
            );
        final List<String> warnings = <String>[];

        await GridSearchAgentOptimizer(
          config,
          onWarning: warnings.add,
        ).optimize(
          LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
          sampler,
        );

        expect(sampler.calls, hasLength(1));
        expect(sampler.calls.single.$1, 'gemini-2.5-flash');
        expect(sampler.calls.single.$2, expectedSet);
        expect(sampler.calls.single.$3, ids);
        expect(
          warnings.join('\n'),
          contains(
            'sampler has no ${requested.name} examples; falling back to 2 '
            '${expectedSet.name} examples.',
          ),
        );
      }
    });

    test('duplicate example IDs are scored once', () async {
      final _ScriptedSampler sampler = _ScriptedSampler(
        (String model, String uid) => <Map<String, Object?>>[
          _metric('quality', 1.0),
        ],
        trainIds: <String>['a', 'a', 'b'],
      );
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash'],
            },
          );

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(config).optimize(
            LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
            sampler,
          );

      expect(sampler.calls[0].$3, <String>['a', 'b']);
      expect(result.optimizedAgents[0].metadata['num_cases_evaluated'], 2);
    });

    test(
      'partial failure does not win Pareto on tokens or latency',
      () async {
        final _ScriptedSampler sampler = _ScriptedSampler(
          (String model, String uid) {
            if (model == 'gemini-2.5-flash-lite' && uid != 'easy') {
              return null;
            }
            final double tokens = uid == 'easy' ? 50.0 : 950.0;
            final double latency = uid == 'easy' ? 0.2 : 3.8;
            final double quality =
                model == 'gemini-2.5-flash-lite' ? 0.8 : 0.9;
            return <Map<String, Object?>>[
              _metric('judge', quality),
              _metric('token_usage_v1', tokens),
              _metric('invocation_duration_v1', latency),
            ];
          },
          trainIds: <String>['easy', 'hard'],
        );
        final GridSearchAgentOptimizerConfig config =
            GridSearchAgentOptimizerConfig(
              paramGrid: <String, List<Object?>>{
                'model': <Object?>['gemini-2.5-flash', 'gemini-2.5-flash-lite'],
              },
              qualityMetric: 'judge',
            );

        final OptimizerResult<GridSearchAgentWithScores> result =
            await GridSearchAgentOptimizer(config).optimize(
              LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
              sampler,
            );

        expect(_modelsOnFront(result), <String>['gemini-2.5-flash']);
      },
    );

    test('real LocalEvalSampler ranks metrics and warns on strict threshold', () async {
      final InMemoryEvalSetsManager manager = InMemoryEvalSetsManager();
      await manager.createEvalSet('test_app', 'train_set');
      for (final String id in <String>['t1', 't2']) {
        await manager.addEvalCase(
          'test_app',
          'train_set',
          EvalCase(
            evalId: id,
            conversation: <Invocation>[
              Invocation(
                userContent: <String, Object?>{
                  'role': 'user',
                  'parts': <Object?>[
                    <String, Object?>{'text': 'hi'},
                  ],
                },
                finalResponse: <String, Object?>{
                  'role': 'model',
                  'parts': <Object?>[
                    <String, Object?>{'text': 'ok from gemini-2.5-pro'},
                  ],
                },
              ),
            ],
          ),
        );
      }

      final LocalEvalSampler sampler = await LocalEvalSampler.create(
        config: LocalEvalSamplerConfig(
          evalConfig: EvalConfig(
            criteria: <String, Object?>{
              'response_match_score': 0.5,
            },
          ),
          appName: 'test_app',
          trainEvalSet: 'train_set',
          trainEvalCaseIds: <String>['t1', 't2'],
        ),
        evalSetsManager: manager,
      );

      final List<BaseLlm> models = <BaseLlm>[
        _EchoModel('gemini-2.5-pro'),
        _EchoModel('gemini-2.5-flash'),
      ];
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{'model': models},
          );
      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(config).optimize(
            LlmAgent(name: 'Worker', model: _EchoModel('gemini-2.5-flash')),
            sampler,
          );

      expect(result.optimizedAgents, hasLength(1));
      expect(
        ((result.optimizedAgents[0].optimizedAgent as LlmAgent).model as BaseLlm)
            .model,
        'gemini-2.5-pro',
      );
      expect(result.optimizedAgents[0].overallScore, closeTo(1.0, 1e-9));

      final List<String> warnings = <String>[];
      final GridSearchAgentOptimizerConfig strictConfig =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{'model': models},
            minQualityScore: 1.5,
          );
      final OptimizerResult<GridSearchAgentWithScores> empty =
          await GridSearchAgentOptimizer(
            strictConfig,
            onWarning: warnings.add,
          ).optimize(
            LlmAgent(name: 'Worker', model: _EchoModel('gemini-2.5-flash')),
            sampler,
          );
      expect(empty.optimizedAgents, isEmpty);
      expect(
        warnings.join('\n'),
        contains('all 2 scored candidates failed feasibility thresholds'),
      );
    });

    test('unscored judge metric skips overall_score fallback', () async {
      for (final Object? qualityMetric in <Object?>[
        null,
        const <String, double>{},
      ]) {
        final _ScriptedSampler sampler = _ScriptedSampler(
          (String model, String uid) {
            if (model == 'all-unscored') {
              return <Map<String, Object?>>[
                _metric('final_response_match_v2', null),
                _metric('token_usage_v1', 50.0),
                _metric('invocation_duration_v1', 0.1),
              ];
            }
            if (model == 'half-unscored' && uid == 'c2') {
              return <Map<String, Object?>>[
                _metric('final_response_match_v2', null),
                _metric('token_usage_v1', 200.0),
                _metric('invocation_duration_v1', 0.4),
              ];
            }
            final double score = model == 'half-unscored' ? 0.8 : 0.9;
            final double tokens = model == 'half-unscored' ? 200.0 : 500.0;
            final double latency = model == 'half-unscored' ? 0.4 : 1.0;
            return <Map<String, Object?>>[
              _metric('final_response_match_v2', score),
              _metric('token_usage_v1', tokens),
              _metric('invocation_duration_v1', latency),
            ];
          },
          trainIds: <String>['c1', 'c2'],
        );
        final GridSearchAgentOptimizerConfig config =
            GridSearchAgentOptimizerConfig(
              paramGrid: <String, List<Object?>>{
                'model': <Object?>[
                  'gemini-2.5-pro',
                  'half-unscored',
                  'all-unscored',
                ],
              },
              qualityMetric: qualityMetric,
            );
        final List<String> warnings = <String>[];

        final OptimizerResult<GridSearchAgentWithScores> result =
            await GridSearchAgentOptimizer(
              config,
              onWarning: warnings.add,
            ).optimize(
              LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
              sampler,
            );

        expect(_modelsOnFront(result), <String>[
          'gemini-2.5-pro',
          'half-unscored',
        ]);
        final GridSearchAgentWithScores partial = result.optimizedAgents[1];
        expect(partial.overallScore, closeTo(0.4, 1e-9));
        expect(partial.evalCaseScores['c1'], closeTo(0.8, 1e-9));
        expect(partial.evalCaseScores.containsKey('c2'), isFalse);
        expect(partial.metadata['num_cases_evaluated'], 1);
        expect(
          warnings.join('\n'),
          allOf(
            contains('1 of 3 candidates produced no scored examples'),
            contains('1 of 3 candidates could not be scored on every example'),
          ),
        );
      }
    });

    test('multi-turn sums tokens and zero-fills partial optionals', () async {
      final Map<String, List<Map<String, Object?>>> cases =
          <String, List<Map<String, Object?>>>{
            'c1': <Map<String, Object?>>[
              <String, Object?>{
                'eval_metric_results': <Map<String, Object?>>[
                  _metric('turn_quality', 0.6),
                  _metric('rubric', null),
                  _metric('invocation_duration_v1', 1.0),
                  _detailedTokenMetric(800.0, 200.0, cachedTokens: null),
                ],
              },
              <String, Object?>{
                'eval_metric_results': <Map<String, Object?>>[
                  _metric('turn_quality', 1.0),
                  _metric('rubric', 0.9),
                  _metric('invocation_duration_v1', 2.0),
                  _detailedTokenMetric(1000.0, 200.0, cachedTokens: 600.0),
                ],
              },
            ],
            'c2': <Map<String, Object?>>[
              <String, Object?>{
                'eval_metric_results': <Map<String, Object?>>[
                  _metric('turn_quality', 0.5),
                  _metric('rubric', 0.5),
                  _metric('invocation_duration_v1', 0.5),
                  _detailedTokenMetric(400.0, 100.0, cachedTokens: null),
                ],
              },
            ],
          };
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash'],
            },
          );

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(config).optimize(
            LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
            _MultiTurnSampler(cases),
          );

      final GridSearchAgentWithScores winner = result.optimizedAgents[0];
      expect(winner.overallScore, closeTo(0.675, 1e-9));
      expect(winner.latencySec, closeTo(1.0, 1e-9));
      expect(winner.tokenUsage, <String, double>{
        'total_tokens': 1350.0,
        'input_tokens': 1100.0,
        'output_tokens': 250.0,
        'cached_tokens': 300.0,
      });
      expect(winner.tokenUsage.containsKey('reasoning_tokens'), isFalse);
    });

    test('multi-turn missing token turn clears candidate tokens', () async {
      final Map<String, List<Map<String, Object?>>> cases =
          <String, List<Map<String, Object?>>>{
            'c1': <Map<String, Object?>>[
              <String, Object?>{
                'eval_metric_results': <Map<String, Object?>>[
                  _metric('quality', 0.8),
                  _metric('invocation_duration_v1', 1.0),
                  _metric('token_usage_v1', 400.0),
                ],
              },
              <String, Object?>{
                'eval_metric_results': <Map<String, Object?>>[
                  _metric('quality', 1.0),
                  _metric('invocation_duration_v1', 2.0),
                ],
              },
            ],
          };
      final GridSearchAgentOptimizerConfig config =
          GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash'],
            },
          );
      final List<String> warnings = <String>[];

      final OptimizerResult<GridSearchAgentWithScores> result =
          await GridSearchAgentOptimizer(
            config,
            onWarning: warnings.add,
          ).optimize(
            LlmAgent(name: 'Worker', model: 'gemini-2.5-flash'),
            _MultiTurnSampler(cases),
          );

      final GridSearchAgentWithScores winner = result.optimizedAgents[0];
      expect(winner.overallScore, closeTo(0.9, 1e-9));
      expect(winner.latencySec, closeTo(1.5, 1e-9));
      expect(winner.tokenUsage, isEmpty);
      expect(warnings.join('\n'), contains('reported no token usage'));
    });

    test('non-finite feasibility thresholds are rejected', () {
      for (final double badValue in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash'],
            },
            minQualityScore: badValue,
          ),
          throwsArgumentError,
        );
        expect(
          () => GridSearchAgentOptimizerConfig(
            paramGrid: <String, List<Object?>>{
              'model': <Object?>['gemini-2.5-flash'],
            },
            maxLatencySec: badValue,
          ),
          throwsArgumentError,
        );
      }
    });
  });
}
