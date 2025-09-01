import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/services/attachment_upload_queue.dart';
import '../../../core/utils/debug_logger.dart';
import '../../../features/chat/providers/chat_providers.dart' as chat;
import 'outbound_task.dart';

class TaskWorker {
  final Ref _ref;
  TaskWorker(this._ref);

  Future<void> perform(OutboundTask task) async {
    await task.map<Future<void>>(
      sendTextMessage: _performSendText,
      uploadMedia: _performUploadMedia,
      executeToolCall: _performExecuteToolCall,
    );
  }

  Future<void> _performSendText(SendTextMessageTask task) async {
    // Ensure uploads referenced in attachments are completed if they are local queued ids
    // For now, assume attachments are already uploaded (fileIds or data URLs) as UI uploads eagerly.
    // If needed, we could resolve queued uploads here by integrating with AttachmentUploadQueue.
    final isReviewer = _ref.read(reviewerModeProvider);
    if (!isReviewer) {
      final api = _ref.read(apiServiceProvider);
      if (api == null) {
        throw Exception('API not available');
      }
    }

    // Set active conversation if provided; otherwise keep current
    try {
      // If a specific conversation id is provided and differs from current, load it
      final active = _ref.read(activeConversationProvider);
      if (task.conversationId != null &&
          task.conversationId!.isNotEmpty &&
          (active == null || active.id != task.conversationId)) {
        try {
          final api = _ref.read(apiServiceProvider);
          if (api != null) {
            final conv = await api.getConversation(task.conversationId!);
            _ref.read(activeConversationProvider.notifier).state = conv;
          }
        } catch (_) {
          // If loading fails, proceed; send flow can create a new conversation
        }
      }
    } catch (_) {}

    // Delegate to existing unified send implementation
    await chat.sendMessageFromService(
      _ref,
      task.text,
      task.attachments.isEmpty ? null : task.attachments,
      task.toolIds.isEmpty ? null : task.toolIds,
    );
  }

  Future<void> _performUploadMedia(UploadMediaTask task) async {
    final uploader = AttachmentUploadQueue();
    // Ensure queue initialized with API upload callback
    try {
      final api = _ref.read(apiServiceProvider);
      if (api != null) {
        await uploader.initialize(
          onUpload: (p, n) => api.uploadFile(p, n),
        );
      }
    } catch (_) {}

    // Enqueue and then wait until the item reaches a terminal state for basic parity
    final id = await uploader.enqueue(
      filePath: task.filePath,
      fileName: task.fileName,
      fileSize: task.fileSize ?? 0,
      mimeType: task.mimeType,
      checksum: task.checksum,
    );

    final completer = Completer<void>();
    late final StreamSubscription<List<QueuedAttachment>> sub;
    sub = uploader.queueStream.listen((items) {
      QueuedAttachment? entry;
      try {
        entry = items.firstWhere((e) => e.id == id);
      } catch (_) {
        entry = null;
      }
      if (entry == null) return;
      switch (entry.status) {
        case QueuedAttachmentStatus.completed:
        case QueuedAttachmentStatus.failed:
        case QueuedAttachmentStatus.cancelled:
          sub.cancel();
          completer.complete();
          break;
        default:
          break;
      }
    });

    // Fire a process tick
    unawaited(uploader.processQueue());
    await completer.future.timeout(const Duration(minutes: 2), onTimeout: () {
      try { sub.cancel(); } catch (_) {}
      DebugLogger.warning('UploadMediaTask timed out: ${task.fileName}');
      return;
    });
  }

  Future<void> _performExecuteToolCall(ExecuteToolCallTask task) async {
    // Placeholder: In this client, native tool execution is orchestrated server-side.
    // We keep this task type for future local tools or MCP bridges.
    debugPrint('ExecuteToolCallTask stub: ${task.toolName}');
  }
}
