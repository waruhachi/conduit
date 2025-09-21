import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:conduit/core/models/tool.dart';
import 'package:conduit/core/services/tools_service.dart';

final toolsListProvider = FutureProvider<List<Tool>>((ref) async {
  final toolsService = ref.watch(toolsServiceProvider);
  if (toolsService == null) return [];
  return await toolsService.getTools();
});

final selectedToolIdsProvider =
    NotifierProvider<SelectedToolIdsNotifier, List<String>>(
      SelectedToolIdsNotifier.new,
    );

class SelectedToolIdsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => [];

  void set(List<String> ids) => state = List<String>.from(ids);
}
