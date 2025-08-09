import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../shared/theme/theme_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/file_info.dart';
import '../../../core/providers/app_providers.dart';

class FileViewerDialog extends ConsumerWidget {
  final FileInfo fileInfo;

  const FileViewerDialog({super.key, required this.fileInfo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use themed tokens via extension
    final fileContent = ref.watch(fileContentProvider(fileInfo.id));

    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: context.conduitTheme.surfaceBackground,
        appBar: AppBar(
          backgroundColor: context.conduitTheme.surfaceBackground,
          elevation: 0,
          title: Text(
            fileInfo.originalFilename,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.conduitTheme.textPrimary),
          ),
          iconTheme: IconThemeData(color: context.conduitTheme.iconPrimary),
          leading: IconButton(
            icon: Icon(Platform.isIOS ? CupertinoIcons.back : Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: Icon(Platform.isIOS ? CupertinoIcons.info : Icons.info),
              onPressed: () => _showFileInfo(context),
            ),
          ],
        ),
        body: fileContent.when(
          data: (content) => _buildContentView(context, content),
          loading: () => Center(
            child: CircularProgressIndicator(
              color: context.conduitTheme.buttonPrimary,
            ),
          ),
          error: (error, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 64, color: context.conduitTheme.error),
                const SizedBox(height: Spacing.md),
                Text(
                  'Failed to load file',
                  style: TextStyle(
                    color: context.conduitTheme.error,
                    fontSize: AppTypography.headlineSmall,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  error.toString(),
                  style: TextStyle(color: context.conduitTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Spacing.md),
                ElevatedButton(
                  onPressed: () =>
                      ref.invalidate(fileContentProvider(fileInfo.id)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentView(BuildContext context, String content) {
    final theme = context.conduitTheme;
    final isTextFile = _isTextFile(fileInfo.mimeType);

    if (!isTextFile) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getFileIcon(fileInfo.mimeType),
              size: 64,
              color: theme.buttonPrimary,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              fileInfo.originalFilename,
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: AppTypography.headlineSmall,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'File type: ${fileInfo.mimeType}',
              style: TextStyle(color: theme.textSecondary),
            ),
            Text(
              'Size: ${_formatFileSize(fileInfo.size)}',
              style: TextStyle(color: theme.textSecondary),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Preview not available for this file type',
              style: TextStyle(color: theme.textTertiary),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.md),
      child: SelectableText(
        content,
        style: TextStyle(
          color: theme.textPrimary,
          fontFamily: 'monospace',
          fontSize: AppTypography.labelLarge,
        ),
      ),
    );
  }

  void _showFileInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.conduitTheme.surfaceBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.dialog),
        ),
        title: Text(
          'File Information',
          style: TextStyle(color: context.conduitTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(context, 'Name', fileInfo.originalFilename),
            _buildInfoRow(context, 'Size', _formatFileSize(fileInfo.size)),
            _buildInfoRow(context, 'Type', fileInfo.mimeType),
            _buildInfoRow(context, 'Created', _formatDate(fileInfo.createdAt)),
            _buildInfoRow(context, 'Modified', _formatDate(fileInfo.updatedAt)),
            if (fileInfo.hash != null)
              _buildInfoRow(context, 'Hash', fileInfo.hash!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: TextStyle(color: context.conduitTheme.buttonPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: Spacing.xxxl + Spacing.md,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: context.conduitTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: context.conduitTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  bool _isTextFile(String mimeType) {
    return mimeType.startsWith('text/') ||
        mimeType == 'application/json' ||
        mimeType == 'application/xml' ||
        mimeType == 'application/javascript' ||
        mimeType.contains('yaml') ||
        mimeType.contains('markdown');
  }

  IconData _getFileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) {
      return Platform.isIOS ? CupertinoIcons.photo : Icons.image;
    } else if (mimeType.startsWith('video/')) {
      return Platform.isIOS ? CupertinoIcons.video_camera : Icons.video_file;
    } else if (mimeType.startsWith('audio/')) {
      return Platform.isIOS ? CupertinoIcons.music_note : Icons.audio_file;
    } else if (mimeType.contains('pdf')) {
      return Platform.isIOS ? CupertinoIcons.doc : Icons.picture_as_pdf;
    } else if (mimeType.startsWith('text/') || mimeType.contains('json')) {
      return Platform.isIOS ? CupertinoIcons.doc_text : Icons.description;
    } else {
      return Platform.isIOS ? CupertinoIcons.doc : Icons.insert_drive_file;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
