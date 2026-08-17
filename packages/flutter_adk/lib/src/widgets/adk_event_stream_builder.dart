import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/material.dart';

/// A reactive widget builder that listens to an ADK [Stream<adk.Event>] and
/// updates the UI as events and state changes arrive.
class AdkEventStreamBuilder extends StatelessWidget {
  /// Creates an [AdkEventStreamBuilder].
  const AdkEventStreamBuilder({
    super.key,
    required this.stream,
    required this.builder,
    this.loadingBuilder,
    this.errorBuilder,
    this.emptyBuilder,
  });

  /// The active ADK event stream.
  final Stream<adk.Event> stream;

  /// Builder invoked whenever new events are received or accumulated.
  final Widget Function(BuildContext context, List<adk.Event> events) builder;

  /// Optional widget displayed while waiting for the first event.
  final WidgetBuilder? loadingBuilder;

  /// Optional widget builder displayed when an error occurs.
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  /// Optional widget displayed when the stream completes with no events.
  final WidgetBuilder? emptyBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<adk.Event>(
      stream: stream,
      builder: (BuildContext context, AsyncSnapshot<adk.Event> snapshot) {
        if (snapshot.hasError) {
          if (errorBuilder != null) {
            return errorBuilder!(context, snapshot.error!);
          }
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          if (loadingBuilder != null) {
            return loadingBuilder!(context);
          }
          return const Center(child: CircularProgressIndicator());
        }

        final adk.Event? latest = snapshot.data;
        if (latest == null) {
          if (emptyBuilder != null) {
            return emptyBuilder!(context);
          }
          return const SizedBox.shrink();
        }

        return builder(context, <adk.Event>[latest]);
      },
    );
  }
}
