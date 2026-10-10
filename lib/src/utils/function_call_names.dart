/// Shared constants for ADK synthetic client and HITL function calls.
library;

/// Prefix for ADK-generated client-side function call identifiers.
const String afFunctionCallIdPrefix = 'adk-';

/// Internal function name used to request credentials.
const String requestEucFunctionCallName = 'adk_request_credential';

/// Internal function name used to request tool confirmation.
const String requestConfirmationFunctionCallName = 'adk_request_confirmation';

/// Internal function name used to request additional user input.
const String requestInputFunctionCallName = 'adk_request_input';

/// Built-in client and HITL function call names emitted by ADK.
const Set<String> clientFunctionCallNames = <String>{
  requestEucFunctionCallName,
  requestConfirmationFunctionCallName,
  requestInputFunctionCallName,
};
