import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';

final class ChatContextMenu {
  static Future<void> show(
    BuildContext context,
    Offset position, {
    required void Function() onReply,
    required void Function() onForward,
    required void Function() onCopy,
    required void Function() onSelect,
    required void Function() onInfo,
    required void Function() onDelete,
  }) {
    final menu = _build(
      position,
      onReply: onReply,
      onForward: onForward,
      onCopy: onCopy,
      onSelect: onSelect,
      onInfo: onInfo,
      onDelete: onDelete,
    );

    return menu.show(context);
  }

  static ContextMenu _build(
    Offset position, {
    required void Function() onReply,
    required void Function() onForward,
    required void Function() onCopy,
    required void Function() onSelect,
    required void Function() onInfo,
    required void Function() onDelete,
  }) {
    final entries = [
      MenuItem(
        label: const Text('Reply'),
        icon: const Icon(Icons.reply_outlined),
        onSelected: (_) => onReply(),
      ),
      MenuItem(
        label: const Text('Forward'),
        icon: const Icon(Icons.forward_outlined),
        onSelected: (_) => onForward(),
      ),
      MenuItem(
        label: const Text('Copy'),
        icon: const Icon(Icons.copy),
        onSelected: (_) => onCopy(),
      ),
      MenuItem(
        label: const Text('Select'),
        icon: const Icon(Icons.check_circle_outline),
        onSelected: (_) => onSelect(),
      ),
      MenuItem(
        label: const Text('Info'),
        icon: const Icon(Icons.info_outline),
        onSelected: (_) => onInfo(),
      ),
      MenuItem(
        label: const Text('Delete'),
        icon: const Icon(Icons.delete_outline),
        onSelected: (_) => onDelete(),
      ),
    ];

    return ContextMenu(
      entries: entries,
      position: position,
      padding: const EdgeInsets.all(8.0),
    );
  }
}
