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
              child: Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ),
      );
}
