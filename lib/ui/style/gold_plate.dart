import 'package:flutter/material.dart';

import '../../app/style_tokens.dart';

BoxDecoration _plate(BuildContext context, EdhStyle c, double height) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(height * .22),
    gradient:
        LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.plateLight, c.goldLight]),
    border: Border.all(color: c.goldDeep),
    boxShadow: [
      BoxShadow(color: Colors.black.withOpacity(dark ? .5 : .2), blurRadius: 4, offset: const Offset(0, 2)),
    ],
  );
}

/// Número numa plaqueta dourada biselada (vida, contagens).
class GoldPlate extends StatelessWidget {
  const GoldPlate(
    this.text, {
    super.key,
    required this.classic,
    this.fontSize = 19,
    this.minWidth = 38,
    this.height = 34,
  });

  final String text;
  final Widget classic;
  final double fontSize, minWidth, height;

  @override
  Widget build(BuildContext context) {
    final c = context.edhStyle;
    if (!c.isEnchanted) return classic;
    return Container(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: _plate(context, c, height),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text,
            maxLines: 1, style: EdhText.plate.copyWith(fontSize: fontSize, color: c.textOnGold, height: 1)),
      ),
    );
  }
}

/// A plaqueta à volta de um widget que já existe (ex.: a vida animada da mesa
/// do bot). No Clássico devolve só o [child]; no Encantado o texto lá dentro
/// passa a escuro, sobre o ouro.
class GoldPlateFrame extends StatelessWidget {
  const GoldPlateFrame({super.key, required this.child, this.height = 32, this.minWidth = 40});

  final Widget child;
  final double height, minWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.edhStyle;
    if (!c.isEnchanted) return child;
    return Container(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: _plate(context, c, height),
      child: DefaultTextStyle.merge(style: TextStyle(color: c.textOnGold), child: child),
    );
  }
}
