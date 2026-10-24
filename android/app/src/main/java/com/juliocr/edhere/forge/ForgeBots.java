package com.juliocr.edhere.forge;

import java.util.ArrayList;
import java.util.EnumSet;
import java.util.List;
import java.util.Random;

import forge.LobbyPlayer;
import forge.ai.LobbyPlayerAi;
import forge.ai.PlayerControllerAi;
import forge.game.Game;
import forge.game.card.Card;
import forge.game.combat.Combat;
import forge.game.player.Player;
import forge.game.spellability.SpellAbility;
import forge.player.GamePlayerUtil;

/**
 * Os bots por dificuldade. Os perfis do Forge mudam sobretudo o estilo: em
 * torneios bot contra bot (Commander, 20 a 30 partidas), Hard, Cautious e
 * Reckless ficaram todos perto de 50% contra o Default. Por isso:
 * - fácil: o bot do Forge com erros de propósito (ganhou 5 de 30 ao normal);
 * - normal: o bot do Forge tal como vem;
 * - difícil: perfil Hard, pesquisa Monte Carlo e baralhamentos que lhe dão
 *   melhor mana (16 de 30 ao normal: contra pessoas a pesquisa evita erros
 *   grosseiros, mas bot contra bot quase não se nota).
 */
final class ForgeBots {
    private ForgeBots() { }

    static final String EASY = "easy";
    static final String NORMAL = "normal";
    static final String HARD = "hard";

    static LobbyPlayer create(String name, String difficulty) {
        if (EASY.equals(difficulty)) {
            EasyLobbyPlayer p = new EasyLobbyPlayer(name);
            p.setAiProfile("Default");
            return p;
        }
        return GamePlayerUtil.createAiPlayer(name, 0, HARD.equals(difficulty) ? "Hard" : "Default");
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

    static final class EasyLobbyPlayer extends LobbyPlayerAi {
        EasyLobbyPlayer(String name) { super(name, EnumSet.noneOf(forge.ai.AIOption.class)); }

        @Override
        public Player createIngamePlayer(Game game, int id) {
            Player ai = new Player(getName(), game, id);
            ai.setFirstController(new EasyController(game, ai, this));
            return ai;
        }
    }

    /** Joga sempre os terrenos; o resto às vezes deixa passar, ataca com menos e falha bloqueios. */
    static final class EasyController extends PlayerControllerAi {
        EasyController(Game game, Player p, LobbyPlayer lp) { super(game, p, lp); }

        @Override
        public List<SpellAbility> chooseSpellAbilityToPlay() {
            List<SpellAbility> sas = super.chooseSpellAbilityToPlay();
            if (sas != null && !sas.isEmpty() && !sas.get(0).isLandAbility() && RNG.nextDouble() < skipPlay) {
                return null; // passa a prioridade, o que fecha essa janela
            }
            return sas;
        }

        @Override
        public void declareAttackers(Player attacker, Combat combat) {
            super.declareAttackers(attacker, combat);
            for (Card c : new ArrayList<>(combat.getAttackers())) {
                if (RNG.nextDouble() < dropAttacker) combat.removeFromCombat(c);
            }
        }

        @Override
        public void declareBlockers(Player defender, Combat combat) {
            super.declareBlockers(defender, combat);
            for (Card c : new ArrayList<>(combat.getAllBlockers())) {
                if (RNG.nextDouble() < dropBlocker) combat.removeFromCombat(c);
            }
        }
    }
}
