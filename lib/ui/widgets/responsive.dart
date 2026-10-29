import 'package:flutter/widgets.dart';

/// A partir desta largura (dp), o ecrã é tratado como tablet.
const double wideBreakpoint = 840;

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= wideBreakpoint;

/// Centra o conteúdo e limita-lhe a largura, para formulários e listas não
/// esticarem a toda a largura de um tablet.
class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.child, this.max = 760});

  final Widget child;
  final double max;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child),
      );
}

/// Colunas de uma grelha de cartas com cerca de [target] dp de largura.
int cardColumns(double width, {double target = 180, int min = 3, int max = 10}) =>
    (width / target).floor().clamp(min, max);

/// Botões fixos no fundo do ecrã (em `Scaffold.bottomNavigationBar`): o que
/// se faz a seguir fica sempre à vista, mesmo quando o conteúdo pede scroll
/// num telemóvel pequeno.
class BottomActions extends StatelessWidget {
  const BottomActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              // 8 de espaço entre os botões: colados pareciam um só
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 8), children[i]],
              ]),
            ),
          ),
        ),
      );
}

/// Um rótulo de uma linha que encolhe a letra quando não cabe, em vez de partir
/// ("Sistem/a") ou cortar ("Aprender a joga…"). Para títulos e botões
/// segmentados, que num telemóvel pequeno com letra grande ficam sem espaço.
class FitText extends StatelessWidget {
  const FitText(this.text, {super.key, this.style, this.alignment = Alignment.center});

  final String text;
  final TextStyle? style;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: Text(text, maxLines: 1, style: style),
      );
}
