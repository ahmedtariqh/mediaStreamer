enum DownloadStatus { queued, downloading, completed, failed, cancelled }

class DownloadTask {
  final String videoId;
  final String title;
  final String thumbnailUrl;
  final String youtubeUrl;
  String filePath;
  double progress;
  DownloadStatus status;
  String? errorMessage;

  DownloadTask({
    required this.videoId,
    required this.title,
    required this.thumbnailUrl,
    required this.youtubeUrl,
    this.filePath = '',
    this.progress = 0.0,
    this.status = DownloadStatus.queued,
    this.errorMessage,
  });
}
