import 'package:freezed_annotation/freezed_annotation.dart';

part 'model.freezed.dart';

@freezed
sealed class Model with _$Model {
  const Model._();

  const factory Model({
    required String id,
    required String name,
    String? description,
    @Default(false) bool isMultimodal,
    @Default(false) bool supportsStreaming,
    @Default(false) bool supportsRAG,
    Map<String, dynamic>? capabilities,
    Map<String, dynamic>? metadata,
    List<String>? supportedParameters,
  }) = _Model;

  factory Model.fromJson(Map<String, dynamic> json) {
    // Handle different response formats from OpenWebUI

    // Extract architecture info for capabilities
    final architecture = json['architecture'] as Map<String, dynamic>?;
    final modality = architecture?['modality'] as String?;
    final inputModalities = architecture?['input_modalities'] as List?;

    // Determine if multimodal based on architecture
    final isMultimodal =
        modality?.contains('image') == true ||
        inputModalities?.contains('image') == true;

    // Extract supported parameters robustly (top-level or nested under provider keys)
    List? supportedParams =
        (json['supported_parameters'] as List?) ??
        (json['supportedParameters'] as List?);

    if (supportedParams == null) {
      const providerKeys = [
        'openai',
        'anthropic',
        'google',
        'meta',
        'mistral',
        'cohere',
        'xai',
        'perplexity',
        'deepseek',
        'groq',
      ];
      for (final key in providerKeys) {
        final provider = json[key] as Map<String, dynamic>?;
        final list =
            (provider?['supported_parameters'] as List?) ??
            (provider?['supportedParameters'] as List?);
        if (list != null) {
          supportedParams = list;
          break;
        }
      }
    }

    // Determine streaming support from supported parameters if known
    final supportsStreaming = supportedParams?.contains('stream') ?? true;

    // Convert supported parameters to List<String> if present
    final supportedParamsList = supportedParams
        ?.map((e) => e.toString())
        .toList();

    return Model(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      isMultimodal: isMultimodal,
      supportsStreaming: supportsStreaming,
      supportsRAG: json['supportsRAG'] as bool? ?? false,
      supportedParameters: supportedParamsList,
      capabilities: {
        'architecture': architecture,
        'pricing': json['pricing'],
        'context_length': json['context_length'],
        'supported_parameters': supportedParamsList ?? supportedParams,
      },
      metadata: {
        'canonical_slug': json['canonical_slug'],
        'created': json['created'],
        'connection_type': json['connection_type'],
      },
    );
  }
}
