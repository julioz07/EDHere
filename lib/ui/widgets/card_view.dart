import 'package:card_db/card_db.dart' hide Card;
import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'mana.dart';

const double cardAspect = 488 / 680;

/// Imagem de uma carta, ou a "carta de texto" quando não há imagem offline.
/// As imagens nunca são cortadas nem alteradas (regras do Scryfall).
class CardImage extends ConsumerWidget {
  const CardImage(this.card, {super.key, this.face = 0, this.preferNormal = false, this.radius = 8});

  final db.Card card;
  final int face;
  final bool preferNormal;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final images = ref.watch(imagesProvider);
    final file = images.best(ImageRef.keyFor(card, face), preferNormal: preferNormal);
    return AspectRatio(
      aspectRatio: cardAspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: file == null
            ? TextCard(card, face: face)
            : Image.file(
                file,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => TextCard(card, face: face),
              ),
      ),
    );
  }
}

Color identityTint(int mask) {
  final letters = ManaColors.lettersOf(mask);
  if (letters.isEmpty) return ManaPalette.c;
  if (letters.length > 1) return const Color(0xFFD9C27A);
  return ManaPalette.of(letters.first);
}

/// Moldura genérica com nome, custo, tipo e texto Oracle.
class TextCard extends StatelessWidget {
  const TextCard(this.card, {super.key, this.face = 0});

  final db.Card card;
  final int face;

  @override
  Widget build(BuildContext context) {
    final f = card.faces.isNotEmpty ? card.faces[face.clamp(0, card.faces.length - 1)] : null;
    final name = f?.name ?? card.name;
    final cost = f?.manaCost ?? card.manaCost;
    final type = f?.typeLine ?? card.typeLine;
    final text = f?.oracleText ?? card.oracleText;
    final pow = f?.power ?? card.power;
    final tou = f?.toughness ?? card.toughness;
    final loy = f?.loyalty ?? card.loyalty;
    final tint = identityTint(card.colorMask == 0 ? card.identityMask : card.colorMask);

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final small = w < 120;
      final fs = (w / 16).clamp(5.0, 13.0);
      const dark = Color(0xFF1B1B1B);
      return Container(
        color: const Color(0xFF151515),
        padding: EdgeInsets.all(w * 0.035),
        child: Container(
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(w * 0.03),
          ),
          padding: EdgeInsets.all(w * 0.03),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _bar(
                  Row(children: [
                    Expanded(
                      child: Text(name,
                          maxLines: small ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: fs * 1.05, fontWeight: FontWeight.w700, color: dark)),
                    ),
                    if (!small) ManaCost(cost, size: fs * 1.1),
                  ]),
                  w),
              SizedBox(height: w * 0.02),
              Expanded(
                flex: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(w * 0.02),
                  ),
                  alignment: Alignment.center,
                  child: small
                      ? ManaCost(cost, size: fs * 1.4)
                      : Icon(Icons.image_not_supported_outlined, size: w * 0.14, color: Colors.black26),
                ),
              ),
              SizedBox(height: w * 0.02),
              if (!small)
                _bar(
                    Text(type,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: fs * 0.9, fontWeight: FontWeight.w600, color: dark)),
                    w),
              if (!small) SizedBox(height: w * 0.02),
              Expanded(
                flex: small ? 2 : 5,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F3EA),
                    borderRadius: BorderRadius.circular(w * 0.02),
                  ),
                  padding: EdgeInsets.all(w * 0.03),
                  child: small
                      ? Text(type,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: fs * 0.9, color: dark))
                      : SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: OracleText(text,
                              style: TextStyle(fontSize: fs * 0.85, color: dark, height: 1.25)),
                        ),
                ),
              ),
              if (pow != null || loy != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    margin: EdgeInsets.only(top: w * 0.02),
                    padding: EdgeInsets.symmetric(horizontal: w * 0.04, vertical: w * 0.005),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F3EA),
                      borderRadius: BorderRadius.circular(w * 0.03),
                    ),
                    child: Text(pow != null ? '$pow/$tou' : '◆ $loy',
                        style: TextStyle(fontSize: fs, fontWeight: FontWeight.w800, color: dark)),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _bar(Widget child, double w) => Container(
        padding: EdgeInsets.symmetric(horizontal: w * 0.03, vertical: w * 0.015),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F3EA),
          borderRadius: BorderRadius.circular(w * 0.03),
        ),
        child: child,
      );
}

/// Linha de lista com miniatura, nome, custo e tipo.
class CardTile extends StatelessWidget {
  const CardTile(this.card,
      {super.key, this.onTap, this.trailing, this.leadingQty, this.subtitle, this.thumbWidth = 56});

  final db.Card card;
  final VoidCallback? onTap;
  final Widget? trailing;
  final int? leadingQty;
  final String? subtitle;

  /// Largura da miniatura (as listas de deck usam maior).
  final double thumbWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            if (leadingQty != null)
              SizedBox(
                width: 28,
                child: Text('$leadingQty',
                    style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
              ),
            SizedBox(width: thumbWidth, child: CardImage(card, radius: thumbWidth * 0.06)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(card.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 6),
                    ManaCost(card.manaCost, size: thumbWidth > 60 ? 19 : 15),
                  ]),
                  Text(subtitle ?? card.typeLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
