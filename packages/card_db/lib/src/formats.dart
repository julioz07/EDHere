/// Que tipo de cartas vão para a zona de comando num formato.
enum CommandZone { none, commander, oathbreaker }

/// Regras de construção de deck e valores iniciais de cada formato.
/// A mesa é igual para todos; isto só muda a validação e a sala.
class GameFormat {
  const GameFormat({
    required this.id,
    required this.label,
    this.legalityKey,
    required this.startingLife,
    this.multiplayerLife,
    this.minDeck,
    this.exactDeck,
    this.maxCopies = 4,
    this.maxSideboard,
    this.commandZone = CommandZone.none,
    this.commanderMayBePlaneswalker = false,
  });

  final String id;
  final String label;

  /// Chave de legalidade no Scryfall; null = sem verificação de banidas.
  final String? legalityKey;
  final int startingLife;
  final int? multiplayerLife;

  /// Mínimo de cartas no deck principal (formatos construídos).
  final int? minDeck;

  /// Tamanho exato do deck, contando a zona de comando (singleton).
  final int? exactDeck;
  final int maxCopies;
  final int? maxSideboard;
  final CommandZone commandZone;
  final bool commanderMayBePlaneswalker;

  bool get isSingleton => maxCopies == 1;
  bool get hasCommandZone => commandZone != CommandZone.none;
  bool get validates => id != 'free' && id != 'cube';

  /// Decks que vêm de boosters (sealed, draft, JumpStart).
  bool get isLimited => id == 'limited';

  static const commander = GameFormat(
    id: 'commander', label: 'Commander', legalityKey: 'commander',
    startingLife: 40, exactDeck: 100, maxCopies: 1,
    commandZone: CommandZone.commander,
  );
  static const brawl = GameFormat(
    id: 'brawl', label: 'Brawl', legalityKey: 'brawl',
    startingLife: 25, multiplayerLife: 30, exactDeck: 100, maxCopies: 1,
    commandZone: CommandZone.commander, commanderMayBePlaneswalker: true,
  );
  static const standardBrawl = GameFormat(
    id: 'standardbrawl', label: 'Standard Brawl', legalityKey: 'standardbrawl',
    startingLife: 25, multiplayerLife: 30, exactDeck: 60, maxCopies: 1,
    commandZone: CommandZone.commander, commanderMayBePlaneswalker: true,
  );
  static const oathbreaker = GameFormat(
    id: 'oathbreaker', label: 'Oathbreaker', legalityKey: 'oathbreaker',
    startingLife: 20, exactDeck: 60, maxCopies: 1,
    commandZone: CommandZone.oathbreaker,
  );
  static const pauperCommander = GameFormat(
    id: 'paupercommander', label: 'Pauper Commander', legalityKey: 'paupercommander',
    startingLife: 30, exactDeck: 100, maxCopies: 1,
    commandZone: CommandZone.commander,
  );
  static const modern = GameFormat(
    id: 'modern', label: 'Modern', legalityKey: 'modern',
    startingLife: 20, minDeck: 60, maxSideboard: 15,
  );
  static const pioneer = GameFormat(
    id: 'pioneer', label: 'Pioneer', legalityKey: 'pioneer',
    startingLife: 20, minDeck: 60, maxSideboard: 15,
  );
  static const standard = GameFormat(
    id: 'standard', label: 'Standard', legalityKey: 'standard',
    startingLife: 20, minDeck: 60, maxSideboard: 15,
  );
  static const legacy = GameFormat(
    id: 'legacy', label: 'Legacy', legalityKey: 'legacy',
    startingLife: 20, minDeck: 60, maxSideboard: 15,
  );
  static const vintage = GameFormat(
    id: 'vintage', label: 'Vintage', legalityKey: 'vintage',
    startingLife: 20, minDeck: 60, maxSideboard: 15,
  );
  static const pauper = GameFormat(
    id: 'pauper', label: 'Pauper', legalityKey: 'pauper',
    startingLife: 20, minDeck: 60, maxSideboard: 15,
  );
  /// Sealed, draft e JumpStart: 40 cartas, sem limite de cópias (o que sai
  /// dos boosters) e sem banidas.
  static const limited = GameFormat(
    id: 'limited', label: 'Limited (sealed/draft)',
    startingLife: 20, minDeck: 40, maxCopies: 99,
  );

  /// Uma lista de cartas para abrir packs de cubo (não é para jogar).
  static const cube = GameFormat(id: 'cube', label: 'Cubo (lista para packs)', startingLife: 20, maxCopies: 99);

  static const free = GameFormat(
    id: 'free', label: 'Livre', startingLife: 20,
    commandZone: CommandZone.commander,
  );

  static const all = [
    commander, brawl, standardBrawl, oathbreaker, pauperCommander,
    modern, pioneer, standard, legacy, vintage, pauper, limited, cube, free,
  ];

  static GameFormat byId(String id) =>
      all.firstWhere((f) => f.id == id, orElse: () => free);
}
