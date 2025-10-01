// test/networking_service_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/services/networking_service.dart';

void main() {
  group('PacketServiceConfig', () {
    test('toJson returns correct map', () {
      final config = PacketServiceConfig(
        remoteAddress: InternetAddress('127.0.0.1'),
        udpPort: 1234,
        tcpPort: 5678,
        useUdp: true,
      );

      final json = config.toJson();

      expect(json['remote'], '127.0.0.1');
      expect(json['udpPort'], 1234);
      expect(json['tcpPort'], 5678);
      expect(json['useUdp'], true);
    });

    test('fromJson returns correct object', () {
      final json = {
        'remote': '192.168.1.1',
        'udpPort': 4321,
        'tcpPort': 8765,
        'useUdp': false,
      };

      final config = PacketServiceConfig.fromJson(json);

      expect(config.remoteAddress.address, '192.168.1.1');
      expect(config.udpPort, 4321);
      expect(config.tcpPort, 8765);
      expect(config.useUdp, false);
    });
  });

  group('PacketMessage', () {
    test('PacketMessage.data creates a data message', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final message = PacketMessage.data(bytes);

      expect(message.type, 'data');
      expect(message.bytes, bytes);
      expect(message.text, isNull);
    });

    test('PacketMessage.log creates a log message', () {
      const text = 'This is a log';
      const message = PacketMessage.log(text);

      expect(message.type, 'log');
      expect(message.text, text);
      expect(message.bytes, isNull);
    });

    test('PacketMessage.error creates an error message', () {
      const text = 'This is an error';
      const message = PacketMessage.error(text);

      expect(message.type, 'error');
      expect(message.text, text);
      expect(message.bytes, isNull);
    });

    test('PacketMessage.state creates a state message', () {
      const text = 'This is a state';
      const message = PacketMessage.state(text);

      expect(message.type, 'state');
      expect(message.text, text);
      expect(message.bytes, isNull);
    });
  });
}
