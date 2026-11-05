import 'package:card_db/card_db.dart' hide Card;
import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/print_service.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import 'card_view.dart';

/// A ilustração de uma carta como fundo (capas de decks, lugares na sala, a
/// mesa). Usa o "art crop" do Scryfall, que é feito para isto (a imagem da
/// carta inteira nunca se corta). Enquanto não há ilustração, um degradê nas
/// cores do deck; o artista fica creditado num canto.
class ArtBanner extends ConsumerWidget {
  const ArtBanner({
    super.key,
    required this.art,
    this.identity = 0,
    this.artist,
    this.child,
    this.scrim = ArtScrim.left,
    this.credit = true,
    this.alignment = const Alignment(0, -0.2),
  });

  /// A partir de uma carta (a face da frente).
  ArtBanner.card(
    db.Card? card, {
    Key? key,
    int identity = 0,
    Widget? child,
    ArtScrim scrim = ArtScrim.left,
    bool credit = true,
    Alignment alignment = const Alignment(0, -0.2),
  }) : this(
          key: key,
          art: card == null ? null : ImageRef.allOf(card).firstOrNull,
          identity: identity == 0 && card != null ? card.identityMask : identity,
          artist: card == null ? null : (card.faces.isNotEmpty ? card.faces.first.artist : null) ?? card.artist,
          child: child,
          scrim: scrim,
          credit: credit,
          alignment: alignment,
        );

  final ImageRef? art;

  /// Cores do deck (máscara WUBRG) para o fundo enquanto não há ilustração.
  final int identity;
  final String? artist;
  final Widget? child;
  final ArtScrim scrim;
  final bool credit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final images = ref.watch(imagesProvider);
    final file = art == null ? null : images.art(art!);
    final tint = identityTint(identity);
    return Stack(fit: StackFit.expand, children: [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(tint, Colors.black, 0.35)!, Color.lerp(tint, Colors.black, 0.75)!],
          ),
        ),
      ),
      if (file != null)
        Image.file(file,
            fit: BoxFit.cover,
            alignment: alignment,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
      // o texto por cima tem de se ler em qualquer ilustração
      DecoratedBox(decoration: BoxDecoration(gradient: scrim.gradient)),
      if (credit && file != null && artist != null)
        Positioned(
          right: 6,
          bottom: 3,
          child: Text(tr('Arte: {v}', {'v': artist}),
              style: const TextStyle(fontSize: 9, color: Colors.white70, shadows: [Shadow(blurRadius: 3)])),
        ),
      if (child != null) child!,
    ]);
  }
}

/// Onde fica o escuro por cima da ilustração (do lado do texto).
enum ArtScrim {
  left,
  bottom,
  full;

  Gradient get gradient => switch (this) {
        ArtScrim.left => const LinearGradient(colors: [Color(0xE6000000), Color(0x99000000), Color(0x22000000)]),
        ArtScrim.bottom => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x11000000), Color(0x55000000), Color(0xE0000000)]),
        ArtScrim.full => const LinearGradient(colors: [Color(0xB3000000), Color(0xB3000000)]),
      };
}

/// A capa de um deck: o comandante ou, sem comandante (Modern, limitado…), a
/// criatura mais cara, ou o feitiço mais caro; com as cores do deck.
({db.Card? cover, List<db.Card> commanders, int identity}) deckCover(
    Deck d, CardRepository? repo, PrintService prints) {
  final cmdIds = d.inBoard(Board.command).map((e) => e.oracleId).toList();
  final cmds = repo?.getMany(cmdIds).values.toList() ?? const <db.Card>[];
  final mainCards = cmds.isNotEmpty
      ? const <db.Card>[]
      : (repo?.getMany(d.inBoard(Board.main).map((e) => e.oracleId).toList()).values ?? const <db.Card>[])
          .where((c) => !c.isLand)
          .toList();
  db.Card? best(bool Function(db.Card) ok) =>
      mainCards.where(ok).fold<db.Card?>(null, (b, c) => b == null || c.mv > b.mv ? c : b);
  final cover = cmds.isNotEmpty ? cmds.first : best((c) => c.frontType.contains('Creature')) ?? best((_) => true);
  final identity =
      (cmds.isNotEmpty ? cmds : mainCards).fold(0, (m, c) => m | (cmds.isNotEmpty ? c.identityMask : c.colorMask));
  return (
    // a versão escolhida no deck (a sua ilustração)
    cover: cover == null
        ? null
        : prints.resolve(cover, printId: d.entries.firstWhere((e) => e.oracleId == cover.oracleId).printId),
    commanders: cmds,
    identity: identity,
  );
}
