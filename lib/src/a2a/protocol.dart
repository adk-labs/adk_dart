import 'dart:async';

enum A2aRole { user, agent }

enum A2aTaskState {
  submitted,
  working,
  inputRequired,
  authRequired,
  failed,
  completed,
}

class A2aUser {
  A2aUser({required this.userName});

  String userName;
}

class A2aCallContext {
  A2aCallContext({this.user});

  A2aUser? user;
}

abstract class A2aPartRoot {
  A2aPartRoot({Map<String, Object?>? metadata})
    : metadata = metadata ?? <String, Object?>{};

  Map<String, Object?> metadata;
}

class A2aTextPart extends A2aPartRoot {
  A2aTextPart({required this.text, super.metadata});

  String text;
}

abstract class A2aFile {
  A2aFile({this.mimeType});

  String? mimeType;
}

class A2aFileWithUri extends A2aFile {
  A2aFileWithUri({required this.uri, super.mimeType});

  String uri;
}

class A2aFileWithBytes extends A2aFile {
  A2aFileWithBytes({required this.bytes, super.mimeType});

  String bytes;
}

class A2aFilePart extends A2aPartRoot {
  A2aFilePart({required this.file, super.metadata});

  A2aFile file;
}

class A2aDataPart extends A2aPartRoot {
  A2aDataPart({Map<String, Object?>? data, super.metadata})
    : data = data ?? <String, Object?>{};

  Map<String, Object?> data;
}

class A2aPart {
  A2aPart({required this.root});

  factory A2aPart.text(String text, {Map<String, Object?>? metadata}) {
    return A2aPart(
      root: A2aTextPart(text: text, metadata: metadata),
    );
  }

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

  factory A2aPart.data(
    Map<String, Object?> data, {
    Map<String, Object?>? metadata,
  }) {
    return A2aPart(
      root: A2aDataPart(data: data, metadata: metadata),
    );
  }

  A2aPartRoot root;

  A2aTextPart? get textPart => root is A2aTextPart ? root as A2aTextPart : null;

  A2aFilePart? get filePart => root is A2aFilePart ? root as A2aFilePart : null;

  A2aDataPart? get dataPart => root is A2aDataPart ? root as A2aDataPart : null;
}

class A2aMessage {
  A2aMessage({
    required this.messageId,
    required this.role,
    List<A2aPart>? parts,
    this.taskId,
    this.contextId,
    Map<String, Object?>? metadata,
  }) : parts = parts ?? <A2aPart>[],
       metadata = metadata ?? <String, Object?>{};

  String messageId;
  A2aRole role;
  List<A2aPart> parts;
  String? taskId;
  String? contextId;
  Map<String, Object?> metadata;
}

class A2aArtifact {
  A2aArtifact({required this.artifactId, List<A2aPart>? parts})
    : parts = parts ?? <A2aPart>[];

  String artifactId;
  List<A2aPart> parts;
}

class A2aTaskStatus {
  A2aTaskStatus({required this.state, this.message, String? timestamp})
    : timestamp = timestamp ?? DateTime.now().toUtc().toIso8601String();

  A2aTaskState state;
  A2aMessage? message;
  String timestamp;
}

class A2aTask {
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

  String id;
  String contextId;
  A2aTaskStatus status;
  List<A2aMessage> history;
  List<A2aArtifact> artifacts;
  Map<String, Object?> metadata;
}

abstract class A2aEvent {}

class A2aTaskStatusUpdateEvent extends A2aEvent {
  A2aTaskStatusUpdateEvent({
    required this.taskId,
    required this.status,
    this.contextId,
    this.finalEvent = false,
    Map<String, Object?>? metadata,
  }) : metadata = metadata ?? <String, Object?>{};

  String? taskId;
  String? contextId;
  A2aTaskStatus status;
  bool finalEvent;
  Map<String, Object?> metadata;
}

class A2aTaskArtifactUpdateEvent extends A2aEvent {
  A2aTaskArtifactUpdateEvent({
    required this.taskId,
    required this.artifact,
    this.contextId,
    this.lastChunk = true,
  });

  String? taskId;
  String? contextId;
  bool lastChunk;
  A2aArtifact artifact;
}

class A2aRequestContext {
  A2aRequestContext({
    required this.taskId,
    required this.contextId,
    this.message,
    this.currentTask,
    Map<String, Object?>? metadata,
    this.callContext,
  }) : metadata = metadata ?? <String, Object?>{};

  String taskId;
  String contextId;
  A2aMessage? message;
  A2aTask? currentTask;
  Map<String, Object?> metadata;
  A2aCallContext? callContext;
}

abstract class A2aEventQueue {
  Future<void> enqueueEvent(A2aEvent event);
}

class InMemoryA2aEventQueue implements A2aEventQueue {
  final List<A2aEvent> events = <A2aEvent>[];
  final StreamController<A2aEvent> _controller =
      StreamController<A2aEvent>.broadcast();

  Stream<A2aEvent> get stream => _controller.stream;

  @override
  Future<void> enqueueEvent(A2aEvent event) async {
    events.add(event);
    _controller.add(event);
  }

  Future<void> close() async {
    await _controller.close();
  }
}

class AgentCapabilities {
  AgentCapabilities({Map<String, Object?>? values})
    : values = values ?? <String, Object?>{};

  Map<String, Object?> values;
}

class AgentProvider {
  AgentProvider({required this.name, this.url});

  String name;
  String? url;

  Map<String, Object?> toJson() => <String, Object?>{'name': name, 'url': url};

  factory AgentProvider.fromJson(Map<String, Object?> json) {
    return AgentProvider(
      name: '${json['name'] ?? ''}',
      url: json['url'] as String?,
    );
  }
}

class SecurityScheme {
  SecurityScheme({required this.type, this.description});

  String type;
  String? description;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    if (description != null) 'description': description,
  };

  factory SecurityScheme.fromJson(Map<String, Object?> json) {
    return SecurityScheme(
      type: '${json['type'] ?? ''}',
      description: json['description'] as String?,
    );
  }
}

class AgentSkill {
  AgentSkill({
    required this.id,
    required this.name,
    required this.description,
    List<String>? examples,
    List<String>? inputModes,
    List<String>? outputModes,
    List<String>? tags,
  }) : examples = examples ?? <String>[],
       inputModes = inputModes,
       outputModes = outputModes,
       tags = tags ?? <String>[];

  String id;
  String name;
  String description;
  List<String> examples;
  List<String>? inputModes;
  List<String>? outputModes;
  List<String> tags;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'description': description,
    'examples': examples,
    'input_modes': inputModes,
    'output_modes': outputModes,
    'tags': tags,
  };

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

class AgentCard {
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

  String name;
  String description;
  String url;
  String version;
  AgentCapabilities capabilities;
  List<AgentSkill> skills;
  List<String> defaultInputModes;
  List<String> defaultOutputModes;
  bool supportsAuthenticatedExtendedCard;
  String? docUrl;
  AgentProvider? provider;
  Map<String, SecurityScheme> securitySchemes;

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

class A2aApplication {
  A2aApplication({
    required this.agentCard,
    required this.executor,
    required this.taskStore,
  });

  AgentCard agentCard;
  Object executor;
  Map<String, A2aTask> taskStore;
}
