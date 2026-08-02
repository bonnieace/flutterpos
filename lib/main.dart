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

import 'audit/audit.dart';
import 'checkout/checkout.dart';
import 'inventory/inventory.dart';
import 'reporting/reporting.dart';
import 'returns/returns.dart';
import 'sales/sales.dart';
import 'shift/shift.dart';

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
      const secureValueStore = FlutterSecureCheckoutOutboxValueStore(
        FlutterSecureStorage(),
      );
      final checkoutOutbox = await HiveCheckoutOutbox.open(
        keyProvider: SecureCheckoutOutboxEncryptionKeyProvider(
          storage: secureValueStore,
        ),
      );
      final checkoutCatalogCache = await HiveCheckoutCatalogCache.open(
        keyProvider: SecureCheckoutOutboxEncryptionKeyProvider(
          storage: secureValueStore,
          storageKey:
              SecureCheckoutOutboxEncryptionKeyProvider.catalogCacheStorageKey,
        ),
      );
      // Receipt counters, shift state, and the outbox share one key: a sale,
      // the receipt numbering it draws from, and the shift it belongs to must
      // share exactly one fate.
      final checkoutReceiptCounters = await HiveCheckoutReceiptCounters.open(
        keyProvider: SecureCheckoutOutboxEncryptionKeyProvider(
          storage: secureValueStore,
        ),
      );
      final tenantShiftState = await HiveTenantShiftState.open(
        keyProvider: SecureCheckoutOutboxEncryptionKeyProvider(
          storage: secureValueStore,
        ),
      );
      // The installation identity is resolved once at startup so every shift
      // and receipt this device records names the same device.
      final deviceId = await checkoutReceiptCounters.resolveDeviceId();
      final connectivity = Connectivity();

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
            checkoutCatalogCache: checkoutCatalogCache,
            checkoutReceiptCounters: checkoutReceiptCounters,
            tenantShiftState: tenantShiftState,
            deviceId: deviceId,
            connectivity: connectivity,
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
    required this.checkoutCatalogCache,
    required this.checkoutReceiptCounters,
    required this.tenantShiftState,
    required this.deviceId,
    required this.connectivity,
    this.invitationLink,
    this.invalidInvitationLink = false,
  });

  final TenantBootstrapService bootstrapService;
  final HiveCheckoutOutbox checkoutOutbox;
  final HiveCheckoutCatalogCache checkoutCatalogCache;
  final HiveCheckoutReceiptCounters checkoutReceiptCounters;
  final HiveTenantShiftState tenantShiftState;
  final String deviceId;
  final Connectivity connectivity;
  final TenantInvitationLink? invitationLink;
  final bool invalidInvitationLink;

  @override
  Widget build(BuildContext context) {
    Future<bool> isOnline() async =>
        await connectivity.checkConnectivity() != ConnectivityResult.none;
    final tenantDataReader = FirebaseTenantDocumentReader();
    // Recording a pending return changes no stock and is open to every active
    // member; restoring it is management-only and runs through the callable, so
    // the two stay a deliberate two-person control. The same actions reach the
    // returns route from shift history and from a receipt lookup.
    final returnActions = TenantReturnActions(
      writer: FirebaseTenantReturnWriter(
        firestore: FirebaseFirestore.instance,
        isOnline: isOnline,
      ),
      verifyCallable: FirebaseVerifyReturnCallable(),
    );
    // The only path in the app that can set stock to an arbitrary figure.
    // It is management-only, which the callable itself enforces, and it is
    // reached one product at a time from the read-only catalog.
    final stockActions = TenantStockActions(
      adjustCallable: FirebaseAdjustStockCallable(),
    );
    // The only path in the app that can ask the server to reconcile. It is
    // owner- and administrator-only, which the callable itself enforces, and
    // it is narrower than the roles that read the surface it is offered on.
    final reconciliationActions = TenantReconciliationActions(
      requestCallable: FirebaseRequestReconciliationCallable(),
    );
    // The only path in the app that totals sales the server currently holds,
    // rather than the reconciled figures. It is management-only, which the
    // callable itself enforces, and it can name no business but the session's.
    final salesTotalsCallable = FirebaseSalesTotalsCallable();

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
        // `emailVerified` above is a claim inside the cached ID token, so it
        // does not change when the user follows the link in their mailbox.
        // Reloading is the only way the app can observe a verification it did
        // not itself perform, which is what makes "I have verified" honest.
        reloadIdentity: () async =>
            FirebaseAuth.instance.currentUser?.reload(),
        // Turns a silent non-delivery into a stated one. Without it a user
        // whose address is suppressed sees the request accepted and taps send
        // again indefinitely.
        emailDeliveryStatusCallable: FirebaseEmailDeliveryStatusCallable(),
        invitationLink: invitationLink,
        invalidInvitationLink: invalidInvitationLink,
        bootstrapService: bootstrapService,
        tenantSwitchStateSources: safeLandingTenantSwitchStateSources(
          checkoutStateSource: CheckoutOutboxTenantSwitchStateSource(
            checkoutOutbox,
          ),
          cashCloseStateSource: TenantShiftSwitchStateSource(tenantShiftState),
        ),
        tenantSwitchOnlineCheck: () async => isOnline(),
        tenantSessionRecoveryFactory: (sessionController) {
          final coordinator = CheckoutRecoveryCoordinator(
            sessionController: sessionController,
            outbox: checkoutOutbox,
            confirmationGateway: FirebaseCheckoutConfirmationGateway(
              firestore: FirebaseFirestore.instance,
              isOnline: isOnline,
            ),
          );
          final submissionWorker = CheckoutSubmissionWorker(
            sessionController: sessionController,
            outbox: checkoutOutbox,
            submissionGateway: FirebaseCheckoutSubmissionGateway(
              firestore: FirebaseFirestore.instance,
              isOnline: isOnline,
            ),
            isOnline: isOnline,
          );
          final catalogRefresher = CheckoutCatalogCacheRefresher(
            sessionController: sessionController,
            cache: checkoutCatalogCache,
            reader: tenantDataReader,
          );
          // Uncertain prior attempts are settled before any new batch commit.
          // The derived catalog cache refreshes last; it never gates evidence.
          return () async => (
            await coordinator.recoverSelectedSession(),
            await submissionWorker.submitDueCheckouts(),
            await catalogRefresher.refreshSelectedSession(),
          );
        },
        tenantRecoveryTriggers: connectivity.onConnectivityChanged
            .where((result) => result != ConnectivityResult.none)
            .map<Object?>((_) => null),
        hasPlatformSuperAdminClaim: (uid) async {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null || user.uid != uid) return false;
          final token = await user.getIdTokenResult();
          return token.claims?['platformRole'] == 'superAdmin';
        },
        tenantDataReader: tenantDataReader,
        // The reconciled totals, and - one day at a time - why each day is in
        // the state it is. The explanation is reached from the summary itself
        // rather than from the landing screen, because that is where a manager
        // already asks whether a day is reconciled.
        dailySummaryRoute: (reader) => TenantDailySummaryScreen(
          reader: reader,
          reconciliationRoute: (businessDate) =>
              TenantReconciliationStatusScreen(
                reader: reader,
                businessDate: businessDate,
                actions: reconciliationActions,
              ),
          reconciliationRoles:
              TenantReconciliationStatusRepository.allowedRoles,
          // Reached from the summary rather than the landing screen for the
          // same reason: the summary is where somebody learns that today has
          // no reconciled figures yet, and this is the answer to that.
          salesTotalsRoute: () => TenantSalesTotalsScreen(
            callable: salesTotalsCallable,
            reader: reader,
          ),
          salesTotalsRoles: TenantSalesTotalsGateway.allowedRoles,
        ),
        dailySummaryRoles: TenantDailyMetricsRepository.allowedRoles,
        receiptLookupRoute: (reader) => TenantReceiptLookupScreen(
          reader: reader,
          returnActions: returnActions,
        ),
        receiptLookupRoles: TenantReceiptLookupRepository.allowedRoles,
        productStockRoute: (reader, product) => TenantProductStockScreen(
          reader: reader,
          product: product,
          actions: stockActions,
        ),
        productStockRoles: TenantProductStockRepository.allowedRoles,
        // The business-wide record of every correction the callable above ever
        // made. It is read-only: an adjustment cannot be undone, only followed
        // by another one.
        stockAdjustmentFeedRoute: (reader) =>
            TenantStockAdjustmentFeedScreen(reader: reader),
        stockAdjustmentFeedRoles:
            TenantStockAdjustmentFeedRepository.allowedRoles,
        // Everything that moved stock, of which the corrections above are only
        // one source. It is the one read in the app that Firestore does not
        // bound by a path prefix, so the collection-group boundary is injected
        // explicitly rather than folded into the general tenant data reader.
        stockMovementFeedRoute: (reader) => TenantStockMovementFeedScreen(
          reader: reader,
          groupReader: tenantDataReader,
        ),
        stockMovementFeedRoles: TenantStockMovementFeedRepository.allowedRoles,
        // The whole business's event trail: who was invited, deactivated, or
        // recovered, and every lifecycle change the platform made. It is
        // deliberately narrower than the stock surfaces above.
        auditLogRoute: (reader) => TenantAuditLogScreen(reader: reader),
        auditLogRoles: TenantAuditLogRepository.allowedRoles,
        shiftPanel: TenantShiftPanel(
          historyReader: tenantDataReader,
          returnActions: returnActions,
          controllerFactory: (sessions) => TenantShiftController(
            sessionController: sessions,
            localState: tenantShiftState,
            reader: tenantDataReader,
            writer: FirebaseTenantShiftWriter(
              firestore: FirebaseFirestore.instance,
              isOnline: isOnline,
            ),
            // The outbox is the only local record of what this device sold, so
            // it is also the only evidence a closing summary may be built from.
            salesLedger: CheckoutOutboxShiftSalesLedger(checkoutOutbox),
            deviceId: deviceId,
            isOnline: isOnline,
          ),
        ),
        // The till, reachable for the first time. Everything below it already
        // existed: the draft service refuses a checkout with no proven open
        // shift, the submission worker and recovery coordinator above pick a
        // saved draft up on their own, and neither is reachable from here.
        //
        // The service is built per navigation because it must bind to the live
        // session controller. That is safe: receipt allocation and every outbox
        // mutation serialize on locks held by the boxes themselves, not by this
        // object, so two instances can never issue the same receipt number.
        checkoutRoute: (sessions) => TenantCheckoutScreen(
          cache: checkoutCatalogCache,
          drafts: CheckoutDraftService(
            sessionController: sessions,
            cache: checkoutCatalogCache,
            outbox: checkoutOutbox,
            receipts: checkoutReceiptCounters,
            // The frozen restriction that a cashier cannot open checkout in a
            // second business while another still holds an open shift on this
            // device is enforced here, not by the screen.
            shiftBinder: TenantShiftCheckoutBinder(tenantShiftState),
          ),
        ),
        pendingCheckoutPanel: CheckoutPendingEvidencePanel(
          source: CheckoutOutboxEvidenceSource(checkoutOutbox),
        ),
        signOut: FirebaseAuth.instance.signOut,
        signedOut: const LoginScreen(),
      ),
    );
  }
}
