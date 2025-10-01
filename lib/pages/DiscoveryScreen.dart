// lib/wifi_connection.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:myapp/pages/DeviceInfo.dart';
import 'package:uuid/uuid.dart';
import 'package:myapp/services/networking_service.dart';
import 'package:myapp/pages/DeviceScreen.dart';


class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final List<DeviceInfo> _devices = [];
  bool _scanning = false;
  String _log = '';

  // Configure ESP32 service name and proto:
  static const String service = '_popat._udp';
  static const String serviceTcp = '_popat._tcp';

  Future<void> _discover() async {
    setState(() {
      _devices.clear();
      _scanning = true;
      _log = 'Scanning...';
    });

    final client = MDnsClient();
    await client.start();

    final found = <String, DeviceInfo>{};

    // Discover UDP Service
    await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(service),
    )) {
      await for (final SrvResourceRecord srv
          in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
          )) {
        await for (final IPAddressResourceRecord ip
            in client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
            )) {
          final key = '${srv.target}:${srv.port}';
          found[key] = DeviceInfo(
            name: srv.target,
            addr: ip.address,
            portUdp: srv.port,
          );
        }
      }
    }

    // Discover TCP Service
    await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(serviceTcp),
    )) {
      await for (final SrvResourceRecord srv
          in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
          )) {
        await for (final IPAddressResourceRecord ip
            in client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
            )) {
          final key = '${srv.target}:${srv.port}';
          final existing = found[key];
          if (existing != null) {
            found[key] = DeviceInfo(
              name: existing.name,
              addr: existing.addr,
              portUdp: existing.portUdp,
              portTcp: srv.port,
            );
          } else {
            found[key] = DeviceInfo(
              name: srv.target,
              addr: ip.address,
              portTcp: srv.port,
            );
          }
        }
      }
    }

    client.stop();

    setState(() {
      _devices.addAll(found.values);
      _scanning = false;
      _log = 'Found ${_devices.length} device(s)';
    });
  }

  void _openDevice(DeviceInfo d) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => DeviceScreen(device: d)));
  }

  @override
  void initState() {
    super.initState();
    _discover();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discvoer Devices')),
      body: Column(
        children: [
          if (_scanning) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _scanning ? null : _discover,
                  icon: const Icon(Icons.search),
                  label: const Text('Scan'),
                ),
                const SizedBox(width: 12),
                Text(_log),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _devices.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final d = _devices[i];
                return ListTile(
                  leading: const Icon(Icons.memory),
                  title: Text(d.name),
                  subtitle: Text(
                    '${d.addr.address} UDP:${d.portUdp ?? '-'} TCP: ${d.portTcp ?? '-'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openDevice(d),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
