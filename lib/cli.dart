/// CLI entrypoint exports for the `adk` executable.
///
/// Import this library when embedding the ADK CLI in tests or custom runners.
library;

export 'src/cli/cli_tools_click.dart' show main, runAdkCli;
