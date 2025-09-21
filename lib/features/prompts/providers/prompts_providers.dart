import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:conduit/core/models/prompt.dart';
import 'package:conduit/core/services/prompts_service.dart';

final promptsListProvider = FutureProvider<List<Prompt>>((ref) async {
  final promptsService = ref.watch(promptsServiceProvider);
  if (promptsService == null) return const <Prompt>[];
  return promptsService.getPrompts();
});

final activePromptCommandProvider =
    NotifierProvider<ActivePromptCommandNotifier, String?>(
      ActivePromptCommandNotifier.new,
    );

class ActivePromptCommandNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? command) => state = command;
}
