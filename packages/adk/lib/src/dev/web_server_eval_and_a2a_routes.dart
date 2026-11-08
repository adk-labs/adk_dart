part of 'web_server.dart';

Future<bool> _handleEvalRoutes(
  HttpRequest request,
  _AdkDevWebContext context,
  List<String> segments, {
  required String appName,
}) async {
  try {
    return await _handleEvalRoutesInner(
      request,
      context,
      segments,
      appName: appName,
    );
  } on _EvalManagerNotConfiguredException catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.internalServerError,
      message: error.message,
      detail: error.message,
    );
    return true;
  }
}

Future<bool> _handleEvalRoutesInner(
  HttpRequest request,
  _AdkDevWebContext context,
  List<String> segments, {
  required String appName,
}) async {
  if (segments.length < 3) {
    return false;
  }

  if (segments.length == 3 &&
      segments[2] == 'metrics-info' &&
      request.method == 'GET') {
    await _handleListMetricsInfo(request, context);
    return true;
  }

  final String category = segments[2];
  final bool isEvalSetCollection = _isEvalSetCollection(category);
  final bool isEvalResultCollection = _isEvalResultCollection(category);

  if (isEvalResultCollection) {
    final bool legacy = category == 'eval_results';
    if (segments.length == 3 && request.method == 'GET') {
      await _handleListEvalResults(
        request,
        context,
        appName: appName,
        legacy: legacy,
      );
      return true;
    }
    if (segments.length == 4 && request.method == 'GET') {
      await _handleGetEvalResult(
        request,
        context,
        appName: appName,
        evalResultId: segments[3],
      );
      return true;
    }
    return false;
  }

  if (!isEvalSetCollection) {
    return false;
  }

  final bool legacy = category == 'eval_sets';
  if (segments.length == 3) {
    if (!legacy && request.method == 'POST') {
      await _handleCreateEvalSet(request, context, appName: appName);
      return true;
    }
    if (request.method == 'GET') {
      await _handleListEvalSets(
        request,
        context,
        appName: appName,
        legacy: legacy,
      );
      return true;
    }
    return false;
  }

  final String evalSetId = segments[3];
  if (legacy && segments.length == 4 && request.method == 'POST') {
    await _handleCreateEvalSetLegacy(
      request,
      context,
      appName: appName,
      evalSetId: evalSetId,
    );
    return true;
  }

  if (segments.length == 5 &&
      (segments[4] == 'add-session' || segments[4] == 'add_session') &&
      request.method == 'POST') {
    await _handleAddSessionToEvalSet(
      request,
      context,
      appName: appName,
      evalSetId: evalSetId,
    );
    return true;
  }

  if (segments.length == 5 &&
      segments[4] == 'evals' &&
      request.method == 'GET') {
    await _handleListEvalsInEvalSet(
      request,
      context,
      appName: appName,
      evalSetId: evalSetId,
    );
    return true;
  }

  if (segments.length == 5 &&
      (segments[4] == 'run' || segments[4] == 'run_eval') &&
      request.method == 'POST') {
    await _handleRunEval(
      request,
      context,
      appName: appName,
      evalSetId: evalSetId,
      legacy: segments[4] == 'run_eval',
    );
    return true;
  }

  if (segments.length == 6 &&
      ((segments[4] == 'eval-cases' && category == 'eval-sets') ||
          (segments[4] == 'evals' && category == 'eval_sets'))) {
    final String evalCaseId = segments[5];
    if (request.method == 'GET') {
      await _handleGetEvalCase(
        request,
        context,
        appName: appName,
        evalSetId: evalSetId,
        evalCaseId: evalCaseId,
      );
      return true;
    }
    if (request.method == 'PUT') {
      await _handleUpdateEvalCase(
        request,
        context,
        appName: appName,
        evalSetId: evalSetId,
        evalCaseId: evalCaseId,
      );
      return true;
    }
    if (request.method == 'DELETE') {
      await _handleDeleteEvalCase(
        request,
        context,
        appName: appName,
        evalSetId: evalSetId,
        evalCaseId: evalCaseId,
      );
      return true;
    }
  }

  return false;
}

bool _isEvalSetCollection(String value) {
  return value == 'eval-sets' || value == 'eval_sets';
}

bool _isEvalResultCollection(String value) {
  return value == 'eval-results' || value == 'eval_results';
}

Future<void> _handleListMetricsInfo(
  HttpRequest request,
  _AdkDevWebContext context,
) async {
  final List<Map<String, Object?>> metrics = defaultMetricEvaluatorRegistry
      .getRegisteredMetrics()
      .map((MetricInfo metric) => metric.toJson())
      .toList(growable: false);
  await _writeJson(
    request,
    context,
    payload: <String, Object?>{'metrics_info': metrics},
  );
}

Future<void> _handleCreateEvalSet(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
}) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final Object? evalSetRaw =
      payload['eval_set'] ?? payload['evalSet'] ?? payload;
  final Map<String, dynamic> evalSetMap = _toDynamicMap(evalSetRaw);
  final String evalSetId = _readString(evalSetMap, const <String>[
    'eval_set_id',
    'evalSetId',
    'id',
    'name',
  ], required: true);
  final EvalSet evalSet = await context._getEvalSetsManager().createEvalSet(
    appName,
    evalSetId,
  );
  await _writeJson(
    request,
    context,
    payload: evalSet.toJson(includeNulls: false),
  );
}

Future<void> _handleCreateEvalSetLegacy(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String evalSetId,
}) async {
  await context._getEvalSetsManager().createEvalSet(appName, evalSetId);
  await _writeJson(request, context, payload: const <String, Object?>{});
}

Future<void> _handleListEvalSets(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required bool legacy,
}) async {
  final EvalSetsManager evalSetsManager = context._getEvalSetsManager();
  List<String> evalSetIds = <String>[];
  try {
    evalSetIds = await evalSetsManager.listEvalSets(appName);
  } on NotFoundError {
    evalSetIds = <String>[];
  }
  if (legacy) {
    await _writeJson(request, context, payload: evalSetIds);
  } else {
    await _writeJson(
      request,
      context,
      payload: <String, Object?>{'eval_set_ids': evalSetIds},
    );
  }
}

Future<void> _handleListEvalResults(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required bool legacy,
}) async {
  final List<String> evalResultIds = await context
      ._getEvalSetResultsManager()
      .listEvalSetResults(appName);
  if (legacy) {
    await _writeJson(request, context, payload: evalResultIds);
  } else {
    await _writeJson(
      request,
      context,
      payload: <String, Object?>{'eval_result_ids': evalResultIds},
    );
  }
}

Future<void> _handleGetEvalResult(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String evalResultId,
}) async {
  final EvalSetResult evalResult = await context
      ._getEvalSetResultsManager()
      .getEvalSetResult(appName, evalResultId);
  await _writeJson(request, context, payload: evalResult.toJson());
}

Future<void> _handleAddSessionToEvalSet(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String evalSetId,
}) async {
  final EvalSetsManager evalSetsManager = context._getEvalSetsManager();
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final String evalId = _readString(payload, const <String>[
    'eval_id',
    'evalId',
  ], required: true);
  final String sessionId = _readString(payload, const <String>[
    'session_id',
    'sessionId',
  ], required: true);
  final String userId = _readString(payload, const <String>[
    'user_id',
    'userId',
  ], required: true);
  final String validatedSessionId = _validatePathIdentifier(
    sessionId,
    'session_id',
  );
  final String validatedUserId = _validatePathIdentifier(userId, 'user_id');

  final Session? session = await context.sessionService.getSession(
    appName: appName,
    userId: validatedUserId,
    sessionId: validatedSessionId,
  );
  if (session == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: 'Session not found',
    );
    return;
  }

  final List<Invocation> invocations = cli_evals
      .convertSessionToEvalInvocations(session);
  final EvalCase evalCase = EvalCase(
    evalId: evalId,
    conversation: invocations,
    sessionInput: SessionInput(
      appName: appName,
      userId: userId,
      state: Map<String, Object?>.from(session.state),
    ),
    creationTimestamp: DateTime.now().millisecondsSinceEpoch / 1000,
  );
  await evalSetsManager.addEvalCase(appName, evalSetId, evalCase);
  await _writeJson(request, context, payload: const <String, Object?>{});
}

Future<void> _handleListEvalsInEvalSet(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String evalSetId,
}) async {
  final EvalSet? evalSet = await context._getEvalSetsManager().getEvalSet(
    appName,
    evalSetId,
  );
  if (evalSet == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'Eval set `$evalSetId` not found.',
    );
    return;
  }
  final List<String> ids =
      evalSet.evalCases
          .map((EvalCase value) => value.evalId)
          .toList(growable: false)
        ..sort();
  await _writeJson(request, context, payload: ids);
}

Future<void> _handleGetEvalCase(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String evalSetId,
  required String evalCaseId,
}) async {
  final EvalCase? evalCase = await context._getEvalSetsManager().getEvalCase(
    appName,
    evalSetId,
    evalCaseId,
  );
  if (evalCase == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: 'Eval set `$evalSetId` or Eval `$evalCaseId` not found.',
    );
    return;
  }
  await _writeJson(request, context, payload: evalCase.toJson());
}

Future<void> _handleUpdateEvalCase(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String evalSetId,
  required String evalCaseId,
}) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final EvalCase updatedEvalCase = EvalCase.fromJson(
    payload.map((String key, Object? value) => MapEntry(key, value)),
  );
  if (updatedEvalCase.evalId.isNotEmpty &&
      updatedEvalCase.evalId != evalCaseId) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'Eval id in EvalCase should match the eval id in the API route.',
    );
    return;
  }

  final EvalCase withRouteId = _copyEvalCaseWithId(updatedEvalCase, evalCaseId);
  try {
    await context._getEvalSetsManager().updateEvalCase(
      appName,
      evalSetId,
      withRouteId,
    );
  } on NotFoundError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: '$error',
    );
    return;
  }
  await _writeJson(request, context, payload: const <String, Object?>{});
}

EvalCase _copyEvalCaseWithId(EvalCase evalCase, String evalCaseId) {
  return EvalCase(
    evalId: evalCaseId,
    input: evalCase.input,
    expectedOutput: evalCase.expectedOutput,
    conversation: evalCase.conversation,
    conversationScenario: evalCase.conversationScenario,
    sessionInput: evalCase.sessionInput,
    creationTimestamp: evalCase.creationTimestamp,
    rubrics: evalCase.rubrics,
    finalSessionState: evalCase.finalSessionState,
    metadata: evalCase.metadata,
  );
}

Future<void> _handleDeleteEvalCase(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String evalSetId,
  required String evalCaseId,
}) async {
  try {
    await context._getEvalSetsManager().deleteEvalCase(
      appName,
      evalSetId,
      evalCaseId,
    );
  } on NotFoundError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: '$error',
    );
    return;
  }
  await _writeJson(request, context, payload: const <String, Object?>{});
}

Future<void> _handleRunEval(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String evalSetId,
  required bool legacy,
}) async {
  final EvalSet? evalSet = await context._getEvalSetsManager().getEvalSet(
    appName,
    evalSetId,
  );
  if (evalSet == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'Eval set `$evalSetId` not found.',
    );
    return;
  }

  final Map<String, dynamic> payload = await _readJsonBody(request);
  final List<String> requestedEvalCaseIds = _parseRunEvalCaseIds(payload);
  final List<EvalMetric> evalMetrics = _parseRunEvalMetrics(payload);

  final List<EvalCase> evalCases = requestedEvalCaseIds.isEmpty
      ? List<EvalCase>.from(evalSet.evalCases)
      : evalSet.evalCases
            .where(
              (EvalCase value) => requestedEvalCaseIds.contains(value.evalId),
            )
            .toList(growable: false);

  final Runner runner = await context.getRunner(appName);
  final LocalEvalService evalService = LocalEvalService(
    rootAgent: runner.agent,
    appName: appName,
  );
  final List<InferenceResult> inferenceResults = await evalService
      .performInference(
        InferenceRequest(
          appName: appName,
          evalCases: evalCases,
          userId: 'eval_user',
        ),
      )
      .toList();

  final Map<String, EvalCase> evalCasesById = <String, EvalCase>{
    for (final EvalCase evalCase in evalCases) evalCase.evalId: evalCase,
  };
  final List<EvalCaseResult> rawResults = await evalService
      .evaluate(
        EvaluateRequest(
          inferenceResults: inferenceResults,
          evalCasesById: evalCasesById,
          evaluateConfig: EvaluateConfig(evalMetrics: evalMetrics),
        ),
      )
      .toList();

  final Map<String, InferenceResult> inferenceByEvalCaseId =
      <String, InferenceResult>{
        for (final InferenceResult inference in inferenceResults)
          inference.evalCaseId: inference,
      };
  final List<EvalCaseResult> normalizedResults = rawResults
      .map((EvalCaseResult value) {
        final InferenceResult? inference =
            inferenceByEvalCaseId[value.evalCaseId];
        return EvalCaseResult(
          evalCaseId: value.evalCaseId,
          metrics: value.metrics,
          evalSetId: evalSetId,
          finalEvalStatus: _deriveEvalStatus(value.metrics),
          sessionId: inference?.sessionId ?? '',
          userId:
              evalCasesById[value.evalCaseId]?.sessionInput?.userId ??
              'eval_user',
          evalSetFile: '$evalSetId.evalset.json',
        );
      })
      .toList(growable: false);
  if (context.evalSetResultsManager != null) {
    await context.evalSetResultsManager!.saveEvalSetResult(
      appName,
      evalSetId,
      normalizedResults,
    );
  }

  final List<Map<String, Object?>> runEvalResults = normalizedResults
      .map((EvalCaseResult value) => value.toJson())
      .toList(growable: false);

  if (legacy) {
    await _writeJson(request, context, payload: runEvalResults);
  } else {
    await _writeJson(
      request,
      context,
      payload: <String, Object?>{'run_eval_results': runEvalResults},
    );
  }
}

EvalStatus _deriveEvalStatus(List<EvalMetricResult> metrics) {
  if (metrics.isEmpty) {
    return EvalStatus.notEvaluated;
  }
  final bool passed = metrics.every(
    (EvalMetricResult value) => value.evalStatus == EvalStatus.passed,
  );
  return passed ? EvalStatus.passed : EvalStatus.failed;
}

List<String> _parseRunEvalCaseIds(Map<String, dynamic> payload) {
  final List<String> ids = <String>[];
  final Object? rawCaseIds = payload['eval_case_ids'] ?? payload['evalCaseIds'];
  if (rawCaseIds is List) {
    ids.addAll(
      rawCaseIds
          .map((Object? value) => '$value'.trim())
          .where((String value) => value.isNotEmpty),
    );
  }
  final Object? rawLegacyIds = payload['eval_ids'] ?? payload['evalIds'];
  if (rawLegacyIds is List) {
    ids.addAll(
      rawLegacyIds
          .map((Object? value) => '$value'.trim())
          .where((String value) => value.isNotEmpty),
    );
  }
  return ids.toSet().toList(growable: false);
}

List<EvalMetric> _parseRunEvalMetrics(Map<String, dynamic> payload) {
  final Object? rawMetrics = payload['eval_metrics'] ?? payload['evalMetrics'];
  if (rawMetrics is! List || rawMetrics.isEmpty) {
    return <EvalMetric>[EvalMetric.finalResponseExactMatch];
  }

  final List<EvalMetric> metrics = <EvalMetric>[];
  for (final Object? raw in rawMetrics) {
    if (raw is String) {
      final EvalMetric? parsed = _evalMetricFromName(raw);
      if (parsed != null) {
        metrics.add(parsed);
      }
      continue;
    }
    if (raw is Map) {
      final Map<String, dynamic> map = _toDynamicMap(raw);
      final String metricName = _readString(map, const <String>[
        'metric_name',
        'metricName',
        'name',
      ], fallback: '');
      final EvalMetric? parsed = _evalMetricFromName(metricName);
      if (parsed != null) {
        metrics.add(parsed);
      }
    }
  }

  if (metrics.isEmpty) {
    return <EvalMetric>[EvalMetric.finalResponseExactMatch];
  }
  return metrics;
}

EvalMetric? _evalMetricFromName(String raw) {
  final String normalized = raw.trim().toLowerCase().replaceAll('-', '_');
  switch (normalized) {
    case 'final_response_exact_match':
    case 'finalresponseexactmatch':
      return EvalMetric.finalResponseExactMatch;
    case 'final_response_contains':
    case 'finalresponsecontains':
      return EvalMetric.finalResponseContains;
    default:
      return null;
  }
}

Future<void> _handleArtifactsRoute(
  HttpRequest request,
  _AdkDevWebContext context,
  List<String> segments, {
  required String appName,
  required String userId,
  required String sessionId,
}) async {
  if (segments.length == 7) {
    if (request.method == 'GET') {
      final List<String> names = await context.artifactService.listArtifactKeys(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
      await _writeJson(request, context, payload: names);
      return;
    }

    if (request.method == 'POST') {
      final Map<String, dynamic> payload = await _readJsonBody(request);
      final String filename = _readString(payload, const <String>[
        'filename',
      ], required: true);

      final Object? artifactRaw = payload['artifact'];
      if (artifactRaw is! Map) {
        throw const FormatException('artifact must be a JSON object.');
      }
      final Part artifact = _partFromJson(_toDynamicMap(artifactRaw));
      final Map<String, Object?>? customMetadata = _readObjectMap(
        payload,
        const <String>['custom_metadata', 'customMetadata'],
      );

      final ArtifactVersion? metadata;
      try {
        final int version = await context.artifactService.saveArtifact(
          appName: appName,
          userId: userId,
          sessionId: sessionId,
          filename: filename,
          artifact: artifact,
          customMetadata: customMetadata,
        );

        metadata = await context.artifactService.getArtifactVersion(
          appName: appName,
          userId: userId,
          sessionId: sessionId,
          filename: filename,
          version: version,
        );
      } catch (_) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.internalServerError,
          message: 'Error saving artifact',
        );
        return;
      }
      if (metadata == null) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.internalServerError,
          message: 'Artifact metadata unavailable.',
          detail: 'Error saving artifact',
        );
        return;
      }

      await _writeJson(
        request,
        context,
        payload: _artifactVersionToJson(metadata),
      );
      return;
    }

    await _writeError(
      request,
      context,
      statusCode: HttpStatus.methodNotAllowed,
      message: 'Method not allowed.',
    );
    return;
  }

  final String artifactName = segments[7];

  if (segments.length == 8) {
    if (request.method == 'GET') {
      final int? version = int.tryParse(
        request.uri.queryParameters['version'] ?? '',
      );
      final Part? artifact = await context.artifactService.loadArtifact(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
        filename: artifactName,
        version: version,
      );
      if (artifact == null) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.notFound,
          message: 'Artifact not found',
        );
        return;
      }
      await _writeJson(request, context, payload: _partToJson(artifact));
      return;
    }

    if (request.method == 'DELETE') {
      await context.artifactService.deleteArtifact(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
        filename: artifactName,
      );
      await _writeJson(request, context, payload: const <String, Object?>{});
      return;
    }

    await _writeError(
      request,
      context,
      statusCode: HttpStatus.methodNotAllowed,
      message: 'Method not allowed.',
    );
    return;
  }

  if (segments.length >= 9 && segments[8] == 'versions') {
    if (segments.length == 9 && request.method == 'GET') {
      final List<int> versions = await context.artifactService.listVersions(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
        filename: artifactName,
      );
      await _writeJson(request, context, payload: versions);
      return;
    }

    if (segments.length == 10 &&
        segments[9] == 'metadata' &&
        request.method == 'GET') {
      final List<ArtifactVersion> metadata = await context.artifactService
          .listArtifactVersions(
            appName: appName,
            userId: userId,
            sessionId: sessionId,
            filename: artifactName,
          );
      await _writeJson(
        request,
        context,
        payload: metadata
            .map<Map<String, Object?>>(_artifactVersionToJson)
            .toList(growable: false),
      );
      return;
    }

    if (segments.length == 10 && request.method == 'GET') {
      final int? versionId = int.tryParse(segments[9]);
      if (versionId == null) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.badRequest,
          message: 'Invalid version id: ${segments[9]}',
        );
        return;
      }

      final Part? artifact = await context.artifactService.loadArtifact(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
        filename: artifactName,
        version: versionId,
      );
      if (artifact == null) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.notFound,
          message: 'Artifact not found',
        );
        return;
      }
      await _writeJson(request, context, payload: _partToJson(artifact));
      return;
    }

    if (segments.length == 11 &&
        segments[10] == 'metadata' &&
        request.method == 'GET') {
      final int? versionId = int.tryParse(segments[9]);
      if (versionId == null) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.badRequest,
          message: 'Invalid version id: ${segments[9]}',
        );
        return;
      }

      final ArtifactVersion? metadata = await context.artifactService
          .getArtifactVersion(
            appName: appName,
            userId: userId,
            sessionId: sessionId,
            filename: artifactName,
            version: versionId,
          );
      if (metadata == null) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.notFound,
          message: 'Artifact version not found',
        );
        return;
      }

      await _writeJson(
        request,
        context,
        payload: _artifactVersionToJson(metadata),
      );
      return;
    }
  }

  await _writeError(
    request,
    context,
    statusCode: HttpStatus.notFound,
    message: 'Not found.',
  );
}

Future<void> _handleA2aAgentCard(
  HttpRequest request,
  _AdkDevWebContext context, {
  String? appNameFromPath,
}) async {
  final String fromQuery =
      request.uri.queryParameters['app_name'] ??
      request.uri.queryParameters['appName'] ??
      '';
  final String resolvedAppName = appNameFromPath?.trim().isNotEmpty == true
      ? appNameFromPath!.trim()
      : (fromQuery.trim().isNotEmpty
            ? fromQuery.trim()
            : context.defaultAppName);

  final Map<String, Object?>? diskCard = await _loadA2aAgentCardFromDisk(
    context,
    resolvedAppName,
  );
  if (diskCard != null) {
    await _writeJson(request, context, payload: diskCard);
    return;
  }

  final Runner runner = await context.getRunner(resolvedAppName);
  final Uri requested = request.requestedUri;
  final String authority = requested.authority;
  final String basePrefix = context.urlPrefix ?? '';
  final AgentCardBuilder cardBuilder = AgentCardBuilder(
    agent: runner.agent,
    rpcUrl: '${requested.scheme}://$authority$basePrefix/a2a/$resolvedAppName',
  );
  final dynamic card = await cardBuilder.build();
  await _writeJson(request, context, payload: card.toJson());
}

Future<Map<String, Object?>?> _loadA2aAgentCardFromDisk(
  _AdkDevWebContext context,
  String appName,
) async {
  final String sep = Platform.pathSeparator;
  final List<String> candidates = <String>[
    '${context.agentsDir}$sep$appName${sep}agent.json',
    if (appName == context.defaultAppName)
      '${context.agentsDir}${sep}agent.json',
  ];

  for (final String candidate in candidates) {
    final File file = File(candidate);
    if (!await file.exists()) {
      continue;
    }
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        continue;
      }
      return decoded.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
    } catch (_) {
      continue;
    }
  }
  return null;
}

String? _extractA2aScopedAppName(String routedPath) {
  const String suffix = '/.well-known/agent.json';
  if (routedPath.startsWith('/a2a/') && routedPath.endsWith(suffix)) {
    final String raw = routedPath.substring(
      '/a2a/'.length,
      routedPath.length - suffix.length,
    );
    final String appName = Uri.decodeComponent(raw).trim();
    if (appName.isEmpty || appName.contains('/')) {
      return null;
    }
    return appName;
  }

  if (routedPath.startsWith('/a2a/') && routedPath.endsWith('/agent-card')) {
    final String raw = routedPath.substring(
      '/a2a/'.length,
      routedPath.length - '/agent-card'.length,
    );
    final String appName = Uri.decodeComponent(raw).trim();
    if (appName.isEmpty || appName.contains('/')) {
      return null;
    }
    return appName;
  }

  return null;
}

/// Parsed A2A RPC route data extracted from HTTP path/method.
class _A2aRpcRoute {
  /// Creates parsed A2A RPC route metadata.
  _A2aRpcRoute({
    required this.appName,
    this.methodFromPath,
    this.taskIdFromPath,
  });

  /// Target app name.
  final String appName;

  /// Optional RPC method inferred from route suffix.
  final String? methodFromPath;

  /// Optional task id inferred from task-scoped routes.
  final String? taskIdFromPath;
}

/// Result bundle for one A2A execution step.
class _A2aExecutionResult {
  /// Creates an A2A execution result bundle.
  _A2aExecutionResult({
    required this.message,
    required this.task,
    required this.updates,
  });

  /// Message payload returned to the caller.
  final Map<String, Object?> message;

  /// Task snapshot payload.
  final Map<String, Object?> task;

  /// Ordered task update payloads.
  final List<Map<String, Object?>> updates;
}

_A2aRpcRoute? _parseA2aRpcRoute(String routedPath, String httpMethod) {
  if (!routedPath.startsWith('/a2a/')) {
    return null;
  }

  final List<String> segments = Uri(
    path: routedPath,
  ).pathSegments.where((String value) => value.isNotEmpty).toList();
  if (segments.length < 2 || segments[0] != 'a2a') {
    return null;
  }

  final String appName = Uri.decodeComponent(segments[1]).trim();
  if (appName.isEmpty || appName.contains('/')) {
    return null;
  }
  if (segments.length == 2) {
    return _A2aRpcRoute(appName: appName);
  }

  if (segments.length == 4 && segments[2] == 'v1') {
    final String? methodFromPath = _a2aMethodFromV1Operation(segments[3]);
    if (methodFromPath == null) {
      return null;
    }
    return _A2aRpcRoute(appName: appName, methodFromPath: methodFromPath);
  }

  if (segments.length >= 5 && segments[2] == 'v1' && segments[3] == 'tasks') {
    final String rawTaskSegment = Uri.decodeComponent(segments[4]).trim();
    if (rawTaskSegment.isEmpty) {
      return null;
    }

    if (segments.length == 5) {
      if (rawTaskSegment.endsWith(':cancel')) {
        final String taskId = rawTaskSegment
            .substring(0, rawTaskSegment.length - ':cancel'.length)
            .trim();
        if (taskId.isEmpty) {
          return null;
        }
        return _A2aRpcRoute(
          appName: appName,
          methodFromPath: 'tasks/cancel',
          taskIdFromPath: taskId,
        );
      }

      if (rawTaskSegment.endsWith(':subscribe')) {
        final String taskId = rawTaskSegment
            .substring(0, rawTaskSegment.length - ':subscribe'.length)
            .trim();
        if (taskId.isEmpty) {
          return null;
        }
        return _A2aRpcRoute(
          appName: appName,
          methodFromPath: 'tasks/resubscribe',
          taskIdFromPath: taskId,
        );
      }

      return _A2aRpcRoute(
        appName: appName,
        methodFromPath: 'tasks/get',
        taskIdFromPath: rawTaskSegment,
      );
    }

    if (segments.length == 6 &&
        segments[5].toLowerCase() == 'pushnotificationconfigs') {
      final String methodFromPath = httpMethod.toUpperCase() == 'GET'
          ? 'tasks/pushnotificationconfig/get'
          : 'tasks/pushnotificationconfig/set';
      return _A2aRpcRoute(
        appName: appName,
        methodFromPath: methodFromPath,
        taskIdFromPath: rawTaskSegment,
      );
    }
  }

  return null;
}

String? _a2aMethodFromV1Operation(String operation) {
  switch (operation.trim().toLowerCase()) {
    case 'message:send':
      return 'message/send';
    case 'message:stream':
      return 'message/stream';
    case 'tasks:get':
      return 'tasks/get';
    case 'tasks:cancel':
      return 'tasks/cancel';
    case 'tasks:resubscribe':
    case 'tasks:subscribe':
      return 'tasks/resubscribe';
    case 'tasks:pushnotificationconfig:set':
    case 'tasks:push_notification_config:set':
      return 'tasks/pushnotificationconfig/set';
    case 'tasks:pushnotificationconfig:get':
    case 'tasks:push_notification_config:get':
      return 'tasks/pushnotificationconfig/get';
    default:
      return null;
  }
}

Future<void> _handleA2aRpc(
  HttpRequest request,
  _AdkDevWebContext context, {
  required _A2aRpcRoute route,
}) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final bool useJsonRpcEnvelope =
      payload.containsKey('jsonrpc') ||
      payload.containsKey('id') ||
      payload.containsKey('method');
  final Object? id = payload['id'];
  final Map<String, dynamic> params;
  if (payload['params'] is Map) {
    params = _toDynamicMap(payload['params']);
  } else if (!useJsonRpcEnvelope && route.methodFromPath != null) {
    params = _toDynamicMap(payload);
  } else {
    params = <String, dynamic>{};
  }
  if (route.taskIdFromPath != null && route.taskIdFromPath!.trim().isNotEmpty) {
    params.putIfAbsent('taskId', () => route.taskIdFromPath!);
    params.putIfAbsent('task_id', () => route.taskIdFromPath!);
    params.putIfAbsent('id', () => route.taskIdFromPath!);
  }

  final String method = _normalizeA2aRpcMethod(
    (payload['method'] is String ? payload['method'] as String : null) ??
        route.methodFromPath ??
        '',
  );

  if (method.isEmpty) {
    await _writeA2aError(
      request,
      context,
      id: id,
      jsonRpcEnvelope: useJsonRpcEnvelope,
      jsonRpcCode: -32600,
      statusCode: HttpStatus.badRequest,
      message: 'A2A JSON-RPC request must provide a method.',
    );
    return;
  }

  try {
    switch (method) {
      case 'message/send':
        final _A2aExecutionResult result = await _executeA2aMessageSend(
          context,
          appName: route.appName,
          params: params,
        );
        await _writeA2aSuccess(
          request,
          context,
          id: id,
          jsonRpcEnvelope: useJsonRpcEnvelope,
          result: result.message,
        );
        return;
      case 'message/stream':
        final _A2aExecutionResult result = await _executeA2aMessageSend(
          context,
          appName: route.appName,
          params: params,
        );
        await _writeA2aSseTaskReplay(
          request,
          context,
          id: id,
          jsonRpcEnvelope: useJsonRpcEnvelope,
          task: result.task,
          updates: result.updates,
        );
        return;
      case 'tasks/get':
        final String taskId = _readString(params, const <String>[
          'taskId',
          'task_id',
          'id',
        ], required: true);
        final Map<String, Object?>? task = context.readA2aTask(
          route.appName,
          taskId,
        );
        if (task == null) {
          await _writeA2aError(
            request,
            context,
            id: id,
            jsonRpcEnvelope: useJsonRpcEnvelope,
            jsonRpcCode: -32004,
            statusCode: HttpStatus.notFound,
            message: 'A2A task not found: $taskId',
          );
          return;
        }
        await _writeA2aSuccess(
          request,
          context,
          id: id,
          jsonRpcEnvelope: useJsonRpcEnvelope,
          result: task,
        );
        return;
      case 'tasks/cancel':
        final String taskId = _readString(params, const <String>[
          'taskId',
          'task_id',
          'id',
        ], required: true);
        final Map<String, Object?>? existing = context.readA2aTask(
          route.appName,
          taskId,
        );
        if (existing == null) {
          await _writeA2aError(
            request,
            context,
            id: id,
            jsonRpcEnvelope: useJsonRpcEnvelope,
            jsonRpcCode: -32004,
            statusCode: HttpStatus.notFound,
            message: 'A2A task not found: $taskId',
          );
          return;
        }

        final Map<String, Object?> canceled = <String, Object?>{
          ...existing,
          'status': <String, Object?>{
            'state': 'failed',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'message': _a2aMessageToJson(
              A2aMessage(
                messageId:
                    'a2a_cancel_${DateTime.now().microsecondsSinceEpoch}',
                role: A2aRole.agent,
                taskId: taskId,
                contextId:
                    '${existing['contextId'] ?? existing['context_id'] ?? ''}',
                parts: <A2aPart>[A2aPart.text('Task cancellation requested.')],
              ),
            ),
          },
        };
        context.upsertA2aTask(route.appName, canceled);
        await _writeA2aSuccess(
          request,
          context,
          id: id,
          jsonRpcEnvelope: useJsonRpcEnvelope,
          result: canceled,
        );
        return;
      case 'tasks/pushnotificationconfig/set':
        final String taskId = _readString(params, const <String>[
          'taskId',
          'task_id',
          'id',
        ], required: true);
        final Map<String, Object?>? task = context.readA2aTask(
          route.appName,
          taskId,
        );
        if (task == null) {
          await _writeA2aError(
            request,
            context,
            id: id,
            jsonRpcEnvelope: useJsonRpcEnvelope,
            jsonRpcCode: -32004,
            statusCode: HttpStatus.notFound,
            message: 'A2A task not found: $taskId',
          );
          return;
        }

        final Map<String, Object?> pushConfig =
            _readObjectMap(params, const <String>[
              'pushNotificationConfig',
              'push_notification_config',
            ]) ??
            <String, Object?>{...params};
        pushConfig.remove('taskId');
        pushConfig.remove('task_id');
        pushConfig.remove('id');

        if (pushConfig.isEmpty) {
          throw const FormatException(
            'Missing required field: pushNotificationConfig',
          );
        }

        context.upsertA2aPushConfig(route.appName, taskId, pushConfig);
        final Map<String, Object?> result = <String, Object?>{
          'taskId': taskId,
          'task_id': taskId,
          'pushNotificationConfig': pushConfig,
          'push_notification_config': pushConfig,
        };
        await _writeA2aSuccess(
          request,
          context,
          id: id,
          jsonRpcEnvelope: useJsonRpcEnvelope,
          result: result,
        );
        return;
      case 'tasks/pushnotificationconfig/get':
        final String taskId = _readString(params, const <String>[
          'taskId',
          'task_id',
          'id',
        ], required: true);
        final Map<String, Object?>? task = context.readA2aTask(
          route.appName,
          taskId,
        );
        if (task == null) {
          await _writeA2aError(
            request,
            context,
            id: id,
            jsonRpcEnvelope: useJsonRpcEnvelope,
            jsonRpcCode: -32004,
            statusCode: HttpStatus.notFound,
            message: 'A2A task not found: $taskId',
          );
          return;
        }

        final Map<String, Object?>? pushConfig = context.readA2aPushConfig(
          route.appName,
          taskId,
        );
        if (pushConfig == null) {
          await _writeA2aError(
            request,
            context,
            id: id,
            jsonRpcEnvelope: useJsonRpcEnvelope,
            jsonRpcCode: -32004,
            statusCode: HttpStatus.notFound,
            message: 'A2A push notification config not found for task: $taskId',
          );
          return;
        }

        final Map<String, Object?> result = <String, Object?>{
          'taskId': taskId,
          'task_id': taskId,
          'pushNotificationConfig': pushConfig,
          'push_notification_config': pushConfig,
        };
        await _writeA2aSuccess(
          request,
          context,
          id: id,
          jsonRpcEnvelope: useJsonRpcEnvelope,
          result: result,
        );
        return;
      case 'tasks/resubscribe':
        final String taskId = _readString(params, const <String>[
          'taskId',
          'task_id',
          'id',
        ], required: true);
        final Map<String, Object?>? task = context.readA2aTask(
          route.appName,
          taskId,
        );
        if (task == null) {
          await _writeA2aError(
            request,
            context,
            id: id,
            jsonRpcEnvelope: useJsonRpcEnvelope,
            jsonRpcCode: -32004,
            statusCode: HttpStatus.notFound,
            message: 'A2A task not found: $taskId',
          );
          return;
        }

        final List<Map<String, Object?>> updates = context.readA2aTaskUpdates(
          route.appName,
          taskId,
        );
        await _writeA2aSseTaskReplay(
          request,
          context,
          id: id,
          jsonRpcEnvelope: useJsonRpcEnvelope,
          task: task,
          updates: updates,
        );
        return;
      default:
        await _writeA2aError(
          request,
          context,
          id: id,
          jsonRpcEnvelope: useJsonRpcEnvelope,
          jsonRpcCode: -32601,
          statusCode: HttpStatus.notFound,
          message: 'A2A JSON-RPC method not found: $method',
        );
        return;
    }
  } on FormatException catch (error) {
    await _writeA2aError(
      request,
      context,
      id: id,
      jsonRpcEnvelope: useJsonRpcEnvelope,
      jsonRpcCode: -32602,
      statusCode: HttpStatus.badRequest,
      message: error.message,
    );
  } on ArgumentError catch (error) {
    await _writeA2aError(
      request,
      context,
      id: id,
      jsonRpcEnvelope: useJsonRpcEnvelope,
      jsonRpcCode: -32602,
      statusCode: HttpStatus.badRequest,
      message: '${error.message}',
    );
  } catch (error) {
    await _writeA2aError(
      request,
      context,
      id: id,
      jsonRpcEnvelope: useJsonRpcEnvelope,
      jsonRpcCode: -32000,
      statusCode: HttpStatus.internalServerError,
      message: 'A2A RPC execution failed: $error',
    );
  }
}

Future<void> _writeA2aSuccess(
  HttpRequest request,
  _AdkDevWebContext context, {
  required Object? id,
  required bool jsonRpcEnvelope,
  required Object? result,
}) async {
  if (jsonRpcEnvelope) {
    await _writeJson(
      request,
      context,
      payload: _a2aJsonRpcSuccess(id: id, result: result),
    );
    return;
  }
  await _writeJson(request, context, payload: result ?? <String, Object?>{});
}

Future<void> _writeA2aError(
  HttpRequest request,
  _AdkDevWebContext context, {
  required Object? id,
  required bool jsonRpcEnvelope,
  required int jsonRpcCode,
  required int statusCode,
  required String message,
}) async {
  if (jsonRpcEnvelope) {
    await _writeJson(
      request,
      context,
      payload: _a2aJsonRpcError(id: id, code: jsonRpcCode, message: message),
    );
    return;
  }
  await _writeError(request, context, statusCode: statusCode, message: message);
}

Future<void> _writeA2aSseTaskReplay(
  HttpRequest request,
  _AdkDevWebContext context, {
  required Object? id,
  required bool jsonRpcEnvelope,
  required Map<String, Object?> task,
  required List<Map<String, Object?>> updates,
}) async {
  final HttpResponse response = request.response;
  _setCorsHeaders(request, response, context);
  response.statusCode = HttpStatus.ok;
  response.headers.contentType = ContentType(
    'text',
    'event-stream',
    charset: 'utf-8',
  );
  response.headers.set('Cache-Control', 'no-cache');
  response.headers.set('Connection', 'keep-alive');

  final List<Map<String, Object?>> streamItems = <Map<String, Object?>>[
    task,
    ...updates,
  ];
  for (final Map<String, Object?> item in streamItems) {
    final Object payload =
        jsonRpcEnvelope ? _a2aJsonRpcSuccess(id: id, result: item) : item;
    response.write('data: ${jsonEncode(payload)}\n\n');
    await response.flush();
  }

  await response.close();
}

Future<_A2aExecutionResult> _executeA2aMessageSend(
  _AdkDevWebContext context, {
  required String appName,
  required Map<String, dynamic> params,
}) async {
  final Map<String, dynamic> messageJson = params['message'] is Map
      ? _toDynamicMap(params['message'])
      : params;
  final A2aMessage message = _a2aMessageFromJson(messageJson);
  if (message.parts.isEmpty) {
    throw const FormatException(
      'A2A request message must contain at least one part.',
    );
  }

  final String requestedTaskId = (message.taskId ?? '').trim();
  final Map<String, Object?>? storedTask = requestedTaskId.isEmpty
      ? null
      : context.readA2aTask(appName, requestedTaskId);
  final A2aTask? currentTask = storedTask == null
      ? null
      : _a2aTaskFromJson(_toDynamicMap(storedTask));

  final String contextId = (message.contextId ?? '').trim().isNotEmpty
      ? message.contextId!.trim()
      : (currentTask?.contextId.trim().isNotEmpty ?? false)
      ? currentTask!.contextId.trim()
      : 'a2a_ctx_${DateTime.now().microsecondsSinceEpoch}';
  final String taskId = requestedTaskId.isNotEmpty
      ? requestedTaskId
      : 'a2a_task_${DateTime.now().microsecondsSinceEpoch}';

  message.contextId = contextId;
  message.taskId = taskId;

  final Runner runner = await context.getRunner(appName);
  final A2aAgentExecutor executor = A2aAgentExecutor(runner: runner);
  final InMemoryA2aEventQueue eventQueue = InMemoryA2aEventQueue();
  await executor.execute(
    A2aRequestContext(
      taskId: taskId,
      contextId: contextId,
      message: message,
      currentTask: currentTask,
    ),
    eventQueue,
  );
  await eventQueue.close();

  final Map<String, Object?> task = _a2aTaskFromEvents(
    taskId: taskId,
    contextId: contextId,
    events: eventQueue.events,
  );
  final List<Map<String, Object?>> updates = eventQueue.events
      .map<Map<String, Object?>>(_a2aEventToJson)
      .toList(growable: false);
  context.upsertA2aTask(appName, task);
  context.upsertA2aTaskUpdates(appName, taskId, updates);
  final Map<String, Object?>? pushConfig = context.readA2aPushConfig(
    appName,
    taskId,
  );
  if (pushConfig != null && updates.isNotEmpty) {
    unawaited(
      context.enqueueA2aPushNotifications(
        appName: appName,
        taskId: taskId,
        pushConfig: pushConfig,
        task: task,
        updates: updates,
      ),
    );
  }

  final Map<String, Object?> status = _toObjectMap(task['status']);
  final Map<String, Object?> statusMessage = _toObjectMap(status['message']);
  final Map<String, Object?> messageResult = _ensureA2aMessageIdentity(
    statusMessage.isNotEmpty ? statusMessage : _a2aFallbackMessage(task),
    taskId: taskId,
    contextId: contextId,
  );

  return _A2aExecutionResult(
    message: messageResult,
    task: task,
    updates: updates,
  );
}

Map<String, Object?> _a2aEventToJson(A2aEvent event) {
  if (event is A2aTaskStatusUpdateEvent) {
    return <String, Object?>{
      'kind': 'task_status_update',
      if (event.taskId != null) 'taskId': event.taskId,
      if (event.taskId != null) 'task_id': event.taskId,
      if (event.contextId != null) 'contextId': event.contextId,
      if (event.contextId != null) 'context_id': event.contextId,
      'status': _a2aTaskStatusToJson(event.status),
      'final': event.finalEvent,
      if (event.metadata.isNotEmpty)
        'metadata': Map<String, Object?>.from(event.metadata),
    };
  }

  if (event is A2aTaskArtifactUpdateEvent) {
    return <String, Object?>{
      'kind': 'task_artifact_update',
      if (event.taskId != null) 'taskId': event.taskId,
      if (event.taskId != null) 'task_id': event.taskId,
      if (event.contextId != null) 'contextId': event.contextId,
      if (event.contextId != null) 'context_id': event.contextId,
      'lastChunk': event.lastChunk,
      'last_chunk': event.lastChunk,
      'append': event.append,
      'artifact': _a2aArtifactToJson(event.artifact),
    };
  }

  return <String, Object?>{'kind': 'unknown'};
}

/// Resolved push-delivery target for A2A background updates.
class _A2aPushTarget {
  /// Creates an A2A push delivery target.
  const _A2aPushTarget({
    required this.uri,
    required this.headers,
    required this.authHeader,
    required this.policy,
  });

  /// Destination webhook URI.
  final Uri uri;

  /// Additional HTTP headers.
  final Map<String, String> headers;

  /// Optional `Authorization` header value.
  final String? authHeader;

  /// Retry and timeout policy for delivery.
  final A2aPushDeliveryPolicy policy;
}

_A2aPushTarget? _resolveA2aPushTarget(Map<String, Object?> pushConfig) {
  final String? url = _resolveA2aPushUrl(pushConfig);
  if (url == null || url.isEmpty) {
    return null;
  }
  final Uri? uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) {
    return null;
  }
  final String scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return null;
  }
  return _A2aPushTarget(
    uri: uri,
    headers: _resolveA2aPushHeaders(pushConfig),
    authHeader: _resolveA2aPushAuthorization(pushConfig),
    policy: _resolveA2aPushPolicy(pushConfig),
  );
}

A2aPushDeliveryPolicy _resolveA2aPushPolicy(Map<String, Object?> pushConfig) {
  final Map<String, dynamic> dynamicPushConfig = _toDynamicMap(pushConfig);
  final Map<String, Object?> retry =
      _readObjectMap(dynamicPushConfig, const <String>[
        'retry',
        'retryPolicy',
        'retry_policy',
      ]) ??
      <String, Object?>{};
  final int maxAttempts = _readPositiveInt(
    retry['maxAttempts'] ??
        retry['max_attempts'] ??
        pushConfig['maxAttempts'] ??
        pushConfig['max_attempts'],
    fallback: 5,
    min: 1,
    max: 32,
  );
  final int baseDelayMs = _readPositiveInt(
    retry['initialDelayMs'] ??
        retry['initial_delay_ms'] ??
        retry['baseDelayMs'] ??
        retry['base_delay_ms'] ??
        pushConfig['initialDelayMs'] ??
        pushConfig['initial_delay_ms'],
    fallback: 1000,
    min: 1,
    max: 60000,
  );
  final int maxDelayMs = _readPositiveInt(
    retry['maxDelayMs'] ??
        retry['max_delay_ms'] ??
        pushConfig['maxDelayMs'] ??
        pushConfig['max_delay_ms'],
    fallback: 60000,
    min: 1,
    max: 300000,
  );
  final int requestTimeoutMs = _readPositiveInt(
    retry['requestTimeoutMs'] ??
        retry['request_timeout_ms'] ??
        pushConfig['requestTimeoutMs'] ??
        pushConfig['request_timeout_ms'],
    fallback: 10000,
    min: 100,
    max: 300000,
  );
  return A2aPushDeliveryPolicy(
    maxAttempts: maxAttempts,
    baseDelayMs: baseDelayMs,
    maxDelayMs: maxDelayMs < baseDelayMs ? baseDelayMs : maxDelayMs,
    requestTimeoutMs: requestTimeoutMs,
  );
}

int _readPositiveInt(
  Object? value, {
  required int fallback,
  required int min,
  int? max,
}) {
  int? parsed;
  if (value is int) {
    parsed = value;
  } else if (value is num) {
    parsed = value.toInt();
  } else if (value is String) {
    parsed = int.tryParse(value.trim());
  }
  if (parsed == null || parsed < min) {
    return fallback;
  }
  if (max != null && parsed > max) {
    return max;
  }
  return parsed;
}

Future<void> _postA2aPushNotification({
  required Uri uri,
  required Map<String, String> headers,
  required String? authHeader,
  required Map<String, Object?> task,
  required Map<String, Object?> update,
  required int requestTimeoutMs,
}) async {
  final HttpClient client = HttpClient();
  try {
    final Duration timeout = Duration(milliseconds: requestTimeoutMs);
    final HttpClientRequest request = await client
        .postUrl(uri)
        .timeout(timeout);
    request.headers.contentType = ContentType.json;
    headers.forEach((String key, String value) {
      request.headers.set(key, value);
    });
    if (authHeader != null && authHeader.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, authHeader);
    }
    request.write(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'method': 'tasks/pushNotification',
        'params': <String, Object?>{
          'task': task,
          'update': update,
          'taskId': '${task['id'] ?? task['taskId'] ?? task['task_id'] ?? ''}',
        },
      }),
    );
    final HttpClientResponse response = await request.close().timeout(timeout);
    await response.drain<Object?>();
    if (response.statusCode < HttpStatus.ok ||
        response.statusCode >= HttpStatus.multipleChoices) {
      throw HttpException(
        'A2A push callback returned HTTP ${response.statusCode}',
        uri: uri,
      );
    }
  } finally {
    client.close(force: true);
  }
}

String? _resolveA2aPushUrl(Map<String, Object?> pushConfig) {
  for (final String key in const <String>[
    'url',
    'endpoint',
    'webhook',
    'webhook_url',
    'webhookUrl',
  ]) {
    final Object? raw = pushConfig[key];
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
    }
  }
  return null;
}

Map<String, String> _resolveA2aPushHeaders(Map<String, Object?> pushConfig) {
  final Object? rawHeaders = pushConfig['headers'];
  if (rawHeaders is! Map) {
    return <String, String>{};
  }
  final Map<String, String> headers = <String, String>{};
  rawHeaders.forEach((Object? key, Object? value) {
    final String normalizedKey = '$key'.trim();
    final String normalizedValue = '$value'.trim();
    if (normalizedKey.isEmpty || normalizedValue.isEmpty) {
      return;
    }
    headers[normalizedKey] = normalizedValue;
  });
  return headers;
}

String? _resolveA2aPushAuthorization(Map<String, Object?> pushConfig) {
  final Object? rawAuth =
      pushConfig['authentication'] ?? pushConfig['auth'] ?? pushConfig['token'];
  if (rawAuth is String && rawAuth.trim().isNotEmpty) {
    return rawAuth.trim();
  }
  if (rawAuth is! Map) {
    return null;
  }
  final Map<String, dynamic> auth = _toDynamicMap(rawAuth);
  final String token = _readString(auth, const <String>[
    'token',
    'accessToken',
    'access_token',
  ]);
  if (token.isEmpty) {
    return null;
  }
  final String scheme = _readString(auth, const <String>[
    'scheme',
    'type',
  ], fallback: 'Bearer');
  return '${scheme.isEmpty ? 'Bearer' : scheme} $token';
}

Map<String, Object?> _a2aTaskFromEvents({
  required String taskId,
  required String contextId,
  required List<A2aEvent> events,
}) {
  A2aTaskStatus status = A2aTaskStatus(state: A2aTaskState.completed);
  final List<Map<String, Object?>> history = <Map<String, Object?>>[];
  final List<Map<String, Object?>> artifacts = <Map<String, Object?>>[];

  for (final A2aEvent event in events) {
    if (event is A2aTaskStatusUpdateEvent) {
      status = event.status;
      final A2aMessage? message = event.status.message;
      if (message != null) {
        history.add(_a2aMessageToJson(message));
      }
      continue;
    }
    if (event is A2aTaskArtifactUpdateEvent) {
      artifacts.add(_a2aArtifactToJson(event.artifact));
    }
  }

  final Map<String, Object?> statusJson = _a2aTaskStatusToJson(status);
  if (_toObjectMap(statusJson['message']).isEmpty && artifacts.isNotEmpty) {
    final Map<String, Object?> lastArtifact = artifacts.last;
    final List<Object?> partsRaw = lastArtifact['parts'] is List
        ? List<Object?>.from(lastArtifact['parts'] as List)
        : const <Object?>[];
    final List<A2aPart> parts = partsRaw
        .whereType<Map>()
        .map((Map value) => _a2aPartFromJson(_toDynamicMap(value)))
        .toList(growable: false);
    statusJson['message'] = _a2aMessageToJson(
      A2aMessage(
        messageId: 'a2a_msg_${DateTime.now().microsecondsSinceEpoch}',
        role: A2aRole.agent,
        taskId: taskId,
        contextId: contextId,
        parts: parts,
      ),
    );
  }

  return <String, Object?>{
    'kind': 'task',
    'id': taskId,
    'taskId': taskId,
    'task_id': taskId,
    'contextId': contextId,
    'context_id': contextId,
    'status': statusJson,
    'history': history,
    'artifacts': artifacts,
  };
}

Map<String, Object?> _a2aFallbackMessage(Map<String, Object?> task) {
  final String taskId =
      '${task['id'] ?? task['taskId'] ?? task['task_id'] ?? ''}';
  final String contextId = '${task['contextId'] ?? task['context_id'] ?? ''}'
      .trim();
  return _a2aMessageToJson(
    A2aMessage(
      messageId: 'a2a_msg_${DateTime.now().microsecondsSinceEpoch}',
      role: A2aRole.agent,
      taskId: taskId.isEmpty ? null : taskId,
      contextId: contextId.isEmpty ? null : contextId,
      parts: <A2aPart>[A2aPart.text('')],
    ),
  );
}

Map<String, Object?> _ensureA2aMessageIdentity(
  Map<String, Object?> message, {
  required String taskId,
  required String contextId,
}) {
  final Map<String, Object?> normalized = Map<String, Object?>.from(message);
  final String currentTaskId =
      '${normalized['taskId'] ?? normalized['task_id'] ?? ''}'.trim();
  final String currentContextId =
      '${normalized['contextId'] ?? normalized['context_id'] ?? ''}'.trim();
  if (currentTaskId.isEmpty && taskId.isNotEmpty) {
    normalized['taskId'] = taskId;
    normalized['task_id'] = taskId;
  }
  if (currentContextId.isEmpty && contextId.isNotEmpty) {
    normalized['contextId'] = contextId;
    normalized['context_id'] = contextId;
  }
  return normalized;
}

A2aTask _a2aTaskFromJson(Map<String, dynamic> json) {
  final String taskId = _readString(json, const <String>[
    'id',
    'taskId',
    'task_id',
  ]);
  final String contextId = _readString(json, const <String>[
    'contextId',
    'context_id',
  ]);
  final List<A2aMessage> history = json['history'] is List
      ? (json['history'] as List<Object?>)
            .whereType<Map>()
            .map((Map value) => _a2aMessageFromJson(_toDynamicMap(value)))
            .toList(growable: false)
      : const <A2aMessage>[];
  final List<A2aArtifact> artifacts = json['artifacts'] is List
      ? (json['artifacts'] as List<Object?>)
            .whereType<Map>()
            .map((Map value) => _a2aArtifactFromJson(_toDynamicMap(value)))
            .toList(growable: false)
      : const <A2aArtifact>[];
  return A2aTask(
    id: taskId,
    contextId: contextId,
    status: _a2aTaskStatusFromJson(_toDynamicMap(json['status'])),
    history: history,
    artifacts: artifacts,
    metadata: _toObjectMap(json['metadata']),
  );
}

A2aTaskStatus _a2aTaskStatusFromJson(Map<String, dynamic> json) {
  return A2aTaskStatus(
    state: _a2aTaskStateFromWire(
      _readString(json, const <String>['state'], fallback: 'completed'),
    ),
    message: json['message'] is Map
        ? _a2aMessageFromJson(_toDynamicMap(json['message']))
        : null,
    timestamp: _nullableString(json, const <String>['timestamp']),
  );
}

A2aTaskState _a2aTaskStateFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'submitted':
      return A2aTaskState.submitted;
    case 'working':
      return A2aTaskState.working;
    case 'input_required':
    case 'inputrequired':
      return A2aTaskState.inputRequired;
    case 'auth_required':
    case 'authrequired':
      return A2aTaskState.authRequired;
    case 'failed':
      return A2aTaskState.failed;
    case 'completed':
      return A2aTaskState.completed;
    case 'canceled':
    case 'cancelled':
      return A2aTaskState.canceled;
  }
  return A2aTaskState.completed;
}

Map<String, Object?> _a2aTaskStatusToJson(A2aTaskStatus status) {
  return <String, Object?>{
    'state': _a2aTaskStateToWire(status.state),
    'timestamp': status.timestamp,
    if (status.message != null) 'message': _a2aMessageToJson(status.message!),
  };
}

String _a2aTaskStateToWire(A2aTaskState state) {
  switch (state) {
    case A2aTaskState.submitted:
      return 'submitted';
    case A2aTaskState.working:
      return 'working';
    case A2aTaskState.inputRequired:
      return 'input_required';
    case A2aTaskState.authRequired:
      return 'auth_required';
    case A2aTaskState.failed:
      return 'failed';
    case A2aTaskState.completed:
      return 'completed';
    case A2aTaskState.canceled:
      return 'canceled';
    case A2aTaskState.rejected:
      return 'rejected';
    case A2aTaskState.unknown:
      return 'unknown';
  }
}

Map<String, Object?> _a2aArtifactToJson(A2aArtifact artifact) {
  return <String, Object?>{
    'kind': 'artifact',
    'artifactId': artifact.artifactId,
    'artifact_id': artifact.artifactId,
    'parts': artifact.parts
        .map<Map<String, Object?>>(_a2aPartToJson)
        .toList(growable: false),
  };
}

A2aArtifact _a2aArtifactFromJson(Map<String, dynamic> json) {
  return A2aArtifact(
    artifactId: _readString(json, const <String>[
      'artifactId',
      'artifact_id',
      'id',
    ]),
    parts: _a2aPartsFromJson(json['parts']),
  );
}

Map<String, Object?> _a2aMessageToJson(A2aMessage message) {
  return <String, Object?>{
    'kind': 'message',
    'messageId': message.messageId,
    'message_id': message.messageId,
    'role': message.role == A2aRole.user ? 'user' : 'agent',
    if (message.taskId != null) 'taskId': message.taskId,
    if (message.taskId != null) 'task_id': message.taskId,
    if (message.contextId != null) 'contextId': message.contextId,
    if (message.contextId != null) 'context_id': message.contextId,
    'parts': message.parts
        .map<Map<String, Object?>>(_a2aPartToJson)
        .toList(growable: false),
  };
}

A2aMessage _a2aMessageFromJson(Map<String, dynamic> json) {
  final String messageId = _readString(json, const <String>[
    'messageId',
    'message_id',
    'id',
  ], fallback: 'a2a_msg_${DateTime.now().microsecondsSinceEpoch}');
  final String roleRaw = _readString(json, const <String>[
    'role',
  ], fallback: 'user');
  final List<A2aPart> parts = _a2aPartsFromJson(json['parts']);
  return A2aMessage(
    messageId: messageId,
    role: roleRaw.toLowerCase() == 'agent' ? A2aRole.agent : A2aRole.user,
    taskId: _nullableString(json, const <String>['taskId', 'task_id']),
    contextId: _nullableString(json, const <String>['contextId', 'context_id']),
    parts: parts,
    metadata: _toObjectMap(json['metadata']),
  );
}

List<A2aPart> _a2aPartsFromJson(Object? raw) {
  if (raw is! List) {
    return const <A2aPart>[];
  }
  final List<A2aPart> parts = <A2aPart>[];
  for (final Object? item in raw) {
    if (item is! Map) {
      continue;
    }
    parts.add(_a2aPartFromJson(_toDynamicMap(item)));
  }
  return parts;
}

A2aPart _a2aPartFromJson(Map<String, dynamic> json) {
  final Map<String, Object?> metadata = _toObjectMap(json['metadata']);
  final String kind = _readString(json, const <String>[
    'kind',
  ], fallback: '').toLowerCase();

  if (kind == 'data') {
    return A2aPart.data(_toObjectMap(json['data']), metadata: metadata);
  }

  if (kind == 'file') {
    final Map<String, dynamic> file = _toDynamicMap(json['file']);
    final String? mimeType = _nullableString(file, const <String>[
      'mimeType',
      'mime_type',
    ]);
    final String? uri = _nullableString(file, const <String>['uri', 'url']);
    if (uri != null && uri.isNotEmpty) {
      return A2aPart.fileUri(uri, mimeType: mimeType, metadata: metadata);
    }
    final String bytes = _readString(file, const <String>[
      'bytes',
    ], fallback: '');
    return A2aPart.fileBytes(bytes, mimeType: mimeType, metadata: metadata);
  }

  final String text = _readString(json, const <String>['text'], fallback: '');
  return A2aPart.text(text, metadata: metadata);
}

Map<String, Object?> _a2aPartToJson(A2aPart part) {
  final Map<String, Object?> metadata = Map<String, Object?>.from(
    part.root.metadata,
  );
  final A2aTextPart? textPart = part.textPart;
  if (textPart != null) {
    return <String, Object?>{
      'kind': 'text',
      'text': textPart.text,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  final A2aDataPart? dataPart = part.dataPart;
  if (dataPart != null) {
    return <String, Object?>{
      'kind': 'data',
      'data': Map<String, Object?>.from(dataPart.data),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  final A2aFilePart? filePart = part.filePart;
  if (filePart != null) {
    final A2aFile file = filePart.file;
    if (file is A2aFileWithUri) {
      return <String, Object?>{
        'kind': 'file',
        'file': <String, Object?>{
          'uri': file.uri,
          if (file.mimeType != null) 'mimeType': file.mimeType,
          if (file.mimeType != null) 'mime_type': file.mimeType,
        },
        if (metadata.isNotEmpty) 'metadata': metadata,
      };
    }
    if (file is A2aFileWithBytes) {
      return <String, Object?>{
        'kind': 'file',
        'file': <String, Object?>{
          'bytes': file.bytes,
          if (file.mimeType != null) 'mimeType': file.mimeType,
          if (file.mimeType != null) 'mime_type': file.mimeType,
        },
        if (metadata.isNotEmpty) 'metadata': metadata,
      };
    }
  }

  return <String, Object?>{
    'kind': 'text',
    'text': '',
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

String _normalizeA2aRpcMethod(String raw) {
  final String normalized =
      raw.trim().toLowerCase().replaceAll(':', '/').replaceAll('.', '/');
  if (normalized == 'tasks/push_notification_config/get' ||
      normalized == 'tasks/push_notification_configs/get') {
    return 'tasks/pushnotificationconfig/get';
  }
  if (normalized == 'tasks/push_notification_config/set' ||
      normalized == 'tasks/push_notification_configs/set') {
    return 'tasks/pushnotificationconfig/set';
  }
  return normalized;
}

Map<String, Object?> _a2aJsonRpcSuccess({required Object? id, Object? result}) {
  return <String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result};
}

Map<String, Object?> _a2aJsonRpcError({
  required Object? id,
  required int code,
  required String message,
  Object? data,
}) {
  final Map<String, Object?> error = <String, Object?>{
    'code': code,
    'message': message,
  };
  if (data != null) {
    error['data'] = data;
  }
  return <String, Object?>{'jsonrpc': '2.0', 'id': id, 'error': error};
}

Map<String, Object?> _toObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}
