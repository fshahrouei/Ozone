// lib/modules/articles/screens/articles_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../controllers/articles_controller.dart';
import '../data/articles_repository.dart';
import '../models/article_model.dart';
import 'article_detail_page.dart';
import '../../../core/widgets/custom_app_bar.dart';

class ArticlesPage extends StatefulWidget {
  const ArticlesPage({super.key});

  @override
  State<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends State<ArticlesPage> {
  late final ArticlesController controller;
  final ScrollController _scrollController = ScrollController();

  // Coach targets: Help + Reload
  final GlobalKey _keyHelp = GlobalKey();
  final GlobalKey _keyReload = GlobalKey();
  TutorialCoachMark? _coach;

  // Floating error overlay
  OverlayEntry? _errorOverlay;

  @override
  void initState() {
    super.initState();
    controller = ArticlesController(repository: ArticlesRepository());
    controller.fetchArticles();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 100) {
        controller.loadMore();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _createCoach();
    });
  }

  @override
  void dispose() {
    _coach = null;
    _scrollController.dispose();
    super.dispose();
  }

  // ---------- Coach ----------
  void _createCoach() {
    _coach = TutorialCoachMark(
      targets: _targets(), // Help → Reload
      colorShadow: Colors.black,
      opacityShadow: 0.6,
      paddingFocus: 10,
      textSkip: '',
      skipWidget: const SizedBox.shrink(),
      imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      onFinish: () {},
      onSkip: () => true,
      pulseEnable: true,
      pulseAnimationDuration: const Duration(milliseconds: 600),
    );
  }

  void _showCoach() => _coach?.show(context: context);

  List<TargetFocus> _targets() {
    return [
      TargetFocus(
        identify: 'help',
        keyTarget: _keyHelp,
        shape: ShapeLightFocus.Circle,
        radius: 10,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (ctx, controller) => _CoachTip(
              title: 'Help',
              text:
                  'Browse a list of articles and news. '
                  'Tap any card to open details. More items load automatically as you scroll down.',
              primary: 'Next',
              onPrimary: controller.next,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.help_outline,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'reload',
        keyTarget: _keyReload,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (ctx, controller) => _CoachTip(
              title: 'Reload',
              text:
                  'Refresh the list of articles. '
                  'Use it after a network error or to fetch the latest content.',
              primary: 'Finish',
              onPrimary: controller.skip,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.refresh,
            ),
          ),
        ],
      ),
    ];
  }

  // ---------- Refresh ----------
  Future<void> _onRefresh() async {
    await controller.refreshArticles();
    if (mounted) setState(() {});
  }

  // ---------- UI ----------
  Widget _buildArticleCard(BuildContext context, Article article) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ArticleDetailPage(articleId: article.id),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.cardColor.withOpacity(0.5),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    if (article.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 7.0),
                        child: Text(
                          article.description.length > 75
                              ? '${article.description.substring(0, 75)}...'
                              : article.description,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: theme.textTheme.bodyMedium?.color,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(22),
                  bottomRight: Radius.circular(22),
                  bottomLeft: Radius.circular(22),
                  topLeft: Radius.circular(22),
                ),
                child: Image.network(
                  article.imageUrl,
                  width: 85,
                  height: 85,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.grey.shade200,
                    width: 85,
                    height: 85,
                    child: const Icon(
                      Icons.image_not_supported,
                      color: Colors.grey,
                      size: 35,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Floating error toast-like overlay
  void _showFloatingError(BuildContext context, String message) {
    if (!mounted) return;

    _errorOverlay?.remove();
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + kToolbarHeight + 12,
        left: 18,
        right: 18,
        child: AnimatedOpacity(
          opacity: 1.0,
          duration: const Duration(milliseconds: 220),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.87),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.18),
                    blurRadius: 15,
                    spreadRadius: 1,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 23),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15.5,
                        height: 1.16,
                        shadows: [Shadow(color: Colors.black26, blurRadius: 3)],
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: () {
                      _errorOverlay?.remove();
                      _errorOverlay = null;
                    },
                    splashRadius: 22,
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    _errorOverlay = overlayEntry;
    Overlay.of(context, rootOverlay: true).insert(overlayEntry);

    Future.delayed(const Duration(seconds: 3)).then((_) {
      if (!mounted) return;
      if (_errorOverlay?.mounted ?? false) {
        _errorOverlay?.remove();
        _errorOverlay = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // If app theme is dark, override this page to a light look (page-only).
    final base = Theme.of(context);
    final lightTheme = base.brightness == Brightness.dark
        ? ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF7F7F9),
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0.8,
            ),
            cardColor: Colors.white,
          )
        : base;

    return Theme(
      data: lightTheme,
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Articles',
          centerTitle: true,
          showDrawer: false,
          leading: [
            IconButton(
              key: _keyHelp,
              icon: const Icon(Icons.help_outline),
              tooltip: 'Help',
              onPressed: _showCoach,
            ),
          ],
          actions: [
            IconButton(
              key: _keyReload,
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload',
              onPressed: _onRefresh,
            ),
          ],
          onBackPressed: () {
            Navigator.pushNamed(context, '/');
          },
        ),
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            if (controller.isLoading && controller.articles.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (controller.articles.isEmpty) {
              return const Center(child: Text('No Data'));
            }

            return RefreshIndicator(
              onRefresh: _onRefresh,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(top: 12, bottom: 20),
                itemCount:
                    controller.articles.length + (controller.hasMore ? 1 : 0),
                itemBuilder: (context, idx) {
                  if (idx < controller.articles.length) {
                    final article = controller.articles[idx];
                    return _buildArticleCard(context, article);
                  } else {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// Lightweight, scrollable Coach tip widget
// ------------------------------------------------------------
class _CoachTip extends StatefulWidget {
  final String title;
  final String text;
  final String primary;
  final VoidCallback onPrimary;
  final String secondary;
  final VoidCallback onSecondary;
  final IconData icon;

  const _CoachTip({
    required this.title,
    required this.text,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.icon,
  });

  @override
  State<_CoachTip> createState() => _CoachTipState();
}

class _CoachTipState extends State<_CoachTip> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxW = size.width - 64;
    final maxH = size.height * 0.7;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Flexible(
                child: RawScrollbar(
                  controller: _scrollCtrl,
                  thumbVisibility: true,
                  thickness: 3,
                  radius: const Radius.circular(8),
                  thumbColor: Colors.white.withOpacity(0.3),
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      widget.text,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: widget.onSecondary,
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: widget.onPrimary,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(widget.primary),
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
