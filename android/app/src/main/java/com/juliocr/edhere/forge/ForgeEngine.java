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

import forge.LobbyPlayer;
import forge.deck.CardPool;
import forge.deck.Deck;
import forge.deck.DeckSection;
import forge.game.Game;
import forge.game.GameEndReason;
import forge.game.GameRules;
import forge.game.GameType;
import forge.game.Match;
import forge.game.player.Player;
import forge.game.player.RegisteredPlayer;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;

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
                List<String> difficulty = new ArrayList<>();
                boolean hardBot = false;
                for (Map<String, Object> s : seats) {
                    Deck deck = buildDeck(s, new ArrayList<>());
                    RegisteredPlayer rp = type == GameType.Commander ? RegisteredPlayer.forCommander(deck) : new RegisteredPlayer(deck);
                    String bot = (String) s.get("bot");
                    String name = (String) s.get("name");
                    LobbyPlayer lp = ForgeBots.create(name, bot == null ? ForgeBots.NORMAL : bot);
                    rp.setPlayer(lp);
                    players.add(rp);
                    difficulty.add(bot);
                    hardBot |= ForgeBots.HARD.equals(bot);
                }
                GameRules rules = new GameRules(type);
                rules.setAppliedVariants(EnumSet.of(type));
                rules.setAllowCheatShuffle(hardBot);
                Number pace = (Number) args.get("pace");
                ForgeMatch m = new ForgeMatch(new Match(rules, players, "EDHere"), difficulty,
                        pace == null ? 0 : pace.intValue(), sink);
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

    /** Uma partida a correr na sua thread. */
    static final class ForgeMatch {
        private final Match match;
        private final List<String> difficulty;
        private final ForgeObserver observer;
        private Thread thread;
        private volatile Game game;
        private volatile boolean running;

        ForgeMatch(Match match, List<String> difficulty, int paceMs, Sink sink) {
            this.match = match;
            this.difficulty = difficulty;
            this.observer = new ForgeObserver(paceMs, sink);
        }

        boolean isRunning() { return running; }

        void start() {
            running = true;
            thread = new Thread(null, this::run, "forge-match", 64L << 20);
            thread.start();
        }

        private void run() {
            try {
                Game g = match.createGame();
                game = g;
                g.setNoGUIUser();
                List<Player> seats = g.getRegisteredPlayers();
                for (int i = 0; i < seats.size(); i++) {
                    ForgeBots.configure(seats.get(i), difficulty.get(i));
                }
                observer.attach(g);
                match.startGame(g);
                observer.finished();
            } catch (Throwable e) {
                Log.e(TAG, "match", e);
                observer.failed(e);
            } finally {
                running = false;
            }
        }

        void stop() {
            observer.stop();
            Game g = game;
            if (g != null && !g.isGameOver()) {
                try { g.setGameOver(GameEndReason.Draw); } catch (Throwable ignored) { }
            }
            if (thread != null) thread.interrupt();
        }
    }
}
