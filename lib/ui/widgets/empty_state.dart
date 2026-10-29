import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// O ecrã quando ainda não há nada (decks, cartas, jogos): um ícone, o que
/// falta, uma linha a explicar e o que fazer a seguir. Faz scroll e não estica
/// num tablet, para o botão nunca ficar fora do ecrã num telemóvel pequeno.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.actions = const []});

  final IconData icon;
  final String title;
  final String? body;

  /// Os botões, do principal para o secundário.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(EdhSize.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(icon, size: 44, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: EdhSize.l),
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: EdhSize.s),
              Text(body!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            for (var i = 0; i < actions.length; i++) ...[
              SizedBox(height: i == 0 ? EdhSize.xl : EdhSize.s),
              actions[i],
            ],
          ]),
        ),
      ),
    );
  }
}
