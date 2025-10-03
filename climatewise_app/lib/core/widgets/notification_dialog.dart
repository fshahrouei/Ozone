// lib/core/widgets/notification_dialog.dart
import 'package:flutter/material.dart';
import '../../core/services/push_navigation_service.dart';
import '../../core/tts/tts_service.dart'; // TTS

/// Reusable dialog to present a tapped push message inside MainNavigation.
/// - Speaks title + body on open (configurable)
/// - Shows title/body clearly
/// - Optionally lists payload "data" keys for debugging/advanced UX
/// - Provides a single primary action (Close by default)
///
/// Usage:
///   await showNotificationDialog(context, pushMessage);
///
/// If you ever want to add an extra CTA (e.g., "Open details"),
/// pass [primaryActionLabel] and [onPrimaryAction].
Future<void> showNotificationDialog(
  BuildContext context,
  PushMessage message, {
  String primaryActionLabel = 'Close',
  VoidCallback? onPrimaryAction,

  /// If true, TTS will speak on open.
  bool speakOnOpen = true,

  /// If true, any ongoing speech will be stopped before speaking.
  bool interruptSpeech = true,

  /// If true, speak the title before the body. If body is empty, speak title only.
  bool includeTitleOnSpeak = true,
}) async {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => NotificationDialog(
      message: message,
      primaryActionLabel: primaryActionLabel,
      onPrimaryAction: onPrimaryAction,
      speakOnOpen: speakOnOpen,
      interruptSpeech: interruptSpeech,
      includeTitleOnSpeak: includeTitleOnSpeak,
    ),
  );
}

class NotificationDialog extends StatefulWidget {
  final PushMessage message;
  final String primaryActionLabel;
  final VoidCallback? onPrimaryAction;

  final bool speakOnOpen;
  final bool interruptSpeech;
  final bool includeTitleOnSpeak;

  const NotificationDialog({
    super.key,
    required this.message,
    this.primaryActionLabel = 'Close',
    this.onPrimaryAction,
    this.speakOnOpen = true,
    this.interruptSpeech = true,
    this.includeTitleOnSpeak = true,
  });

  @override
  State<NotificationDialog> createState() => _NotificationDialogState();
}

class _NotificationDialogState extends State<NotificationDialog> {
  late final String _title;
  late final String _body;
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();

    // Normalize title/body once
    final title = widget.message.title?.trim().isNotEmpty == true
        ? widget.message.title!.trim()
        : 'Notification';

    final body = (widget.message.body?.trim().isNotEmpty == true)
        ? widget.message.body!.trim()
        : (widget.message.data['body']?.toString().trim() ?? '');

    _title = title;
    _body = body;

    // Auto-speak on open (if enabled and we have something to say)
    if (widget.speakOnOpen && (_title.isNotEmpty || _body.isNotEmpty)) {
      _speakMessage();
    }
  }

  String _composeSpeechText() {
    // Prefer speaking both: "Title. Body"
    if (widget.includeTitleOnSpeak) {
      if (_title.isNotEmpty && _body.isNotEmpty) {
        return '$_title. $_body';
      }
      if (_title.isNotEmpty) return _title;
      return _body; // title empty, body available
    } else {
      // Only body (fallback to title if body empty)
      return _body.isNotEmpty ? _body : _title;
    }
  }

  Future<void> _speakMessage() async {
    final text = _composeSpeechText().trim();
    if (text.isEmpty) return;

    setState(() => _isSpeaking = true);
    try {
      await TtsService.instance.speak(text, interrupt: widget.interruptSpeech);
    } finally {
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  Future<void> _stopSpeaking() async {
    await TtsService.instance.stop();
    if (mounted) setState(() => _isSpeaking = false);
  }

  @override
  void dispose() {
    // Stop TTS when dialog is dismissed to avoid lingering speech
    TtsService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.notifications_active),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _title,
              style: theme.textTheme.titleLarge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Small TTS control: replay or stop
          IconButton(
            tooltip: _isSpeaking ? 'Stop voice' : 'Play voice',
            onPressed: () {
              if (_isSpeaking) {
                _stopSpeaking();
              } else {
                _speakMessage();
              }
            },
            icon: Icon(_isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_body.isNotEmpty)
                Text(
                  _body,
                  style: theme.textTheme.bodyLarge,
                ),
              if (_body.isEmpty)
                Text(
                  'No message body.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              const SizedBox(height: 16),

              // Optional payload details (collapsible)
              if (widget.message.data.isNotEmpty) _PayloadSection(data: widget.message.data),

              // Timestamp / source (tiny meta)
              const SizedBox(height: 12),
              _MetaRow(message: widget.message),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _stopSpeaking();
            Navigator.of(context).maybePop();
          },
          child: const Text('Dismiss'),
        ),
        FilledButton(
          onPressed: () {
            if (widget.onPrimaryAction != null) {
              widget.onPrimaryAction!();
            }
            _stopSpeaking();
            Navigator.of(context).maybePop();
          },
          child: Text(widget.primaryActionLabel),
        ),
      ],
    );
  }
}

class _PayloadSection extends StatefulWidget {
  final Map<String, dynamic> data;
  const _PayloadSection({required this.data});

  @override
  State<_PayloadSection> createState() => _PayloadSectionState();
}

class _PayloadSectionState extends State<_PayloadSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        onExpansionChanged: (v) => setState(() => _expanded = v),
        leading: const Icon(Icons.dataset_outlined),
        title: Text(
          'Additional data',
          style: theme.textTheme.titleMedium,
        ),
        subtitle: !_expanded
            ? Text(
                'Tap to view payload details',
                style: theme.textTheme.bodySmall,
              )
            : null,
        children: [
          const SizedBox(height: 4),
          ...widget.data.entries.map(
            (e) => _DataRowItem(k: e.key, v: e.value),
          ),
        ],
      ),
    );
  }
}

class _DataRowItem extends StatelessWidget {
  final String k;
  final dynamic v;
  const _DataRowItem({required this.k, required this.v});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(width: 0.3, color: Color(0x1F000000)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$k: ',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              _stringify(v),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  static String _stringify(dynamic v) {
    if (v is Map || v is List) return v.toString();
    return v?.toString() ?? '';
  }
}

class _MetaRow extends StatelessWidget {
  final PushMessage message;
  const _MetaRow({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ts = message.receivedAt.toLocal().toString(); // you can format later
    final source = message.source.name;

    return Row(
      children: [
        Icon(Icons.schedule, size: 16, color: theme.hintColor),
        const SizedBox(width: 6),
        Text(
          ts,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(width: 12),
        Icon(Icons.source, size: 16, color: theme.hintColor),
        const SizedBox(width: 6),
        Text(
          source,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
    );
  }
}
