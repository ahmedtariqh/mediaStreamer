import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _resumePlayback = true;
  bool _showResumeOnStartup = true;
  int _historyCount = 0;

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
    });
  }

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
