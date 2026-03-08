import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../services/youtube_service.dart';
import '../services/download_manager.dart';
import '../services/database_service.dart';
import '../models/youtube_link.dart';
import '../widgets/format_picker_sheet.dart';
import '../models/stream_info_item.dart';

class SharePopupScreen extends StatefulWidget {
  const SharePopupScreen({super.key});

  @override
  State<SharePopupScreen> createState() => _SharePopupScreenState();
}

class _SharePopupScreenState extends State<SharePopupScreen> {
  final _youtubeService = YoutubeService();
  bool _isFetching = true;
  String? _errorMessage;

  static const _channel = MethodChannel('com.mediastreamer/app_control');

  @override
  void initState() {
    super.initState();
    _handleIntent();
  }

  Future<void> _handleIntent() async {
    try {
      final initialMedia = await ReceiveSharingIntent.instance
          .getInitialMedia();
      if (initialMedia.isNotEmpty) {
        final text = initialMedia.first.path;

        final urlMatch = RegExp(
          r'(https?://(?:www\.)?(?:youtube\.com|youtu\.be)[^\s]+)',
        ).firstMatch(text);
        final url = urlMatch?.group(0) ?? text;

        if (url.contains('youtube') || url.contains('youtu.be')) {
          _fetchAndShowPicker(url);
          return;
        }
      }

      // Not a youtube URL or empty, close
      _closePopup(finish: true);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    }
  }

  Future<void> _fetchAndShowPicker(String url) async {
    try {
      final (video, streams) = await _youtubeService.getAvailableStreams(url);

      if (!mounted) return;
      setState(() => _isFetching = false);

      final selected = await showModalBottomSheet<StreamInfoItem>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => FormatPickerSheet(
          videoTitle: video.title,
          thumbnailUrl: video.thumbnails.highResUrl,
          streams: streams,
        ),
      );

      if (selected != null && mounted) {
        await DownloadManager().startDownload(url, selected);

        await DatabaseService.saveLink(
          YoutubeLink(
            url: url,
            title: video.title,
            notes: 'Started background download',
            dateAdded: DateTime.now(),
          ),
        );
        _closePopup(); // This sends task to back! So background download continues
      } else {
        _closePopup(finish: true); // User cancelled sheet, kill the task
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFetching = false;
          _errorMessage = 'Error: ${e.toString()}';
        });
      }
    }
  }

  void _closePopup({bool finish = false}) {
    if (finish) {
      _channel.invokeMethod('finish');
    } else {
      _channel.invokeMethod('minimize');
    }
  }

  @override
  void dispose() {
    _youtubeService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isFetching && _errorMessage == null) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: AlertDialog(
          title: const Text('Error'),
          content: Text(_errorMessage!),
          actions: [
            TextButton(
              onPressed: () => _closePopup(finish: true),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }

    return const Scaffold(backgroundColor: Colors.transparent);
  }
}
