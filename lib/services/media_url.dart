/// Extract web URLs from Android share text and match social hosts precisely.
class MediaUrl {
  static String? extract(String text) {
    for (final match in RegExp(
      r'https?://[^\s<>"\u0000-\u001f]+',
      caseSensitive: false,
    ).allMatches(text)) {
      final value = match.group(0)!.replaceFirst(RegExp(r'[).,;!\]}]+$'), '');
      final uri = Uri.tryParse(value);
      if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) continue;
      return uri.removeFragment().toString();
    }
    return null;
  }

  static String require(String text) {
    final url = extract(text);
    if (url == null) {
      throw const FormatException('Enter or share a valid video URL.');
    }
    return url;
  }

  static bool isSocialVideo(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return false;
    }
    final host = uri.host.toLowerCase();
    bool at(String domain) => host == domain || host.endsWith('.$domain');
    if (at('youtu.be')) return uri.pathSegments.isNotEmpty;
    if (at('youtube.com')) {
      return uri.path == '/watch' && uri.queryParameters.containsKey('v') ||
          RegExp(r'^/(shorts|live|embed)/[^/]+').hasMatch(uri.path);
    }
    if (at('facebook.com')) {
      return uri.path.contains('/videos/') ||
          uri.path.contains('/reel/') ||
          uri.path.startsWith('/share/') ||
          uri.path == '/watch/' ||
          uri.path == '/watch' ||
          uri.path == '/video.php';
    }
    if (at('fb.watch') || at('vm.tiktok.com') || at('vt.tiktok.com')) {
      return true;
    }
    if (at('instagram.com')) {
      return RegExp(r'^/(reel|reels|p)/[^/]+').hasMatch(uri.path);
    }
    if (at('tiktok.com')) return uri.path.contains('/video/');
    if (at('x.com') || at('twitter.com')) return uri.path.contains('/status/');
    return at('vimeo.com') && RegExp(r'/\d+').hasMatch(uri.path);
  }
}
