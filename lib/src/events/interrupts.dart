/// Utilities for indexing and resolving workflow and agent interrupts.
library;

import '../types/content.dart';
import '../utils/function_call_names.dart';
import 'event.dart';
import 'node_path_builder.dart';

/// Represents an open, unanswered interrupt in an event stream.
///
/// ```dart
/// final interrupts = indexOpenInterrupts(session.events);
/// for (final entry in interrupts.entries) {
///   print('Open interrupt ${entry.key} emitted by ${entry.value.author}');
/// }
/// ```
class OpenInterrupt {
  /// Creates an open interrupt descriptor.
  const OpenInterrupt({
    this.author,
    this.ancestorAuthors = const <String>[],
  });

  /// Author of the event that initiated the interrupt.
  final String? author;

  /// Authors of ancestor nodes along the execution branch.
  final List<String> ancestorAuthors;

  /// Returns all authors (the event author plus ancestor authors).
  List<String> get allAuthors {
    final List<String> authors = <String>[];
    if (author != null && author!.isNotEmpty) {
      authors.add(author!);
    }
    for (final String ancestor in ancestorAuthors) {
      if (ancestor.isNotEmpty && !authors.contains(ancestor)) {
        authors.add(ancestor);
      }
    }
    return List<String>.unmodifiable(authors);
  }

  @override
  String toString() =>
      'OpenInterrupt(author: $author, ancestorAuthors: $ancestorAuthors)';
}

/// Returns all interrupt IDs carried by [event].
///
/// Includes [event.longRunningToolIds] as well as fallback extraction from
/// `adk_request_input`, `adk_request_credential`, and `adk_request_confirmation`
/// function calls for sessions where [Event.longRunningToolIds] was omitted.
Set<String> extractEventInterruptIds(Event event) {
  final Set<String> interruptIds = <String>{
    if (event.longRunningToolIds != null) ...event.longRunningToolIds!,
  };
  for (final FunctionCall fc in event.getFunctionCalls()) {
    if (fc.id != null &&
        (fc.name == requestInputFunctionCallName ||
         fc.name == requestEucFunctionCallName ||
         fc.name == requestConfirmationFunctionCallName)) {
      interruptIds.add(fc.id!);
    }
  }
  return interruptIds;
}

/// Whether [event] represents an active interrupt pause.
bool isInterruptEvent(Event event) =>
    extractEventInterruptIds(event).isNotEmpty;

/// Indexes interrupts in [events] that have not yet been answered.
///
/// An interrupt is considered answered when a subsequent user [FunctionResponse]
/// in [events] carries `fr.id == interruptId`, or arrives on a sub-branch whose
/// run IDs contain `interruptId`.
Map<String, OpenInterrupt> indexOpenInterrupts(Iterable<Event> events) {
  final Map<String, OpenInterrupt> index = <String, OpenInterrupt>{};
  final Map<String, String> callAuthorById = <String, String>{};

  for (final Event event in events) {
    final List<String> branchRunIds = event.branch != null && event.branch!.isNotEmpty
        ? BranchPath.fromString(event.branch).orderedRunIds
        : const <String>[];

    if (event.author.isNotEmpty && event.author != 'user') {
      for (final FunctionCall fc in event.getFunctionCalls()) {
        if (fc.id != null && fc.id!.isNotEmpty) {
          callAuthorById[fc.id!] = event.author;
        }
      }
    }

    if (event.author == 'user') {
      final List<FunctionResponse> responses = event.getFunctionResponses();
      for (final FunctionResponse fr in responses) {
        if (fr.id != null) {
          index.remove(fr.id);
        }
      }

      if (branchRunIds.isNotEmpty && responses.isNotEmpty && index.isNotEmpty) {
        for (final String interruptId in index.keys.toList()) {
          if (branchRunIds.contains(interruptId)) {
            index.remove(interruptId);
          }
        }
      }
    }

    final Set<String> interruptIds = extractEventInterruptIds(event);
    if (interruptIds.isEmpty) {
      continue;
    }

    final List<String> ancestorAuthors = <String>[];
    for (final String runId in branchRunIds.reversed) {
      final String? ancAuthor = callAuthorById[runId];
      if (ancAuthor != null &&
          ancAuthor.isNotEmpty &&
          !ancestorAuthors.contains(ancAuthor)) {
        ancestorAuthors.add(ancAuthor);
      }
    }

    for (final String interruptId in interruptIds) {
      index[interruptId] = OpenInterrupt(
        author: event.author.isNotEmpty ? event.author : null,
        ancestorAuthors: List<String>.unmodifiable(ancestorAuthors),
      );
    }
  }

  return index;
}
