class FolderItem {
  final String name;
  final String path;
  final int mediaCount;

  const FolderItem({
    required this.name,
    required this.path,
    this.mediaCount = 0,
  });
}
