import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:conduit/core/models/tool.dart';
import 'package:conduit/core/services/tools_service.dart';

final toolsListProvider = FutureProvider<List<Tool>>((ref) async {
  final toolsService = ref.watch(toolsServiceProvider);
  if (toolsService == null) return [];
  return await toolsService.getTools();
});

final selectedToolIdsProvider = StateProvider<List<String>>((ref) => []);