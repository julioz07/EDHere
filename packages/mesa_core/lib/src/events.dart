/// Tipos de evento da mesa. Todos levam só IDs; a identidade de uma carta
/// (`o`, oracle id) só aparece quando a carta passa a ser pública.
abstract final class Ev {
  // Sala e preparação
  static const joinTable = 'join_table';
  static const startGame = 'start_game';
  static const deckLoaded = 'deck_loaded';

  // Turno
  static const passTurn = 'pass_turn';
  static const setPhase = 'set_phase';
  static const untapAll = 'untap_all';

  // Cartas
  static const move = 'move';
  static const tap = 'tap';
  static const flip = 'flip';
  static const faceDown = 'face_down';
  static const attach = 'attach';
  static const control = 'change_control';
  static const position = 'set_position';

  // Contadores e tokens
  static const counter = 'counter';
  static const token = 'create_token';
  static const tokenQty = 'set_token_qty';

  // Jogador
  static const life = 'set_life';
  static const commanderDamage = 'commander_damage';
  static const playerCounter = 'set_player_counter';
  static const monarch = 'set_monarch';
  static const initiative = 'set_initiative';
  static const defeated = 'concede';

  // Grimório e mão
  static const draw = 'draw';
  static const shuffle = 'shuffle';
  static const mill = 'mill';
  static const reveal = 'reveal';
  static const scryDone = 'scry_done';
  static const mulligan = 'mulligan';
  static const bottom = 'bottom';

  // Mesa
  static const highlight = 'highlight';
  static const arrow = 'target_arrow';
  static const rollDie = 'roll_die';
  static const flipCoin = 'flip_coin';
  static const randomPlayer = 'random_player';
  static const undo = 'undo';
  static const emote = 'chat_emote';

  // Estado global
  static const storm = 'storm';
  static const dayNight = 'day_night';
  static const gameOver = 'game_over';

  /// Eventos que não entram no registo nem contam para "a última ação".
  static const silent = {highlight, position};
}

/// Uma intenção pronta a enviar (local ou pela rede).
class Intent {
  const Intent(this.type, this.payload);
  final String type;
  final Map<String, dynamic> payload;

  @override
  String toString() => 'Intent($type $payload)';
}
