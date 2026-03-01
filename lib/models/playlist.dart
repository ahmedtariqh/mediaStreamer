class Playlist {
  final int? id;
  final String name;
  final DateTime dateCreated;

  Playlist({this.id, required this.name, required this.dateCreated});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'dateCreated': dateCreated.toIso8601String(),
    };
  }

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id'] as int?,
      name: map['name'] as String,
      dateCreated: DateTime.parse(map['dateCreated'] as String),
    );
  }

  Playlist copyWith({int? id, String? name, DateTime? dateCreated}) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      dateCreated: dateCreated ?? this.dateCreated,
    );
  }
}
