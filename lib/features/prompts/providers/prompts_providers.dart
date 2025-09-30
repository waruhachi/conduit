import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:conduit/core/models/prompt.dart';
import 'package:conduit/core/services/prompts_service.dart';

part 'prompts_providers.g.dart';

@riverpod
Future<List<Prompt>> promptsList(Ref ref) async {
  final promptsService = ref.watch(promptsServiceProvider);
  if (promptsService == null) return const <Prompt>[];
  return promptsService.getPrompts();
}

@riverpod
class ActivePromptCommand extends _$ActivePromptCommand {
  @override
  String? build() => null;

  void set(String? command) => state = command;
}
