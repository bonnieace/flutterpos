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
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'checkout/checkout.dart';

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
      final checkoutOutbox = await HiveCheckoutOutbox.open(
        keyProvider: SecureCheckoutOutboxEncryptionKeyProvider(
          storage: const FlutterSecureCheckoutOutboxValueStore(
            FlutterSecureStorage(),
          ),
        ),
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

      TenantInvitationLink? invitationLink;
      var invalidInvitationLink = false;
      try {
        invitationLink = TenantInvitationLink.fromUriIfPresent(Uri.base);
      } on FormatException {
        invalidInvitationLink = true;
      }

      runApp(
        SentryWidget(
          child: SpiritPOSApp(
            bootstrapService: bootstrapService,
            checkoutOutbox: checkoutOutbox,
            invitationLink: invitationLink,
            invalidInvitationLink: invalidInvitationLink,
          ),
        ),
      );
    },
  );
}

class SpiritPOSApp extends StatelessWidget {
  const SpiritPOSApp({
    super.key,
    required this.bootstrapService,
    required this.checkoutOutbox,
    this.invitationLink,
    this.invalidInvitationLink = false,
  });

  final TenantBootstrapService bootstrapService;
  final HiveCheckoutOutbox checkoutOutbox;
  final TenantInvitationLink? invitationLink;
  final bool invalidInvitationLink;

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
        invitationLink: invitationLink,
        invalidInvitationLink: invalidInvitationLink,
        bootstrapService: bootstrapService,
        tenantSwitchStateSources: safeLandingTenantSwitchStateSources(
          checkoutStateSource: CheckoutOutboxTenantSwitchStateSource(
            checkoutOutbox,
          ),
        ),
        tenantSwitchOnlineCheck: () async =>
            await Connectivity().checkConnectivity() != ConnectivityResult.none,
        hasPlatformSuperAdminClaim: (uid) async {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null || user.uid != uid) return false;
          final token = await user.getIdTokenResult();
          return token.claims?['platformRole'] == 'superAdmin';
        },
        signOut: FirebaseAuth.instance.signOut,
        signedOut: const LoginScreen(),
      ),
    );
  }
}
