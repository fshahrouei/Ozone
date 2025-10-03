import '../../../core/services/api_service.dart';
import '../models/article_model.dart';

/// Repository for handling CRUD operations on articles.
/// Uses [ApiService] to interact with the backend API.
class ArticlesRepository {
  final ApiService api = ApiService(ignoreSSLError: true);

  /// Returns the correct API endpoint for a given [action].
  /// Some actions require [id], otherwise an [ArgumentError] is thrown.
  String getEndpoint(String action, [dynamic id]) {
    switch (action) {
      case 'index':
        return "frontend/posts/index";
      case 'show':
        return id == null
            ? throw ArgumentError('id is required')
            : "frontend/posts/show/$id";
      case 'store':
        return "frontend/posts/store";
      case 'update':
        return id == null
            ? throw ArgumentError('id is required')
            : "frontend/posts/update/$id";
      case 'destroy':
        return id == null
            ? throw ArgumentError('id is required')
            : "frontend/posts/destroy/$id";
      default:
        throw UnimplementedError('Unknown endpoint: $action');
    }
  }

  List<Article> _articles = [];
  List<Article> get articles => _articles;

  /// Fetches a list of articles with pagination and optional search query.
  /// Resets the list when [page] is 1, otherwise appends new data.
  Future<List<Article>> fetchArticles({
    int page = 1,
    int limit = 12,
    String? query,
  }) async {
    String endpoint = "${getEndpoint('index')}?page=$page&limit=$limit";
    if (query != null && query.isNotEmpty) {
      // If your API uses a different param (e.g., `search`), adjust this line.
      endpoint += "&q=$query";
    }
    final response = await api.get(endpoint);
    final items = response['data'] as List;
    final fetched = items.map((e) => Article.fromJson(e)).toList();
    if (page == 1) {
      _articles = fetched;
    } else {
      _articles.addAll(fetched);
    }
    return fetched;
  }

  /// Fetches a single article by its [id].
  Future<Article> fetchArticleById(int id) async {
    final response = await api.get(getEndpoint('show', id));
    return Article.fromJson(response['data']);
  }

  /// Adds a new article and updates the local cache.
  Future<Article> addArticle(Article article) async {
    final response = await api.post(getEndpoint('store'), article.toJson());
    final newArticle = Article.fromJson(response['data']);
    _articles.add(newArticle);
    return newArticle;
  }

  /// Updates an existing article and replaces it in the local cache.
  Future<Article> updateArticle(Article article) async {
    final response = await api.put(
      getEndpoint('update', article.id),
      article.toJson(),
    );
    final updatedArticle = Article.fromJson(response['data']);
    final index = _articles.indexWhere((a) => a.id == updatedArticle.id);
    if (index != -1) {
      _articles[index] = updatedArticle;
    }
    return updatedArticle;
  }

  /// Deletes an article and removes it from the local cache.
  Future<void> deleteArticle(int id) async {
    await api.delete(getEndpoint('destroy', id));
    _articles.removeWhere((a) => a.id == id);
  }
}
