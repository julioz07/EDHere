import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/settings.dart';

import '../net/discovery.dart';

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
      appBar: AppBar(title: const Text('Sobre')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: SvgPicture.asset(Brand.vertical(theme.brightness), height: 140)),
          const SizedBox(height: 8),
          Center(child: Text('Versão $appVersion', style: theme.textTheme.bodySmall)),
          const SizedBox(height: 20),
          section('O que é',
              'Uma mesa de jogo offline para jogar com quem está ao teu lado. A app gere zonas, '
                  'vida, contadores e turnos; as regras ficam a cargo dos jogadores, como numa mesa '
                  'física. É 100% gratuita, sem anúncios, sem contas e sem servidores próprios.'),
          section('Conteúdo de fãs',
              'EDHere é conteúdo de fãs não oficial, permitido pela Fan Content Policy. Não é '
                  'aprovado nem endossado pela Wizards. Partes dos materiais usados são propriedade '
                  'da Wizards of the Coast. ©Wizards of the Coast LLC.'),
          section('Dados e imagens',
              'Os dados e as imagens das cartas vêm do Scryfall, descarregados diretamente para o '
                  'teu telemóvel. O EDHere não é produzido nem apoiado pelo Scryfall. As imagens são '
                  'mostradas sem cortes nem alterações, com o nome do artista.'),
          section('Símbolos de mana',
              'Os símbolos de mana são desenhados pela própria app e mostram sempre a letra da cor.'),
        ],
      ),
    );
  }
}
