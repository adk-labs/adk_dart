/// Discovery Engine integration for verifying model answers against facts
/// with the Discovery Engine CheckGrounding API.
library;

export 'check_grounding_client.dart'
    show
        CheckGroundingApiException,
        CheckGroundingAuthHeadersProvider,
        CheckGroundingClient,
        CheckGroundingTransport,
        checkGroundingUserAgent;
export 'plugin.dart' show GroundingClient, GroundingPlugin, OnResult;
export 'types.dart'
    show Fact, FactChunk, GroundingLimits, GroundingResult, GroundingStatus;
