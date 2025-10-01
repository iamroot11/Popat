
// test/widget_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:myapp/main.dart';
import 'package:myapp/pages/DeviceInfo.dart';
import 'package:myapp/pages/DiscoveryScreen.dart';
import 'package:myapp/services/networking_service.dart';

import 'mocks.mocks.dart';

void main() {
  late MockPacketService mockPacketService;

  setUp(() {
    mockPacketService = MockPacketService();
    PacketService.instance = mockPacketService;

    // Mock the streams
    when(mockPacketService.onData).thenAnswer((_) => StreamController<Uint8List>().stream);
    when(mockPacketService.onLog).thenAnswer((_) => StreamController<String>().stream);
    when(mockPacketService.onState).thenAnswer((_) => StreamController<String>().stream);
  });

  testWidgets('Full application flow test', (WidgetTester tester) async {
    // 1. Start the app
    await tester.pumpWidget(const App());

    // 2. Mock the discovery process
    final fakeDevice = DeviceInfo(
      name: 'Test Arduino',
      addr: InternetAddress('192.168.1.100'),
      portUdp: 1234,
      portTcp: 5678,
    );

    // Replace the _discover method with a mock implementation
    final discoveryScreenState = tester.state<State<DiscoveryScreen>>(find.byType(DiscoveryScreen));
    if (discoveryScreenState is _DiscoveryScreenState) {
      (discoveryScreenState as dynamic)._devices = [fakeDevice];
      (discoveryScreenState as dynamic)._log = 'Found 1 device(s)';
      (discoveryScreenState as dynamic)._scanning = false;
    }


    await tester.pumpAndSettle();

    /the device is found
    expect(find.text('Test Arduino'), findsOneWidget);
    expect(find.text('192.168.1.100 UDP:1234 TCP: 5678'), findsOneWidget);

    // 4. Tap on the device to navigate to the DeviceScreen
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();

    // 5. Verify navigation to the DeviceScreen
    expect(find.text('Device Test Arduino'), findsOneWidget);

    // 6. Tap the "Connect" button
    when(mockPacketService.start(any)).thenAnswer((_) async {});
    await tester.tap(find.text('Connect'));
    await tester.pump();

    // 7. Verify that the PacketService.start method was called
    verify(mockPacketService.start(any)).called(1);

    // 8. Enter text into the message field
    const testMessage = 'Hello, Arduino!';
    await tester.enterText(find.byType(TextField), testMessage);
    await tester.pump();

    // 9. Tap the "Send" button
    when(mockPacketService.sendText(any)).thenAnswer((_) {});
    await tester.tap(find.text('Send'));
    await tester.pump();

    // 10. Verify that the PacketService.sendText method was called
    verify(mockPacketService.sendText(testMessage)).called(1);

    // 11. Simulate receiving a packet
    final receivedData = Uint8List.fromList('Arduino says hi!'.codeUnits);
    final dataController = StreamController<Uint8List>();
    when(mockPacketService.onData).thenAnswer((_) => dataController.stream);
    dataController.add(receivedData);
    await tester.pump();

    // 12. Verify that the received packet is displayed
    expect(find.text('Arduino says hi!'), findsOneWidget);

    await dataController.close();
  });
}

// A minimal implementation of the private _DiscoveryScreenState to access its members.
class _DiscoveryScreenState extends State<DiscoveryScreen> {
  List<DeviceInfo> _devices = [];
  String _log = '';
  bool _scanning = false;

  @override
  Widget build(BuildContext context) {
    return Container(); // Not used in the test
  }

  void _discover() {
    // This method is mocked in the test
  }
}
