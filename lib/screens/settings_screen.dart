import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';
import '../services/webhook_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ── Resume Playback ──
  bool _resumePlayback = true;
  bool _showResumeOnStartup = true;
  int _historyCount = 0;

  // ── Webhook ──
  bool _webhookEnabled = false;
  String _webhookUrl = '';
  int _webhookInterval = 60;
  bool _webhookSendNotes = true;
  bool _webhookSendLinks = true;
  bool _webhookDeleteAfterSend = false;

  static const _intervals = <int, String>{
    5: '5 minutes',
    15: '15 minutes',
    30: '30 minutes',
    60: '1 hour',
    360: '6 hours',
    720: '12 hours',
    1440: '24 hours',
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final positions = await DatabaseService.getAllPlaybackPositions();
    if (!mounted) return;
    setState(() {
      _resumePlayback = prefs.getBool('resumePlayback') ?? true;
      _showResumeOnStartup = prefs.getBool('showResumeOnStartup') ?? true;
      _historyCount = positions.length;

      _webhookEnabled = prefs.getBool('webhookEnabled') ?? false;
      _webhookUrl = prefs.getString('webhookUrl') ?? '';
      _webhookInterval = prefs.getInt('webhookIntervalMinutes') ?? 60;
      _webhookSendNotes = prefs.getBool('webhookSendNotes') ?? true;
      _webhookSendLinks = prefs.getBool('webhookSendLinks') ?? true;
      _webhookDeleteAfterSend =
          prefs.getBool('webhookDeleteAfterSend') ?? false;
    });
  }

  // ── Resume helpers ──

  Future<void> _setResumePlayback(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('resumePlayback', value);
    setState(() => _resumePlayback = value);
  }

  Future<void> _setShowResumeOnStartup(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showResumeOnStartup', value);
    setState(() => _showResumeOnStartup = value);
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Playback History'),
        content: const Text(
          'This will remove all saved playback positions. '
          'You won\'t be able to resume any previously played files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseService.clearAllPlaybackPositions();
      if (mounted) {
        setState(() => _historyCount = 0);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Playback history cleared')),
        );
      }
    }
  }

  // ── Webhook helpers ──

  Future<void> _setWebhookPref(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  Future<void> _toggleWebhookEnabled(bool value) async {
    if (value && _webhookUrl.isEmpty) {
      // Force user to enter a URL first
      final url = await _promptWebhookUrl();
      if (url == null || url.isEmpty) return;
      _webhookUrl = url;
      await _setWebhookPref('webhookUrl', url);
    }
    await _setWebhookPref('webhookEnabled', value);
    setState(() => _webhookEnabled = value);
    if (value) {
      await WebhookService.restart();
    } else {
      WebhookService.stop();
    }
  }

  Future<void> _setWebhookInterval(int minutes) async {
    await _setWebhookPref('webhookIntervalMinutes', minutes);
    setState(() => _webhookInterval = minutes);
    if (_webhookEnabled) await WebhookService.restart();
  }

  Future<void> _toggleSendNotes(bool value) async {
    await _setWebhookPref('webhookSendNotes', value);
    setState(() => _webhookSendNotes = value);
  }

  Future<void> _toggleSendLinks(bool value) async {
    await _setWebhookPref('webhookSendLinks', value);
    setState(() => _webhookSendLinks = value);
  }

  Future<void> _toggleDeleteAfterSend(bool value) async {
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enable Delete After Send?'),
          content: const Text(
            'When enabled, all sent notes and links will be permanently '
            'deleted from your device after a successful webhook delivery.\n\n'
            'This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Enable'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _setWebhookPref('webhookDeleteAfterSend', value);
    setState(() => _webhookDeleteAfterSend = value);
  }

  Future<String?> _promptWebhookUrl() {
    final controller = TextEditingController(text: _webhookUrl);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Webhook URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://example.com/webhook',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editWebhookUrl() async {
    final url = await _promptWebhookUrl();
    if (url == null) return;
    _webhookUrl = url;
    await _setWebhookPref('webhookUrl', url);
    setState(() {});
    if (_webhookEnabled && url.isEmpty) {
      await _toggleWebhookEnabled(false);
    }
  }

  Future<void> _sendNow() async {
    final success = await WebhookService.sendNow();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Webhook sent successfully' : 'Webhook send failed',
          ),
          backgroundColor: success ? Colors.green : Colors.redAccent,
        ),
      );
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Resume Playback Section ──
          _SectionHeader(title: 'Resume Playback', icon: Icons.replay),
          const SizedBox(height: 8),
          _buildCard(
            theme,
            children: [
              SwitchListTile(
                title: const Text('Auto-Resume Playback'),
                subtitle: const Text(
                  'Automatically resume files from where you left off',
                ),
                value: _resumePlayback,
                onChanged: _setResumePlayback,
                secondary: Icon(
                  Icons.play_circle_outline,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Divider(height: 1, indent: 56),
              SwitchListTile(
                title: const Text('Startup Resume Reminder'),
                subtitle: const Text(
                  'Show a reminder to continue your last media on app launch',
                ),
                value: _showResumeOnStartup,
                onChanged: _setShowResumeOnStartup,
                secondary: Icon(
                  Icons.notifications_active_outlined,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Playback History Section ──
          _SectionHeader(title: 'Playback History', icon: Icons.history),
          const SizedBox(height: 8),
          _buildCard(
            theme,
            children: [
              ListTile(
                leading: Icon(
                  Icons.storage_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Saved Positions'),
                subtitle: Text(
                  '$_historyCount file${_historyCount == 1 ? '' : 's'} tracked',
                ),
                trailing: Text(
                  '$_historyCount',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(
                  Icons.delete_sweep_outlined,
                  color: Colors.redAccent,
                ),
                title: const Text('Clear All Playback History'),
                subtitle: const Text('Remove all saved positions'),
                onTap: _historyCount > 0 ? _clearHistory : null,
                enabled: _historyCount > 0,
                trailing: _historyCount > 0
                    ? const Icon(Icons.chevron_right, color: Colors.white38)
                    : null,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Webhook Export Section ──
          _SectionHeader(title: 'Webhook Export', icon: Icons.webhook),
          const SizedBox(height: 8),
          _buildCard(
            theme,
            children: [
              SwitchListTile(
                title: const Text('Enable Webhook'),
                subtitle: Text(
                  _webhookEnabled ? 'Sending periodically' : 'Disabled',
                ),
                value: _webhookEnabled,
                onChanged: _toggleWebhookEnabled,
                secondary: Icon(
                  Icons.power_settings_new,
                  color: _webhookEnabled
                      ? Colors.greenAccent
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: Icon(Icons.link, color: theme.colorScheme.primary),
                title: const Text('Webhook URL'),
                subtitle: Text(
                  _webhookUrl.isEmpty ? 'Not set' : _webhookUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(
                  Icons.edit_outlined,
                  color: Colors.white38,
                ),
                onTap: _editWebhookUrl,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: Icon(
                  Icons.timer_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Send Interval'),
                trailing: DropdownButton<int>(
                  value: _webhookInterval,
                  underline: const SizedBox.shrink(),
                  dropdownColor: theme.colorScheme.surface,
                  items: _intervals.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _setWebhookInterval(v);
                  },
                ),
              ),
              const Divider(height: 1, indent: 56),
              SwitchListTile(
                title: const Text('Send Notes'),
                value: _webhookSendNotes,
                onChanged: _toggleSendNotes,
                secondary: Icon(
                  Icons.note_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Divider(height: 1, indent: 56),
              SwitchListTile(
                title: const Text('Send Links'),
                value: _webhookSendLinks,
                onChanged: _toggleSendLinks,
                secondary: Icon(
                  Icons.link_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Divider(height: 1, indent: 56),
              SwitchListTile(
                title: const Text('Delete After Send'),
                subtitle: const Text(
                  'Remove notes/links from device after successful send',
                ),
                value: _webhookDeleteAfterSend,
                onChanged: _toggleDeleteAfterSend,
                secondary: Icon(
                  Icons.delete_forever_outlined,
                  color: _webhookDeleteAfterSend
                      ? Colors.redAccent
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
              const Divider(height: 1, indent: 56),
              // Send Now button
              ListTile(
                leading: ValueListenableBuilder<bool>(
                  valueListenable: WebhookService.isSending,
                  builder: (_, sending, child) => sending
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Icon(
                          Icons.send_outlined,
                          color: theme.colorScheme.primary,
                        ),
                ),
                title: const Text('Send Now'),
                subtitle: const Text('Send immediately regardless of timer'),
                onTap: _webhookUrl.isNotEmpty ? _sendNow : null,
                enabled: _webhookUrl.isNotEmpty,
              ),
              const Divider(height: 1, indent: 56),
              // Last status
              ValueListenableBuilder<String>(
                valueListenable: WebhookService.lastStatus,
                builder: (_, status, child) => status.isEmpty
                    ? const SizedBox.shrink()
                    : ListTile(
                        leading: Icon(
                          status.startsWith('✓')
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          color: status.startsWith('✓')
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                        title: const Text('Last Status'),
                        subtitle: Text(
                          status,
                          style: TextStyle(
                            color: status.startsWith('✓')
                                ? Colors.greenAccent
                                : Colors.redAccent,
                          ),
                        ),
                      ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // ── Info ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Playback positions are saved automatically every few '
                    'seconds while you watch. When you re-open a file, it '
                    'will resume from where you left off.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(ThemeData theme, {required List<Widget> children}) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
