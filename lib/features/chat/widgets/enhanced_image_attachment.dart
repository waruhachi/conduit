import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../core/providers/app_providers.dart';

// Global cache for image data to prevent reloading
final _globalImageCache = <String, String>{};

class EnhancedImageAttachment extends ConsumerStatefulWidget {
  final String attachmentId;
  final bool isMarkdownFormat;
  final VoidCallback? onTap;
  final BoxConstraints? constraints;
  final bool isUserMessage;

  const EnhancedImageAttachment({
    super.key,
    required this.attachmentId,
    this.isMarkdownFormat = false,
    this.onTap,
    this.constraints,
    this.isUserMessage = false,
  });

  @override
  ConsumerState<EnhancedImageAttachment> createState() =>
      _EnhancedImageAttachmentState();
}

class _EnhancedImageAttachmentState
    extends ConsumerState<EnhancedImageAttachment>
    with AutomaticKeepAliveClientMixin {
  String? _cachedImageData;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    // Check global cache first
    if (_globalImageCache.containsKey(widget.attachmentId)) {
      if (mounted) {
        setState(() {
          _cachedImageData = _globalImageCache[widget.attachmentId];
          _isLoading = false;
        });
      }
      return;
    }

    // Check if this is already a data URL or base64 image
    if (widget.attachmentId.startsWith('data:') ||
        widget.attachmentId.startsWith('http')) {
      _globalImageCache[widget.attachmentId] = widget.attachmentId;
      if (mounted) {
        setState(() {
          _cachedImageData = widget.attachmentId;
          _isLoading = false;
        });
      }
      return;
    }

    final api = ref.read(apiServiceProvider);
    if (api == null) {
      if (mounted) {
        setState(() {
          _errorMessage = 'API service not available';
          _isLoading = false;
        });
      }
      return;
    }

    try {
      // Get file info to check if it's an image
      final fileInfo = await api.getFileInfo(widget.attachmentId);
      final fileName = _extractFileName(fileInfo);
      final ext = fileName.toLowerCase().split('.').last;

      if (!['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg'].contains(ext)) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Not an image file: $fileName';
            _isLoading = false;
          });
        }
        return;
      }

      // Get the image content
      final fileContent = await api.getFileContent(widget.attachmentId);
      
      // Cache globally
      _globalImageCache[widget.attachmentId] = fileContent;
      
      // Limit cache size
      if (_globalImageCache.length > 50) {
        _globalImageCache.remove(_globalImageCache.keys.first);
      }
      
      if (mounted) {
        setState(() {
          _cachedImageData = fileContent;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load image: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  String _extractFileName(Map<String, dynamic> fileInfo) {
    return fileInfo['filename'] ??
        fileInfo['meta']?['name'] ??
        fileInfo['name'] ??
        fileInfo['file_name'] ??
        fileInfo['original_name'] ??
        fileInfo['original_filename'] ??
        'unknown';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_cachedImageData == null) {
      return const SizedBox.shrink();
    }

    // Handle different image data formats
    if (_cachedImageData!.startsWith('http')) {
      return _buildNetworkImage();
    } else {
      return _buildBase64Image();
    }
  }

  Widget _buildLoadingState() {
    return Container(
      constraints: widget.constraints ??
          const BoxConstraints(
            maxWidth: 300,
            maxHeight: 300,
            minHeight: 150,
            minWidth: 200,
          ),
      margin: const EdgeInsets.only(bottom: Spacing.xs),
      decoration: BoxDecoration(
        color: context.conduitTheme.surfaceBackground.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        border: Border.all(
          color: context.conduitTheme.dividerColor.withValues(alpha: 0.3),
          width: BorderWidth.thin,
        ),
      ),
      child: Center(
        child: CircularProgressIndicator(
          color: context.conduitTheme.buttonPrimary,
          strokeWidth: 2,
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      constraints: widget.constraints ??
          const BoxConstraints(
            maxWidth: 300,
            maxHeight: 150,
            minHeight: 100,
            minWidth: 200,
          ),
      margin: const EdgeInsets.only(bottom: Spacing.xs),
      decoration: BoxDecoration(
        color: context.conduitTheme.surfaceBackground.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        border: Border.all(
          color: context.conduitTheme.error.withValues(alpha: 0.3),
          width: BorderWidth.thin,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: context.conduitTheme.error,
            size: 32,
          ),
          const SizedBox(height: Spacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: context.conduitTheme.error,
                fontSize: AppTypography.bodySmall,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkImage() {
    final imageWidget = CachedNetworkImage(
      imageUrl: _cachedImageData!,
      fit: BoxFit.cover,
      placeholder: (context, url) => _buildLoadingState(),
      errorWidget: (context, url, error) {
        _errorMessage = error.toString();
        return _buildErrorState();
      },
    );

    return _wrapImage(imageWidget);
  }

  Widget _buildBase64Image() {
    try {
      // Extract base64 data from data URL if needed
      String actualBase64;
      if (_cachedImageData!.startsWith('data:')) {
        final commaIndex = _cachedImageData!.indexOf(',');
        if (commaIndex != -1) {
          actualBase64 = _cachedImageData!.substring(commaIndex + 1);
        } else {
          throw Exception('Invalid data URL format');
        }
      } else {
        actualBase64 = _cachedImageData!;
      }

      final imageBytes = base64.decode(actualBase64);
      final imageWidget = Image.memory(
        imageBytes,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          _errorMessage = 'Failed to decode image';
          return _buildErrorState();
        },
      );

      return _wrapImage(imageWidget);
    } catch (e) {
      _errorMessage = 'Invalid image format';
      return _buildErrorState();
    }
  }

  Widget _wrapImage(Widget imageWidget) {
    return Container(
      constraints: widget.constraints ??
          const BoxConstraints(
            maxWidth: 400,
            maxHeight: 400,
          ),
      margin: widget.isMarkdownFormat
          ? const EdgeInsets.symmetric(vertical: Spacing.sm)
          : EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap ?? () => _showFullScreenImage(context),
          child: Hero(
            tag: 'image_${widget.attachmentId}',
            child: imageWidget,
          ),
        ),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => FullScreenImageViewer(
          imageData: _cachedImageData!,
          tag: 'image_${widget.attachmentId}',
        ),
      ),
    );
  }
}

class FullScreenImageViewer extends StatelessWidget {
  final String imageData;
  final String tag;

  const FullScreenImageViewer({
    super.key,
    required this.imageData,
    required this.tag,
  });

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;

    if (imageData.startsWith('http')) {
      imageWidget = CachedNetworkImage(
        imageUrl: imageData,
        fit: BoxFit.contain,
        placeholder: (context, url) => Center(
          child: CircularProgressIndicator(
            color: context.conduitTheme.buttonPrimary,
          ),
        ),
        errorWidget: (context, url, error) => Center(
          child: Icon(
            Icons.error_outline,
            color: context.conduitTheme.error,
            size: 48,
          ),
        ),
      );
    } else {
      try {
        String actualBase64;
        if (imageData.startsWith('data:')) {
          final commaIndex = imageData.indexOf(',');
          actualBase64 = imageData.substring(commaIndex + 1);
        } else {
          actualBase64 = imageData;
        }
        final imageBytes = base64.decode(actualBase64);
        imageWidget = Image.memory(
          imageBytes,
          fit: BoxFit.contain,
        );
      } catch (e) {
        imageWidget = Center(
          child: Icon(
            Icons.error_outline,
            color: context.conduitTheme.error,
            size: 48,
          ),
        );
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Hero(
              tag: tag,
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: imageWidget,
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: IconButton(
              icon: const Icon(
                Icons.close,
                color: Colors.white,
                size: 28,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}