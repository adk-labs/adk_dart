part of 'cli.dart';

/// CLI selection target for one eval source and optional case ids.
class _EvalSelection {
  /// Creates an eval selection descriptor.
  _EvalSelection({required this.source, required this.evalCaseIds});

  /// Eval set id or file path.
  final String source;

  /// Selected eval case ids within [source].
  final Set<String> evalCaseIds;
}

/// Resolved eval target after loading/expanding selections.
class _EvalTarget {
  /// Creates a resolved eval target.
  _EvalTarget({required this.evalSetId, required this.evalCaseIds});

  /// Eval set identifier.
  final String evalSetId;

  /// Selected eval case ids within [evalSetId].
  final Set<String> evalCaseIds;
}

/// Parsed arguments for `adk eval`.
class _ParsedEvalCliCommand {
  /// Creates parsed `eval` command arguments.
  _ParsedEvalCliCommand({
    required this.agentPath,
    required this.selections,
    this.configFilePath,
    required this.printDetailedResults,
    this.evalStorageUri,
    this.logLevel,
    this.numRuns,
    this.parallelism,
    this.enableFeatures = const <String>[],
    this.disableFeatures = const <String>[],
  });

  /// Agent directory path.
  final String agentPath;

  /// Eval source selections to run.
  final List<_EvalSelection> selections;

  /// Optional eval config file path.
  final String? configFilePath;

  /// Whether to print detailed per-case output.
  final bool printDetailedResults;

  /// Optional eval storage backend URI.
  final String? evalStorageUri;

  /// Optional log verbosity level.
  final String? logLevel;

  /// Optional number of times to run each eval case.
  final int? numRuns;

  /// Optional maximum number of eval cases to run in parallel.
  final int? parallelism;

  /// Feature flags forced to enabled.
  final List<String> enableFeatures;

  /// Feature flags forced to disabled.
  final List<String> disableFeatures;
}

/// Parsed arguments for `adk optimize`.
class _ParsedOptimizeCliCommand {
  /// Creates parsed `optimize` command arguments.
  _ParsedOptimizeCliCommand({
    required this.agentPath,
    required this.samplerConfigFilePath,
    this.optimizerConfigFilePath,
    required this.printDetailedResults,
    required this.logLevel,
    this.enableFeatures = const <String>[],
    this.disableFeatures = const <String>[],
  });

  /// Agent directory path.
  final String agentPath;

  /// Local eval sampler config file path.
  final String samplerConfigFilePath;

  /// Optional GEPA optimizer config file path.
  final String? optimizerConfigFilePath;

  /// Whether to print detailed optimizer output.
  final bool printDetailedResults;

  /// Log level applied while optimizing.
  final String logLevel;

  /// Feature flags forced to enabled.
  final List<String> enableFeatures;

  /// Feature flags forced to disabled.
  final List<String> disableFeatures;
}

/// Parsed arguments for `adk eval_set create`.
class _ParsedEvalSetCreateCommand {
  /// Creates parsed `eval_set create` command arguments.
  _ParsedEvalSetCreateCommand({
    required this.agentPath,
    required this.evalSetId,
    this.evalStorageUri,
    this.logLevel,
  });

  /// Agent directory path.
  final String agentPath;

  /// New eval set identifier.
  final String evalSetId;

  /// Optional eval storage backend URI.
  final String? evalStorageUri;

  /// Optional log verbosity level.
  final String? logLevel;
}

/// Parsed arguments for `adk eval_set add_eval_case`.
class _ParsedEvalSetAddEvalCaseCommand {
  /// Creates parsed `eval_set add_eval_case` command arguments.
  _ParsedEvalSetAddEvalCaseCommand({
    required this.agentPath,
    required this.evalSetId,
    required this.scenariosFilePath,
    required this.sessionInputFilePath,
    this.evalStorageUri,
    this.logLevel,
  });

  /// Agent directory path.
  final String agentPath;

  /// Target eval set identifier.
  final String evalSetId;

  /// Scenario definitions input file path.
  final String scenariosFilePath;

  /// Session input transcript file path.
  final String sessionInputFilePath;

  /// Optional eval storage backend URI.
  final String? evalStorageUri;

  /// Optional log verbosity level.
  final String? logLevel;
}

/// Parsed arguments for `adk eval_set generate_eval_cases`.
class _ParsedEvalSetGenerateEvalCasesCommand {
  /// Creates parsed `eval_set generate_eval_cases` command arguments.
  _ParsedEvalSetGenerateEvalCasesCommand({
    required this.agentPath,
    required this.evalSetId,
    required this.conversationGenerationConfigFilePath,
    required this.sessionInputFilePath,
    this.repeatNum = 1,
    this.evalStorageUri,
    this.logLevel,
  });

  /// Agent directory path.
  final String agentPath;

  /// Target eval set identifier.
  final String evalSetId;

  /// Conversation generation config file path.
  final String conversationGenerationConfigFilePath;

  /// Session input file path.
  final String sessionInputFilePath;

  /// Number of times to repeat generation.
  final int repeatNum;

  /// Optional eval storage backend URI.
  final String? evalStorageUri;

  /// Optional log verbosity level.
  final String? logLevel;
}

class _ConversationGenerationConfig {
  _ConversationGenerationConfig({
    required this.count,
    required this.generationPrompt,
    required this.scenarios,
    this.startingPrompt,
  });

  final int count;
  final String generationPrompt;
  final List<String> scenarios;
  final String? startingPrompt;

  factory _ConversationGenerationConfig.fromJson(Map<String, Object?> json) {
    final Object? rawCount = json['count'] ?? json['num_scenarios'];
    final int count = rawCount is int && rawCount > 0 ? rawCount : 1;
    final String generationPrompt =
        '${json['generation_prompt'] ?? json['generationPrompt'] ?? json['conversation_plan'] ?? ''}'
            .trim();
    final String? startingPrompt = _emptyToNull(
      '${json['starting_prompt'] ?? json['startingPrompt'] ?? ''}',
    );
    final List<String> scenarios = <String>[];
    final Object? rawScenarios = json['scenarios'];
    if (rawScenarios is List) {
      for (final Object? item in rawScenarios) {
        if (item is String && item.trim().isNotEmpty) {
          scenarios.add(item.trim());
        } else if (item is Map && item['conversation_plan'] != null) {
          scenarios.add('${item['conversation_plan']}'.trim());
        }
      }
    }
    return _ConversationGenerationConfig(
      count: count,
      generationPrompt: generationPrompt,
      scenarios: scenarios,
      startingPrompt: startingPrompt,
    );
  }
}

/// Helper container for eval set/result manager dependencies.
class _EvalManagers {
  /// Creates eval manager dependencies.
  _EvalManagers({
    required this.evalSetsManager,
    required this.evalSetResultsManager,
  });

  /// Eval set CRUD manager.
  final EvalSetsManager evalSetsManager;

  /// Eval result persistence manager.
  final EvalSetResultsManager evalSetResultsManager;
}

/// Loaded CLI agent bundle with path metadata.
class _LoadedCliAgent {
  /// Creates a loaded agent bundle.
  _LoadedCliAgent({
    required this.rootAgent,
    required this.appName,
    required this.agentsParentDirPath,
  });

  /// Root agent instance.
  final BaseAgent rootAgent;

  /// Logical app name used by runner/session services.
  final String appName;

  /// Parent directory containing loadable agents.
  final String agentsParentDirPath;
}


Future<int> _runEvalCliCommand(
  List<String> args, {
  required IOSink out,
  IOSink? err,
}) async {
  final _ParsedEvalCliCommand command = _parseEvalCliCommand(args);
  if (command.logLevel != null) {
    cli_logs.setupAdkLogger(level: _toCliLogEnum(command.logLevel!));
  }
  _applyFeatureOverridesFromCli(
    enableFeatures: command.enableFeatures,
    disableFeatures: command.disableFeatures,
    err: err ?? stderr,
  );
  final _LoadedCliAgent loadedAgent = await _loadAgentForCli(command.agentPath);

  final bool usesFileTargets = _usesEvalSetFileTargets(command.selections);
  final _EvalManagers managers = _createEvalManagers(
    evalStorageUri: command.evalStorageUri,
    agentsDir: loadedAgent.agentsParentDirPath,
    useInMemory: usesFileTargets,
  );
  final List<_EvalTarget> evalTargets = await _resolveEvalTargets(
    command: command,
    appName: loadedAgent.appName,
    evalSetsManager: managers.evalSetsManager,
    usesFileTargets: usesFileTargets,
  );

  String? effectiveConfigFilePath = command.configFilePath;
  if (effectiveConfigFilePath == null &&
      usesFileTargets &&
      command.selections.isNotEmpty) {
    final File firstEvalSetFile = File(command.selections.first.source).absolute;
    final File defaultConfigFile = File(
      '${firstEvalSetFile.parent.path}${Platform.pathSeparator}test_config.json',
    );
    if (defaultConfigFile.existsSync()) {
      effectiveConfigFilePath = defaultConfigFile.path;
    }
  }

  final EvalConfig evalConfig = cli_eval.getEvaluationCriteriaOrDefault(
    effectiveConfigFilePath,
  );
  cli_eval.loadAggregationMethods(evalConfig.multiRunConfig);
  final int resolvedNumRuns =
      command.numRuns ?? evalConfig.multiRunConfig?.numRuns ?? 1;
  cli_eval.checkPassKCriteriaAgainstNumRuns(
    evalConfig.multiRunConfig,
    resolvedNumRuns,
  );
  final int? resolvedParallelism = command.parallelism ?? evalConfig.parallelism;

  final List<EvalCaseResult> allResults = <EvalCaseResult>[];
  for (final _EvalTarget target in evalTargets) {
    final EvalSet? evalSet = await managers.evalSetsManager.getEvalSet(
      loadedAgent.appName,
      target.evalSetId,
    );
    if (evalSet == null) {
      throw StateError('Eval set `${target.evalSetId}` not found.');
    }

    final List<EvalCase> selectedCases = target.evalCaseIds.isEmpty
        ? List<EvalCase>.from(evalSet.evalCases)
        : evalSet.evalCases
              .where(
                (EvalCase item) => target.evalCaseIds.contains(item.evalId),
              )
              .toList(growable: false);
    if (selectedCases.isEmpty) {
      throw StateError('No matching eval IDs found in `${target.evalSetId}`.');
    }

    allResults.addAll(
      await _evaluateEvalSet(
        rootAgent: loadedAgent.rootAgent,
        appName: loadedAgent.appName,
        evalSetId: target.evalSetId,
        evalCases: selectedCases,
        evalSetResultsManager: managers.evalSetResultsManager,
        configFilePath: effectiveConfigFilePath,
        evalConfig: evalConfig,
        numRuns: resolvedNumRuns,
        parallelism: resolvedParallelism,
      ),
    );
  }

  final List<cli_eval.MultiRunCaseResult> aggregateEvalResults =
      cli_eval.aggregateEvalCaseResults(
        allResults,
        multiRunConfig: evalConfig.multiRunConfig,
      );

  final Map<String, (int passed, int failed)> summaryByEvalSet =
      <String, (int, int)>{};
  for (final cli_eval.MultiRunCaseResult result in aggregateEvalResults) {
    final (int passed, int failed) current =
        summaryByEvalSet[result.evalSetId] ?? (0, 0);
    if (result.finalEvalStatus == EvalStatus.passed) {
      summaryByEvalSet[result.evalSetId] = (current.$1 + 1, current.$2);
    } else {
      summaryByEvalSet[result.evalSetId] = (current.$1, current.$2 + 1);
    }
  }

  out.writeln('Eval Run Summary');
  if (resolvedNumRuns > 1) {
    out.writeln(
      'Each eval case was run $resolvedNumRuns times and judged on all $resolvedNumRuns runs.',
    );
  }
  final List<String> evalSetIds = summaryByEvalSet.keys.toList(growable: false)
    ..sort();
  for (final String evalSetId in evalSetIds) {
    final (int passed, int failed) counts = summaryByEvalSet[evalSetId]!;
    out.writeln(
      '$evalSetId:\n  Tests passed: ${counts.$1}\n  Tests failed: ${counts.$2}',
    );
  }

  if (command.printDetailedResults) {
    if (resolvedNumRuns > 1 ||
        cli_eval.hasPassCountRules(evalConfig.multiRunConfig)) {
      out.writeln(
        cli_eval.prettyPrintEvalResultsAcrossRuns(
          aggregateEvalResults,
          numRuns: resolvedNumRuns,
        ),
      );
    } else {
      for (final EvalCaseResult result in allResults) {
        out.writeln(
          '*********************************************************************',
        );
        out.writeln(cli_eval.prettyPrintEvalResult(result));
      }
    }
  }

  final int totalFailed = summaryByEvalSet.values.fold<int>(
    0,
    (int sum, (int, int) counts) => sum + counts.$2,
  );
  return (totalFailed > 0 || summaryByEvalSet.isEmpty) ? 1 : 0;
}

Future<int> _runOptimizeCliCommand(
  List<String> args, {
  required IOSink out,
  IOSink? err,
}) async {
  final _ParsedOptimizeCliCommand command = _parseOptimizeCliCommand(args);
  cli_logs.setupAdkLogger(level: _toCliLogEnum(command.logLevel));
  _applyFeatureOverridesFromCli(
    enableFeatures: command.enableFeatures,
    disableFeatures: command.disableFeatures,
    err: err ?? stderr,
  );

  final _LoadedCliAgent loadedAgent = await _loadAgentForCli(command.agentPath);
  final LocalEvalSamplerConfig samplerConfig = LocalEvalSamplerConfig.fromJson(
    await _readJsonObjectFile(
      command.samplerConfigFilePath,
      label: 'sampler config file',
    ),
  );
  if (samplerConfig.appName != loadedAgent.appName) {
    throw CliUsageError(
      'App name in the agent path (${loadedAgent.appName}) does not match '
      'the app name in the sampler config file (${samplerConfig.appName}).',
    );
  }

  final GepaRootAgentPromptOptimizerConfig optimizerConfig =
      command.optimizerConfigFilePath == null
      ? GepaRootAgentPromptOptimizerConfig()
      : GepaRootAgentPromptOptimizerConfig.fromJson(
          await _readJsonObjectFile(
            command.optimizerConfigFilePath!,
            label: 'optimizer config file',
          ),
        );

  final _EvalManagers managers = _createEvalManagers(
    evalStorageUri: null,
    agentsDir: loadedAgent.agentsParentDirPath,
    useInMemory: false,
  );
  final LocalEvalSampler sampler = await LocalEvalSampler.create(
    config: samplerConfig,
    evalSetsManager: managers.evalSetsManager,
  );
  final GepaRootAgentPromptOptimizer optimizer = GepaRootAgentPromptOptimizer(
    optimizerConfig,
  );
  final GepaRootAgentPromptOptimizerResult result = await optimizer.optimize(
    loadedAgent.rootAgent as Agent,
    sampler,
  );
  _printOptimizationResults(result, command: command, out: out);
  return 0;
}

void _printOptimizationResults(
  GepaRootAgentPromptOptimizerResult result, {
  required _ParsedOptimizeCliCommand command,
  required IOSink out,
}) {
  final int bestIdx = _bestOptimizedAgentIndex(result);

  out.writeln('=' * 80);
  out.writeln('Optimized root agent instructions:');
  out.writeln('-' * 80);
  out.writeln(result.optimizedAgents[bestIdx].optimizedAgent.instruction);

  if (command.printDetailedResults) {
    out.writeln('=' * 80);
    final Map<String, Object?>? gepaResult = result.gepaResult;
    if (gepaResult == null || gepaResult.isEmpty) {
      out.writeln('Detailed GEPA optimization metrics are not available.');
    } else {
      out.writeln('Detailed GEPA optimization metrics:');
      out.writeln('-' * 80);
      out.writeln(const JsonEncoder.withIndent('  ').convert(gepaResult));
    }
  }

  out.writeln('=' * 80);
}

Future<int> _runEvalSetCliCommand(
  List<String> args, {
  required IOSink out,
}) async {
  if (args.isEmpty) {
    throw CliUsageError(
      'Missing eval_set subcommand. Supported: create, add_eval_case, generate_eval_cases.',
    );
  }

  final String subcommand = args.first;
  final List<String> commandArgs = args.skip(1).toList(growable: false);
  switch (subcommand) {
    case 'create':
      final _ParsedEvalSetCreateCommand command = _parseEvalSetCreateCommand(
        commandArgs,
      );
      if (command.logLevel != null) {
        cli_logs.setupAdkLogger(level: _toCliLogEnum(command.logLevel!));
      }
      final Directory agentDir = Directory(command.agentPath).absolute;
      final String appName = projectDirName(agentDir.path);
      final _EvalManagers managers = _createEvalManagers(
        evalStorageUri: command.evalStorageUri,
        agentsDir: agentDir.parent.absolute.path,
        useInMemory: false,
      );
      await managers.evalSetsManager.createEvalSet(appName, command.evalSetId);
      out.writeln(
        "Eval set '${command.evalSetId}' created for app '$appName'.",
      );
      return 0;
    case 'add_eval_case':
      final _ParsedEvalSetAddEvalCaseCommand command =
          _parseEvalSetAddEvalCaseCommand(commandArgs);
      if (command.logLevel != null) {
        cli_logs.setupAdkLogger(level: _toCliLogEnum(command.logLevel!));
      }
      final Directory agentDir = Directory(command.agentPath).absolute;
      final String appName = projectDirName(agentDir.path);
      final _EvalManagers managers = _createEvalManagers(
        evalStorageUri: command.evalStorageUri,
        agentsDir: agentDir.parent.absolute.path,
        useInMemory: false,
      );
      final SessionInput sessionInput = SessionInput.fromJson(
        await _readJsonObjectFile(
          command.sessionInputFilePath,
          label: 'session input file',
        ),
      );
      final ConversationScenarios conversationScenarios =
          await _readConversationScenariosFile(command.scenariosFilePath);

      for (final ConversationScenario scenario
          in conversationScenarios.scenarios) {
        final String evalId = _stableScenarioId(scenario);
        final EvalCase? existing = await managers.evalSetsManager.getEvalCase(
          appName,
          command.evalSetId,
          evalId,
        );
        if (existing != null) {
          out.writeln(
            "Eval case '$evalId' already exists in eval set '${command.evalSetId}', skipped adding.",
          );
          continue;
        }

        await managers.evalSetsManager.addEvalCase(
          appName,
          command.evalSetId,
          EvalCase(
            evalId: evalId,
            conversationScenario: scenario,
            sessionInput: sessionInput,
            creationTimestamp: DateTime.now().millisecondsSinceEpoch / 1000,
          ),
        );
        out.writeln(
          "Eval case '$evalId' added to eval set '${command.evalSetId}'.",
        );
      }
      return 0;
    case 'generate_eval_cases':
      final _ParsedEvalSetGenerateEvalCasesCommand command =
          _parseEvalSetGenerateEvalCasesCommand(commandArgs);
      if (command.logLevel != null) {
        cli_logs.setupAdkLogger(level: _toCliLogEnum(command.logLevel!));
      }
      final Directory agentDir = Directory(command.agentPath).absolute;
      final String appName = projectDirName(agentDir.path);
      final _EvalManagers managers = _createEvalManagers(
        evalStorageUri: command.evalStorageUri,
        agentsDir: agentDir.parent.absolute.path,
        useInMemory: false,
      );
      final _ConversationGenerationConfig config =
          _ConversationGenerationConfig.fromJson(
            await _readJsonObjectFile(
              command.conversationGenerationConfigFilePath,
              label: 'conversation generation config file',
            ),
          );
      final SessionInput sessionInput = SessionInput.fromJson(
        await _readJsonObjectFile(
          command.sessionInputFilePath,
          label: 'session input file',
        ),
      );
      try {
        await managers.evalSetsManager.createEvalSet(
          appName,
          command.evalSetId,
        );
      } on ArgumentError {
        // Eval set already exists; proceed to add generated cases.
      }
      for (int r = 0; r < command.repeatNum; r += 1) {
        for (int i = 0; i < config.count; i += 1) {
          final String prompt = config.generationPrompt.isNotEmpty
              ? config.generationPrompt
              : (config.scenarios.isNotEmpty
                    ? config.scenarios[i % config.scenarios.length]
                    : 'Generate a realistic user conversation.');
          final ConversationScenario scenario = ConversationScenario(
            startingPrompt: config.startingPrompt ?? 'Hello!',
            conversationPlan: prompt,
          );
          final String evalId = _stableScenarioId(
            ConversationScenario(
              startingPrompt: '${scenario.startingPrompt}#$r#$i',
              conversationPlan: scenario.conversationPlan,
            ),
          );
          await managers.evalSetsManager.addEvalCase(
            appName,
            command.evalSetId,
            EvalCase(
              evalId: evalId,
              conversationScenario: scenario,
              sessionInput: sessionInput,
              creationTimestamp: DateTime.now().millisecondsSinceEpoch / 1000,
            ),
          );
          out.writeln(
            "Eval case '$evalId' added to eval set '${command.evalSetId}'.",
          );
        }
      }
      return 0;
    default:
      throw CliUsageError('Unknown eval_set subcommand: $subcommand');
  }
}

_ParsedEvalCliCommand _parseEvalCliCommand(List<String> args) {
  String? configFilePath;
  bool printDetailedResults = false;
  String? evalStorageUri;
  String? logLevel;
  int? numRuns;
  int? parallelism;
  bool verbose = false;
  final List<String> enableFeatures = <String>[];
  final List<String> disableFeatures = <String>[];
  final List<String> positionals = <String>[];

  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--config_file_path') {
      configFilePath = _nextArg(args, i, '--config_file_path');
      i += 1;
      continue;
    }
    if (arg.startsWith('--config_file_path=')) {
      configFilePath = arg.substring('--config_file_path='.length);
      continue;
    }
    if (arg == '--print_detailed_results') {
      printDetailedResults = true;
      continue;
    }
    if (arg == '--num_runs') {
      final String rawNumRuns = _nextArg(args, i, '--num_runs');
      final int? parsed = int.tryParse(rawNumRuns.trim());
      if (parsed == null || parsed < 1) {
        throw CliUsageError(
          "Invalid value for '--num_runs': $rawNumRuns is not in the range x>=1.",
        );
      }
      numRuns = parsed;
      i += 1;
      continue;
    }
    if (arg.startsWith('--num_runs=')) {
      final String rawNumRuns = arg.substring('--num_runs='.length);
      final int? parsed = int.tryParse(rawNumRuns.trim());
      if (parsed == null || parsed < 1) {
        throw CliUsageError(
          "Invalid value for '--num_runs': $rawNumRuns is not in the range x>=1.",
        );
      }
      numRuns = parsed;
      continue;
    }
    if (arg == '--parallelism') {
      final String rawParallelism = _nextArg(args, i, '--parallelism');
      final int? parsed = int.tryParse(rawParallelism.trim());
      if (parsed == null || parsed < 1) {
        throw CliUsageError(
          "Invalid value for '--parallelism': $rawParallelism is not in the range x>=1.",
        );
      }
      parallelism = parsed;
      i += 1;
      continue;
    }
    if (arg.startsWith('--parallelism=')) {
      final String rawParallelism = arg.substring('--parallelism='.length);
      final int? parsed = int.tryParse(rawParallelism.trim());
      if (parsed == null || parsed < 1) {
        throw CliUsageError(
          "Invalid value for '--parallelism': $rawParallelism is not in the range x>=1.",
        );
      }
      parallelism = parsed;
      continue;
    }
    if (arg == '--eval_storage_uri') {
      evalStorageUri = _nextArg(args, i, '--eval_storage_uri');
      i += 1;
      continue;
    }
    if (arg.startsWith('--eval_storage_uri=')) {
      evalStorageUri = arg.substring('--eval_storage_uri='.length);
      continue;
    }
    if (arg == '--log_level' || arg == '--verbosity') {
      logLevel = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--log_level=') || arg.startsWith('--verbosity=')) {
      logLevel = arg.substring(arg.indexOf('=') + 1);
      continue;
    }
    if (arg == '-v' || arg == '--verbose') {
      verbose = true;
      continue;
    }
    if (arg == '--enable_features') {
      enableFeatures.add(_nextArg(args, i, '--enable_features'));
      i += 1;
      continue;
    }
    if (arg.startsWith('--enable_features=')) {
      enableFeatures.add(arg.substring('--enable_features='.length));
      continue;
    }
    if (arg == '--disable_features') {
      disableFeatures.add(_nextArg(args, i, '--disable_features'));
      i += 1;
      continue;
    }
    if (arg.startsWith('--disable_features=')) {
      disableFeatures.add(arg.substring('--disable_features='.length));
      continue;
    }
    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for eval: $arg');
    }
    positionals.add(arg);
  }

  if (positionals.length < 2) {
    throw CliUsageError(
      'eval requires <project_dir> and at least one <eval_set_file_or_id>.',
    );
  }

  final List<_EvalSelection> selections = positionals
      .skip(1)
      .map(_parseEvalSelection)
      .toList(growable: false);
  final String? resolvedLogLevel = (logLevel != null || verbose)
      ? _resolveCliLogLevel(explicit: _emptyToNull(logLevel), verbose: verbose)
      : null;
  return _ParsedEvalCliCommand(
    agentPath: positionals.first,
    selections: selections,
    configFilePath: _emptyToNull(configFilePath),
    printDetailedResults: printDetailedResults,
    evalStorageUri: _emptyToNull(evalStorageUri),
    logLevel: resolvedLogLevel,
    numRuns: numRuns,
    parallelism: parallelism,
    enableFeatures: _normalizeCsvValues(enableFeatures),
    disableFeatures: _normalizeCsvValues(disableFeatures),
  );
}

_ParsedOptimizeCliCommand _parseOptimizeCliCommand(List<String> args) {
  String? samplerConfigFilePath;
  String? optimizerConfigFilePath;
  String? logLevel;
  bool verbose = false;
  bool printDetailedResults = false;
  final List<String> enableFeatures = <String>[];
  final List<String> disableFeatures = <String>[];
  final List<String> positionals = <String>[];

  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--sampler_config_file_path') {
      samplerConfigFilePath = _nextArg(args, i, '--sampler_config_file_path');
      i += 1;
      continue;
    }
    if (arg.startsWith('--sampler_config_file_path=')) {
      samplerConfigFilePath = arg.substring(
        '--sampler_config_file_path='.length,
      );
      continue;
    }
    if (arg == '--optimizer_config_file_path') {
      optimizerConfigFilePath = _nextArg(
        args,
        i,
        '--optimizer_config_file_path',
      );
      i += 1;
      continue;
    }
    if (arg.startsWith('--optimizer_config_file_path=')) {
      optimizerConfigFilePath = arg.substring(
        '--optimizer_config_file_path='.length,
      );
      continue;
    }
    if (arg == '--print_detailed_results') {
      printDetailedResults = true;
      continue;
    }
    if (arg == '--log_level' || arg == '--verbosity') {
      logLevel = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--log_level=') || arg.startsWith('--verbosity=')) {
      logLevel = arg.substring(arg.indexOf('=') + 1);
      continue;
    }
    if (arg == '-v' || arg == '--verbose') {
      verbose = true;
      continue;
    }
    if (arg == '--enable_features') {
      enableFeatures.add(_nextArg(args, i, '--enable_features'));
      i += 1;
      continue;
    }
    if (arg.startsWith('--enable_features=')) {
      enableFeatures.add(arg.substring('--enable_features='.length));
      continue;
    }
    if (arg == '--disable_features') {
      disableFeatures.add(_nextArg(args, i, '--disable_features'));
      i += 1;
      continue;
    }
    if (arg.startsWith('--disable_features=')) {
      disableFeatures.add(arg.substring('--disable_features='.length));
      continue;
    }
    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for optimize: $arg');
    }
    positionals.add(arg);
  }

  if (positionals.isEmpty) {
    throw CliUsageError('Missing optimize agent directory path.');
  }
  if (positionals.length > 1) {
    throw CliUsageError('optimize accepts only one agent directory path.');
  }
  if (_emptyToNull(samplerConfigFilePath) == null) {
    throw CliUsageError('Missing required option --sampler_config_file_path.');
  }

  return _ParsedOptimizeCliCommand(
    agentPath: positionals.single,
    samplerConfigFilePath: samplerConfigFilePath!.trim(),
    optimizerConfigFilePath: _emptyToNull(optimizerConfigFilePath),
    printDetailedResults: printDetailedResults,
    logLevel: _resolveCliLogLevel(
      explicit: _emptyToNull(logLevel),
      verbose: verbose,
    ),
    enableFeatures: _normalizeCsvValues(enableFeatures),
    disableFeatures: _normalizeCsvValues(disableFeatures),
  );
}

_EvalSelection _parseEvalSelection(String rawValue) {
  final String value = rawValue.trim();
  if (value.isEmpty) {
    throw CliUsageError('Empty eval set target is not allowed.');
  }
  final int colonIndex = value.indexOf(':');
  if (colonIndex <= 0 || colonIndex >= value.length - 1) {
    return _EvalSelection(source: value, evalCaseIds: <String>{});
  }
  // Treat Windows drive roots like C:\path as plain file paths.
  if (colonIndex == 1 && RegExp(r'^[A-Za-z]$').hasMatch(value[0])) {
    return _EvalSelection(source: value, evalCaseIds: <String>{});
  }

  final String source = value.substring(0, colonIndex).trim();
  final String idsPart = value.substring(colonIndex + 1).trim();
  final Set<String> ids = idsPart
      .split(',')
      .map((String item) => item.trim())
      .where((String item) => item.isNotEmpty)
      .toSet();
  return _EvalSelection(source: source, evalCaseIds: ids);
}

bool _usesEvalSetFileTargets(List<_EvalSelection> selections) {
  bool? usingFiles;
  for (final _EvalSelection selection in selections) {
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      selection.source,
    );
    final bool isExistingPath = type != FileSystemEntityType.notFound;
    if (usingFiles == null) {
      usingFiles = isExistingPath;
      continue;
    }
    if (usingFiles != isExistingPath) {
      throw CliUsageError(
        'Mixing eval set file paths with eval set ids is not supported.',
      );
    }
  }
  return usingFiles ?? false;
}

String? _resolveEvalStorageUri(
  String? evalStorageUri, {
  Map<String, String>? environment,
}) {
  final String? explicit = _emptyToNull(evalStorageUri);
  if (explicit != null) {
    return explicit;
  }
  return _emptyToNull(
    (environment ?? Platform.environment)['ADK_EVAL_STORAGE_URI'],
  );
}

String _localEvalDirFromUri(String evalStorageUri) {
  final Uri parsed = Uri.parse(evalStorageUri);
  if (parsed.scheme != 'file') {
    throw ArgumentError(
      'Unsupported evals storage URI: $evalStorageUri. Supported URIs: '
      'gs://<bucket name>, file://<path>',
    );
  }
  final String authority = parsed.authority.toLowerCase();
  if (authority.isNotEmpty && authority != 'localhost') {
    throw ArgumentError(
      'Invalid evals storage URI: $evalStorageUri. file:// URIs must '
      'target the local host, e.g. file:///abs/path',
    );
  }
  final String afterScheme = evalStorageUri.substring('file:'.length);
  if (!afterScheme.startsWith('/') ||
      !parsed.path.startsWith('/') ||
      parsed.path.isEmpty ||
      parsed.path == '/') {
    throw ArgumentError(
      'Invalid evals storage URI: $evalStorageUri. file:// URIs must use '
      'an absolute path, e.g. file:///abs/path',
    );
  }
  final String localPath = Uri.decodeFull(parsed.path);
  try {
    Directory(localPath).createSync(recursive: true);
  } on FileSystemException catch (error) {
    throw ArgumentError(
      "Failed to create eval storage directory '$localPath' for "
      "'$evalStorageUri' (configured via --eval_storage_uri or "
      'ADK_EVAL_STORAGE_URI): $error',
    );
  }
  return localPath;
}

_EvalManagers _createEvalManagers({
  required String? evalStorageUri,
  required String agentsDir,
  required bool useInMemory,
  Map<String, String>? environment,
}) {
  final String? resolvedUri = _resolveEvalStorageUri(
    evalStorageUri,
    environment: environment,
  );
  if (resolvedUri == null) {
    if (useInMemory) {
      return _EvalManagers(
        evalSetsManager: InMemoryEvalSetsManager(),
        evalSetResultsManager: InMemoryEvalSetResultsManager(),
      );
    }
    return _EvalManagers(
      evalSetsManager: LocalEvalSetsManager(agentsDir),
      evalSetResultsManager: LocalEvalSetResultsManager(agentsDir),
    );
  }

  final EvalSetsManager configuredSetsManager;
  final EvalSetResultsManager configuredResultsManager;
  if (resolvedUri.startsWith('gs://')) {
    final cli_evals.GcsEvalManagers gcsManagers = cli_evals
        .createGcsEvalManagersFromUri(resolvedUri);
    configuredSetsManager = gcsManagers.evalSetsManager;
    configuredResultsManager = gcsManagers.evalSetResultsManager;
  } else {
    final String localDir = _localEvalDirFromUri(resolvedUri);
    configuredSetsManager = LocalEvalSetsManager(localDir);
    configuredResultsManager = LocalEvalSetResultsManager(localDir);
  }

  return _EvalManagers(
    evalSetsManager: useInMemory
        ? InMemoryEvalSetsManager()
        : configuredSetsManager,
    evalSetResultsManager: configuredResultsManager,
  );
}

Future<List<_EvalTarget>> _resolveEvalTargets({
  required _ParsedEvalCliCommand command,
  required String appName,
  required EvalSetsManager evalSetsManager,
  required bool usesFileTargets,
}) async {
  final List<_EvalTarget> targets = <_EvalTarget>[];
  if (usesFileTargets) {
    for (final _EvalSelection selection in command.selections) {
      final FileSystemEntityType type = FileSystemEntity.typeSync(
        selection.source,
      );
      if (type != FileSystemEntityType.file) {
        throw CliUsageError(
          'Eval target `${selection.source}` must be a file path.',
        );
      }

      final EvalSet evalSet;
      try {
        evalSet = loadEvalSetFromFile(selection.source, selection.source);
      } on Exception catch (error) {
        throw CliUsageError(
          '`${selection.source}` should be a valid eval set file. $error',
        );
      }

      await evalSetsManager.createEvalSet(appName, evalSet.evalSetId);
      final List<EvalCase> selectedCases = selection.evalCaseIds.isEmpty
          ? evalSet.evalCases
          : evalSet.evalCases
                .where(
                  (EvalCase item) =>
                      selection.evalCaseIds.contains(item.evalId),
                )
                .toList(growable: false);
      for (final EvalCase evalCase in selectedCases) {
        await evalSetsManager.addEvalCase(appName, evalSet.evalSetId, evalCase);
      }
      _mergeEvalTarget(targets, evalSet.evalSetId, selection.evalCaseIds);
    }
    return targets;
  }

  for (final _EvalSelection selection in command.selections) {
    _mergeEvalTarget(targets, selection.source, selection.evalCaseIds);
  }
  return targets;
}

void _mergeEvalTarget(
  List<_EvalTarget> targets,
  String evalSetId,
  Set<String> evalCaseIds,
) {
  final int index = targets.indexWhere((item) => item.evalSetId == evalSetId);
  if (index == -1) {
    targets.add(
      _EvalTarget(
        evalSetId: evalSetId,
        evalCaseIds: Set<String>.from(evalCaseIds),
      ),
    );
    return;
  }

  final _EvalTarget existing = targets[index];
  if (existing.evalCaseIds.isEmpty || evalCaseIds.isEmpty) {
    targets[index] = _EvalTarget(evalSetId: evalSetId, evalCaseIds: <String>{});
    return;
  }
  targets[index] = _EvalTarget(
    evalSetId: evalSetId,
    evalCaseIds: <String>{...existing.evalCaseIds, ...evalCaseIds},
  );
}

Future<List<EvalCaseResult>> _evaluateEvalSet({
  required BaseAgent rootAgent,
  required String appName,
  required String evalSetId,
  required List<EvalCase> evalCases,
  required EvalSetResultsManager evalSetResultsManager,
  String? configFilePath,
  EvalConfig? evalConfig,
  int numRuns = 1,
  int? parallelism,
}) async {
  final LocalEvalService evalService = LocalEvalService(
    rootAgent: rootAgent,
    appName: appName,
  );
  final EvalConfig resolvedEvalConfig =
      evalConfig ?? cli_eval.getEvaluationCriteriaOrDefault(configFilePath);
  final int effectiveParallelism =
      parallelism ?? resolvedEvalConfig.parallelism ?? 4;

  final List<InferenceResult> inferenceResults = await evalService
      .performInference(
        InferenceRequest(
          appName: appName,
          evalCases: evalCases,
          userId: 'eval_user',
          inferenceConfig: InferenceConfig(
            useLive: resolvedEvalConfig.liveModelConfig != null,
            numRuns: numRuns,
            parallelism: effectiveParallelism,
          ),
        ),
      )
      .toList();

  final Map<String, EvalCase> evalCasesById = <String, EvalCase>{
    for (final EvalCase evalCase in evalCases) evalCase.evalId: evalCase,
  };
  final List<EvalMetric> evalMetrics =
      cli_eval.resolveCliEvalMetricsFromConfig(resolvedEvalConfig);
  final List<EvalCaseResult> rawResults = await evalService
      .evaluate(
        EvaluateRequest(
          inferenceResults: inferenceResults,
          evalCasesById: evalCasesById,
          evaluateConfig: EvaluateConfig(
            evalMetrics: evalMetrics,
            parallelism: effectiveParallelism,
          ),
        ),
      )
      .toList();

  final Map<(String, int?), InferenceResult> inferenceByCaseAndRep =
      <(String, int?), InferenceResult>{
        for (final InferenceResult inference in inferenceResults)
          (inference.evalCaseId, inference.repetitionIndex): inference,
      };
  final Map<String, InferenceResult> inferenceByEvalCaseId =
      <String, InferenceResult>{
        for (final InferenceResult inference in inferenceResults)
          inference.evalCaseId: inference,
      };
  final List<EvalCaseResult> normalizedResults = rawResults
      .map((EvalCaseResult value) {
        final InferenceResult? inference =
            inferenceByCaseAndRep[(value.evalCaseId, value.repetitionIndex)] ??
            inferenceByEvalCaseId[value.evalCaseId];
        return EvalCaseResult(
          evalCaseId: value.evalCaseId,
          metrics: value.metrics,
          evalSetId: evalSetId,
          finalEvalStatus: _deriveEvalStatusFromMetrics(value.metrics),
          sessionId: value.sessionId.isNotEmpty
              ? value.sessionId
              : (inference?.sessionId ?? ''),
          userId:
              evalCasesById[value.evalCaseId]?.sessionInput?.userId ??
              'eval_user',
          evalSetFile: '$evalSetId.evalset.json',
          repetitionIndex: value.repetitionIndex ?? inference?.repetitionIndex,
        );
      })
      .toList(growable: false);
  await evalSetResultsManager.saveEvalSetResult(
    appName,
    evalSetId,
    normalizedResults,
  );
  return normalizedResults;
}

EvalStatus _deriveEvalStatusFromMetrics(List<EvalMetricResult> metrics) {
  if (metrics.isEmpty) {
    return EvalStatus.notEvaluated;
  }
  final bool passed = metrics.every(
    (EvalMetricResult metric) => metric.evalStatus == EvalStatus.passed,
  );
  return passed ? EvalStatus.passed : EvalStatus.failed;
}

Future<_LoadedCliAgent> _loadAgentForCli(String projectDirPath) async {
  final Directory requestedDir = Directory(projectDirPath).absolute;
  final FileSystemEntityType entityType = await FileSystemEntity.type(
    requestedDir.path,
  );
  if (entityType == FileSystemEntityType.notFound) {
    throw FileSystemException(
      'Project directory does not exist.',
      requestedDir.path,
    );
  }
  if (entityType != FileSystemEntityType.directory) {
    throw FileSystemException(
      'Project path is not a directory.',
      requestedDir.path,
    );
  }
  final Directory agentDir = Directory(
    await requestedDir.resolveSymbolicLinks(),
  );

  await _migrateLegacyProjectToRootAgentYaml(agentDir.path);

  final String agentFolderName = projectDirName(agentDir.path);
  final Directory agentsParentDir = agentDir.parent.absolute;
  loadServicesModule(agentDir.path);
  final AgentLoader agentLoader = AgentLoader(
    agentsParentDir.path,
    enableDevProjectFallback: false,
  );
  final AgentOrApp loaded = agentLoader.loadAgent(agentFolderName);
  final BaseAgent rootAgent = asBaseAgent(loaded);
  final String appName = loaded is App ? loaded.name : agentFolderName;
  return _LoadedCliAgent(
    rootAgent: rootAgent,
    appName: appName,
    agentsParentDirPath: agentsParentDir.path,
  );
}

int _bestOptimizedAgentIndex(GepaRootAgentPromptOptimizerResult result) {
  if (result.optimizedAgents.isEmpty) {
    return 0;
  }
  final Object? rawBestIdx = result.gepaResult?['best_idx'];
  if (rawBestIdx is int &&
      rawBestIdx >= 0 &&
      rawBestIdx < result.optimizedAgents.length) {
    return rawBestIdx;
  }
  int bestIndex = 0;
  double bestScore = result.optimizedAgents.first.overallScore ?? 0.0;
  for (int i = 1; i < result.optimizedAgents.length; i += 1) {
    final double score = result.optimizedAgents[i].overallScore ?? 0.0;
    if (score > bestScore) {
      bestScore = score;
      bestIndex = i;
    }
  }
  return bestIndex;
}

_ParsedEvalSetCreateCommand _parseEvalSetCreateCommand(List<String> args) {
  String? evalStorageUri;
  String? logLevel;
  bool verbose = false;
  final List<String> positionals = <String>[];
  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--eval_storage_uri') {
      evalStorageUri = _nextArg(args, i, '--eval_storage_uri');
      i += 1;
      continue;
    }
    if (arg.startsWith('--eval_storage_uri=')) {
      evalStorageUri = arg.substring('--eval_storage_uri='.length);
      continue;
    }
    if (arg == '--log_level' || arg == '--verbosity') {
      logLevel = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--log_level=') || arg.startsWith('--verbosity=')) {
      logLevel = arg.substring(arg.indexOf('=') + 1);
      continue;
    }
    if (arg == '-v' || arg == '--verbose') {
      verbose = true;
      continue;
    }
    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for eval_set create: $arg');
    }
    positionals.add(arg);
  }
  if (positionals.length != 2) {
    throw CliUsageError(
      'eval_set create requires <project_dir> <eval_set_id>.',
    );
  }
  final String? resolvedLogLevel = (logLevel != null || verbose)
      ? _resolveCliLogLevel(explicit: _emptyToNull(logLevel), verbose: verbose)
      : null;
  return _ParsedEvalSetCreateCommand(
    agentPath: positionals[0],
    evalSetId: positionals[1],
    evalStorageUri: _emptyToNull(evalStorageUri),
    logLevel: resolvedLogLevel,
  );
}

_ParsedEvalSetAddEvalCaseCommand _parseEvalSetAddEvalCaseCommand(
  List<String> args,
) {
  String? evalStorageUri;
  String? logLevel;
  bool verbose = false;
  String? scenariosFilePath;
  String? sessionInputFilePath;
  final List<String> positionals = <String>[];
  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--eval_storage_uri') {
      evalStorageUri = _nextArg(args, i, '--eval_storage_uri');
      i += 1;
      continue;
    }
    if (arg.startsWith('--eval_storage_uri=')) {
      evalStorageUri = arg.substring('--eval_storage_uri='.length);
      continue;
    }
    if (arg == '--log_level' || arg == '--verbosity') {
      logLevel = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--log_level=') || arg.startsWith('--verbosity=')) {
      logLevel = arg.substring(arg.indexOf('=') + 1);
      continue;
    }
    if (arg == '-v' || arg == '--verbose') {
      verbose = true;
      continue;
    }
    if (arg == '--scenarios_file') {
      scenariosFilePath = _nextArg(args, i, '--scenarios_file');
      i += 1;
      continue;
    }
    if (arg.startsWith('--scenarios_file=')) {
      scenariosFilePath = arg.substring('--scenarios_file='.length);
      continue;
    }
    if (arg == '--session_input_file') {
      sessionInputFilePath = _nextArg(args, i, '--session_input_file');
      i += 1;
      continue;
    }
    if (arg.startsWith('--session_input_file=')) {
      sessionInputFilePath = arg.substring('--session_input_file='.length);
      continue;
    }
    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for eval_set add_eval_case: $arg');
    }
    positionals.add(arg);
  }
  if (positionals.length != 2) {
    throw CliUsageError(
      'eval_set add_eval_case requires <project_dir> <eval_set_id>.',
    );
  }
  if (_emptyToNull(scenariosFilePath) == null) {
    throw CliUsageError('eval_set add_eval_case requires --scenarios_file.');
  }
  if (_emptyToNull(sessionInputFilePath) == null) {
    throw CliUsageError(
      'eval_set add_eval_case requires --session_input_file.',
    );
  }
  final String? resolvedLogLevel = (logLevel != null || verbose)
      ? _resolveCliLogLevel(explicit: _emptyToNull(logLevel), verbose: verbose)
      : null;
  return _ParsedEvalSetAddEvalCaseCommand(
    agentPath: positionals[0],
    evalSetId: positionals[1],
    scenariosFilePath: _emptyToNull(scenariosFilePath)!,
    sessionInputFilePath: _emptyToNull(sessionInputFilePath)!,
    evalStorageUri: _emptyToNull(evalStorageUri),
    logLevel: resolvedLogLevel,
  );
}

_ParsedEvalSetGenerateEvalCasesCommand _parseEvalSetGenerateEvalCasesCommand(
  List<String> args,
) {
  String? evalStorageUri;
  String? logLevel;
  bool verbose = false;
  String? configFilePath;
  String? sessionInputFilePath;
  int repeatNum = 1;
  final List<String> positionals = <String>[];
  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--eval_storage_uri') {
      evalStorageUri = _nextArg(args, i, '--eval_storage_uri');
      i += 1;
      continue;
    }
    if (arg.startsWith('--eval_storage_uri=')) {
      evalStorageUri = arg.substring('--eval_storage_uri='.length);
      continue;
    }
    if (arg == '--log_level' || arg == '--verbosity') {
      logLevel = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--log_level=') || arg.startsWith('--verbosity=')) {
      logLevel = arg.substring(arg.indexOf('=') + 1);
      continue;
    }
    if (arg == '-v' || arg == '--verbose') {
      verbose = true;
      continue;
    }
    if (arg == '--conversation_generation_config_file') {
      configFilePath = _nextArg(
        args,
        i,
        '--conversation_generation_config_file',
      );
      i += 1;
      continue;
    }
    if (arg.startsWith('--conversation_generation_config_file=')) {
      configFilePath = arg.substring(
        '--conversation_generation_config_file='.length,
      );
      continue;
    }
    if (arg == '--session_input_file') {
      sessionInputFilePath = _nextArg(args, i, '--session_input_file');
      i += 1;
      continue;
    }
    if (arg.startsWith('--session_input_file=')) {
      sessionInputFilePath = arg.substring('--session_input_file='.length);
      continue;
    }
    if (arg == '--repeat_num') {
      final String rawRepeat = _nextArg(args, i, '--repeat_num');
      final int? parsed = int.tryParse(rawRepeat.trim());
      if (parsed == null || parsed <= 0) {
        throw CliUsageError('Invalid value for --repeat_num: $rawRepeat');
      }
      repeatNum = parsed;
      i += 1;
      continue;
    }
    if (arg.startsWith('--repeat_num=')) {
      final String rawRepeat = arg.substring('--repeat_num='.length);
      final int? parsed = int.tryParse(rawRepeat.trim());
      if (parsed == null || parsed <= 0) {
        throw CliUsageError('Invalid value for --repeat_num: $rawRepeat');
      }
      repeatNum = parsed;
      continue;
    }
    if (arg.startsWith('-')) {
      throw CliUsageError(
        'Unknown option for eval_set generate_eval_cases: $arg',
      );
    }
    positionals.add(arg);
  }
  if (positionals.length != 2) {
    throw CliUsageError(
      'eval_set generate_eval_cases requires <project_dir> <eval_set_id>.',
    );
  }
  if (_emptyToNull(configFilePath) == null) {
    throw CliUsageError(
      'eval_set generate_eval_cases requires --conversation_generation_config_file.',
    );
  }
  if (_emptyToNull(sessionInputFilePath) == null) {
    throw CliUsageError(
      'eval_set generate_eval_cases requires --session_input_file.',
    );
  }
  final String? resolvedLogLevel = (logLevel != null || verbose)
      ? _resolveCliLogLevel(explicit: _emptyToNull(logLevel), verbose: verbose)
      : null;
  return _ParsedEvalSetGenerateEvalCasesCommand(
    agentPath: positionals[0],
    evalSetId: positionals[1],
    conversationGenerationConfigFilePath: _emptyToNull(configFilePath)!,
    sessionInputFilePath: _emptyToNull(sessionInputFilePath)!,
    repeatNum: repeatNum,
    evalStorageUri: _emptyToNull(evalStorageUri),
    logLevel: resolvedLogLevel,
  );
}

Future<Map<String, Object?>> _readJsonObjectFile(
  String filePath, {
  required String label,
}) async {
  final File file = File(filePath);
  if (!await file.exists()) {
    throw FileSystemException('$label not found.', file.path);
  }
  final Object? decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) {
    throw FormatException('$label must contain a JSON object.');
  }
  return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
}

Future<ConversationScenarios> _readConversationScenariosFile(
  String filePath,
) async {
  final File file = File(filePath);
  if (!await file.exists()) {
    throw FileSystemException('scenarios file not found.', file.path);
  }
  final Object? decoded = jsonDecode(await file.readAsString());
  if (decoded is List) {
    return ConversationScenarios.fromJson(<String, Object?>{
      'scenarios': decoded,
    });
  }
  if (decoded is Map) {
    final Map<String, Object?> map = decoded.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
    return ConversationScenarios.fromJson(map);
  }
  throw const FormatException(
    'scenarios file must contain a JSON array or object.',
  );
}

String _stableScenarioId(ConversationScenario scenario) {
  final String canonical = jsonEncode(
    _normalizeJsonForStableHash(scenario.toJson()),
  );
  final String digest = crypto.sha256
      .convert(utf8.encode(canonical))
      .toString();
  return digest.substring(0, 8);
}

Object? _normalizeJsonForStableHash(Object? value) {
  if (value is Map) {
    final List<String> keys =
        value.keys.map((Object? key) => '$key').toList(growable: false)..sort();
    final Map<String, Object?> normalized = <String, Object?>{};
    for (final String key in keys) {
      normalized[key] = _normalizeJsonForStableHash(value[key]);
    }
    return normalized;
  }
  if (value is List) {
    return value
        .map((Object? item) => _normalizeJsonForStableHash(item))
        .toList(growable: false);
  }
  return value;
}
