import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
    WidgetsFlutterBinding.ensureInitialized();
    


  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform,); 
  runApp(const SpiritPOSApp());
}

class SpiritPOSApp extends StatelessWidget {
  const SpiritPOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: spiritTheme,
      home: const LoginScreen(),
    );
  }
}