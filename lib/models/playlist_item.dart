enum PlaylistItemType { localFile, download, youtubeLink }

class PlaylistItem {
  final int? id;
  final int playlistId;
  final PlaylistItemType type;
  final String path; // file path for local/download, empty for youtubeLink
  final int? linkId; // reference to youtube_links.id
  final String title;
  final int sortOrder;

  PlaylistItem({
    this.id,
    required this.playlistId,
    required this.type,
    this.path = '',
    this.linkId,
    required this.title,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'playlistId': playlistId,
      'type': type.index,
      'path': path,
      'linkId': linkId,
      'title': title,
      'sortOrder': sortOrder,
    };
  }

  factory PlaylistItem.fromMap(Map<String, dynamic> map) {
    return PlaylistItem(
      id: map['id'] as int?,
      playlistId: map['playlistId'] as int,
      type: PlaylistItemType.values[map['type'] as int],
      path: (map['path'] as String?) ?? '',
      linkId: map['linkId'] as int?,
      title: map['title'] as String,
      sortOrder: (map['sortOrder'] as int?) ?? 0,
    );
  }

  PlaylistItem copyWith({
    int? id,
    int? playlistId,
    PlaylistItemType? type,
    String? path,
    int? linkId,
    String? title,
    int? sortOrder,
  }) {
    return PlaylistItem(
      id: id ?? this.id,
      playlistId: playlistId ?? this.playlistId,
      type: type ?? this.type,
      path: path ?? this.path,
      linkId: linkId ?? this.linkId,
      title: title ?? this.title,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
