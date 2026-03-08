class DownloadHistoryItem {
  final String id;
  final String videoId;
  final String title;
  final String youtubeUrl;
  final String thumbnailUrl;
  final String filePath;
  final DateTime downloadDate;
  bool fileExists;

  DownloadHistoryItem({
    required this.id,
    required this.videoId,
    required this.title,
    required this.youtubeUrl,
    required this.thumbnailUrl,
    required this.filePath,
    required this.downloadDate,
    this.fileExists = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'videoId': videoId,
    'title': title,
    'youtubeUrl': youtubeUrl,
    'thumbnailUrl': thumbnailUrl,
    'filePath': filePath,
    'downloadDate': downloadDate.toIso8601String(),
    'fileExists': fileExists,
  };

  factory DownloadHistoryItem.fromJson(Map<String, dynamic> json) =>
      DownloadHistoryItem(
        id: json['id'],
        videoId: json['videoId'],
        title: json['title'],
        youtubeUrl: json['youtubeUrl'],
        thumbnailUrl: json['thumbnailUrl'],
        filePath: json['filePath'],
        downloadDate: DateTime.parse(json['downloadDate']),
        fileExists: json['fileExists'] ?? true,
      );
}
