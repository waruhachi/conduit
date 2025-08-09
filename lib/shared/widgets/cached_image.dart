import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/theme_extensions.dart';
import 'improved_loading_states.dart';

/// Cached network image widget with progressive loading and error handling
class CachedImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;
  final bool enableMemoryCache;
  final int? maxWidthDiskCache;
  final int? maxHeightDiskCache;

  const CachedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.fadeOutDuration = const Duration(milliseconds: 100),
    this.enableMemoryCache = true,
    this.maxWidthDiskCache,
    this.maxHeightDiskCache,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: fadeInDuration,
      fadeOutDuration: fadeOutDuration,
      placeholder: placeholder != null
          ? (context, url) => placeholder!
          : _buildDefaultPlaceholder,
      errorWidget: errorWidget != null
          ? (context, url, error) => errorWidget!
          : _buildDefaultErrorWidget,
      memCacheWidth: enableMemoryCache ? width?.toInt() : null,
      memCacheHeight: enableMemoryCache ? height?.toInt() : null,
      maxWidthDiskCache: maxWidthDiskCache,
      maxHeightDiskCache: maxHeightDiskCache,
      useOldImageOnUrlChange: true,
      filterQuality: FilterQuality.medium,
    );
  }

  Widget _buildDefaultPlaceholder(BuildContext context, String url) {
    return ShimmerLoader(
      width: width ?? double.infinity,
      height: height ?? 200,
      borderRadius: BorderRadius.circular(8),
    );
  }

  Widget _buildDefaultErrorWidget(
    BuildContext context,
    String url,
    dynamic error,
  ) {
    return Container(
      width: width,
      height: height,
      color: context.conduitTheme.shimmerBase,
      child: Icon(
        Icons.broken_image,
        color: context.conduitTheme.iconSecondary,
        size: (width != null && height != null)
            ? (width! < height! ? width! * 0.5 : height! * 0.5)
            : 24,
      ),
    );
  }
}

/// Cached circular avatar with progressive loading
class CachedAvatar extends StatelessWidget {
  final String? imageUrl;
  final String fallbackText;
  final double radius;
  final Color? backgroundColor;
  final Color? textColor;

  const CachedAvatar({
    super.key,
    this.imageUrl,
    required this.fallbackText,
    this.radius = 20,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor:
          backgroundColor ?? context.conduitTheme.surfaceBackground,
      child: imageUrl != null
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: imageUrl!,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                placeholder: (context, url) => CircularProgressIndicator(
                  strokeWidth: 2,
                  color: textColor ?? context.conduitTheme.iconSecondary,
                ),
                errorWidget: (context, url, error) => Text(
                  fallbackText.isNotEmpty ? fallbackText[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: textColor ?? context.conduitTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: radius * 0.6,
                  ),
                ),
                memCacheWidth: (radius * 2).toInt(),
                memCacheHeight: (radius * 2).toInt(),
              ),
            )
          : Text(
              fallbackText.isNotEmpty ? fallbackText[0].toUpperCase() : '?',
              style: TextStyle(
                color: textColor ?? context.conduitTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.6,
              ),
            ),
    );
  }
}
