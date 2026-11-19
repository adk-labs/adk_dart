/// Fsspec artifact service integration for ADK.
library;

export 'backends.dart'
    show
        FsspecBackendAdapter,
        FsspecObjectMetadata,
        GcsBackendAdapter,
        GenericBackendAdapter,
        S3BackendAdapter,
        S3ConditionalRequestConflictException;
export 'fsspec_artifact_service.dart'
    show
        FilesystemProtocol,
        FsspecArtifactService,
        FsspecFileExistsException,
        FsspecInputValidationError,
        FsspecPermissionException,
        FsspecUrlToFsResolver,
        FsspecWriteStream,
        GcsPreconditionError,
        InMemoryFsspecFilesystem,
        LocalFsspecFilesystem,
        newRewindTombstone,
        urlToFs;
