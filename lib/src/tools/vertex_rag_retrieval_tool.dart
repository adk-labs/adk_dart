/// Vertex AI RAG built-in retrieval tool.
library;

import '../models/llm_request.dart';
import 'base_tool.dart';
import 'retrieval/vertex_ai_rag_retrieval.dart';
import 'tool_context.dart';

/// Server-side Vertex AI RAG retrieval tool.
///
/// The model backend executes this tool through
/// `retrieval.vertexRagStore`; no local runtime execution is required.
class VertexRagRetrievalTool extends BaseTool {
  /// Creates a Vertex RAG built-in retrieval tool.
  VertexRagRetrievalTool({
    VertexAiRagStore? vertexRagStore,
    List<String>? ragCorpora,
    List<VertexAiRagResource>? ragResources,
    int? similarityTopK,
    double? vectorDistanceThreshold,
  }) : vertexRagStore =
           vertexRagStore ??
           VertexAiRagStore(
             ragCorpora: ragCorpora,
             ragResources: ragResources,
             similarityTopK: similarityTopK,
             vectorDistanceThreshold: vectorDistanceThreshold,
           ),
       super(
         name: 'vertex_rag_retrieval',
         description: 'Vertex AI RAG Retrieval Tool',
       );

  /// Configured Vertex AI RAG store.
  final VertexAiRagStore vertexRagStore;

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return null;
  }

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    llmRequest.config.tools ??= <ToolDeclaration>[];
    llmRequest.config.tools!.add(
      ToolDeclaration(
        retrieval: <String, Object?>{
          'vertexRagStore': vertexRagStore.toVertexJson(),
        },
      ),
    );
  }
}
