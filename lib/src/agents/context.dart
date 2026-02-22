import '../events/event_actions.dart';
import '../sessions/state.dart';
import '../tools/tool_confirmation.dart';
import '../types/content.dart';
import 'invocation_context.dart';
import 'readonly_context.dart';
import '../artifacts/base_artifact_service.dart';

class Context extends ReadonlyContext {
  Context(
    InvocationContext invocationContext, {
    EventActions? eventActions,
    this.functionCallId,
    this.toolConfirmation,
  }) : _eventActions = eventActions ?? EventActions(),
       _state = State(
         value: invocationContext.session.state,
         delta: (eventActions ?? EventActions()).stateDelta,
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

  Future<void> deleteArtifact(String filename) {
    return invocationContext.deleteArtifact(filename: filename);
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
    _eventActions.requestedAuthConfigs[callId] = authConfig;
  }
}
