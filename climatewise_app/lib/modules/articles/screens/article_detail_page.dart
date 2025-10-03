import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../data/articles_repository.dart';
import '../models/article_model.dart';
import '../../../core/widgets/custom_app_bar.dart';

/// Shows a single article by ID, including cover image, title/summary,
/// and full Markdown content (if available).
class ArticleDetailPage extends StatefulWidget {
  final int articleId;
  const ArticleDetailPage({super.key, required this.articleId});

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  Article? article;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchDetail();
  }

  Future<void> fetchDetail() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final response =
          await ArticlesRepository().fetchArticleById(widget.articleId);
      setState(() {
        article = response;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Article Details',
        showDrawer: false,
        centerTitle: false, // left-aligned title
        onBackPressed: () => Navigator.pop(context), // back button
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text('Error: $errorMessage'))
              : article == null
                  ? const Center(child: Text('Article not found.'))
                  : ListView(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                      children: [
                        // Full-width cover image
                        Image.network(
                          article!.imageUrl,
                          width: double.infinity,
                          fit: BoxFit.fitWidth,
                          errorBuilder: (c, e, s) => Container(
                            color: Colors.grey.shade200,
                            height: 200,
                            alignment: Alignment.center,
                            child: const Icon(Icons.image,
                                size: 64, color: Colors.grey),
                          ),
                        ),

                        // Title
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                          child: Text(
                            article!.name,
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              height: 1.3,
                            ),
                          ),
                        ),

                        // Summary/description
                        if (article!.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                            child: Text(
                              article!.description,
                              style: const TextStyle(
                                fontSize: 15,
                                color: Colors.black87,
                                height: 1.45,
                              ),
                            ),
                          ),

                        // Full content (Markdown)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
                          child: MarkdownBody(
                            data: article!.markdown ?? '',
                            styleSheet: MarkdownStyleSheet.fromTheme(
                              Theme.of(context),
                            ).copyWith(
                              h1: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                              h2: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepPurple,
                              ),
                              h3: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                              p: const TextStyle(
                                fontSize: 15.2,
                                height: 1.65,
                                color: Colors.black87,
                              ),
                              blockquote: const TextStyle(
                                color: Colors.black87,
                                fontStyle: FontStyle.italic,
                                fontSize: 15.2,
                                height: 1.5,
                                letterSpacing: -0.1,
                              ),
                              blockquoteDecoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              listBullet: const TextStyle(
                                fontSize: 15.2,
                                color: Colors.blueGrey,
                              ),
                              code: TextStyle(
                                fontSize: 14,
                                backgroundColor: Colors.grey.shade100,
                                fontFamily: 'monospace',
                                color: Colors.deepOrange,
                              ),
                              horizontalRuleDecoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    width: 1,
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                              ),
                              tableHead: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15.5,
                              ),
                              tableBody: const TextStyle(
                                fontSize: 15.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}
