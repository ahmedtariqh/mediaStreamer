enum StreamType { muxed, videoOnly, audioOnly }

class StreamInfoItem {
  final String qualityLabel;
  final StreamType type;
  final String codec;
  final String container;
  final int sizeBytes;
  final String fileSize;
  final String formatId;
  final String title;
  final String thumbnailUrl;
  final String videoId;

  const StreamInfoItem({
    required this.qualityLabel,
    required this.type,
    required this.codec,
    required this.container,
    required this.sizeBytes,
    required this.fileSize,
    required this.formatId,
    this.title = '',
    this.thumbnailUrl = '',
    this.videoId = '',
  });

  String get typeLabel => switch (type) {
    StreamType.muxed => 'Video + Audio',
    StreamType.videoOnly => 'Video Only',
    StreamType.audioOnly => 'Audio Only',
  };

  static String formatFileSize(int bytes) {
    if (bytes <= 0) return 'Size varies';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }
}
