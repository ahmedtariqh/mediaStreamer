import 'package:flutter/material.dart';
import 'stream_screen.dart';
import 'receiver_screen.dart';
import 'notes_screen.dart';
import 'settings_screen.dart';
import 'browser_screen.dart';

class MoreScreen extends StatelessWidget {
  final void Function(String url)? onUrlDetected;

  const MoreScreen({super.key, this.onUrlDetected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildOptionCard(
              context,
              theme,
              icon: Icons.cast,
              title: 'Stream',
              subtitle: 'Stream videos to other devices',
              gradient: [
                theme.colorScheme.primary.withValues(alpha: 0.2),
                theme.colorScheme.secondary.withValues(alpha: 0.1),
              ],
              iconColor: theme.colorScheme.primary,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StreamScreen()),
              ),
            ),
            const SizedBox(height: 12),
            _buildOptionCard(
              context,
              theme,
              icon: Icons.download_for_offline,
              title: 'Receive',
              subtitle: 'Receive streams from other devices',
              gradient: [
                theme.colorScheme.secondary.withValues(alpha: 0.2),
                theme.colorScheme.primary.withValues(alpha: 0.1),
              ],
              iconColor: theme.colorScheme.secondary,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReceiverScreen()),
              ),
            ),
            const SizedBox(height: 12),
            _buildOptionCard(
              context,
              theme,
              icon: Icons.note,
              title: 'Video Notes',
              subtitle: 'Notes saved after watching videos',
              gradient: [
                Colors.amber.withValues(alpha: 0.15),
                Colors.orange.withValues(alpha: 0.08),
              ],
              iconColor: Colors.amber,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotesScreen()),
              ),
            ),
            const SizedBox(height: 12),
            _buildOptionCard(
              context,
              theme,
              icon: Icons.language,
              title: 'Web Browser',
              subtitle: 'Browse with ad/popup protection and detect videos',
              gradient: [
                Colors.purple.withValues(alpha: 0.15),
                Colors.deepPurple.withValues(alpha: 0.08),
              ],
              iconColor: Colors.purpleAccent,
              onTap: () async {
                final url = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(builder: (_) => const BrowserScreen()),
                );
                if (url != null && onUrlDetected != null) {
                  onUrlDetected!(url);
                }
              },
            ),
            const SizedBox(height: 12),
            _buildOptionCard(
              context,
              theme,
              icon: Icons.settings,
              title: 'Settings',
              subtitle: 'Resume playback, history & preferences',
              gradient: [
                Colors.blueGrey.withValues(alpha: 0.15),
                Colors.grey.withValues(alpha: 0.08),
              ],
              iconColor: Colors.blueGrey,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradient,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
