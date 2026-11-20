import 'dart:math' as math;

import 'package:flutter/material.dart';

/// O rebordo das molduras do Encantado, como o de uma carta: fio de ouro,
/// intervalo escuro e um segundo fio de ouro a 20% por dentro.
class GoldFrameBorder extends OutlinedBorder {
  const GoldFrameBorder({
    required this.gold,
    this.radius = 14,
    this.highlighted = false,
    super.side = BorderSide.none,
  });

  final Color gold;
  final double radius;

  /// Item ativo ou do próprio jogador: fio mais forte.
  final bool highlighted;

  static const _gap = 3.0;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(1);

  RRect _rrect(Rect rect, [double inset = 0]) =>
      RRect.fromRectAndRadius(rect.deflate(inset), Radius.circular(math.max(0, radius - inset)));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(_rrect(rect, 1));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(_rrect(rect));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = highlighted ? 1.5 : 1
      ..color = gold.withOpacity(highlighted ? .95 : .7);
    canvas.drawRRect(_rrect(rect, .5), outer);
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = gold.withOpacity(highlighted ? .35 : .2);
    canvas.drawRRect(_rrect(rect, _gap + .5), inner);
  }

  @override
  GoldFrameBorder copyWith({BorderSide? side, Color? gold, double? radius, bool? highlighted}) => GoldFrameBorder(
        gold: gold ?? this.gold,
        radius: radius ?? this.radius,
        highlighted: highlighted ?? this.highlighted,
        side: side ?? this.side,
      );

  @override
  ShapeBorder scale(double t) => copyWith(radius: radius * t);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) =>
      a is GoldFrameBorder ? copyWith(gold: Color.lerp(a.gold, gold, t), radius: lerpDouble(a.radius, radius, t)) : null;

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) =>
      b is GoldFrameBorder ? copyWith(gold: Color.lerp(gold, b.gold, t), radius: lerpDouble(radius, b.radius, t)) : null;

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;

  @override
  bool operator ==(Object other) =>
      other is GoldFrameBorder &&
      other.gold == gold &&
      other.radius == radius &&
      other.highlighted == highlighted &&
      other.side == side;

  @override
  int get hashCode => Object.hash(gold, radius, highlighted, side);
}
