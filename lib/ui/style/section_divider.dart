import 'package:flutter/material.dart';

import '../../app/style_tokens.dart';

/// Título de secção. Encantado: ── COM OUTROS ── em Cinzel dourado.
class SectionDivider extends StatelessWidget {
  const SectionDivider(this.label, {super.key, required this.classic});

  final String label;
  final Widget classic;

  @override
  Widget build(BuildContext context) {
    final c = context.edhStyle;
    if (!c.isEnchanted) return classic;
    Widget line(bool toRight) => Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: toRight
                    ? [c.gold.withOpacity(0), c.gold.withOpacity(.6)]
                    : [c.gold.withOpacity(.6), c.gold.withOpacity(0)],
              ),
            ),
          ),
        );
    return Semantics(
      header: true,
      label: label,
      excludeSemantics: true,
      // O texto fica ao centro e pode ocupar até 80% da largura: um título
      // longo vai a duas linhas, não a cinco; os fios repartem o resto.
      child: LayoutBuilder(
        builder: (context, box) => Row(children: [
          line(true),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth * .8),
            child: Text(label.toUpperCase(),
                textAlign: TextAlign.center, style: EdhText.section.copyWith(color: c.goldText)),
          ),
          const SizedBox(width: 10),
          line(false),
        ]),
      ),
    );
  }
}
