import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/server_config.dart';
import '../../../core/providers/app_providers.dart';

// Server management providers
final addServerProvider = FutureProvider.family<void, ServerConfig>((
  ref,
  server,
) async {
  final storage = ref.read(optimizedStorageServiceProvider);
  final configs = await storage.getServerConfigs();

  // Add new server
  configs.add(server);

  // Save updated list
  await storage.saveServerConfigs(configs);

  // Refresh the server list
  ref.invalidate(serverConfigsProvider);
});

final deleteServerProvider = FutureProvider.family<void, String>((
  ref,
  serverId,
) async {
  final storage = ref.read(optimizedStorageServiceProvider);
  final configs = await storage.getServerConfigs();

  // Remove server with matching ID
  configs.removeWhere((config) => config.id == serverId);

  // Save updated list
  await storage.saveServerConfigs(configs);

  // If this was the active server, clear active server ID
  final activeId = await storage.getActiveServerId();
  if (activeId == serverId) {
    await storage.setActiveServerId(null);
  }

  // Refresh providers
  ref.invalidate(serverConfigsProvider);
  ref.invalidate(activeServerProvider);
});

final setActiveServerProvider = FutureProvider.family<void, String>((
  ref,
  serverId,
) async {
  final storage = ref.read(optimizedStorageServiceProvider);
  await storage.setActiveServerId(serverId);

  // Refresh active server provider
  ref.invalidate(activeServerProvider);
});
