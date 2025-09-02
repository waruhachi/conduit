import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/services/attachment_upload_queue.dart';
import '../../../core/utils/debug_logger.dart';
import '../../../core/models/chat_message.dart';
import '../../../features/chat/providers/chat_providers.dart' as chat;
import '../../../features/chat/services/file_attachment_service.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'outbound_task.dart';

class TaskWorker {
  final Ref _ref;
  TaskWorker(this._ref);

  Future<void> perform(OutboundTask task) async {
    await task.map<Future<void>>(
      sendTextMessage: _performSendText,
      uploadMedia: _performUploadMedia,
      executeToolCall: _performExecuteToolCall,
      generateImage: _performGenerateImage,
      imageToDataUrl: _performImageToDataUrl,
      saveConversation: _performSaveConversation,
      generateTitle: _performGenerateTitle,
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

      // Reflect progress into UI attachment state if that file is present
      try {
        final current = _ref.read(attachedFilesProvider);
        final idx = current.indexWhere((f) => f.file.path == task.filePath);
        if (idx != -1) {
          final existing = current[idx];
          final status = switch (entry.status) {
            QueuedAttachmentStatus.pending => FileUploadStatus.uploading,
            QueuedAttachmentStatus.uploading => FileUploadStatus.uploading,
            QueuedAttachmentStatus.completed => FileUploadStatus.completed,
            QueuedAttachmentStatus.failed => FileUploadStatus.failed,
            QueuedAttachmentStatus.cancelled => FileUploadStatus.failed,
          };
          final newState = FileUploadState(
            file: File(task.filePath),
            fileName: task.fileName,
            fileSize: task.fileSize ?? existing.fileSize,
            progress: status == FileUploadStatus.completed ? 1.0 : existing.progress,
            status: status,
            fileId: entry.fileId ?? existing.fileId,
            error: entry.lastError,
          );
          _ref
              .read(attachedFilesProvider.notifier)
              .updateFileState(task.filePath, newState);
        }
      } catch (_) {}
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

  Future<void> _performGenerateImage(GenerateImageTask task) async {
    final api = _ref.read(apiServiceProvider);
    final selectedModel = _ref.read(selectedModelProvider);
    if (api == null) {
      throw Exception('API not available');
    }

    // Add assistant placeholder to show progress
    try {
      final placeholder = ChatMessage(
        id: const Uuid().v4(),
        role: 'assistant',
        content: '',
        timestamp: DateTime.now(),
        model: selectedModel?.id,
        isStreaming: true,
      );
      _ref.read(chat.chatMessagesProvider.notifier).addMessage(placeholder);
    } catch (_) {}

    // Generate images
    List<Map<String, dynamic>> _extractGeneratedFiles(dynamic resp) {
      final results = <Map<String, dynamic>>[];
      if (resp is List) {
        for (final item in resp) {
          if (item is String && item.isNotEmpty) {
            results.add({'type': 'image', 'url': item});
          } else if (item is Map) {
            final url = item['url'];
            final b64 = item['b64_json'] ?? item['b64'];
            if (url is String && url.isNotEmpty) {
              results.add({'type': 'image', 'url': url});
            } else if (b64 is String && b64.isNotEmpty) {
              results.add({'type': 'image', 'url': 'data:image/png;base64,$b64'});
            }
          }
        }
        return results;
      }
      if (resp is! Map) return results;
      final data = resp['data'];
      if (data is List) {
        for (final item in data) {
          if (item is Map) {
            final url = item['url'];
            final b64 = item['b64_json'] ?? item['b64'];
            if (url is String && url.isNotEmpty) {
              results.add({'type': 'image', 'url': url});
            } else if (b64 is String && b64.isNotEmpty) {
              results.add({'type': 'image', 'url': 'data:image/png;base64,$b64'});
            }
          } else if (item is String && item.isNotEmpty) {
            results.add({'type': 'image', 'url': item});
          }
        }
      }
      final images = resp['images'];
      if (images is List) {
        for (final item in images) {
          if (item is String && item.isNotEmpty) {
            results.add({'type': 'image', 'url': item});
          } else if (item is Map) {
            final url = item['url'];
            final b64 = item['b64_json'] ?? item['b64'];
            if (url is String && url.isNotEmpty) {
              results.add({'type': 'image', 'url': url});
            } else if (b64 is String && b64.isNotEmpty) {
              results.add({'type': 'image', 'url': 'data:image/png;base64,$b64'});
            }
          }
        }
      }
      final singleUrl = resp['url'];
      if (singleUrl is String && singleUrl.isNotEmpty) {
        results.add({'type': 'image', 'url': singleUrl});
      }
      final singleB64 = resp['b64_json'] ?? resp['b64'];
      if (singleB64 is String && singleB64.isNotEmpty) {
        results.add({'type': 'image', 'url': 'data:image/png;base64,$singleB64'});
      }
      return results;
    }

    try {
      final imageResponse = await api.generateImage(prompt: task.prompt);
      final generatedFiles = _extractGeneratedFiles(imageResponse);
      if (generatedFiles.isNotEmpty) {
        _ref.read(chat.chatMessagesProvider.notifier).updateLastMessageWithFunction(
              (m) => m.copyWith(files: generatedFiles, isStreaming: false),
            );

        // Sync conversation to server
        try {
          final messages = _ref.read(chat.chatMessagesProvider);
          final activeConv = _ref.read(activeConversationProvider);
          if (activeConv != null && messages.isNotEmpty) {
            await api.updateConversationWithMessages(
              activeConv.id,
              messages,
              model: selectedModel?.id,
            );
            // Update local active conversation messages
            final updated = activeConv.copyWith(
              messages: messages,
              updatedAt: DateTime.now(),
            );
            _ref.read(activeConversationProvider.notifier).state = updated;
            _ref.invalidate(conversationsProvider);
          }
        } catch (_) {}

        // Trigger title generation (best-effort)
        try {
          final activeConv = _ref.read(activeConversationProvider);
          final messages = _ref.read(chat.chatMessagesProvider);
          final modelId = selectedModel?.id;
          if (activeConv != null && modelId != null) {
            final formatted = <Map<String, dynamic>>[];
            for (final msg in messages) {
              formatted.add({
                'id': msg.id,
                'role': msg.role,
                'content': msg.content,
                'timestamp': msg.timestamp.millisecondsSinceEpoch ~/ 1000,
              });
            }
            final title = await api.generateTitle(
              conversationId: activeConv.id,
              messages: formatted,
              model: modelId,
            );
            if (title != null && title.isNotEmpty && title != 'New Chat') {
              final updated = activeConv.copyWith(
                title: title.length > 100 ? '${title.substring(0, 100)}...' : title,
                updatedAt: DateTime.now(),
              );
              _ref.read(activeConversationProvider.notifier).state = updated;
              try {
                final cur = _ref.read(chat.chatMessagesProvider);
                await api.updateConversationWithMessages(
                  updated.id,
                  cur,
                  title: updated.title,
                  model: modelId,
                );
              } catch (_) {}
              _ref.invalidate(conversationsProvider);
            }
          }
        } catch (_) {}
      } else {
        _ref.read(chat.chatMessagesProvider.notifier).finishStreaming();
      }
    } catch (e) {
      _ref.read(chat.chatMessagesProvider.notifier).finishStreaming();
    }
  }

  Future<void> _performImageToDataUrl(ImageToDataUrlTask task) async {
    try {
      // Update UI to uploading state first
      try {
        final current = _ref.read(attachedFilesProvider);
        final idx = current.indexWhere((f) => f.file.path == task.filePath);
        if (idx != -1) {
          final existing = current[idx];
          final uploading = FileUploadState(
            file: existing.file,
            fileName: task.fileName,
            fileSize: existing.fileSize,
            progress: 0.5,
            status: FileUploadStatus.uploading,
            fileId: existing.fileId,
          );
          _ref.read(attachedFilesProvider.notifier).updateFileState(
                task.filePath,
                uploading,
              );
        }
      } catch (_) {}

      // Read file and convert to data URL
      final file = File(task.filePath);
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      final ext = path.extension(task.fileName).toLowerCase();
      String mime = 'image/png';
      if (ext == '.jpg' || ext == '.jpeg') mime = 'image/jpeg';
      else if (ext == '.gif') mime = 'image/gif';
      else if (ext == '.webp') mime = 'image/webp';
      final dataUrl = 'data:$mime;base64,$b64';

      // Mark as completed with data URL as fileId
      try {
        final current = _ref.read(attachedFilesProvider);
        final idx = current.indexWhere((f) => f.file.path == task.filePath);
        if (idx != -1) {
          final existing = current[idx];
          final done = FileUploadState(
            file: existing.file,
            fileName: task.fileName,
            fileSize: existing.fileSize,
            progress: 1.0,
            status: FileUploadStatus.completed,
            fileId: dataUrl,
          );
          _ref.read(attachedFilesProvider.notifier).updateFileState(
                task.filePath,
                done,
              );
        }
      } catch (_) {}
    } catch (e) {
      try {
        final current = _ref.read(attachedFilesProvider);
        final idx = current.indexWhere((f) => f.file.path == task.filePath);
        if (idx != -1) {
          final existing = current[idx];
          final failed = FileUploadState(
            file: existing.file,
            fileName: task.fileName,
            fileSize: existing.fileSize,
            progress: 0.0,
            status: FileUploadStatus.failed,
            fileId: existing.fileId,
            error: e.toString(),
          );
          _ref.read(attachedFilesProvider.notifier).updateFileState(
                task.filePath,
                failed,
              );
        }
      } catch (_) {}
    }
  }

  Future<void> _performSaveConversation(SaveConversationTask task) async {
    final api = _ref.read(apiServiceProvider);
    final messages = _ref.read(chat.chatMessagesProvider);
    final activeConv = _ref.read(activeConversationProvider);
    final selectedModel = _ref.read(selectedModelProvider);
    if (api == null || messages.isEmpty || activeConv == null) return;

    // Skip if last assistant is empty placeholder
    final last = messages.last;
    if (last.role == 'assistant' &&
        last.content.trim().isEmpty &&
        (last.files?.isEmpty ?? true) &&
        (last.attachmentIds?.isEmpty ?? true)) {
      return;
    }

    try {
      await api.updateConversationWithMessages(
        activeConv.id,
        messages,
        model: selectedModel?.id,
      );
      final updated = activeConv.copyWith(
        messages: messages,
        updatedAt: DateTime.now(),
      );
      _ref.read(activeConversationProvider.notifier).state = updated;
      _ref.invalidate(conversationsProvider);
    } catch (_) {}
  }

  Future<void> _performGenerateTitle(GenerateTitleTask task) async {
    final api = _ref.read(apiServiceProvider);
    final activeConv = _ref.read(activeConversationProvider);
    final selectedModel = _ref.read(selectedModelProvider);
    if (api == null || selectedModel == null) return;
    try {
      final messages = _ref.read(chat.chatMessagesProvider);
      final formatted = <Map<String, dynamic>>[];
      for (final msg in messages) {
        formatted.add({
          'id': msg.id,
          'role': msg.role,
          'content': msg.content,
          'timestamp': msg.timestamp.millisecondsSinceEpoch ~/ 1000,
        });
      }
      final title = await api.generateTitle(
        conversationId: task.conversationId,
        messages: formatted,
        model: selectedModel.id,
      );
      if (title != null && title.isNotEmpty && title != 'New Chat') {
        if (activeConv != null && activeConv.id == task.conversationId) {
          final updated = activeConv.copyWith(
            title: title.length > 100 ? '${title.substring(0, 100)}...' : title,
            updatedAt: DateTime.now(),
          );
          _ref.read(activeConversationProvider.notifier).state = updated;
          try {
            final cur = _ref.read(chat.chatMessagesProvider);
            await api.updateConversationWithMessages(
              updated.id,
              cur,
              title: updated.title,
              model: selectedModel.id,
            );
          } catch (_) {}
          _ref.invalidate(conversationsProvider);
        }
      }
    } catch (_) {}
  }
}
