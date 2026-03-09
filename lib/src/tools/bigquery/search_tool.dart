/// BigQuery catalog search helpers backed by Dataplex.
library;

import 'client.dart';
import 'config.dart';

String _constructSearchQueryHelper(
  String predicate,
  String operator,
  List<String> items,
) {
  if (items.isEmpty) {
    return '';
  }

  final List<String> clauses = items
      .map((String item) => '$predicate$operator"$item"')
      .toList(growable: false);
  return clauses.length == 1 ? clauses.first : '(${clauses.join(' OR ')})';
}

/// Searches Dataplex catalog entries scoped to BigQuery assets.
Future<Map<String, Object?>> searchCatalog({
  required String prompt,
  required String projectId,
  required Object credentials,
  required Object settings,
  String? location,
  int pageSize = 10,
  List<String>? projectIdsFilter,
  List<String>? datasetIdsFilter,
  List<String>? typesFilter,
}) async {
  try {
    if (projectId.trim().isEmpty) {
      return <String, Object?>{
        'status': 'ERROR',
        'error_details': 'project_id must be provided.',
      };
    }

    final BigQueryToolConfig toolSettings = BigQueryToolConfig.fromObject(
      settings,
    );
    final DataplexCatalogClient dataplexClient = getDataplexCatalogClient(
      credentials: credentials,
      userAgent: <String?>[
        toolSettings.applicationName,
        'search_catalog',
      ].whereType<String>(),
    );

    final List<String> queryParts = <String>[];
    if (prompt.trim().isNotEmpty) {
      queryParts.add('(${prompt.trim()})');
    }

    final List<String> projectsToFilter =
        projectIdsFilter == null || projectIdsFilter.isEmpty
        ? <String>[projectId]
        : List<String>.from(projectIdsFilter);
    queryParts.add(
      _constructSearchQueryHelper('projectid', '=', projectsToFilter),
    );

    if (datasetIdsFilter != null && datasetIdsFilter.isNotEmpty) {
      final List<String> datasetResourceFilters = <String>[];
      for (final String filteredProjectId in projectsToFilter) {
        for (final String datasetId in datasetIdsFilter) {
          datasetResourceFilters.add(
            'linked_resource:"//bigquery.googleapis.com/projects/'
            '$filteredProjectId/datasets/$datasetId/*"',
          );
        }
      }
      if (datasetResourceFilters.isNotEmpty) {
        queryParts.add('(${datasetResourceFilters.join(' OR ')})');
      }
    }

    if (typesFilter != null && typesFilter.isNotEmpty) {
      queryParts.add(_constructSearchQueryHelper('type', '=', typesFilter));
    }

    queryParts.add('system=BIGQUERY');

    final String searchLocation = location?.trim().isNotEmpty == true
        ? location!.trim()
        : (toolSettings.location?.trim().isNotEmpty == true
              ? toolSettings.location!.trim()
              : 'global');
    final String searchScope = 'projects/$projectId/locations/$searchLocation';

    final List<DataplexSearchEntryResult> results = dataplexClient
        .searchEntries(
          name: searchScope,
          query: queryParts
              .where((String item) => item.isNotEmpty)
              .join(' AND '),
          pageSize: pageSize,
          semanticSearch: true,
        )
        .toList(growable: false);

    return <String, Object?>{
      'status': 'SUCCESS',
      'results': results
          .map(
            (DataplexSearchEntryResult item) =>
                Map<String, Object?>.from(item.toApiRepr()),
          )
          .toList(growable: false),
    };
  } on DataplexCatalogApiException catch (error) {
    return <String, Object?>{
      'status': 'ERROR',
      'error_details': 'Dataplex API Error: ${error.message}',
    };
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}
