import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart' hide Table, Intent;
import 'package:mesa_core/mesa_core.dart';

import '../../app/theme.dart';
import '../../game/game_controller.dart';
import '../cards/card_detail_screen.dart';
import '../widgets/card_view.dart';
import '../widgets/mana.dart';
import 'table_card.dart';

Future<T?> _sheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: builder,
    );

/// Pede um número (para "comprar N", "scry N", etc.).
Future<int?> pickNumber(BuildContext context, String title, {int initial = 1, int max = 20}) {
  var n = initial;
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton.filledTonal(
              onPressed: n > 1 ? () => set(() => n--) : null, icon: const Icon(Icons.remove)),
          SizedBox(
            width: 64,
            child: Text('$n', textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.headlineMedium),
          ),
          IconButton.filledTonal(
              onPressed: n < max ? () => set(() => n++) : null, icon: const Icon(Icons.add)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, n), child: const Text('OK')),
        ],
      ),
    ),
  );
}

Future<int?> pickPlayer(BuildContext context, GameController ctrl, String title, {bool excludeSelf = false}) {
  final players = ctrl.state.players.values.where((p) => !excludeSelf || p.seat != ctrl.actor).toList();
  return showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        for (final p in players)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, p.seat),
            child: Text(p.name, style: const TextStyle(fontSize: 16)),
          ),
      ],
    ),
  );
}

Widget _header(BuildContext context, db.Card? card, CardInstance? inst, {String? subtitle}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 110,
        child: inst != null
            ? TableCardView(instance: inst, card: card, width: 110, showTapped: false)
            : card != null
                ? CardImage(card, preferNormal: true)
                : const CardBack(),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(card?.name ?? inst?.tokenName ?? 'Token',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (card != null) ...[
            const SizedBox(height: 4),
            ManaCost(card.manaCost),
            const SizedBox(height: 4),
            Text(card.typeLine, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            OracleText(
                card.faces.isNotEmpty
                    ? card.faces[(inst?.faceIndex ?? 0).clamp(0, card.faces.length - 1)].oracleText
                    : card.oracleText,
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.labelSmall),
          ],
        ]),
      ),
    ]),
  );
}

ListTile _tile(IconData icon, String text, VoidCallback onTap, {String? subtitle}) => ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(text),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: onTap,
    );

/// Ações sobre uma carta pública (campo, cemitério, exílio, comando).
Future<void> showCardActions(BuildContext context, GameController ctrl, CardInstance c) {
  final card = ctrl.card(c.oracleId, printId: c.printId);
  final mine = ctrl.mySeats.contains(c.controller) || ctrl.mySeats.contains(c.owner);
  final pl = ctrl.state.players[c.owner];
  final tax = c.isCommander ? pl?.commanderTax(c.id) : null;
  return _sheet<void>(context, (ctx) {
    void done(VoidCallback f) {
      Navigator.pop(ctx);
      f();
    }

    final onField = c.zone == Zone.battlefield;
    return ListView(shrinkWrap: true, children: [
      _header(ctx, card, c,
          subtitle: [
            '${c.zone.label} · dono: ${pl?.name ?? '?'}',
            if (c.controller != c.owner) 'controlado por ${ctrl.state.players[c.controller]?.name}',
            if (tax != null) 'Taxa de comandante: +$tax',
          ].join(' · ')),
      if (card != null)
        _tile(Icons.zoom_in, 'Ver carta', () {
          Navigator.pop(ctx);
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CardDetailScreen(card: card)));
        }),
      _tile(Icons.highlight, ctrl.state.highlight == c.id ? 'Tirar destaque' : 'Destacar para todos',
          () => done(() => ctrl.highlight(ctrl.state.highlight == c.id ? null : c))),
      if (mine) ...[
        if (onField) ...[
          if (ctrl.landStack(c).length > 1) ...[
            _tile(
                c.tapped ? Icons.undo : Icons.rotate_90_degrees_cw,
                c.tapped
                    ? 'Desvirar os ${ctrl.landStack(c).length} terrenos'
                    : 'Virar os ${ctrl.landStack(c).length} terrenos (tap)',
                () => done(() => ctrl.toggleTap(c))),
            _tile(
                c.tapped ? Icons.undo : Icons.rotate_90_degrees_cw,
                c.tapped ? 'Desvirar só esta' : 'Virar só esta',
                () => done(() => ctrl.toggleTap(c, single: true))),
          ] else
            _tile(c.tapped ? Icons.undo : Icons.rotate_90_degrees_cw, c.tapped ? 'Desvirar' : 'Virar (tap)',
                () => done(() => ctrl.toggleTap(c))),
          _tile(Icons.exposure, 'Contadores', () {
            Navigator.pop(ctx);
            showCounterSheet(context, ctrl, c);
          }),
          if ((card?.faces.length ?? 0) > 1)
            _tile(Icons.flip, 'Transformar (outra face)',
                () => done(() => ctrl.send(Intent(Ev.flip, {'id': c.id})))),
          _tile(Icons.flip_to_back, c.faceDown ? 'Virar para cima' : 'Virar para baixo',
              () => done(() => ctrl.send(Intent(Ev.faceDown, {'id': c.id, 'value': !c.faceDown})))),
          _tile(Icons.link, c.attachedTo == null ? 'Anexar a…' : 'Desanexar', () async {
            Navigator.pop(ctx);
            if (c.attachedTo != null) {
              ctrl.send(Intent(Ev.attach, {'id': c.id, 'to': null}));
              return;
            }
            final target = await _pickFieldCard(context, ctrl, exclude: c.id, title: 'Anexar a');
            if (target != null) ctrl.send(Intent(Ev.attach, {'id': c.id, 'to': target.id}));
          }),
          _tile(Icons.gps_fixed, 'Apontar para… (carta ou jogador)', () {
            Navigator.pop(ctx);
            showTargetPicker(context, ctrl, from: c.id);
          }),
          _tile(Icons.swap_horiz, 'Dar o controlo a…', () async {
            Navigator.pop(ctx);
            final seat = await pickPlayer(context, ctrl, 'Novo controlador');
            if (seat != null) ctrl.send(Intent(Ev.control, {'id': c.id, 'seat': seat}));
          }),
          _tile(
              Icons.content_copy,
              'Duplicar como token',
              () => done(() => ctrl.send(ctrl.table.createToken(ctrl.actor,
                  oracleId: c.oracleId,
                  name: c.tokenName,
                  pt: c.tokenPt,
                  x: (c.x + 0.05).clamp(0, 1),
                  y: (c.y + 0.05).clamp(0, 1),
                  copyOf: c.id)))),
          if (c.isToken)
            _tile(Icons.layers, 'Quantidade (${c.stackQty})', () async {
              Navigator.pop(ctx);
              final n = await pickNumber(context, 'Quantidade', initial: c.stackQty, max: 999);
              if (n != null) ctrl.send(Intent(Ev.tokenQty, {'id': c.id, 'qty': n}));
            }),
          if (c.isToken && c.stackQty > 1)
            _tile(Icons.call_split, 'Separar da pilha…', () async {
              Navigator.pop(ctx);
              final n = await pickNumber(context, 'Quantos separar?', initial: 1, max: c.stackQty - 1);
              if (n != null) ctrl.splitStack(c, n);
            }, subtitle: 'Por exemplo, para atacar só com alguns'),
        ],
        const Divider(),
        for (final z in [Zone.battlefield, Zone.hand, Zone.graveyard, Zone.exile, Zone.command])
          if (z != c.zone && (z != Zone.command || c.isCommander || ctrl.state.format == 'free'))
            _tile(_zoneIcon(z), 'Para ${_zoneWithArticle(z)}', () {
              Navigator.pop(ctx);
              moveMaybeToCommand(context, ctrl, c, z);
            }),
        _tile(Icons.vertical_align_top, 'Para o topo do grimório', () {
          Navigator.pop(ctx);
          moveMaybeToCommand(context, ctrl, c, Zone.library);
        }),
        _tile(Icons.vertical_align_bottom, 'Para o fundo do grimório', () {
          Navigator.pop(ctx);
          moveMaybeToCommand(context, ctrl, c, Zone.library, pos: 'bottom');
        }),
      ],
    ]);
  });
}

/// Move uma carta pública. Se for um comandante a ir para o cemitério,
/// exílio, mão ou grimório, pergunta se vai antes para a zona de comando
/// (regra do Commander).
Future<void> moveMaybeToCommand(BuildContext context, GameController ctrl, CardInstance c, Zone to,
    {String pos = 'top'}) async {
  const leaving = {Zone.graveyard, Zone.exile, Zone.hand, Zone.library};
  if (!c.isCommander || !leaving.contains(to)) {
    ctrl.moveCard(c, to, pos: pos);
    return;
  }
  final name = ctrl.card(c.oracleId, printId: c.printId)?.frontName ?? 'O comandante';
  final command = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.star_rounded, color: Colors.amber),
      title: Text('$name vai para ${_zoneWithArticle(to)}'),
      content: const Text('Na regra do Commander, o dono pode pô-lo na zona de comando em vez disso.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Para ${_zoneWithArticle(to)}')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Zona de comando')),
      ],
    ),
  );
  if (command == null) return;
  ctrl.moveCard(c, command ? Zone.command : to, pos: pos);
}

String _zoneWithArticle(Zone z) => switch (z) {
      Zone.battlefield => 'o campo',
      Zone.hand => 'a mão',
      Zone.graveyard => 'o cemitério',
      Zone.exile => 'o exílio',
      Zone.command => 'a zona de comando',
      Zone.library => 'o grimório',
    };

IconData _zoneIcon(Zone z) => switch (z) {
      Zone.battlefield => Icons.dashboard_outlined,
      Zone.hand => Icons.back_hand_outlined,
      Zone.graveyard => Icons.delete_outline,
      Zone.exile => Icons.block,
      Zone.command => Icons.star_outline,
      Zone.library => Icons.layers_outlined,
    };

Future<CardInstance?> _pickFieldCard(BuildContext context, GameController ctrl,
    {required int exclude, required String title}) {
  final cards = ctrl.state.cards.values.where((c) => c.zone == Zone.battlefield && c.id != exclude).toList()
    ..sort((a, b) => a.controller.compareTo(b.controller));
  return _sheet<CardInstance>(
      context,
      (ctx) => ListView(shrinkWrap: true, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final c in cards)
              ListTile(
                leading: SizedBox(
                    width: 36,
                    child: TableCardView(
                        instance: c,
                        card: ctrl.card(c.oracleId, printId: c.printId),
                        width: 36,
                        showTapped: false)),
                title: Text(ctrl.card(c.oracleId, printId: c.printId)?.name ?? c.tokenName ?? 'Token'),
                subtitle: Text(ctrl.state.players[c.controller]?.name ?? ''),
                onTap: () => Navigator.pop(ctx, c),
              ),
          ]));
}

/// Escolher um alvo: um jogador ou uma carta no campo de qualquer jogador.
/// O alvo fica destacado para todos e entra no registo.
Future<void> showTargetPicker(BuildContext context, GameController ctrl, {int? from}) {
  final s = ctrl.state;
  final seats = s.players.keys.toList()..sort();
  return _sheet<void>(context, (ctx) {
    final theme = Theme.of(ctx);
    void pick(Map<String, dynamic> target) {
      Navigator.pop(ctx);
      ctrl.send(Intent(Ev.arrow, {if (from != null) 'from': from, ...target}));
    }

    return SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.75,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
        Text('Apontar para…', style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        Text('Jogadores', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final seat in seats)
            ActionChip(
              avatar: const Icon(Icons.person, size: 18),
              label: Text('${s.players[seat]!.name} (${s.players[seat]!.life})'),
              onPressed: () => pick({'seat': seat}),
            ),
        ]),
        for (final seat in seats)
          if (s.zoneCards(seat, Zone.battlefield).where((c) => c.id != from).isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Campo de ${s.players[seat]!.name}', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              childAspectRatio: cardAspect,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final c in s.zoneCards(seat, Zone.battlefield))
                  if (c.id != from)
                    GestureDetector(
                      onTap: () => pick({'to': c.id}),
                      child: LayoutBuilder(
                        builder: (_, k) => TableCardView(
                            instance: c,
                            card: ctrl.card(c.oracleId, printId: c.printId),
                            width: k.maxWidth,
                            showTapped: false),
                      ),
                    ),
              ],
            ),
          ],
      ]),
    );
  });
}

/// Habilidades comuns que se podem dar a uma carta (equipamentos, auras...).
const grantableAbilities = [
  'Flying',
  'First strike',
  'Double strike',
  'Deathtouch',
  'Lifelink',
  'Vigilance',
  'Trample',
  'Haste',
  'Hexproof',
  'Indestructible',
  'Menace',
  'Reach',
  'Defender',
  'Ward',
  'Shroud',
  'Protection',
  'Infect',
  'Unblockable',
];

/// Contadores, modificadores de poder/resistência e habilidades de uma carta.
/// Os valores tocam-se para escrever um número diretamente.
Future<void> showCounterSheet(BuildContext context, GameController ctrl, CardInstance c) {
  const kinds = [
    CounterKind.plus,
    CounterKind.minus,
    CounterKind.loyalty,
    'charge',
    'shield',
    'stun',
    'oil',
    'time',
    'lore',
    'flood',
    'doom',
    'rad',
  ];
  return _sheet<void>(
      context,
      (ctx) => ListenableBuilder(
            listenable: ctrl,
            builder: (ctx, _) {
              final cur = ctrl.state.cards[c.id];
              if (cur == null) return const SizedBox.shrink();
              final theme = Theme.of(ctx);
              final card = ctrl.card(cur.oracleId, printId: cur.printId);
              final pt = effectivePt(cur, card);
              final extra = cur.counters.keys
                  .where((k) =>
                      !kinds.contains(k) && !k.startsWith('mod:') && !k.startsWith(CounterKind.keyword))
                  .toList();

              void setValue(String kind, int v) =>
                  ctrl.send(Intent(Ev.counter, {'id': cur.id, 'kind': kind, 'value': v}));

              Future<void> edit(String kind, String label, {bool signed = false}) async {
                final v = await pickValue(ctx, label, initial: cur.counters[kind] ?? 0, signed: signed);
                if (v != null) setValue(kind, v);
              }

              Widget stepper(String kind, String label, {Widget? leading, bool signed = false}) {
                final v = cur.counters[kind] ?? 0;
                return ListTile(
                  dense: true,
                  leading: leading,
                  title: Text(label),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      onPressed: signed || v > 0 ? () => ctrl.counter(cur, kind, -1) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    InkWell(
                      onTap: () => edit(kind, label, signed: signed),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 48,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outline),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(signed && v > 0 ? '+$v' : '$v',
                            textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                      ),
                    ),
                    IconButton(
                        onPressed: () => ctrl.counter(cur, kind, 1),
                        icon: const Icon(Icons.add_circle_outline)),
                  ]),
                );
              }

              Widget icon(String kind) {
                final i = counterIconFor(kind);
                return i == null ? const SizedBox(width: 24) : ManaIcon(i, size: 22);
              }

              Future<void> addOther() async {
                final text = TextEditingController();
                final kind = await showDialog<String>(
                  context: ctx,
                  builder: (d) => AlertDialog(
                    title: const Text('Outro contador'),
                    content: TextField(
                      controller: text,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: 'Ex.: page, verse, fuse'),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
                      TextButton(
                        onPressed: () => Navigator.pop(d, text.text.trim().toLowerCase()),
                        child: const Text('Juntar'),
                      ),
                    ],
                  ),
                );
                if (kind != null && kind.isNotEmpty) ctrl.counter(cur, kind, 1);
              }

              return SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.8,
                child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Row(children: [
                      Expanded(
                        child:
                            Text(card?.name ?? cur.tokenName ?? 'Carta', style: theme.textTheme.titleMedium),
                      ),
                      if (pt != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                pt.$2 ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(pt.$1,
                              style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: pt.$2 ? theme.colorScheme.onPrimary : null)),
                        ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text('Poder e resistência (equipamentos, efeitos)',
                        style: theme.textTheme.labelLarge),
                  ),
                  stepper(CounterKind.modPower, 'Poder ±', signed: true, leading: const Icon(Icons.flash_on)),
                  stepper(CounterKind.modToughness, 'Resistência ±',
                      signed: true, leading: const Icon(Icons.shield_outlined)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text('Contadores', style: theme.textTheme.labelLarge),
                  ),
                  for (final k in [...kinds, ...extra]) stepper(k, k, leading: icon(k)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: addOther,
                        icon: const Icon(Icons.add),
                        label: const Text('Outro contador'),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text('Habilidades dadas por efeitos', style: theme.textTheme.labelLarge),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final kw in grantableAbilities)
                        Builder(builder: (_) {
                          final key = '${CounterKind.keyword}$kw';
                          final on = (cur.counters[key] ?? 0) > 0;
                          final ic = abilityIconFor(kw);
                          return FilterChip(
                            selected: on,
                            avatar: ic == null ? null : ManaIcon(ic, size: 18),
                            label: Text(kw),
                            onSelected: (v) => setValue(key, v ? 1 : 0),
                          );
                        }),
                    ]),
                  ),
                ]),
              );
            },
          ));
}

/// Pede um número inteiro escrevendo-o (aceita negativos se [signed]).
Future<int?> pickValue(BuildContext context, String title, {int initial = 0, bool signed = false}) {
  final ctrl = TextEditingController(text: '$initial');
  int? parse(String v) => int.tryParse(v.replaceAll('+', '').trim());
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(signed: signed),
        onSubmitted: (v) => Navigator.pop(ctx, parse(v)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(ctx, parse(ctrl.text)), child: const Text('OK')),
      ],
    ),
  );
}

/// Ações sobre uma carta da minha mão.
Future<void> showHandCardActions(BuildContext context, GameController ctrl, PrivateCard pc) {
  final card = ctrl.card(pc.oracleId, printId: pc.printId);
  return _sheet<void>(context, (ctx) {
    void done(VoidCallback f) {
      Navigator.pop(ctx);
      f();
    }

    final isInstant =
        card != null && (card.frontType.contains('Instant') || card.frontType.contains('Sorcery'));
    return ListView(shrinkWrap: true, children: [
      _header(ctx, card, null),
      if (isInstant)
        _tile(Icons.flash_on, 'Lançar (vai para o cemitério)',
            () => done(() => ctrl.playFromHand(pc, to: Zone.graveyard))),
      _tile(Icons.dashboard_outlined, 'Jogar para o campo', () => done(() => ctrl.playFromHand(pc))),
      _tile(Icons.flip_to_back, 'Jogar virada para baixo',
          () => done(() => ctrl.playFromHand(pc, faceDown: true))),
      _tile(Icons.delete_outline, 'Descartar', () => done(() => ctrl.playFromHand(pc, to: Zone.graveyard))),
      _tile(Icons.block, 'Exilar', () => done(() => ctrl.playFromHand(pc, to: Zone.exile))),
      _tile(Icons.vertical_align_top, 'Pôr no topo do grimório',
          () => done(() => ctrl.playFromHand(pc, to: Zone.library))),
      _tile(Icons.vertical_align_bottom, 'Pôr no fundo do grimório',
          () => done(() => ctrl.playFromHand(pc, to: Zone.library, pos: 'bottom'))),
      _tile(
          Icons.visibility,
          'Revelar a todos',
          () => done(() =>
              ctrl.send(ctrl.table.revealHidden(ctrl.actor, Zone.hand, [pc.pid], what: 'uma carta da mão')))),
      if (card != null)
        _tile(Icons.zoom_in, 'Ver carta', () {
          Navigator.pop(ctx);
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CardDetailScreen(card: card)));
        }),
    ]);
  });
}

/// Menu do grimório: comprar, baralhar, scry, surveil, mill, procurar...
Future<void> showLibraryMenu(BuildContext context, GameController ctrl) {
  final seat = ctrl.actor;
  return _sheet<void>(context, (ctx) {
    Future<void> withN(String title, void Function(int n) f, {int initial = 1}) async {
      Navigator.pop(ctx);
      final n = await pickNumber(context, title, initial: initial);
      if (n != null) f(n);
    }

    final t = ctrl.table;
    return ListView(shrinkWrap: true, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text('Grimório (${ctrl.state.players[seat]?.libraryCount ?? 0})',
            style: Theme.of(ctx).textTheme.titleMedium),
      ),
      _tile(Icons.add_card, 'Comprar 1', () {
        Navigator.pop(ctx);
        ctrl.draw();
      }),
      _tile(Icons.library_add, 'Comprar N…', () => withN('Comprar', ctrl.draw)),
      _tile(Icons.shuffle, 'Baralhar', () {
        Navigator.pop(ctx);
        ctrl.send(t.shuffle(seat));
      }),
      _tile(Icons.remove_red_eye_outlined, 'Scry N…',
          () => withN('Scry', (n) => showScrySheet(context, ctrl, n, kind: 'scry'))),
      _tile(Icons.manage_search, 'Surveil N…',
          () => withN('Surveil', (n) => showScrySheet(context, ctrl, n, kind: 'surveil'))),
      _tile(Icons.visibility_outlined, 'Ver o topo (só eu)…',
          () => withN('Ver o topo', (n) => showScrySheet(context, ctrl, n, kind: 'look'))),
      _tile(Icons.campaign_outlined, 'Revelar o topo a todos', () {
        Navigator.pop(ctx);
        final top = ctrl.zones(seat).library.firstOrNull;
        if (top != null) ctrl.send(t.revealHidden(seat, Zone.library, [top.pid], what: 'o topo do grimório'));
      }),
      _tile(Icons.delete_sweep_outlined, 'Mill N…', () => withN('Mill', (n) => ctrl.send(t.mill(seat, n)))),
      _tile(Icons.block, 'Exilar o topo', () {
        Navigator.pop(ctx);
        ctrl.send(t.mill(seat, 1, to: Zone.exile));
      }),
      _tile(Icons.search, 'Procurar uma carta', () {
        Navigator.pop(ctx);
        showLibrarySearch(context, ctrl);
      }),
      _tile(Icons.refresh, 'Mulligan (London)', () async {
        Navigator.pop(ctx);
        ctrl.mulligan();
        final count = ctrl.mulligans[seat] ?? 0;
        // O primeiro mulligan é grátis em formatos multijogador de Commander.
        final free = ctrl.state.format != 'free' &&
            const {'commander', 'brawl', 'paupercommander', 'oathbreaker'}.contains(ctrl.state.format);
        final toBottom = free ? count - 1 : count;
        if (toBottom > 0 && context.mounted) await showBottomPicker(context, ctrl, toBottom);
      }),
    ]);
  });
}

/// Escolher N cartas da mão para o fundo (depois do mulligan).
Future<void> showBottomPicker(BuildContext context, GameController ctrl, int n) {
  final chosen = <int>{};
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => ListenableBuilder(
        listenable: ctrl,
        builder: (ctx, _) => StatefulBuilder(builder: (ctx, set) {
              final hand = ctrl.zones(ctrl.actor).hand;
              return AlertDialog(
                title: Text('Escolhe $n para o fundo'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 4,
                    childAspectRatio: cardAspect,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    children: [
                      for (final pc in hand)
                        GestureDetector(
                          onTap: () => set(() => chosen.contains(pc.pid)
                              ? chosen.remove(pc.pid)
                              : (chosen.length < n ? chosen.add(pc.pid) : null)),
                          child: Opacity(
                            opacity: chosen.contains(pc.pid) ? 0.4 : 1,
                            child: ctrl.card(pc.oracleId, printId: pc.printId) == null
                                ? const CardBack()
                                : CardImage(ctrl.card(pc.oracleId, printId: pc.printId)!, radius: 4),
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: chosen.length == n && chosen.every((p) => hand.any((c) => c.pid == p))
                        ? () {
                            Navigator.pop(ctx);
                            ctrl.send(ctrl.table.bottom(ctrl.actor, chosen.toList()));
                          }
                        : null,
                    child: Text('Confirmar (${chosen.length}/$n)'),
                  ),
                ],
              );
            })),
  );
}

/// Scry, surveil ou só ver o topo: reordenar e decidir onde fica cada carta.
Future<void> showScrySheet(BuildContext context, GameController ctrl, int n, {required String kind}) {
  final seat = ctrl.actor;
  final top = ctrl.zones(seat).library.take(n).toList();
  final where = {for (final c in top) c.pid: 'top'};
  final order = [...top];
  return _sheet<void>(
      context,
      (ctx) => StatefulBuilder(builder: (ctx, set) {
            final altLabel = kind == 'surveil' ? 'Cemitério' : 'Fundo';
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  kind == 'look'
                      ? 'Topo do grimório (só tu vês)'
                      : '${kind == 'scry' ? 'Scry' : 'Surveil'} $n · arrasta para ordenar (o primeiro fica no topo)',
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
              ),
              Flexible(
                child: ReorderableListView(
                  shrinkWrap: true,
                  onReorder: (a, b) => set(() {
                    if (b > a) b--;
                    order.insert(b, order.removeAt(a));
                  }),
                  children: [
                    for (final pc in order)
                      ListTile(
                        key: ValueKey(pc.pid),
                        leading: SizedBox(
                          width: 40,
                          child: ctrl.card(pc.oracleId, printId: pc.printId) == null
                              ? const CardBack()
                              : CardImage(ctrl.card(pc.oracleId, printId: pc.printId)!, radius: 3),
                        ),
                        title: Text(ctrl.cardName(pc.oracleId)),
                        trailing: kind == 'look'
                            ? null
                            : SegmentedButton<String>(
                                showSelectedIcon: false,
                                segments: [
                                  const ButtonSegment(value: 'top', label: Text('Topo')),
                                  ButtonSegment(value: 'alt', label: Text(altLabel)),
                                ],
                                selected: {where[pc.pid] == 'top' ? 'top' : 'alt'},
                                onSelectionChanged: (s) => set(() => where[pc.pid] = s.first),
                              ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (kind == 'look') {
                      // Só reordena o topo, sem dizer nada aos outros.
                      ctrl.send(ctrl.table.scryDone(seat, top: [for (final c in order) c.pid], kind: 'look'));
                      return;
                    }
                    final keep = [
                      for (final c in order)
                        if (where[c.pid] == 'top') c.pid
                    ];
                    final alt = [
                      for (final c in order)
                        if (where[c.pid] != 'top') c.pid
                    ];
                    ctrl.send(kind == 'surveil'
                        ? ctrl.table.scryDone(seat, top: keep, graveyard: alt, kind: 'surveil')
                        : ctrl.table.scryDone(seat, top: keep, bottom: alt));
                  },
                  child: const Text('Concluir'),
                ),
              ),
            ]);
          }));
}

/// Procurar no grimório (tutor): escolher uma carta e para onde vai.
Future<void> showLibrarySearch(BuildContext context, GameController ctrl) {
  final seat = ctrl.actor;
  var filter = '';
  return _sheet<void>(
      context,
      (ctx) => StatefulBuilder(builder: (ctx, set) {
            final lib = [...ctrl.zones(seat).library]
              ..sort((a, b) => ctrl.cardName(a.oracleId).compareTo(ctrl.cardName(b.oracleId)));
            final shown = lib
                .where((c) =>
                    filter.isEmpty ||
                    ctrl.cardName(c.oracleId).toLowerCase().contains(filter.toLowerCase()) ||
                    (ctrl
                            .card(c.oracleId, printId: c.printId)
                            ?.typeLine
                            .toLowerCase()
                            .contains(filter.toLowerCase()) ??
                        false))
                .toList();
            return SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.8,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search), hintText: 'Nome ou tipo (ex.: land)'),
                    onChanged: (v) => set(() => filter = v),
                  ),
                ),
                Expanded(
                  child: ListView(children: [
                    for (final pc in shown)
                      if (ctrl.card(pc.oracleId, printId: pc.printId) case final card?)
                        CardTile(card, onTap: () async {
                          final to = await showDialog<String>(
                            context: ctx,
                            builder: (d) => SimpleDialog(title: Text(card.name), children: [
                              for (final (k, l) in const [
                                ('hand', 'Para a mão'),
                                ('battlefield', 'Para o campo'),
                                ('top', 'Para o topo'),
                                ('graveyard', 'Para o cemitério'),
                                ('exile', 'Para o exílio'),
                              ])
                                SimpleDialogOption(onPressed: () => Navigator.pop(d, k), child: Text(l)),
                            ]),
                          );
                          if (to == null || !ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (to == 'top') {
                            ctrl.send(ctrl.table.shuffle(seat));
                            // Depois de baralhar, a carta procurada vai para o topo.
                            ctrl.send(ctrl.table.scryDone(seat, top: [pc.pid], kind: 'look'));
                          } else {
                            ctrl.fromLibrary(pc, Zone.byId(to));
                            ctrl.send(ctrl.table.shuffle(seat));
                          }
                        }),
                  ]),
                ),
              ]),
            );
          }));
}

/// Lista de uma zona pública (cemitério, exílio, comando) de um jogador.
Future<void> showZoneList(BuildContext context, GameController ctrl, int seat, Zone zone) {
  var hadCards = ctrl.state.zoneCards(seat, zone).isNotEmpty;
  return _sheet<void>(
      context,
      (ctx) => ListenableBuilder(
            listenable: ctrl,
            builder: (ctx, _) {
              final cards = ctrl.state.zoneCards(seat, zone).toList().reversed.toList();
              if (cards.isEmpty && hadCards) {
                // Saiu a última carta: a lista vazia já não serve para nada.
                hadCards = false;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (ctx.mounted) Navigator.of(ctx).maybePop();
                });
              }
              return SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.6,
                child: Column(children: [
                  Text('${zone.label} de ${ctrl.state.players[seat]?.name} (${cards.length})',
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Expanded(
                    child: cards.isEmpty
                        ? const Center(child: Text('Vazio'))
                        : GridView.count(
                            padding: const EdgeInsets.all(12),
                            crossAxisCount: 4,
                            childAspectRatio: cardAspect,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            children: [
                              for (final c in cards)
                                GestureDetector(
                                  onTap: () => showCardActions(context, ctrl, c),
                                  child: LayoutBuilder(
                                    builder: (_, k) => TableCardView(
                                        instance: c,
                                        card: ctrl.card(c.oracleId, printId: c.printId),
                                        width: k.maxWidth,
                                        showTapped: false),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ]),
              );
            },
          ));
}

/// Vida, dano de comandante e contadores de um jogador.
Future<void> showPlayerSheet(BuildContext context, GameController ctrl, int seat) {
  return _sheet<void>(
      context,
      (ctx) => ListenableBuilder(
            listenable: ctrl,
            builder: (ctx, _) {
              final s = ctrl.state;
              final p = s.players[seat]!;
              final theme = Theme.of(ctx);
              final enemyCommanders = s.cards.values.where((c) => c.isCommander && c.owner != seat).toList();
              Widget stepper(String label, int value, void Function(int) change, {Widget? leading}) =>
                  ListTile(
                    dense: true,
                    leading: leading,
                    title: Text(label),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(onPressed: () => change(-1), icon: const Icon(Icons.remove_circle_outline)),
                      SizedBox(
                          width: 32,
                          child: Text('$value',
                              textAlign: TextAlign.center, style: theme.textTheme.titleMedium)),
                      IconButton(onPressed: () => change(1), icon: const Icon(Icons.add_circle_outline)),
                    ]),
                  );
              return ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 16), children: [
                Center(child: Text(p.name, style: theme.textTheme.titleLarge)),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (final d in [-5, -1])
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(56, 48)),
                        onPressed: () => ctrl.life(seat, d),
                        child: Text('$d'),
                      ),
                    ),
                  SizedBox(
                    width: 96,
                    child: Text('${p.life}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  for (final d in [1, 5])
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(56, 48)),
                        onPressed: () => ctrl.life(seat, d),
                        child: Text('+$d'),
                      ),
                    ),
                ]),
                if (enemyCommanders.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text('Dano de comandante (desconta na vida)', style: theme.textTheme.titleSmall),
                  ),
                  for (final c in enemyCommanders)
                    stepper(
                      '${ctrl.card(c.oracleId, printId: c.printId)?.frontName ?? '?'} (${s.players[c.owner]?.name})',
                      p.commanderDamage[c.id] ?? 0,
                      (d) => ctrl.commanderDamage(seat, c.id, d),
                      leading: Icon(Icons.star_rounded,
                          color: (p.commanderDamage[c.id] ?? 0) >= 21 ? EdhColors.bad : Colors.amber),
                    ),
                ],
                const Divider(),
                for (final (k, l) in const [
                  (PlayerCounter.poison, 'Veneno'),
                  (PlayerCounter.energy, 'Energia'),
                  (PlayerCounter.experience, 'Experiência'),
                  (PlayerCounter.rad, 'Rad'),
                ])
                  stepper(l, p.counters[k] ?? 0, (d) => ctrl.playerCounter(seat, k, d)),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.gps_fixed, color: targetGlow),
                  title: const Text('Apontar para este jogador'),
                  onTap: () {
                    Navigator.pop(ctx);
                    ctrl.send(Intent(Ev.arrow, {'seat': seat}));
                  },
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Monarca'),
                  value: s.monarch == seat,
                  onChanged: (v) => ctrl.send(Intent(Ev.monarch, {'seat': v ? seat : null})),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Iniciativa'),
                  value: s.initiative == seat,
                  onChanged: (v) => ctrl.send(Intent(Ev.initiative, {'seat': v ? seat : null})),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text("Bênção da cidade (City's Blessing)"),
                  value: (p.counters[PlayerCounter.blessing] ?? 0) > 0,
                  onChanged: (v) => ctrl.playerCounter(seat, PlayerCounter.blessing, v ? 1 : -1),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Derrotado'),
                  value: p.defeated,
                  onChanged: (v) => ctrl.send(Intent(Ev.defeated, {'seat': seat, 'value': v})),
                ),
              ]);
            },
          ));
}

/// Criar tokens: os que o deck cria, os mais comuns, da base ou personalizados.
Future<void> showTokenSheet(BuildContext context, GameController ctrl) {
  final name = TextEditingController();
  final pt = TextEditingController();
  var qty = 1;
  var query = '';
  final fromDeck = ctrl.deckTokens(ctrl.actor);
  final common = [
    for (final h in db.commonTokens)
      if (ctrl.repo.tokenNamed(h) case final t?)
        if (!fromDeck.any((d) => d.oracleId == t.oracleId)) t,
  ];
  String ptOf(db.Card c) => c.power == null ? '' : ' ${c.power}/${c.toughness}';
  return _sheet<void>(
      context,
      (ctx) => StatefulBuilder(builder: (ctx, set) {
            final theme = Theme.of(ctx);
            // Há muitas versões do mesmo token: mostra uma por nome, tipo, P/R e texto.
            final results = <String, db.Card>{};
            if (query.trim().isNotEmpty) {
              for (final c in ctrl.repo.search('$query is:token', limit: 80).cards) {
                results.putIfAbsent('${c.name}|${c.typeLine}|${ptOf(c)}|${c.oracleText}', () => c);
              }
            }
            void create({String? oracleId, String? n, String? p}) {
              Navigator.pop(ctx);
              ctrl.send(ctrl.table
                  .createToken(ctrl.actor, oracleId: oracleId, name: n, pt: p, qty: qty, x: 0.5, y: 0.5));
            }

            Widget chips(String title, List<db.Card> tokens) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final t in tokens)
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 16),
                          label: Text('${t.name}${ptOf(t)}'),
                          tooltip: t.oracleText.isEmpty ? null : t.oracleText,
                          onPressed: () => create(oracleId: t.oracleId),
                        ),
                    ]),
                  ]),
                );

            return SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.85,
              child: Column(children: [
                Text('Criar token', style: theme.textTheme.titleMedium),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('Quantidade'),
                  IconButton(
                      onPressed: qty > 1 ? () => set(() => qty--) : null, icon: const Icon(Icons.remove)),
                  Text('$qty', style: theme.textTheme.titleMedium),
                  IconButton(onPressed: () => set(() => qty++), icon: const Icon(Icons.add)),
                ]),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search), hintText: 'Procurar token (ex.: treasure, soldier)'),
                    onChanged: (v) => set(() => query = v),
                  ),
                ),
                Expanded(
                  child: ListView(children: [
                    if (query.trim().isEmpty) ...[
                      if (fromDeck.isNotEmpty) chips('Do teu deck', fromDeck),
                      if (common.isNotEmpty) chips('Comuns', common),
                    ],
                    for (final c in results.values)
                      CardTile(c,
                          onTap: () => create(oracleId: c.oracleId),
                          subtitle: [
                            '${c.typeLine}${ptOf(c)}',
                            if (c.oracleText.isNotEmpty) c.oracleText.replaceAll('\n', ' '),
                          ].join(' · ')),
                  ]),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(children: [
                    Expanded(
                        child: TextField(
                            controller: name, decoration: const InputDecoration(labelText: 'Personalizado'))),
                    const SizedBox(width: 8),
                    SizedBox(
                        width: 72,
                        child:
                            TextField(controller: pt, decoration: const InputDecoration(labelText: 'P/R'))),
                    IconButton.filled(
                      onPressed: () => create(
                          n: name.text.trim().isEmpty ? 'Token' : name.text.trim(),
                          p: pt.text.trim().isEmpty ? null : pt.text.trim()),
                      icon: const Icon(Icons.add),
                    ),
                  ]),
                ),
              ]),
            );
          }));
}

Future<void> showLogSheet(BuildContext context, GameController ctrl) {
  return _sheet<void>(
      context,
      (ctx) => ListenableBuilder(
            listenable: ctrl,
            builder: (ctx, _) {
              final log = ctrl.state.log.reversed.toList();
              return SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.7,
                child: Column(children: [
                  Text('Registo', style: Theme.of(ctx).textTheme.titleMedium),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: log.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                              width: 44,
                              child: Text('#${log[i].seq}',
                                  style: Theme.of(ctx)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant))),
                          Expanded(child: Text(ctrl.logText(log[i]))),
                        ]),
                      ),
                    ),
                  ),
                ]),
              );
            },
          ));
}

Future<void> showRevealDialog(BuildContext context, GameController ctrl, Reveal r) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${ctrl.state.players[r.seat]?.name} revelou ${r.what}'),
      content: SizedBox(
        width: double.maxFinite,
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: r.oracleIds.length == 1 ? 1 : 3,
          childAspectRatio: cardAspect,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (final o in r.oracleIds)
              if (ctrl.card(o) case final c?) CardImage(c, preferNormal: true) else const CardBack(),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}
