package com.juliocr.edhere.forge;

import android.content.Context;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import forge.deck.CardPool;
import forge.deck.Deck;
import forge.deck.DeckSection;
import forge.game.Game;
import forge.game.GameEndReason;
import forge.game.GameRules;
import forge.game.GameType;
import forge.game.Match;
import forge.game.card.Card;
import forge.game.player.Player;
import forge.game.player.RegisteredPlayer;
import forge.game.spellability.SpellAbilityStackInstance;
import forge.gamemodes.match.HostedMatch;
import forge.gui.GuiBase;
import forge.gui.interfaces.IGuiGame;
import forge.interfaces.IGameController;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import forge.player.LobbyPlayerHuman;

/**
 * O motor do Forge dentro da app. Tudo o que toca no Forge corre fora da
 * thread da interface: o arranque e a preparação dos decks num worker, cada
 * partida numa thread própria (com pilha grande: a IA é recursiva).
 */
public final class ForgeEngine {
    private ForgeEngine() { }

    /** Recebe estados e eventos da partida (chamado fora da thread da interface). */
    public interface Sink { void emit(Map<String, Object> event); }

    /** Resposta a um pedido (chamada fora da thread da interface). */
    public interface Reply {
        void ok(Object value);
        void fail(String code, String message);
    }

    private static final String TAG = "EDHereForge";
    private static final String RES_ASSET = "forge/forge-res.zip";

    static void log(String msg) { Log.i(TAG, msg); }

    private static final ExecutorService worker = Executors.newSingleThreadExecutor(
            r -> new Thread(null, r, "forge-worker", 32L << 20));

    private static volatile String state = "idle"; // idle, loading, ready, error
    private static volatile String error;
    private static volatile ForgeMatch match;

    public static Map<String, Object> status() {
        Map<String, Object> m = new HashMap<>();
        m.put("state", state);
        if (error != null) m.put("error", error);
        m.put("playing", match != null && match.isRunning());
        return m;
    }

    /** Prepara os dados (só da primeira vez) e arranca o Forge. Responde com o estado. */
    public static synchronized void init(Context ctx, String language, Reply reply) {
        if ("ready".equals(state) || "loading".equals(state)) {
            worker.execute(() -> reply.ok(status())); // em "loading", responde depois de acabar
            return;
        }
        state = "loading";
        error = null;
        final Context app = ctx.getApplicationContext();
        worker.execute(() -> {
            try {
                long t0 = System.nanoTime();
                File dir = extractRes(app);
                long t1 = System.nanoTime();
                start(dir, language);
                log(String.format("pronto: dados %.1f s, arranque %.1f s", (t1 - t0) / 1e9, (System.nanoTime() - t1) / 1e9));
                state = "ready";
            } catch (Throwable e) {
                Log.e(TAG, "init", e);
                error = e.toString();
                state = "error";
            }
            reply.ok(status());
        });
    }

    /** Copia os dados do Forge para a app se faltarem ou forem de outra versão. */
    private static File extractRes(Context ctx) throws IOException {
        File dir = new File(ctx.getFilesDir(), "forge");
        String want = assetVersion(ctx);
        File stamp = new File(dir, "VERSION");
        if (want != null && stamp.exists() && want.equals(readFirstLine(stamp))) {
            return dir;
        }
        deleteTree(dir);
        if (!dir.mkdirs()) throw new IOException("não foi possível criar " + dir);
        byte[] buf = new byte[1 << 16];
        try (ZipInputStream zin = new ZipInputStream(ctx.getAssets().open(RES_ASSET))) {
            ZipEntry e;
            while ((e = zin.getNextEntry()) != null) {
                File out = new File(dir, e.getName());
                if (!out.getCanonicalPath().startsWith(dir.getCanonicalPath() + File.separator)) {
                    throw new IOException("entrada fora da pasta: " + e.getName());
                }
                if (e.isDirectory()) { out.mkdirs(); continue; }
                out.getParentFile().mkdirs();
                // o VERSION escreve-se no fim: se a cópia for interrompida, repete-se
                if ("VERSION".equals(e.getName())) continue;
                try (OutputStream os = new FileOutputStream(out)) {
                    int n;
                    while ((n = zin.read(buf)) > 0) os.write(buf, 0, n);
                }
            }
        }
        String home = dir.getAbsolutePath() + "/";
        try (OutputStream os = new FileOutputStream(new File(dir, "forge.profile.properties"))) {
            os.write(("userDir=" + home + "user/\ncacheDir=" + home + "cache/\n").getBytes(StandardCharsets.UTF_8));
        }
        try (OutputStream os = new FileOutputStream(stamp)) {
            os.write(((want == null ? "?" : want) + "\n").getBytes(StandardCharsets.UTF_8));
        }
        return dir;
    }

    private static String assetVersion(Context ctx) throws IOException {
        try (ZipInputStream zin = new ZipInputStream(ctx.getAssets().open(RES_ASSET))) {
            ZipEntry e;
            while ((e = zin.getNextEntry()) != null) {
                if ("VERSION".equals(e.getName())) {
                    return new BufferedReader(new InputStreamReader(zin, StandardCharsets.UTF_8)).readLine().trim();
                }
            }
        }
        return null;
    }

    private static String readFirstLine(File f) throws IOException {
        try (InputStream in = new java.io.FileInputStream(f)) {
            String s = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8)).readLine();
            return s == null ? "" : s.trim();
        }
    }

    private static void deleteTree(File f) {
        File[] kids = f.listFiles();
        if (kids != null) for (File k : kids) deleteTree(k);
        f.delete();
    }

    private static void start(File dir, String language) {
        // Sem user.home, o Forge não consegue calcular as pastas por defeito e
        // não arranca (mesmo com o forge.profile.properties a indicá-las).
        System.setProperty("user.home", dir.getAbsolutePath());
        GuiBase.setInterface(new HeadlessGui(dir.getAbsolutePath()));
        FModel.initialize(null, prefs -> {
            // Só lê o script de cada carta quando é preciso: com as 34 mil
            // carregadas, a memória chega aos 130 MB (o limite é ~192 MB).
            prefs.setPref(FPref.LOAD_CARD_SCRIPTS_LAZILY, true);
            prefs.setPref(FPref.UI_LANGUAGE, language);
            // passa a vez sozinho quando a pessoa não tem nada que possa fazer
            prefs.setPref(FPref.YIELD_AUTO_PASS_NO_ACTIONS, true);
            // sem gravações de partidas (e o código delas precisa do netty, que não vem na app)
            prefs.setPref(FPref.UI_RECORD_REPLAYS, false);
            return null;
        });
    }

    /** Cartas destes decks que o Forge não conhece. Responde com {seat: [nomes]}. */
    public static void checkDecks(List<Map<String, Object>> seats, Reply reply) {
        worker.execute(() -> {
            try {
                Map<String, Object> out = new LinkedHashMap<>();
                for (int i = 0; i < seats.size(); i++) {
                    List<String> missing = new ArrayList<>();
                    buildDeck(seats.get(i), missing);
                    out.put(String.valueOf(i), missing);
                }
                reply.ok(out);
            } catch (Throwable e) {
                Log.e(TAG, "checkDecks", e);
                reply.fail("deck", e.toString());
            }
        });
    }

    /**
     * Começa uma partida. Cada lugar: {name, bot: "easy"|"normal"|"hard"|null,
     * deck: [{n: nome, q: quantidade, b: "main"|"command"|"side"}]}.
     * Opções: format ("commander" ou "constructed"), pace (ms entre jogadas, para se ver).
     */
    @SuppressWarnings("unchecked")
    public static synchronized void startMatch(Map<String, Object> args, Sink sink, Reply reply) {
        if (!"ready".equals(state)) {
            reply.fail("not_ready", "o motor ainda não arrancou");
            return;
        }
        stopMatch();
        worker.execute(() -> {
            try {
                GameType type = "commander".equals(args.get("format")) ? GameType.Commander : GameType.Constructed;
                List<Map<String, Object>> seats = (List<Map<String, Object>>) args.get("seats");
                List<RegisteredPlayer> players = new ArrayList<>();
                Map<Integer, String> difficulty = new HashMap<>(); // índice do lugar -> dificuldade
                RegisteredPlayer human = null;
                boolean hardBot = false;
                for (int i = 0; i < seats.size(); i++) {
                    Map<String, Object> s = seats.get(i);
                    Deck deck = buildDeck(s, new ArrayList<>());
                    RegisteredPlayer rp = type == GameType.Commander ? RegisteredPlayer.forCommander(deck) : new RegisteredPlayer(deck);
                    String bot = (String) s.get("bot");
                    String name = (String) s.get("name");
                    if (bot == null && human == null) {
                        rp.setPlayer(new LobbyPlayerHuman(name));
                        human = rp;
                    } else {
                        rp.setPlayer(ForgeBots.create(name, bot == null ? ForgeBots.NORMAL : bot));
                        difficulty.put(i, bot == null ? ForgeBots.NORMAL : bot);
                        hardBot |= ForgeBots.HARD.equals(bot);
                    }
                    players.add(rp);
                }
                GameRules rules = new GameRules(type);
                rules.setAppliedVariants(EnumSet.of(type));
                rules.setAllowCheatShuffle(hardBot);
                Number pace = (Number) args.get("pace");
                ForgeMatch m = new ForgeMatch(rules, players, human, difficulty, pace == null ? 0 : pace.intValue(), sink);
                match = m;
                m.start();
                reply.ok(null);
            } catch (Throwable e) {
                Log.e(TAG, "startMatch", e);
                reply.fail("start", e.toString());
            }
        });
    }

    public static synchronized void stopMatch() {
        ForgeMatch m = match;
        match = null;
        if (m != null) m.stop();
    }

    @SuppressWarnings("unchecked")
    private static Deck buildDeck(Map<String, Object> seat, List<String> missing) {
        Deck deck = new Deck((String) seat.get("name"));
        for (Map<String, Object> e : (List<Map<String, Object>>) seat.get("deck")) {
            String name = (String) e.get("n");
            int qty = ((Number) e.get("q")).intValue();
            String board = (String) e.get("b");
            CardPool pool = "command".equals(board) ? deck.getOrCreate(DeckSection.Commander)
                    : "side".equals(board) ? deck.getOrCreate(DeckSection.Sideboard)
                    : deck.getMain();
            int before = pool.countAll();
            pool.add(name, qty);
            // "A // B": o Forge só usa o nome completo nas cartas divididas; nas
            // de duas faces (transformar, MDFC, aventura) usa o da frente
            if (pool.countAll() == before && name.contains(" // ")) {
                pool.add(name.substring(0, name.indexOf(" // ")), qty);
            }
            if (pool.countAll() == before) missing.add(name);
        }
        return deck;
    }

    /** Um toque da pessoa: {kind: card|player|ok|cancel|stack|concede, id}. */
    public static void act(Map<String, Object> args) {
        ForgeMatch m = match;
        if (m != null) m.act(args);
    }

    /** A resposta a uma pergunta ("ask") da partida. */
    public static void answer(int id, Object value) {
        ForgeMatch m = match;
        if (m != null && m.gui != null) m.gui.answer(id, value);
    }

    /**
     * Uma partida a correr na sua thread. Só com bots, corre o Match
     * diretamente; com uma pessoa, passa pelo HostedMatch do Forge, que liga o
     * controlador humano à nossa interface (EdhereGui).
     */
    static final class ForgeMatch {
        private final GameRules rules;
        private final List<RegisteredPlayer> players;
        private final RegisteredPlayer human;
        private final Map<Integer, String> difficulty;
        private final ForgeObserver observer;
        final EdhereGui gui;
        private Thread thread;
        private volatile Game game;
        private volatile boolean running;

        ForgeMatch(GameRules rules, List<RegisteredPlayer> players, RegisteredPlayer human,
                   Map<Integer, String> difficulty, int paceMs, Sink sink) {
            this.rules = rules;
            this.players = players;
            this.human = human;
            this.difficulty = difficulty;
            this.observer = new ForgeObserver(paceMs, sink);
            this.gui = human == null ? null : new EdhereGui(sink, observer, this::onGame);
        }

        boolean isRunning() { return running; }

        void start() {
            running = true;
            // "Game..." no nome: o Forge trata-a como thread do jogo e corre a
            // partida aqui mesmo (com pilha grande: a IA é recursiva)
            thread = new Thread(null, this::run, "Game-EDHere", 64L << 20);
            thread.start();
        }

        /** O jogo acabou de ser criado: liga o observador e configura os bots. */
        private void onGame(Game g) {
            game = g;
            for (Player p : g.getRegisteredPlayers()) {
                int seat = players.indexOf(p.getRegisteredPlayer());
                String level = difficulty.get(seat);
                if (level != null) ForgeBots.configure(p, level);
                else observer.setHumans(java.util.Collections.singletonList(p));
            }
            observer.attach(g);
        }

        private void run() {
            try {
                if (human == null) {
                    Match match = new Match(rules, players, "EDHere");
                    Game g = match.createGame();
                    g.setNoGUIUser();
                    onGame(g);
                    match.startGame(g);
                } else {
                    HostedMatch hosted = new HostedMatch();
                    Map<RegisteredPlayer, IGuiGame> guis = new HashMap<>();
                    guis.put(human, gui);
                    hosted.startMatch(rules, null, players, guis, null);
                }
                observer.finished();
            } catch (Throwable e) {
                Log.e(TAG, "match", e);
                observer.failed(e);
            } finally {
                running = false;
            }
        }

        /** Os toques correm na thread da interface do Forge, como num ecrã do próprio Forge. */
        void act(Map<String, Object> args) {
            if (gui == null) return;
            HeadlessGui.runInEdt(() -> {
                try {
                    IGameController c = gui.controller();
                    Game g = game;
                    if (c == null || g == null) return;
                    String kind = (String) args.get("kind");
                    Number id = (Number) args.get("id");
                    switch (kind) {
                        case "ok": c.selectButtonOk(); break;
                        case "cancel": c.selectButtonCancel(); break;
                        case "card": {
                            Card card = g.findById(id.intValue());
                            if (card != null) c.selectCard(card.getView(), null, null);
                            break;
                        }
                        case "player": {
                            Player p = g.getPlayer(id.intValue());
                            if (p != null) c.selectPlayer(p.getView(), null);
                            break;
                        }
                        case "stack": {
                            for (SpellAbilityStackInstance si : g.getStack()) {
                                if (si.getId() == id.intValue()) c.selectStackItem(si.getView());
                            }
                            break;
                        }
                        case "concede": c.concede(); break;
                        default: log("toque desconhecido: " + kind);
                    }
                } catch (Throwable e) {
                    Log.e(TAG, "act", e);
                }
            });
        }

        void stop() {
            observer.stop();
            if (gui != null) {
                gui.close();
                IGameController c = gui.controller();
                if (c != null) HeadlessGui.runInEdt(() -> {
                    try { c.concede(); } catch (Throwable ignored) { }
                });
            }
            Game g = game;
            if (g != null && !g.isGameOver()) {
                try { g.setGameOver(GameEndReason.Draw); } catch (Throwable ignored) { }
            }
            // a ver bots, acorda a thread das pausas; com uma pessoa, o concede
            // já liberta o jogo (interromper faz o Forge registar um "bug")
            if (thread != null && gui == null) thread.interrupt();
        }
    }
}
