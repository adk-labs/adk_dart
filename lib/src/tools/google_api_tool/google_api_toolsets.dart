import '../../auth/auth_credential.dart';
import 'google_api_tool.dart';
import 'google_api_toolset.dart';
import 'googleapi_to_openapi_converter.dart';

class BigQueryToolset extends GoogleApiToolset {
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

class CalendarToolset extends GoogleApiToolset {
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

class GmailToolset extends GoogleApiToolset {
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

class YoutubeToolset extends GoogleApiToolset {
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

class SlidesToolset extends GoogleApiToolset {
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

class SheetsToolset extends GoogleApiToolset {
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

class DocsToolset extends GoogleApiToolset {
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
