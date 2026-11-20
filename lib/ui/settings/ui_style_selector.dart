import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings.dart';
import '../../l10n/l10n.dart';
import '../widgets/responsive.dart';

/// Clássico ou Encantado, nas Definições (por baixo de Claro/Escuro).
class UiStyleSelector extends ConsumerWidget {
  const UiStyleSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return SegmentedButton<UiStyle>(
      // Sem o visto, como no de Claro/Escuro: com letra grande não cabia.
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
            value: UiStyle.classic, icon: const Icon(Icons.crop_square), label: FitText(tr('Clássico'))),
        ButtonSegment(
            value: UiStyle.enchanted, icon: const Icon(Icons.auto_awesome), label: FitText(tr('Encantado'))),
      ],
      selected: {s.uiStyle},
      onSelectionChanged: (v) => s.uiStyle = v.first,
    );
  }
}
