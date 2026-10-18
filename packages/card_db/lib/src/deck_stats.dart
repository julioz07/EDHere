import 'dart:math' as math;

import 'card.dart';
import 'deck.dart';
import 'mana.dart';

/// Probabilidade de ter pelo menos [atLeast] cartas de um grupo de
/// [successes] ao comprar [draws] cartas de um baralho de [population].
double probabilityAtLeast(int population, int successes, int draws, int atLeast) {
  if (atLeast <= 0) return 1;
  if (draws > population) draws = population;
  double logChoose(int n, int k) {
    if (k < 0 || k > n) return double.negativeInfinity;
    var r = 0.0;
    for (var i = 1; i <= k; i++) {
      r += _ln(n - k + i) - _ln(i);
    }
    return r;
  }

  final total = logChoose(population, draws);
  var p = 0.0;
  for (var k = atLeast; k <= draws && k <= successes; k++) {
    final lp = logChoose(successes, k) + logChoose(population - successes, draws - k) - total;
    if (lp.isFinite) p += _exp(lp);
  }
  return p.clamp(0, 1).toDouble();
}

double _ln(int x) => math.log(x);
double _exp(double x) => math.exp(x);

/// Estatísticas do deck (principal + zona de comando).
class DeckStats {
  DeckStats._();

  /// Cartas não-terreno por valor de mana; o índice 7 junta 7 ou mais.
  final List<int> curve = List.filled(8, 0);

  /// Símbolos de mana de cada cor nos custos.
  final Map<String, int> pips = {};

  /// Terrenos (e outras fontes) que produzem cada cor.
  final Map<String, int> sources = {};
  final Map<String, int> types = {};
  int lands = 0;
  int nonLands = 0;
  double averageMv = 0;

  static const typeOrder = [
    'Creature', 'Instant', 'Sorcery', 'Artifact', 'Enchantment',
    'Planeswalker', 'Battle', 'Land',
  ];

  static DeckStats of(Deck deck, Map<String, Card> cards) {
    final s = DeckStats._();
    var mvSum = 0.0;
    for (final e in deck.entries) {
      if (e.board != Board.main && e.board != Board.command) continue;
      final c = cards[e.oracleId];
      if (c == null) continue;
      final type = c.frontType;
      for (final t in typeOrder) {
        if (type.contains(t)) {
          s.types[t] = (s.types[t] ?? 0) + e.qty;
          break;
        }
      }
      if (c.isLand) {
        s.lands += e.qty;
        for (final m in c.producedMana) {
          if ('WUBRG'.contains(m)) s.sources[m] = (s.sources[m] ?? 0) + e.qty;
        }
        continue;
      }
      s.nonLands += e.qty;
      mvSum += c.mv * e.qty;
      s.curve[c.mv.clamp(0, 7).toInt()] += e.qty;
      final cost = c.faces.isNotEmpty ? c.faces.first.manaCost : c.manaCost;
      colorPips(cost).forEach((k, v) => s.pips[k] = (s.pips[k] ?? 0) + v * e.qty);
    }
    s.averageMv = s.nonLands == 0 ? 0 : mvSum / s.nonLands;
    return s;
  }
}
