import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../l10n/l10n.dart';

/// A soma das mudanças de vida dos últimos segundos ("−7", "+3"), como nos
/// contadores de vida: com vários toques seguidos, ninguém conta de cabeça.
/// Apaga-se 2 s depois da última mudança.
class LifeDelta extends StatefulWidget {
  const LifeDelta({super.key, required this.life, this.fontSize = 13});

  final int life;
  final double fontSize;

  @override
  State<LifeDelta> createState() => _LifeDeltaState();
}

class _LifeDeltaState extends State<LifeDelta> {
  int _sum = 0;
  Timer? _clear;

  @override
  void didUpdateWidget(LifeDelta old) {
    super.didUpdateWidget(old);
    if (old.life == widget.life) return;
    _sum += widget.life - old.life;
    _clear?.cancel();
    _clear = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _sum = 0);
    });
  }

  @override
  void dispose() {
    _clear?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_sum == 0) return const SizedBox.shrink();
    return Text(
      _sum > 0 ? '+$_sum' : '−${-_sum}',
      style: TextStyle(
        fontSize: widget.fontSize,
        fontWeight: FontWeight.w800,
        color: _sum > 0 ? EdhColors.ok : EdhColors.bad,
      ),
    );
  }
}

/// Botão de − ou + da vida: um toque muda 1, manter premido muda 10.
class LifeStepButton extends StatelessWidget {
  const LifeStepButton({super.key, required this.up, required this.onChange});

  final bool up;
  final void Function(int delta) onChange;

  @override
  Widget build(BuildContext context) {
    final sign = up ? 1 : -1;
    return Tooltip(
      message: up ? tr('+1 (manter premido: +10)') : tr('−1 (manter premido: −10)'),
      child: InkResponse(
        radius: 22,
        onTap: () => onChange(sign),
        onLongPress: () => onChange(10 * sign),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(up ? Icons.add : Icons.remove),
        ),
      ),
    );
  }
}
