import '../agents/context.dart';
import '../events/event.dart';
import '../events/node_path_builder.dart';
import '../types/content.dart';
import 'workflow.dart';

/// ReplayManager - unified orchestrator for event rehydration, interception, and sequence barriers.
class ReplayManager {
  ReplayManager();

  final Map<String, ReplaySequenceBarrier> _parentSequenceBarriers =
      <String, ReplaySequenceBarrier>{};
  final Map<String, List<Event>> _eventsByParent = <String, List<Event>>{};
  final Map<String, List<Event>> _transitiveEventsByParent =
      <String, List<Event>>{};
  int _indexedEventCount = -1;

  void _ensureIndex(Context ctx) {
    final List<Event> events = ctx.invocationContext.session.events;
    if (_indexedEventCount != events.length) {
      _buildEventIndex(events, ctx.invocationContext.invocationId);
      _indexedEventCount = events.length;
    }
  }

  void _buildEventIndex(List<Event> events, String invocationId) {
    _eventsByParent.clear();
    _transitiveEventsByParent.clear();
    final Map<String, String> fcToParent = <String, String>{};

    for (final Event event in events) {
      if (event.author == 'user') {
        _indexUserEvent(event, fcToParent);
        continue;
      }

      final String path = event.nodeInfo.path;
      if (path.isEmpty) {
        continue;
      }

      final NodePathBuilder pathBuilder = NodePathBuilder.fromString(path);
      final String parentPath =
          pathBuilder.parent != null ? pathBuilder.parent.toString() : '';

      _addEventToIndex(parentPath, event);

      // Track interrupts to route future user responses
      final Set<String> interruptIds = <String>{
        ...?event.longRunningToolIds,
        ...event.actions.requestedToolConfirmations.keys,
      };
      for (final String fid in interruptIds) {
        fcToParent[fid] = parentPath;
      }
    }
  }

  void _indexUserEvent(Event event, Map<String, String> fcToParent) {
    final Content? content = event.content;
    if (content == null || content.parts.isEmpty) {
      return;
    }
    bool matched = false;
    final Set<String> addedParents = <String>{};
    for (final Part part in content.parts) {
      final String? frId = part.functionResponse?.id;
      if (frId != null && frId.isNotEmpty && fcToParent.containsKey(frId)) {
        final String parent = fcToParent[frId]!;
        if (!addedParents.contains(parent)) {
          _addEventToIndex(parent, event);
          addedParents.add(parent);
          matched = true;
        }
      }
    }

    if (!matched) {
      // General user prompt event: add to root ("")
      _eventsByParent.putIfAbsent('', () => <Event>[]).add(event);
      _transitiveEventsByParent.putIfAbsent('', () => <Event>[]).add(event);
    }
  }

  void _addEventToIndex(String parentPath, Event event) {
    _eventsByParent.putIfAbsent(parentPath, () => <Event>[]).add(event);

    NodePathBuilder? curr = parentPath.isNotEmpty
        ? NodePathBuilder.fromString(parentPath)
        : null;
    while (curr != null && curr.toString().isNotEmpty) {
      _transitiveEventsByParent
          .putIfAbsent(curr.toString(), () => <Event>[])
          .add(event);
      curr = curr.parent;
    }

    _transitiveEventsByParent.putIfAbsent('', () => <Event>[]).add(event);
  }

  /// Retrieves pre-filtered session events relevant to rehydrating a node path.
  List<Event> getEventsForRehydration(Context ctx, String nodePath) {
    if (nodePath.isEmpty) {
      return <Event>[];
    }

    _ensureIndex(ctx);
    final NodePathBuilder pathBuilder = NodePathBuilder.fromString(nodePath);
    final NodePathBuilder? parentBuilder = pathBuilder.parent;
    if (parentBuilder == null || parentBuilder.toString().isEmpty) {
      return ctx.invocationContext.session.events;
    }
    final String parentPath = parentBuilder.toString();

    final List<Event> nodeEvents =
        _transitiveEventsByParent[parentPath] ?? <Event>[];
    if (nodeEvents.isEmpty) {
      return ctx.invocationContext.session.events;
    }

    // Top-level user text prompts live under root key ("").
    final List<Event> rootEvents = _eventsByParent[''] ?? <Event>[];
    final List<Event> userPrompts = rootEvents
        .where((Event e) => e.author == 'user' && !nodeEvents.contains(e))
        .toList();

    if (userPrompts.isEmpty) {
      return nodeEvents;
    }

    final List<Event> sessionEvents = ctx.invocationContext.session.events;
    final Set<Event> eventSet = <Event>{...nodeEvents, ...userPrompts};
    return sessionEvents.where(eventSet.contains).toList();
  }

  /// Ensure a sequence barrier is set up for dynamic nodes under parentPath.
  ReplaySequenceBarrier prepareParentSequenceBarrier(
      Context ctx, String parentPath) {
    return _parentSequenceBarriers.putIfAbsent(parentPath, () {
      _ensureIndex(ctx);
      final List<Event> events = _eventsByParent[parentPath] ?? <Event>[];
      final List<String> seq =
          _scanSequence(events, ctx, parentPath, strictDirectChild: true);
      return ReplaySequenceBarrier(seq);
    });
  }

  List<String> _scanSequence(
    List<Event> events,
    Context ctx,
    String basePath, {
    required bool strictDirectChild,
  }) {
    final NodePathBuilder basePathBuilder = NodePathBuilder.fromString(basePath);
    final List<String> sequence = <String>[];

    for (final Event event in events) {
      final String eventNodePath = event.nodeInfo.path;
      final NodePathBuilder eventPathBuilder =
          NodePathBuilder.fromString(eventNodePath);

      if (!eventPathBuilder.isDescendantOf(basePathBuilder)) {
        continue;
      }

      final NodePathBuilder childPath =
          basePathBuilder.getDirectChild(eventPathBuilder);
      if (strictDirectChild && eventPathBuilder != childPath) {
        continue;
      }

      final String segment = childPath.leafSegment;

      if (event.isFinalResponse() ||
          event.actions.route != null ||
          event.longRunningToolIds?.isNotEmpty == true) {
        if (sequence.contains(segment)) {
          sequence.remove(segment);
        }
        sequence.add(segment);
      }
    }

    return sequence;
  }

  /// Advance sequence barrier if initialized for parentPath.
  void advanceSequence(String parentPath, String key) {
    _parentSequenceBarriers[parentPath]?.checkAndAdvance(key);
  }

  /// Wait for sequence barrier if initialized for parentPath.
  Future<void> waitSequence(String parentPath, String key) async {
    await _parentSequenceBarriers[parentPath]?.wait(key);
  }
}
