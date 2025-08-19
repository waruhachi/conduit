import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:conduit/features/tools/providers/tools_providers.dart';

class ToolSelector extends ConsumerWidget {
  const ToolSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toolsAsync = ref.watch(toolsListProvider);
    final selectedIds = ref.watch(selectedToolIdsProvider);
    final theme = Theme.of(context);

    return toolsAsync.when(
      data: (tools) {
        if (tools.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          height: 40,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: tools.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final tool = tools[index];
              final isSelected = selectedIds.contains(tool.id);

              return FilterChip(
                label: Text(tool.name),
                selected: isSelected,
                onSelected: (_) {
                  final currentIds = ref.read(selectedToolIdsProvider);
                  if (isSelected) {
                    ref.read(selectedToolIdsProvider.notifier).state = 
                        currentIds.where((id) => id != tool.id).toList();
                  } else {
                    ref.read(selectedToolIdsProvider.notifier).state = 
                        [...currentIds, tool.id];
                  }
                },
                avatar: Icon(
                  Icons.build,
                  size: 16,
                  color: isSelected
                      ? theme.colorScheme.onSecondaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              );
            },
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
    );
  }
}