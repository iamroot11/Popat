import 'dart:io';

class DeviceInfo {
  final String name;
  final InternetAddress addr;
  final int? portUdp;
  final int? portTcp;
  DeviceInfo({
    required this.name,
    required this.addr,
    this.portUdp,
    this.portTcp,
  });
}