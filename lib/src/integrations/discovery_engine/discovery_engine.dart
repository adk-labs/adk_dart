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
export 'types.dart'
    show FactChunk, GroundingLimits, GroundingResult, GroundingStatus;
