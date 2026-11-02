// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// Utility modules for Agent Builder Assistant.
library;

export '_adk_symbols.dart' show adkSymbolExists, adk_symbol_exists;
export 'adk_source_utils.dart'
    show
        clearSchemaCache,
        clear_schema_cache,
        findAdkSourceFolder,
        findAdkSourceFolderOverride,
        find_adk_source_folder,
        getAdkSchemaPath,
        getAdkSchemaPathOverride,
        get_adk_schema_path,
        loadAgentConfigSchema,
        loadAgentConfigSchemaMap,
        load_agent_config_schema;
export 'path_normalizer.dart'
    show sanitizeGeneratedFilePath, sanitize_generated_file_path;
export 'resolve_root_directory.dart'
    show
        canonicalizePath,
        extractSessionState,
        isPathRelativeTo,
        relativePathFromRoot,
        resolveFilePath,
        resolveFilePaths,
        resolve_file_path,
        resolve_file_paths;
