import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/providers.dart';
import '../../data/settings.dart';
import '../../net/discovery.dart';
import '../about_screen.dart';
import '../data/data_tab.dart';
import '../stats/stats_screen.dart';

/// Definições: aparência, mesa, dados offline e sobre.
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final data = ref.watch(cardDataProvider);
    final theme = Theme.of(context);

    Widget section(String title, IconData icon) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Row(children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(title, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Definições')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        section('Aparência', Icons.palette_outlined),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('Sistema')),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Escuro')),
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Claro')),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => s.themeMode = v.first,
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Fundo da área de jogo', style: theme.textTheme.titleSmall),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 150,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _BgOption(
                label: 'Nenhum',
                selected: s.background == 'none',
                onTap: () => s.background = 'none',
                child: Container(color: theme.colorScheme.surfaceContainerHighest),
              ),
              for (final b in TableBackground.builtIn)
                _BgOption(
                  label: b.label,
                  selected: s.background == 'asset:${b.id}',
                  onTap: () => s.background = 'asset:${b.id}',
                  child: Image.asset(b.asset, fit: BoxFit.cover),
                ),
              _BgOption(
                label: 'Da galeria',
                selected: s.background == 'file',
                onTap: () => _pickFromGallery(context, s),
                child: s.background == 'file' && s.backgroundImage != null
                    ? Image(
                        key: ValueKey(s.imageCacheVersion),
                        image: s.backgroundImage!,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.add_photo_alternate_outlined,
                            size: 32, color: theme.colorScheme.primary),
                      ),
              ),
            ],
          ),
        ),
        if (s.background != 'none')
          ListTile(
            title: Text('Escurecer o fundo (${(s.backgroundDim * 100).round()}%)'),
            subtitle: Slider(
              value: s.backgroundDim,
              max: 0.8,
              divisions: 8,
              label: '${(s.backgroundDim * 100).round()}%',
              onChanged: (v) => s.backgroundDim = v,
            ),
          ),
        section('Mesa', Icons.table_restaurant_outlined),
        ListTile(
          title: Text('Tamanho das cartas no campo (${(s.cardScale * 100).round()}%)'),
          subtitle: Slider(
            value: s.cardScale,
            min: 0.7,
            max: 1.6,
            divisions: 9,
            label: '${(s.cardScale * 100).round()}%',
            onChanged: (v) => s.cardScale = v,
          ),
        ),
        SwitchListTile(
          title: const Text('Compra automática no início do turno'),
          subtitle: const Text('Valor por defeito em cada jogo'),
          value: s.autoDraw,
          onChanged: (v) => s.autoDraw = v,
        ),
        SwitchListTile(
          title: const Text('Toque duplo para virar (tap)'),
          subtitle: const Text('Desligado, um toque abre sempre o menu da carta'),
          value: s.doubleTapToTap,
          onChanged: (v) => s.doubleTapToTap = v,
        ),
        SwitchListTile(
          title: const Text('Ordenar a mão'),
          subtitle: const Text('Feitiços por custo primeiro, terrenos no fim'),
          value: s.sortHand,
          onChanged: (v) => s.sortHand = v,
        ),
        SwitchListTile(
          title: const Text('Manter o ecrã ligado durante o jogo'),
          subtitle: const Text('Evita que a rede caia quando o ecrã se apaga'),
          value: s.keepScreenOn,
          onChanged: (v) => s.keepScreenOn = v,
        ),
        SwitchListTile(
          title: const Text('Confirmar antes de sair da mesa'),
          value: s.confirmLeave,
          onChanged: (v) => s.confirmLeave = v,
        ),
        section('Dados', Icons.storage_outlined),
        ListTile(
          leading: const Icon(Icons.cloud_download_outlined),
          title: const Text('Base de cartas e imagens offline'),
          subtitle: Text(data.hasData
              ? '${data.cardCount} cartas${data.updateAvailable ? ' · há uma atualização' : ''}'
              : 'Ainda não descarregada'),
          trailing: data.updateAvailable || !data.hasData
              ? const Badge(child: Icon(Icons.chevron_right))
              : const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DataTab())),
        ),
        ListTile(
          leading: const Icon(Icons.bar_chart),
          title: const Text('Histórico e estatísticas'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StatsScreen())),
        ),
        section('Sobre', Icons.info_outline),
        ListTile(
          leading: SvgPicture.asset(Brand.symbol(theme.brightness), width: 28, height: 28),
          title: const Text('Sobre o EDHere'),
          subtitle: const Text('Versão $appVersion'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Licenças'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'EDHere',
            applicationVersion: appVersion,
            applicationIcon: Padding(
              padding: const EdgeInsets.all(12),
              child: SvgPicture.asset(Brand.symbol(theme.brightness), width: 48),
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _pickFromGallery(BuildContext context, Settings s) async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2160);
      if (file == null) return;
      await s.useCustomBackground(file.path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Não foi possível usar a imagem: $e')));
      }
    }
  }
}

class _BgOption extends StatelessWidget {
  const _BgOption({required this.label, required this.selected, required this.onTap, required this.child});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Container(
            width: 72,
            height: 118,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? scheme.primary : scheme.outline, width: selected ? 3 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(fit: StackFit.expand, children: [
              child,
              if (selected)
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: scheme.primary,
                      child: Icon(Icons.check, size: 14, color: scheme.onPrimary),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ]),
      ),
    );
  }
}
