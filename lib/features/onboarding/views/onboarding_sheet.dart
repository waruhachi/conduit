import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../../shared/theme/theme_extensions.dart';
import 'package:flutter_animate/flutter_animate.dart';

class OnboardingSheet extends StatefulWidget {
  const OnboardingSheet({super.key});

  @override
  State<OnboardingSheet> createState() => _OnboardingSheetState();
}

class _OnboardingSheetState extends State<OnboardingSheet> {
  final PageController _controller = PageController();
  int _index = 0;

  final List<_OnboardingPage> _pages = const [
    _OnboardingPage(
      title: 'Start a conversation',
      subtitle:
          'Choose a model, then type below to begin. Tap New Chat anytime.',
      icon: CupertinoIcons.chat_bubble_2,
      bullets: [
        'Tap the model name in the top bar to switch models',
        'Use New Chat to reset context',
      ],
    ),
    _OnboardingPage(
      title: 'Attach context',
      subtitle: 'Ground responses by adding files or images.',
      icon: CupertinoIcons.doc_on_doc,
      bullets: ['Files: PDFs, docs, datasets', 'Images: photos or screenshots'],
    ),
    _OnboardingPage(
      title: 'Speak naturally',
      subtitle: 'Tap the mic to dictate with live waveform feedback.',
      icon: CupertinoIcons.mic_fill,
      bullets: [
        'Stop anytime; partial text is preserved',
        'Great for quick notes or long prompts',
      ],
    ),
    _OnboardingPage(
      title: 'Quick actions',
      subtitle:
          'Long‑press the top‑left menu to open shortcuts like New Chat, Files, and Profile.',
      icon: CupertinoIcons.line_horizontal_3,
      bullets: [
        'Tap to open chats list; long‑press for Quick Actions',
        'Jump instantly to New Chat, Files, or Profile',
      ],
    ),
  ];

  void _next() {
    if (_index < _pages.length - 1) {
      _controller.nextPage(
        duration: AnimationDuration.fast,
        curve: AnimationCurves.easeInOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    final isSmall = height < 720;
    return Container(
      height: height * 0.7,
      decoration: BoxDecoration(
        color: context.conduitTheme.surfaceBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppBorderRadius.modal),
        ),
        boxShadow: ConduitShadows.modal,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: Spacing.md),
                decoration: BoxDecoration(
                  color: context.conduitTheme.dividerColor,
                  borderRadius: BorderRadius.circular(AppBorderRadius.xs),
                ),
              ),

              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) {
                    final page = _pages[i];
                    final content = _IllustratedPage(page: page);
                    return isSmall
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Spacing.lg,
                            ),
                            child: content,
                          )
                        : content;
                  },
                ),
              ),

              const SizedBox(height: Spacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: AnimationDuration.fast,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 6,
                    width: active ? 20 : 6,
                    decoration: BoxDecoration(
                      color: active
                          ? context.conduitTheme.buttonPrimary
                          : context.conduitTheme.dividerColor,
                      borderRadius: BorderRadius.circular(
                        AppBorderRadius.badge,
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: Spacing.lg),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        color: context.conduitTheme.textSecondary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: context.conduitTheme.buttonPrimary,
                      foregroundColor: context.conduitTheme.buttonPrimaryText,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.lg,
                        vertical: Spacing.sm,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppBorderRadius.button,
                        ),
                      ),
                    ),
                    child: Text(_index == _pages.length - 1 ? 'Done' : 'Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String>? bullets;
  const _OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.bullets,
  });
}

class _IllustratedPage extends StatelessWidget {
  final _OnboardingPage page;
  const _IllustratedPage({required this.page});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Aurora blob illustration
        SizedBox(
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(top: 10, left: 24, child: _blob(context, 90, 0.18)),
              Positioned(
                bottom: 0,
                right: 16,
                child: _blob(context, 130, 0.12),
              ),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: context.conduitTheme.buttonPrimary,
                  borderRadius: BorderRadius.circular(AppBorderRadius.avatar),
                  boxShadow: ConduitShadows.glow,
                ),
                child: Icon(page.icon, color: context.conduitTheme.textInverse),
              ).animate().scale(duration: AnimationDuration.fast),
            ],
          ),
        ),
        const SizedBox(height: Spacing.lg),
        Text(
          page.title,
          style: TextStyle(
            fontSize: AppTypography.headlineMedium,
            fontWeight: FontWeight.w700,
            color: context.conduitTheme.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          page.subtitle,
          style: TextStyle(
            fontSize: AppTypography.bodyLarge,
            color: context.conduitTheme.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        if (page.bullets != null && page.bullets!.isNotEmpty) ...[
          const SizedBox(height: Spacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: page.bullets!
                .map(
                  (b) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.lg,
                      vertical: 4,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(top: 8, right: 8),
                          decoration: BoxDecoration(
                            color: context.conduitTheme.buttonPrimary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            b,
                            style: TextStyle(
                              color: context.conduitTheme.textSecondary,
                              fontSize: AppTypography.bodyMedium,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _blob(BuildContext context, double size, double alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.conduitTheme.buttonPrimary.withValues(alpha: alpha),
        boxShadow: ConduitShadows.glow,
      ),
    );
  }
}
