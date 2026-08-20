import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'login_screen.dart';
import 'tenancy/tenancy.dart';
import 'theme.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart'
    show CapabilityProfile;

import 'audit/audit.dart';
import 'checkout/checkout.dart';
import 'dev/firebase_emulators.dart';
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
      // **A callable will not leave the device without an App Check provider,
      // and that is what this line is for.** `FirebaseContextProvider` in the
      // Android callable SDK fetches an auth token and an App Check token as one
      // pair; with no provider installed the second throws *No AppCheckProvider
      // installed* and the pair fails as *1 out of 2 underlying tasks failed* —
      // so `listMyTenants` never reaches the wire and the routing shell reports
      // "We could not open your business account", naming a connection that is
      // in fact fine.
      //
      // **Debug builds only, and the debug provider.** It mints a local token
      // that the emulator suite does not verify, which is exactly what a local
      // run needs. A release build is deliberately left as it was: real
      // attestation is Play Integrity plus a registered app in the console, and
      // turning that on here without either would swap one silent failure for
      // another.
      if (kDebugMode) {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: const AndroidDebugProvider(),
          providerApple: const AppleDebugProvider(),
        );
      }
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
      // The printing slice's durable half, and the last piece it was missing.
      // Its own key, for the reason `printJobsStorageKey` gives.
      final checkoutPrintJobs = await HivePrintJobQueue.open(
        keyProvider: SecureCheckoutOutboxEncryptionKeyProvider(
          storage: secureValueStore,
          storageKey:
              SecureCheckoutOutboxEncryptionKeyProvider.printJobsStorageKey,
        ),
      );
      // **Loaded once, here, because it reads an asset.**
      // `CheckoutReceiptBody` takes a *loaded* profile precisely so that a
      // formatter invoked from wherever a sale happens to be committed never
      // does I/O. This is the composition root that owes it one.
      final printerCapabilityProfile = await CapabilityProfile.load();
      // The compile-time platform seam: `dart:io` sockets on mobile and
      // desktop, the loud unsupported stub on web. Built once — the transport
      // holds no mutable state and opens a connection per job.
      final printerTransport = createPrinterTransport();

      // The installation identity is resolved once at startup so every shift
      // and receipt this device records names the same device.
      final deviceId = await checkoutReceiptCounters.resolveDeviceId();
      final connectivity = Connectivity();
      // The one seam between a saved sale and the workers that carry it to the
      // server. Connectivity is piped into it here, once, rather than in
      // `build`, so the shell sees one stream for the life of the process.
      final checkoutSyncSignals = CheckoutSyncSignals();
      connectivity.onConnectivityChanged
          .where((result) => result != ConnectivityResult.none)
          .listen((_) => checkoutSyncSignals.requestSyncAfterReconnect());

      // Configure Firestore for offline persistence
      FirebaseFirestore firestore = FirebaseFirestore.instance;

      // Enable persistence (works on mobile and web)
      firestore.settings = const Settings(
        persistenceEnabled: true, // Enable offline cache
        cacheSizeBytes:
            Settings.CACHE_SIZE_UNLIMITED, // Optional: unlimited cache
      );

      // Deliberately after the assignment above and before the first Firebase
      // call: `useFirestoreEmulator` records its host inside those same
      // settings, so assigning a whole `Settings` afterwards would discard the
      // redirect and send a local run's writes to the real project. Without
      // the `--dart-define` this does nothing at all.
      await connectFirebaseEmulatorsFromEnvironment();

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
            checkoutPrintJobs: checkoutPrintJobs,
            printerCapabilityProfile: printerCapabilityProfile,
            printerTransport: printerTransport,
            tenantShiftState: tenantShiftState,
            deviceId: deviceId,
            connectivity: connectivity,
            invitationLink: invitationLink,
            invalidInvitationLink: invalidInvitationLink,
            checkoutSyncSignals: checkoutSyncSignals,
          ),
        ),
      );
    },
  );
}

/// This device's queue depth, in words, or null when there is nothing to say.
///
/// The wording is `PrinterFailureNotice.queueDepth`; what is here is the read,
/// and the decision that a queue which cannot be listed is not a queue that is
/// empty.
String? _printQueueStatus(HivePrintJobQueue queue) {
  final PrintJobListing listing;
  try {
    listing = queue.pending();
  } catch (_) {
    // A queue that cannot be listed is not a queue that is empty, but the home
    // is not the surface to explain it on — the route itself states it.
    return 'Could not be read';
  }
  return PrinterFailureNotice.queueDepth(
    waiting: listing.jobs.length,
    unreadable: listing.unreadable,
  );
}

/// The shop's own name for the top of a receipt, or null.
///
/// **A branding read that fails must not cost a receipt.** The name is a
/// heading; `CheckoutReceiptBody` already falls back to its own wording when it
/// is absent, so anything that goes wrong reading it is swallowed here rather
/// than propagating into the print hook, where it would be reported as
/// `receipt_not_queued` and the paper would never come out.
Future<String?> _receiptBusinessName(
  TenantSession session,
  TenantDataReader reader,
) async {
  try {
    final branding = await TenantBrandingRepository(
      session: session,
      reader: reader,
    ).load();
    return branding?.companyName;
  } catch (_) {
    return null;
  }
}

class SpiritPOSApp extends StatelessWidget {
  const SpiritPOSApp({
    super.key,
    required this.bootstrapService,
    required this.checkoutOutbox,
    required this.checkoutCatalogCache,
    required this.checkoutReceiptCounters,
    required this.checkoutPrintJobs,
    required this.printerCapabilityProfile,
    required this.printerTransport,
    required this.tenantShiftState,
    required this.deviceId,
    required this.connectivity,
    required this.checkoutSyncSignals,
    this.invitationLink,
    this.invalidInvitationLink = false,
  });

  final TenantBootstrapService bootstrapService;
  final HiveCheckoutOutbox checkoutOutbox;
  final HiveCheckoutCatalogCache checkoutCatalogCache;
  final HiveCheckoutReceiptCounters checkoutReceiptCounters;

  /// The durable print queue, the loaded ESC/POS profile, and the platform
  /// transport. Three fields rather than a pre-built dispatcher because the
  /// dispatcher is cheap and the queue is not: the box is opened once at
  /// startup, and a dispatcher is composed per route from it.
  final HivePrintJobQueue checkoutPrintJobs;
  final CapabilityProfile printerCapabilityProfile;
  final PrinterTransport printerTransport;
  final HiveTenantShiftState tenantShiftState;
  final String deviceId;
  final Connectivity connectivity;
  final CheckoutSyncSignals checkoutSyncSignals;
  final TenantInvitationLink? invitationLink;
  final bool invalidInvitationLink;

  @override
  Widget build(BuildContext context) {
    Future<bool> isOnline() async =>
        await connectivity.checkConnectivity() != ConnectivityResult.none;
    final tenantDataReader = FirebaseTenantDocumentReader();
    // The one call that turns a committed sale into a receipt on its way to
    // paper. Composed here because this is the only place holding all four
    // pieces at once: the durable queue, the platform transport, the loaded
    // ESC/POS profile, and a reader that can say where this business prints.
    final printDispatcher = CheckoutPrintDispatcher(
      queue: checkoutPrintJobs,
      transport: printerTransport,
      profile: printerCapabilityProfile,
    );
    // **Runs after the sale is durable, and can never un-write one.** §6.3
    // applied to printing: the record is written first, the receipt is produced
    // over committed state, and a printer that is off becomes a stated reason
    // rather than a refused sale. `CheckoutPrintDispatcher.dispatch` never
    // throws for a printing reason, so what comes back here is a code or null.
    Future<String?> printReceipt(
      CheckoutOutboxRecord record,
      TenantSession session,
    ) async {
      final printer = await TenantPrinterConfigurationRepository(
        session: session,
        reader: tenantDataReader,
      ).load();
      final result = await printDispatcher.dispatch(
        CheckoutSalePayload.fromOutboxRecord(record, session: session),
        printer: printer,
        // The same value and the same fallback the home's title uses, so the
        // paper and the app name the business identically.
        businessName: await _receiptBusinessName(session, tenantDataReader),
        servedBy: FirebaseAuth.instance.currentUser?.displayName,
      );
      return result.outcome == CheckoutPrintOutcome.sent
          ? null
          : result.reasonCode;
    }
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
    // The only two paths in the app that can ask the server to reconcile and to
    // correct a shift whose totals disagree with its sales. Both are owner- and
    // administrator-only, which the callables themselves enforce, and both are
    // narrower than the roles that read the surfaces they are offered on. The
    // correction can name no figure: the server reads it from the sale-derived
    // total it verified, and never touches the cash counted at close.
    final reconciliationActions = TenantReconciliationActions(
      requestCallable: FirebaseRequestReconciliationCallable(),
      amendShiftSummaryCallable: FirebaseAmendShiftSummaryCallable(),
    );
    // The only path in the app that totals sales the server currently holds,
    // rather than the reconciled figures. It is management-only, which the
    // callable itself enforces, and it can name no business but the session's.
    final salesTotalsCallable = FirebaseSalesTotalsCallable();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: spiritTheme,
      // `design.md` §2.4: bouncing scroll physics everywhere, on both
      // platforms, and no Material overscroll glow. It belongs on the app
      // rather than on each scrollable, because "everywhere" is not a rule
      // three hundred list views can be trusted to remember.
      scrollBehavior: const SpiritScrollBehavior(),
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
          // The order these run in is a tested contract, not a comment here.
          final pass = CheckoutSyncPass(
            recover: coordinator.recoverSelectedSession,
            submit: submissionWorker.submitDueCheckouts,
            refreshCatalog: catalogRefresher.refreshSelectedSession,
            reportEvidenceChanged: checkoutSyncSignals.reportEvidenceChanged,
          );
          return (trigger) async {
            // A sale saved at the till needs submitting and confirming; it does
            // not need the whole product catalog re-read.
            await pass.run(
              refreshDerivedData: trigger is! CheckoutSaveSyncRequest,
            );
            return null;
          };
        },
        tenantRecoveryTriggers: checkoutSyncSignals.syncRequests,
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
          // One product's whole ledger, entered from a row. Deliberately the
          // path-bounded read rather than a `productId`-narrowed group page:
          // both return the same documents in the same order to the same
          // roles, and only this one survives the product being deleted
          // without spending a composite index on the widest read in the app.
          productLedgerRoute: (productId) => TenantProductLedgerScreen(
            reader: reader,
            productId: productId,
          ),
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
          // The decorator is what makes a saved sale reach the server while the
          // till stays open. It is wrapped here rather than inside the screen so
          // the screen still knows only how to save.
          drafts: CheckoutSyncOnSaveDraftSink(
            signals: checkoutSyncSignals,
            delegate: CheckoutDraftService(
              sessionController: sessions,
              cache: checkoutCatalogCache,
              outbox: checkoutOutbox,
              receipts: checkoutReceiptCounters,
              // The frozen restriction that a cashier cannot open checkout in a
              // second business while another still holds an open shift on this
              // device is enforced here, not by the screen.
              shiftBinder: TenantShiftCheckoutBinder(tenantShiftState),
              // The seam that was built and never connected: without it a sale
              // commits and no bytes are ever generated.
              onSaved: printReceipt,
            ),
          ),
        ),
        // The one path in the app that publishes what a till prices in, and the
        // one capability every other operational surface here already assumed:
        // the catalog refresher refuses outright while no usable currency is
        // published, so a business that never opens this route cannot sell at
        // all. Owner and administrator only, which the Firestore rule for
        // `configuration/{documentId}` enforces on its own.
        //
        // A commit asks for a full sync pass, because the catalog refresh is the
        // only thing that re-reads the document: without it this device would
        // keep pricing new sales with the code that was just replaced.
        checkoutConfigurationRoute: (reader) =>
            TenantCheckoutConfigurationScreen(
              reader: reader,
              writer: FirebaseTenantCheckoutConfigurationWriter(
                firestore: FirebaseFirestore.instance,
                isOnline: isOnline,
              ),
              onPublished:
                  checkoutSyncSignals.requestSyncAfterConfigurationChange,
            ),
        checkoutConfigurationRoles:
            TenantCheckoutConfigurationPublisher.allowedRoles,
        // Where this business prints. The last surface printing was missing:
        // `docs/printer_transport.md` §6 forbids guessing an address, so until
        // this has been used once every receipt queues with
        // `printer_not_configured` and no paper comes out.
        //
        // `probe` is the transport's own connect-and-close, handed over so
        // *Test this printer* answers "is it reachable?" against what is typed,
        // before it is saved and without wasting a roll.
        printerConfigurationRoute: (reader) => TenantPrinterConfigurationScreen(
          reader: reader,
          writer: FirebaseTenantConfigurationDocumentWriter(
            firestore: FirebaseFirestore.instance,
            isOnline: isOnline,
          ),
          probe: printerTransport.probe,
        ),
        printerConfigurationRoles:
            TenantPrinterConfigurationPublisher.allowedRoles,
        // This device's unsent receipts, and the one control that can move one:
        // *Send again*. It rebuilds nothing — the bytes on the job are the ones
        // the sale produced, so a receipt retried after a price change still
        // prints what was charged.
        printQueueRoute: () => TenantPrintQueueScreen(
          queue: checkoutPrintJobs,
          onRetry: (receiptNumber) async {
            final result = await printDispatcher.retry(receiptNumber);
            return result.outcome == CheckoutPrintOutcome.sent
                ? null
                : result.reasonCode;
          },
        ),
        printQueueStatus: () => _printQueueStatus(checkoutPrintJobs),
        // The only path in the app that puts a product in the catalog, and the
        // last capability every other operational surface here already assumed.
        // Creating and retiring are direct Firestore writes, because the rules
        // on `products` and `categories` already name exactly the roles this
        // route is offered to: create is owner/admin/manager, delete is
        // owner/admin.
        //
        // Correcting one is the exception and it is a callable. `allow update`
        // on `products` permits a strictly decreasing quantity and nothing else
        // - the checkout decrement - and widening it would trade the guarantee
        // that no client can inflate stock for a price edit that records no
        // actor, no previous value, and no reason. `updateProduct` writes
        // through the Admin SDK instead, so that clause stays byte-identical.
        //
        // A committed change asks for a full sync pass, because the catalog
        // refresh is the only thing that re-reads `products` and `categories`:
        // without it this device could not sell a product that now exists,
        // could still sell one that no longer does, and would keep pricing with
        // a figure that has just been corrected.
        catalogManagementRoute: (reader) => TenantCatalogManagementScreen(
          reader: reader,
          writer: FirebaseTenantCatalogWriter(
            firestore: FirebaseFirestore.instance,
            isOnline: isOnline,
          ),
          updateCallable: FirebaseUpdateProductCallable(),
          // Both bulk halves are callables and neither could be anything else.
          // A correction cannot be a client `WriteBatch` at all, for the reason
          // above. An import could create products past the rules - `allow
          // create` admits the same three roles - but no device can write the
          // `stock_adjustments` record and `stock_movements` entry that give an
          // opening quantity a recorded origin, because both collections are
          // server-write-only. A device import would therefore leave stock with
          // no ledger entry, which is the defect the previous app shipped.
          bulkRoute: (context) => TenantBulkCatalogScreen(
            reader: reader,
            batchCallable: FirebaseUpdateProductsCallable(),
            importCallable: FirebaseImportProductsCallable(),
            onChanged: checkoutSyncSignals.requestSyncAfterCatalogChange,
          ),
          onChanged: checkoutSyncSignals.requestSyncAfterCatalogChange,
        ),
        catalogManagementRoles: TenantCatalogManagementRepository.allowedRoles,
        pendingCheckoutPanel: CheckoutPendingEvidencePanel(
          source: CheckoutOutboxEvidenceSource(checkoutOutbox),
          // Without this the counts are read once when the session opens, so a
          // sale rang up moments earlier is reported as no sale at all.
          refreshSignals: checkoutSyncSignals.evidenceChanges,
        ),
        // §4.4 v0.7's top bar wants the signed-in member's name. Firebase has
        // already loaded it, so this hands over state that exists rather than
        // adding a read to the home - which is what kept the bar blocked for a
        // day. It is frequently null: an identity created by an emailed
        // invitation has no display name until somebody types one.
        memberName: () => FirebaseAuth.instance.currentUser?.displayName,
        signOut: FirebaseAuth.instance.signOut,
        signedOut: const LoginScreen(),
      ),
    );
  }
}
