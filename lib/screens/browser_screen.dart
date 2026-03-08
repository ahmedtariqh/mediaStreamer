import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/detected_video.dart';
import '../services/download_manager.dart';
import '../services/browser_state_service.dart';
import 'history_screen.dart';
import 'bookmarks_screen.dart';

class BrowserScreen extends StatefulWidget {
  final String? initialUrl;

  const BrowserScreen({super.key, this.initialUrl});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;
  late final TextEditingController _urlController;

  double progress = 0;
  bool canGoBack = false;
  bool canGoForward = false;

  // Settings
  bool isAdBlockEnabled = true;
  bool isDesktopMode = false;

  // Video Detection
  List<DetectedVideo> detectedVideos = [];

  final List<ContentBlocker> contentBlockers = [];

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: widget.initialUrl ?? 'https://duckduckgo.com/',
    );
    _loadSettings();
    _initAdBlockers();
  }

  Future<void> _loadSettings() async {
    final adBlock = await BrowserStateService.getAdBlockEnabled();
    final desktop = await BrowserStateService.getDesktopModeEnabled();
    setState(() {
      isAdBlockEnabled = adBlock;
      isDesktopMode = desktop;
    });
  }

  void _initAdBlockers() {
    final adDomains = [
      ".doubleclick.net",
      ".googleadservices.com",
      ".googlesyndication.com",
      ".moat.com",
      ".adnxs.com",
      ".criteo.com",
      ".taboola.com",
      ".outbrain.com",
      ".rubiconproject.com",
      ".amazon-adsystem.com",
      ".advertising.com",
      ".pubmatic.com",
      ".openx.net",
      ".adform.net",
    ];

    for (var domain in adDomains) {
      contentBlockers.add(
        ContentBlocker(
          trigger: ContentBlockerTrigger(urlFilter: domain),
          action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
        ),
      );
    }
  }

  void _checkMediaResource(String url) {
    if (url.isEmpty || url.startsWith('data:') || url.startsWith('blob:')) {
      return;
    }

    final lowerUrl = url.toLowerCase();

    // Check if it's a Youtube request - let the popup handle it directly
    if (lowerUrl.contains('youtube.com/watch') ||
        lowerUrl.contains('youtu.be/')) {
      // Only intercept if we haven't already returned the URL
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('YouTube video detected, returning to home...'),
        ),
      );
      Navigator.pop(context, url);
      return;
    }

    // Generic video detection
    String? mediaType;
    if (lowerUrl.contains('.m3u8')) {
      mediaType = 'HLS (m3u8)';
    } else if (lowerUrl.contains('.mp4')) {
      mediaType = 'MP4';
    } else if (lowerUrl.contains('.mkv')) {
      mediaType = 'MKV';
    } else if (lowerUrl.contains('.webm')) {
      mediaType = 'WEBM';
    }

    if (mediaType != null) {
      final nameStr = Uri.parse(url).pathSegments.last.isNotEmpty
          ? Uri.parse(url).pathSegments.last
          : 'Video Stream';

      final v = DetectedVideo(url: url, mediaType: mediaType, name: nameStr);
      if (!detectedVideos.contains(v)) {
        setState(() {
          detectedVideos.add(v);
        });
      }
    }
  }

  void _showDetectedVideos() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Detected Videos (${detectedVideos.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: detectedVideos.isEmpty
                  ? const Center(
                      child: Text('No videos detected on this page yet.'),
                    )
                  : ListView.builder(
                      itemCount: detectedVideos.length,
                      itemBuilder: (context, index) {
                        final video = detectedVideos[index];
                        return ListTile(
                          leading: const Icon(
                            Icons.video_library,
                            color: Colors.greenAccent,
                          ),
                          title: Text(
                            video.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(video.mediaType),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.download),
                                tooltip: 'Download',
                                onPressed: () {
                                  Navigator.pop(context);
                                  _startDownload(video.url, video.name);
                                },
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _startDownload(video.url, video.name);
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _startDownload(String url, String name) {
    if (url.toLowerCase().contains('.m3u8')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'HLS downloads via browser not fully supported yet. Please use YouTube links if available.',
          ),
        ),
      );
      return;
    }

    DownloadManager().startGenericDownload(url, name);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Started download: $name')));
  }

  Future<void> _handleMenuSelection(String choice) async {
    switch (choice) {
      case 'desktop':
        setState(() {
          isDesktopMode = !isDesktopMode;
        });
        await BrowserStateService.setDesktopModeEnabled(isDesktopMode);
        webViewController?.setSettings(
          settings: InAppWebViewSettings(
            preferredContentMode: isDesktopMode
                ? UserPreferredContentMode.DESKTOP
                : UserPreferredContentMode.RECOMMENDED,
          ),
        );
        webViewController?.reload();
        break;
      case 'adblock':
        setState(() {
          isAdBlockEnabled = !isAdBlockEnabled;
        });
        await BrowserStateService.setAdBlockEnabled(isAdBlockEnabled);
        webViewController?.setSettings(
          settings: InAppWebViewSettings(
            contentBlockers: isAdBlockEnabled ? contentBlockers : [],
          ),
        );
        webViewController?.reload();
        break;
      case 'history':
        final selectedUrl = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HistoryScreen()),
        );
        if (selectedUrl != null) {
          _urlController.text = selectedUrl;
          webViewController?.loadUrl(
            urlRequest: URLRequest(url: WebUri(selectedUrl)),
          );
        }
        break;
      case 'bookmarks':
        final selectedUrl = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BookmarksScreen()),
        );
        if (selectedUrl != null) {
          _urlController.text = selectedUrl;
          webViewController?.loadUrl(
            urlRequest: URLRequest(url: WebUri(selectedUrl)),
          );
        }
        break;
      case 'add_bookmark':
        final urlStr = (await webViewController?.getUrl())?.toString();
        final titleStr = (await webViewController?.getTitle()) ?? 'Bookmark';
        if (urlStr != null) {
          await BrowserStateService.addBookmark(urlStr, titleStr);
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Bookmark added')));
          }
        }
        break;
      case 'find':
        // For standard "Find in page" functionality
        // Could implement an overlay with a textfield that calls webViewController?.findAllAsync(find: text)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Use the address bar to search via duckduckgo'),
          ),
        );
        break;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Container(
          height: 40,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 16),
                padding: EdgeInsets.zero,
                onPressed: canGoBack ? () => webViewController?.goBack() : null,
                color: canGoBack ? Colors.white : Colors.white38,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 16),
                padding: EdgeInsets.zero,
                onPressed: canGoForward
                    ? () => webViewController?.goForward()
                    : null,
                color: canGoForward ? Colors.white : Colors.white38,
              ),
              Expanded(
                child: TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Search or type URL',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (value) {
                    var url = Uri.parse(value);
                    if (url.scheme.isEmpty) {
                      url = Uri.parse(
                        (value.contains(".") && !value.contains(" "))
                            ? "https://$value"
                            : "https://duckduckgo.com/?q=$value",
                      );
                    }
                    webViewController?.loadUrl(
                      urlRequest: URLRequest(url: WebUri.uri(url)),
                    );
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                padding: EdgeInsets.zero,
                onPressed: () => webViewController?.reload(),
              ),
            ],
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _handleMenuSelection,
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'bookmarks',
                child: ListTile(
                  leading: Icon(Icons.bookmarks),
                  title: Text('Bookmarks'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'history',
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text('History'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'add_bookmark',
                child: ListTile(
                  leading: Icon(Icons.bookmark_add),
                  title: Text('Add Bookmark'),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'desktop',
                child: ListTile(
                  leading: const Icon(Icons.desktop_mac),
                  title: const Text('Desktop Mode'),
                  trailing: isDesktopMode
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                ),
              ),
              PopupMenuItem<String>(
                value: 'adblock',
                child: ListTile(
                  leading: const Icon(Icons.shield),
                  title: const Text('Ad & Popup Blocker'),
                  trailing: isAdBlockEnabled
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'find',
                child: ListTile(
                  leading: Icon(Icons.search),
                  title: Text('Find in page'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (progress < 1.0)
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                InAppWebView(
                  key: webViewKey,
                  initialUrlRequest: URLRequest(
                    url: WebUri(widget.initialUrl ?? "https://duckduckgo.com/"),
                  ),
                  initialSettings: InAppWebViewSettings(
                    contentBlockers: isAdBlockEnabled ? contentBlockers : [],
                    javaScriptEnabled: true,
                    javaScriptCanOpenWindowsAutomatically:
                        true, // Requires onCreateWindow
                    supportMultipleWindows:
                        true, // We must handle onCreateWindow
                    useShouldOverrideUrlLoading:
                        true, // Needed to intercept requests natively, but MUST return ALLOW
                    mediaPlaybackRequiresUserGesture: false,
                    preferredContentMode: isDesktopMode
                        ? UserPreferredContentMode.DESKTOP
                        : UserPreferredContentMode.RECOMMENDED,
                    allowsInlineMediaPlayback: true,
                  ),
                  onWebViewCreated: (controller) {
                    webViewController = controller;
                  },
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final uri = navigationAction.request.url;
                    if (uri != null) {
                      _checkMediaResource(uri.toString());
                      // Important: explicitly allow navigation so links ACTUALLY work
                      return NavigationActionPolicy.ALLOW;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  onLoadStart: (controller, url) {
                    if (url != null) {
                      setState(() {
                        _urlController.text = url.toString();
                        // Reset caught videos on new page navigate
                        detectedVideos.clear();
                      });
                      _checkMediaResource(url.toString());
                    }
                  },
                  onLoadStop: (controller, url) async {
                    if (url != null) {
                      final title = await controller.getTitle() ?? "Unknown";
                      await BrowserStateService.addHistory(
                        url.toString(),
                        title,
                      );
                    }
                  },
                  shouldInterceptRequest: (controller, request) async {
                    _checkMediaResource(request.url.toString());
                    return null;
                  },
                  onProgressChanged: (controller, p) async {
                    final back = await controller.canGoBack();
                    final forward = await controller.canGoForward();
                    setState(() {
                      progress = p / 100;
                      canGoBack = back;
                      canGoForward = forward;
                    });
                  },
                  onCreateWindow: (controller, createWindowAction) async {
                    // Logic to handle new windows / popups
                    if (isAdBlockEnabled) {
                      // Silently block pop-ups when ad block is enabled
                      return false;
                    }

                    // If adBlock is disabled, open the popup link in our SAME window
                    final urlToOpen = createWindowAction.request.url;
                    if (urlToOpen != null) {
                      controller.loadUrl(
                        urlRequest: URLRequest(url: urlToOpen),
                      );
                    }
                    return true;
                  },
                ),

                // Floating Action Button for detected videos
                if (detectedVideos.isNotEmpty)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: FloatingActionButton.extended(
                      onPressed: _showDetectedVideos,
                      icon: const Icon(Icons.video_library),
                      label: Text('${detectedVideos.length} Videos'),
                      backgroundColor: Colors.greenAccent.shade700,
                      foregroundColor: Colors.black,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
