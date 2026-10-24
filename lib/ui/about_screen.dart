import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/settings.dart';

import '../net/discovery.dart';
import 'widgets/responsive.dart';
import '../l10n/l10n.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: Text(tr('Sobre'))),
      body: MaxWidth(
          child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: SvgPicture.asset(Brand.vertical(theme.brightness), height: 140)),
          const SizedBox(height: 8),
          Center(
              child: Text(tr('Versão {appVersion}', {'appVersion': appVersion}),
                  style: theme.textTheme.bodySmall)),
          const SizedBox(height: 20),
          section(tr('O que é'),
              tr('Uma mesa de jogo offline para jogar com quem está ao teu lado. A app gere zonas, vida, contadores e turnos; as regras ficam a cargo dos jogadores, como numa mesa física. É 100% gratuita, sem anúncios, sem contas e sem servidores próprios.')),
          section(tr('Conteúdo de fãs'),
              tr('EDHere é conteúdo de fãs não oficial, permitido pela Fan Content Policy. Não é aprovado nem endossado pela Wizards. Partes dos materiais usados são propriedade da Wizards of the Coast. ©Wizards of the Coast LLC.')),
          section(tr('Dados e imagens'),
              tr('Os dados e as imagens das cartas vêm do Scryfall, descarregados diretamente para o teu telemóvel. O EDHere não é produzido nem apoiado pelo Scryfall. As imagens são mostradas sem cortes nem alterações, com o nome do artista.')),
          section(tr('Boosters e JumpStart'),
              tr('A composição dos boosters de cada set e as listas dos pacotes JumpStart vêm do MTGJSON (licença MIT) e estão incluídas na app.')),
          section(tr('Símbolos dos sets'),
              tr('Os símbolos dos sets são da fonte Keyrune, de Andrew Gioia (SIL OFL 1.1). Os símbolos originais são marcas da Wizards of the Coast.')),
          section(tr('Símbolos de mana'),
              tr('Os símbolos de mana são desenhados pela própria app e mostram sempre a letra da cor.')),
          section(tr('O bot'),
              tr('O bot usa o motor do Forge, que aplica as regras e joga do outro lado. O Forge é software livre, feito por uma comunidade de voluntários, sob a licença GPL-3.0, e vem dentro da app sem alterações.')),
          const SelectableText('https://github.com/Card-Forge/forge'),
          const SizedBox(height: 20),
          section(tr('Código aberto'),
              tr('O código do EDHere é aberto, sob a licença GPL-3.0: pode ser estudado, alterado e partilhado nos termos dessa licença. O nome e o logótipo do EDHere não fazem parte da licença.')),
          const SelectableText('https://github.com/julioz07/EDHere'),
        ],
      )),
    );
  }
}
