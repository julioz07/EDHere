import 'package:card_db/card_db.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/resume_store.dart';
import '../game/solo_save.dart';
import 'app_paths.dart';
import 'card_data_service.dart';
import 'image_service.dart';
import 'print_service.dart';

/// Substituídos em `main()` depois de inicializados.
final pathsProvider = Provider<AppPaths>((_) => throw UnimplementedError());
final prefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError());
final deckStoreProvider = Provider<DeckStore>((_) => throw UnimplementedError());

final cardDataProvider =
    ChangeNotifierProvider<CardDataService>((ref) => CardDataService(ref.watch(pathsProvider)));

final imagesProvider = ChangeNotifierProvider<ImageService>((ref) => ImageService(ref.watch(pathsProvider)));

final printsProvider = ChangeNotifierProvider<PrintService>(
    (ref) => PrintService(ref.watch(deckStoreProvider), ref.read(imagesProvider)));

/// Base de cartas aberta, ou null enquanto não houver dados.
final cardRepoProvider = Provider<CardRepository?>((ref) => ref.watch(cardDataProvider).repo);

final decksProvider = ChangeNotifierProvider<DeckList>((ref) => DeckList(ref.watch(deckStoreProvider)));

/// Lista de decks do utilizador.
class DeckList extends ChangeNotifier {
  DeckList(this.store) : decks = store.listDecks();

  final DeckStore store;
  List<Deck> decks;

  Deck save(Deck d) {
    final saved = store.save(d);
    decks = store.listDecks();
    notifyListeners();
    return saved;
  }

  void delete(int id) {
    store.deleteDeck(id);
    decks = store.listDecks();
    notifyListeners();
  }

  /// Volta a ler da base (depois de importar um backup).
  void reload() {
    decks = store.listDecks();
    notifyListeners();
  }
}

/// Nome do jogador, guardado entre sessões.
final playerNameProvider =
    StateProvider<String>((ref) => ref.watch(prefsProvider).getString('player_name') ?? '');

/// Jogo em rede a que se pode voltar (se a app fechou a meio).
final resumeProvider = ChangeNotifierProvider<ResumeStore>((ref) => ResumeStore(ref.watch(prefsProvider)));

/// Jogo solo gravado para continuar depois.
final soloSaveProvider = ChangeNotifierProvider<SoloSaveStore>(
    (ref) => SoloSaveStore('${ref.watch(pathsProvider).root}/solo_game.json'));
