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
import forge.game.event.GameEventCardChangeZone;
import forge.game.event.GameEventCardDamaged;
import forge.game.event.GameEventGameOutcome;
import forge.game.event.GameEventLandPlayed;
import forge.game.event.GameEventPlayerDamaged;
import forge.game.event.GameEventSpellAbilityCast;
import forge.game.event.GameEventSpellResolved;
import forge.game.event.GameEventTokenCreated;
import forge.game.event.GameEventTurnBegan;
import forge.game.event.GameEventTurnPhase;
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
final class ForgeObserver implements ForgeBots.Thinker {
    private static final ZoneType[] ZONES = {
            ZoneType.Battlefield, ZoneType.Hand, ZoneType.Graveyard, ZoneType.Exile, ZoneType.Command,
    };
    private static final int MIN_GAP_MS = 120; // entre estados sem pausa, para não inundar o Flutter

    /** Base das pausas (ms): cada jogada do bot espera um múltiplo disto. Muda-se a meio do jogo. */
    private volatile int paceMs;
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

    void setPace(int ms) { paceMs = ms; }

    /**
     * O bot vai fazer uma jogada: a mesa mostra o que ele está a ver (a carta, os
     * alvos, quem ataca) e o jogo espera um pouco antes de a fazer, ao ritmo escolhido.
     */
    @Override
    public void think(Player who, String kind, List<Integer> cards, List<Integer> players, double weight) {
        if (stopped || who == null) return;
        int ms = (int) (weight * paceMs);
        Map<String, Object> m = new HashMap<>();
        m.put("type", "think");
        m.put("by", who.getId());
        m.put("kind", kind);
        m.put("cards", new ArrayList<Object>(cards));
        m.put("players", new ArrayList<Object>(players));
        m.put("ms", Math.max(ms, 500));
        emit(m);
        if (ms > 0) {
            try {
                Thread.sleep(ms);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
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

    /**
     * O ritmo do jogo: depois de cada acontecimento do bot, envia o estado (e,
     * nas jogadas, um destaque com a carta) e espera um múltiplo de [paceMs],
     * para se perceber o que fez. As jogadas da própria pessoa não esperam.
     */
    @Subscribe
    public void onEvent(GameEvent ev) {
        if (stopped) return;
        if (ev instanceof GameEventGameOutcome) {
            emit(snapshot());
            return;
        }
        boolean human = byHuman(ev);
        double pause = 0;
        Map<String, Object> spot = null;
        if (ev instanceof GameEventSpellAbilityCast) {
            GameEventSpellAbilityCast e = (GameEventSpellAbilityCast) ev;
            pause = human ? 0 : 2.0;
            if (!human) spot = castSpot(e);
        } else if (ev instanceof GameEventAttackersDeclared) {
            GameEventAttackersDeclared e = (GameEventAttackersDeclared) ev;
            if (!human && !e.attackersMap().isEmpty()) {
                pause = 1.6;
                spot = spot("attack", e.player(), null);
                spot.put("count", e.attackersMap().size());
                // as criaturas atacantes, para o destaque as mostrar lado a lado
                List<Object> attackers = new ArrayList<>();
                List<Object> names = new ArrayList<>();
                for (forge.game.card.CardView c : e.attackersMap().values()) {
                    attackers.add(c.getId());
                    names.add(c.getName());
                }
                spot.put("cards", attackers);
                spot.put("names", names);
            }
        } else if (ev instanceof GameEventBlockersDeclared) {
            pause = human ? 0 : 1.4;
        } else if (ev instanceof GameEventLandPlayed) {
            GameEventLandPlayed e = (GameEventLandPlayed) ev;
            if (!human) {
                pause = 1.0;
                spot = spot("land", e.player(), e.land());
            }
        } else if (ev instanceof GameEventSpellResolved) {
            pause = human ? 0 : 0.8;
        } else if (ev instanceof GameEventTurnBegan) {
            pause = 0.8;
        } else if (ev instanceof GameEventPlayerDamaged || ev instanceof GameEventCardDamaged) {
            pause = 0.5; // de quem for: vê-se a vida a descer e a carta marcada
        } else if (ev instanceof GameEventCardChangeZone) {
            GameEventCardChangeZone e = (GameEventCardChangeZone) ev;
            boolean dies = e.from() != null && e.to() != null
                    && e.from().zoneType() == ZoneType.Battlefield && e.to().zoneType() == ZoneType.Graveyard;
            if (dies) pause = 0.6;
        } else if (ev instanceof GameEventTokenCreated) {
            pause = 0.4;
        } else if (ev instanceof GameEventTurnPhase) {
            // as fases andam devagar o suficiente para se verem e seguirem (o utilizador
            // pediu pelo menos mais 2 s por fase, ao ritmo normal): no turno do bot e
            // no meu quando o Forge passa sozinho (não há nada que se possa jogar)
            GameEventTurnPhase e = (GameEventTurnPhase) ev;
            if (e.playerTurn() != null && !humans.isEmpty()) pause = humans.contains(e.playerTurn().getId()) ? 2.35 : 2.25;
        }

        long now = System.currentTimeMillis();
        if (pause == 0 && spot == null && now - lastEmit < MIN_GAP_MS) {
            dirty = true;
            return;
        }
        dirty = false;
        emit(snapshot());
        int ms = (int) (pause * paceMs);
        if (spot != null && paceMs > 0) {
            spot.put("ms", Math.max(ms, 600));
            emit(spot);
        }
        if (ms > 0) {
            try {
                Thread.sleep(ms);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    private static Map<String, Object> spot(String kind, PlayerView who, forge.game.card.CardView card) {
        Map<String, Object> m = new HashMap<>();
        m.put("type", "spot");
        m.put("kind", kind);
        if (who != null) m.put("by", who.getId());
        if (card != null) {
            m.put("card", card.getId());
            m.put("n", card.getName());
        }
        return m;
    }

    /** Um feitiço ou habilidade do bot: a carta, o que faz e os alvos. */
    private static Map<String, Object> castSpot(GameEventSpellAbilityCast e) {
        forge.game.card.CardView host = e.sa() == null ? null : e.sa().getHostCard();
        PlayerView who = e.si() == null ? null : e.si().getActivatingPlayer();
        String kind = e.si() == null ? "cast" : e.si().isTrigger() ? "trigger" : e.si().isAbility() ? "ability" : "cast";
        Map<String, Object> m = spot(kind, who, host);
        if (e.si() != null && e.si().getText() != null) m.put("text", e.si().getText());
        if (e.targetDescription() != null && !e.targetDescription().isEmpty()) m.put("targets", e.targetDescription());
        return m;
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
            if (combat != null && combat.isBlocking(c)) {
                m.put("blk", true);
                // quem bloqueia, para as setas de bloqueio
                List<Object> of = new ArrayList<>();
                for (Card a : combat.getAttackersBlockedBy(c)) of.add(a.getId());
                m.put("blkOf", of);
            }
            if (combat != null && combat.isAttacking(c)) {
                // o alvo do ataque: um jogador ("p") ou um planeswalker/batalha ("c")
                forge.game.GameEntity d = combat.getDefenderByAttacker(c);
                if (d instanceof Player) m.put("atkP", ((Player) d).getId());
                else if (d instanceof Card) m.put("atkC", ((Card) d).getId());
            }
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
