class YoutubeLink {
  final int? id;
  final String url;
  final String title;
  final String notes;
  final DateTime dateAdded;

  YoutubeLink({
    this.id,
    required this.url,
    required this.title,
    this.notes = '',
    required this.dateAdded,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'url': url,
      'title': title,
      'notes': notes,
      'dateAdded': dateAdded.toIso8601String(),
    };
  }

  factory YoutubeLink.fromMap(Map<String, dynamic> map) {
    return YoutubeLink(
      id: map['id'] as int?,
      url: map['url'] as String,
      title: map['title'] as String,
      notes: (map['notes'] as String?) ?? '',
      dateAdded: DateTime.parse(map['dateAdded'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'title': title,
      'notes': notes,
      'dateAdded': dateAdded.toIso8601String(),
    };
  }

  YoutubeLink copyWith({
    int? id,
    String? url,
    String? title,
    String? notes,
    DateTime? dateAdded,
  }) {
    return YoutubeLink(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      dateAdded: dateAdded ?? this.dateAdded,
    );
  }
}
