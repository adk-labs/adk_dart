/// Execution environment abstractions and local implementation.
library;

export 'base_environment.dart'
    show
        BaseEnvironment,
        EnvironmentExecutionResult,
        ExecutionResult,
        encodeWriteFileContent;
export 'local_environment.dart' show LocalEnvironment;
export '../tools/environment/environment_toolset.dart'
    show
        EnvironmentLockCancelledException,
        closeIfInitialized,
        ensureInitialized,
        environmentInstruction,
        environmentWorkingDirInstruction;
