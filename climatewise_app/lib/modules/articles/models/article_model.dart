/// Model representing an article item.
/// Includes minimal metadata plus optional full markdown content.
class Article {
  final int id;
  final String name;
  final String description;
  final String imageUrl;
  final DateTime? publishedAt;
  final String? markdown;

  Article({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    this.publishedAt,
    this.markdown,
  });

  /// Creates an [Article] instance from JSON.
  factory Article.fromJson(Map<String, dynamic> json) {
    String? dateStr = json['published_at']?.toString();
    return Article(
      id: int.tryParse(json['id'].toString()) ?? 0,
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      imageUrl: json['imageUrl'] ?? '',
      publishedAt: (dateStr != null && dateStr.isNotEmpty)
          ? DateTime.tryParse(dateStr)
          : null,
      markdown: json['markdown'], // May be null if content not provided
    );
  }

  /// Serializes [Article] back to JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'imageUrl': imageUrl,
      'published_at': publishedAt?.toIso8601String(),
      'markdown': markdown,
    };
  }
}
