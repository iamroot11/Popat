import 'package:flutter/material.dart';
import 'package:myapp/pages/connector.dart';
import 'package:myapp/pages/DiscoveryScreen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {'/': (context) => const DiscoveryScreen()},
    );
  }
}
