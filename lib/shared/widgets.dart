import 'package:flutter/material.dart';
import '../theme.dart';

class StartButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;
  const StartButton({super.key, required this.onPressed, this.label='START'});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.charcoal),
        child: Text(label, style: const TextStyle(fontSize: 16, letterSpacing: 1.2)),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const SectionHeader({super.key, required this.title, this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      if(subtitle!=null) ...[const SizedBox(height:4), Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium)],
    ]);
  }
}

class EmptyState extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({super.key, required this.message, this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        const Icon(Icons.wb_sunny_outlined, size: 48, color: AppTheme.mutedGrey),
        const SizedBox(height:16),
        Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
        if(actionLabel!=null) ...[const SizedBox(height:16), TextButton(onPressed: onAction, child: Text(actionLabel!))],
      ]),
    );
  }
}
