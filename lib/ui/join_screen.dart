import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../net/discovery.dart';
import '../net/join_code.dart';
import '../net/network_util.dart';
import '../net/room_client.dart';
import '../net/room_link.dart';
import '../room/room_session.dart';
import 'qr_scan_screen.dart';
import 'lobby_screen.dart';
import 'widgets/responsive.dart';
import '../l10n/l10n.dart';

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.playerName});

  final String playerName;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _browser = RoomBrowser();
  StreamSubscription<List<RoomAd>>? _sub;
  List<RoomAd> _rooms = const [];
  bool _discoveryFailed = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = _browser.rooms.listen((r) => setState(() => _rooms = r));
    _browser.start().catchError((Object _) {
      if (mounted) setState(() => _discoveryFailed = true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _browser.dispose();
    super.dispose();
  }

  Future<void> _join(List<String> hosts, int port, String roomName, {bool askPin = false}) async {
    String? pin;
    if (askPin) {
      pin = await _askPin();
      if (pin == null) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = RoomClient(
      hosts: hosts,
      port: port,
      playerName: widget.playerName,
      pin: pin,
    );
    try {
      await client.connect();
      final session = RoomSession.client(client: client, roomName: client.roomName ?? roomName);
      if (!mounted) {
        await session.close();
        return;
      }
      await _browser.stop();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'lobby'),
        builder: (_) => LobbyScreen(session: session),
      ));
    } on RoomJoinException catch (e) {
      if (!mounted) return;
      // Sala com PIN que não sabíamos: pede-o e tenta outra vez.
      if (!askPin && e.message == tr('PIN errado')) {
        setState(() => _busy = false);
        return _join(hosts, port, roomName, askPin: true);
      }
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<String?> _askPin() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('PIN da sala')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar'))),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr('Entrar')),
          ),
        ],
      ),
    );
  }

  Future<void> _scanQr() async {
    final raw =
        await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (raw == null || !mounted) return;
    final code = JoinCode.tryParse(raw);
    if (code != null) {
      return _join(code.hosts, code.port, code.roomName, askPin: code.hasPin);
    }
    if (raw.startsWith('WIFI:')) {
      setState(() => _error = tr(
          'Esse é o QR do Wi-Fi. Lê-o com a câmara do telemóvel para ligar à rede do anfitrião, volta aqui e escolhe a sala ou lê o QR da sala.'));
    } else {
      setState(() => _error = tr('Este QR code não é de uma sala EDHere.'));
    }
  }

  Future<void> _tryGateway() async {
    final gw = await wifiGatewayIp();
    if (!mounted) return;
    if (gw == null) {
      setState(() => _error = tr('Não encontrei o gateway. Estás ligado a um Wi-Fi?'));
      return;
    }
    await _join([gw], defaultRoomPort, tr('Sala'));
  }

  Future<void> _manualIp() async {
    final ipCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '$defaultRoomPort');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Ligar por IP')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ipCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('IP do anfitrião')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: portCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr('Porta')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar'))),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Ligar')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final ip = ipCtrl.text.trim();
    final port = int.tryParse(portCtrl.text.trim()) ?? defaultRoomPort;
    if (!isValidIPv4(ip)) {
      setState(() => _error = tr('IP inválido: {ip}', {'ip': ip}));
      return;
    }
    await _join([ip], port, tr('Sala'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Entrar numa sala'))),
      body: MaxWidth(
          child: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              Text(tr('Salas na rede'), style: theme.textTheme.titleMedium),
              const SizedBox(width: 10),
              if (!_discoveryFailed)
                const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            const SizedBox(height: 12),
            if (_rooms.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _discoveryFailed
                        ? tr('A descoberta automática falhou nesta rede. Usa o QR code, o gateway ou o IP.')
                        : tr('À procura… Confirma que estás no mesmo Wi-Fi ou hotspot que o anfitrião.'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              for (final room in _rooms)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: Icon(Icons.table_restaurant_rounded, color: scheme.primary),
                      title: Text(room.name),
                      subtitle: Text([
                        room.format,
                        room.freeSeats == 1
                            ? tr('1 lugar livre')
                            : tr('{freeSeats} lugares livres', {'freeSeats': room.freeSeats}),
                        if (room.host != null) '${room.host}:${room.port}',
                        if (room.appVersion != appVersion)
                          tr('versão {appVersion}', {'appVersion': room.appVersion}),
                        if (room.dbVersion != cardDbVersion) tr('base de cartas diferente'),
                      ].join(' · ')),
                      trailing: room.hasPin ? const Icon(Icons.lock_outline) : null,
                      onTap: room.host == null
                          ? null
                          : () => _join([room.host!], room.port, room.name, askPin: room.hasPin),
                    ),
                  ),
                ),
            const SizedBox(height: 24),
            Text(tr('Outras formas'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _scanQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(tr('Ler QR code da sala')),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _tryGateway,
              icon: const Icon(Icons.router_outlined),
              label: Text(tr('Ligar ao hotspot do anfitrião')),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _manualIp,
              icon: const Icon(Icons.keyboard_outlined),
              label: Text(tr('Introduzir IP')),
            ),
            if (_busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_error != null) ...[
              const SizedBox(height: 20),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      )),
    );
  }
}
