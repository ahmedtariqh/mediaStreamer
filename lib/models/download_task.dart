import 'package:uuid/uuid.dart';

enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

class DownloadTask {
  final String id;
  final String videoId;
  final String title;
  final String thumbnailUrl;
  final String youtubeUrl;
  String filePath;
  double progress;
  DownloadStatus status;
  String? errorMessage;

  // Transient state variables
  int downloadedBytes = 0;
  int totalBytes = 0;
  double currentSpeed = 0.0;

  DownloadTask({
    String? id,
    required this.videoId,
    required this.title,
    required this.thumbnailUrl,
    required this.youtubeUrl,
    this.filePath = '',
    this.progress = 0.0,
    this.status = DownloadStatus.queued,
    this.errorMessage,
  }) : id = id ?? const Uuid().v4();
}
