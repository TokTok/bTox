import 'package:flutter/material.dart';

final class AttachmentButton extends StatelessWidget {
  final IconData icon;
  final String text;
  final void Function()? onPressed;

  const AttachmentButton({
    super.key,
    required this.icon,
    required this.text,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton(icon: Icon(icon, size: 56), onPressed: onPressed),
        Text(text),
      ],
    );
  }
}
