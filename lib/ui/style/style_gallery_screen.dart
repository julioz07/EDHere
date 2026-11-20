import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/settings.dart';
import 'style.dart';

/// Só em debug: as peças e os componentes nos 4 temas, para rever o estilo.
class StyleGalleryScreen extends StatelessWidget {
  const StyleGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Galeria de estilos')),
      body: ListView(children: [
        for (final style in UiStyle.values)
          for (final b in [Brightness.dark, Brightness.light])
            Theme(
              data: buildTheme(b, style),
              child: Builder(
                builder: (context) => ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: DefaultTextStyle(
                    style: Theme.of(context).textTheme.bodyMedium!,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                      child: _Sample(title: '${style.name} · ${b.name}'),
                    ),
                  ),
                ),
              ),
            ),
      ]),
    );
  }
}

class _Sample extends StatefulWidget {
  const _Sample({required this.title});

  final String title;

  @override
  State<_Sample> createState() => _SampleState();
}

class _SampleState extends State<_Sample> {
  var _seg = 0;
  var _nav = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.edhStyle;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.title, style: theme.textTheme.headlineSmall),
      const SizedBox(height: 16),
      SectionDivider('Com outros', classic: Text('Com outros', style: theme.textTheme.titleSmall)),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.add), label: const Text('Criar sala')),
      const SizedBox(height: 10),
      OutlinedButton.icon(
          onPressed: () {}, icon: const Icon(Icons.qr_code_scanner), label: const Text('Entrar numa sala')),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () {}, child: const Text('Sealed'))),
        const SizedBox(width: 10),
        const Expanded(child: FilledButton(onPressed: null, child: Text('Desligado'))),
      ]),
      TextButton(onPressed: () {}, child: const Text('Saber mais')),
      const SizedBox(height: 10),
      const TextField(
        decoration: InputDecoration(
            labelText: 'O teu nome', prefixIcon: Icon(Icons.person_outline), helperText: 'É o nome que os outros veem'),
      ),
      const SizedBox(height: 16),
      SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 0, label: Text('Tipo')),
          ButtonSegment(value: 1, label: Text('Custo')),
          ButtonSegment(value: 2, label: Text('Cor')),
        ],
        selected: {_seg},
        onSelectionChanged: (v) => setState(() => _seg = v.first),
      ),
      const SizedBox(height: 16),
      const Card(
        child: ListTile(
          leading: Icon(Icons.style_outlined),
          title: Text('Krenko, Mob Boss'),
          subtitle: Text('Commander · 100 cartas'),
          trailing: Icon(Icons.chevron_right),
        ),
      ),
      const SizedBox(height: 20),
      StyleFrame(
        highlighted: true,
        classic: (child) => Card(child: Padding(padding: const EdgeInsets.all(14), child: child)),
        child: Row(children: [
          Column(children: [
            const LegendCrown(),
            Icon(Icons.shield_outlined, color: c.goldText, size: 36),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('JOGO GRAVADO', style: theme.textTheme.labelSmall?.copyWith(color: c.goldText)),
              Text('Krenko Goblins', style: theme.textTheme.titleLarge),
              Text('Goldfish · turno 1', style: theme.textTheme.bodySmall),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 20),
      Row(children: [
        for (final (i, (name, life, active)) in [('Ana', '40', true), ('Bruno', '38', false), ('Carla', '31', false)]
            .indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: TurnGlow(
              active: active,
              classic: (child) => DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: active ? theme.colorScheme.primary : theme.colorScheme.outline),
                ),
                child: child,
              ),
              child: StyleFrame(
                showGem: false,
                padding: const EdgeInsets.all(8),
                radius: 12,
                classic: (child) => Padding(padding: const EdgeInsets.all(8), child: child),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    ManaOrb(
                      color: GameColors.player(i),
                      size: 12,
                      classic: CircleAvatar(radius: 5, backgroundColor: GameColors.player(i)),
                    ),
                    const SizedBox(width: 6),
                    Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall)),
                  ]),
                  const SizedBox(height: 6),
                  GoldPlate(life, classic: Text(life, style: theme.textTheme.headlineSmall)),
                ]),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 20),
      DefaultTabController(
        length: 3,
        child: TabBar(tabs: [for (final t in ['Cartas', 'Estatísticas', 'Validação']) Tab(text: t)]),
      ),
      const SizedBox(height: 12),
      Text('Ana comprou 1 carta',
          style: c.isEnchanted ? EdhText.flavor.copyWith(color: c.textMuted) : theme.textTheme.bodyMedium),
      const SizedBox(height: 12),
      NavigationBar(
        selectedIndex: _nav,
        onDestinationSelected: (i) => setState(() => _nav = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search), label: 'Cartas'),
          NavigationDestination(icon: Icon(Icons.style_outlined), label: 'Decks'),
          NavigationDestination(icon: Icon(Icons.play_arrow), label: 'Jogar'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Definições'),
        ],
      ),
    ]);
  }
}
