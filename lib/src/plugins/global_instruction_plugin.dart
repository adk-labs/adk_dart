/// Plugin hooks and implementations for ADK runtime pipelines.
library;

import 'dart:async';

import '../agents/callback_context.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../utils/instructions_utils.dart';
import 'base_plugin.dart';

/// Produces a global instruction string for each model callback context.
typedef GlobalInstructionProvider =
    FutureOr<String> Function(CallbackContext readonlyContext);

/// Prepends a global system instruction to outgoing model requests.
class GlobalInstructionPlugin extends BasePlugin {
  /// Creates a global instruction plugin.
  GlobalInstructionPlugin({
    String? globalInstruction,
    GlobalInstructionProvider? globalInstructionProvider,
    super.name = 'global_instruction',
  }) : _globalInstruction = globalInstruction ?? '',
       _globalInstructionProvider = globalInstructionProvider;

  final String _globalInstruction;
  final GlobalInstructionProvider? _globalInstructionProvider;

  /// Injects a resolved global instruction into [llmRequest].
  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    if (_globalInstruction.isEmpty && _globalInstructionProvider == null) {
      return null;
    }

    final String finalGlobalInstruction = await _resolveGlobalInstruction(
      callbackContext,
    );
    if (finalGlobalInstruction.isEmpty) {
      return null;
    }

    final String? existingInstruction = llmRequest.config.systemInstruction;
    if (existingInstruction == null || existingInstruction.isEmpty) {
      llmRequest.config.systemInstruction = finalGlobalInstruction;
      return null;
    }

    llmRequest.config.systemInstruction =
        '$finalGlobalInstruction\n\n$existingInstruction';
    return null;
  }

  Future<String> _resolveGlobalInstruction(CallbackContext context) async {
    if (_globalInstructionProvider != null) {
      final FutureOr<String> value = _globalInstructionProvider(context);
      return await Future<String>.value(value);
    }
    if (_globalInstruction.isEmpty) {
      return '';
    }
    return injectSessionState(_globalInstruction, context);
  }
}
