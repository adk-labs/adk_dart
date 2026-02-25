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

class Context extends ReadonlyContext {
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

  Context._internal(
    InvocationContext invocationContext,
    this._eventActions,
    this.functionCallId,
    this.toolConfirmation,
  ) : _state = State(
        value: invocationContext.session.state,
        delta: _eventActions.stateDelta,
      ),
      super(invocationContext);

  final EventActions _eventActions;
  final State _state;

  String? functionCallId;
  ToolConfirmation? toolConfirmation;

  @override
  State get state => _state;

  EventActions get actions => _eventActions;

  Future<Part?> loadArtifact(String filename, {int? version}) {
    return invocationContext.loadArtifact(filename: filename, version: version);
  }

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

  Future<ArtifactVersion?> getArtifactVersion(String filename, {int? version}) {
    return invocationContext.getArtifactVersion(
      filename: filename,
      version: version,
    );
  }

  Future<List<String>> listArtifacts() {
    return invocationContext.listArtifacts();
  }

  Future<List<int>> listArtifactVersions(String filename) {
    return invocationContext.listArtifactVersions(filename: filename);
  }

  Future<SearchMemoryResponse> searchMemory(String query) {
    return invocationContext.searchMemory(query: query);
  }

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

  Future<void> addMemory({
    required List<MemoryEntry> memories,
    Map<String, Object?>? customMetadata,
  }) {
    return invocationContext.addMemory(
      memories: memories,
      customMetadata: customMetadata,
    );
  }

  Future<void> addSessionToMemory() {
    return invocationContext.addSessionToMemory();
  }

  Future<void> deleteArtifact(String filename) {
    return invocationContext.deleteArtifact(filename: filename);
  }

  Future<void> saveCredential(AuthConfig authConfig) async {
    final Object? service = invocationContext.credentialService;
    if (service is! BaseCredentialService) {
      throw StateError('Credential service is not initialized.');
    }
    await service.saveCredential(authConfig, this);
  }

  Future<AuthCredential?> loadCredential(AuthConfig authConfig) async {
    final Object? service = invocationContext.credentialService;
    if (service is! BaseCredentialService) {
      throw StateError('Credential service is not initialized.');
    }
    return service.loadCredential(authConfig, this);
  }

  AuthCredential? getAuthResponse(AuthConfig authConfig) {
    return AuthHandler(authConfig: authConfig).getAuthResponse(state);
  }

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
