import 'package:card_db/card_db.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// As minhas cartas: quantidades indicativas, sem gestão de inventário.
class Collection extends ChangeNotifier {
  Collection(this.store) : _owned = store.collection();

  final DeckStore store;
  Map<String, int> _owned;

  Map<String, int> get owned => _owned;
  int ownedOf(String oracleId) => _owned[oracleId] ?? 0;
  bool get isEmpty => _owned.isEmpty;

  void set(String oracleId, int qty) {
    store.setOwned(oracleId, qty);
    reload();
  }

  void change(String oracleId, int delta) => set(oracleId, ownedOf(oracleId) + delta);

  /// Junta várias cartas. Com [atLeast] não soma: garante pelo menos essa
  /// quantidade (para "tenho este deck físico").
  void addAll(Map<String, int> cards, {bool atLeast = false}) {
    store.addOwned(cards, atLeast: atLeast);
    reload();
  }

  /// Volta a ler da base (depois de importar um backup).
  void reload() {
    _owned = store.collection();
    notifyListeners();
  }
}

final collectionProvider =
    ChangeNotifierProvider<Collection>((ref) => Collection(ref.watch(deckStoreProvider)));
