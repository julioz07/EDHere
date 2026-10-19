import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/providers.dart';
import '../../data/settings.dart';
import '../../net/discovery.dart';
import '../about_screen.dart';
import '../onboarding_screen.dart';
import '../shell.dart';
import '../data/data_tab.dart';
import '../stats/stats_screen.dart';
import '../widgets/responsive.dart';
import 'backup_actions.dart';
import '../../l10n/l10n.dart';

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
      appBar: AppBar(title: Text(tr('Definições'))),
      body: MaxWidth(
          child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        section(tr('Língua'), Icons.language),
        ListTile(
          title: Text(tr('Língua da app')),
          subtitle: Text(tr('Por defeito, a do telemóvel')),
          trailing: DropdownButton<AppLang>(
            value: s.appLang,
            underline: const SizedBox.shrink(),
            items: [
              for (final l in AppLang.values) DropdownMenuItem(value: l, child: Text(l.label)),
            ],
            onChanged: (l) {
              if (l == null || l == s.appLang) return;
              // A app refaz-se na nova língua e volta a este separador.
              AppShell.reopenTab = 3;
              s.appLang = l;
            },
          ),
        ),
        const CardLanguageTile(icon: false),
        section(tr('Aparência'), Icons.palette_outlined),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                  value: ThemeMode.system,
                  icon: const Icon(Icons.brightness_auto),
                  label: Text(tr('Sistema'))),
              ButtonSegment(
                  value: ThemeMode.dark, icon: const Icon(Icons.dark_mode), label: Text(tr('Escuro'))),
              ButtonSegment(
                  value: ThemeMode.light, icon: const Icon(Icons.light_mode), label: Text(tr('Claro'))),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => s.themeMode = v.first,
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(tr('Fundo da área de jogo'), style: theme.textTheme.titleSmall),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 150,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _BgOption(
                label: tr('Nenhum'),
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
                label: tr('Da galeria'),
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
            title: Text(tr('Escurecer o fundo ({v}%)', {'v': (s.backgroundDim * 100).round()})),
            subtitle: Slider(
              value: s.backgroundDim,
              max: 0.8,
              divisions: 8,
              label: '${(s.backgroundDim * 100).round()}%',
              onChanged: (v) => s.backgroundDim = v,
            ),
          ),
        section(tr('Mesa'), Icons.table_restaurant_outlined),
        ListTile(
          title: Text(tr('Tamanho das cartas no campo ({v}%)', {'v': (s.cardScale * 100).round()})),
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
          title: Text(tr('Compra automática no início do turno')),
          subtitle: Text(tr('Valor por defeito em cada jogo')),
          value: s.autoDraw,
          onChanged: (v) => s.autoDraw = v,
        ),
        SwitchListTile(
          title: Text(tr('Toque duplo para virar (tap)')),
          subtitle: Text(tr('Desligado, um toque abre sempre o menu da carta')),
          value: s.doubleTapToTap,
          onChanged: (v) => s.doubleTapToTap = v,
        ),
        SwitchListTile(
          title: Text(tr('Ordenar a mão')),
          subtitle: Text(tr('Feitiços por custo primeiro, terrenos no fim')),
          value: s.sortHand,
          onChanged: (v) => s.sortHand = v,
        ),
        SwitchListTile(
          title: Text(tr('Manter o ecrã ligado durante o jogo')),
          subtitle: Text(tr('Evita que a rede caia quando o ecrã se apaga')),
          value: s.keepScreenOn,
          onChanged: (v) => s.keepScreenOn = v,
        ),
        SwitchListTile(
          title: Text(tr('Confirmar antes de sair da mesa')),
          value: s.confirmLeave,
          onChanged: (v) => s.confirmLeave = v,
        ),
        section(tr('Dados'), Icons.storage_outlined),
        ListTile(
          leading: const Icon(Icons.cloud_download_outlined),
          title: Text(tr('Base de cartas e imagens offline')),
          subtitle: Text(data.hasData
              ? tr('{cardCount} cartas{v}',
                  {'cardCount': data.cardCount, 'v': data.updateAvailable ? tr(' · há uma atualização') : ''})
              : tr('Ainda não descarregada')),
          trailing: data.updateAvailable || !data.hasData
              ? const Badge(child: Icon(Icons.chevron_right))
              : const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DataTab())),
        ),
        ListTile(
          leading: const Icon(Icons.bar_chart),
          title: Text(tr('Histórico e estatísticas')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StatsScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.upload_file),
          title: Text(tr('Exportar backup')),
          subtitle: Text(tr('Decks, as minhas cartas e histórico num ficheiro (Drive, PC…)')),
          onTap: () => exportBackup(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: Text(tr('Importar backup')),
          subtitle: Text(tr('Junta o que está no ficheiro ao que já tens')),
          onTap: () => importBackupFile(context, ref),
        ),
        section(tr('Sobre'), Icons.info_outline),
        ListTile(
          leading: const Icon(Icons.slideshow_outlined),
          title: Text(tr('Ver a introdução')),
          subtitle: Text(tr('O que a app faz e como funciona')),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const OnboardingScreen(replay: true))),
        ),
        ListTile(
          leading: SvgPicture.asset(Brand.symbol(theme.brightness), width: 28, height: 28),
          title: Text(tr('Sobre o EDHere')),
          subtitle: Text(tr('Versão {appVersion}', {'appVersion': appVersion})),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(tr('Licenças')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(
            context: context,
            applicationName: tr('EDHere'),
            applicationVersion: appVersion,
            applicationIcon: Padding(
              padding: const EdgeInsets.all(12),
              child: SvgPicture.asset(Brand.symbol(theme.brightness), width: 48),
            ),
          ),
        ),
      ])),
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
            .showSnackBar(SnackBar(content: Text(tr('Não foi possível usar a imagem: {e}', {'e': e}))));
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
