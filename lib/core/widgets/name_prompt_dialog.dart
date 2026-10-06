import 'package:flutter/material.dart';

/// Asks for a single line of text, returning null if it is cancelled.
///
/// Used wherever the app creates something by name -- a playlist from the
/// library tab, or from the player's add-to-playlist sheet.
Future<String?> showNamePromptDialog(
  BuildContext context, {
  String title = 'New playlist',
  String hintText = 'Playlist name',
  String confirmLabel = 'Create',
  int? maxLength,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NamePromptDialog(
      title: title,
      hintText: hintText,
      confirmLabel: confirmLabel,
      maxLength: maxLength,
    ),
  );
}

/// The dialog behind [showNamePromptDialog].
///
/// It is a [StatefulWidget] rather than a function that builds an [AlertDialog]
/// because the text controller has to outlive the `showDialog` future: the route
/// keeps its widget tree while it animates out, so disposing the controller when
/// the future completes hands the still-mounted [TextField] a dead controller and
/// throws. Tying the controller to the element fixes it for both cases at once.
class _NamePromptDialog extends StatefulWidget {
  final String title;
  final String hintText;
  final String confirmLabel;
  final int? maxLength;

  const _NamePromptDialog({
    required this.title,
    required this.hintText,
    required this.confirmLabel,
    this.maxLength,
  });

  @override
  State<_NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<_NamePromptDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Closes with the trimmed name, or with nothing when it is blank.
  ///
  /// A blank name is treated as a cancellation so an empty playlist is never
  /// created by accident.
  void _submit() {
    final name = _controller.text.trim();
    Navigator.of(context).pop(name.isEmpty ? null : name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1B4B),
      title: Text(widget.title, style: const TextStyle(color: Colors.white)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: widget.maxLength,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: const TextStyle(color: Colors.white54),
          counterStyle: const TextStyle(color: Colors.white38),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}