import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:myapp/pages/DeviceInfo.dart';
import 'package:uuid/uuid.dart';
import 'package:myapp/services/networking_service.dart';

class DeviceScreen extends StatefulWidget {
  final DeviceInfo device;
  const DeviceScreen({super.key, required this.device});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  final _txt = TextEditingController();
  StreamSubscription? _dataSub;
  StreamSubscription? _logSub;
  StreamSubscription? _stateSub;
  final _uuid = const Uuid();

  String _state = 'idle';
  final List<String> _logs = [];
  final List<String> _received = [];

  bool useUdp = true;

  Future<void> _connect() async {
    final cfg = PacketServiceConfig(
      remoteAddress: widget.device.addr,
      udpPort: widget.device.portUdp ?? 4210,
      tcpPort: widget.device.portTcp ?? 8080,
      useUdp: useUdp,
    );

    await PacketService.instance.start(cfg);
    _dataSub ??= PacketService.instance.onData.listen((bytes) {
      setState(() {
        _received.add(utf8.decode(bytes, allowMalformed: true));
      });
    });
    _logSub ??= PacketService.instance.onLog.listen((t) {
      setState(() {
        _logs.add(t);
      });
    });
    _stateSub ??= PacketService.instance.onState.listen((s) {
      setState(() {
        _state = s;
      });
    });
  }

  void _send() {
    final payload = jsonEncode({
      'id': _uuid.v4(),
      't': DateTime.now().toIso8601String(),
      'type': 'ping',
      'body': _txt.text,
    });
    PacketService.instance.sendText(payload);
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _logSub?.cancel();
    _stateSub?.cancel();

    // Do NOT stop the service on dispose so it survives navigation changes
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    return Scaffold(
      appBar: AppBar(title: Text('Device ${d.name}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('UDP'),
                  selected: useUdp,
                  onSelected: (v) {
                    setState(() => useUdp = true);
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('TCP'),
                  selected: !useUdp,
                  onSelected: (v) {
                    setState(() => useUdp = false);
                  },
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _connect,
                  icon: const Icon(Icons.link),
                  label: const Text('Connect'),
                ),
                const SizedBox(width: 12),
                Text('State: $_state'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _txt,
                    decoration: const InputDecoration(
                      labelText: 'Message JSON',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _send, child: const Text('Send')),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _Panel(
                    title: 'Logs',
                    child: ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (_, i) => Text(_logs[i]),
                    ),
                  ),
                ),
                Expanded(
                  child: _Panel(
                    title: 'Received',
                    child: ListView.builder(
                      itemCount: _received.length,
                      itemBuilder: (_, i) => Text(_received[i]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;
  const _Panel({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            alignment: Alignment.centerLeft,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(padding: const EdgeInsets.all(8), child: child),
          ),
        ],
      ),
    );
  }
}
