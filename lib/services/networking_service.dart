// lib/services/networking_service.dart
// Will run indefinitely and is independent of the user interface.
// Uses a singleton + background isolate pattern to avoid being torn down by navigation.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

class PacketServiceConfig {
  // Basic configuration and methods
  final InternetAddress remoteAddress;
  final int udpPort;
  final int tcpPort;
  final bool useUdp;

  const PacketServiceConfig({
    required this.remoteAddress,
    required this.udpPort,
    required this.tcpPort,
    required this.useUdp,
  });

  // Convert PacketServiceConfig to JSON
  Map<String, dynamic> toJson() => {
    'remote': remoteAddress.address,
    'udpPort': udpPort,
    'tcpPort': tcpPort,
    'useUdp': useUdp,
  };

  // Convert JSON to PacketServiceConfig
  static PacketServiceConfig fromJson(Map<String, dynamic> json) {
    return PacketServiceConfig(
      remoteAddress: InternetAddress(json['remote'] as String),
      udpPort: json['udpPort'] as int,
      tcpPort: json['tcpPort'] as int,
      useUdp: json['useUdp'] as bool,
    );
  }
}

class PacketMessage {
  final String type; // Types include: 'data', 'log', 'error', 'state'
  final Uint8List? bytes;
  final String? text;

  // Constructors for different kinds of messages sent.
  const PacketMessage.data(this.bytes) : type = 'data', text = null;
  const PacketMessage.log(this.text) : type = 'log', bytes = null;
  const PacketMessage.error(this.text) : type = 'error', bytes = null;
  const PacketMessage.state(this.text) : type = 'state', bytes = null;
}

class PacketService {
  // Singleton access in the UI isolate
  static final PacketService instance = PacketService._internal();
  PacketService._internal();

  // Streams for UI
  final _dataController = StreamController<Uint8List>.broadcast();
  final _logController = StreamController<String>.broadcast();
  final _stateController = StreamController<String>.broadcast();

  Stream<Uint8List> get onData => _dataController.stream;
  Stream<String> get onLog => _logController.stream;
  Stream<String> get onState => _stateController.stream;

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;

  bool get running => _isolate != null && _sendPort != null;

  // Start Method
  Future<void> start(PacketServiceConfig config) async {
    if (running) return;

    _receivePort = ReceivePort();
    _receivePort!.listen(_handleIsolateMessage);

    final initArgs = {
      'config': config.toJson(),
      'replyPort': _receivePort!.sendPort,
    };
    _isolate = await Isolate.spawn(
      _isolateMain,
      initArgs,
      debugName: 'PacketServiceIsolate',
    );
  }

  // Stop Method
  Future<void> stop() async {
    _sendPort?.send({'cmd': 'shutdown'});
    _sendPort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;

    await _dataController.close();
    await _logController.close();
    await _stateController.close();
  }

  // Send Bytes
  void sendBytes(Uint8List bytes) {
    _sendPort?.send({'cmd': 'send_bytes', 'data': bytes});
  }

  void sendText(String text) {
    final bytes = Uint8List.fromList(utf8.encode(text));
    sendBytes(bytes);
  }

  void _handleIsolateMessage(dynamic message) {
    if (message is SendPort) {
      _sendPort = message;
      _stateController.add('connected');
    } else if (message is Map && message['type'] == 'data') {
      _dataController.add(message['data'] as Uint8List);
    } else if (message is Map && message['type'] == 'log') {
      _logController.add(message['text'] as String);
    } else if (message is Map && message['type'] == 'state') {
      _stateController.add(message['text'] as String);
    } else if (message is Map && message['type'] == 'error') {
      _logController.add('[ERROR] ${message['text']}');
      _stateController.add('error');
    }
  }

  // ==== Isolate Entry ====
  static Future<void> _isolateMain(dynamic args) async {
    final argMap = args as Map;
    final replyPort = argMap['replyPort'] as SendPort;
    final cfg = PacketServiceConfig.fromJson(
      Map<String, dynamic>.from(argMap['config'] as Map),
    );

    final commandPort = ReceivePort();
    replyPort.send(commandPort.sendPort);

    // State
    RawDatagramSocket? udpSocket;
    Socket? tcpSocket;
    StreamSubscription? udpSub;
    StreamSubscription<List<int>>? tcpSub;

    // Helpers to talk back to UI isolate
    void sendLog(String t) => replyPort.send({'type': 'log', 'text': t});
    void sendState(String t) => replyPort.send({'type': 'state', 'text': t});
    void sendData(Uint8List t) => replyPort.send({'type': 'data', 'data': t});
    void sendErr(String t) => replyPort.send({'type': 'error', 'text': t});

    Future<void> setupUdp() async {
      try {
        // Bind to any address, ephermal port for client
        udpSocket = await RawDatagramSocket.bind(
          cfg.remoteAddress.type == InternetAddressType.IPv6
              ? InternetAddress.anyIPv6
              : InternetAddress.anyIPv4,
          0,
        );

        udpSocket!.readEventsEnabled = true;
        udpSub = udpSocket!.listen((event) {
          if (event == RawSocketEvent.read) {
            final datagram = udpSocket!.receive();
            if (datagram != null) {
              sendData(Uint8List.fromList(datagram.data));
            }
          }
        });
        sendLog('UDP bound, targe ${cfg.remoteAddress.address}:${cfg.udpPort}');
        sendState('udp-ready');
      } catch (e) {
        sendErr('UDP Setup failed: $e');
      }
    }

    Future<void> setupTcp() async {
      try {
        tcpSocket = await Socket.connect(
          cfg.remoteAddress,
          cfg.tcpPort,
          timeout: const Duration(seconds: 5),
        );
        tcpSub = tcpSocket!.listen(
          (chunk) => sendData(Uint8List.fromList(chunk)),
          onError: (e) => sendErr('TCP read error: $e'),
          onDone: () => sendState('tcp-closed'),
          cancelOnError: true,
        );
        sendLog('TCP connected ${cfg.remoteAddress.address}:${cfg.tcpPort}');
        sendState('tcp-ready');
      } catch (e) {
        sendErr('TCP connect failed: $e');
      }
    }

    // Initialize chosen transport
    if (cfg.useUdp) {
      await setupUdp();
    } else {
      await setupTcp();
    }

    // Command Loop
    await for (final msg in commandPort) {
      if (msg is Map && msg['cmd'] == 'send_bytes') {
        final data = msg['data'] as Uint8List;
        if (cfg.useUdp && udpSocket != null) {
          try {
            udpSocket!.send(data, cfg.remoteAddress, cfg.udpPort);
          } catch (e) {
            sendErr('UDP send failed: $e');
          }
        } else if (!cfg.useUdp && tcpSocket != null) {
          try {
            tcpSocket!.add(data);
            await tcpSocket!.flush();
          } catch (e) {
            sendErr('TCP send failed: $e');
          }
        } else {
          sendErr('No active transport to send');
        }
      } else if (msg is Map && msg['cmd'] == 'shutdown') {
        await udpSub?.cancel();
        udpSocket?.close();
        await tcpSub?.cancel();
        await tcpSocket?.close();
        sendState('stopped');
        break;
      }
    }
  }
}
