import 'package:flutter/material.dart';

/// Linha "continuar isto" (jogo gravado, pool por montar...): ícone, título,
/// subtítulo e os botões. Com espaço, os botões ficam à direita; num ecrã
/// estreito vão para baixo, para não espremerem o texto.
class ResumeTile extends StatelessWidget {
  const ResumeTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    this.onDelete,
    this.deleteTooltip,
    this.onLongPress,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback? onDelete;
  final String? deleteTooltip;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
      onPressed: onAction,
      child: Text(actionLabel),
    );
    final delete = onDelete == null
        ? null
        : IconButton(tooltip: deleteTooltip, icon: const Icon(Icons.delete_outline), onPressed: onDelete);
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 440) {
        return ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [if (delete != null) delete, button]),
          onLongPress: onLongPress,
        );
      }
      final theme = Theme.of(context);
      return InkWell(
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2, right: 16), child: Icon(icon)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  Text(subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ),
            ]),
            Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [if (delete != null) delete, const SizedBox(width: 4), button]),
          ]),
        ),
      );
    });
  }
}
