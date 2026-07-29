import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'login_screen.dart';
import 'screens/main_hub_screen.dart';
import 'theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = 'http://f620ef1faeb840549bc58d8bb3d52ac5@glitchtip-oaeu77z41o045sbhwwdwngfk.5.189.157.23.sslip.io/1';
      options.tracesSampleRate = 1.0;
      options.profilesSampleRate = 1.0;
      options.replay.sessionSampleRate = 1.0;
      options.replay.onErrorSampleRate = 1.0;
      options.privacy.maskAllImages = false;
      options.privacy.maskAllText = false;
    },
    appRunner: () async {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

      // Configure Firestore for offline persistence
      FirebaseFirestore firestore = FirebaseFirestore.instance;

      // Enable persistence (works on mobile and web)
      firestore.settings = const Settings(
        persistenceEnabled: true,          // Enable offline cache
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED, // Optional: unlimited cache
      );

      runApp(SentryWidget(child: const SpiritPOSApp()));
    },
  );
}

class SpiritPOSApp extends StatelessWidget {
  const SpiritPOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: spiritTheme,
      home: AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const MainHubScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
