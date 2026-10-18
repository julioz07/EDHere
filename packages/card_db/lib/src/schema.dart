/// Versão do esquema de `cards.sqlite`. Uma base com outra versão é ignorada
/// e a app pede para voltar a descarregar os dados.
const int cardSchemaVersion = 1;

const List<String> cardSchema = [
  '''
  CREATE TABLE meta(
    key TEXT PRIMARY KEY,
    value TEXT
  )''',
  '''
  CREATE TABLE cards(
    oracle_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    name_norm TEXT NOT NULL,
    mana_cost TEXT,
    mv REAL,
    type_line TEXT,
    oracle_text TEXT,
    power TEXT,
    toughness TEXT,
    loyalty TEXT,
    defense TEXT,
    color_mask INTEGER,
    color_count INTEGER,
    identity_mask INTEGER,
    identity_count INTEGER,
    layout TEXT,
    keywords TEXT,
    rarity TEXT,
    set_code TEXT,
    collector_number TEXT,
    print_id TEXT,
    artist TEXT,
    released_at TEXT,
    img_small TEXT,
    img_normal TEXT,
    faces_json TEXT,
    produced_mana TEXT,
    is_token INTEGER,
    is_extra INTEGER,
    is_paper INTEGER,
    game_changer INTEGER,
    reserved INTEGER,
    edhrec_rank INTEGER
  )''',
  'CREATE INDEX cards_name ON cards(name_norm)',
  // Todos os nomes por que uma carta pode ser procurada: o completo e o de
  // cada face ("Fire // Ice", "Fire", "Ice").
  '''
  CREATE TABLE card_names(
    name_norm TEXT NOT NULL,
    oracle_id TEXT NOT NULL,
    PRIMARY KEY(name_norm, oracle_id)
  ) WITHOUT ROWID''',
  // Só se guardam legal, banned e restricted; ausência = not_legal.
  '''
  CREATE TABLE legalities(
    format TEXT NOT NULL,
    oracle_id TEXT NOT NULL,
    status TEXT NOT NULL,
    PRIMARY KEY(format, oracle_id)
  ) WITHOUT ROWID''',
  'CREATE INDEX legalities_card ON legalities(oracle_id)',
  '''
  CREATE TABLE rulings(
    oracle_id TEXT NOT NULL,
    published_at TEXT,
    source TEXT,
    comment TEXT
  )''',
  'CREATE INDEX rulings_card ON rulings(oracle_id)',
];
