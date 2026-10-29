package com.juliocr.edhere.forge;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

import forge.LobbyPlayer;
import forge.deck.CardPool;
import forge.game.GameEntityView;
import forge.game.card.CardView;
import forge.game.phase.PhaseType;
import forge.game.player.DelayedReveal;
import forge.game.player.IHasIcon;
import forge.game.player.PlayerView;
import forge.game.spellability.SpellAbilityView;
import forge.game.spellability.StackItemView;
import forge.gamemodes.match.AbstractGuiGame;
import forge.gamemodes.match.input.InputPassPriority;
import forge.gamemodes.match.Selection;
import forge.item.PaperCard;
import forge.localinstance.skin.FSkinProp;
import forge.player.PlayerControllerHuman;
import forge.trackable.TrackableCollection;
import forge.trackable.TrackableObject;
import forge.util.FSerializableFunction;
import forge.util.ITriggerEvent;

/**
 * A interface do Forge para a pessoa que joga, desenhada pelo Flutter.
 *
 * - Prompts (o que o Forge espera: mensagem, botões, cartas a escolher): vão
 *   como evento "prompt", com o estado da mesa nesse momento.
 * - Perguntas (escolher, ordenar, confirmar, distribuir): vão como evento
 *   "ask" e a thread do jogo fica à espera da resposta ([answer]).
 * - Os toques da pessoa chegam por ForgeEngine.act e vão para o controlador
 *   na thread da interface do Forge.
 */
final class EdhereGui extends AbstractGuiGame {
    private final ForgeEngine.Sink sink;
    private final ForgeObserver observer;
    private final AtomicInteger nextAsk = new AtomicInteger(1);
    private final Map<Integer, CompletableFuture<Object>> pending = new ConcurrentHashMap<>();
    private volatile boolean closed;

    // o prompt atual (o Forge manda a mensagem e os botões em chamadas separadas)
    private String promptMessage = "";
    private Integer promptCard;
    private String okLabel = "";
    private String cancelLabel = "";
    private boolean okEnabled;
    private boolean cancelEnabled;

    private final java.util.function.Consumer<forge.game.Game> onGame;

    /** [onGame] corre quando o jogo é criado, antes do mulligan (é o primeiro sítio onde o Game existe). */
    EdhereGui(ForgeEngine.Sink sink, ForgeObserver observer, java.util.function.Consumer<forge.game.Game> onGame) {
        this.sink = sink;
        this.observer = observer;
        this.onGame = onGame;
    }

    @Override
    public void setOriginalGameController(PlayerView view, forge.interfaces.IGameController controller) {
        super.setOriginalGameController(view, controller);
        if (controller instanceof forge.player.PlayerControllerHuman) {
            onGame.accept(((forge.player.PlayerControllerHuman) controller).getGame());
        }
    }

    /** O controlador da pessoa, para os toques. */
    forge.interfaces.IGameController controller() {
        return getGameController();
    }

    // ---------------------------------------------------------------- prompts

    @Override
    public void showPromptMessage(PlayerView player, String message, CardView card) {
        promptMessage = message == null ? "" : message;
        // algumas traduções do Forge deixam o %s do nome por substituir
        if (player != null && promptMessage.contains("%s")) promptMessage = promptMessage.replace("%s", player.getName());
        promptCard = card == null ? null : card.getId();
        emitPrompt();
    }

    @Override
    public void updateButtons(PlayerView owner, String label1, String label2, boolean enable1, boolean enable2, boolean focus1) {
        okLabel = label1 == null ? "" : label1;
        cancelLabel = label2 == null ? "" : label2;
        okEnabled = enable1;
        cancelEnabled = enable2;
        emitPrompt();
    }

    @Override
    public void setSelection(Selection selection) {
        super.setSelection(selection);
        emitPrompt();
    }

    private synchronized void emitPrompt() {
        if (closed) return;
        Map<String, Object> m = observer.snapshotSafe();
        m.put("type", "prompt");
        m.put("msg", promptMessage);
        if (promptCard != null) m.put("pcard", promptCard);
        m.put("ok", button(okLabel, okEnabled));
        m.put("cancel", button(cancelLabel, cancelEnabled));
        Selection sel = getSelection();
        if (sel != null) {
            List<Object> cards = new ArrayList<>();
            List<Object> players = new ArrayList<>();
            List<Object> chosen = new ArrayList<>();
            for (CardView c : sel.cards()) cards.add(c.getId());
            for (TrackableObject t : sel.targets()) {
                if (t instanceof PlayerView) players.add(t.getId());
                else if (t instanceof CardView) cards.add(t.getId());
            }
            for (TrackableObject t : sel.chosen()) chosen.add(t.getId());
            m.put("sel", cards);
            m.put("selP", players);
            m.put("chosen", chosen);
        }
        // o que o Forge destaca: jogáveis (prioridade), fontes de mana (a pagar),
        // atacantes possíveis; "auto" são as fontes que o botão Auto vai virar
        if (!weak.isEmpty()) m.put("play", new ArrayList<>(weak));
        if (!autoTap.isEmpty()) m.put("auto", new ArrayList<>(autoTap));
        // o tipo de pergunta, para a mesa escrever as suas mensagens (as do
        // Forge para a prioridade são "Prioridade: X | Turno: N | Fase: ...")
        m.put("input", inputKind());
        forge.util.Localizer loc = forge.util.Localizer.getInstance();
        if (cancelLabel.startsWith(loc.getMessage("lblUndo"))) m.put("cancelKind", "undo");
        else if (cancelLabel.equals(loc.getMessage("lblEndTurn"))) m.put("cancelKind", "endTurn");
        sink.emit(m);
        observer.markDirty();
    }

    /** priority, mulligan, attack, block, pay, select, wait (o bot a jogar) ou other. */
    private String inputKind() {
        if (!(getGameController() instanceof PlayerControllerHuman)) return "wait";
        Object in = ((PlayerControllerHuman) getGameController()).getInputQueue().getInput();
        if (in == null || in instanceof forge.gamemodes.match.input.InputLockUI) return "wait";
        String n = in.getClass().getSimpleName();
        if (in instanceof InputPassPriority) return "priority";
        // depois do mulligan: escolher as cartas que vão para o fundo (não é "ficas com esta mão?")
        if (n.equals("InputLondonMulligan")) return "bottom";
        if (n.contains("Mulligan")) return "mulligan";
        if (n.equals("InputAttack")) return "attack";
        if (n.equals("InputBlock")) return "block";
        if (n.startsWith("InputPayMana")) return "pay";
        if (n.startsWith("InputSelect")) return "select";
        return "other";
    }

    private final java.util.Set<Integer> weak = new java.util.LinkedHashSet<>();
    private final java.util.Set<Integer> autoTap = new java.util.LinkedHashSet<>();

    /** As cartas que o Forge sugere (com UI_SHOW_ACTIONABLE_HIGHLIGHTS); as repetidas são o plano do Auto. */
    @Override
    public void setWeaklySelectable(Iterable<CardView> cards) {
        super.setWeaklySelectable(cards);
        synchronized (this) {
            weak.clear();
            autoTap.clear();
            for (CardView c : cards) {
                if (!weak.add(c.getId())) autoTap.add(c.getId());
            }
        }
        emitPrompt();
    }

    @Override
    public void clearWeaklySelectable() {
        super.clearWeaklySelectable();
        synchronized (this) {
            weak.clear();
            autoTap.clear();
        }
    }

    private static Map<String, Object> button(String label, boolean enabled) {
        Map<String, Object> b = new HashMap<>();
        b.put("label", label);
        b.put("on", enabled);
        return b;
    }

    // -------------------------------------------------------------- perguntas

    /** Envia uma pergunta e espera pela resposta (na thread do jogo). null = sem resposta (partida parada). */
    private Object ask(Map<String, Object> q) {
        if (closed) return null;
        int id = nextAsk.getAndIncrement();
        CompletableFuture<Object> f = new CompletableFuture<>();
        pending.put(id, f);
        q.put("type", "ask");
        q.put("id", id);
        sink.emit(q);
        try {
            return f.get();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return null;
        } catch (Exception e) {
            return null;
        } finally {
            pending.remove(id);
        }
    }

    void answer(int id, Object value) {
        CompletableFuture<Object> f = pending.get(id);
        if (f != null) f.complete(value);
    }

    /** Liberta a thread do jogo de qualquer pergunta pendente (ao sair da partida). */
    void close() {
        closed = true;
        for (CompletableFuture<Object> f : pending.values()) f.complete(null);
    }

    private static Map<String, Object> question(String kind, String title, String message) {
        Map<String, Object> q = new LinkedHashMap<>();
        q.put("kind", kind);
        if (title != null) q.put("title", title);
        if (message != null) q.put("msg", message);
        return q;
    }

    /** Uma opção para o Flutter: o texto e, se for carta ou jogador, o id. */
    private static <T> Map<String, Object> option(T t, FSerializableFunction<T, String> display) {
        Map<String, Object> o = new HashMap<>();
        String label = display != null ? display.apply(t) : String.valueOf(t);
        if (t instanceof CardView) {
            CardView c = (CardView) t;
            o.put("card", c.getId());
            o.put("n", c.getName());
            if (display == null) label = c.getName();
        } else if (t instanceof PlayerView) {
            o.put("player", ((PlayerView) t).getId());
            if (display == null) label = ((PlayerView) t).getName();
        }
        o.put("label", label);
        return o;
    }

    private static <T> List<Object> options(Collection<T> items, FSerializableFunction<T, String> display) {
        List<Object> out = new ArrayList<>();
        for (T t : items) out.add(option(t, display));
        return out;
    }

    @SuppressWarnings("unchecked")
    private static List<Integer> indices(Object answer) {
        List<Integer> out = new ArrayList<>();
        if (answer instanceof List) {
            for (Object o : (List<Object>) answer) out.add(((Number) o).intValue());
        }
        return out;
    }

    @Override
    public <T> List<T> getChoices(String message, int min, int max, List<T> choices, List<T> selected, FSerializableFunction<T, String> display) {
        if (choices == null || choices.isEmpty()) return new ArrayList<>();
        if (min == 1 && max == 1 && choices.size() == 1) return new ArrayList<>(choices);
        Map<String, Object> q = question("choose", null, message);
        q.put("min", min);
        q.put("max", max);
        q.put("options", options(choices, display));
        if (selected != null) {
            List<Object> pre = new ArrayList<>();
            for (T s : selected) pre.add(choices.indexOf(s));
            q.put("selected", pre);
        }
        List<T> out = new ArrayList<>();
        for (int i : indices(ask(q))) {
            if (i >= 0 && i < choices.size()) out.add(choices.get(i));
        }
        // sem resposta (a partida acabou): o mínimo, para o Forge não rebentar
        while (out.size() < min && out.size() < choices.size()) out.add(choices.get(out.size()));
        return out;
    }

    @Override
    public <T> OrderResult<T> order(String title, String top, int remainingObjectsMin, int remainingObjectsMax,
                                    List<T> sourceChoices, List<T> destChoices, CardView referenceCard,
                                    boolean sideboardingMode, boolean allowRemember) {
        List<T> all = new ArrayList<>(sourceChoices);
        if (destChoices != null) all.addAll(destChoices);
        if (all.size() <= 1) return new OrderResult<>(all, false);
        Map<String, Object> q = question("order", title, top);
        q.put("options", options(all, null));
        List<T> out = new ArrayList<>();
        for (int i : indices(ask(q))) {
            if (i >= 0 && i < all.size() && !out.contains(all.get(i))) out.add(all.get(i));
        }
        for (T t : all) if (!out.contains(t)) out.add(t);
        return new OrderResult<>(out, false);
    }

    @Override
    public List<CardView> manipulateCardList(String title, Iterable<CardView> cards, Iterable<CardView> manipulable,
                                             boolean toTop, boolean toBottom, boolean toAnywhere) {
        List<CardView> all = new ArrayList<>();
        for (CardView c : cards) all.add(c);
        if (all.size() <= 1) return all;
        Map<String, Object> q = question("order", title, null);
        q.put("options", options(all, null));
        List<CardView> out = new ArrayList<>();
        for (int i : indices(ask(q))) {
            if (i >= 0 && i < all.size() && !out.contains(all.get(i))) out.add(all.get(i));
        }
        for (CardView c : all) if (!out.contains(c)) out.add(c);
        return out;
    }

    @Override
    public boolean confirm(CardView c, String question, boolean defaultIsYes, List<String> options) {
        Map<String, Object> q = question("confirm", null, question);
        if (c != null) q.put("card", c.getId());
        List<String> labels = options == null || options.size() < 2 ? null : options;
        if (labels != null) q.put("labels", labels);
        Object a = ask(q);
        return a == null ? defaultIsYes : Boolean.TRUE.equals(a);
    }

    @Override
    public boolean showConfirmDialog(String message, String title, String yesButtonText, String noButtonText, boolean defaultYes) {
        Map<String, Object> q = question("confirm", title, message);
        List<String> labels = new ArrayList<>();
        labels.add(yesButtonText);
        labels.add(noButtonText);
        q.put("labels", labels);
        Object a = ask(q);
        return a == null ? defaultYes : Boolean.TRUE.equals(a);
    }

    @Override
    public int showOptionDialog(String message, String title, FSkinProp icon, List<String> options, int defaultOption) {
        if (options == null || options.isEmpty()) return defaultOption;
        Map<String, Object> q = question("choose", title, message);
        q.put("min", 1);
        q.put("max", 1);
        q.put("options", options(options, null));
        List<Integer> a = indices(ask(q));
        return a.isEmpty() ? defaultOption : a.get(0);
    }

    @Override
    public String showInputDialog(String message, String title, FSkinProp icon, String initialInput, List<String> inputOptions, boolean isNumeric) {
        if (inputOptions != null && !inputOptions.isEmpty()) {
            int i = showOptionDialog(message, title, icon, inputOptions, Math.max(0, inputOptions.indexOf(initialInput)));
            return i >= 0 && i < inputOptions.size() ? inputOptions.get(i) : initialInput;
        }
        Map<String, Object> q = question("input", title, message);
        q.put("initial", initialInput == null ? "" : initialInput);
        q.put("numeric", isNumeric);
        Object a = ask(q);
        return a == null ? initialInput : String.valueOf(a);
    }

    @Override
    public SpellAbilityView getAbilityToPlay(CardView hostCard, List<SpellAbilityView> abilities, ITriggerEvent triggerEvent) {
        if (abilities.isEmpty()) return null;
        if (abilities.size() == 1) return abilities.get(0);
        Map<String, Object> q = question("choose", null, null);
        q.put("min", 0);
        q.put("max", 1);
        q.put("ability", true);
        if (hostCard != null) q.put("card", hostCard.getId());
        q.put("options", options(abilities, null));
        List<Integer> a = indices(ask(q));
        return a.isEmpty() ? null : abilities.get(a.get(0));
    }

    @Override
    public GameEntityView chooseSingleEntityForEffect(String title, List<? extends GameEntityView> optionList, DelayedReveal delayedReveal, boolean isOptional) {
        if (optionList.isEmpty()) return null;
        if (!isOptional && optionList.size() == 1) return optionList.get(0);
        Map<String, Object> q = question("choose", title, null);
        q.put("min", isOptional ? 0 : 1);
        q.put("max", 1);
        q.put("options", options(optionList, null));
        List<Integer> a = indices(ask(q));
        if (a.isEmpty()) return isOptional ? null : optionList.get(0);
        return optionList.get(a.get(0));
    }

    @Override
    public List<GameEntityView> chooseEntitiesForEffect(String title, List<? extends GameEntityView> optionList, int min, int max, DelayedReveal delayedReveal) {
        List<GameEntityView> out = new ArrayList<>();
        if (optionList.isEmpty()) return out;
        Map<String, Object> q = question("choose", title, null);
        q.put("min", min);
        q.put("max", max);
        q.put("options", options(optionList, null));
        for (int i : indices(ask(q))) {
            if (i >= 0 && i < optionList.size()) out.add(optionList.get(i));
        }
        while (out.size() < min && out.size() < optionList.size()) out.add(optionList.get(out.size()));
        return out;
    }

    /**
     * Dano de combate: o dano letal a cada bloqueador pela ordem e o resto ao
     * último (ou ao jogador, se houver atropelar). É o que se faz quase sempre;
     * escolher à mão fica para depois.
     */
    @Override
    public Map<CardView, Integer> assignCombatDamage(CardView attacker, List<CardView> blockers, int damage,
                                                     GameEntityView defender, boolean overrideOrder, boolean maySkip) {
        Map<CardView, Integer> out = new LinkedHashMap<>();
        int left = damage;
        for (int i = 0; i < blockers.size(); i++) {
            CardView b = blockers.get(i);
            boolean last = i == blockers.size() - 1;
            int lethal = Math.max(0, b.getCurrentState().getToughness() - b.getDamage());
            int give = last && defender == null ? left : Math.min(left, lethal);
            out.put(b, give);
            left -= give;
        }
        if (left > 0 && defender instanceof CardView) out.put((CardView) defender, left);
        else if (left > 0 && !blockers.isEmpty() && defender == null) {
            CardView lastB = blockers.get(blockers.size() - 1);
            out.put(lastB, out.get(lastB) + left);
        }
        return out;
    }

    @Override
    public Map<Object, Integer> assignGenericAmount(CardView effectSource, Map<Object, Integer> target, int amount,
                                                    boolean atLeastOne, String amountLabel) {
        List<Object> keys = new ArrayList<>(target.keySet());
        Map<String, Object> q = question("distribute", amountLabel, null);
        if (effectSource != null) q.put("card", effectSource.getId());
        q.put("amount", amount);
        q.put("atLeastOne", atLeastOne);
        q.put("options", options(keys, null));
        Object a = ask(q);
        Map<Object, Integer> out = new LinkedHashMap<>();
        List<Integer> split = indices(a);
        if (split.size() == keys.size()) {
            for (int i = 0; i < keys.size(); i++) out.put(keys.get(i), split.get(i));
        } else {
            // sem resposta: tudo no primeiro (e 1 em cada, se for obrigatório)
            int left = amount;
            for (int i = keys.size() - 1; i >= 1; i--) {
                int give = atLeastOne ? 1 : 0;
                out.put(keys.get(i), give);
                left -= give;
            }
            out.put(keys.get(0), left);
        }
        return out;
    }

    @Override
    public void message(String message, String title) {
        Map<String, Object> m = question("message", title, message);
        m.put("type", "info");
        sink.emit(m);
    }

    @Override
    public void showErrorDialog(String message, String title) {
        message(message, title);
    }

    // -------------------------------------------------------- resto da interface

    /**
     * Onde a pessoa quer parar (com a pilha vazia). O Forge também passa
     * sozinho quando não há nada que se possa fazer (YIELD_AUTO_PASS_NO_ACTIONS).
     */
    @Override
    public boolean isUiSetToSkipPhase(PlayerView playerTurn, PhaseType phase) {
        if (fullControl) return false;
        boolean mine = getLocalPlayers().contains(playerTurn);
        return !(mine ? myStops : theirStops).contains(phase.name());
    }

    /** As paragens (PhaseType) no meu turno e no do bot; por defeito as fases principais e o ataque/fim dele. */
    private volatile java.util.Set<String> myStops = new java.util.HashSet<>(java.util.Arrays.asList("MAIN1", "MAIN2"));
    private volatile java.util.Set<String> theirStops =
            new java.util.HashSet<>(java.util.Arrays.asList("COMBAT_DECLARE_ATTACKERS", "END_OF_TURN"));
    private volatile boolean fullControl;

    void setStops(List<String> mine, List<String> theirs, boolean full) {
        myStops = new java.util.HashSet<>(mine);
        theirStops = new java.util.HashSet<>(theirs);
        fullControl = full;
        // em controlo total o Forge também deixa de passar sozinho quando não há jogadas
        forge.model.FModel.getPreferences().setPref(
                forge.localinstance.properties.ForgePreferences.FPref.YIELD_AUTO_PASS_NO_ACTIONS, !full);
    }

    @Override protected void updateCurrentPlayer(PlayerView player) { }
    @Override public void openView(TrackableCollection<PlayerView> myPlayers) { }
    @Override public void showCombat() { }
    @Override public void flashIncorrectAction() { }
    @Override public void alertUser() { }
    @Override public void finishGame() { }
    @Override public void setPanelSelection(CardView hostCard) { }
    @Override public void setCard(CardView card) { }
    @Override public void setPlayerAvatar(LobbyPlayer player, IHasIcon ihi) { }
    @Override public List<PaperCard> sideboard(CardPool sideboard, CardPool main, String message) { return null; }
}
