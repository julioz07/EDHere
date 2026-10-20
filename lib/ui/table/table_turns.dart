import 'package:flutter/material.dart';

/// Mesa partilhada (dois jogadores à volta do mesmo ecrã): diz para que lado
/// está virada a metade de um jogador, em quartos de volta. Os menus, os
/// diálogos e os detalhes de uma carta abertos a partir dessa metade aparecem
/// virados para esse jogador e encostados ao lado dele, e não sempre em baixo.
class TableTurns extends InheritedWidget {
  const TableTurns({super.key, required this.turns, required super.child});

  final int turns;

  /// null fora da mesa partilhada (ecrã normal, um jogador).
  static int? of(BuildContext context) => context.getInheritedWidgetOfExactType<TableTurns>()?.turns;

  @override
  bool updateShouldNotify(TableTurns oldWidget) => oldWidget.turns != turns;
}

/// Menu de baixo da mesa. Na mesa partilhada abre virado para o jogador e só
/// na metade dele.
Future<T?> showTableSheet<T>(BuildContext context, WidgetBuilder builder) {
  final turns = TableTurns.of(context);
  if (turns == null) {
    return showModalBottomSheet<T>(context: context, isScrollControlled: true, useSafeArea: true, builder: builder);
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, __) => SafeArea(
      child: RotatedBox(
        quarterTurns: turns,
        child: LayoutBuilder(
          builder: (ctx, box) => Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              // Cada jogador tem metade do ecrã: o menu não passa para a do outro.
              constraints: BoxConstraints(maxWidth: 640, maxHeight: box.maxHeight * 0.5),
              child: Material(
                color: Theme.of(ctx).colorScheme.surfaceContainerLow,
                clipBehavior: Clip.antiAlias,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: TableTurns(turns: turns, child: Builder(builder: builder)),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Diálogo da mesa; na mesa partilhada fica virado para o jogador.
Future<T?> showTableDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final turns = TableTurns.of(context);
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: turns == null
        ? builder
        : (ctx) => RotatedBox(
              quarterTurns: turns,
              child: TableTurns(turns: turns, child: Builder(builder: builder)),
            ),
  );
}

/// Abre um ecrã inteiro (detalhes de uma carta), virado para o jogador na mesa
/// partilhada.
Future<T?> pushTablePage<T>(BuildContext context, Widget page) {
  final turns = TableTurns.of(context);
  return Navigator.of(context).push(MaterialPageRoute<T>(
    builder: (_) => turns == null || turns == 0 ? page : RotatedBox(quarterTurns: turns, child: page),
  ));
}
