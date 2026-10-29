package com.juliocr.edhere.forge;

import java.util.ArrayList;
import java.util.EnumSet;
import java.util.List;
import java.util.Random;

import forge.LobbyPlayer;
import forge.ai.LobbyPlayerAi;
import forge.ai.PlayerControllerAi;
import forge.game.Game;
import forge.game.GameEntity;
import forge.game.card.Card;
import forge.game.combat.Combat;
import forge.game.player.Player;
import forge.game.spellability.SpellAbility;
import forge.game.spellability.TargetChoices;

/**
 * Os bots por dificuldade. Os perfis do Forge mudam sobretudo o estilo: em
 * torneios bot contra bot (Commander, 20 a 30 partidas), Hard, Cautious e
 * Reckless ficaram todos perto de 50% contra o Default. Por isso:
 * - fácil: o bot do Forge com erros de propósito (ganhou 5 de 30 ao normal);
 * - normal: o bot do Forge tal como vem;
 * - difícil: perfil Hard, pesquisa Monte Carlo e baralhamentos que lhe dão
 *   melhor mana (16 de 30 ao normal: contra pessoas a pesquisa evita erros
 *   grosseiros, mas bot contra bot quase não se nota).
 *
 * Todos mostram o que vão fazer antes de o fazer ({@link Thinker}): a carta
 * que vão jogar, os alvos, quem ataca e quem bloqueia. Como numa mesa a sério,
 * o adversário pensa à vista; o tempo que isso leva segue a velocidade escolhida.
 */
final class ForgeBots {
    private ForgeBots() { }

    static final String EASY = "easy";
    static final String NORMAL = "normal";
    static final String HARD = "hard";

    /** Quem mostra o que o bot está a pensar (a mesa da partida a correr). */
    interface Thinker {
        /** [kind]: cast, attack ou block; [weight]: quanto tempo fica à vista (× o ritmo). */
        void think(Player who, String kind, List<Integer> cards, List<Integer> players, double weight);
    }

    static volatile Thinker thinker;

    static LobbyPlayer create(String name, String difficulty) {
        BotLobbyPlayer p = new BotLobbyPlayer(name, EASY.equals(difficulty));
        p.setAiProfile(HARD.equals(difficulty) ? "Hard" : "Default");
        return p;
    }

    /** Liga a pesquisa Monte Carlo só no bot difícil (no Forge é por jogo). */
    static void configure(Player p, String difficulty) {
        if (p.getController() instanceof PlayerControllerAi) {
            ((PlayerControllerAi) p.getController()).getAi().setFlatMonteCarloOverride(HARD.equals(difficulty));
        }
    }

    private static final Random RNG = new Random();
    // Com 0.3/0.35/0.35 o fácil ainda ganhava 11 de 30 ao normal; com 0.5, 5 de 30.
    static double skipPlay = 0.5;
    static double dropAttacker = 0.5;
    static double dropBlocker = 0.5;

    static final class BotLobbyPlayer extends LobbyPlayerAi {
        private final boolean easy;

        BotLobbyPlayer(String name, boolean easy) {
            super(name, EnumSet.noneOf(forge.ai.AIOption.class));
            this.easy = easy;
        }

        @Override
        public Player createIngamePlayer(Game game, int id) {
            Player ai = new Player(getName(), game, id);
            ai.setFirstController(new BotController(game, ai, this, easy));
            return ai;
        }
    }

    /**
     * O bot do Forge a pensar à vista. O fácil joga sempre os terrenos; o resto às
     * vezes deixa passar, ataca com menos e falha bloqueios.
     */
    static final class BotController extends PlayerControllerAi {
        private final boolean easy;

        BotController(Game game, Player p, LobbyPlayer lp, boolean easy) {
            super(game, p, lp);
            this.easy = easy;
        }

        @Override
        public List<SpellAbility> chooseSpellAbilityToPlay() {
            List<SpellAbility> sas = super.chooseSpellAbilityToPlay();
            if (sas == null || sas.isEmpty() || sas.get(0).isLandAbility()) return sas;
            if (easy && RNG.nextDouble() < skipPlay) {
                return null; // passa a prioridade, o que fecha essa janela
            }
            // a IA escolhe os alvos ao avaliar a jogada: aqui já se sabe a carta e os alvos
            SpellAbility sa = sas.get(0);
            List<Integer> cards = new ArrayList<>();
            List<Integer> players = new ArrayList<>();
            if (sa.getHostCard() != null) cards.add(sa.getHostCard().getId());
            for (SpellAbility s = sa; s != null; s = s.getSubAbility()) {
                TargetChoices t = s.getTargets();
                if (t == null) continue;
                for (Card c : t.getTargetCards()) cards.add(c.getId());
                for (Player p : t.getTargetPlayers()) players.add(p.getId());
            }
            think("cast", cards, players, 1.4);
            return sas;
        }

        @Override
        public void declareAttackers(Player attacker, Combat combat) {
            super.declareAttackers(attacker, combat);
            if (easy) {
                for (Card c : new ArrayList<>(combat.getAttackers())) {
                    if (RNG.nextDouble() < dropAttacker) combat.removeFromCombat(c);
                }
            }
            List<Integer> cards = new ArrayList<>();
            List<Integer> players = new ArrayList<>();
            for (Card c : combat.getAttackers()) {
                cards.add(c.getId());
                GameEntity d = combat.getDefenderByAttacker(c);
                if (d instanceof Player && !players.contains(d.getId())) players.add(d.getId());
                else if (d instanceof Card) cards.add(d.getId());
            }
            if (!cards.isEmpty()) think("attack", cards, players, 1.4);
        }

        @Override
        public void declareBlockers(Player defender, Combat combat) {
            super.declareBlockers(defender, combat);
            if (easy) {
                for (Card c : new ArrayList<>(combat.getAllBlockers())) {
                    if (RNG.nextDouble() < dropBlocker) combat.removeFromCombat(c);
                }
            }
            List<Integer> cards = new ArrayList<>();
            for (Card b : combat.getAllBlockers()) cards.add(b.getId());
            if (!cards.isEmpty()) think("block", cards, new ArrayList<>(), 1.0);
        }

        private void think(String kind, List<Integer> cards, List<Integer> players, double weight) {
            Thinker t = thinker;
            if (t != null) t.think(getPlayer(), kind, cards, players, weight);
        }
    }
}
