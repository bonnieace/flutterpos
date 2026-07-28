# Client configuration audit

## Purpose

This document identifies values and assumptions that are tied to the current client or Firebase project and must be made configurable before this codebase can be safely reused for other clients.

## Decision summary — shared public app

- Keep one public app name, icon, package/bundle ID, signing identity, and store listing owned by us.
- Build and publish one app binary. Normal client onboarding must **not** rebuild the app.
- The binary connects first to a fixed control-plane Firebase project, resolves a tenant code, and then initializes a named secondary Firebase app for that tenant's project.
- Put client-visible identity inside the signed-in experience: business name, logo, colors, receipts, payments, regional settings, and feature flags.
- Provision tenant Firebase projects and their backend resources from the control plane. The proposed implementation is in `files/`.

### Configurable without rebuilding

- Tenant Firebase project/options returned by the control plane
- Business/trading name, logo, theme colors, contact/address details
- Receipt footer, tax/PIN, till/paybill/account details
- Currency, locale, time zone, business-day cutoff
- Payment methods, thresholds, printer settings, feature flags
- Tenant users, roles, inventory, categories, and operational data
- Tenant Cloud Functions/rules/index version, deployed server-side

### Still requires an app rebuild and store release

- Installed app name or launcher icon
- Android package ID, Apple bundle ID, signing, capabilities, or entitlements
- Native splash assets, permissions, SDKs/plugins, and minimum OS targets
- Store listing metadata/screenshots where the store requires a new release
- A change to the control-plane Firebase project compiled into the bootstrap app

Owning the public app identity removes nearly all per-client rebuild work. A rebuild becomes a product release event, not a tenant-onboarding step. The build-profile/flavor approach later in this audit is therefore an optional white-label path, not the chosen default architecture.

The main conclusion is that changing only the Firebase project is **not enough**. The application currently mixes four kinds of client-specific state:

1. Firebase/project wiring needed before the app starts.
2. Build-time identity such as package IDs, display names, icons, and splash screens.
3. Runtime business settings such as receipt details, currency, payments, printer settings, and business-day rules.
4. Secrets and privileged identifiers that should not be shipped in the app at all.

## Current configuration status

- Firebase initialization is generated and hard-coded in `lib/firebase_options.dart`.
- `lib/config.dart` contains the beginnings of a store configuration screen, but the **entire file is commented out**. The settings buttons that would open it are also commented out in `lib/screens/main_hub_screen.dart:231-276`.
- The only active read from the `store` collection uses one hard-coded document ID and only reads application-update fields (`lib/screens/main_hub_screen.dart:115-120`).
- There is no active, central client configuration model or service. Client values are duplicated across UI, receipts, reports, and platform files.
- No Firestore rules, Storage rules, Firestore index definition, or repeatable seed/bootstrap script is checked into the repository.

## Priority summary

| Priority | Area | Why it blocks reuse |
| --- | --- | --- |
| P0 | Firebase app/project selection | Every client build must point to the correct Auth, Firestore, Storage, and Functions resources. |
| P0 | Receipt and invoice identity | The current client's names, address, payment details, and till number would appear on another client's documents. |
| P0 | Hard-coded privileged IDs and API credentials | Access behavior and third-party usage would remain tied to the current project/account. |
| P0 | Firebase bootstrap, rules, indexes, and functions | A newly selected Firebase project will not work merely because its IDs were copied into the app. |
| P1 | App name, IDs, icons, splash, theme | Installable builds and UI would still carry old or placeholder branding. |
| P1 | Regional and POS rules | Currency, payment methods, dates, shifts, printing, and thresholds differ by client. |
| P2 | Bar-specific schema and terminology | `alcohol`/`alcoholsales` and bar-oriented UI limit reuse for other business types. |
| P2 | Old artifacts and unused client assets | They can leak prior-client branding or data into distributions and future work. |

## Detailed findings

### 1. Firebase project and platform app registration — P0

The following files point directly to the current Firebase project and must be generated or selected for each client:

| File | Current coupling | Required treatment |
| --- | --- | --- |
| `.firebaserc:3` | Default Firebase CLI project is `thamani-23709`. | Use explicit aliases per client and require an explicit project during deploy. Do not rely on an accidentally selected default. |
| `firebase.json:4-24` | FlutterFire platform-to-app mappings contain the current project ID and app IDs. | Regenerate with FlutterFire for each client profile. |
| `lib/firebase_options.dart:43-87` | API keys, Firebase app IDs, sender ID, project ID, auth domain, bucket, analytics IDs, and Apple bundle ID are compiled into the app. | Generate a client-specific options file or select generated options through build flavors. Firebase API keys are project identifiers, not server secrets, but the mapping must still be correct. |
| `android/app/google-services.json:2-60` | Contains the current project and three Android client registrations. | Replace with the new project's generated file and ensure the selected entry matches the build's application ID. |
| `android/app/build.gradle.kts:12,27` | Android namespace/application ID is fixed. | Define a stable base ID or per-client flavor IDs, then register those exact IDs in Firebase. |
| `ios/Runner.xcodeproj/project.pbxproj:371,550,572` | iOS bundle ID is fixed. | Parameterize it through schemes/configurations and register each ID in Firebase. |
| `macos/Runner/Configs/AppInfo.xcconfig:11` | macOS bundle ID is fixed. | Parameterize it alongside the selected Firebase macOS app. |

`FirebaseFunctions.instance` is used without a region override in `lib/screens/create_user.dart:84`, `lib/screens/users.dart:1710-1711`, and `lib/pos/reports.dart:191-192`. If functions are deployed outside the default region, the region must also be part of configuration.

Linux currently throws `UnsupportedError` in `lib/firebase_options.dart:25-28`, so Linux is not a supported Firebase target in the current setup.

### 2. Firebase environment bootstrap — P0

Selecting another Firebase project also requires the following project-side setup:

- Enable Email/Password Firebase Authentication; the login screen calls `signInWithEmailAndPassword`.
- Deploy the Cloud Functions in `functions/src/index.ts`: `getSalesComparison`, `createStaffUser`, and `toggleStaffStatus`.
- Create an initial Firebase Auth administrator and a matching `staff/{uid}` document. Otherwise nobody can log in and `createStaffUser` cannot authorize its caller.
- Create the client configuration/store document, initial product categories, and any opening inventory.
- Create required Firestore composite indexes. Current queries include combinations such as:
  - `shifts`: `staffId + status + startTime`
  - `alcoholsales`: `businessDate + soldBy`
  - `staff`: `status + role`
  - `returns`: `timestamp` ordering/filtering
- Add and deploy Firestore and Storage security rules. None are currently declared in `firebase.json`.
- Configure Storage and its CORS requirements if product-image upload is enabled.
- Decide whether historical data, users, inventory, and storage objects are migrated or the project starts empty.

The current application expects these Firestore collections:

| Collection | Purpose |
| --- | --- |
| `staff` | Login profile, role, status, and current-shift state. |
| `shifts` | Opening/closing state and business-day totals. |
| `categories` | Product categories. |
| `alcohol` | Product/inventory records. |
| `alcoholsales` | Transactions. |
| `returns` | Returns, voids, and fraud-review data. |
| `store` | Update metadata; intended store configuration is currently disabled. |
| `orphaned_auth_users` | Cloud Function rollback-failure log. |

There are also legacy report files that still reference `hwsales` and `hstock` (`lib/pos/reports/debtpayment.dart`, `monthlyreports.dart`, and `productreport.dart`). These pages appear disconnected from the active hub, but they should be removed, migrated, or clearly marked unsupported so a future route does not silently query a different schema.

### 3. Client name and visible branding — P0/P1

Hard-coded current-client branding appears in active UI and generated reports:

- `ChillTent` is displayed in:
  - `lib/screens/create_user.dart:445`
  - `lib/screens/users.dart:84,162,1776`
  - `lib/pos/goods.dart:1071,4793`
  - `lib/pos/reports.dart:1368`
  - `lib/pos/reports/paymentsfreq.dart:142`
- Android's installed app label is `ChillTentPOS` in `android/app/src/main/AndroidManifest.xml:3`.
- The login email example contains `spiritpos.com` in `lib/login_screen.dart:158`, while the root widget/theme are also internally named `SpiritPOSApp` and `spiritTheme` (`lib/main.dart:35-41`, `lib/theme.dart:9`). Internal class names do not affect users, but the mixed naming shows that branding has no single source.
- Placeholder product identity remains in several platform files:
  - `pubspec.yaml:1-2`
  - `ios/Runner/Info.plist:7-16`
  - `web/index.html:24,30`
  - `web/manifest.json:2-6`
  - `macos/Runner/Configs/AppInfo.xcconfig:8-14`
  - `windows/runner/Runner.rc:92-98`
  - `windows/runner/main.cpp:30`

Create configuration fields for at least:

- Public/trading name
- Legal entity name
- Short app name and full display name
- Tagline/slogan
- Support email, phone, and website
- Copyright owner
- Login hint/domain, if a branded hint is desired

### 4. Icons, splash screens, and bundled assets — P1

`images/logo.png` is the source for launcher icons and splash images in:

- `flutter_launcher_icons.yaml:4-29`
- `splash.yaml:4-11`
- the duplicate configuration in `pubspec.yaml:142-162`

Generated copies exist under Android resources, iOS/macOS asset catalogs, Windows resources, and `web/icons`/`web/splash`. Replacing only `images/logo.png` will not update an already generated build; the icon and splash generators must run as part of each client build/onboarding process.

The `images` directory also contains likely client- or business-specific assets such as `jamos-removebg-preview.png`, `brand1.png` through `brand3.png`, several other logo files, bar/drink images, and background mockups. Most are not referenced by active Dart code, but they should be classified as shared, client-owned, or removable.

The checked-in `app-release.apk`, screenshots, HTML mockup, logs, and root PDF should also be reviewed. Client builds and screenshots should not be treated as reusable source assets.

### 5. Receipt and printer configuration — P0

The thermal receipt is implemented twice and contains duplicated client data:

| Setting | Evidence |
| --- | --- |
| Receipt header/business name | `lib/pos/pos.dart:722`, `lib/services/Receipt_service.dart:46` |
| Location/address | `lib/pos/pos.dart:731`, `lib/services/Receipt_service.dart:55` |
| Currency text | `lib/pos/pos.dart:821`, `lib/services/Receipt_service.dart:137` and many other UI/report locations |
| Till number | `lib/pos/pos.dart:834`, `lib/services/Receipt_service.dart:149` |
| Payment account name | `lib/pos/pos.dart:839`, `lib/services/Receipt_service.dart:154` |
| Printer HTTP endpoint | `lib/pos/pos.dart:849`, `lib/services/Receipt_service.dart:164` |
| Paper width | `lib/pos/pos.dart:716`, `lib/services/Receipt_service.dart:40` |
| Request timeout | `lib/pos/pos.dart:862`, `lib/services/Receipt_service.dart:177` |
| Number of receipt copies | Two copies are explicitly printed at `lib/pos/pos.dart:3075-3089`. |

Create one receipt/printer configuration consumed by both implementations. It should include business name, address lines, phone/email, tax/KRA PIN if needed, footer, return policy, till/paybill/account details, paper size, printer connection type/endpoint, timeout, and copy count.

The printer endpoint is a private LAN IP belonging to the current installation. It must be store/device-level configuration, not a global constant baked into every client build.

### 6. Invoice identity and payment details — P0

Invoice generation currently uses a different hard-coded supplier:

- Supplier: `Jamos Solutions` — `lib/pos/pos.dart:3014`
- Postal address — `lib/pos/pos.dart:3015`
- Paybill, account number, and account name — `lib/pos/pos.dart:3016-3018`
- Three-day due date — `lib/pos/pos.dart:3010`
- Receipt PDF header/location: `lib/api/pdf_invoice_api.dart:57,65`

These values must come from the same client identity/billing configuration as the receipt. Payment identifiers should never be copied between clients by default.

### 7. Currency, locale, tax, and time — P1

Currency formatting is not centralized:

- Most active screens and reports hard-code variations of `Ksh`, `KSh`, or `KSH`.
- `lib/utils.dart:4` hard-codes `Ksh`.
- `lib/pos/utils/formatters/formatter.dart:9-10` instead formats US dollars using `en_US`.
- Decimal digits vary between zero and two across screens and reports.

Use a configured ISO currency code and locale with one formatter everywhere. Suggested fields are `currencyCode`, `currencySymbol`, `locale`, and `currencyDecimalDigits`.

Other regional/business rules to configure:

- Tax enablement and rate. `lib/pos/pos.dart:1449` calculates 8.25%, while `lib/pos/utils/helpers/pricing_calculator.dart:27-30` contains an example 10% rate.
- Time zone. The application mostly uses device-local `DateTime.now()`, which can produce different business dates on incorrectly configured devices.
- Business-day cutoff. `lib/services/shift_service.dart:8` uses **5 AM**, but `lib/screens/main_hub_screen.dart:1221-1226` uses **6 AM**. This is both client-specific and a current correctness bug; one shared setting/function must be used.
- Date/time display format and first day of the reporting week.

### 8. Payments, roles, permissions, and feature availability — P0/P1

Payment methods are both client-specific and inconsistent:

- POS checkout offers `Cash`, `Mpesa`, `Bank`, `Debt`, and `Split` at `lib/pos/pos.dart:1392` and `1820`.
- Sales-report editing only offers `Cash`, `Mpesa`, and `Bank` at `lib/pos/reports/salesReports.dart:65`.
- Payment reporting contains additional `Card` labels/handling in `lib/pos/reports/paymentsfreq.dart`.

Configure enabled payment methods and their canonical IDs/display labels once, then reuse that list in checkout, returns, shifts, and reports.

Roles are fixed as `Admin`, `Manager`, and `Cashier` in both Flutter UI (`lib/screens/create_user.dart:621-623`) and Cloud Functions (`functions/src/index.ts:247`). Module visibility is hard-coded by those role names in `lib/screens/main_hub_screen.dart:660-765`. If clients can have different roles or enabled modules, permissions should be data-driven. If the roles are a permanent product contract, document and seed them consistently instead of treating them as arbitrary strings.

A specific Firebase Auth UID receives special cashier reporting access in `lib/pos/reports/salesReports.dart:148-153`. This must be removed before switching projects. Use an explicit permission/custom claim such as `reports.viewAllSales`, not a client user's UID.

### 9. Update distribution — P0/P1

The app checks one hard-coded `store` document ID at `lib/screens/main_hub_screen.dart:115` for:

- `latest_version`
- `update_message`
- `download_url`

Use a stable path present in every project, such as `app_config/current`, or make the store ID part of the selected client profile. The update channel and download URL may also need to differ by platform and client.

### 10. External services and embedded credentials — P0

- The error-monitoring DSN and aggressive trace/profile/replay sampling are hard-coded in `lib/main.dart:12-21`. Monitoring environment, release, sample rates, and privacy masking must be selected per deployment. Client data should not be sent to the current monitoring project by accident.
- A remove.bg API key is embedded twice in `lib/pos/goods.dart:1927,3012`, and the API is called directly from the client near `lib/pos/goods.dart:2277-2285`. Treat the exposed key as compromised, rotate it, and proxy this operation through a protected backend/Cloud Function using a secret manager. Do not place the replacement key in a client profile or Firestore document readable by the app.
- The printer endpoint is installation-specific configuration, as described above.
- The placeholder base URL in `lib/pos/utils/http/http_client.dart:5` should be removed or made an explicit environment setting before that helper is used.

### 11. Theme and visual identity — P1

The main theme palette is defined in `lib/theme.dart:4-7`, but the same green/dark colors are also repeated as literals throughout large screens such as `lib/pos/goods.dart`. Supporting client themes will require replacing those repeated literals with theme tokens (`ThemeData`/`ColorScheme`) before a configured palette can work reliably.

At minimum, configure primary/accent color, background/surface colors, logo variants, and light/dark mode policy. Keep accessibility contrast validation in the shared application rather than making it optional per client.

### 12. Inventory terminology and thresholds — P1/P2

The data model is specifically named for a bar:

- Products are stored in `alcohol`.
- Sales are stored in `alcoholsales`.
- Some UI copy says "alcoholsales" (`lib/pos/goods.dart:158,246`).
- Bundled beer/gin assets reinforce the same vertical assumption.

If every client is a bar/lounge, the collection names can remain an internal schema contract, although visible terms should still be configurable. If this product will serve other retail types, migrate to neutral collection/domain names such as `products` and `sales`, or add a repository layer so UI/business logic does not know the physical collection names.

Inventory warning thresholds are also inconsistent: low stock is `< 5` in `lib/pos/goods.dart:654,1691` but `<= 5` in `lib/pos/reports.dart:316-318`; high stock uses `> 100` in `lib/pos/goods.dart:658`. Put these thresholds in one configuration source.

## Recommended configuration split

Do not put every setting in one `.env` file. Different settings are needed at different points in the application lifecycle.

### A. Build profile / flavor

Used before Firebase and Flutter UI can start:

- Client/profile ID
- Firebase options for every supported platform
- Android application ID/namespace
- Apple/macOS bundle IDs
- Installed app display name
- Icons, splash images, and web manifest metadata
- Monitoring environment and DSN
- Default/fallback client configuration

A practical layout would be one non-secret profile per client plus generated platform files, for example:

```text
clients/
  client_a/
    app_profile.json
    logo.png
    google-services.json
  client_b/
    app_profile.json
    logo.png
    google-services.json
```

Flutter values can be selected with flavors and/or `--dart-define-from-file`. Native identifiers, native app names, and Firebase native files should be selected by Android product flavors and Apple schemes/configurations, or by a validated generation script.

### B. Runtime client/store document

Once Firebase is initialized, load a stable document such as `app_config/current`. Suggested shape:

```yaml
identity:
  tradingName: ""
  legalName: ""
  slogan: ""
  logoUrl: ""
  supportEmail: ""
  supportPhone: ""
  addressLines: []
regional:
  locale: "en_KE"
  timeZone: "Africa/Nairobi"
  currencyCode: "KES"
  currencySymbol: "KSh"
  currencyDecimalDigits: 2
pos:
  businessDayCutoffHour: 5
  taxEnabled: false
  taxRate: 0.0
  paymentMethods: []
  lowStockThreshold: 5
  highStockThreshold: 100
receipt:
  footerLines: []
  taxPin: ""
  tillNumber: ""
  paybillNumber: ""
  paymentAccount: ""
printing:
  endpoint: ""
  paperWidthMm: 80
  copies: 1
  timeoutSeconds: 10
features:
  returns: true
  inventory: true
  reports: true
updates:
  latestVersion: ""
  message: ""
  downloadUrls: {}
theme:
  primaryColor: ""
  accentColor: ""
```

Use typed Dart models, validation, defaults, and a local cache. A missing or invalid P0 field should show a clear configuration error rather than silently printing another client's fallback details.

### C. Backend-only secrets

Store secrets in the relevant backend secret manager, not in Dart, generated assets, `--dart-define`, or readable Firestore documents:

- remove.bg or other paid API credentials
- service-account credentials
- private payment-provider credentials/webhook secrets
- any future signing or integration secrets

## Recommended implementation order

1. Create typed `BuildProfile` and `ClientConfig` models plus a single configuration service.
2. Remove the hard-coded privileged UID and replace it with role/permission data or Firebase custom claims.
3. Move third-party API calls requiring secrets behind Cloud Functions and rotate the exposed key.
4. Centralize receipt/invoice identity and printer configuration; make all print paths use it.
5. Centralize money, locale, tax, time zone, and business-day calculation. Resolve the current 5 AM/6 AM mismatch.
6. Centralize payment methods, roles/permissions, feature flags, and stock thresholds.
7. Replace UI brand strings and literal brand colors with configuration/theme tokens.
8. Add per-client build flavors/schemes for Firebase files, package IDs, app names, icons, and splash screens.
9. Add Firebase rules, indexes, Cloud Function deployment, and an idempotent bootstrap/seed command to source control.
10. Add an onboarding validation command that verifies the selected profile, Firebase project, required collections/config document, Auth provider, deployed functions, rules, indexes, storage, and build identifiers before release.

## New-client switching checklist

### Firebase

- [ ] Create/select the Firebase project and record the expected project ID.
- [ ] Register each supported Android, iOS, macOS, web, and Windows app using the exact build identifiers.
- [ ] Regenerate/select FlutterFire options and native Firebase files.
- [ ] Enable Email/Password authentication.
- [ ] Deploy functions, Firestore rules, Storage rules, and indexes to the explicit client project.
- [ ] Create the initial administrator Auth user and matching `staff/{uid}` document.
- [ ] Seed `app_config/current`, categories, and any initial inventory.
- [ ] Verify Storage/CORS and product-image upload.

### Brand/build

- [ ] Select app display names, application/bundle IDs, version/update channel, logo, icons, splash, web metadata, and copyright.
- [ ] Generate icons and splash assets, then confirm no generated asset still carries another client's logo.
- [ ] Select the client's monitoring project/environment and privacy settings.

### Business configuration

- [ ] Verify legal/trading identity, address, support contacts, tax details, receipt footer, and payment/till account.
- [ ] Verify currency, locale, time zone, business-day cutoff, date formats, and tax rules.
- [ ] Verify payment methods, roles/permissions, enabled modules, inventory thresholds, printer endpoint/paper/copies, and update URL.
- [ ] Confirm whether old data is migrated or the project intentionally starts empty.

### Release validation

- [ ] Log in as admin, manager, and cashier and verify each permission boundary.
- [ ] Create a product and category, upload an image, open a shift, complete each enabled payment type, return/void a sale, and close the shift.
- [ ] Verify reports and Cloud Functions against the selected project.
- [ ] Print and inspect a receipt/invoice for old names, addresses, accounts, currency, or logos.
- [ ] Confirm the application package/bundle IDs, display name, launcher icon, splash, monitoring environment, and update channel.
- [ ] Search the release source/build output for prior-client names and identifiers before handoff.

## Definition of done

The project is ready for safe per-client Firebase switching when a client can be selected by one explicit build/profile choice, a repeatable bootstrap command prepares the matching Firebase project, no client-specific names/IDs/credentials remain in shared Dart code, and an automated validation step fails the build if required settings or project mappings are missing or inconsistent.
