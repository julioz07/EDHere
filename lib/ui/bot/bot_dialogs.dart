import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';

import '../../bot/forge_table.dart';
import '../../l10n/l10n.dart';
import '../widgets/card_view.dart';
import '../widgets/mana.dart';

/// Mostra uma pergunta do Forge e devolve a resposta no formato que o
/// EdhereGui espera: índices (choose, order, distribute), bool (confirm) ou
/// texto (input). O Forge fica parado até haver resposta, por isso o diálogo
/// não se fecha sem responder.
Future<Object?> showForgeAsk(BuildContext context, ForgeAsk ask, ForgeCardLookup lookup, ForgeTableState? state) {
  db.Card? cardOf(ForgeOption o) {
    if (o.cardId != null) {
      final onTable = state?.card(o.cardId!);
      if (onTable?.card != null) return onTable!.card;
    }
    return o.cardName == null ? null : lookup.byName(o.cardName!);
  }

  final source = ask.cardId == null ? null : state?.card(ask.cardId!)?.card;
  final Widget dialog = switch (ask.kind) {
    'confirm' => _ConfirmDialog(ask: ask, source: source),
    'order' => _OrderDialog(ask: ask, cardOf: cardOf),
    'input' => _InputDialog(ask: ask),
    'distribute' => _DistributeDialog(ask: ask, cardOf: cardOf),
    _ => _ChooseDialog(ask: ask, cardOf: cardOf, source: source),
  };
  return showDialog<Object?>(context: context, barrierDismissible: false, builder: (_) => dialog);
}

String _title(ForgeAsk ask, String fallback) {
  final t = ask.title?.trim() ?? '';
  if (t.isNotEmpty) return t;
  final m = ask.message?.trim() ?? '';
  return m.isNotEmpty ? m : fallback;
}

/// A mensagem por baixo do título, se o título não for já a mensagem.
Widget? _subtitle(BuildContext context, ForgeAsk ask) {
  final t = ask.title?.trim() ?? '';
  final m = ask.message?.trim() ?? '';
  if (t.isEmpty || m.isEmpty) return null;
  return Padding(padding: const EdgeInsets.only(bottom: 8), child: OracleText(m, style: Theme.of(context).textTheme.bodyMedium));
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({super.key, required this.option, required this.card, this.trailing, this.onTap, this.selected = false});

  final ForgeOption option;
  final db.Card? card;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;

  /// Cada opção é um botão (contorno, toque, cheio quando escolhido): numa
  /// lista de texto simples não se percebia que eram escolhas.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final detail = card != null && option.label != card!.name && option.label != card!.displayName;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? scheme.primary : scheme.outline, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                if (card != null) ...[SizedBox(width: 40, child: CardImage(card!, radius: 3)), const SizedBox(width: 12)],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    OracleText(card?.displayName ?? option.label,
                        style: text.bodyLarge?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w500)),
                    if (detail) OracleText(option.label, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ]),
                ),
                if (trailing != null) trailing!,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChooseDialog extends StatefulWidget {
  const _ChooseDialog({required this.ask, required this.cardOf, this.source});

  final ForgeAsk ask;
  final db.Card? Function(ForgeOption) cardOf;
  final db.Card? source;

  @override
  State<_ChooseDialog> createState() => _ChooseDialogState();
}

class _ChooseDialogState extends State<_ChooseDialog> {
  late final Set<int> _picked = {...widget.ask.selected.where((i) => i >= 0)};

  bool get _single => widget.ask.max == 1;

  /// Só para ver (o Forge mostra assim cartas reveladas e avisos): nada a escolher.
  bool get _readOnly => widget.ask.max <= 0;

  @override
  Widget build(BuildContext context) {
    final ask = widget.ask;
    final ok = _picked.length >= ask.min && _picked.length <= ask.max;
    return AlertDialog(
      title: Text(_title(ask, tr('Escolhe'))),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_subtitle(context, ask) case final sub?) sub,
          if (!_single && !_readOnly)
            Text(
              ask.min == ask.max
                  ? tr('Escolhe {n}.', {'n': ask.min})
                  : tr('Escolhe de {a} a {b}.', {'a': ask.min, 'b': ask.max}),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (var i = 0; i < ask.options.length; i++)
                _OptionTile(
                  option: ask.options[i],
                  card: widget.cardOf(ask.options[i]),
                  selected: _picked.contains(i),
                  trailing: _single || _readOnly
                      ? null
                      : Checkbox(
                          value: _picked.contains(i),
                          onChanged: (_) => _toggle(i),
                        ),
                  onTap: _readOnly ? null : () => _single ? Navigator.pop(context, [i]) : _toggle(i),
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        if (_readOnly)
          FilledButton(onPressed: () => Navigator.pop(context, <int>[]), child: Text(tr('OK')))
        else if (ask.min == 0)
          TextButton(onPressed: () => Navigator.pop(context, <int>[]), child: Text(tr('Nenhuma'))),
        if (!_single && !_readOnly)
          FilledButton(
            onPressed: ok ? () => Navigator.pop(context, _picked.toList()..sort()) : null,
            child: Text(tr('Confirmar')),
          ),
      ],
    );
  }

  void _toggle(int i) {
    setState(() {
      if (!_picked.remove(i) && _picked.length < widget.ask.max) _picked.add(i);
    });
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.ask, this.source});

  final ForgeAsk ask;
  final db.Card? source;

  @override
  Widget build(BuildContext context) {
    final yes = ask.labels.isNotEmpty ? ask.labels[0] : tr('Sim');
    final no = ask.labels.length > 1 ? ask.labels[1] : tr('Não');
    return AlertDialog(
      title: ask.title == null ? null : Text(ask.title!),
      content: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (source != null) ...[SizedBox(width: 70, child: CardImage(source!, radius: 4)), const SizedBox(width: 12)],
        Expanded(child: OracleText(ask.message ?? '')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(no)),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(yes)),
      ],
    );
  }
}

/// Ordenar (o primeiro da lista fica no topo / é o primeiro).
class _OrderDialog extends StatefulWidget {
  const _OrderDialog({required this.ask, required this.cardOf});

  final ForgeAsk ask;
  final db.Card? Function(ForgeOption) cardOf;

  @override
  State<_OrderDialog> createState() => _OrderDialogState();
}

class _OrderDialogState extends State<_OrderDialog> {
  late final List<int> _order = [for (var i = 0; i < widget.ask.options.length; i++) i];

  @override
  Widget build(BuildContext context) {
    final ask = widget.ask;
    return AlertDialog(
      title: Text(_title(ask, tr('Ordenar'))),
      content: SizedBox(
        width: 420,
        height: 360,
        child: Column(children: [
          if (_subtitle(context, ask) case final sub?) sub,
          Text(tr('Arrasta para mudar a ordem. O primeiro fica em cima.'), style: Theme.of(context).textTheme.bodySmall),
          Expanded(
            child: ReorderableListView(
              buildDefaultDragHandles: true,
              onReorder: (from, to) => setState(() {
                final v = _order.removeAt(from);
                _order.insert(to > from ? to - 1 : to, v);
              }),
              children: [
                for (final i in _order)
                  _OptionTile(
                    key: ValueKey(i),
                    option: ask.options[i],
                    card: widget.cardOf(ask.options[i]),
                    trailing: const Icon(Icons.drag_handle),
                  ),
              ],
            ),
          ),
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context, _order), child: Text(tr('Confirmar')))],
    );
  }
}

class _InputDialog extends StatefulWidget {
  const _InputDialog({required this.ask});

  final ForgeAsk ask;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final _text = TextEditingController(text: widget.ask.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title(widget.ask, '')),
      content: TextField(
        controller: _text,
        autofocus: true,
        keyboardType: widget.ask.numeric ? TextInputType.number : TextInputType.text,
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context, _text.text), child: Text(tr('Confirmar')))],
    );
  }
}

/// Dividir uma quantidade (dano, contadores) pelos alvos.
class _DistributeDialog extends StatefulWidget {
  const _DistributeDialog({required this.ask, required this.cardOf});

  final ForgeAsk ask;
  final db.Card? Function(ForgeOption) cardOf;

  @override
  State<_DistributeDialog> createState() => _DistributeDialogState();
}

class _DistributeDialogState extends State<_DistributeDialog> {
  late final List<int> _split = () {
    final n = widget.ask.options.length;
    final base = widget.ask.atLeastOne ? 1 : 0;
    final split = List.filled(n, base);
    if (n > 0) split[0] += widget.ask.amount - base * n;
    return split;
  }();

  int get _left => widget.ask.amount - _split.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final ask = widget.ask;
    final min = ask.atLeastOne ? 1 : 0;
    return AlertDialog(
      title: Text(_title(ask, tr('Dividir'))),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Por dividir: {n}', {'n': _left})),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (var i = 0; i < ask.options.length; i++)
                _OptionTile(
                  option: ask.options[i],
                  card: widget.cardOf(ask.options[i]),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: _split[i] > min ? () => setState(() => _split[i]--) : null,
                    ),
                    Text('${_split[i]}'),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _left > 0 ? () => setState(() => _split[i]++) : null,
                    ),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        FilledButton(onPressed: _left == 0 ? () => Navigator.pop(context, _split) : null, child: Text(tr('Confirmar'))),
      ],
    );
  }
}
