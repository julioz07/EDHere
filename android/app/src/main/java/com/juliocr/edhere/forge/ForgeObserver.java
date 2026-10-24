package com.juliocr.edhere.forge;

import com.google.common.collect.Multiset;
import com.google.common.eventbus.Subscribe;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

import forge.card.CardStateName;
import forge.game.Game;
import forge.game.GameLogEntry;
import forge.game.GameLogVerbosity;
import forge.game.GameOutcome;
import forge.game.card.Card;
import forge.game.card.CounterType;
import forge.game.event.GameEvent;
import forge.game.event.GameEventAttackersDeclared;
import forge.game.event.GameEventBlockersDeclared;
import forge.game.event.GameEventGameOutcome;
import forge.game.event.GameEventLandPlayed;
import forge.game.event.GameEventSpellAbilityCast;
import forge.game.event.GameEventSpellResolved;
import forge.game.event.GameEventTurnBegan;
import forge.game.phase.PhaseHandler;
import forge.game.player.Player;
import forge.game.player.PlayerView;
import forge.game.spellability.SpellAbilityStackInstance;
import forge.game.zone.ZoneType;

/**
 * Ouve os eventos da partida e envia o estado da mesa ao Flutter. Corre na
 * thread da partida (o EventBus do Forge entrega os eventos na thread que os
 * lança), por isso ler o jogo aqui é seguro. As pausas também ficam aqui: é
 * assim que se dá tempo para ver o que o bot fez.
 */
final class ForgeObserver {
    private static final ZoneType[] ZONES = {
            ZoneType.Battlefield, ZoneType.Hand, ZoneType.Graveyard, ZoneType.Exile, ZoneType.Command,
    };
    private static final int MIN_GAP_MS = 120; // entre estados sem pausa, para não inundar o Flutter

    private final int paceMs;
    private final ForgeEngine.Sink sink;
    /** As pessoas a jogar (ids do Forge): só se vê a mão delas. Vazio = bot contra bot, vê-se tudo. */
    private final Set<Integer> humans = new HashSet<>();
    private volatile boolean stopped;
    private volatile Game game;
    private long lastEmit;

    /**
     * Um estado ficou por enviar (veio depressa demais a seguir a outro). O
     * último de uma sequência rápida tem de chegar ao Flutter: sem isto, a mesa
     * podia ficar num estado antigo (uma carta já devolvida à mão, um turno atrás).
     */
    private volatile boolean dirty;
    private final ScheduledExecutorService flusher = Executors.newSingleThreadScheduledExecutor(
            r -> new Thread(r, "forge-flush"));

    ForgeObserver(int paceMs, ForgeEngine.Sink sink) {
        this.paceMs = paceMs;
        this.sink = sink;
    }

    void setHumans(Iterable<Player> players) {
        for (Player p : players) humans.add(p.getId());
    }

    /** Uma jogada da pessoa não precisa de pausa: só as do bot, para se ver o que fez. */
    private boolean byHuman(Object ev) {
        if (humans.isEmpty()) return false;
        PlayerView who = null;
        if (ev instanceof GameEventAttackersDeclared) who = ((GameEventAttackersDeclared) ev).player();
        else if (ev instanceof GameEventLandPlayed) who = ((GameEventLandPlayed) ev).player();
        else if (ev instanceof GameEventBlockersDeclared) who = ((GameEventBlockersDeclared) ev).defendingPlayer();
        else if (ev instanceof GameEventSpellAbilityCast || ev instanceof GameEventSpellResolved) {
            SpellAbilityStackInstance top = game.getStack().isEmpty() ? null : game.getStack().peek();
            if (top != null && top.getActivatingPlayer() != null) return humans.contains(top.getActivatingPlayer().getId());
            return false;
        }
        return who != null && humans.contains(who.getId());
    }

    void attach(Game g) {
        game = g;
        g.subscribeToEvents(this);
        flusher.scheduleWithFixedDelay(() -> {
            if (dirty && !stopped) {
                dirty = false;
                emit(snapshotSafe());
            }
        }, MIN_GAP_MS, MIN_GAP_MS, TimeUnit.MILLISECONDS);
    }

    void stop() {
        stopped = true;
        flusher.shutdownNow();
    }

    @Subscribe
    public void onEvent(GameEvent ev) {
        if (stopped) return;
        double pause;
        if (ev instanceof GameEventSpellAbilityCast) pause = 1.2;
        else if (ev instanceof GameEventAttackersDeclared || ev instanceof GameEventBlockersDeclared) pause = 1.0;
        else if (ev instanceof GameEventSpellResolved) pause = 0.6;
        else if (ev instanceof GameEventLandPlayed) pause = 0.5;
        else if (ev instanceof GameEventTurnBegan) pause = 0.4;
        else if (ev instanceof GameEventGameOutcome) {
            emit(snapshot());
            return;
        } else pause = 0;

        if (byHuman(ev)) pause = 0;
        long now = System.currentTimeMillis();
        if (pause == 0 && now - lastEmit < MIN_GAP_MS) {
            dirty = true;
            return;
        }
        dirty = false;
        emit(snapshot());
        if (pause > 0 && paceMs > 0) {
            try {
                Thread.sleep((long) (pause * paceMs));
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    /** Pede um estado novo daqui a pouco (por exemplo depois de um prompt, que pode apanhar o jogo a meio). */
    void markDirty() { dirty = true; }

    void finished() {
        if (stopped) return;
        flusher.shutdownNow(); // o "over" tem de ser o último
        Map<String, Object> m = snapshot();
        m.put("type", "over");
        GameOutcome o = game.getOutcome();
        if (o != null && !o.isDraw() && o.getWinningLobbyPlayer() != null) {
            for (Player p : game.getRegisteredPlayers()) {
                if (p.getLobbyPlayer() == o.getWinningLobbyPlayer()) m.put("winner", p.getId());
            }
        }
        emit(m);
    }

    void failed(Throwable e) {
        Map<String, Object> m = new HashMap<>();
        m.put("type", "error");
        m.put("error", e.toString());
        emit(m);
    }

    private synchronized void emit(Map<String, Object> m) {
        lastEmit = System.currentTimeMillis();
        sink.emit(m);
    }

    /**
     * O estado para um prompt: pode ser pedido fora da thread do jogo (os
     * toques correm na thread da interface), quando o jogo está à espera.
     */
    Map<String, Object> snapshotSafe() {
        for (int i = 0; i < 3; i++) {
            try {
                return snapshot();
            } catch (RuntimeException e) {
                // ConcurrentModification se o jogo mexer ao mesmo tempo: tenta outra vez
                android.util.Log.w("EDHereForge", "snapshot", e);
            }
        }
        return new HashMap<>();
    }

    private Map<String, Object> snapshot() {
        Map<String, Object> m = new HashMap<>();
        m.put("type", "state");
        PhaseHandler ph = game.getPhaseHandler();
        m.put("turn", ph.getTurn());
        if (ph.getPhase() != null) m.put("phase", ph.getPhase().name());
        if (ph.getPlayerTurn() != null) m.put("active", ph.getPlayerTurn().getId());
        if (ph.getPriorityPlayer() != null) m.put("priority", ph.getPriorityPlayer().getId());

        List<Object> players = new ArrayList<>();
        List<Object> cards = new ArrayList<>();
        // lido uma vez: Card.isAttacking() lê-o duas vezes e rebenta se o combate acabar entretanto
        forge.game.combat.Combat combat = ph.getCombat();
        for (Player p : game.getRegisteredPlayers()) {
            players.add(player(p));
            boolean showHand = humans.isEmpty() || humans.contains(p.getId());
            for (ZoneType z : ZONES) {
                if (z == ZoneType.Hand && !showHand) continue;
                for (Card c : p.getCardsIn(z)) cards.add(card(c, z, combat));
            }
        }
        m.put("players", players);
        m.put("cards", cards);

        List<Object> stack = new ArrayList<>();
        for (SpellAbilityStackInstance si : game.getStack()) {
            Map<String, Object> s = new HashMap<>();
            s.put("id", si.getId());
            Card src = si.getSourceCard();
            if (src != null) {
                s.put("src", src.getId());
                s.put("n", src.getName());
            }
            s.put("text", si.getStackDescription());
            if (si.getActivatingPlayer() != null) s.put("ctrl", si.getActivatingPlayer().getId());
            stack.add(s);
        }
        m.put("stack", stack);

        List<Object> log = new ArrayList<>();
        for (GameLogEntry e : game.getGameLog().getLogEntriesForVerbosity(GameLogVerbosity.MEDIUM)) {
            if (log.size() >= 20) break;
            log.add(e.message());
        }
        m.put("log", log);
        return m;
    }

    private static Map<String, Object> player(Player p) {
        Map<String, Object> m = new HashMap<>();
        m.put("id", p.getId());
        m.put("name", p.getName());
        m.put("life", p.getLife());
        m.put("hand", p.getCardsIn(ZoneType.Hand).size());
        m.put("library", p.getCardsIn(ZoneType.Library).size());
        if (p.hasLost()) m.put("lost", true);
        Map<String, Object> counters = counters(p.getCounters());
        if (!counters.isEmpty()) m.put("cn", counters);
        Map<String, Object> cmd = new HashMap<>();
        for (Map.Entry<Card, Integer> e : p.getCommanderDamage()) {
            if (e.getValue() > 0) cmd.put(String.valueOf(e.getKey().getId()), e.getValue());
        }
        if (!cmd.isEmpty()) m.put("cmdDmg", cmd);
        return m;
    }

    private static Map<String, Object> card(Card c, ZoneType z, forge.game.combat.Combat combat) {
        Map<String, Object> m = new HashMap<>();
        m.put("id", c.getId());
        // o nome da carta impressa ("A // B" nas de duas faces), para a imagem
        m.put("n", c.getPaperCard() != null ? c.getPaperCard().getName() : c.getName());
        m.put("z", z.name().toLowerCase());
        m.put("ow", c.getOwner().getId());
        m.put("c", c.getController().getId());
        if (c.isTapped()) m.put("t", true);
        if (c.isFaceDown()) m.put("fd", true);
        if (c.getCurrentStateName() == CardStateName.Backside || c.getCurrentStateName() == CardStateName.Flipped) {
            m.put("fi", 1);
        }
        // cartas de efeito do Forge (a regra do comandante, emblemas...), não cartas de jogo
        if (c.isImmutable()) m.put("fx", true);
        if (c.isToken()) {
            m.put("tk", true);
            m.put("tn", c.getName());
        }
        if (c.isCommander()) {
            m.put("cmd", true);
            m.put("casts", c.getOwner().getCommanderCast(c));
        }
        if (z == ZoneType.Battlefield) {
            if (c.isCreature()) {
                m.put("pow", c.getNetPower());
                m.put("tou", c.getNetToughness());
                if (c.isSick()) m.put("sick", true);
                if (c.getDamage() > 0) m.put("dmg", c.getDamage());
            }
            if (combat != null && combat.isAttacking(c)) m.put("atk", true);
            if (c.getAttachedTo() != null) m.put("at", c.getAttachedTo().getId());
            Map<String, Object> counters = counters(c.getCounters());
            if (!counters.isEmpty()) m.put("cn", counters);
        }
        return m;
    }

    /** Os nomes dos contadores do Forge para as chaves da mesa ("+1/+1", "loyalty"...). */
    private static Map<String, Object> counters(Multiset<CounterType> ms) {
        Map<String, Object> m = new HashMap<>();
        for (Multiset.Entry<CounterType> e : ms.entrySet()) {
            String name = e.getElement().getName();
            String key = "LOYAL".equals(name) ? "loyalty" : name.equals("+1/+1") || name.equals("-1/-1") ? name : name.toLowerCase();
            m.put(key, e.getCount());
        }
        return m;
    }
}
