class VideoNote {
  final int? id;
  final String youtubeUrl;
  final String title;
  final String notes;
  final DateTime dateWatched;

  VideoNote({
    this.id,
    required this.youtubeUrl,
    required this.title,
    required this.notes,
    required this.dateWatched,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'youtubeUrl': youtubeUrl,
      'title': title,
      'notes': notes,
      'dateWatched': dateWatched.toIso8601String(),
    };
  }

  factory VideoNote.fromMap(Map<String, dynamic> map) {
    return VideoNote(
      id: map['id'] as int?,
      youtubeUrl: map['youtubeUrl'] as String,
      title: map['title'] as String,
      notes: map['notes'] as String,
      dateWatched: DateTime.parse(map['dateWatched'] as String),
    );
  }

  VideoNote copyWith({
    int? id,
    String? youtubeUrl,
    String? title,
    String? notes,
    DateTime? dateWatched,
  }) {
    return VideoNote(
      id: id ?? this.id,
      youtubeUrl: youtubeUrl ?? this.youtubeUrl,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      dateWatched: dateWatched ?? this.dateWatched,
    );
  }
}
