import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'login_screen.dart';
import 'tenancy/tenancy.dart';
import 'theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn =
          'http://f620ef1faeb840549bc58d8bb3d52ac5@glitchtip-oaeu77z41o045sbhwwdwngfk.5.189.157.23.sslip.io/1';
      options.tracesSampleRate = 1.0;
      options.profilesSampleRate = 1.0;
      options.replay.sessionSampleRate = 1.0;
      options.replay.onErrorSampleRate = 1.0;
      options.privacy.maskAllImages = false;
      options.privacy.maskAllText = false;
    },
    appRunner: () async {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await Hive.initFlutter();
      final tenantSelectionBox = await Hive.openBox<String>(
        HiveTenantSelectionStore.boxName,
      );

      // Configure Firestore for offline persistence
      FirebaseFirestore firestore = FirebaseFirestore.instance;

      // Enable persistence (works on mobile and web)
      firestore.settings = const Settings(
        persistenceEnabled: true, // Enable offline cache
        cacheSizeBytes:
            Settings.CACHE_SIZE_UNLIMITED, // Optional: unlimited cache
      );

      final tenantGateway = FirebaseTenantGateway();
      final bootstrapService = TenantBootstrapService(
        rootGateway: tenantGateway,
        directory: TenantDirectory(tenantGateway),
        selectionStore: HiveTenantSelectionStore(tenantSelectionBox),
      );

      runApp(
        SentryWidget(child: SpiritPOSApp(bootstrapService: bootstrapService)),
      );
    },
  );
}

class SpiritPOSApp extends StatelessWidget {
  const SpiritPOSApp({super.key, required this.bootstrapService});

  final TenantBootstrapService bootstrapService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: spiritTheme,
      home: TenantRoutingShell(
        authUidChanges: FirebaseAuth.instance.authStateChanges().map(
          (user) => user?.uid,
        ),
        isEmailVerified: (uid) {
          final user = FirebaseAuth.instance.currentUser;
          return user != null && user.uid == uid && user.emailVerified;
        },
        bootstrapService: bootstrapService,
        signOut: FirebaseAuth.instance.signOut,
        signedOut: const LoginScreen(),
      ),
    );
  }
}
