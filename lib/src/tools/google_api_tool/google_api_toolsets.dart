/// Preconfigured Google API toolset wrappers for common services.
library;

import 'google_api_toolset.dart';

/// Google BigQuery API toolset wrapper.
class BigQueryToolset extends GoogleApiToolset {
  /// Creates a BigQuery toolset.
  BigQueryToolset({
    super.clientId,
    super.clientSecret,
    super.toolFilter,
    super.serviceAccount,
    super.toolNamePrefix,
    super.discoverySpec,
    super.openApiSpec,
    super.specFetcher,
    super.requestExecutor,
  }) : super(
         'bigquery',
         'v2',
       );
}

/// Google Calendar API toolset wrapper.
class CalendarToolset extends GoogleApiToolset {
  /// Creates a Calendar toolset.
  CalendarToolset({
    super.clientId,
    super.clientSecret,
    super.toolFilter,
    super.serviceAccount,
    super.toolNamePrefix,
    super.discoverySpec,
    super.openApiSpec,
    super.specFetcher,
    super.requestExecutor,
  }) : super(
         'calendar',
         'v3',
       );
}

/// Google Gmail API toolset wrapper.
class GmailToolset extends GoogleApiToolset {
  /// Creates a Gmail toolset.
  GmailToolset({
    super.clientId,
    super.clientSecret,
    super.toolFilter,
    super.serviceAccount,
    super.toolNamePrefix,
    super.discoverySpec,
    super.openApiSpec,
    super.specFetcher,
    super.requestExecutor,
  }) : super(
         'gmail',
         'v1',
       );
}

/// YouTube Data API toolset wrapper.
class YoutubeToolset extends GoogleApiToolset {
  /// Creates a YouTube toolset.
  YoutubeToolset({
    super.clientId,
    super.clientSecret,
    super.toolFilter,
    super.serviceAccount,
    super.toolNamePrefix,
    super.discoverySpec,
    super.openApiSpec,
    super.specFetcher,
    super.requestExecutor,
  }) : super(
         'youtube',
         'v3',
       );
}

/// Google Slides API toolset wrapper.
class SlidesToolset extends GoogleApiToolset {
  /// Creates a Slides toolset.
  SlidesToolset({
    super.clientId,
    super.clientSecret,
    super.toolFilter,
    super.serviceAccount,
    super.toolNamePrefix,
    super.discoverySpec,
    super.openApiSpec,
    super.specFetcher,
    super.requestExecutor,
  }) : super(
         'slides',
         'v1',
       );
}

/// Google Sheets API toolset wrapper.
class SheetsToolset extends GoogleApiToolset {
  /// Creates a Sheets toolset.
  SheetsToolset({
    super.clientId,
    super.clientSecret,
    super.toolFilter,
    super.serviceAccount,
    super.toolNamePrefix,
    super.discoverySpec,
    super.openApiSpec,
    super.specFetcher,
    super.requestExecutor,
  }) : super(
         'sheets',
         'v4',
       );
}

/// Google Docs API toolset wrapper.
class DocsToolset extends GoogleApiToolset {
  /// Creates a Docs toolset.
  DocsToolset({
    super.clientId,
    super.clientSecret,
    super.toolFilter,
    super.serviceAccount,
    super.toolNamePrefix,
    super.discoverySpec,
    super.openApiSpec,
    super.specFetcher,
    super.requestExecutor,
  }) : super(
         'docs',
         'v1',
       );
}
