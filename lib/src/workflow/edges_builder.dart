/// Fluent builder for workflow graph edges.
library;

import 'workflow.dart';

/// A builder for the edges of a workflow graph, declared as chains of calls
/// that start at [from] or [fromStart].
///
/// ```dart
/// final edges = EdgesBuilder()
///   ..fromStart().chain([classify, category]).route((r) {
///     r.on('billing').then(billing);
///     r.otherwise(summarize);
///   })
///   ..from(billing).then(summarize);
///
/// final workflow = Workflow(
///   name: 'support_triage',
///   nodes: [classify, category, billing, summarize],
///   edges: edges.build(),
/// );
/// ```
class EdgesBuilder {
  /// Creates an empty workflow edges builder.
  EdgesBuilder();

  final List<Edge> _edges = <Edge>[];

  /// Builds a list of [Edge]s using a builder [definition] callback.
  ///
  /// ```dart
  /// final edges = EdgesBuilder.buildEdges((g) {
  ///   g.fromStart().then(step1).then(step2);
  /// });
  /// ```
  static List<Edge> buildEdges(void Function(EdgesBuilder g) definition) {
    final EdgesBuilder builder = EdgesBuilder();
    definition(builder);
    return builder.build();
  }

  /// Starts a chain of edges at [node].
  EdgeChain from(Object node) {
    ArgumentError.checkNotNull(node, 'node');
    return EdgeChain._(this, node);
  }

  /// Starts a chain of edges at [START]: `g.fromStart().then(a)`.
  EdgeChain fromStart() => from(START);

  /// Starts a chain at [nodes] as a group so they can join without fan-out.
  NodeGroupChain fromGroup(Iterable<Object> nodes) {
    final List<Object> list = List<Object>.unmodifiable(nodes);
    if (list.isEmpty) {
      throw ArgumentError.value(nodes, 'nodes', 'Node group must not be empty.');
    }
    return NodeGroupChain._(this, list);
  }

  /// Starts a chain at [first], [second], and optional [rest] nodes as a group.
  NodeGroupChain fromNodes(Object first, Object second, [List<Object> rest = const <Object>[]]) {
    return fromGroup(<Object>[first, second, ...rest]);
  }

  /// Returns an unmodifiable list of the edges added so far.
  List<Edge> build() => List<Edge>.unmodifiable(_edges);

  void _add(Edge edge) {
    _edges.add(edge);
  }

  void _addAll(Iterable<Edge> edges) {
    _edges.addAll(edges);
  }

  static List<Edge> _edgesTo(Object from, Iterable<Object> targets, [Object? route]) {
    return <Edge>[
      for (final Object target in targets)
        Edge(fromNode: from, toNode: target, route: route),
    ];
  }
}

/// A chain of edges positioned at a node, started by [EdgesBuilder.from],
/// [EdgesBuilder.fromStart], or [NodeGroupChain.joinTo].
class EdgeChain {
  EdgeChain._(this._builder, this._node);

  final EdgesBuilder _builder;
  final Object _node;

  /// Connects the current node to [next] and continues from [next].
  EdgeChain then(Object next) {
    ArgumentError.checkNotNull(next, 'next');
    _builder._add(Edge(fromNode: _node, toNode: next));
    return EdgeChain._(_builder, next);
  }

  /// Fans out by connecting the current node to each of [targets] so they run
  /// concurrently, and continues from them as a group.
  NodeGroupChain thenGroup(Iterable<Object> targets) {
    final List<Object> nodes = List<Object>.unmodifiable(targets);
    if (nodes.isNotEmpty) {
      _builder._addAll(EdgesBuilder._edgesTo(_node, nodes));
    }
    return NodeGroupChain._(_builder, nodes);
  }

  /// Fans out by connecting the current node to each of [targets].
  NodeGroupChain thenAll(Iterable<Object> targets) => thenGroup(targets);

  /// Connects the current node to each node in [nodes] in sequential order,
  /// and continues from the last node in the chain.
  EdgeChain chain(Iterable<Object> nodes) {
    final List<Object> list = List<Object>.unmodifiable(nodes);
    if (list.isEmpty) {
      return this;
    }
    EdgeChain current = this;
    for (final Object next in list) {
      current = current.then(next);
    }
    return current;
  }

  /// Adds the current node's routing map and ends the chain.
  void route(void Function(RouteMap r) routeMapDefinition) {
    final RouteMap routeMap = RouteMap._(_node);
    routeMapDefinition(routeMap);
    final List<Edge> routeEdges = routeMap._build();
    if (routeEdges.isEmpty) {
      throw ArgumentError(
        'The routing map of node \'$_node\' needs at least one entry.',
      );
    }
    _builder._addAll(routeEdges);
  }
}

/// A chain of edges positioned at a node group from a fan-out or [EdgesBuilder.fromGroup].
class NodeGroupChain {
  NodeGroupChain._(this._builder, this._nodes);

  final EdgesBuilder _builder;
  final List<Object> _nodes;

  /// Connects each node in the group to [join], which runs once all predecessors complete,
  /// and continues from [join].
  EdgeChain joinTo(Object join) {
    ArgumentError.checkNotNull(join, 'join');
    for (final Object node in _nodes) {
      _builder._add(Edge(fromNode: node, toNode: join));
    }
    return EdgeChain._(_builder, join);
  }
}

/// A routing map configured in [EdgeChain.route] mapping routes emitted by the
/// source node to downstream target nodes.
class RouteMap {
  RouteMap._(this._from);

  final Object _from;
  final List<Edge> _edges = <Edge>[];
  final List<RouteMapEntry> _pendingEntries = <RouteMapEntry>[];
  bool _built = false;

  /// Starts an entry for [route]; [RouteMapEntry.then] completes it.
  RouteMapEntry on(Object route) {
    _checkNotBuilt();
    if (route is RouteSet) {
      return _start(route.routes);
    }
    return _start(<Object>[route]);
  }

  /// Starts an entry that fires when the source node emits any of [routes].
  RouteMapEntry onAny(Iterable<Object> routes) {
    _checkNotBuilt();
    final List<Object> list = List<Object>.unmodifiable(routes);
    return _start(list);
  }

  /// Starts or completes an entry for [route].
  ///
  /// When [first] is provided, completes the route entry immediately with
  /// [first] and optional [rest] targets.
  RouteMapEntry when(
    Object route, [
    Object? first,
    List<Object> rest = const <Object>[],
  ]) {
    final RouteMapEntry entry = on(route);
    if (first != null) {
      entry.then(first, rest);
    }
    return entry;
  }

  /// Leads to [first] and optional [rest] targets when no other route matches,
  /// including when the node emits none.
  void otherwise(Object first, [List<Object> rest = const <Object>[]]) {
    _checkNotBuilt();
    final List<Object> targets = <Object>[first, ...rest];
    for (final Object target in targets) {
      _edges.add(Edge(fromNode: _from, toNode: target, route: DEFAULT_ROUTE));
    }
  }

  /// Explicitly drops [route] without adding a target edge.
  void drop([Object? route]) {
    _checkNotBuilt();
  }

  /// Groups routes for [on] so one edge fires on any of them.
  RouteSet anyOf(Iterable<Object> routes) => RouteSet(routes);

  List<Edge> _build() {
    _built = true;
    if (_pendingEntries.isNotEmpty) {
      throw StateError(
        'on(...) in the routing map of node \'$_from\' has no target; '
        'complete it with then(node).',
      );
    }
    return List<Edge>.unmodifiable(_edges);
  }

  void _complete(RouteMapEntry entry, Object route, List<Object> targets) {
    _checkNotBuilt();
    _pendingEntries.remove(entry);
    for (final Object target in targets) {
      _edges.add(Edge(fromNode: _from, toNode: target, route: route));
    }
  }

  RouteMapEntry _start(List<Object> routes) {
    _checkNotBuilt();
    final Object routePayload = routes.length == 1 ? routes.first : routes;
    final RouteMapEntry entry = RouteMapEntry._(this, routePayload);
    _pendingEntries.add(entry);
    return entry;
  }

  void _checkNotBuilt() {
    if (_built) {
      throw StateError(
        'The routing map of node \'$_from\' was already built; '
        'add its entries inside route(...).',
      );
    }
  }
}

/// A routing-map entry started by [RouteMap.on] whose route has no target yet;
/// [then] completes it.
class RouteMapEntry {
  RouteMapEntry._(this._routeMap, this._route);

  final RouteMap _routeMap;
  final Object _route;

  /// Leads to [first] and each node in [rest] when the source node emits this entry's route.
  void then(Object first, [List<Object> rest = const <Object>[]]) {
    ArgumentError.checkNotNull(first, 'first');
    _routeMap._complete(this, _route, <Object>[first, ...rest]);
  }
}

/// A set of routes that select a single edge firing when the source emits any of them.
class RouteSet {
  /// Creates a route set from [routes].
  RouteSet(Iterable<Object> routes)
      : routes = List<Object>.unmodifiable(routes.toSet());

  /// Unique routes in this set.
  final List<Object> routes;
}
