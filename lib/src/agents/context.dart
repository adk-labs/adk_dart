/// Mutable execution context used by tools and callbacks.
library;

import '../events/event_actions.dart';
import '../events/event.dart';
import '../auth/auth_credential.dart';
import '../auth/auth_handler.dart';
import '../auth/auth_tool.dart';
import '../auth/credential_service/base_credential_service.dart';
import '../memory/base_memory_service.dart';
import '../memory/memory_entry.dart';
import '../sessions/state.dart';
import '../tools/tool_confirmation.dart';
import '../types/content.dart';
import 'invocation_context.dart';
import 'readonly_context.dart';
import '../artifacts/base_artifact_service.dart';

/// Mutable context for a single agent invocation.
class Context extends ReadonlyContext {
  /// Creates a mutable [Context] backed by [invocationContext].
  factory Context(
    InvocationContext invocationContext, {
    EventActions? eventActions,
    String? functionCallId,
    ToolConfirmation? toolConfirmation,
  }) {
    final EventActions resolvedEventActions = eventActions ?? EventActions();
    return Context._internal(
      invocationContext,
      resolvedEventActions,
      functionCallId,
      toolConfirmation,
    );
  }

  /// Creates a mutable [Context] with pre-resolved action containers.
  Context._internal(
    super.invocationContext,
    this._eventActions,
    this.functionCallId,
    this.toolConfirmation,
  ) : _state = State(
        value: invocationContext.session.state,
        delta: _eventActions.stateDelta,
      );

  /// Event action accumulator for this invocation.
  final EventActions _eventActions;

  /// Mutable state view and delta writer.
  final State _state;

  /// Current function-call ID when running inside a tool invocation.
  String? functionCallId;

  /// Current tool confirmation payload, if present.
  ToolConfirmation? toolConfirmation;

  /// Mutable session state for this invocation.
  @override
  State get state => _state;

  /// Buffered actions collected during this invocation.
  EventActions get actions => _eventActions;

  /// Loads an artifact [filename] and optional [version].
  Future<Part?> loadArtifact(String filename, {int? version}) {
    return invocationContext.loadArtifact(filename: filename, version: version);
  }

  /// Saves [artifact] to [filename] and returns its new version.
  Future<int> saveArtifact(
    String filename,
    Part artifact, {
    Map<String, Object?>? customMetadata,
  }) async {
    final int version = await invocationContext.saveArtifact(
      filename: filename,
      artifact: artifact,
      customMetadata: customMetadata,
    );
    _eventActions.artifactDelta[filename] = version;
    return version;
  }

  /// Returns metadata for an artifact [filename] and optional [version].
  Future<ArtifactVersion?> getArtifactVersion(String filename, {int? version}) {
    return invocationContext.getArtifactVersion(
      filename: filename,
      version: version,
    );
  }

  /// Lists artifact filenames for this session.
  Future<List<String>> listArtifacts() {
    return invocationContext.listArtifacts();
  }

  /// Lists available versions for artifact [filename].
  Future<List<int>> listArtifactVersions(String filename) {
    return invocationContext.listArtifactVersions(filename: filename);
  }

  /// Searches memory entries using [query].
  Future<SearchMemoryResponse> searchMemory(String query) {
    return invocationContext.searchMemory(query: query);
  }

  /// Adds [events] to memory for this or another [sessionId].
  Future<void> addEventsToMemory({
    required List<Event> events,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) {
    return invocationContext.addEventsToMemory(
      events: events,
      sessionId: sessionId,
      customMetadata: customMetadata,
    );
  }

  /// Adds explicit [memories] to the memory service.
  Future<void> addMemory({
    required List<MemoryEntry> memories,
    Map<String, Object?>? customMetadata,
  }) {
    return invocationContext.addMemory(
      memories: memories,
      customMetadata: customMetadata,
    );
  }

  /// Persists the current session transcript to memory.
  Future<void> addSessionToMemory() {
    return invocationContext.addSessionToMemory();
  }

  /// Deletes artifact [filename] and its versions.
  Future<void> deleteArtifact(String filename) {
    return invocationContext.deleteArtifact(filename: filename);
  }

  /// Saves a credential resolved from [authConfig].
  ///
  /// Throws a [StateError] when credential services are unavailable.
  Future<void> saveCredential(AuthConfig authConfig) async {
    final Object? service = invocationContext.credentialService;
    if (service is! BaseCredentialService) {
      throw StateError('Credential service is not initialized.');
    }
    await service.saveCredential(authConfig, this);
  }

  /// Loads a credential for [authConfig], if available.
  ///
  /// Throws a [StateError] when credential services are unavailable.
  Future<AuthCredential?> loadCredential(AuthConfig authConfig) async {
    final Object? service = invocationContext.credentialService;
    if (service is! BaseCredentialService) {
      throw StateError('Credential service is not initialized.');
    }
    return service.loadCredential(authConfig, this);
  }

  /// Returns an auth response payload derived from [authConfig].
  AuthCredential? getAuthResponse(AuthConfig authConfig) {
    return AuthHandler(authConfig: authConfig).getAuthResponse(state);
  }

  /// Requests user confirmation for the current tool call.
  ///
  /// Throws a [StateError] when this context is not bound to a tool call.
  void requestConfirmation({String? hint, Object? payload}) {
    final String? callId = functionCallId;
    if (callId == null || callId.isEmpty) {
      throw StateError(
        'requestConfirmation requires functionCallId. This method can only be used in a tool context.',
      );
    }

    _eventActions.requestedToolConfirmations[callId] = ToolConfirmation(
      hint: hint,
      payload: payload,
    );
  }

  /// Requests authentication input for the current tool call.
  ///
  /// Throws a [StateError] when this context is not bound to a tool call.
  void requestCredential(Object authConfig) {
    final String? callId = functionCallId;
    if (callId == null || callId.isEmpty) {
      throw StateError(
        'requestCredential requires functionCallId. This method can only be used in a tool context.',
      );
    }
    if (authConfig is AuthConfig) {
      _eventActions.requestedAuthConfigs[callId] = AuthHandler(
        authConfig: authConfig,
      ).generateAuthRequest();
      return;
    }
    _eventActions.requestedAuthConfigs[callId] = authConfig;
  }
}
