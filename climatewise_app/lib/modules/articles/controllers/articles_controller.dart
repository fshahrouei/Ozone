import 'package:flutter/material.dart';
import '../data/articles_repository.dart';
import '../models/article_model.dart';

/// Controller for managing the state of articles:
/// - Handles fetching, searching, refreshing, and pagination.
/// - Provides loading, error, and "has more" state to the UI.
class ArticlesController with ChangeNotifier {
  final ArticlesRepository repository;

  ArticlesController({required this.repository});

  List<Article> _articles = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  final int _pageSize = 12;
  String _searchQuery = '';
  String? _errorMessage;

  List<Article> get articles => _articles;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;

  /// Fetches articles from the repository.
  /// - If [refresh] is true, it resets to the first page and clears the list.
  Future<void> fetchArticles({bool refresh = false}) async {
    if (_isLoading) return;
    _isLoading = true;

    if (refresh) {
      _currentPage = 1;
      _articles = [];
      _hasMore = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final newArticles = await repository.fetchArticles(
        page: _currentPage,
        limit: _pageSize,
        query: _searchQuery.isNotEmpty ? _searchQuery : null,
      );

      if (refresh) {
        _articles = newArticles;
      } else {
        _articles.addAll(newArticles);
      }

      _hasMore = newArticles.length == _pageSize;
      _currentPage++;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Starts a new search and resets the list.
  Future<void> searchArticles(String query) async {
    _searchQuery = query;
    await fetchArticles(refresh: true);
  }

  /// Loads the next page if available (typically triggered by scroll).
  Future<void> loadMore() async {
    if (!_hasMore || _isLoading) return;
    await fetchArticles();
  }

  /// Manually refreshes the list (e.g. pull-to-refresh).
  Future<void> refreshArticles() async {
    await fetchArticles(refresh: true);
  }
}
