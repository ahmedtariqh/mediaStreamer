import 'package:youtube_explode_dart/youtube_explode_dart.dart';

enum StreamType { muxed, videoOnly, audioOnly }

class StreamInfoItem {
  final String qualityLabel;
  final StreamType type;
  final String codec;
  final String container;
  final int sizeBytes;
  final String fileSize;
  final StreamInfo streamInfo;

  StreamInfoItem({
    required this.qualityLabel,
    required this.type,
    required this.codec,
    required this.container,
    required this.sizeBytes,
    required this.fileSize,
    required this.streamInfo,
  });

  String get typeLabel {
    switch (type) {
      case StreamType.muxed:
        return 'Video + Audio';
      case StreamType.videoOnly:
        return 'Video Only';
      case StreamType.audioOnly:
        return 'Audio Only';
    }
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }
}
