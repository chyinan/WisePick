import 'package:flutter/material.dart';
import 'core/auth/login_page.dart';

void main() {
  runApp(const WisePickAdminApp());
}

class WisePickAdminApp extends StatelessWidget {
  const WisePickAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WisePick Admin',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}
