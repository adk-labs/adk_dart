/// Bundled BigQuery skills (`bigquery-ai-ml` and `bigquery-graph`).
library;

import '../../skills/skill_runtime.dart';

/// Names of bundled BigQuery skills available via [getBigQuerySkill].
const List<String> availableBigQuerySkills = <String>[
  'bigquery-ai-ml',
  'bigquery-graph',
];

/// Loads a bundled BigQuery [Skill] by [skillName].
///
/// Defaults to `'bigquery-ai-ml'`. Throws an [ArgumentError] if [skillName] is
/// not one of [availableBigQuerySkills].
Skill getBigQuerySkill([String skillName = 'bigquery-ai-ml']) {
  if (!availableBigQuerySkills.contains(skillName)) {
    final String available = availableBigQuerySkills.join(', ');
    throw ArgumentError(
      'Unknown BigQuery skill "$skillName". Available skills: $available.',
    );
  }
  switch (skillName) {
    case 'bigquery-ai-ml':
      return Skill(
        frontmatter: Frontmatter(
          name: 'bigquery-ai-ml',
          license: 'Apache-2.0',
          metadata: <String, Object?>{'author': 'google-adk', 'version': '1.0'},
          description:
              "Leverages BigQuery's built-in machine learning and GenAI capabilities "
              'for advanced data analytics. Use when you need to write SQL queries '
              'that perform time-series forecasting, predict values, detect outliers or anomalies, find key drivers, '
              'perform semantic search or vector search, classify text, calculate similarity, '
              'summarize content, translate language, evaluate models, filter by semantic conditions, '
              'measure the causal effect of an intervention, compute correlations between columns, '
              'detect change points or structural breaks, extract trend or seasonality components, '
              'or leverage generative AI capabilities in BigQuery. Do not use for general '
              'BigQuery dataset, table, or job management requests.',
        ),
        instructions: _bigQueryAiMlInstructions,
        resources: Resources(references: _bigQueryAiMlReferences),
      );
    case 'bigquery-graph':
      return Skill(
        frontmatter: Frontmatter(
          name: 'bigquery-graph',
          license: 'Apache-2.0',
          metadata: <String, Object?>{'author': 'google-adk', 'version': '1.0'},
          description:
              'Skill for Graph Query Language (GQL) or SQL/PGQ queries against a property graph.\n'
              'Includes path finding, multi-hop traversal, topological connection, shortest path,\n'
              'node reachability, edge connectivity, and semantic graph queries.\n',
        ),
        instructions: _bigQueryGraphInstructions,
        resources: Resources(references: _bigQueryGraphReferences),
      );
    default:
      final String available = availableBigQuerySkills.join(', ');
      throw ArgumentError(
        'Unknown BigQuery skill "$skillName". Available skills: $available.',
      );
  }
}

const String _bigQueryAiMlInstructions = '''# BigQuery AI & ML

BigQuery integrates with Vertex AI to provide powerful machine learning and
generative AI capabilities directly within SQL queries using built-in functions
like `AI.FORECAST`, `AI.KEY_DRIVERS`, `AI.DETECT_ANOMALIES`, and `AI.GENERATE`.

## Reference Directory

-   **Functions Reference**:

    -   **AI.AGG**: [ai_agg.md](references/ai_agg.md) - Multi-row semantic
        aggregation and summarization.
    -   **AI.CAUSAL_EFFECT**:
        [ai_causal_effect.md](references/ai_causal_effect.md) - Quantifies the
        impact of an intervention on a time series.
    -   **AI.CLASSIFY**: [ai_classify.md](references/ai_classify.md) - Classify
        text.
    -   **AI.DETECT_ANOMALIES**:
        [ai_detect_anomalies.md](references/ai_detect_anomalies.md) - Detect
        anomalies.
    -   **AI.EVALUATE**: [ai_evaluate.md](references/ai_evaluate.md) - Evaluate
        models.
    -   **AI.FORECAST**: [ai_forecast.md](references/ai_forecast.md) -
        Time-series forecasting.
    -   **AI.GENERATE**: [ai_generate.md](references/ai_generate.md) - Generate
        text using LLMs.
    -   **AI.GENERATE_EMBEDDING**:
        [ai_generate_embedding.md](references/ai_generate_embedding.md) -
        Generate embeddings.
    -   **AI.GENERATE_TABLE**:
        [ai_generate_table.md](references/ai_generate_table.md) - Table-valued
        AI generation.
    -   **AI.IF**: [ai_if.md](references/ai_if.md) - Evaluate semantic
        conditions.
    -   **AI.KEY_DRIVERS**: [ai_key_drivers.md](references/ai_key_drivers.md) -
        Identifies key drivers, this is a TVF.
    -   **AI.SCORE**: [ai_score.md](references/ai_score.md) - Score data.
    -   **AI.SEARCH**: [ai_search.md](references/ai_search.md) - Semantic
        search.
    -   **AI.SIMILARITY**: [ai_similarity.md](references/ai_similarity.md) -
        Semantic similarity.
    -   **Remote Models**: [remote_models.md](references/remote_models.md) -
        Working with remote models (Vertex AI).
    -   **CONTRIBUTION_ANALYSIS**:
        [ml_contribution_analysis.md](references/ml_contribution_analysis.md)
        -   Finds contributing factors, key drivers of change. Requires creating
            a MODEL entity.
    -   **ML.CORRELATION**: [ml_correlation.md](references/ml_correlation.md) -
        Calculates correlation between columns, optionally sliced by dimensions.
    -   **ML.DETECT_CHANGE_POINTS**:
        [ml_detect_change_points.md](references/ml_detect_change_points.md) -
        Detects structural breaks or sustained shifts in a time series.
    -   **ML.SEASONALITY**: [ml_seasonality.md](references/ml_seasonality.md) -
        Extracts seasonal components from a time series.
    -   **ML.TREND**: [ml_trend.md](references/ml_trend.md) - Extracts the
        long-term trend component from a time series.
    -   **VECTOR_SEARCH**: [vector_search.md](references/vector_search.md) -
        Vector search best practices.''';

const Map<String, String> _bigQueryAiMlReferences = <String, String>{
  'ai_agg.md':
      '# AI.AGG\n\nMulti-row semantic aggregation and summarization in BigQuery SQL using `AI.AGG`.',
  'ai_causal_effect.md':
      '# AI.CAUSAL_EFFECT\n\nQuantifies the causal impact of an intervention on a time series using `AI.CAUSAL_EFFECT`.',
  'ai_classify.md':
      '# AI.CLASSIFY\n\nClassifies text inputs into user-defined categories using `AI.CLASSIFY`.',
  'ai_detect_anomalies.md':
      '# AI.DETECT_ANOMALIES\n\nDetects time-series anomalies using `AI.DETECT_ANOMALIES` TVF.',
  'ai_evaluate.md':
      '# AI.EVALUATE\n\nEvaluates forecasting and ML models in BigQuery using `AI.EVALUATE`.',
  'ai_forecast.md':
      '# AI.FORECAST\n\nPerforms time-series forecasting in BigQuery SQL using `AI.FORECAST`.',
  'ai_generate.md':
      '# AI.GENERATE\n\nGenerates free-form or structured text using Vertex AI models via `AI.GENERATE`.',
  'ai_generate_embedding.md':
      '# AI.GENERATE_EMBEDDING\n\nGenerates text or multimodal vector embeddings using `AI.GENERATE_EMBEDDING`.',
  'ai_generate_table.md':
      '# AI.GENERATE_TABLE\n\nGenerates structured table rows from prompts using `AI.GENERATE_TABLE`.',
  'ai_if.md':
      '# AI.IF\n\nEvaluates natural-language semantic conditions in WHERE/SELECT clauses using `AI.IF`.',
  'ai_key_drivers.md':
      '# AI.KEY_DRIVERS\n\nIdentifies key drivers of a metric using the `AI.KEY_DRIVERS` table-valued function.',
  'ai_score.md':
      '# AI.SCORE\n\nScores rows against a natural-language rubric using `AI.SCORE`.',
  'ai_search.md':
      '# AI.SEARCH\n\nPerforms semantic search over tables with autonomous embedding generation using `AI.SEARCH`.',
  'ai_similarity.md':
      '# AI.SIMILARITY\n\nComputes semantic similarity scores between inputs using `AI.SIMILARITY`.',
  'ml_contribution_analysis.md':
      '# CONTRIBUTION_ANALYSIS\n\nFinds contributing factors and key drivers of change by creating a `CONTRIBUTION_ANALYSIS` model (`CREATE MODEL ... OPTIONS(model_type=\'CONTRIBUTION_ANALYSIS\')`) and querying `ML.GET_INSIGHTS`.',
  'ml_correlation.md':
      '# ML.CORRELATION\n\nCalculates pairwise correlation between numerical columns using `ML.CORRELATION`.',
  'ml_detect_change_points.md':
      '# ML.DETECT_CHANGE_POINTS\n\nDetects structural breaks or sustained shifts in time-series data using `ML.DETECT_CHANGE_POINTS`.',
  'ml_seasonality.md':
      '# ML.SEASONALITY\n\nExtracts seasonal components from time-series data using `ML.SEASONALITY`.',
  'ml_trend.md':
      '# ML.TREND\n\nExtracts long-term trend components from time-series data using `ML.TREND`.',
  'remote_models.md':
      '# Remote Models\n\nCreates and manages BigQuery ML remote models backed by Vertex AI endpoints (`CREATE MODEL ... REMOTE WITH CONNECTION ...`).',
  'vector_search.md':
      '# VECTOR_SEARCH\n\nPerforms vector similarity search in BigQuery using `VECTOR_SEARCH` and vector indexes.',
};

const String _bigQueryGraphInstructions =
    '''# Graph Query Language (GQL) Query Generation Guidelines

You are querying a property graph consisting of nodes and edges. You **MUST
exclusively use the BigQuery GoogleSQL GQL standard**, which is the only
supported graph query language and implements the ISO GQL standard.

**You MUST NEVER, under any circumstances, generate or consider Cypher
queries.** Any deviation from the BigQuery GoogleSQL GQL standard is strictly
prohibited.

## Reference Directory

-   [Semantic Graph Guidelines](references/semantic_queries.md): Guidelines for
    generating SQL queries against a semantic graph.
-   [Graph Schema Best Practices](references/graph_schema/best_practices.md):
    Best practices for defining BigQuery property graph schemas.
-   [Graph Schema DDL Reference](references/graph_schema/ddl_reference.md): DDL
    syntax reference for property graphs.
-   [Graph Limitations & Feature Parity](references/graph_schema/feature_parity.md):
    Current limitations and feature parity for BigQuery Graph.
-   [Graph Schema DDL Advisor](references/graph_schema/graph_schema_ddl_advisor.md):
    Assists in defining and optimizing schemas.

## Pre-generation Checklist

Before generating any GQL, you MUST:

1.  **Identify Output Intent**: Determine if the user intends to **visualize a
    graph network** (requires `TO_JSON()`) or **view tabular data** (requires
    specific properties).
2.  **Verify Language Standard**: Confirm the query will use **BigQuery
    GoogleSQL GQL**. NEVER use Cypher.

## Core Directives for Agent Query Generation

1.  **Default Query Construction (Standalone GQL)**: Write standalone GQL
    queries using the `RETURN` statement natively. **Explicitly avoid using the
    `GRAPH_TABLE` table-valued function unless the user constraints actively
    require standard SQL relational integration or aggregation.**
2.  **Keyword Escaping**: Enforce backticks (`) around reserved SQL and GQL
    keywords such as `order`, `begin`, and `path` used as identifiers.
3.  **Strictly Follow Graph Schema**: Ensure all labels and properties strictly
    match the provided graph schema.
4.  **Result Uniqueness**: Use `DISTINCT` in `RETURN` or `COLUMNS` when unique
    results are implied.
5.  **Graph Path Variables**: Assign matched path patterns to a path variable
    (e.g., `MATCH p = ...`) when path traversal or relationships are requested.''';

const Map<String, String> _bigQueryGraphReferences = <String, String>{
  'semantic_queries.md':
      '# Semantic Graph Specific Rules\n\nQuery semantic graphs via `GRAPH_EXPAND("project.dataset.graph")` and wrap `is_measure=TRUE` columns in `AGG(...)`.',
  'graph_schema/best_practices.md':
      '# BigQuery Graph Schema Best Practices\n\nScope properties explicitly with `PROPERTIES (...)`, define PK/FK constraints, avoid column name collisions in `GRAPH_EXPAND`, and always specify safe alphanumeric aliases (`AS alias`).',
  'graph_schema/ddl_reference.md':
      '# BigQuery Property Graph DDL Reference\n\nSyntax reference for `CREATE [OR REPLACE] PROPERTY GRAPH` with `NODE TABLES`, `EDGE TABLES`, `KEY`, `SOURCE KEY`, `DESTINATION KEY`, and `MEASURE(...)` semantic extensions.',
  'graph_schema/feature_parity.md':
      '# BigQuery Graph Limitations & Feature Parity\n\n`GRAPH_EXPAND` requires a tree topology without cycles, self-loops, disconnected forests, or convergent diamonds, and measures must be queried with `AGG()`.',
  'graph_schema/graph_schema_ddl_advisor.md':
      '# BigQuery Graph Schema Advisor\n\nStep-by-step protocol for analyzing requirements, building `CREATE PROPERTY GRAPH` DDL, scoping properties, enforcing safe aliases, and validating topology constraints.',
};
