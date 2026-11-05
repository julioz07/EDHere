import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// Um passo da visita à mesa: a parte do ecrã em destaque e o que se diz dela.
class TourStep {
  const TourStep(this.target, this.title, this.text);
  final GlobalKey target;
  final String title;
  final String text;
}

/// A visita à mesa na primeira vez: escurece o ecrã menos a parte de que se
/// fala, com um balão por cima ou por baixo. Saltar acaba logo.
class TableTour extends StatefulWidget {
  const TableTour({super.key, required this.steps, required this.onDone});
  final List<TourStep> steps;
  final VoidCallback onDone;

  @override
  State<TableTour> createState() => _TableTourState();
}

class _TableTourState extends State<TableTour> {
  int _i = 0;

  /// O retângulo do alvo, nas coordenadas da visita (null se não estiver no ecrã).
  Rect? _rect(BuildContext context) {
    final target = widget.steps[_i].target.currentContext?.findRenderObject();
    final me = context.findRenderObject();
    if (target is! RenderBox || me is! RenderBox || !target.hasSize || !target.attached) return null;
    final topLeft = me.globalToLocal(target.localToGlobal(Offset.zero));
    return (topLeft & target.size).inflate(4);
  }

  void _next() {
    if (_i < widget.steps.length - 1) {
      setState(() => _i++);
    } else {
      widget.onDone();
    }
  }

  @override
  void initState() {
    super.initState();
    // as posições só se sabem depois do primeiro desenho
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final step = widget.steps[_i];
    final last = _i == widget.steps.length - 1;
    return LayoutBuilder(builder: (context, box) {
      final rect = _rect(context);
      final h = box.maxHeight;
      // O balão vai para o lado do alvo com mais espaço; se nenhum chega (o
      // campo ocupa quase tudo), fica por cima do alvo, em baixo (o balão
      // num telemóvel tem perto de 280 de altura).
      final spaceBelow = rect == null ? h : h - rect.bottom - 12;
      final spaceAbove = rect == null ? 0.0 : rect.top - 12;
      final ({double top, double bottom, Alignment align}) place =
          rect == null || (spaceBelow < 280 && spaceAbove < 280)
              ? (top: 16, bottom: 16, align: Alignment.bottomCenter)
              : spaceBelow >= 280 && (spaceBelow >= spaceAbove || spaceAbove < 280)
                  ? (top: h - spaceBelow, bottom: 16, align: Alignment.topCenter)
                  : (top: 16, bottom: h - rect.top + 12, align: Alignment.bottomCenter);
      final bubble = Material(
        color: theme.colorScheme.surface,
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(step.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(step.text, style: theme.textTheme.bodyMedium),
            ),
            Row(children: [
              Text(tr('{i} de {n}', {'i': _i + 1, 'n': widget.steps.length}), style: theme.textTheme.labelMedium),
              const SizedBox(width: 8),
              // num ecrã estreito (ou com letra grande) os botões passam para baixo
              Expanded(
                child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    overflowAlignment: OverflowBarAlignment.end,
                    children: [
                      if (!last)
                        TextButton(
                            style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
                            onPressed: widget.onDone,
                            child: Text(tr('Saltar'))),
                      TextButton(
                          style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
                          onPressed: _next,
                          child: Text(last ? tr('Começar a jogar') : tr('Seguinte'))),
                    ]),
              ),
            ]),
          ]),
        ),
      );
      return Stack(children: [
        // o ecrã escurecido; tocar fora do balão passa ao passo seguinte
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _next,
            child: CustomPaint(painter: _Spotlight(rect)),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: place.top,
          bottom: place.bottom,
          child: Align(
            alignment: place.align,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              // com letra muito grande, o texto desliza em vez de sair do ecrã
              child: SingleChildScrollView(child: bubble),
            ),
          ),
        ),
      ]);
    });
  }
}

class _Spotlight extends CustomPainter {
  _Spotlight(this.hole);
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final all = Path()..addRect(Offset.zero & size);
    final path = hole == null
        ? all
        : Path.combine(
            PathOperation.difference, all, Path()..addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(12))));
    canvas.drawPath(path, Paint()..color = Colors.black.withOpacity(0.72));
    if (hole != null) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(hole!, const Radius.circular(12)),
          Paint()
            ..color = Colors.white70
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_Spotlight old) => old.hole != hole;
}
