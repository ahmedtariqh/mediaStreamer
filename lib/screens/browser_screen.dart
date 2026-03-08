import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;

  final _urlController = TextEditingController(text: 'https://duckduckgo.com/');
  double progress = 0;
  bool canGoBack = false;
  bool canGoForward = false;

  final List<ContentBlocker> contentBlockers = [];

  @override
  void initState() {
    super.initState();
    // Add some common ad blocking rules
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

  void _extractVideoLinks(String url) {
    if (url.contains('youtube.com/') || url.contains('youtu.be/')) {
      // Send it to the home screen
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('YouTube video detected, returning to home...'),
        ),
      );
      Navigator.pop(context, url);
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
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 20),
                onPressed: canGoBack ? () => webViewController?.goBack() : null,
                color: canGoBack ? Colors.white : Colors.white38,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 20),
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
                  decoration: const InputDecoration(
                    hintText: 'Search or type URL',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    isDense: true,
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
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => webViewController?.reload(),
              ),
            ],
          ),
        ),
        actions: const [SizedBox(width: 8)],
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
            child: InAppWebView(
              key: webViewKey,
              initialUrlRequest: URLRequest(
                url: WebUri("https://duckduckgo.com/"),
              ),
              initialSettings: InAppWebViewSettings(
                contentBlockers: contentBlockers,
                javaScriptEnabled: true,
                javaScriptCanOpenWindowsAutomatically: false,
                supportMultipleWindows: false,
                useShouldOverrideUrlLoading: true,
              ),
              onWebViewCreated: (controller) {
                webViewController = controller;
              },
              onLoadStart: (controller, url) {
                if (url != null) {
                  _urlController.text = url.toString();
                  _extractVideoLinks(url.toString());
                }
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
                // By default, block popups (returns false to ignore the window creation)
                return false;
              },
            ),
          ),
        ],
      ),
    );
  }
}
