class DetectedVideo {
  final String url;
  final String mediaType;
  final String name;

  DetectedVideo({
    required this.url,
    required this.mediaType,
    required this.name,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DetectedVideo && other.url == url;
  }

  @override
  int get hashCode => url.hashCode;
}
