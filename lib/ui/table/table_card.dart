import 'dart:math';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart' hide Table, Intent;
import 'package:mesa_core/mesa_core.dart';

import '../../data/settings.dart';
import '../widgets/card_view.dart';
import '../widgets/mana.dart';

/// Cor do brilho dos alvos (como no exemplo de referência).
const targetGlow = Color(0xFFFF5A7A);

/// Verso de carta do EDHere (sem o verso oficial). Com [label], mostra uma
/// etiqueta por cima (por exemplo "Virada" numa carta face para baixo).
class CardBack extends StatelessWidget {
  const CardBack({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: cardAspect,
      child: LayoutBuilder(builder: (context, c) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(c.maxWidth * 0.05),
          child: Stack(fit: StackFit.expand, children: [
            Image.asset(Brand.cardBack, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
            if (label != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: FittedBox(
                    child: Text(label!,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ]),
        );
      }),
    );
  }
}

/// Poder/resistência finais de uma carta no campo, ou null se não tiver.
(String, bool)? effectivePt(CardInstance c, db.Card? card) {
  String? basePow;
  String? baseTou;
  if (card == null) {
    final pt = c.tokenPt?.split('/');
    if (pt != null && pt.length == 2) {
      basePow = pt[0];
      baseTou = pt[1];
    }
  } else if (card.faces.isNotEmpty && card.faces.length > c.faceIndex) {
    basePow = card.faces[c.faceIndex].power ?? card.power;
    baseTou = card.faces[c.faceIndex].toughness ?? card.toughness;
  } else {
    basePow = card.power;
    baseTou = card.toughness;
  }
  if (basePow == null || baseTou == null) return null;
  final plus = c.counters[CounterKind.plus] ?? 0;
  final minus = c.counters[CounterKind.minus] ?? 0;
  final dp = plus - minus + (c.counters[CounterKind.modPower] ?? 0);
  final dt = plus - minus + (c.counters[CounterKind.modToughness] ?? 0);
  if (dp == 0 && dt == 0) return ('$basePow/$baseTou', false);
  String add(String base, int d) {
    final n = int.tryParse(base);
    return n == null ? '$base${d >= 0 ? '+' : ''}$d' : '${n + d}';
  }

  return ('${add(basePow, dp)}/${add(baseTou, dt)}', true);
}

/// Uma carta numa zona pública da mesa.
class TableCardView extends StatelessWidget {
  const TableCardView({
    super.key,
    required this.instance,
    required this.card,
    required this.width,
    this.highlighted = false,
    this.targeted = false,
    this.targeting = false,
    this.showTapped = true,
    this.showDetails = true,
    this.tax,
  });

  final CardInstance instance;
  final db.Card? card;
  final double width;
  final bool highlighted;

  /// Alguém apontou para esta carta.
  final bool targeted;

  /// Esta carta está a apontar para algo.
  final bool targeting;
  final bool showTapped;

  /// Contadores, habilidades e P/R por cima da carta (no campo).
  final bool showDetails;

  /// Taxa de comandante a mostrar na zona de comando.
  final int? tax;

  @override
  Widget build(BuildContext context) {
    final c = instance;
    final scheme = Theme.of(context).colorScheme;
    Widget face;
    if (c.faceDown) {
      face = const CardBack(label: 'Virada');
    } else if (card == null) {
      face = _TokenFace(name: c.tokenName ?? 'Token', pt: c.tokenPt);
    } else {
      face = CardImage(card!, face: c.faceIndex, radius: width * 0.05);
    }

    final iconSize = (width * 0.16).clamp(10.0, 18.0);
    final counters = <Widget>[
      for (final e in c.counters.entries)
        if (!e.key.startsWith('mod:') && !e.key.startsWith(CounterKind.keyword))
          _CounterBadge(kind: e.key, value: e.value, size: iconSize),
      if (c.stackQty > 1) _Badge('×${c.stackQty}', scheme.primary, iconSize),
      if (tax != null && tax! > 0) _Badge('+$tax', Colors.orange, iconSize),
    ];

    // Habilidades: as dadas por efeitos (destacadas) e as da própria carta.
    final granted = [
      for (final k in c.counters.keys)
        if (k.startsWith(CounterKind.keyword)) k.substring(CounterKind.keyword.length),
    ];
    final own = c.faceDown ? const <String>[] : (card?.keywords ?? const <String>[]);
    final abilityIcons = <(String, bool)>[
      for (final k in granted)
        if (abilityIconFor(k) case final i?) (i, true),
      for (final k in own)
        if (!granted.contains(k))
          if (abilityIconFor(k) case final i?) (i, false),
    ].take(6).toList();

    final pt = c.faceDown ? null : effectivePt(c, card);

    final glow = targeted
        ? BoxShadow(color: targetGlow.withOpacity(0.9), blurRadius: 14, spreadRadius: 4)
        : highlighted
            ? BoxShadow(color: scheme.primary, blurRadius: 10, spreadRadius: 3)
            : const BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1));

    Widget body = SizedBox(
      width: width,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(width * 0.06),
            boxShadow: [glow],
          ),
          child: face,
        ),
        if (c.isCommander)
          Positioned(
            top: -4,
            left: -4,
            child: Icon(Icons.star_rounded, size: width * 0.22, color: Colors.amber),
          ),
        if (showDetails && abilityIcons.isNotEmpty)
          Positioned(
            top: width * 0.16,
            right: -2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (icon, isGranted) in abilityIcons)
                  Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isGranted ? scheme.primary : Colors.black.withOpacity(0.65),
                      shape: BoxShape.circle,
                    ),
                    child: ManaIcon(icon, size: iconSize * 0.9, color: Colors.white),
                  ),
              ],
            ),
          ),
        if (showDetails && counters.isNotEmpty)
          Positioned(
            bottom: width * 0.2,
            left: 2,
            right: 2,
            child: Wrap(spacing: 2, runSpacing: 2, children: counters),
          ),
        if (showDetails && pt != null && (pt.$2 || width < 70))
          Positioned(
            bottom: 2,
            right: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: pt.$2 ? scheme.primary : Colors.black87,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(pt.$1,
                  style:
                      TextStyle(color: Colors.white, fontSize: iconSize * 0.9, fontWeight: FontWeight.w800)),
            ),
          ),
        if (targeted)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: targetGlow, shape: BoxShape.circle),
                  child: Icon(Icons.gps_fixed, color: Colors.white, size: width * 0.28),
                ),
              ),
            ),
          ),
        if (targeting)
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(color: targetGlow, shape: BoxShape.circle),
              child: Icon(Icons.call_made, color: Colors.white, size: iconSize),
            ),
          ),
      ]),
    );
    if (showTapped && c.tapped) {
      body = Transform.rotate(angle: pi / 2, child: Opacity(opacity: 0.92, child: body));
    }
    return body;
  }
}

class _CounterBadge extends StatelessWidget {
  const _CounterBadge({required this.kind, required this.value, required this.size});
  final String kind;
  final int value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = counterIconFor(kind);
    final label = switch (kind) {
      CounterKind.plus => '+$value',
      CounterKind.minus => '-$value',
      _ => '$value',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(color: _color(kind), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ManaIcon(icon, size: size * 0.85, color: Colors.white),
        if (icon == null)
          Text('${kind.length > 6 ? kind.substring(0, 6) : kind} ',
              style: TextStyle(color: Colors.white, fontSize: size * 0.7)),
        const SizedBox(width: 2),
        Text(label,
            style: TextStyle(color: Colors.white, fontSize: size * 0.85, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  static Color _color(String kind) => switch (kind) {
        CounterKind.plus => const Color(0xFF2E9E5B),
        CounterKind.minus => const Color(0xFFC0392B),
        CounterKind.loyalty => const Color(0xFF6C4BB6),
        _ => const Color(0xFF455A64),
      };
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color, this.size);
  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Text(text,
            style: TextStyle(color: Colors.white, fontSize: size * 0.85, fontWeight: FontWeight.w800)),
      );
}

class _TokenFace extends StatelessWidget {
  const _TokenFace({required this.name, this.pt});
  final String name;
  final String? pt;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: cardAspect,
        child: LayoutBuilder(
          builder: (context, c) => Container(
            decoration: BoxDecoration(
              color: const Color(0xFFE9E4D8),
              borderRadius: BorderRadius.circular(c.maxWidth * 0.06),
              border: Border.all(color: Colors.black54, width: 2),
            ),
            padding: EdgeInsets.all(c.maxWidth * 0.06),
            child: Column(children: [
              Text(name,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: c.maxWidth * 0.12, fontWeight: FontWeight.w700, color: Colors.black87)),
              const Spacer(),
              Text('Token', style: TextStyle(fontSize: c.maxWidth * 0.09, color: Colors.black54)),
              if (pt != null)
                Text(pt!,
                    style: TextStyle(
                        fontSize: c.maxWidth * 0.14, fontWeight: FontWeight.w800, color: Colors.black87)),
            ]),
          ),
        ),
      );
}
