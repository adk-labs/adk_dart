/// Core A2A protocol models used by routing, execution, and transport layers.
library;

import 'dart:async';

/// Message author role in the A2A protocol.
enum A2aRole { user, agent }

/// Task lifecycle states in the A2A protocol.
enum A2aTaskState {
  submitted,
  working,
  inputRequired,
  authRequired,
  failed,
  completed,
}

/// End-user identity attached to a call context.
class A2aUser {
  /// Creates an A2A user identity.
  A2aUser({required this.userName});

  /// User name identifier.
  String userName;
}

/// Call context metadata sent with A2A requests.
class A2aCallContext {
  /// Creates a call context.
  A2aCallContext({this.user});

  /// Optional end-user identity.
  A2aUser? user;
}

/// Base interface for all A2A message parts.
abstract class A2aPartRoot {
  /// Creates a part root with optional [metadata].
  A2aPartRoot({Map<String, Object?>? metadata})
    : metadata = metadata ?? <String, Object?>{};

  /// Part metadata payload.
  Map<String, Object?> metadata;
}

/// Text part payload.
class A2aTextPart extends A2aPartRoot {
  /// Creates a text part.
  A2aTextPart({required this.text, super.metadata});

  /// Text value.
  String text;
}

/// Base interface for file payload variants.
abstract class A2aFile {
  /// Creates a file payload descriptor.
  A2aFile({this.mimeType});

  /// Optional MIME type.
  String? mimeType;
}

/// File payload referencing a URI.
class A2aFileWithUri extends A2aFile {
  /// Creates a file payload from [uri].
  A2aFileWithUri({required this.uri, super.mimeType});

  /// File URI.
  String uri;
}

/// File payload embedding bytes (typically base64-encoded).
class A2aFileWithBytes extends A2aFile {
  /// Creates a file payload from [bytes].
  A2aFileWithBytes({required this.bytes, super.mimeType});

  /// File bytes payload.
  String bytes;
}

/// Part payload that wraps an [A2aFile].
class A2aFilePart extends A2aPartRoot {
  /// Creates a file part.
  A2aFilePart({required this.file, super.metadata});

  /// File payload.
  A2aFile file;
}

/// Part payload carrying JSON-like structured data.
class A2aDataPart extends A2aPartRoot {
  /// Creates a data part.
  A2aDataPart({Map<String, Object?>? data, super.metadata})
    : data = data ?? <String, Object?>{};

  /// Structured data payload.
  Map<String, Object?> data;
}

/// Wrapper for concrete part payload variants.
class A2aPart {
  /// Creates a part from a concrete [root] payload.
  A2aPart({required this.root});

  /// Creates a text part wrapper.
  factory A2aPart.text(String text, {Map<String, Object?>? metadata}) {
    return A2aPart(
      root: A2aTextPart(text: text, metadata: metadata),
    );
  }

  /// Creates a URI file part wrapper.
  factory A2aPart.fileUri(
    String uri, {
    String? mimeType,
    Map<String, Object?>? metadata,
  }) {
    return A2aPart(
      root: A2aFilePart(
        file: A2aFileWithUri(uri: uri, mimeType: mimeType),
        metadata: metadata,
      ),
    );
  }

  /// Creates an inline-bytes file part wrapper.
  factory A2aPart.fileBytes(
    String bytes, {
    String? mimeType,
    Map<String, Object?>? metadata,
  }) {
    return A2aPart(
      root: A2aFilePart(
        file: A2aFileWithBytes(bytes: bytes, mimeType: mimeType),
        metadata: metadata,
      ),
    );
  }

  /// Creates a structured-data part wrapper.
  factory A2aPart.data(
    Map<String, Object?> data, {
    Map<String, Object?>? metadata,
  }) {
    return A2aPart(
      root: A2aDataPart(data: data, metadata: metadata),
    );
  }

  /// Concrete part root payload.
  A2aPartRoot root;

  /// Text payload view when [root] is [A2aTextPart].
  A2aTextPart? get textPart => root is A2aTextPart ? root as A2aTextPart : null;

  /// File payload view when [root] is [A2aFilePart].
  A2aFilePart? get filePart => root is A2aFilePart ? root as A2aFilePart : null;

  /// Data payload view when [root] is [A2aDataPart].
  A2aDataPart? get dataPart => root is A2aDataPart ? root as A2aDataPart : null;
}

/// Message envelope used by A2A requests and task history.
class A2aMessage {
  /// Creates an A2A message.
  A2aMessage({
    required this.messageId,
    required this.role,
    List<A2aPart>? parts,
    this.taskId,
    this.contextId,
    Map<String, Object?>? metadata,
  }) : parts = parts ?? <A2aPart>[],
       metadata = metadata ?? <String, Object?>{};

  /// Message identifier.
  String messageId;

  /// Author role for this message.
  A2aRole role;

  /// Ordered part payloads.
  List<A2aPart> parts;

  /// Optional task identifier.
  String? taskId;

  /// Optional context identifier.
  String? contextId;

  /// Additional metadata.
  Map<String, Object?> metadata;
}

/// Artifact payload produced by a task.
class A2aArtifact {
  /// Creates an artifact envelope.
  A2aArtifact({required this.artifactId, List<A2aPart>? parts})
    : parts = parts ?? <A2aPart>[];

  /// Artifact identifier.
  String artifactId;

  /// Artifact part payloads.
  List<A2aPart> parts;
}

/// Status snapshot for an A2A task.
class A2aTaskStatus {
  /// Creates a task status snapshot.
  A2aTaskStatus({required this.state, this.message, String? timestamp})
    : timestamp = timestamp ?? DateTime.now().toUtc().toIso8601String();

  /// Current task state.
  A2aTaskState state;

  /// Optional status message.
  A2aMessage? message;

  /// Status timestamp in ISO-8601 UTC format.
  String timestamp;
}

/// Task container for ongoing or completed A2A work.
class A2aTask {
  /// Creates an A2A task.
  A2aTask({
    required this.id,
    required this.contextId,
    required this.status,
    List<A2aMessage>? history,
    List<A2aArtifact>? artifacts,
    Map<String, Object?>? metadata,
  }) : history = history ?? <A2aMessage>[],
       artifacts = artifacts ?? <A2aArtifact>[],
       metadata = metadata ?? <String, Object?>{};

  /// Task identifier.
  String id;

  /// Context identifier.
  String contextId;

  /// Current task status.
  A2aTaskStatus status;

  /// Historical message transcript.
  List<A2aMessage> history;

  /// Produced artifacts.
  List<A2aArtifact> artifacts;

  /// Task metadata.
  Map<String, Object?> metadata;
}

/// Base type for all A2A stream events.
abstract class A2aEvent {}

/// Event carrying task status updates.
class A2aTaskStatusUpdateEvent extends A2aEvent {
  /// Creates a status-update event.
  A2aTaskStatusUpdateEvent({
    required this.taskId,
    required this.status,
    this.contextId,
    this.finalEvent = false,
    Map<String, Object?>? metadata,
  }) : metadata = metadata ?? <String, Object?>{};

  /// Task identifier.
  String? taskId;

  /// Context identifier.
  String? contextId;

  /// New task status.
  A2aTaskStatus status;

  /// Whether this event is terminal for the current task.
  bool finalEvent;

  /// Event metadata.
  Map<String, Object?> metadata;
}

/// Event carrying task artifact updates.
class A2aTaskArtifactUpdateEvent extends A2aEvent {
  /// Creates an artifact-update event.
  A2aTaskArtifactUpdateEvent({
    required this.taskId,
    required this.artifact,
    this.contextId,
    this.lastChunk = true,
    this.append = false,
  });

  /// Task identifier.
  String? taskId;

  /// Context identifier.
  String? contextId;

  /// Whether this is the last artifact chunk.
  bool lastChunk;

  /// Whether this chunk appends to an existing artifact stream.
  bool append;

  /// Artifact payload.
  A2aArtifact artifact;
}

/// Incoming request context supplied to A2A executors.
class A2aRequestContext {
  /// Creates an A2A request context.
  A2aRequestContext({
    required this.taskId,
    required this.contextId,
    this.message,
    this.currentTask,
    Map<String, Object?>? metadata,
    this.callContext,
  }) : metadata = metadata ?? <String, Object?>{};

  /// Task identifier for this request.
  String taskId;

  /// Context identifier for this request.
  String contextId;

  /// Incoming message payload.
  A2aMessage? message;

  /// Current task snapshot, when resuming.
  A2aTask? currentTask;

  /// Request metadata.
  Map<String, Object?> metadata;

  /// Optional call context.
  A2aCallContext? callContext;
}

/// Queue contract used to emit A2A events.
abstract class A2aEventQueue {
  /// Enqueues one A2A [event].
  Future<void> enqueueEvent(A2aEvent event);
}

/// In-memory event queue implementation for A2A flows.
class InMemoryA2aEventQueue implements A2aEventQueue {
  /// Buffered emitted events.
  final List<A2aEvent> events = <A2aEvent>[];
  final StreamController<A2aEvent> _controller =
      StreamController<A2aEvent>.broadcast();

  /// Broadcast stream of emitted events.
  Stream<A2aEvent> get stream => _controller.stream;

  @override
  Future<void> enqueueEvent(A2aEvent event) async {
    events.add(event);
    _controller.add(event);
  }

  /// Closes the queue stream.
  Future<void> close() async {
    await _controller.close();
  }
}

/// Extensible capability map for agent cards.
class AgentCapabilities {
  /// Creates an agent capability map.
  AgentCapabilities({Map<String, Object?>? values})
    : values = values ?? <String, Object?>{};

  /// Capability values keyed by name.
  Map<String, Object?> values;
}

/// Provider information for an agent card.
class AgentProvider {
  /// Creates an agent provider descriptor.
  AgentProvider({required this.name, this.url});

  /// Provider name.
  String name;

  /// Optional provider URL.
  String? url;

  /// Serializes this provider to JSON.
  Map<String, Object?> toJson() => <String, Object?>{'name': name, 'url': url};

  /// Creates a provider descriptor from JSON.
  factory AgentProvider.fromJson(Map<String, Object?> json) {
    return AgentProvider(
      name: '${json['name'] ?? ''}',
      url: json['url'] as String?,
    );
  }
}

/// Security scheme descriptor for authenticated agent cards.
class SecurityScheme {
  /// Creates a security scheme descriptor.
  SecurityScheme({required this.type, this.description});

  /// Security scheme type (for example `oauth2`).
  String type;

  /// Optional description.
  String? description;

  /// Serializes this security scheme to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    if (description != null) 'description': description,
  };

  /// Creates a security scheme from JSON.
  factory SecurityScheme.fromJson(Map<String, Object?> json) {
    return SecurityScheme(
      type: '${json['type'] ?? ''}',
      description: json['description'] as String?,
    );
  }
}

/// Skill descriptor listed in an agent card.
class AgentSkill {
  /// Creates an agent skill.
  AgentSkill({
    required this.id,
    required this.name,
    required this.description,
    List<String>? examples,
    this.inputModes,
    this.outputModes,
    List<String>? tags,
  }) : examples = examples ?? <String>[],
       tags = tags ?? <String>[];

  /// Skill identifier.
  String id;

  /// Skill name.
  String name;

  /// Skill description.
  String description;

  /// Example prompts or inputs.
  List<String> examples;

  /// Supported input mime types.
  List<String>? inputModes;

  /// Supported output mime types.
  List<String>? outputModes;

  /// Skill tags.
  List<String> tags;

  /// Serializes this skill to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'description': description,
    'examples': examples,
    'input_modes': inputModes,
    'output_modes': outputModes,
    'tags': tags,
  };

  /// Creates a skill descriptor from JSON.
  factory AgentSkill.fromJson(Map<String, Object?> json) {
    return AgentSkill(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      examples: (json['examples'] as List?)?.map((Object? e) => '$e').toList(),
      inputModes: (json['input_modes'] as List?)
          ?.map((Object? e) => '$e')
          .toList(),
      outputModes: (json['output_modes'] as List?)
          ?.map((Object? e) => '$e')
          .toList(),
      tags: (json['tags'] as List?)?.map((Object? e) => '$e').toList(),
    );
  }
}

/// Agent-card payload exposed over A2A discovery endpoints.
class AgentCard {
  /// Creates an agent card.
  AgentCard({
    required this.name,
    required this.description,
    required this.url,
    required this.version,
    AgentCapabilities? capabilities,
    List<AgentSkill>? skills,
    List<String>? defaultInputModes,
    List<String>? defaultOutputModes,
    this.supportsAuthenticatedExtendedCard = false,
    this.docUrl,
    this.provider,
    Map<String, SecurityScheme>? securitySchemes,
  }) : capabilities = capabilities ?? AgentCapabilities(),
       skills = skills ?? <AgentSkill>[],
       defaultInputModes = defaultInputModes ?? <String>['text/plain'],
       defaultOutputModes = defaultOutputModes ?? <String>['text/plain'],
       securitySchemes = securitySchemes ?? <String, SecurityScheme>{};

  /// Agent display name.
  String name;

  /// Agent description.
  String description;

  /// Agent RPC URL.
  String url;

  /// Agent card version.
  String version;

  /// Capability map.
  AgentCapabilities capabilities;

  /// Published skill descriptors.
  List<AgentSkill> skills;

  /// Default input mime types.
  List<String> defaultInputModes;

  /// Default output mime types.
  List<String> defaultOutputModes;

  /// Whether extended authenticated cards are supported.
  bool supportsAuthenticatedExtendedCard;

  /// Optional documentation URL.
  String? docUrl;

  /// Optional provider metadata.
  AgentProvider? provider;

  /// Optional security-scheme map.
  Map<String, SecurityScheme> securitySchemes;

  /// Serializes this card to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'description': description,
      'url': url,
      'version': version,
      'capabilities': capabilities.values,
      'skills': skills.map((AgentSkill s) => s.toJson()).toList(),
      'default_input_modes': defaultInputModes,
      'default_output_modes': defaultOutputModes,
      'supports_authenticated_extended_card': supportsAuthenticatedExtendedCard,
      if (docUrl != null) 'doc_url': docUrl,
      if (provider != null) 'provider': provider!.toJson(),
      if (securitySchemes.isNotEmpty)
        'security_schemes': securitySchemes.map(
          (String k, SecurityScheme v) =>
              MapEntry<String, Object?>(k, v.toJson()),
        ),
    };
  }

  /// Creates an agent card from JSON.
  factory AgentCard.fromJson(Map<String, Object?> json) {
    final Map<String, SecurityScheme> schemes = <String, SecurityScheme>{};
    final Object? rawSchemes = json['security_schemes'];
    if (rawSchemes is Map) {
      rawSchemes.forEach((Object? key, Object? value) {
        if (key is String && value is Map<String, Object?>) {
          schemes[key] = SecurityScheme.fromJson(value);
        } else if (key is String && value is Map) {
          schemes[key] = SecurityScheme.fromJson(
            value.map(
              (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
            ),
          );
        }
      });
    }

    return AgentCard(
      name: '${json['name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      url: '${json['url'] ?? ''}',
      version: '${json['version'] ?? ''}',
      capabilities: AgentCapabilities(
        values:
            (json['capabilities'] as Map<String, Object?>?) ??
            <String, Object?>{},
      ),
      skills: (json['skills'] as List?)
          ?.whereType<Map>()
          .map(
            (Map s) => AgentSkill.fromJson(
              s.map(
                (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
              ),
            ),
          )
          .toList(),
      defaultInputModes: (json['default_input_modes'] as List?)
          ?.map((Object? e) => '$e')
          .toList(),
      defaultOutputModes: (json['default_output_modes'] as List?)
          ?.map((Object? e) => '$e')
          .toList(),
      supportsAuthenticatedExtendedCard:
          json['supports_authenticated_extended_card'] == true,
      docUrl: json['doc_url'] as String?,
      provider: json['provider'] is Map
          ? AgentProvider.fromJson(
              (json['provider'] as Map).map(
                (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
              ),
            )
          : null,
      securitySchemes: schemes,
    );
  }
}

/// In-memory A2A application bundle of card, executor, and task store.
class A2aApplication {
  /// Creates an A2A application bundle.
  A2aApplication({
    required this.agentCard,
    required this.executor,
    required this.taskStore,
  });

  /// Agent card exposed to callers.
  AgentCard agentCard;

  /// Executor implementation handling requests.
  Object executor;

  /// In-memory task store keyed by task ID.
  Map<String, A2aTask> taskStore;
}
