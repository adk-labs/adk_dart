/// Path builder for hierarchical workflow node paths.
library;

/// Represents a path to a node in a hierarchical workflow.
///
/// A node path is a sequence of segments, each identifying a node instance,
/// typically in the form `node_name@run_id` or just `node_name`.
class NodePathBuilder {
  /// Creates a node path from [segments].
  NodePathBuilder(Iterable<String> segments)
    : _segments = List<String>.unmodifiable(segments);

  final List<String> _segments;

  /// Parses a node path from a slash-separated string.
  factory NodePathBuilder.fromString(String path) {
    if (path.isEmpty) {
      return NodePathBuilder(const <String>[]);
    }
    return NodePathBuilder(path.split('/'));
  }

  /// Path segments.
  List<String> get segments => _segments;

  /// Name of the leaf node without its run ID suffix.
  String get nodeName {
    if (_segments.isEmpty) {
      return '';
    }
    return _segments.last.splitRunId().name;
  }

  /// Full leaf segment.
  String get leafSegment {
    if (_segments.isEmpty) {
      return '';
    }
    return _segments.last;
  }

  /// Run ID of the leaf segment, if present.
  String? get runId {
    if (_segments.isEmpty) {
      return null;
    }
    return _segments.last.splitRunId().runId;
  }

  /// Parent path, or `null` for root/empty paths.
  NodePathBuilder? get parent {
    if (_segments.length <= 1) {
      return null;
    }
    return NodePathBuilder(_segments.take(_segments.length - 1));
  }

  /// Returns a new path with [nodeName] appended.
  NodePathBuilder append(String nodeName, [String? runId]) {
    final String segment = runId == null || runId.isEmpty
        ? nodeName
        : '$nodeName@$runId';
    return NodePathBuilder(<String>[..._segments, segment]);
  }

  /// Whether this path is a strict descendant of [ancestor].
  bool isDescendantOf(NodePathBuilder ancestor) {
    if (_segments.length <= ancestor._segments.length) {
      return false;
    }
    return _startsWith(ancestor._segments);
  }

  /// Whether this path is a direct child of [parent].
  bool isDirectChildOf(NodePathBuilder parent) {
    if (_segments.length != parent._segments.length + 1) {
      return false;
    }
    return _startsWith(parent._segments);
  }

  /// Returns the direct child path from this path toward [descendant].
  NodePathBuilder getDirectChild(NodePathBuilder descendant) {
    if (descendant._segments.length <= _segments.length) {
      throw ArgumentError('Descendant path is not longer than self path');
    }
    if (!descendant._startsWith(_segments)) {
      throw ArgumentError('Descendant path does not start with self path');
    }
    return NodePathBuilder(descendant._segments.take(_segments.length + 1));
  }

  bool _startsWith(List<String> prefix) {
    if (_segments.length < prefix.length) {
      return false;
    }
    for (int i = 0; i < prefix.length; i++) {
      if (_segments[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() => _segments.join('/');

  @override
  bool operator ==(Object other) {
    if (other is! NodePathBuilder ||
        other._segments.length != _segments.length) {
      return false;
    }
    for (int i = 0; i < _segments.length; i++) {
      if (_segments[i] != other._segments[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_segments);
}

class _NodePathSegment {
  const _NodePathSegment({required this.name, this.runId});

  final String name;

  final String? runId;
}

extension on String {
  _NodePathSegment splitRunId() {
    final int marker = lastIndexOf('@');
    if (marker < 0) {
      return _NodePathSegment(name: this);
    }
    return _NodePathSegment(
      name: substring(0, marker),
      runId: substring(marker + 1),
    );
  }
}
