import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:gpt_markdown/custom_widgets/markdown_config.dart'
    show CodeBlockBuilder, GptMarkdownConfig, ImageBuilder;
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:highlight/highlight.dart' as hl;

import '../../theme/theme_extensions.dart';

/// Registry used to compose custom markdown components.
class ConduitMarkdownRegistry {
  ConduitMarkdownRegistry._();

  static final List<MarkdownComponent> _blockComponents = [
    DetailsMarkdownComponent(),
  ];

  static final List<MarkdownComponent> _inlineComponents = [];

  static UnmodifiableListView<MarkdownComponent> get blockComponents =>
      UnmodifiableListView(_blockComponents);

  static UnmodifiableListView<MarkdownComponent> get inlineComponents =>
      UnmodifiableListView(_inlineComponents);

  static void registerBlockComponent(MarkdownComponent component) {
    _blockComponents.add(component);
  }

  static void registerInlineComponent(MarkdownComponent component) {
    _inlineComponents.add(component);
  }

  static List<MarkdownComponent> composeBlockComponents() {
    return [..._blockComponents, ...MarkdownComponent.globalComponents];
  }

  static List<MarkdownComponent> composeInlineComponents() {
    return [..._inlineComponents, ...MarkdownComponent.inlineComponents];
  }
}

class ConduitMarkdownTheme {
  const ConduitMarkdownTheme({
    required this.textStyle,
    required this.themeData,
    required this.imageBuilder,
    required this.codeBuilder,
    required this.blockComponents,
    required this.inlineComponents,
    this.followLinkColor = true,
  });

  final TextStyle textStyle;
  final GptMarkdownThemeData themeData;
  final ImageBuilder imageBuilder;
  final CodeBlockBuilder codeBuilder;
  final List<MarkdownComponent> blockComponents;
  final List<MarkdownComponent> inlineComponents;
  final bool followLinkColor;
}

class ConduitMarkdownConfig {
  static ConduitMarkdownTheme resolve(BuildContext context) {
    final theme = context.conduitTheme;
    final materialTheme = Theme.of(context);

    final bodyStyle = AppTypography.bodyMediumStyle.copyWith(
      color: theme.textPrimary,
      height: 1.45,
    );

    final codeColor = theme.code?.color ?? theme.textSecondary;

    final markdownThemeData = GptMarkdownThemeData(
      brightness: materialTheme.brightness,
      h1: AppTypography.headlineLargeStyle.copyWith(color: theme.textPrimary),
      h2: AppTypography.headlineMediumStyle.copyWith(color: theme.textPrimary),
      h3: AppTypography.headlineSmallStyle.copyWith(color: theme.textPrimary),
      h4: AppTypography.bodyLargeStyle.copyWith(color: theme.textPrimary),
      h5: AppTypography.bodyMediumStyle.copyWith(
        color: theme.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      h6: AppTypography.bodySmallStyle.copyWith(color: theme.textSecondary),
      hrLineColor: theme.dividerColor,
      highlightColor: theme.surfaceContainer.withValues(alpha: 0.4),
      linkColor: materialTheme.colorScheme.primary,
      linkHoverColor: materialTheme.colorScheme.primary.withValues(alpha: 0.8),
    );

    return ConduitMarkdownTheme(
      textStyle: bodyStyle,
      themeData: markdownThemeData,
      imageBuilder: (context, imageUrl) {
        final uri = Uri.tryParse(imageUrl);
        if (uri == null) {
          return _buildImageError(context, context.conduitTheme);
        }

        final scheme = uri.scheme;

        if (scheme == 'data') {
          return buildBase64Image(imageUrl, context, context.conduitTheme);
        }

        if (scheme.isEmpty || scheme == 'http' || scheme == 'https') {
          return buildNetworkImage(imageUrl, context, context.conduitTheme);
        }

        return const SizedBox.shrink();
      },
      codeBuilder: (context, name, code, closed) {
        final conduitTheme = context.conduitTheme;
        final textStyle = AppTypography.codeStyle.copyWith(
          color: conduitTheme.code?.color ?? codeColor,
        );

        final container = ConduitCodeView(
          code: code,
          language: name.trim().isEmpty ? null : name.trim(),
          baseStyle: textStyle,
          conduitTheme: conduitTheme,
        );

        return CodeBlockWrapper(
          code: code,
          language: name.trim().isEmpty ? null : name.trim(),
          theme: conduitTheme,
          child: container,
        );
      },
      blockComponents: ConduitMarkdownRegistry.composeBlockComponents(),
      inlineComponents: ConduitMarkdownRegistry.composeInlineComponents(),
    );
  }

  static Widget buildBase64Image(
    String dataUrl,
    BuildContext context,
    ConduitThemeExtension theme,
  ) {
    try {
      final commaIndex = dataUrl.indexOf(',');
      if (commaIndex == -1) {
        throw Exception('Invalid data URL format');
      }

      final base64String = dataUrl.substring(commaIndex + 1);
      final imageBytes = base64.decode(base64String);

      return ConduitMarkdownImage.memory(bytes: imageBytes, theme: theme);
    } catch (e) {
      return _buildImageError(context, theme);
    }
  }

  static Widget buildNetworkImage(
    String url,
    BuildContext context,
    ConduitThemeExtension theme,
  ) {
    return ConduitMarkdownImage.network(url: url, theme: theme);
  }

  static Widget _buildImageError(
    BuildContext context,
    ConduitThemeExtension theme,
  ) {
    return const SizedBox.shrink();
  }
}

class CodeBlockWrapper extends StatelessWidget {
  const CodeBlockWrapper({
    super.key,
    required this.child,
    required this.code,
    this.language,
    required this.theme,
  });

  final Widget child;
  final String code;
  final String? language;
  final ConduitThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: theme.surfaceBackground.withValues(alpha: 0.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppBorderRadius.sm),
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                _showCopiedToast(context);
              },
              child: Container(
                padding: const EdgeInsets.all(Spacing.xs),
                decoration: BoxDecoration(
                  color: theme.surfaceBackground.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(AppBorderRadius.sm),
                ),
                child: Icon(
                  Icons.copy,
                  size: IconSize.sm,
                  color: theme.iconSecondary,
                ),
              ),
            ),
          ),
        ),
        if (language != null)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm,
                vertical: Spacing.xxs,
              ),
              decoration: BoxDecoration(
                color: theme.surfaceBackground.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(AppBorderRadius.xs),
              ),
              child: Text(
                language!,
                style: AppTypography.bodySmallStyle.copyWith(
                  color: theme.textSecondary,
                  fontFamily: AppTypography.monospaceFontFamily,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

void _showCopiedToast(BuildContext context) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    return;
  }
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: const Text('Code copied to clipboard.'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      backgroundColor: context.conduitTheme.surfaceContainer,
    ),
  );
}

class ConduitCodeView extends StatelessWidget {
  const ConduitCodeView({
    super.key,
    required this.code,
    required this.language,
    required this.baseStyle,
    required this.conduitTheme,
  });

  final String code;
  final String? language;
  final TextStyle baseStyle;
  final ConduitThemeExtension conduitTheme;

  @override
  Widget build(BuildContext context) {
    final normalizedLanguage = language?.toLowerCase();
    hl.Result? result;
    try {
      result = hl.highlight.parse(
        code,
        language: normalizedLanguage != null && normalizedLanguage.isNotEmpty
            ? normalizedLanguage
            : null,
        autoDetection: normalizedLanguage == null || normalizedLanguage.isEmpty,
      );
    } catch (_) {
      result = hl.highlight.parse(code, autoDetection: true);
    }

    final spans = _buildTextSpans(
      result.nodes ?? const <hl.Node>[],
      baseStyle,
      conduitTheme,
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: Spacing.xs),
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: conduitTheme.surfaceBackground.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        border: Border.all(
          color: conduitTheme.cardBorder.withValues(alpha: 0.2),
          width: BorderWidth.micro,
        ),
      ),
      child: SelectableText.rich(
        TextSpan(
          style: baseStyle,
          children: spans.isNotEmpty ? spans : [TextSpan(text: code)],
        ),
      ),
    );
  }

  List<TextSpan> _buildTextSpans(
    List<hl.Node> nodes,
    TextStyle base,
    ConduitThemeExtension theme,
  ) {
    if (nodes.isEmpty) {
      return const [];
    }

    return nodes.map((node) {
      final style = _styleFor(node.className, base, theme);
      if ((node.children ?? const []).isNotEmpty) {
        return TextSpan(
          style: style,
          children: _buildTextSpans(node.children!, style, theme),
        );
      }
      return TextSpan(text: node.value ?? '', style: style);
    }).toList();
  }

  TextStyle _styleFor(
    String? className,
    TextStyle base,
    ConduitThemeExtension theme,
  ) {
    if (className == null || className.isEmpty) {
      return base;
    }

    final colorMap = <String, Color>{
      'keyword': theme.info,
      'built_in': theme.info,
      'type': theme.info,
      'literal': theme.warning,
      'symbol': theme.warning,
      'number': theme.warning,
      'string': theme.success,
      'subst': theme.textSecondary,
      'comment': theme.textSecondary.withValues(alpha: 0.7),
      'quote': theme.textSecondary.withValues(alpha: 0.7),
      'doctag': theme.info,
      'meta': theme.iconSecondary,
      'title': theme.info,
      'section': theme.info,
      'attr': theme.warning,
      'attribute': theme.warning,
      'name': theme.info,
      'selector-tag': theme.info,
    };

    Color? color;
    for (final entry in colorMap.entries) {
      if (className.contains(entry.key)) {
        color = entry.value;
        break;
      }
    }

    return base.copyWith(
      color: color ?? base.color ?? theme.code?.color ?? theme.textSecondary,
      fontStyle: className.contains('comment')
          ? FontStyle.italic
          : base.fontStyle,
      fontWeight: className.contains('keyword')
          ? FontWeight.w600
          : base.fontWeight,
    );
  }
}

class ConduitMarkdownImage extends StatelessWidget {
  const ConduitMarkdownImage._({
    required this.child,
    required this.theme,
    required this.heroTag,
    required this.semanticLabel,
  });

  static int _heroSequence = 0;

  static String _nextHeroTag(String base) {
    final tag = '$base#${_heroSequence++}';
    return tag;
  }

  factory ConduitMarkdownImage.network({
    required String url,
    required ConduitThemeExtension theme,
  }) {
    final lowerUrl = url.toLowerCase();
    final isAnimated = lowerUrl.endsWith('.gif') || lowerUrl.endsWith('.webp');

    final heroTag = _nextHeroTag('markdown_image_$url');

    return ConduitMarkdownImage._(
      theme: theme,
      heroTag: heroTag,
      semanticLabel: 'Markdown image',
      child: CachedNetworkImage(
        imageUrl: url,
        fadeInDuration: const Duration(milliseconds: 200),
        imageBuilder: (context, provider) {
          return _InteractiveImage(
            theme: theme,
            heroTag: heroTag,
            child: Image(image: provider, fit: BoxFit.contain),
          );
        },
        placeholder: (context, url) => Container(
          height: 200,
          decoration: BoxDecoration(
            color: theme.surfaceBackground.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
          ),
          child: Center(
            child: CircularProgressIndicator(
              color: theme.loadingIndicator,
              strokeWidth: 2,
            ),
          ),
        ),
        errorWidget: (context, url, error) =>
            ConduitMarkdownConfig._buildImageError(context, theme),
        memCacheHeight: isAnimated ? null : 1024,
        memCacheWidth: isAnimated ? null : 1024,
      ),
    );
  }

  factory ConduitMarkdownImage.memory({
    required Uint8List bytes,
    required ConduitThemeExtension theme,
  }) {
    final heroTag = _nextHeroTag('markdown_image_memory');

    return ConduitMarkdownImage._(
      theme: theme,
      heroTag: heroTag,
      semanticLabel: 'Embedded markdown image',
      child: _InteractiveImage(
        theme: theme,
        heroTag: heroTag,
        child: Image.memory(bytes, fit: BoxFit.contain),
      ),
    );
  }

  final Widget child;
  final ConduitThemeExtension theme;
  final String heroTag;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(label: semanticLabel, image: true, child: child);
  }
}

class _InteractiveImage extends StatelessWidget {
  const _InteractiveImage({
    required this.theme,
    required this.heroTag,
    required this.child,
  });

  final ConduitThemeExtension theme;
  final String heroTag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showImageViewer(context, heroTag, child, theme),
      child: Hero(
        tag: heroTag,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: Spacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
            boxShadow: [
              BoxShadow(
                color: theme.cardShadow.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 500),
            child: child,
          ),
        ),
      ),
    );
  }
}

void _showImageViewer(
  BuildContext context,
  String heroTag,
  Widget child,
  ConduitThemeExtension theme,
) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: theme.surfaceBackground.withValues(alpha: 0.85),
        insetPadding: const EdgeInsets.all(Spacing.md),
        child: Hero(
          tag: heroTag,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppBorderRadius.lg),
            child: InteractiveViewer(minScale: 0.5, maxScale: 4, child: child),
          ),
        ),
      );
    },
  );
}

class DetailsMarkdownComponent extends BlockMd {
  @override
  String get expString => r"<details[^>]*>[\s\S]*?<\/details>";

  @override
  Widget build(BuildContext context, String text, GptMarkdownConfig config) {
    final summaryMatch = RegExp(
      r"<summary[^>]*>([\s\S]*?)<\/summary>",
      dotAll: true,
      multiLine: true,
    ).firstMatch(text);

    final summary = summaryMatch?.group(1)?.trim() ?? 'Details';

    var content = text
        .replaceFirst(RegExp(r"<details[^>]*>"), '')
        .replaceAll(summaryMatch?.group(0) ?? '', '')
        .replaceFirst(RegExp(r"<\/details>\s*$"), '')
        .trim();

    return ConduitDetailsBlock(
      summary: summary,
      content: content,
      config: config,
    );
  }
}

class ConduitDetailsBlock extends StatefulWidget {
  const ConduitDetailsBlock({
    super.key,
    required this.summary,
    required this.content,
    required this.config,
  });

  final String summary;
  final String content;
  final GptMarkdownConfig config;

  @override
  State<ConduitDetailsBlock> createState() => _ConduitDetailsBlockState();
}

class _ConduitDetailsBlockState extends State<ConduitDetailsBlock> {
  late bool _expanded;
  late List<InlineSpan> _contentSpans;

  @override
  void initState() {
    super.initState();
    _expanded = false;
    _contentSpans = MarkdownComponent.generate(
      context,
      widget.content,
      widget.config.copyWith(),
      true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    final cardColor = theme.surfaceContainer.withValues(alpha: 0.7);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: Spacing.sm),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
        boxShadow: [
          BoxShadow(
            color: theme.cardShadow.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
        child: ExpansionTile(
          title: Text(
            widget.summary,
            style: AppTypography.headlineSmallStyle.copyWith(
              color: theme.textPrimary,
            ),
          ),
          tilePadding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          trailing: Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            color: theme.iconSecondary,
          ),
          onExpansionChanged: (isExpanded) {
            setState(() => _expanded = isExpanded);
          },
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              child: widget.config.getRich(
                TextSpan(style: widget.config.style, children: _contentSpans),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
