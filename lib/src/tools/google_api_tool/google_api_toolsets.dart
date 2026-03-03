/// Preconfigured Google API toolset wrappers for common services.
library;

import '../../auth/auth_credential.dart';
import 'google_api_tool.dart';
import 'google_api_toolset.dart';
import 'googleapi_to_openapi_converter.dart';

/// Google BigQuery API toolset wrapper.
class BigQueryToolset extends GoogleApiToolset {
  /// Creates a BigQuery toolset.
  BigQueryToolset({
    String? clientId,
    String? clientSecret,
    Object? toolFilter,
    ServiceAccountAuth? serviceAccount,
    String? toolNamePrefix,
    Map<String, Object?>? discoverySpec,
    Map<String, Object?>? openApiSpec,
    GoogleDiscoverySpecFetcher? specFetcher,
    GoogleApiRequestExecutor? requestExecutor,
  }) : super(
         'bigquery',
         'v2',
         clientId: clientId,
         clientSecret: clientSecret,
         toolFilter: toolFilter,
         serviceAccount: serviceAccount,
         toolNamePrefix: toolNamePrefix,
         discoverySpec: discoverySpec,
         openApiSpec: openApiSpec,
         specFetcher: specFetcher,
         requestExecutor: requestExecutor,
       );
}

/// Google Calendar API toolset wrapper.
class CalendarToolset extends GoogleApiToolset {
  /// Creates a Calendar toolset.
  CalendarToolset({
    String? clientId,
    String? clientSecret,
    Object? toolFilter,
    ServiceAccountAuth? serviceAccount,
    String? toolNamePrefix,
    Map<String, Object?>? discoverySpec,
    Map<String, Object?>? openApiSpec,
    GoogleDiscoverySpecFetcher? specFetcher,
    GoogleApiRequestExecutor? requestExecutor,
  }) : super(
         'calendar',
         'v3',
         clientId: clientId,
         clientSecret: clientSecret,
         toolFilter: toolFilter,
         serviceAccount: serviceAccount,
         toolNamePrefix: toolNamePrefix,
         discoverySpec: discoverySpec,
         openApiSpec: openApiSpec,
         specFetcher: specFetcher,
         requestExecutor: requestExecutor,
       );
}

/// Google Gmail API toolset wrapper.
class GmailToolset extends GoogleApiToolset {
  /// Creates a Gmail toolset.
  GmailToolset({
    String? clientId,
    String? clientSecret,
    Object? toolFilter,
    ServiceAccountAuth? serviceAccount,
    String? toolNamePrefix,
    Map<String, Object?>? discoverySpec,
    Map<String, Object?>? openApiSpec,
    GoogleDiscoverySpecFetcher? specFetcher,
    GoogleApiRequestExecutor? requestExecutor,
  }) : super(
         'gmail',
         'v1',
         clientId: clientId,
         clientSecret: clientSecret,
         toolFilter: toolFilter,
         serviceAccount: serviceAccount,
         toolNamePrefix: toolNamePrefix,
         discoverySpec: discoverySpec,
         openApiSpec: openApiSpec,
         specFetcher: specFetcher,
         requestExecutor: requestExecutor,
       );
}

/// YouTube Data API toolset wrapper.
class YoutubeToolset extends GoogleApiToolset {
  /// Creates a YouTube toolset.
  YoutubeToolset({
    String? clientId,
    String? clientSecret,
    Object? toolFilter,
    ServiceAccountAuth? serviceAccount,
    String? toolNamePrefix,
    Map<String, Object?>? discoverySpec,
    Map<String, Object?>? openApiSpec,
    GoogleDiscoverySpecFetcher? specFetcher,
    GoogleApiRequestExecutor? requestExecutor,
  }) : super(
         'youtube',
         'v3',
         clientId: clientId,
         clientSecret: clientSecret,
         toolFilter: toolFilter,
         serviceAccount: serviceAccount,
         toolNamePrefix: toolNamePrefix,
         discoverySpec: discoverySpec,
         openApiSpec: openApiSpec,
         specFetcher: specFetcher,
         requestExecutor: requestExecutor,
       );
}

/// Google Slides API toolset wrapper.
class SlidesToolset extends GoogleApiToolset {
  /// Creates a Slides toolset.
  SlidesToolset({
    String? clientId,
    String? clientSecret,
    Object? toolFilter,
    ServiceAccountAuth? serviceAccount,
    String? toolNamePrefix,
    Map<String, Object?>? discoverySpec,
    Map<String, Object?>? openApiSpec,
    GoogleDiscoverySpecFetcher? specFetcher,
    GoogleApiRequestExecutor? requestExecutor,
  }) : super(
         'slides',
         'v1',
         clientId: clientId,
         clientSecret: clientSecret,
         toolFilter: toolFilter,
         serviceAccount: serviceAccount,
         toolNamePrefix: toolNamePrefix,
         discoverySpec: discoverySpec,
         openApiSpec: openApiSpec,
         specFetcher: specFetcher,
         requestExecutor: requestExecutor,
       );
}

/// Google Sheets API toolset wrapper.
class SheetsToolset extends GoogleApiToolset {
  /// Creates a Sheets toolset.
  SheetsToolset({
    String? clientId,
    String? clientSecret,
    Object? toolFilter,
    ServiceAccountAuth? serviceAccount,
    String? toolNamePrefix,
    Map<String, Object?>? discoverySpec,
    Map<String, Object?>? openApiSpec,
    GoogleDiscoverySpecFetcher? specFetcher,
    GoogleApiRequestExecutor? requestExecutor,
  }) : super(
         'sheets',
         'v4',
         clientId: clientId,
         clientSecret: clientSecret,
         toolFilter: toolFilter,
         serviceAccount: serviceAccount,
         toolNamePrefix: toolNamePrefix,
         discoverySpec: discoverySpec,
         openApiSpec: openApiSpec,
         specFetcher: specFetcher,
         requestExecutor: requestExecutor,
       );
}

/// Google Docs API toolset wrapper.
class DocsToolset extends GoogleApiToolset {
  /// Creates a Docs toolset.
  DocsToolset({
    String? clientId,
    String? clientSecret,
    Object? toolFilter,
    ServiceAccountAuth? serviceAccount,
    String? toolNamePrefix,
    Map<String, Object?>? discoverySpec,
    Map<String, Object?>? openApiSpec,
    GoogleDiscoverySpecFetcher? specFetcher,
    GoogleApiRequestExecutor? requestExecutor,
  }) : super(
         'docs',
         'v1',
         clientId: clientId,
         clientSecret: clientSecret,
         toolFilter: toolFilter,
         serviceAccount: serviceAccount,
         toolNamePrefix: toolNamePrefix,
         discoverySpec: discoverySpec,
         openApiSpec: openApiSpec,
         specFetcher: specFetcher,
         requestExecutor: requestExecutor,
       );
}
