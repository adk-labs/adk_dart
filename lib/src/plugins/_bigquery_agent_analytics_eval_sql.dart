/// Builds the eval SQL of the BigQuery agent analytics plugin.
library;

/// Payload columns eligible for physical projection.
const Set<String> projectablePayloadColumns = <String>{
  'content',
  'content_parts',
  'attributes',
  'latency_ms',
};

/// Validates [denylist] and returns the immutable denied column set.
///
/// Throws an [ArgumentError] if any entry is not in [projectablePayloadColumns].
Set<String> validatePayloadColumnDenylist(Iterable<String>? denylist) {
  final Set<String> denied = Set<String>.unmodifiable(
    denylist ?? const <String>[],
  );
  final List<String> invalid =
      denied
          .where((String col) => !projectablePayloadColumns.contains(col))
          .toList()
        ..sort();
  if (invalid.isNotEmpty) {
    final List<String> allowed = projectablePayloadColumns.toList()..sort();
    throw ArgumentError(
      'payload_column_denylist may only contain projectable payload columns '
      '$allowed; got $invalid. Identity/correlation columns (timestamp, '
      'event_type, session_id, invocation_id, trace_id, span_id, '
      'parent_span_id, is_truncated, ...) are protected and cannot be '
      'projected out.',
    );
  }
  return denied;
}

/// Characters that cannot appear in a backtick-quoted BigQuery table or view ID.
final RegExp evalTableIdUnquotableRe = RegExp(
  r'[`\\\x00-\x1f\x7f-\x9f\u2028\u2029]',
);

final RegExp _evalSqlLeadingWhereRe = RegExp(
  r'^WHERE(?:\s+|\b)',
  caseSensitive: false,
);

final RegExp _evalSqlOpeningQuoteRe = RegExp("^('''|\"\"\"|['\"`])");

String _evalViewDatasetRef(
  String fullTableId,
  Set<String> deniedColumns, [
  String viewPrefix = 'v',
]) {
  validatePayloadColumnDenylist(deniedColumns);
  if (deniedColumns.contains('content')) {
    throw ArgumentError(
      "Cannot build eval view SQL when 'content' is in "
      'payload_column_denylist.',
    );
  }
  final int dotIndex = fullTableId.lastIndexOf('.');
  final String datasetRef = dotIndex > 0
      ? fullTableId.substring(0, dotIndex)
      : '';
  final String table = dotIndex >= 0 ? fullTableId.substring(dotIndex + 1) : '';
  if (datasetRef.isEmpty || table.isEmpty) {
    throw ArgumentError(
      'full_table_id must be a dataset-qualified table name such as '
      "'project.dataset.table'; got '$fullTableId'.",
    );
  }
  if (evalTableIdUnquotableRe.hasMatch(fullTableId)) {
    throw ArgumentError(
      'full_table_id must not contain a backtick, backslash, control or '
      'line-break character, because the SQL quotes it in backticks; got '
      "'$fullTableId'.",
    );
  }
  if (viewPrefix.isEmpty || evalTableIdUnquotableRe.hasMatch(viewPrefix)) {
    throw ArgumentError(
      'view_prefix must be a non-empty string without a backtick, backslash, '
      "control or line-break character; got '$viewPrefix'.",
    );
  }
  return datasetRef;
}

String _blankEvalSqlComments(String clause, String paramName) {
  final StringBuffer parts = StringBuffer();
  int start = 0;
  while (start < clause.length) {
    if (clause.startsWith('--', start) || clause.startsWith('#', start)) {
      int end = clause.indexOf('\n', start);
      if (end < 0) {
        end = clause.length;
      }
      parts.write(' ' * (end - start));
      start = end;
    } else if (clause.startsWith('/*', start)) {
      int end = clause.indexOf('*/', start + 2);
      if (end < 0) {
        throw ArgumentError(
          "$paramName has an unterminated block comment; got '$clause'.",
        );
      }
      end += 2;
      parts.write(' ' * (end - start));
      start = end;
    } else {
      int end = start + 1;
      final RegExpMatch? opening = _evalSqlOpeningQuoteRe.firstMatch(
        clause.substring(start),
      );
      if (opening != null) {
        final String quote = opening.group(0)!;
        end = start + quote.length;
        while (!clause.startsWith(quote, end)) {
          if (end >= clause.length) {
            final String token = quote == '`'
                ? 'quoted identifier'
                : 'string literal';
            throw ArgumentError(
              "$paramName has an unterminated $token; got '$clause'.",
            );
          }
          end += clause[end] == r'\' ? 2 : 1;
        }
        end += quote.length;
      }
      parts.write(clause.substring(start, end));
      start = end;
    }
  }
  return parts.toString();
}

bool _isWhitespaceChar(String ch) => ch.trim().isEmpty;

String _normalizeEvalWhereCondition(String clause, String paramName) {
  if (clause.trim().isEmpty) {
    return '';
  }
  final String code = _blankEvalSqlComments(clause, paramName);
  int start = 0;
  while (start < code.length && _isWhitespaceChar(code[start])) {
    start += 1;
  }
  final Set<int> dropped = <int>{};
  final RegExpMatch? match = _evalSqlLeadingWhereRe.firstMatch(
    clause.substring(start),
  );
  if (match != null) {
    final int matchEnd = start + match.end;
    for (int i = start; i < matchEnd; i += 1) {
      dropped.add(i);
    }
    start = matchEnd;
  }
  int end = code.length;
  while (end > start &&
      (_isWhitespaceChar(code[end - 1]) || code[end - 1] == ';')) {
    end -= 1;
    if (code[end] == ';') {
      dropped.add(end);
    }
  }
  if (end == start) {
    throw ArgumentError("$paramName has no condition; got '$clause'.");
  }
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < clause.length; i += 1) {
    if (!dropped.contains(i)) {
      buffer.write(clause[i]);
    }
  }
  return buffer.toString().trim();
}

String _formatEvalRawWhereClause(String rawWhereClause) {
  final String condition = _normalizeEvalWhereCondition(
    rawWhereClause,
    'raw_where_clause',
  );
  if (condition.isEmpty) {
    return '';
  }
  return '\n      AND (\n        $condition\n      )';
}

String _formatEvalOuterWhereClause(String whereClause) {
  final String condition = _normalizeEvalWhereCondition(
    whereClause,
    'where_clause',
  );
  if (condition.isEmpty) {
    return '';
  }
  return '\nWHERE\n  (\n    $condition\n  )';
}

String _buildEvalViewCtes({
  required String fullTableId,
  required Set<String> deniedColumns,
  required String scopeColumns,
  String rawWhereClause = '',
}) {
  final String contentPartsColumn = deniedColumns.contains('content_parts')
      ? 'ARRAY<STRUCT<part_index INT64, mime_type STRING, text STRING, '
            'part_attributes STRING, storage_mode STRING>>[] AS content_parts'
      : 'content_parts';
  final String attributesColumn = deniedColumns.contains('attributes')
      ? 'CAST(NULL AS JSON) AS attributes'
      : 'attributes';
  final String latencyMsColumn = deniedColumns.contains('latency_ms')
      ? 'CAST(NULL AS JSON) AS latency_ms'
      : 'latency_ms';
  final String formattedRawWhere = _formatEvalRawWhereClause(rawWhereClause);

  return _evalViewCtesTemplate
      .replaceAll('{full_table_id}', fullTableId)
      .replaceAll('{content_parts_column}', contentPartsColumn)
      .replaceAll('{attributes_column}', attributesColumn)
      .replaceAll('{latency_ms_column}', latencyMsColumn)
      .replaceAll('{scope_columns}', scopeColumns)
      .replaceAll('{raw_where_clause}', formattedRawWhere)
      .replaceFirst(RegExp(r'\n+$'), '');
}

/// Builds the `{viewPrefix}_eval_session` view DDL.
String buildEvalSessionViewSql(
  String fullTableId, {
  String viewPrefix = 'v',
  Iterable<String>? deniedColumns,
}) {
  final Set<String> denied = validatePayloadColumnDenylist(deniedColumns);
  final String datasetRef = _evalViewDatasetRef(
    fullTableId,
    denied,
    viewPrefix,
  );
  final String viewRef = '$datasetRef.${viewPrefix}_eval_session';
  final String querySql = buildEvalSessionQuerySql(
    fullTableId,
    deniedColumns: denied,
  );
  return 'CREATE OR REPLACE VIEW `$viewRef` AS\n$querySql';
}

/// Builds the `{viewPrefix}_eval_turn` view DDL.
String buildEvalTurnViewSql(
  String fullTableId, {
  String viewPrefix = 'v',
  Iterable<String>? deniedColumns,
}) {
  final Set<String> denied = validatePayloadColumnDenylist(deniedColumns);
  final String datasetRef = _evalViewDatasetRef(
    fullTableId,
    denied,
    viewPrefix,
  );
  final String viewRef = '$datasetRef.${viewPrefix}_eval_turn';
  final String querySql = buildEvalTurnQuerySql(
    fullTableId,
    deniedColumns: denied,
  );
  return 'CREATE OR REPLACE VIEW `$viewRef` AS\n$querySql';
}

/// Builds a query that reads the rows of the `eval_session` view.
String buildEvalSessionQuerySql(
  String fullTableId, {
  Iterable<String>? deniedColumns,
  String whereClause = '',
  String rawWhereClause = '',
}) {
  final Set<String> denied = validatePayloadColumnDenylist(deniedColumns);
  _evalViewDatasetRef(fullTableId, denied);
  final String ctes = _buildEvalViewCtes(
    fullTableId: fullTableId,
    deniedColumns: denied,
    scopeColumns: 'session_id',
    rawWhereClause: rawWhereClause,
  );
  final String formattedWhere = _formatEvalOuterWhereClause(whereClause);
  return _evalSessionQueryTemplate
      .replaceAll('{ctes}', ctes)
      .replaceAll('{where_clause}', formattedWhere);
}

/// Builds a query that reads the rows of the `eval_turn` view.
String buildEvalTurnQuerySql(
  String fullTableId, {
  Iterable<String>? deniedColumns,
  String whereClause = '',
  String rawWhereClause = '',
}) {
  final Set<String> denied = validatePayloadColumnDenylist(deniedColumns);
  _evalViewDatasetRef(fullTableId, denied);
  final String ctes = _buildEvalViewCtes(
    fullTableId: fullTableId,
    deniedColumns: denied,
    scopeColumns: 'session_id, invocation_id',
    rawWhereClause: rawWhereClause,
  );
  final String formattedWhere = _formatEvalOuterWhereClause(whereClause);
  return _evalTurnQueryTemplate
      .replaceAll('{ctes}', ctes)
      .replaceAll('{where_clause}', formattedWhere);
}

const String _evalViewCtesTemplate = r'''WITH
  -- The events of the sessions to read, one row per event.  Every later step
  -- reads these rows rather than the table, so a filter here narrows them all.
  RawEvents AS (
    SELECT
      timestamp,
      event_id,
      event_type,
      agent,
      session_id,
      invocation_id,
      user_id,
      content,
      {content_parts_column},
      {attributes_column},
      {latency_ms_column},
      status,
      error_message,
      is_truncated
    FROM
      `{full_table_id}`
    WHERE
      session_id IS NOT NULL
      AND invocation_id IS NOT NULL{raw_where_clause}
  ),
  -- Each event with the fields that later steps read parsed out of its JSON
  -- payload: its author, the tool name and args, whether the tool is a
  -- framework tool, the user text, the model response before it is unwrapped,
  -- and the token and latency numbers.
  TypedEvents AS (
    SELECT
      *,
      COALESCE(
        agent, JSON_VALUE(attributes, '$.root_agent_name'), 'root_agent'
      ) AS author,
      JSON_VALUE(content, '$.tool') AS tool_name,
      -- The framework tools are the transfer and the tools that pause the turn
      -- for a credential, a confirmation or input from the user.  The trace
      -- shows their AGENT_TRANSFER and HITL rows instead of their tool rows.
      -- A row that names no tool is not a framework tool.
      COALESCE(JSON_VALUE(content, '$.tool'), '') IN (
        'transfer_to_agent',
        'adk_request_credential',
        'adk_request_confirmation',
        'adk_request_input'
      ) AS is_framework_tool,
      TO_JSON_STRING(JSON_QUERY(content, '$.args')) AS tool_args_json,
      CASE
        WHEN event_type != 'USER_MESSAGE_RECEIVED' THEN NULL
        WHEN COALESCE(ARRAY_LENGTH(content_parts), 0) > 0 THEN (
          SELECT
            STRING_AGG(p.text, '\n' ORDER BY p.part_index)
          FROM
            UNNEST(content_parts) AS p
          WHERE
            p.mime_type = 'text/plain'
            AND COALESCE(p.storage_mode, 'INLINE') = 'INLINE'
            AND COALESCE(
              p.part_attributes, TO_JSON_STRING(JSON_OBJECT())
            ) = TO_JSON_STRING(JSON_OBJECT())
            AND p.text IS NOT NULL
            AND p.text NOT IN ('', '[BINARY DATA]', '[UPLOAD FAILED]')
        )
        WHEN NOT REGEXP_CONTAINS(
          COALESCE(
            JSON_VALUE(content, '$.text_summary'),
            JSON_VALUE(content, '$'),
            ''
          ),
          r'^Function response: '
        ) THEN NULLIF(
          COALESCE(
            JSON_VALUE(content, '$.text_summary'), JSON_VALUE(content, '$')
          ),
          ''
        )
        ELSE NULL
      END AS message_text,
      (
        event_type = 'USER_MESSAGE_RECEIVED'
        AND (
          REGEXP_CONTAINS(
            COALESCE(
              JSON_VALUE(content, '$.text_summary'),
              JSON_VALUE(content, '$'),
              ''
            ),
            r'^Function response: '
          )
          OR EXISTS(
            SELECT 1
            FROM UNNEST(content_parts) AS p
            WHERE
              JSON_QUERY(p.part_attributes, '$.function_response')
              IS NOT NULL
          )
        )
      ) AS is_function_response,
      IF(
        event_type = 'AGENT_RESPONSE',
        COALESCE(
          IF(
            JSON_TYPE(JSON_QUERY(content, '$.text_summary')) = 'string'
              AND TRIM(JSON_VALUE(content, '$.text_summary')) != '',
            JSON_VALUE(content, '$.text_summary'),
            NULL
          ),
          NULLIF(JSON_VALUE(content, '$.response'), ''),
          IF(
            JSON_TYPE(JSON_QUERY(content, '$.response'))
              IN ('object', 'array'),
            TO_JSON_STRING(JSON_QUERY(content, '$.response')),
            NULL
          )
        ),
        NULL
      ) AS formatted_response,
      (
        event_type = 'LLM_RESPONSE'
        AND (
          JSON_VALUE(attributes, '$.finish_reason') IS NOT NULL
          OR JSON_VALUE(attributes, '$.cache_type') IS NOT NULL
        )
      ) AS is_final_llm_response,
      SAFE_CAST(JSON_VALUE(content, '$.usage.total') AS INT64) AS usage_total,
      SAFE_CAST(JSON_VALUE(content, '$.usage.prompt') AS INT64)
        AS usage_prompt,
      SAFE_CAST(JSON_VALUE(content, '$.usage.completion') AS INT64)
        AS usage_completion,
      SAFE_CAST(JSON_VALUE(latency_ms, '$.total_ms') AS INT64) AS total_ms
    FROM
      RawEvents
  ),
  -- Marks the real tool calls, the calls of tools other than the framework
  -- tools, and unwraps the text of each model response.  It also counts the
  -- HITL requests so far in each turn.
  ResponseEvents AS (
    SELECT
      *,
      -- A TOOL_STARTING row that names no tool, as when a custom
      -- content_formatter fails, is not a tool call, since the trace could not
      -- pair it with its response.
      (
        event_type = 'TOOL_STARTING'
        AND NULLIF(tool_name, '') IS NOT NULL
        AND NOT is_framework_tool
      ) AS is_tool_call,
      -- The number of HITL requests so far in the turn.  A turn that resumes
      -- after one keeps its invocation_id, so the count tells the calls before
      -- a pause from the calls after it.
      COUNTIF(
        event_type IN (
          'HITL_CREDENTIAL_REQUEST',
          'HITL_CONFIRMATION_REQUEST',
          'HITL_INPUT_REQUEST'
        )
      ) OVER (
        PARTITION BY session_id, invocation_id
        ORDER BY timestamp, event_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS hitl_request_count,
      -- The text parts that _format_content renders become plain text, and a
      -- response with any other part has no text.
      CASE
        WHEN
          REGEXP_CONTAINS(formatted_response, r"(?s)^text: '.*'$")
          AND NOT REGEXP_CONTAINS(
            formatted_response,
            r' [|] (?:call: |resp: |Executable code |Code execution result )'
          )
          AND NOT REGEXP_CONTAINS(formatted_response, r' [|] other(?: [|] |$)')
          THEN NULLIF(
            REGEXP_REPLACE(
              REGEXP_REPLACE(formatted_response, r"^text: '|'$", ''),
              r"' [|] text: '",
              CHR(10)
            ),
            ''
          )
        WHEN
          NOT REGEXP_CONTAINS(
            formatted_response,
            r'^(?:call: |resp: |Executable code |Code execution result )'
          )
          AND NOT REGEXP_CONTAINS(
            formatted_response, r"^(?:None$|text: '|other(?: [|] |$))"
          )
          THEN NULLIF(formatted_response, '')
        ELSE NULL
      END AS response_text
    FROM
      TypedEvents
  ),
  -- Adds two marks to each event: whether its turn has a final model
  -- response, which picks the rows that count tokens, and the island number
  -- that a run of consecutive identical tool calls shares.  The second
  -- ROW_NUMBER restarts after each HITL request, so the request ends a run,
  -- as a different call does.
  AnnotatedEvents AS (
    SELECT
      *,
      LOGICAL_OR(is_final_llm_response) OVER (
        PARTITION BY session_id, invocation_id
      ) AS turn_has_final_llm_response,
      ROW_NUMBER() OVER (
        PARTITION BY session_id, invocation_id, is_tool_call
        ORDER BY timestamp, event_id
      ) - ROW_NUMBER() OVER (
        PARTITION BY
          session_id,
          invocation_id,
          is_tool_call,
          tool_name,
          tool_args_json,
          hitl_request_count
        ORDER BY timestamp, event_id
      ) AS tool_call_island
    FROM
      ResponseEvents
  ),
  -- Each event as a step of the AgentData trace: its author, its place among
  -- the events that share its timestamp, and its content as user text, a
  -- function call, a function response or model text, if it has any.
  TraceEvents AS (
    SELECT
      session_id,
      invocation_id,
      timestamp,
      event_id,
      event_type,
      user_id,
      agent,
      JSON_VALUE(attributes, '$.root_agent_name') AS root_agent_name,
      status,
      error_message,
      is_truncated,
      message_text,
      response_text,
      is_function_response,
      is_tool_call,
      is_framework_tool,
      IF(is_tool_call, tool_name, NULL) AS invoked_tool_name,
      IF(
        is_tool_call,
        COUNT(*) OVER (
          PARTITION BY
            session_id,
            invocation_id,
            is_tool_call,
            tool_name,
            tool_args_json,
            tool_call_island
        ),
        NULL
      ) AS tool_call_run_length,
      (
        event_type = 'LLM_RESPONSE'
        AND (is_final_llm_response OR NOT turn_has_final_llm_response)
      ) AS is_usage_row,
      usage_total,
      usage_prompt,
      usage_completion,
      total_ms,
      -- Orders the events that share a timestamp: the user message, a call, a
      -- transfer, a response, and then the rest.
      CASE
        WHEN event_type = 'USER_MESSAGE_RECEIVED' THEN 1
        WHEN
          event_type IN (
            'TOOL_STARTING',
            'HITL_CREDENTIAL_REQUEST',
            'HITL_CONFIRMATION_REQUEST',
            'HITL_INPUT_REQUEST'
          )
          THEN 2
        WHEN event_type = 'AGENT_TRANSFER' THEN 3
        WHEN
          event_type IN (
            'TOOL_COMPLETED',
            'TOOL_ERROR',
            'HITL_CREDENTIAL_REQUEST_COMPLETED',
            'HITL_CONFIRMATION_REQUEST_COMPLETED',
            'HITL_INPUT_REQUEST_COMPLETED'
          )
          THEN 4
        ELSE 5
      END AS event_seq,
      CASE event_type
        WHEN 'USER_MESSAGE_RECEIVED' THEN 'user'
        WHEN 'AGENT_TRANSFER'
          THEN COALESCE(JSON_VALUE(content, '$.from_agent'), author)
        ELSE author
      END AS event_author,
      CASE
        WHEN event_type = 'USER_MESSAGE_RECEIVED' AND message_text IS NOT NULL
          THEN JSON_OBJECT(
            'role', 'user',
            'parts', JSON_ARRAY(JSON_OBJECT('text', message_text))
          )
        WHEN
          is_tool_call
          OR event_type IN (
            'HITL_CREDENTIAL_REQUEST',
            'HITL_CONFIRMATION_REQUEST',
            'HITL_INPUT_REQUEST'
          )
          THEN JSON_OBJECT(
            'role', 'model',
            'parts', JSON_ARRAY(
              JSON_OBJECT(
                'function_call', JSON_OBJECT(
                  'name', COALESCE(tool_name, ''),
                  'args', IF(
                    JSON_TYPE(JSON_QUERY(content, '$.args')) = 'object',
                    JSON_QUERY(content, '$.args'),
                    JSON_OBJECT()
                  )
                )
              )
            )
          )
        WHEN event_type = 'AGENT_TRANSFER'
          THEN JSON_OBJECT(
            'role', 'model',
            'parts', JSON_ARRAY(
              JSON_OBJECT(
                'function_call', JSON_OBJECT(
                  'name', 'transfer_to_agent',
                  'args', JSON_OBJECT(
                    'agent_name',
                    COALESCE(JSON_VALUE(content, '$.to_agent'), '')
                  )
                )
              )
            )
          )
        WHEN
          (
            event_type = 'TOOL_COMPLETED'
            AND NULLIF(tool_name, '') IS NOT NULL
            AND NOT is_framework_tool
          )
          OR event_type IN (
            'HITL_CREDENTIAL_REQUEST_COMPLETED',
            'HITL_CONFIRMATION_REQUEST_COMPLETED',
            'HITL_INPUT_REQUEST_COMPLETED'
          )
          THEN JSON_OBJECT(
            'role', 'user',
            'parts', JSON_ARRAY(
              JSON_OBJECT(
                'function_response', JSON_OBJECT(
                  'name', COALESCE(tool_name, ''),
                  'response', IF(
                    JSON_TYPE(JSON_QUERY(content, '$.result')) = 'object',
                    JSON_QUERY(content, '$.result'),
                    JSON_OBJECT('result', JSON_QUERY(content, '$.result'))
                  )
                )
              )
            )
          )
        WHEN
          event_type = 'TOOL_ERROR'
          AND NULLIF(tool_name, '') IS NOT NULL
          AND NOT is_framework_tool
          THEN JSON_OBJECT(
            'role', 'user',
            'parts', JSON_ARRAY(
              JSON_OBJECT(
                'function_response', JSON_OBJECT(
                  'name', tool_name,
                  'response', JSON_OBJECT(
                    'error',
                    COALESCE(NULLIF(error_message, ''), 'Tool execution failed')
                  )
                )
              )
            )
          )
        WHEN event_type = 'AGENT_RESPONSE' AND response_text IS NOT NULL
          THEN JSON_OBJECT(
            'role', 'model',
            'parts', JSON_ARRAY(JSON_OBJECT('text', response_text))
          )
        ELSE NULL
      END AS event_content
    FROM
      AnnotatedEvents
  ),
  -- One row per turn, with its trace events in order and its metrics: tool
  -- calls and errors, token totals, latency, and whether it paused or
  -- finished.
  TurnRollup AS (
    SELECT
      session_id,
      invocation_id,
      ARRAY_AGG(
        user_id IGNORE NULLS ORDER BY timestamp LIMIT 1
      )[SAFE_OFFSET(0)] AS user_id,
      ARRAY_AGG(
        root_agent_name IGNORE NULLS ORDER BY timestamp LIMIT 1
      )[SAFE_OFFSET(0)] AS first_root_agent_name,
      ARRAY_AGG(
        agent IGNORE NULLS ORDER BY timestamp LIMIT 1
      )[SAFE_OFFSET(0)] AS first_agent,
      MIN(timestamp) AS turn_start_timestamp,
      MAX(timestamp) AS turn_end_timestamp,
      COUNTIF(is_tool_call) AS tool_call_count,
      COUNTIF(event_type = 'TOOL_ERROR' AND NOT is_framework_tool)
        AS tool_error_count,
      COUNTIF(event_type = 'LLM_ERROR') AS llm_error_count,
      COUNTIF(event_type = 'AGENT_ERROR') AS agent_error_count,
      COALESCE(
        LOGICAL_OR(
          status = 'ERROR'
          OR (COALESCE(status, '') != 'OK' AND error_message IS NOT NULL)
          OR (event_type = 'LLM_RESPONSE' AND error_message IS NOT NULL)
        ),
        FALSE
      ) AS has_error,
      LOGICAL_OR(event_content IS NOT NULL AND COALESCE(is_truncated, FALSE))
        AS has_truncated_content,
      COALESCE(MAX(tool_call_run_length), 0) >= 3 AS has_tool_loop,
      COALESCE(MAX(tool_call_run_length), 0)
        AS max_consecutive_identical_tool_calls,
      COALESCE(
        ARRAY_AGG(
          DISTINCT invoked_tool_name IGNORE NULLS ORDER BY invoked_tool_name
        ),
        ARRAY<STRING>[]
      ) AS distinct_tools_used,
      COALESCE(SUM(IF(is_usage_row, usage_prompt, NULL)), 0)
        AS total_prompt_tokens,
      COALESCE(SUM(IF(is_usage_row, usage_completion, NULL)), 0)
        AS total_completion_tokens,
      COALESCE(SUM(IF(is_usage_row, usage_total, NULL)), 0) AS total_tokens,
      COALESCE(
        MAX(IF(event_type = 'INVOCATION_COMPLETED', total_ms, NULL)),
        MAX(IF(event_type = 'AGENT_COMPLETED', total_ms, NULL))
      ) AS turn_latency_ms,
      (
        COALESCE(LOGICAL_OR(event_type = 'INVOCATION_COMPLETED'), FALSE)
        AND NOT COALESCE(
          LOGICAL_OR(
            event_type = 'AGENT_RESPONSE' AND response_text IS NOT NULL
          ),
          FALSE
        )
        AND COALESCE(
          LOGICAL_OR(
            event_type IN (
              'TOOL_PAUSED',
              'HITL_CREDENTIAL_REQUEST',
              'HITL_CONFIRMATION_REQUEST',
              'HITL_INPUT_REQUEST'
            )
          ),
          FALSE
        )
      ) AS is_paused,
      (
        COALESCE(LOGICAL_OR(event_type = 'INVOCATION_COMPLETED'), FALSE)
        AND COALESCE(
          LOGICAL_OR(
            event_type = 'AGENT_RESPONSE' AND response_text IS NOT NULL
          ),
          FALSE
        )
      ) AS is_complete,
      COALESCE(
        LOGICAL_OR(
          event_type = 'USER_MESSAGE_RECEIVED' AND message_text IS NOT NULL
        ),
        FALSE
      ) AS has_user_message,
      COALESCE(LOGICAL_OR(is_function_response), FALSE)
        AS has_function_response,
      ARRAY_AGG(
        IF(
          event_content IS NULL,
          NULL,
          JSON_OBJECT(
            'author', event_author,
            'content', event_content,
            'event_time',
            FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%E6SZ', timestamp)
          )
        )
        IGNORE NULLS
        ORDER BY timestamp, event_seq, event_id
      ) AS events
    FROM
      TraceEvents
    GROUP BY
      session_id,
      invocation_id
  ),
  -- Each turn with its place in the session and whether it is ready for
  -- evaluation, on its own or as a part of its session.
  Turns AS (
    SELECT
      *,
      COALESCE(first_root_agent_name, first_agent) AS root_agent,
      ROW_NUMBER() OVER (
        PARTITION BY session_id
        ORDER BY turn_start_timestamp, invocation_id
      ) - 1 AS turn_index,
      IF(
        COALESCE(ARRAY_LENGTH(events), 0) > 0, TO_JSON(events), JSON_ARRAY()
      ) AS events_json,
      (
        has_user_message
        AND is_complete
        AND NOT has_truncated_content
        AND COALESCE(ARRAY_LENGTH(events), 0) > 0
      ) AS eval_ready,
      -- In a session, a paused turn and the function response turn that
      -- resumes it are ready together.
      (
        (
          has_user_message
          OR (
            has_function_response
            AND COALESCE(
              LAG(is_paused) OVER (
                PARTITION BY session_id
                ORDER BY turn_start_timestamp, invocation_id
              ),
              FALSE
            )
          )
        )
        AND (
          is_complete
          OR (
            is_paused
            AND COALESCE(
              LEAD(has_function_response) OVER (
                PARTITION BY session_id
                ORDER BY turn_start_timestamp, invocation_id
              ),
              FALSE
            )
          )
        )
        AND NOT has_truncated_content
        AND COALESCE(ARRAY_LENGTH(events), 0) > 0
      ) AS session_turn_eval_ready
    FROM
      TurnRollup
  ),
  -- One row per event of an agent, with the parts of its configuration that
  -- the event logs: the instruction, description and sub agents of
  -- AGENT_STARTING, and the tool declarations of LLM_REQUEST.
  AgentRows AS (
    SELECT
      session_id,
      invocation_id,
      agent AS agent_id,
      timestamp,
      IF(
        event_type = 'AGENT_STARTING',
        COALESCE(
          JSON_VALUE(content, '$.text_summary'),
          IF(
            REGEXP_CONTAINS(
              JSON_VALUE(content, '$'),
              r'^(?:<(?:function|bound method) |<.+ at 0x[0-9a-fA-F]+>|functools\.partial\()'
            ),
            NULL,
            JSON_VALUE(content, '$')
          ),
          JSON_VALUE(attributes, '$.static_instruction')
        ),
        NULL
      ) AS instruction,
      IF(
        event_type = 'AGENT_STARTING',
        JSON_VALUE(attributes, '$.agent_description'),
        NULL
      ) AS description,
      IF(
        event_type = 'AGENT_STARTING'
        AND JSON_TYPE(JSON_QUERY(attributes, '$.sub_agents')) = 'array',
        JSON_QUERY(attributes, '$.sub_agents'),
        NULL
      ) AS sub_agents,
      IF(
        event_type = 'LLM_REQUEST'
        AND JSON_TYPE(JSON_QUERY(attributes, '$.tools')) = 'array',
        JSON_QUERY(attributes, '$.tools'),
        NULL
      ) AS tool_declarations
    FROM
      RawEvents
    WHERE
      agent IS NOT NULL
  ),
  -- The latest logged value of each part of the configuration of each agent,
  -- in each session or turn.
  AgentLatest AS (
    SELECT
      {scope_columns},
      agent_id,
      ARRAY_AGG(
        instruction IGNORE NULLS ORDER BY timestamp DESC LIMIT 1
      )[SAFE_OFFSET(0)] AS instruction,
      ARRAY_AGG(
        description IGNORE NULLS ORDER BY timestamp DESC LIMIT 1
      )[SAFE_OFFSET(0)] AS description,
      ARRAY_AGG(
        sub_agents IGNORE NULLS ORDER BY timestamp DESC LIMIT 1
      )[SAFE_OFFSET(0)] AS sub_agents,
      ARRAY_AGG(
        tool_declarations IGNORE NULLS ORDER BY timestamp DESC LIMIT 1
      )[SAFE_OFFSET(0)] AS tool_declarations
    FROM
      AgentRows
    GROUP BY
      {scope_columns},
      agent_id
  ),
  -- The function declarations of the latest tools that each agent sent to the
  -- model, in the order that they were logged.
  AgentToolDeclarations AS (
    SELECT
      {scope_columns},
      agent_id,
      ARRAY_AGG(
        IF(
          JSON_TYPE(JSON_QUERY(declaration, '$.parameters')) = 'object',
          JSON_OBJECT(
            'name', JSON_VALUE(declaration, '$.name'),
            'description',
            COALESCE(JSON_VALUE(declaration, '$.description'), ''),
            'parameters_json_schema', JSON_QUERY(declaration, '$.parameters')
          ),
          JSON_OBJECT(
            'name', JSON_VALUE(declaration, '$.name'),
            'description',
            COALESCE(JSON_VALUE(declaration, '$.description'), '')
          )
        )
        ORDER BY declaration_offset
      ) AS function_declarations
    FROM
      AgentLatest
    INNER JOIN
      UNNEST(JSON_QUERY_ARRAY(tool_declarations)) AS declaration
      WITH OFFSET AS declaration_offset
    WHERE
      JSON_VALUE(declaration, '$.name') IS NOT NULL
    GROUP BY
      {scope_columns},
      agent_id
  ),
  -- The first non-blank system prompt that each agent sent to the model in
  -- the session.  An agent whose instruction is a callable logs no
  -- instruction text, so this is its fallback.
  SessionAgentPrompts AS (
    SELECT
      session_id,
      agent AS agent_id,
      ARRAY_AGG(
        IF(
          JSON_TYPE(JSON_QUERY(content, '$.system_prompt')) = 'string'
            AND TRIM(JSON_VALUE(content, '$.system_prompt')) != '',
          JSON_VALUE(content, '$.system_prompt'),
          NULL
        )
        IGNORE NULLS
        ORDER BY timestamp, event_id
        LIMIT 1
      )[SAFE_OFFSET(0)] AS logged_system_prompt
    FROM
      RawEvents
    WHERE
      event_type = 'LLM_REQUEST'
      AND agent IS NOT NULL
    GROUP BY
      session_id,
      agent
  ),
  -- The AgentConfig of each agent.  Its instruction comes from the latest
  -- AGENT_STARTING event, else from the logged system prompt.
  AgentConfigs AS (
    SELECT
      {scope_columns},
      agent_id,
      JSON_OBJECT(
        'agent_id', agent_id,
        'instruction',
        COALESCE(NULLIF(instruction, ''), logged_system_prompt, ''),
        'description', COALESCE(description, ''),
        'sub_agents', COALESCE(sub_agents, JSON_ARRAY()),
        'tools', IF(
          function_declarations IS NULL,
          JSON_ARRAY(),
          JSON_ARRAY(
            JSON_OBJECT(
              'function_declarations', TO_JSON(function_declarations)
            )
          )
        )
      ) AS agent_config
    FROM
      AgentLatest
    LEFT JOIN
      SessionAgentPrompts
      USING (session_id, agent_id)
    LEFT JOIN
      AgentToolDeclarations
      USING ({scope_columns}, agent_id)
  ),
  -- The agents of each session or turn, as one JSON object keyed by agent id.
  AgentMaps AS (
    SELECT
      {scope_columns},
      JSON_OBJECT(
        ARRAY_AGG(agent_id ORDER BY agent_id),
        ARRAY_AGG(agent_config ORDER BY agent_id)
      ) AS agents
    FROM
      AgentConfigs
    GROUP BY
      {scope_columns}
  )
''';

const String _evalSessionQueryTemplate = r'''{ctes},
  -- One row per session, rolled up from its turns.
  SessionRollup AS (
    SELECT
      session_id,
      ARRAY_AGG(
        user_id IGNORE NULLS ORDER BY turn_start_timestamp LIMIT 1
      )[SAFE_OFFSET(0)] AS user_id,
      COALESCE(
        ARRAY_AGG(
          first_root_agent_name IGNORE NULLS
          ORDER BY turn_start_timestamp
          LIMIT 1
        )[SAFE_OFFSET(0)],
        ARRAY_AGG(
          first_agent IGNORE NULLS ORDER BY turn_start_timestamp LIMIT 1
        )[SAFE_OFFSET(0)]
      ) AS root_agent,
      MIN(turn_start_timestamp) AS session_start_timestamp,
      MAX(turn_end_timestamp) AS session_end_timestamp,
      COUNT(DISTINCT invocation_id) AS turn_count,
      SUM(tool_call_count) AS tool_call_count,
      SUM(tool_error_count) AS tool_error_count,
      SUM(llm_error_count) AS llm_error_count,
      SUM(agent_error_count) AS agent_error_count,
      LOGICAL_OR(has_error) AS has_error,
      LOGICAL_OR(has_truncated_content) AS has_truncated_content,
      LOGICAL_OR(has_tool_loop) AS has_tool_loop,
      MAX(max_consecutive_identical_tool_calls)
        AS max_consecutive_identical_tool_calls,
      ARRAY_CONCAT_AGG(distinct_tools_used) AS tools_used_by_turn,
      SUM(total_prompt_tokens) AS total_prompt_tokens,
      SUM(total_completion_tokens) AS total_completion_tokens,
      SUM(total_tokens) AS total_tokens,
      SUM(turn_latency_ms) AS total_latency_ms,
      LOGICAL_AND(session_turn_eval_ready) AS eval_ready,
      ARRAY_AGG(
        JSON_OBJECT(
          'turn_index', turn_index,
          'turn_id', invocation_id,
          'events', events_json
        )
        ORDER BY turn_index
      ) AS turn_traces
    FROM
      Turns
    GROUP BY
      session_id
  ),
  -- The rows of the eval session view, named by their output columns so that
  -- the where clause can filter them.
  EvalSessions AS (
    SELECT
      s.session_id,
      s.user_id,
      s.root_agent,
      s.session_start_timestamp,
      s.session_end_timestamp,
      s.turn_count,
      s.tool_call_count,
      s.tool_error_count,
      s.llm_error_count,
      s.agent_error_count,
      s.has_error,
      s.has_truncated_content,
      s.has_tool_loop,
      s.max_consecutive_identical_tool_calls,
      ARRAY(
        SELECT DISTINCT tool
        FROM UNNEST(s.tools_used_by_turn) AS tool
        ORDER BY tool
      ) AS distinct_tools_used,
      s.total_prompt_tokens,
      s.total_completion_tokens,
      s.total_tokens,
      s.total_latency_ms,
      s.eval_ready,
      JSON_OBJECT(
        'agents', COALESCE(m.agents, JSON_OBJECT()),
        'turns', TO_JSON(s.turn_traces)
      ) AS trace
    FROM
      SessionRollup AS s
    LEFT JOIN
      AgentMaps AS m
      ON m.session_id = s.session_id
  )
SELECT
  session_id,
  user_id,
  root_agent,
  session_start_timestamp,
  session_end_timestamp,
  turn_count,
  tool_call_count,
  tool_error_count,
  llm_error_count,
  agent_error_count,
  has_error,
  has_truncated_content,
  has_tool_loop,
  max_consecutive_identical_tool_calls,
  distinct_tools_used,
  total_prompt_tokens,
  total_completion_tokens,
  total_tokens,
  total_latency_ms,
  eval_ready,
  trace
FROM
  EvalSessions{where_clause}''';

const String _evalTurnQueryTemplate = r'''{ctes},
  -- The rows of the eval turn view, named by their output columns so that the
  -- where clause can filter them.
  EvalTurns AS (
    SELECT
      t.session_id,
      t.invocation_id,
      t.turn_index,
      t.user_id,
      t.root_agent,
      t.turn_start_timestamp,
      t.turn_end_timestamp,
      t.tool_call_count,
      t.tool_error_count,
      t.llm_error_count,
      t.agent_error_count,
      t.has_error,
      t.has_truncated_content,
      t.has_tool_loop,
      t.max_consecutive_identical_tool_calls,
      t.distinct_tools_used,
      t.total_prompt_tokens,
      t.total_completion_tokens,
      t.total_tokens,
      t.turn_latency_ms,
      t.eval_ready,
      JSON_OBJECT(
        'agents', COALESCE(m.agents, JSON_OBJECT()),
        'turns', JSON_ARRAY(
          JSON_OBJECT(
            'turn_index', 0,
            'turn_id', t.invocation_id,
            'events', t.events_json
          )
        )
      ) AS trace
    FROM
      Turns AS t
    LEFT JOIN
      AgentMaps AS m
      ON m.session_id = t.session_id AND m.invocation_id = t.invocation_id
  )
SELECT
  session_id,
  invocation_id,
  turn_index,
  user_id,
  root_agent,
  turn_start_timestamp,
  turn_end_timestamp,
  tool_call_count,
  tool_error_count,
  llm_error_count,
  agent_error_count,
  has_error,
  has_truncated_content,
  has_tool_loop,
  max_consecutive_identical_tool_calls,
  distinct_tools_used,
  total_prompt_tokens,
  total_completion_tokens,
  total_tokens,
  turn_latency_ms,
  eval_ready,
  trace
FROM
  EvalTurns{where_clause}''';
