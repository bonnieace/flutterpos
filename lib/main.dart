import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'observability/app_telemetry.dart';
import 'observability/glitchtip_telemetry.dart';
import 'storage/device_storage.dart';
import 'storage/device_storage_screen.dart';
import 'login_screen.dart';
import 'tenancy/tenancy.dart';
import 'tenancy/tenant_configuration_screens.dart';
import 'theme.dart';
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
import 'expenses/expenses.dart';
import 'inventory/inventory.dart';
import 'platform/device_identity.dart';
import 'platform/play_update_gate.dart';
import 'reporting/reporting.dart';
import 'reports/report_saver.dart';
import 'returns/returns.dart';
import 'sales/sales.dart';
import 'production/production.dart';
import 'shift/shift.dart';
import 'suppliers/suppliers.dart';
import 'customers/customers.dart';
import 'whatsapp/whatsapp.dart';
import 'ui/routes.dart';

Future<void> main() async {
  AppTelemetry.install(GlitchTipTelemetry());
  await SentryFlutter.init(
    (options) {
      // Build-time settings apply to debug and release builds. An empty DSN
      // disables reporting while allowing the app to start normally.
      options.dsn = firebaseEmulatorsRequested
          ? ''
          : const String.fromEnvironment(
              'SENTRY_DSN',
              defaultValue:
                  'https://fa5d44ec2b4745d6862d85ebfe2a5f36@glitchtip.uzanet.co.ke/1',
            );
      options.environment = const String.fromEnvironment(
        'SENTRY_ENVIRONMENT',
        defaultValue: 'sit',
      );
      const release = String.fromEnvironment('SENTRY_RELEASE');
      if (release.isNotEmpty) {
        options.release = release;
      }
      // Otherwise the SDK derives the release from the native app version.
      options.tracesSampleRate = 1.0;
      options.sampleRate = 1.0;
      options.maxBreadcrumbs = 100;
      options.beforeSend = scrubGlitchTipEvent;
      options.beforeSendTransaction = scrubGlitchTipTransaction;
      options.enableAutoSessionTracking = false;
      // GlitchTip uses error reports and sampled traces. Leave profiling at
      // its disabled default and disable both replay capture modes.
      options.replay.sessionSampleRate = 0.0;
      options.replay.onErrorSampleRate = 0.0;
      options.sendDefaultPii = false;
      options.privacy.maskAllImages = true;
      options.privacy.maskAllText = true;
    },
    appRunner: () async {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      // **No App Check provider, and no plugin to install one, since
      // 2026-09-28.** One was activated here - the debug provider in debug,
      // Play Integrity in release - for an app nobody had registered, against
      // a backend that enforces nothing. Every Firebase SDK waits for a token
      // before it sends, so on a phone the launch's `users` read waited 10-15
      // seconds for Play Integrity to be refused, ran out its 8-second
      // deadline, and told the person they were offline on every cold start.
      //
      // App Check's component is still in the build, through the native
      // Storage SDK. With no provider a token request fails at once and every
      // SDK sends without one, which a phone confirmed on Wi-Fi and 4G.
      // `app_check_off_test.dart` says what bringing App Check back takes.
      await Hive.initFlutter();
      // **No store that fails to open may stop the till for good.** Each one
      // below opens through the gate: a torn final write is repaired, anything
      // else asks whoever is holding the phone whether to try again or carry
      // on without that store, whose file is then set aside rather than
      // deleted. See `lib/storage/device_storage.dart`.
      DeviceStorage.directory = (await getApplicationDocumentsDirectory()).path;
      var storageQuestion = 0;
      final deviceStorage = DeviceStorageGate(
        ask: (store, {required canContinue}) {
          final answer = Completer<DeviceStorageChoice>();
          runApp(
            DeviceStorageProblemApp(
              theme: spiritTheme,
              store: store,
              canContinue: canContinue,
              onChoice: answer.complete,
              attempt: storageQuestion++,
            ),
          );
          return answer.future;
        },
      );
      final tenantSelectionBox = await Hive.openBox<String>(
        HiveTenantSelectionStore.boxName,
      );
      const secureValueStore = FlutterSecureCheckoutOutboxValueStore(
        FlutterSecureStorage(),
      );
      final checkoutOutbox = await deviceStorage.open(
        DeviceStore.checkoutOutbox,
        () => HiveCheckoutOutbox.open(
          keyProvider: SecureCheckoutOutboxEncryptionKeyProvider(
            storage: secureValueStore,
          ),
        ),
      );
      final tenantMutationStore = await deviceStorage.open(
        DeviceStore.tenantMutations,
        () => TenantPendingMutationStore.open(
          keyProvider: SecureCheckoutOutboxEncryptionKeyProvider(
            storage: secureValueStore,
            storageKey: SecureCheckoutOutboxEncryptionKeyProvider
                .tenantMutationStorageKey,
          ),
        ),
      );
      // **What the till has sold since the catalog was last read.** A sale
      // does not refresh the catalog - that would re-read every product in the
      // business on every customer - so without this the register reports the
      // stock some earlier refresh saw and drifts all day. Held in memory: a
      // refresh happens whenever a session opens or connectivity returns, so
      // the tally never needs to outlive the process. One instance, because
      // the cache subtracts what the draft service records.
      final checkoutCatalogLocalSales = CheckoutCatalogLocalSales();
      final checkoutCatalogCache = await deviceStorage.open(
        DeviceStore.catalogCache,
        () => HiveCheckoutCatalogCache.open(
          keyProvider: SecureCheckoutOutboxEncryptionKeyProvider(
            storage: secureValueStore,
            storageKey: SecureCheckoutOutboxEncryptionKeyProvider
                .catalogCacheStorageKey,
          ),
          localSales: checkoutCatalogLocalSales,
        ),
      );
      // Product photographs waiting for Storage. Its own box and its own key
      // for the reasons `productImageDraftStorageKey` gives: these are
      // megabytes of a shop's own pictures with no second copy anywhere, and
      // they must not share a fate with the record of a sale.
      final productImageDrafts = await deviceStorage.open(
        DeviceStore.productImageDrafts,
        () => HiveTenantProductImageDrafts.open(
          keyProvider: SecureCheckoutOutboxEncryptionKeyProvider(
            storage: secureValueStore,
            storageKey: SecureCheckoutOutboxEncryptionKeyProvider
                .productImageDraftStorageKey,
          ),
        ),
      );
      // A stock count in progress. Its own box, because a count is an hour of
      // somebody's attention with no second copy anywhere and must not share a
      // fate with the record of a sale - the same argument the photograph
      // drafts above make for themselves.
      final stockTakeDrafts = await deviceStorage.open(
        DeviceStore.stockTakeDrafts,
        () => HiveTenantStockTakeDrafts.open(
          keyProvider: SecureCheckoutOutboxEncryptionKeyProvider(
            storage: secureValueStore,
            storageKey: SecureCheckoutOutboxEncryptionKeyProvider
                .productImageDraftStorageKey,
          ),
        ),
      );
      // The request IDs of an import that has not finished. Its own box for the
      // reason the count above has one: what it holds is the only thing that
      // can tell a stopped import from a fresh one, and losing it with a sale
      // would mean creating four hundred products twice.
      final productImportAttempts = await deviceStorage.open(
        DeviceStore.productImportAttempts,
        () => HiveTenantProductImportAttempts.open(
          keyProvider: SecureCheckoutOutboxEncryptionKeyProvider(
            storage: secureValueStore,
            storageKey: SecureCheckoutOutboxEncryptionKeyProvider
                .productImageDraftStorageKey,
          ),
        ),
      );
      // The request id of a staff mutation this device started and has not had
      // an answer to. It is the difference between *press Invite again after a
      // restart and be refused because the person already exists* and *press
      // Invite again and be told what the first attempt actually did*.
      final staffRequestTickets = await deviceStorage.open(
        DeviceStore.staffRequestTickets,
        () => HiveTenantStaffRequestTickets.open(
          keyProvider: SecureCheckoutOutboxEncryptionKeyProvider(
            storage: secureValueStore,
            storageKey: SecureCheckoutOutboxEncryptionKeyProvider
                .productImageDraftStorageKey,
          ),
        ),
      );
      // Photographs this device has already downloaded, so a catalog draws on a
      // cold start without fetching it all again and draws at all with no
      // signal. Its own boxes, unencrypted and bounded - see
      // `product_image_cache.dart` - and a failure to open one is a device that
      // fetches every time rather than a device that will not start.
      final tenantImageCache = await HiveTenantImageCache.open()
          .then<HiveTenantImageCache?>(
            (cache) => cache,
            onError: (Object error, StackTrace stackTrace) {
              AppTelemetry.captureHandled(
                error,
                stackTrace,
                boundary: 'inventory.image_cache_open',
              );
              return null;
            },
          );
      // Which businesses chose *Don't show again* on the till's no-printer
      // notice. A failure to open it is a till that keeps reminding, never one
      // that will not start.
      final printerSetupReminder = await HiveCheckoutPrinterSetupReminder.open()
          .then<CheckoutPrinterSetupReminder?>(
            (reminder) => reminder,
            onError: (Object error, StackTrace stackTrace) {
              AppTelemetry.captureHandled(
                error,
                stackTrace,
                boundary: 'checkout.printer_setup_reminder_open',
              );
              return null;
            },
          );
      // Receipt counters, shift state, and the outbox share one key: a sale,
      // the receipt numbering it draws from, and the shift it belongs to must
      // share exactly one fate.
      // **Shift state opens first, because the identity asks it a question.**
      // An identity minted before the platform could be asked is rebound to this
      // device on the next launch that holds no shift - and "holds no shift" is
      // this box's answer to give.
      final tenantShiftState = await deviceStorage.open(
        DeviceStore.shiftState,
        () => HiveTenantShiftState.open(
          keyProvider: SecureCheckoutOutboxEncryptionKeyProvider(
            storage: secureValueStore,
          ),
        ),
      );
      final checkoutReceiptCounters = await deviceStorage.open(
        DeviceStore.receiptCounters,
        () => HiveCheckoutReceiptCounters.open(
          // The platform's own answer to "which device is this", so an identity
          // minted after a reinstall still names the till it is running on.
          hardwareIdentity: const MethodChannelDeviceHardwareIdentity(),
          keyProvider: SecureCheckoutOutboxEncryptionKeyProvider(
            storage: secureValueStore,
          ),
        ),
      );
      // The printing slice's durable half, and the last piece it was missing.
      // Its own key, for the reason `printJobsStorageKey` gives.
      final checkoutPrintJobs = await deviceStorage.open(
        DeviceStore.printJobs,
        () => HivePrintJobQueue.open(
          keyProvider: SecureCheckoutOutboxEncryptionKeyProvider(
            storage: secureValueStore,
            storageKey:
                SecureCheckoutOutboxEncryptionKeyProvider.printJobsStorageKey,
          ),
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
      AppTelemetry.current.updateDevice({
        'installation_id': deviceId,
        'platform': defaultTargetPlatform.name,
      });
      final connectivity = Connectivity();
      // The one seam between a saved sale and the workers that carry it to the
      // server. Connectivity is piped into it here, once, rather than in
      // `build`, so the shell sees one stream for the life of the process.
      final checkoutSyncSignals = CheckoutSyncSignals();
      // Lives as long as the app, like the sync signals above it, because the
      // shell subscribes once and compares the stream by identity.
      final bootstrapRefreshSignals = TenantBootstrapRefreshSignals();
      connectivity.onConnectivityChanged.listen(
        (result) {
          AppTelemetry.current.updateDevice({'connectivity': result.name});
          if (result != ConnectivityResult.none) {
            checkoutSyncSignals.requestSyncAfterReconnect();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          AppTelemetry.captureHandled(
            error,
            stackTrace,
            boundary: 'device.connectivity_stream',
          );
        },
      );

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
        // **The cache shares the selection box on purpose.** Which business to
        // open and what is needed to open it are two halves of one fact, and a
        // second box would be another `await` on the startup path for nothing.
        directory: TenantDirectory(
          tenantGateway,
          cache: HiveTenantDirectoryCache(tenantSelectionBox),
        ),
        selectionStore: HiveTenantSelectionStore(tenantSelectionBox),
        rootCache: HiveRootRoutingProfileCache(tenantSelectionBox),
        observer: (event) {
          Sentry.addBreadcrumb(
            Breadcrumb(
              category: 'tenant.bootstrap',
              message: event.kind.name,
              level: SentryLevel.info,
              data: event.toData(),
            ),
          );
        },
      );

      // **Read before the first frame, and listened to afterwards.** An
      // emailed invitation opens the app by App Link, and until 2026-09-08 this
      // was a single read of `Uri.base` - which on Android is a directory, not
      // the URL that launched anything, so no mailed invitation could ever be
      // acted on. `InvitationLinkIntake` takes the launch link from the intent
      // and keeps a stream for links followed while the app is already up.
      final invitationIntake = InvitationLinkIntake(
        kIsWeb
            ? const UriBaseInvitationLinkSource()
            : PlatformInvitationLinkSource(),
      );
      await invitationIntake.start();

      final cartActivity = CheckoutCartActivity();
      runApp(
        SentryWidget(
          child: PlayUpdateGate(
            saleInProgress: () => cartActivity.saleInProgress,
            child: SpiritPOSApp(
              bootstrapService: bootstrapService,
              checkoutOutbox: checkoutOutbox,
              tenantMutationStore: tenantMutationStore,
              productImageDrafts: productImageDrafts,
              stockTakeDrafts: stockTakeDrafts,
              productImportAttempts: productImportAttempts,
              staffRequestTickets: staffRequestTickets,
              tenantImageCache: tenantImageCache,
              printerSetupReminder: printerSetupReminder,
              checkoutCatalogCache: checkoutCatalogCache,
              checkoutReceiptCounters: checkoutReceiptCounters,
              checkoutPrintJobs: checkoutPrintJobs,
              printerCapabilityProfile: printerCapabilityProfile,
              printerTransport: printerTransport,
              tenantShiftState: tenantShiftState,
              deviceId: deviceId,
              connectivity: connectivity,
              invitationIntake: invitationIntake,
              checkoutSyncSignals: checkoutSyncSignals,
              bootstrapRefreshSignals: bootstrapRefreshSignals,
              cartActivity: cartActivity,
            ),
          ),
        ),
      );
    },
  );
}

/// How many receipts this device is holding, or null when it cannot say.
///
/// **The badge on the top bar's glyph, since 2026-09-03.** It was the figure on
/// an *Unprinted receipts* launcher tile, beside a sentence-shaped reading in
/// the drawer; the tile and the sentence are both gone, and the receipts
/// themselves are a section of the notifications page. A queue that cannot be
/// listed is a queue with no figure rather than a queue with none in it.
TenantConfiguredPrinter _absentPrinter(Object error, StackTrace stackTrace) {
  AppTelemetry.captureHandled(
    error,
    stackTrace,
    boundary: 'printing.configuration_load',
  );
  return const TenantConfiguredPrinter.absent();
}

int? _printQueueCount(HivePrintJobQueue queue, {String? tenantId}) {
  try {
    return queue.pending(tenantId: tenantId).jobs.length;
  } catch (error, stackTrace) {
    AppTelemetry.captureHandled(
      error,
      stackTrace,
      boundary: 'print_queue.count',
    );
    return null;
  }
}

/// The shop's own name for the top of a receipt, or null.
///
/// **A branding read that fails must not cost a receipt.** The name is a
/// heading; `CheckoutReceiptBody` already falls back to its own wording when it
/// is absent, so anything that goes wrong reading it is swallowed here rather
/// than propagating into the print hook, where it would be reported as
/// `receipt_not_queued` and the paper would never come out.
Future<TenantBranding?> _receiptBranding(
  TenantSession session,
  TenantDataReader reader,
) async {
  try {
    return await TenantBrandingRepository(
      session: session,
      reader: reader,
    ).loadOrRegistered();
  } catch (error, stackTrace) {
    AppTelemetry.captureHandled(
      error,
      stackTrace,
      boundary: 'receipt.branding',
    );
    return null;
  }
}

/// How long a logo has to arrive before a receipt goes to paper without it.
///
/// **Much shorter than `fetchProductImage`'s own thirty seconds.** This runs
/// between a committed sale and its receipt, and a mark at the top is not worth
/// half a minute of a queue at the counter. The first sale after a logo is
/// published may pay it; every one after that reads the picture off this device.
const Duration _receiptLogoTimeout = Duration(seconds: 5);

/// The published logo as bytes, from this device where it has them.
///
/// Null for every failure - no logo, no network, a picture that will not
/// download - because a receipt without its mark is a receipt and a refused
/// receipt is not.
Future<Uint8List?> _receiptLogo(Uri? url, TenantImageCache? cache) async {
  if (url == null) return null;
  return loadTenantImageBytes(url, cache: cache, timeout: _receiptLogoTimeout);
}

/// The shift controller each session is already using, if it has one.
///
/// See `shiftControllerFactory` for why this is cached and why it is weak.
final Expando<TenantShiftController> _shiftControllers =
    Expando<TenantShiftController>();

/// The open-difference counter each session is already using, if it has one.
///
/// Cached and weak for exactly the reasons `_shiftControllers` is: the home is
/// rebuilt constantly, a fresh controller would re-read the count on every
/// rebuild, and a strong map here would hold every session this process ever
/// saw alive.
final Expando<TenantOpenDifferencesController> _openDifferenceControllers =
    Expando<TenantOpenDifferencesController>();

class SpiritPOSApp extends StatelessWidget {
  const SpiritPOSApp({
    super.key,
    required this.bootstrapService,
    required this.checkoutOutbox,
    required this.tenantMutationStore,
    required this.productImageDrafts,
    required this.stockTakeDrafts,
    required this.productImportAttempts,
    required this.staffRequestTickets,
    required this.tenantImageCache,
    required this.printerSetupReminder,
    required this.checkoutCatalogCache,
    required this.checkoutReceiptCounters,
    required this.checkoutPrintJobs,
    required this.printerCapabilityProfile,
    required this.printerTransport,
    required this.tenantShiftState,
    required this.deviceId,
    required this.connectivity,
    required this.checkoutSyncSignals,
    required this.bootstrapRefreshSignals,
    this.invitationIntake,
    this.cartActivity,
  });

  final TenantBootstrapService bootstrapService;
  final HiveCheckoutOutbox checkoutOutbox;
  final TenantPendingMutationStore tenantMutationStore;

  /// Photographs chosen on this device that Storage has not taken yet. Read by
  /// every surface that draws a product, through
  /// [TenantProductImageDraftScope].
  final HiveTenantProductImageDrafts productImageDrafts;
  final HiveTenantStockTakeDrafts stockTakeDrafts;

  /// The request IDs of an import that stopped part way, so it can be finished
  /// rather than run again under keys the server has never seen.
  final HiveTenantProductImportAttempts productImportAttempts;
  final HiveTenantStaffRequestTickets staffRequestTickets;

  /// Photographs already published, kept on this device. Null where the boxes
  /// would not open, which draws every picture from the network exactly as the
  /// app did before the store existed.
  final TenantImageCache? tenantImageCache;

  /// Null where its box would not open, which leaves the till's no-printer
  /// notice without *Don't show again*.
  final CheckoutPrinterSetupReminder? printerSetupReminder;
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

  /// How the account-creation wizard pushed over the routing shell tells it that
  /// the business it resolved against no longer exists in the state it saw.
  final TenantBootstrapRefreshSignals bootstrapRefreshSignals;

  /// The emailed invitation the app was opened on, and the ones that arrive
  /// later. Null in a host that no link can reach.
  final InvitationLinkIntake? invitationIntake;

  /// Whether the till holds an unsaved sale, for the Play update to wait on.
  final CheckoutCartActivity? cartActivity;

  /// Mints a newer ID token for the signed-in identity.
  ///
  /// **Not a re-authentication.** A forced refresh picks up claims that have
  /// moved on the server - the address, after `changeSignupEmail` - but it
  /// leaves `auth_time` exactly where it was, which is why it cures one of the
  /// two refusals `sendAccountVerification` can raise and not the other.
  static Future<void> _refreshSession() async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
  }

  /// Proves the signed-in identity again from its password, in place.
  ///
  /// **This is the remedy that used to be a sign-out.** Re-authenticating moves
  /// `auth_time`, which is the only thing the server's five-minute rule reads,
  /// and it keeps the session - so the wizard pushed above the routing shell
  /// survives it along with everything typed into it. The password arrives
  /// from the field and is not stored anywhere by this.
  static Future<void> _reauthenticate(String password) async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw StateError('There is no signed-in address to confirm.');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }

  /// Every change of signed-in identity, including to nobody.
  ///
  /// **Cached deliberately, and broadcast.** Two `OnboardingFlow`s can be
  /// mounted at once - the wizard pushed over the routing shell and the shell's
  /// own copy - so both must be able to listen, and the shell compares the
  /// stream by identity to decide whether to resubscribe. A fresh
  /// `authStateChanges()` per build would resubscribe forever.
  static final Stream<Object?> _identityChanges = FirebaseAuth.instance
      .authStateChanges()
      .asBroadcastStream();

  /// Trades a credential the server minted for a live session on this device.
  ///
  /// **The replacement for a session an address change is about to end.** A
  /// custom token authenticates by uid, so it is unaffected by the password
  /// credential being rebound underneath the old one.
  static Future<void> _resumeSession(String token) async {
    await FirebaseAuth.instance.signInWithCustomToken(token);
  }

  @override
  Widget build(BuildContext context) {
    Future<bool> isOnline() async =>
        await connectivity.checkConnectivity() != ConnectivityResult.none;
    final rawTenantDataReader = FirebaseTenantDocumentReader();
    final tenantDataReader = TenantPendingMutationOverlayReader(
      base: rawTenantDataReader,
      store: tenantMutationStore,
      currentUid: () => FirebaseAuth.instance.currentUser?.uid,
    );
    final mutationGateway = FirebaseTenantMutationGateway();
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
      final cacheReader = tenantDataReader.cacheOnly;
      final reads = await Future.wait<Object?>(<Future<Object?>>[
        TenantPrinterConfigurationRepository(
          session: session,
          reader: cacheReader,
        ).load().catchError(_absentPrinter),
        _receiptBranding(session, cacheReader),
      ]);
      final sale = CheckoutSalePayload.fromOutboxRecord(
        record,
        session: session,
      );
      final printer = reads[0]! as TenantConfiguredPrinter;
      final branding = reads[1] as TenantBranding?;
      final result = await printDispatcher.enqueue(
        sale,
        printer: printer,
        // The same value and the same fallback the home's title uses, so the
        // paper and the app name the business identically.
        businessName: branding?.companyName,
        servedBy: FirebaseAuth.instance.currentUser?.displayName,
        // Only where there is something to print on: a business with no printer
        // configured refuses below, and fetching a picture for it would be a
        // download nobody asked for.
        logo: printer.canPrint
            ? await _receiptLogo(branding?.logoUrl, tenantImageCache)
            : null,
        // The line the business details screen has always promised would print
        // under the name.
        slogan: branding?.slogan,
      );
      if (result.outcome == CheckoutPrintOutcome.refused) {
        return result.reasonCode;
      }
      // The durable job exists; transport now runs independently of checkout.
      unawaited(printDispatcher.retry(sale.receiptNumber));
      return null;
    }

    // **What a receipt's heading will now say, on paper.** Composed here with
    // `printReceipt` because it needs the same two pieces this is the only
    // place holding at once - the loaded ESC/POS profile and the platform
    // transport - and the same cache-only read of where this business prints.
    // A business with no printer refuses with `printer_not_configured`, which
    // the screen swallows: it is not a fault, it is a shop without a printer.
    Future<void> printBrandingProof({
      required TenantSession session,
      required String companyName,
      String? slogan,
      Uint8List? logo,
    }) async {
      final printer = await TenantPrinterConfigurationRepository(
        session: session,
        reader: tenantDataReader.cacheOnly,
      ).load().catchError(_absentPrinter);
      final configuration = printer.require();
      await printerTransport.send(
        configuration.endpoint,
        CheckoutBrandingProofPage(
          profile: printerCapabilityProfile,
          configuration: configuration,
        ).build(
          at: DateTime.now(),
          companyName: companyName,
          slogan: slogan,
          logo: logo,
        ),
      );
    }

    // **A second copy of a receipt, and the audit line that makes it
    // answerable for.** Composed here for the same reason `printReceipt` is:
    // this is the only place holding the durable queue, the transport, the
    // loaded profile, the branding and the configured printer at once. The
    // context reader is deliberately the same cache-only read the first copy
    // used, so a reprint carries the heading the original did.
    final receiptReprinter = CheckoutTenantReceiptReprinter(
      dispatcher: printDispatcher,
      callable: FirebaseRecordReceiptReprintCallable(),
      readContext: (session) async {
        final cacheReader = tenantDataReader.cacheOnly;
        final reads = await Future.wait<Object?>(<Future<Object?>>[
          TenantPrinterConfigurationRepository(
            session: session,
            reader: cacheReader,
          ).load().catchError(_absentPrinter),
          _receiptBranding(session, cacheReader),
        ]);
        final printer = reads[0]! as TenantConfiguredPrinter;
        final branding = reads[1] as TenantBranding?;
        return TenantReceiptPrintContext(
          printer: printer,
          businessName: branding?.companyName,
          servedBy: FirebaseAuth.instance.currentUser?.displayName,
          logo: printer.canPrint
              ? await _receiptLogo(branding?.logoUrl, tenantImageCache)
              : null,
          slogan: branding?.slogan,
        );
      },
    );

    // Recording a pending return changes no stock and is open to every active
    // member; restoring it is management-only and runs through the callable, so
    // the two stay a deliberate two-person control. The same actions reach the
    // returns route from shift history and from a receipt lookup.
    final returnActions = TenantReturnActions(
      writer: QueuedTenantReturnWriter(
        store: tenantMutationStore,
        onQueued: checkoutSyncSignals.requestSyncAfterSave,
      ),
      verifyCallable: FirebaseVerifyReturnCallable(),
    );
    // **The one write a sale ever takes after it is created.** The register no
    // longer preselects a payment method, so a cashier who was never told how
    // the customer paid saves a sale that names none; this is what lets them
    // answer it afterwards, from the sale's own card, once. Online only, like
    // the callable beside it: there is nothing honest to show for an answer
    // this device has not been able to hand over.
    final saleTenderCallable = FirebaseSetSaleTenderCallable();
    // **What a deactivated cashier can still hand over.** Sales that never left
    // this device are unreachable by every ordinary path once the membership
    // ends; this is the one door left, and it opens only for sales attributed
    // to that cashier and dated before their own deactivation.
    final strandedSalesDrainer = CheckoutStrandedSalesDrainer(
      outbox: checkoutOutbox,
      callable: FirebaseDrainStrandedSalesCallable(),
    );
    // What the business spends outside its stock. Recording is owner and
    // administrator only - the rules enforce it - and the same online check
    // every other client write uses: an expense is recorded on the server, so
    // there is nothing honest to show for one attempted with no connection.
    final expenseWriter = QueuedTenantExpenseWriter(
      store: tenantMutationStore,
      onQueued: checkoutSyncSignals.requestSyncAfterSave,
    );
    // Who stock is bought from. Queued like categories and for their reason:
    // a supplier's name is unique across the business, which only the server
    // can check, so a name a colleague took first is refused at drain and
    // reported rather than silently doubled.
    final supplierWriter = QueuedTenantSupplierWriter(
      store: tenantMutationStore,
      currentUid: () => FirebaseAuth.instance.currentUser?.uid,
      onQueued: checkoutSyncSignals.requestSyncAfterSave,
    );
    // **One writer for the till and the Customers screen**, so a customer added
    // at the counter and one added from the directory travel the same queue.
    final customerWriter = QueuedTenantCustomerWriter(
      store: tenantMutationStore,
      currentUid: () => FirebaseAuth.instance.currentUser?.uid,
      onQueued: checkoutSyncSignals.requestSyncAfterSave,
    );
    // **One way a repayment is taken**, from Customers - a record or its card
    // in the list - into the cashier's own shift, bound exactly as a sale is.
    // Not from the till, at the developer's direction on 2026-10-02.
    final customerPayments = CustomerPaymentServices(
      writer: QueuedTenantCustomerPaymentWriter(
        store: tenantMutationStore,
        currentUid: () => FirebaseAuth.instance.currentUser?.uid,
        onQueued: checkoutSyncSignals.requestSyncAfterSave,
      ),
      shifts: TenantShiftCheckoutBinder(tenantShiftState),
    );
    // **One queue for every *Send on WhatsApp***, from the till and from the
    // Sales report alike, so a receipt promised offline goes when either does.
    final whatsappReceiptWriter = QueuedTenantWhatsappReceiptWriter(
      store: tenantMutationStore,
      currentUid: () => FirebaseAuth.instance.currentUser?.uid,
      onQueued: checkoutSyncSignals.requestSyncAfterSave,
    );
    // **One counting screen, two doors onto it.** A cashier opens it from the
    // home menu; anybody who can read *Stock counts* opens it from the button on
    // that screen. Built once rather than at each call site, so the draft box,
    // the outbox writer and the sync signal cannot drift apart between them - a
    // count started by one door and a count started by the other have to be the
    // same count.
    TenantStockTakeScreen buildStockTakeScreen() => TenantStockTakeScreen(
      catalog: checkoutCatalogCache,
      drafts: stockTakeDrafts,
      obligations: stockTakeDrafts,
      writer: QueuedTenantStockTakeWriter(
        store: tenantMutationStore,
        currentUid: () => FirebaseAuth.instance.currentUser?.uid,
        // The count is durable here the moment it is handed in; this asks the
        // worker to start carrying it now rather than at the next reconnect.
        onQueued: checkoutSyncSignals.requestSyncAfterSave,
      ),
    );
    // **Where a callable-backed change waits.** Correcting a product and moving
    // stock are the two catalog changes that are not document writes and never
    // can be - `allow update` on `products` admits a strictly decreasing
    // quantity and nothing else - so both go through the Admin SDK. Queueing
    // them does not change that: the record holds the callable's own payload
    // and `FirebaseTenantMutationGateway` makes the call when it drains.
    //
    // Replaying one is safe because the payload names a `requestId` the server
    // keeps an idempotency record against, so a retry answers off that record
    // rather than moving the same stock twice.
    Future<void> queueCallableMutation({
      required TenantPendingMutationKind kind,
      required String prefix,
      required String tenantId,
      required String productId,
      required String requestId,
      required Map<String, Object?> payload,
    }) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      // **Thrown, not returned.** This read `return` until 2026-09-13, and a
      // silent return here is the worst answer available: the caller takes it
      // for a successful enqueue and reports "Stock changed from 10 to 8" for an
      // adjustment that was dropped on the floor. `QueuedTenantCatalogWriter`
      // has always thrown for this same condition, so one of the two was wrong
      // and it was this one. Reachable only if signing out races a live session,
      // which is exactly the case nobody would be watching for.
      if (uid == null) {
        throw StateError(
          'There is no signed-in account to record this against.',
        );
      }
      await tenantMutationStore.enqueue(
        uid: uid,
        tenantId: tenantId,
        // The request ID, not the product: one product may be corrected twice
        // before either lands, and the second must not collide with the first.
        operationId: '$prefix-$requestId',
        kind: kind,
        targetPath: TenantPaths(tenantId).product(productId),
        payload: payload,
      );
      checkoutSyncSignals.requestSyncAfterCatalogChange();
    }

    // The only path in the app that can set stock to an arbitrary figure.
    // It is management-only, which the callable itself enforces, and it is
    // reached one product at a time from the read-only catalog.
    final stockActions = TenantStockActions(
      adjustCallable: FirebaseAdjustStockCallable(),
      adjustQueue:
          ({
            required tenantId,
            required productId,
            required requestId,
            required payload,
          }) => queueCallableMutation(
            kind: TenantPendingMutationKind.stockAdjust,
            prefix: 'stock-adjust',
            tenantId: tenantId,
            productId: productId,
            requestId: requestId,
            payload: payload,
          ),
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
    // **One construction, two hosts.** The till's gate opens the shift and the
    // close panel it pushes counts the cash; both must bind to the same local
    // state, writer and sales ledger, or a shift opened by one would be
    // invisible to the other. Declared here rather than inlined twice for
    // exactly that reason.
    //
    // **One per session, not one per mount, since 2026-08-26.** The gate is
    // rebuilt every time a person opens the till, and a fresh controller starts
    // at `TenantShiftPhase.unknown` - so every *New sale* drew the gate's
    // loading state, read the canonical shift again, and only then drew a till.
    // That flash is what the product owner reported as jitter. Keyed off the
    // session controller, the second entry starts from the phase the first one
    // established and `restore` refreshes underneath it.
    //
    // **An `Expando`, so the cache cannot outlive the session.** A `Map` here
    // would hold every session controller this process ever built alive; an
    // expando's key is weak, so a session that is gone takes its shift
    // controller with it.
    TenantShiftController shiftControllerFactory(
      TenantSessionController sessions,
    ) => _shiftControllers[sessions] ??= TenantShiftController(
      sessionController: sessions,
      localState: tenantShiftState,
      reader: tenantDataReader,
      writer: FirebaseTenantShiftWriter(
        firestore: FirebaseFirestore.instance,
        isOnline: isOnline,
      ),
      // The outbox is the only local record of what this device sold, so it is
      // what proves this phone's share of a close and what gates it.
      salesLedger: CheckoutOutboxShiftSalesLedger(checkoutOutbox),
      // A shift may span the cashier's phones, so the close counts every
      // phone's sales on the server where it can.
      serverTotals: FirebaseShiftServerSalesTotals(
        firestore: FirebaseFirestore.instance,
      ),
      deviceId: deviceId,
      isOnline: isOnline,
    );

    // The count behind the badge on *Reports*. Cached per session for the same
    // reason the shift controller is: the home rebuilds constantly, and a fresh
    // one would re-read the summary document every time it did.
    TenantOpenDifferencesController openDifferencesFactory(
      TenantSessionController sessions,
    ) => _openDifferenceControllers[sessions] ??=
        TenantOpenDifferencesController(
          sessionController: sessions,
          reader: tenantDataReader,
        );

    // **One Sales report, reached two ways.** The home's *Sales* opens it on
    // today and everyone; a shift history card opens it on that shift's day
    // and member. Both carry the same totals, reprinting, tender and catalog,
    // or the report a card opened would be a thinner screen under the same
    // name - so it is built here, once.
    Widget salesReport(
      TenantDataReader reader, {
      String? businessDate,
      String? staffId,
    }) => TenantSalesReportScreen(
      reader: reader,
      reportReader: tenantDataReader,
      totalsCallable: salesTotalsCallable,
      checkoutOutbox: checkoutOutbox,
      returnActions: returnActions,
      reprinter: receiptReprinter,
      // Where a sale that names no payment method is given one, by the
      // cashier who rang it up. The same card the old app offered this
      // on, beside Return and Reprint.
      tenderCallable: saleTenderCallable,
      // The same offline catalog the till prices against, so an item row
      // can draw the product's photograph without a read of its own.
      catalog: checkoutCatalogCache,
      initialBusinessDate: businessDate,
      initialStaffId: staffId,
      receiptWriter: whatsappReceiptWriter,
      reportSaver: const SharedFileTenantReportSaver(),
      imageCache: tenantImageCache,
    );

    // **Every settings page, built in one place.** The business home opens it
    // from its three Business tiles, and the till opens its printer page when a
    // receipt could not print because no printer is set up yet.
    Widget settingsPage(TenantDataReader reader, String? initialSettingKey) {
      final destinations = <TenantSettingsDestination>[
        // **The setting that stops every sale on every device, on a row
        // that says so.** A commit asks for a full sync pass, because
        // the catalog refresh is the only thing that re-reads the
        // document: without it this device would keep pricing new sales
        // with the code that was just replaced.
        TenantSettingsDestination(
          settingKey: 'currency',
          kind: TenantSettingKind.currency,
          icon: Icons.payments_outlined,
          allowedRoles: TenantCheckoutConfigurationPublisher.allowedRoles,
          builder: (_) => TenantCheckoutConfigurationPanel(
            reader: reader,
            writer: FirebaseTenantCheckoutConfigurationWriter(
              firestore: FirebaseFirestore.instance,
              isOnline: isOnline,
            ),
            onPublished:
                checkoutSyncSignals.requestSyncAfterConfigurationChange,
          ),
        ),
        TenantSettingsDestination(
          settingKey: 'printer',
          kind: TenantSettingKind.printer,
          icon: Icons.print_outlined,
          allowedRoles: TenantPrinterConfigurationPublisher.allowedRoles,
          builder: (context) => TenantPrinterConfigurationPanel(
            reader: reader,
            writer: QueuedTenantConfigurationWriter(
              store: tenantMutationStore,
              cacheReader: reader.cached ?? reader,
              currentUid: () => FirebaseAuth.instance.currentUser?.uid,
              remote: FirebaseTenantConfigurationDocumentWriter(
                firestore: FirebaseFirestore.instance,
                isOnline: isOnline,
              ),
            ),
            // Puts a page on the roll against what is typed,
            // before it is saved, headed with the receipt
            // branding this device holds - logo included - so the
            // page shows what a receipt will look like. The
            // branding read is the receipt's own cache-only one,
            // and a failed read prints the page unbranded.
            testPrint: (configuration) async {
              final session = TenantSessionScope.read(context).session;
              final branding = session == null
                  ? null
                  : await _receiptBranding(session, tenantDataReader.cacheOnly);
              await printerTransport.send(
                configuration.endpoint,
                CheckoutPrinterTestPage(
                  profile: printerCapabilityProfile,
                  configuration: configuration,
                ).build(
                  at: DateTime.now(),
                  businessName: branding?.companyName,
                  slogan: branding?.slogan,
                  logo: await _receiptLogo(branding?.logoUrl, tenantImageCache),
                ),
              );
            },
          ),
        ),
        TenantSettingsDestination(
          settingKey: 'stock-take',
          kind: TenantSettingKind.stockCounts,
          icon: Icons.fact_check_outlined,
          allowedRoles: TenantStockTakeSchedulePublisher.allowedRoles,
          // **Not queued, and that is deliberate.** The queued writer
          // carries `branding` and `printer` and passes everything else
          // straight at the server, which is what this wants: deciding
          // a counting rota is an owner sitting down with the business,
          // not an operational act taken on a shop floor with no
          // signal. The till reads the published document from cache
          // and treats an unreadable one as "no count is due", so a
          // schedule that never reaches a device interrupts nobody.
          builder: (_) => TenantStockTakeSettingsPanel(
            reader: reader,
            writer: QueuedTenantConfigurationWriter(
              store: tenantMutationStore,
              cacheReader: reader.cached ?? reader,
              currentUid: () => FirebaseAuth.instance.currentUser?.uid,
              remote: FirebaseTenantConfigurationDocumentWriter(
                firestore: FirebaseFirestore.instance,
                isOnline: isOnline,
              ),
            ),
          ),
        ),
        // **Who may sell for a price agreed with the customer**, set per
        // person the way the counting rota is, and written the same way for
        // the same reason: it is an owner deciding something with the
        // business, and a till that never receives it sells at the listed
        // price, which is where every business starts.
        TenantSettingsDestination(
          settingKey: 'agreed-prices',
          kind: TenantSettingKind.agreedPrices,
          icon: Icons.handshake_outlined,
          allowedRoles: TenantPriceAgreementPublisher.allowedRoles,
          builder: (_) => TenantPriceAgreementSettingsPanel(
            reader: reader,
            writer: QueuedTenantConfigurationWriter(
              store: tenantMutationStore,
              cacheReader: reader.cached ?? reader,
              currentUid: () => FirebaseAuth.instance.currentUser?.uid,
              remote: FirebaseTenantConfigurationDocumentWriter(
                firestore: FirebaseFirestore.instance,
                isOnline: isOnline,
              ),
            ),
          ),
        ),
      ];
      final currency = destinations[0];
      final printer = destinations[1];
      final stockCounts = destinations[2];
      final agreedPrices = destinations[3];
      return switch (initialSettingKey) {
        'business-details' => TenantConfigurationPage(
          title: 'Business details',
          builder: (context) => TenantBrandingPanel(
            reader: reader,
            writer: QueuedTenantConfigurationWriter(
              store: tenantMutationStore,
              cacheReader: reader.cached ?? reader,
              currentUid: () => FirebaseAuth.instance.currentUser?.uid,
              remote: FirebaseTenantConfigurationDocumentWriter(
                isOnline: isOnline,
              ),
            ),
            logoStore: FirebaseTenantBrandingLogoStore(),
            backgroundRemover: CallableTenantProductBackgroundRemover(
              callable: FirebaseRemoveProductBackgroundCallable(),
            ),
            printProof: printBrandingProof,
            // The hosted page that takes the request. Deletion is done by hand
            // for now, so the page is the whole of the process.
            onRequestAccountDeletion: () => unawaited(
              launchUrl(
                Uri.parse('https://auth.uzapay.co.ke/account-deletion'),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
        ),
        'printer' => TenantConfigurationPage(
          title: 'Printer',
          builder: printer.builder,
        ),
        _ => TenantConfigurationsScreen(
          currencyBuilder: currency.builder,
          stockCountsBuilder: stockCounts.builder,
          agreedPricesBuilder: agreedPrices.builder,
          // **Straight at the server, as the agreed prices are**: an owner
          // deciding how customers earn is not an act taken on a shop floor
          // with no signal, and a till never reads this to sell.
          loyaltyBuilder: (_) => TenantLoyaltySettingsPanel(
            reader: reader,
            writer: QueuedTenantConfigurationWriter(
              store: tenantMutationStore,
              cacheReader: reader.cached ?? reader,
              currentUid: () => FirebaseAuth.instance.currentUser?.uid,
              remote: FirebaseTenantConfigurationDocumentWriter(
                firestore: FirebaseFirestore.instance,
                isOnline: isOnline,
              ),
            ),
          ),
        ),
      };
    }

    // **Above `MaterialApp`, so every route is inside it.** A staged photograph
    // has to be drawable wherever a product is - the catalog, the till's
    // picture band, a cart line - and each of those is a separate root
    // navigator push. One scope at the top is the only placement that reaches
    // all of them without every surface holding a subscription of its own.
    return TenantProductImageDraftScope(
      notifier: productImageDrafts,
      // The published half of the same question, in the same place and for the
      // same reason: every surface that draws a product is its own root
      // navigator push, and one scope at the top reaches all of them.
      child: TenantImageCacheScope(
        cache: tenantImageCache,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: spiritTheme,
          // **What tells the home it is back on top.** Every module is pushed
          // over the landing route, so returning from one is a pop rather than
          // a rebuild - and without this the figures stay as they were read on
          // the way in. See `_RereadOnReturn`.
          navigatorObservers: <NavigatorObserver>[tenantRouteObserver],
          // `design.md` §2.4: bouncing scroll physics everywhere, on both
          // platforms, and no Material overscroll glow. It belongs on the app
          // rather than on each scrollable, because "everywhere" is not a rule
          // three hundred list views can be trusted to remember.
          scrollBehavior: const SpiritScrollBehavior(),
          home: TenantRoutingShell(
            // **The one chance to settle what this device is still holding.**
            // A deactivation reaches the app through no channel of its own, so
            // it finds out by asking - and that ask is online, which is the
            // whole of the window. Sales the outbox never sent would otherwise
            // sit on the phone for good: the workers stop at a session that
            // cannot access the business, and `allow create` refuses the write
            // regardless. See `CheckoutStrandedSalesDrainer`.
            onTenantAccessLost: (uid, tenantId) async {
              final result = await strandedSalesDrainer.drain(
                uid: uid,
                tenantId: tenantId,
              );
              if (result.attempted) {
                debugPrint(
                  'Stranded sales: ${result.handedOver} handed over, '
                  '${result.alreadyPresent} already held, '
                  '${result.unreadable} unreadable.',
                );
              }
            },
            // The home's greeting states how today compares with yesterday, and
            // this is what it adds the two days up with. The same callable the
            // sales totals route already uses.
            salesTotalsCallable: salesTotalsCallable,
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
            // not itself perform, which is what the verify step's watch is: this
            // call on a timer, and again on every app resume.
            reloadIdentity: () async =>
                FirebaseAuth.instance.currentUser?.reload(),
            // The address the verify step names, read from Auth rather than from
            // the root document - the document holds a mirror of it, and after a
            // change in place the mirror is the half that can lag.
            readEmail: () => FirebaseAuth.instance.currentUser?.email,
            // Turns a silent non-delivery into a stated one. Without it a user
            // whose address is suppressed sees the request accepted and taps send
            // again indefinitely.
            emailDeliveryStatusCallable: FirebaseEmailDeliveryStatusCallable(),
            invitationLink: invitationIntake?.launchArrival?.link,
            invalidInvitationLink:
                invitationIntake?.launchArrival?.invalid ?? false,
            invitationArrivals: invitationIntake?.arrivals,
            onInvitationLinkSettled: invitationIntake?.settled,
            bootstrapService: bootstrapService,
            tenantSwitchStateSources: safeLandingTenantSwitchStateSources(
              checkoutStateSource: CheckoutOutboxTenantSwitchStateSource(
                checkoutOutbox,
              ),
              pendingWritesStateSource: TenantPendingMutationSwitchStateSource(
                tenantMutationStore,
              ),
              cashCloseStateSource: TenantShiftSwitchStateSource(
                tenantShiftState,
              ),
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
              final mutationWorker = TenantPendingMutationWorker(
                store: tenantMutationStore,
                submission: mutationGateway,
                confirmation: mutationGateway,
                workerId: deviceId,
                onRetryDue: checkoutSyncSignals.requestSyncForRetry,
              );
              // Photographs, carried on the same passes as everything else. The
              // bytes never enter the mutation outbox - only the URL does, and
              // only once Storage has taken them.
              final imageWorker = TenantProductImageUploadWorker(
                drafts: productImageDrafts,
                store: FirebaseTenantProductImageStore(),
                mutations: tenantMutationStore,
                requestId: secureStockAdjustmentRequestId,
                queue:
                    ({
                      required tenantId,
                      required productId,
                      required requestId,
                      required payload,
                    }) => queueCallableMutation(
                      kind: TenantPendingMutationKind.productCorrect,
                      prefix: 'product-image',
                      tenantId: tenantId,
                      productId: productId,
                      requestId: requestId,
                      payload: payload,
                    ),
              );
              // The order these run in is a tested contract, not a comment here.
              final pass = CheckoutSyncPass(
                recover: coordinator.recoverSelectedSession,
                submit: submissionWorker.submitDueCheckouts,
                refreshCatalog: catalogRefresher.refreshSelectedSession,
                reportEvidenceChanged:
                    checkoutSyncSignals.reportEvidenceChanged,
              );
              return (trigger) async {
                // A sale saved at the till needs submitting and confirming; it does
                // not need the whole product catalog re-read. Nor does a retry
                // that fell due, which is only a send.
                final session = sessionController.requireSession();
                await Future.wait<void>(<Future<void>>[
                  pass.run(
                    refreshDerivedData:
                        trigger is! CheckoutSaveSyncRequest &&
                        trigger is! CheckoutRetrySyncRequest,
                  ),
                  // Sequential on purpose: a photograph waits for its product to
                  // exist on the server, and the mutation worker is what puts it
                  // there - so a create confirmed in this pass lets its picture
                  // go in the same one rather than a pass later.
                  mutationWorker
                      .run(session)
                      .then((_) => imageWorker.run(session)),
                ]);
                return null;
              };
            },
            tenantRecoveryTriggers: checkoutSyncSignals.syncRequests,
            bootstrapRefreshRequests: bootstrapRefreshSignals.requests,
            refreshSession: _refreshSession,
            reauthenticate: _reauthenticate,
            identityChanges: _identityChanges,
            resumeSession: _resumeSession,
            // What retires the offline card: a bootstrap read from cache is
            // refreshed in place once the radio is back, and `fromCache` goes with
            // it. See `TenantRoutingShell.reconnectSignals`.
            reconnectSignals: checkoutSyncSignals.reconnects,
            hasPlatformSuperAdminClaim: (uid) async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null || user.uid != uid) return false;
              final token = await user.getIdTokenResult();
              return token.claims?['platformRole'] == 'superAdmin';
            },
            tenantDataReader: tenantDataReader,
            staffRequestTickets: staffRequestTickets,
            // **The hub is retired, 2026-09-14, at the developer's direction.**
            // It was restored on 2026-08-29 because a slot that can name only one
            // report had left the other five with no entrance, and a menu was the
            // cheapest way to name six things. What it cost is a step in front of
            // every one of them: the old mono-tenant app put the week on the slot
            // itself and made its figures the doors, so *Total sales* opened the
            // sales report rather than a list whose first row opened it.
            //
            // The week is that page again, and the five reports are cards on its
            // own grid. Each still re-asks the role question with its own domain's
            // list - see `WeeklyReportDestination` - so a role that opens *Reports*
            // still sees only the reports it may read.
            dailySummaryRoute: (reader) => TenantWeeklyReportScreen(
              reader: reader,
              callable: salesTotalsCallable,
              checkoutOutbox: checkoutOutbox,
              // The sale-line roll-up behind *Top selling items* and *Recent
              // transactions* needs the history reader, which the plain
              // constructor cannot reach.
              salesRepositoryFactory: (session) => TenantSaleHistoryRepository(
                session: session,
                reader: reader,
                reportReader: tenantDataReader,
              ),
              destinations: WeeklyReportDestinations(
                // What *Total sales* and *Transactions* elaborate into: the one
                // surface that can total today and split it by how each sale was
                // paid for.
                salesTotals: WeeklyReportDestination(
                  build: () => TenantSalesTotalsScreen(
                    callable: salesTotalsCallable,
                    reader: reader,
                    checkoutOutbox: checkoutOutbox,
                  ),
                  roles: TenantSalesTotalsGateway.allowedRoles,
                ),
                // The reconciled totals, and - one day at a time - why each day is
                // in the state it is. The explanation stays reached from the
                // summary itself, which is where a manager already asks.
                dailySummary: WeeklyReportDestination(
                  build: () => TenantDailySummaryScreen(
                    reader: reader,
                    checkoutOutbox: checkoutOutbox,
                    reconciliationRoute: (businessDate) =>
                        TenantReconciliationStatusScreen(
                          reader: reader,
                          businessDate: businessDate,
                          actions: reconciliationActions,
                        ),
                    reconciliationRoles:
                        TenantReconciliationStatusRepository.allowedRoles,
                    salesTotalsRoute: () => TenantSalesTotalsScreen(
                      callable: salesTotalsCallable,
                      reader: reader,
                      checkoutOutbox: checkoutOutbox,
                    ),
                    salesTotalsRoles: TenantSalesTotalsGateway.allowedRoles,
                  ),
                  roles: TenantDailyMetricsRepository.allowedRoles,
                ),
                // A calendar month, which nothing else in this product can name:
                // every standing period ends today, so once August began nothing
                // could be asked how July went. It stays its own screen because it
                // cannot reuse this page's loader - two range requests rather than
                // one per day, which a month cannot afford.
                monthlyReport: WeeklyReportDestination(
                  build: () => TenantMonthlyReportScreen(
                    reader: reader,
                    callable: salesTotalsCallable,
                    checkoutOutbox: checkoutOutbox,
                  ),
                  roles: TenantSalesTotalsGateway.allowedRoles,
                ),
                // **The one tap the badge on *Reports* needs.** These records were
                // reachable only through the daily summary, then a run, then its
                // differences - a route nobody walks unless they already know
                // something is waiting at the end of it, which is precisely why a
                // recorded difference could sit unread.
                differences: WeeklyReportDestination(
                  build: () => TenantReconciliationAnomalyScreen(
                    reader: reader,
                    actions: reconciliationActions,
                  ),
                  roles: TenantReconciliationAnomalyRepository.allowedRoles,
                ),
                // **Given a door at last.** Built, tested and unreachable: the
                // route was declared on the landing screen and on the catalog
                // panel and consumed by neither, so the only surface that can say
                // what moved across the whole business has never been openable.
                stockMovements: WeeklyReportDestination(
                  build: () => TenantStockMovementFeedScreen(
                    reader: reader,
                    groupReader: tenantDataReader,
                    productLedgerRoute: (productId) =>
                        TenantProductLedgerScreen(
                          reader: reader,
                          productId: productId,
                        ),
                  ),
                  roles: TenantStockMovementFeedRepository.allowedRoles,
                ),
                openDifferenceCount: (sessions) =>
                    openDifferencesFactory(sessions).openCount,
              ),
            ),
            dailySummaryRoles: TenantSalesTotalsGateway.allowedRoles,
            expensesRoute: (reader) => TenantExpensesScreen(
              reader: reader,
              writer: expenseWriter,
              // The share sheet, which is how a generated file reaches
              // somewhere a person can find it without a storage permission.
              reportSaver: const SharedFileTenantReportSaver(),
              imageCache: tenantImageCache,
            ),
            expensesRoles: TenantExpenseRepository.allowedRoles,
            suppliersRoute: (reader) => TenantSuppliersScreen(
              reader: reader,
              writer: supplierWriter,
              // `requestSyncAfterCatalogChange`, because a delivery moves stock
              // and sets costs: the refresh is what carries both into the
              // till's offline catalog, so the next sale is costed right.
              deliveries: TenantSupplierDeliveryServices(
                writer: QueuedTenantSupplierDeliveryWriter(
                  store: tenantMutationStore,
                  currentUid: () => FirebaseAuth.instance.currentUser?.uid,
                  onQueued: checkoutSyncSignals.requestSyncAfterCatalogChange,
                ),
                productSearchReader: tenantDataReader,
              ),
              reportSaver: const SharedFileTenantReportSaver(),
              imageCache: tenantImageCache,
            ),
            suppliersRoles: TenantSupplierRepository.allowedRoles,
            productionRoute: (reader) => TenantProductionScreen(
              reader: reader,
              // A batch moves stock and sets a cost, so the till's offline
              // catalog is stale the moment it is queued.
              services: TenantProductionServices(
                writer: QueuedTenantProductionWriter(
                  store: tenantMutationStore,
                  currentUid: () => FirebaseAuth.instance.currentUser?.uid,
                  onQueued: checkoutSyncSignals.requestSyncAfterCatalogChange,
                ),
                productSearchReader: tenantDataReader,
              ),
              reportSaver: const SharedFileTenantReportSaver(),
              imageCache: tenantImageCache,
            ),
            productionRoles: TenantProductionRepository.allowedRoles,
            receiptLookupRoute: (reader) => salesReport(reader),
            receiptLookupRoles: TenantSaleHistoryRepository.reportRoles,
            customersRoute: (reader) => TenantCustomersScreen(
              reader: reader,
              writer: customerWriter,
              salesReader: tenantDataReader,
              payments: customerPayments,
            ),
            customersRoles: TenantCustomerRepository.manageRoles,
            // **Straight at the server, as every owner's setting is**, and the
            // status check is the server's own answer about whether this
            // deployment has a number to send from.
            whatsappReceiptsRoute: (reader) => TenantWhatsappReceiptsScreen(
              reader: reader,
              writer: QueuedTenantConfigurationWriter(
                store: tenantMutationStore,
                cacheReader: reader.cached ?? reader,
                currentUid: () => FirebaseAuth.instance.currentUser?.uid,
                remote: FirebaseTenantConfigurationDocumentWriter(
                  firestore: FirebaseFirestore.instance,
                  isOnline: isOnline,
                ),
              ),
              statusCheck: firebaseWhatsappReceiptStatus,
            ),
            whatsappReceiptsRoles: TenantEReceiptPublisher.allowedRoles,
            returnFeedRoute: (reader) => TenantReturnFeedScreen(
              reader: reader,
              actions: returnActions,
              reportSaver: const SharedFileTenantReportSaver(),
              imageCache: tenantImageCache,
            ),
            returnFeedRoles: TenantReturnHistoryRepository.allowedRoles,
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
            stockMovementFeedRoles:
                TenantStockMovementFeedRepository.allowedRoles,
            // The whole business's event trail: who was invited, deactivated, or
            // recovered, and every lifecycle change the platform made. It is
            // deliberately narrower than the stock surfaces above.
            auditLogRoute: (reader) => TenantAuditLogScreen(
              reader: reader,
              reportSaver: const SharedFileTenantReportSaver(),
              imageCache: tenantImageCache,
            ),
            // **On the home since 2026-09-16.** It used to be reached from a
            // button inside the cash-count sheet, which meant starting a count
            // to read last week's - and that button popped the sheet and then
            // pushed against the context it had just destroyed, so it never
            // arrived at all. It is a report, and it sits with the reports.
            shiftHistoryRoute: (reader) => TenantShiftHistoryScreen(
              reader: reader,
              returnActions: returnActions,
              reportSaver: const SharedFileTenantReportSaver(),
              imageCache: tenantImageCache,
              // A card opens the report above on its shift's day, narrowed to
              // whoever ran it.
              salesReportRoute: ({required businessDate, required staffId}) =>
                  salesReport(
                    reader,
                    businessDate: businessDate,
                    staffId: staffId,
                  ),
            ),
            auditLogRoles: TenantAuditLogRepository.allowedRoles,
            // **A cashier's open shift, on the home, since 2026-09-30.** Opened
            // at the till as before; closed there or from here, through the
            // same sheet and the same controller the till's gate holds.
            shiftPanel: (currency, memberName) => TenantHomeShiftCard(
              controllerFactory: shiftControllerFactory,
              currency: currency,
              memberName: memberName,
              returnActions: returnActions,
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
            // **The shift is opened and closed at the till, not on the home.**
            // Restored 2026-08-25 to where the pre-multitenancy app had it: the
            // old `pos.dart` gated itself on entry and offered *stepping away* or
            // *end my shift* on the way out. The gate wraps the till rather than
            // living inside it, so the checkout screen still knows only how to
            // sell.
            checkoutRoute: (sessions) => TenantShiftGate(
              controllerFactory: shiftControllerFactory,
              // What *Close shift* needs, handed over directly. It used to be a
              // whole pushed page built here; since 2026-09-03 the choice opens
              // the counting sheet itself.
              currency: TenantReportingCurrency.unknown,
              returnActions: returnActions,
              // **Inside the shift gate, so the count is asked about after the
              // shift is settled.** `TenantShiftGate` renders its child only
              // once a shift is open, which is exactly the ordering wanted and
              // costs the shift code no change at all.
              child: TenantStockTakeGate(
                loadSchedule: (session) => TenantStockTakeScheduleRepository(
                  session: session,
                  // Cache-first, because this is read on the way into the till
                  // and the till must open with no signal. A business whose
                  // schedule this device has never read gets no schedule, which
                  // means no count is due - the failure is open, by design.
                  reader: tenantDataReader.cacheOnly,
                ).load(),
                // **And then the server, which nothing else on a cashier's
                // path reads.** Without it the schedule reached a phone only
                // where an owner had opened *Stock counts* on it, and stayed
                // as it was that day - found on two emulators on 2026-09-29.
                // The gate applies this answer after the cached one and never
                // waits on it.
                refreshSchedule: (session) => TenantStockTakeScheduleRepository(
                  session: session,
                  reader: tenantDataReader,
                ).load(),
                obligations: stockTakeDrafts,
                countRoute: (routeContext, scope) => TenantStockTakeScreen(
                  catalog: checkoutCatalogCache,
                  drafts: stockTakeDrafts,
                  obligations: stockTakeDrafts,
                  scope: scope,
                  writer: QueuedTenantStockTakeWriter(
                    store: tenantMutationStore,
                    currentUid: () => FirebaseAuth.instance.currentUser?.uid,
                    onQueued: checkoutSyncSignals.requestSyncAfterSave,
                  ),
                ),
                child: TenantCheckoutScreen(
                  cache: checkoutCatalogCache,
                  cartActivity: cartActivity,
                  // The overlay reader, so a customer added at this till is
                  // found by its own picker before the server has them.
                  customers: CheckoutCustomerServices(
                    reader: tenantDataReader,
                    writer: customerWriter,
                    receiptWriter: whatsappReceiptWriter,
                  ),
                  // **Cache first, then the server, and neither holds the
                  // till.** The cached answer is what lets *Agree a price*
                  // appear with no signal; the server read is what brings the
                  // policy to this phone at all, since nothing else on a
                  // cashier's path reads it. Either failing leaves the button
                  // off and the till selling at the listed price.
                  loadPriceAgreement: (session, {required cached}) =>
                      TenantPriceAgreementRepository(
                        session: session,
                        reader: cached
                            ? tenantDataReader.cacheOnly
                            : tenantDataReader,
                      ).load(),
                  // The decorator is what makes a saved sale reach the server while the
                  // till stays open. It is wrapped here rather than inside the screen so
                  // the screen still knows only how to save.
                  drafts: CheckoutSyncOnSaveDraftSink(
                    signals: checkoutSyncSignals,
                    delegate: CheckoutDraftService(
                      sessionController: sessions,
                      cache: checkoutCatalogCache,
                      localSales: checkoutCatalogCache.localSales,
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
                  printerSetupReminder: printerSetupReminder,
                  // The same page the business home's Printer tile opens. The
                  // till offers it only to the roles that can change the
                  // printer.
                  onSetUpPrinter: (context) {
                    final controller = TenantSessionScope.of(context);
                    Navigator.of(context).push(
                      AppPageRoute<void>(
                        builder: (_) => TenantSessionScope(
                          controller: controller,
                          child: settingsPage(tenantDataReader, 'printer'),
                        ),
                      ),
                    );
                  },
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
            settingsRoute: settingsPage,
            settingsRoles: TenantCheckoutConfigurationPublisher.allowedRoles,
            printQueueCount: () => _printQueueCount(checkoutPrintJobs),
            // Nightly reconciliation has been recording differences that nobody
            // sees unless they go looking for them. This is the count of the ones
            // still open, badged on the route that opens them.
            unresolvedDifferencesCount: (sessions) =>
                openDifferencesFactory(sessions).openCount,
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
            // **The only inventory route every active member reaches.** A count
            // writes to `stock_takes`, which no client may write either - it goes
            // through `submitStockTake` like the rest - and it moves no stock at
            // all, which is what makes opening it safe.
            stockTakeRoute: (reader) => buildStockTakeScreen(),
            stockTakeRoles: TenantStockTakeGateway.allowedRoles,
            stockTakeReviewRoute: (reader) => TenantStockTakeReviewScreen(
              reader: reader,
              reportSaver: const SharedFileTenantReportSaver(),
              imageCache: tenantImageCache,
              // The same counting screen the home tile opens for a cashier.
              // Anybody who can read the record of counts starts one from here
              // instead, which is why the tile is not offered to them.
              countRoute: (_) => buildStockTakeScreen(),
              applyCallable: FirebaseApplyStockTakeCallable(),
              // Accepting a count writes to `products`, `stock_adjustments` and
              // `stock_movements`, so the till's offline catalog is stale the
              // moment it lands.
              onApplied: checkoutSyncSignals.requestSyncAfterCatalogChange,
            ),
            stockTakeReviewRoles: TenantStockTakeReviewRepository.allowedRoles,
            catalogManagementRoute: (reader) => TenantCatalogManagementScreen(
              reader: reader,
              productSearchReader: tenantDataReader,
              reportSaver: const SharedFileTenantReportSaver(),
              imageCache: tenantImageCache,
              imageStore: FirebaseTenantProductImageStore(),
              // **Where a photograph waits, and the reason adding one offline
              // works at all.** Without this the form falls to the inline
              // `TenantProductImageStore.upload` - a Storage `putData` with no
              // timeout, which offline retries for Storage's own ten minutes
              // and holds the whole catalog panel disabled for every second of
              // it. Staged here instead: the bytes go to an encrypted box on
              // this device, the product is written immediately, and
              // `TenantProductImageUploadWorker` above carries the picture up
              // once the product itself is on the server.
              imageDrafts: productImageDrafts,
              // *Remove background*, restored from the old catalog form. The key
              // lives in the deployment's secret manager and the call is made by
              // `removeProductBackground`; a deployment that never set the secret
              // gets a callable that refuses with `failed-precondition`, which the
              // form words as "not set up for this business" rather than as a
              // fault. See `product_background_removal.dart`.
              backgroundRemover: CallableTenantProductBackgroundRemover(
                callable: FirebaseRemoveProductBackgroundCallable(),
              ),
              // **Durable-first since 2026-09-04, at the developer's direction.**
              // What that bought is that the form no longer waits for an
              // acknowledgement: adding a product used to hold the whole panel
              // across a Storage upload, a download URL, a Firestore round trip
              // and two catalog reads.
              //
              // **Two of these four stopped being document writes on 2026-09-13,
              // and this comment claimed otherwise for a commit.** Creating and
              // retiring a product are callables now and `allow create` and
              // `allow delete` on `products` are both `if false`, because either
              // may move a quantity and no device may write the
              // `stock_adjustments` record that accounts for it. Only the two
              // category writes are still the `set` and `update` the rules
              // admit.
              //
              // `requestSyncAfterCatalogChange` rather than `requestSyncAfterSave`,
              // because a catalog change is precisely the case that does need the
              // full pass: the refresh is the only thing that re-reads `products`
              // and `categories` into the till's offline cache.
              writer: QueuedTenantCatalogWriter(
                store: tenantMutationStore,
                currentUid: () => FirebaseAuth.instance.currentUser?.uid,
                onQueued: checkoutSyncSignals.requestSyncAfterCatalogChange,
              ),
              updateCallable: FirebaseUpdateProductCallable(),
              updateQueue:
                  ({
                    required tenantId,
                    required productId,
                    required requestId,
                    required payload,
                  }) => queueCallableMutation(
                    kind: TenantPendingMutationKind.productCorrect,
                    prefix: 'product-correct',
                    tenantId: tenantId,
                    productId: productId,
                    requestId: requestId,
                    payload: payload,
                  ),
              // Both bulk halves are callables and neither could be anything else.
              // A correction cannot be a client `WriteBatch` at all, for the reason
              // above. An import could once have created products past the rules,
              // when `allow create` still admitted three roles - but no device can
              // write the
              // `stock_adjustments` record and `stock_movements` entry that give an
              // opening quantity a recorded origin, because both collections are
              // server-write-only. A device import would therefore leave stock with
              // no ledger entry, which is the defect the previous app shipped.
              bulkRoute: (context) => TenantBulkCatalogScreen(
                reader: reader,
                batchCallable: FirebaseUpdateProductsCallable(),
                importCallable: FirebaseImportProductsCallable(),
                // The two platform halves of the journey the pre-multitenancy
                // app had: take a template away, bring a filled sheet back.
                // Injected rather than reached for inside the panel, because
                // opening a file picker and raising a share sheet are the two
                // things its widget tests cannot do.
                sheetPicker: const FilePickerTenantProductSheetPicker(),
                sheetSaver: const SharedFileTenantProductSheetSaver(),
                // Where an import that stopped part way is kept, so it can be
                // finished under the request IDs it was started under rather
                // than run again under new ones.
                attempts: productImportAttempts,
                onChanged: checkoutSyncSignals.requestSyncAfterCatalogChange,
              ),
              onChanged: checkoutSyncSignals.requestSyncAfterCatalogChange,
              productStockRoute: (product) => TenantProductStockScreen(
                reader: reader,
                product: product,
                actions: stockActions,
              ),
              // The correcting half. The composition root still owns the callable;
              // what it hands over is the errand rather than a screen for the
              // catalog to push, because the correction also owns its own dismissal
              // and the sentence it leaves behind on the catalog.
              adjustStockRoute: (context, product) =>
                  openTenantProductStockAdjustmentScreen(
                    context,
                    reader: reader,
                    product: product,
                    actions: stockActions,
                  ),
              productStockRoles: TenantProductStockRepository.allowedRoles,
              adjustmentFeedRoute: () =>
                  TenantStockAdjustmentFeedScreen(reader: reader),
              adjustmentFeedRoles:
                  TenantStockAdjustmentFeedRepository.allowedRoles,
              movementFeedRoute: () => TenantStockMovementFeedScreen(
                reader: reader,
                groupReader: tenantDataReader,
                productLedgerRoute: (productId) => TenantProductLedgerScreen(
                  reader: reader,
                  productId: productId,
                ),
              ),
              movementFeedRoles: TenantStockMovementFeedRepository.allowedRoles,
            ),
            catalogManagementRoles:
                TenantCatalogManagementRepository.allowedRoles,
            // **The sales this device has not sent.** The badge beside the
            // title already counts them; without this the home's own figures
            // could not, so a shopkeeper who rang one offline watched the
            // total refuse to move.
            checkoutOutbox: checkoutOutbox,
            pendingCheckoutPanel: CheckoutPendingEvidencePanel(
              source: CombinedLocalWorkEvidenceSource(
                checkouts: CheckoutOutboxEvidenceSource(checkoutOutbox),
                mutations: tenantMutationStore,
              ),
              // Without this the counts are read once when the session opens, so a
              // sale rang up moments earlier is reported as no sale at all.
              refreshSignals: mergeLocalWorkEvidenceSignals(
                checkoutSyncSignals.evidenceChanges,
                tenantMutationStore.changes,
              ),
              // The badge is about everything this device still owes, so it counts
              // the receipts that never printed along with the sales that never
              // sent. Both are on the page it opens.
              alsoWaiting: (tenantId) =>
                  _printQueueCount(checkoutPrintJobs, tenantId: tenantId) ?? 0,
              // **This device's unsent receipts, and the one control that can move
              // one: *Send again*.** It rebuilds nothing - the bytes on the job are
              // the ones the sale produced, so a receipt retried after a price
              // change still prints what was charged.
              notificationsRoute: (context) => TenantNotificationsScreen(
                // **Read here rather than inside the page.** This builder runs
                // under the `TenantSessionScope` the glyph pushes, so the
                // business is known at the one point that knows it - and the
                // page is left stating what it was given instead of hiding
                // every receipt when a lookup fails.
                tenantId:
                    TenantSessionScope.of(context).session?.tenantId ?? '',
                evidenceSource: CombinedLocalWorkEvidenceSource(
                  checkouts: CheckoutOutboxEvidenceSource(checkoutOutbox),
                  mutations: tenantMutationStore,
                ),
                refreshSignals: mergeLocalWorkEvidenceSignals(
                  checkoutSyncSignals.evidenceChanges,
                  tenantMutationStore.changes,
                ),
                printQueue: checkoutPrintJobs,
                onRetryPrint: (receiptNumber) async {
                  final result = await printDispatcher.retry(receiptNumber);
                  return result.outcome == CheckoutPrintOutcome.sent
                      ? null
                      : result.reasonCode;
                },
                // **The one notification here that is about the business.** A
                // shift whose cashier lost their access can be closed by nobody
                // at a till, so it is offered to the roles the Rules already let
                // read another cashier's shift - and to nobody else, which is
                // why both of these are null for a cashier rather than merely
                // disabled.
                abandonedShifts: () async {
                  final session = TenantSessionScope.read(context).session;
                  if (session == null ||
                      !TenantAbandonedShiftRepository.isVisibleTo(session)) {
                    return const <AbandonedShift>[];
                  }
                  return TenantAbandonedShiftRepository(
                    session: session,
                    reader: tenantDataReader,
                  ).find(collectionReader: tenantDataReader);
                },
                onCloseAbandonedShift: (shift) async {
                  final session = TenantSessionScope.read(context).session;
                  if (session == null) {
                    throw const AbandonedShiftCloseException(
                      AbandonedShiftCloseFailure.forbidden,
                    );
                  }
                  await FirebaseCloseAbandonedShiftCallable().call(<
                    String,
                    Object?
                  >{
                    'tenantId': session.tenantId,
                    'shiftId': shift.shiftId,
                    // **Required, and it is what the audit entry will say.**
                    // The server refuses a close carrying no reason at all,
                    // which is right for a destructive act on somebody else's
                    // shift. Nothing on this surface asks the operator to type
                    // one - the row already states the whole circumstance - so
                    // the circumstance is what gets recorded.
                    'reason':
                        'Closed from notifications: the cashier was '
                        'deactivated while this shift was open.',
                    // One request id per attempt, so a retry after an uncertain
                    // outcome is a new attempt rather than a replay of one the
                    // server may already have applied.
                    'requestId':
                        'close-${shift.shiftId}-'
                        '${DateTime.now().toUtc().millisecondsSinceEpoch}',
                  });
                },
              ),
            ),
            // §4.4 v0.7's top bar wants the signed-in member's name. Firebase has
            // already loaded it, so this hands over state that exists rather than
            // adding a read to the home - which is what kept the bar blocked for a
            // day. It is frequently null: an identity created by an emailed
            // invitation has no display name until somebody types one.
            memberName: () => FirebaseAuth.instance.currentUser?.displayName,
            signOut: FirebaseAuth.instance.signOut,
            // **Signing up is a route this screen opens, not a mode inside it.**
            // The wizard is pushed above the shell, so account creation - which
            // signs the new identity in and makes the shell rebuild underneath -
            // does not tear the flow down mid-way through it. It pops when the
            // business is open, revealing a shell that has already routed there.
            signedOut: LoginScreen(
              // A signed-out invitee who has just followed their link lands
              // here, and this is where the app says why it opened.
              invitationArrival: invitationIntake?.arrival,
              createAccountRoute: (context) => OnboardingFlow(
                readIdentity: () {
                  final user = FirebaseAuth.instance.currentUser;
                  return OnboardingIdentity(
                    uid: user?.uid,
                    email: user?.email,
                    emailVerified: user?.emailVerified ?? false,
                    // Deliberately not read from Firestore: a fresh signup has no
                    // root document to read until the blocking function has
                    // written one, and what this flow has just saved it already
                    // knows. See `OnboardingFlow._savedDisplayName`.
                    displayName: user?.displayName,
                    phone: null,
                  );
                },
                reloadIdentity: () async =>
                    FirebaseAuth.instance.currentUser?.reload(),
                // The wizard waits on the same mail the selector's panel does,
                // so it gets the same way of finding out it will never arrive.
                emailDeliveryStatusCallable:
                    FirebaseEmailDeliveryStatusCallable(),
                // **Signing out leaves, rather than staying put.** This
                // wizard is pushed above the shell, so a bare `signOut` left it
                // on screen over a sign-in screen it was hiding: the step it
                // was showing was about an identity that no longer existed, and
                // the way out was a back gesture nobody had been offered. The
                // sign-out is awaited first so what the pop reveals is already
                // the sign-in screen and not a frame of this flow's own
                // resumption.
                onSignOut: () async {
                  final navigator = Navigator.of(context);
                  await FirebaseAuth.instance.signOut();
                  if (navigator.canPop()) navigator.pop();
                },
                refreshSession: _refreshSession,
                reauthenticate: _reauthenticate,
                identityChanges: _identityChanges,
                resumeSession: _resumeSession,
                // **Ask first, then pop.** This wizard sits above the shell, so
                // the shell's last bootstrap ran before this business existed
                // and resolved - correctly, at the time - to no accessible
                // tenant. Popping alone therefore revealed *Almost there*, and
                // only a relaunch put the owner in the shop they had just
                // opened. The signal re-runs the bootstrap; the pop reveals it
                // already running.
                onOpenBusiness: (_) {
                  bootstrapRefreshSignals.requestAfterBusinessCreated();
                  Navigator.of(context).pop();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
