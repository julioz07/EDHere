import 'package:card_db/card_db.dart' show GameFormat;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../net/discovery.dart';
import '../net/host_server.dart';
import '../net/hotspot.dart';
import '../net/network_util.dart';
import '../room/room_session.dart';
import 'lobby_screen.dart';
import 'widgets/responsive.dart';
import '../l10n/l10n.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key, required this.playerName});

  final String playerName;

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  late final _roomName = TextEditingController(text: tr('Mesa de {playerName}', {'playerName': widget.playerName}));
  final _pin = TextEditingController();
  int _seats = 4;
  String _format = 'commander';
  bool _useHotspot = false;
  bool _busy = false;
  String? _error;

  static bool _permissionsExplained = false;

  /// Explica as permissões antes de o sistema as pedir.
  Future<bool> _explainPermissions() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Criar uma rede para a mesa')),
        content: Text(
          tr('Para criar o hotspot, o Android vai pedir a permissão "Dispositivos próximos" (Android 13 ou mais recente) ou "Localização" (Android 8 a 12).\n\nO EDHere só a usa para criar a rede local da mesa. Não guarda nem envia a tua localização.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Agora não'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Continuar'))),
        ],
      ),
    );
    return ok == true;
  }

  @override
  void dispose() {
    _roomName.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    HotspotInfo? hotspot;
    HostServer? server;
    RoomAdvertiser? advertiser;
    try {
      if (_useHotspot) {
        if (!_permissionsExplained) {
          final ok = await _explainPermissions();
          if (!ok) {
            setState(() => _busy = false);
            return;
          }
          _permissionsExplained = true;
        }
        hotspot = await Hotspot.start();
      }

      final name = _roomName.text.trim().isEmpty
          ? tr('Mesa de {playerName}', {'playerName': widget.playerName})
          : _roomName.text.trim();
      final pin = _pin.text.trim();
      server = HostServer(
        roomName: name,
        hostName: widget.playerName,
        pin: pin.isEmpty ? null : pin,
        maxSeats: _seats,
      );
      await server.start();

      // O anúncio mDNS é opcional: se falhar, o QR e o IP continuam a dar.
      advertiser = RoomAdvertiser();
      try {
        await advertiser.start(RoomAd(
          name: name,
          port: server.port,
          format: _format,
          freeSeats: _seats - 1,
          hasPin: pin.isNotEmpty,
          appVersion: appVersion,
          dbVersion: cardDbVersion,
        ));
      } catch (_) {
        advertiser = null;
      }

      final session = RoomSession.host(
        server: server,
        roomName: name,
        hostAddresses: await localIPv4Addresses(preferHotspot: hotspot != null),
        advertiser: advertiser,
        hotspot: hotspot,
        hasPin: pin.isNotEmpty,
      );
      if (!mounted) {
        await session.close();
        return;
      }
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'lobby'),
        builder: (_) => LobbyScreen(
          session: session,
          format: _format,
          life: GameFormat.byId(_format).startingLife,
        ),
      ));
    } catch (e) {
      await server?.close();
      await advertiser?.stop();
      if (hotspot != null) await Hotspot.stop();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Criar sala'))),
      // "Abrir sala" fica fora da lista: sempre à vista, mesmo com o teclado.
      body: Column(children: [
        Expanded(
          child: MaxWidth(
              child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: _roomName,
                maxLength: 40,
                decoration: InputDecoration(labelText: tr('Nome da sala'), counterText: ''),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _format,
                decoration: InputDecoration(labelText: tr('Formato')),
                items: [
                  for (final f in GameFormat.all) DropdownMenuItem(value: f.id, child: Text(f.label)),
                ],
                onChanged: _busy ? null : (v) => setState(() => _format = v ?? _format),
              ),
              const SizedBox(height: 20),
              Text(tr('Lugares: {seats}', {'seats': _seats}), style: theme.textTheme.titleSmall),
              Slider(
                value: _seats.toDouble(),
                min: 2,
                max: 6,
                divisions: 4,
                label: '$_seats',
                onChanged: _busy ? null : (v) => setState(() => _seats = v.round()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pin,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: tr('PIN (opcional)'),
                  helperText: tr('Impede que estranhos na mesma rede entrem'),
                  helperMaxLines: 2,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              if (Hotspot.isSupported)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _useHotspot,
                  onChanged: _busy ? null : (v) => setState(() => _useHotspot = v),
                  title: Text(tr('Criar hotspot (sem Wi-Fi)')),
                  subtitle:
                      Text(tr('Este telemóvel cria uma rede local. Os outros ligam-se a ela pelo QR code do Wi-Fi.')),
                )
              else
                Text(
                  tr('Sem Wi-Fi? Liga o Hotspot Pessoal nas Definições do iPhone e pede aos outros que se liguem a ele.'),
                  style: theme.textTheme.bodySmall,
                ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          )),
        ),
        BottomActions(children: [
          FilledButton(
            onPressed: _busy ? null : _create,
            child: _busy
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(tr('Abrir sala')),
          ),
        ]),
      ]),
    );
  }
}
