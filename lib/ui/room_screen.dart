import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app/theme.dart';
import '../net/join_code.dart';
import '../net/room_client.dart';
import '../net/room_link.dart';
import '../room/room_model.dart';
import '../room/room_session.dart';
import 'widgets/responsive.dart';
import '../l10n/l10n.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.session, this.diagnostics = false});

  final RoomSession session;

  /// Aberto a partir do lobby: sair não fecha a sala.
  final bool diagnostics;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late final RoomModel _model = RoomModel(widget.session.link);
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    // Se o ecrã do anfitrião bloquear, o sistema corta a rede.
    if (!widget.diagnostics) WakelockPlus.enable();
  }

  @override
  void dispose() {
    if (!widget.diagnostics) WakelockPlus.disable();
    _model.dispose();
    if (!_closing && !widget.diagnostics) widget.session.close();
    super.dispose();
  }

  Future<void> _leave() async {
    if (widget.diagnostics) {
      Navigator.of(context).pop();
      return;
    }
    final isHost = widget.session.isHost;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isHost ? tr('Fechar a sala?') : tr('Sair da sala?')),
        content: Text(isHost
            ? tr('Todos os jogadores perdem a ligação.')
            : tr('O teu lugar fica livre para outra pessoa.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Ficar'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(isHost ? tr('Fechar') : tr('Sair'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _closing = true;
    await widget.session.close();
    if (mounted) Navigator.of(context).pop();
  }

  void _showQr() => showRoomQr(context, widget.session);

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: ListenableBuilder(
        listenable: _model,
        builder: (context, _) {
          final status = s.link.status;
          return Scaffold(
            appBar: AppBar(
              title: Text(s.roomName, overflow: TextOverflow.ellipsis),
              actions: [
                if (s.isHost)
                  IconButton(
                    tooltip: tr('QR code da sala'),
                    onPressed: _showQr,
                    icon: const Icon(Icons.qr_code_2),
                  ),
                IconButton(
                  tooltip: tr('Sair'),
                  onPressed: _leave,
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
            body: MaxWidth(
                child: Column(
              children: [
                if (status == LinkStatus.reconnecting) const _ReconnectingBanner(),
                if (status == LinkStatus.closed && !_closing) const _ClosedBanner(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: _StatusCard(model: _model, session: s),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _Players(model: _model),
                ),
                const SizedBox(height: 8),
                if (_model.bursts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _BurstSummary(model: _model),
                  ),
                const Divider(),
                Expanded(child: _EventLog(model: _model)),
                const Divider(),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _Actions(
                      model: _model,
                      enabled: status == LinkStatus.connected,
                    ),
                  ),
                ),
              ],
            )),
          );
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.model, required this.session});

  final RoomModel model;
  final RoomSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = session.link;
    final (label, color) = switch (link.status) {
      LinkStatus.connected => (tr('Ligado'), EdhColors.ok),
      LinkStatus.connecting => (tr('A ligar'), EdhColors.warn),
      LinkStatus.reconnecting => (tr('A religar'), EdhColors.warn),
      LinkStatus.rejected => (tr('Recusado'), EdhColors.bad),
      LinkStatus.closed => (tr('Fechado'), EdhColors.bad),
    };
    final client = link is RoomClient ? link : null;
    final facts = <(String, String)>[
      (tr('Papel'), session.isHost ? tr('Anfitrião') : tr('Lugar {mySeat}', {'mySeat': model.mySeat})),
      if (!session.isHost) ('RTT', link.rttMs == null ? '—' : tr('{rttMs} ms', {'rttMs': link.rttMs})),
      (tr('Último seq'), '${model.lastSeq}'),
      if (client != null) (tr('Saltos'), '${client.seqGaps}'),
      if (client != null) (tr('Religações'), '${client.reconnects}'),
      if (session.isHost)
        (
          tr('Endereço'),
          session.hostAddresses.isEmpty ? tr('sem rede') : '${session.hostAddresses.first}:${session.port}'
        ),
      if (client?.connectedHost != null) (tr('Anfitrião'), '${client!.connectedHost}:${client.port}'),
      if (session.hotspot != null) (tr('Hotspot'), session.hotspot!.ssid),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(label, style: theme.textTheme.titleSmall),
            ]),
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                for (final (k, v) in facts)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(k,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      Text(v, style: theme.textTheme.bodyMedium),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Players extends StatelessWidget {
  const _Players({required this.model});

  final RoomModel model;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in model.players.values)
            Chip(
              avatar: Icon(
                p.isHost ? Icons.star_rounded : Icons.person,
                size: 18,
                color: p.connected ? EdhColors.ok : EdhColors.bad,
              ),
              label: Text(p.seat == model.mySeat ? tr('{v} (tu)', {'v': p.name}) : p.name),
              side: BorderSide(
                color: p.seat == model.mySeat ? scheme.primary : scheme.outline,
              ),
            ),
        ],
      ),
    );
  }
}

class _BurstSummary extends StatelessWidget {
  const _BurstSummary({required this.model});

  final RoomModel model;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final last = model.bursts.values.toList().reversed.take(4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in last)
          Row(children: [
            Icon(
              !r.inOrder
                  ? Icons.error_outline
                  : r.done
                      ? Icons.check_circle_outline
                      : Icons.hourglass_bottom,
              size: 16,
              color: !r.inOrder
                  ? EdhColors.bad
                  : r.done
                      ? EdhColors.ok
                      : EdhColors.warn,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tr('Carga de {v}: {received}/{expected}{v2} (seq {firstSeq}–{lastSeq})', {
                  'v': model.nameOf(r.actor),
                  'received': r.received,
                  'expected': r.expected,
                  'v2': r.inOrder ? tr(' em ordem') : tr(' FORA DE ORDEM'),
                  'firstSeq': r.firstSeq,
                  'lastSeq': r.lastSeq
                }),
                style: style,
              ),
            ),
          ]),
      ],
    );
  }
}

class _EventLog extends StatelessWidget {
  const _EventLog({required this.model});

  final RoomModel model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // Os eventos de carga enchem o registo; mostram-se só no resumo.
    final items = model.log.where((e) => e.type != 'burst').toList();
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final e = items[items.length - 1 - i];
        final mine = e.actor == model.mySeat;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                child: Text('#${e.seq}', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ),
              Expanded(
                child: Text(
                  model.describe(e),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: mine ? theme.colorScheme.primary : null,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.model, required this.enabled});

  final RoomModel model;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              onPressed: enabled ? onTap : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(height: 2),
                  Text(label, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        );
    return Row(children: [
      btn(Icons.wifi_tethering, tr('Ping'), model.ping),
      btn(Icons.casino_outlined, 'd20', () => model.rollDie(20)),
      btn(Icons.toll_outlined, tr('Moeda'), model.flipCoin),
      btn(Icons.speed, tr('Carga 100'), () => model.sendBurst(100)),
    ]);
  }
}

class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner();

  @override
  Widget build(BuildContext context) => MaterialBanner(
        backgroundColor: const Color(0x33E0A63A),
        leading: const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        content: Text(tr('Ligação perdida. A tentar voltar a ligar…')),
        actions: const [SizedBox.shrink()],
      );
}

class _ClosedBanner extends StatelessWidget {
  const _ClosedBanner();

  @override
  Widget build(BuildContext context) => MaterialBanner(
        backgroundColor: const Color(0x33E5534B),
        leading: const Icon(Icons.link_off),
        content: Text(tr('A sala foi fechada.')),
        actions: const [SizedBox.shrink()],
      );
}

/// QR codes da sala (Wi-Fi do hotspot e entrada na sala).
void showRoomQr(BuildContext context, RoomSession session) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _QrSheet(session: session),
  );
}

class _QrSheet extends StatefulWidget {
  const _QrSheet({required this.session});

  final RoomSession session;

  @override
  State<_QrSheet> createState() => _QrSheetState();
}

class _QrSheetState extends State<_QrSheet> {
  late bool _wifi = widget.session.hotspot != null;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final hotspot = s.hotspot;
    final theme = Theme.of(context);
    final data = _wifi && hotspot != null
        ? wifiQr(ssid: hotspot.ssid, password: hotspot.password)
        : s.joinCode.encode();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hotspot != null) ...[
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(tr('1. Wi-Fi'))),
                  ButtonSegment(value: false, label: Text(tr('2. Sala'))),
                ],
                selected: {_wifi},
                onSelectionChanged: (v) => setState(() => _wifi = v.first),
              ),
              const SizedBox(height: 16),
            ],
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(data: data, size: 240),
            ),
            const SizedBox(height: 16),
            Text(
              _wifi
                  ? tr('Lê com a câmara do telemóvel para ligar à rede "{ssid}".\nPassword: {password}',
                      {'ssid': hotspot!.ssid, 'password': hotspot.password})
                  : tr('Na app: Entrar numa sala → Ler QR code.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (!_wifi && s.hostAddresses.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                tr('IP: {v} · porta {port}', {'v': s.hostAddresses.join(' / '), 'port': s.port}),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
