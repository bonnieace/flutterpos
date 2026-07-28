# Shared-app tenant control plane

## TL;DR

- Keep one app name, icon, package ID, and store listing. Build the Flutter app once.
- Ship only the **control-plane Firebase config** in that app.
- On first launch, resolve a tenant code through `getTenantConfig`, then initialize a named/secondary Firebase app using the returned config.
- Each client gets a separate Firebase project and data boundary.
- Business name, logo, colors, receipt text, and other internal branding live in tenant Firestore and change without rebuilding.
- A rebuild is still needed for native/store-facing changes: package/bundle ID, installed app name/icon, signing, permissions, native plugins, or App Check platform registration.

This folder is a runnable reference bundle, not just pseudocode. It includes the control-plane Functions, private Firestore rules, an internal onboarding console, retry handling, and contracts for the two infrastructure integrations that must be supplied by your environment.

## What the flow does

1. A `superAdmin` signs in to the internal web console and calls `onboardTenant`.
2. The callable validates the input, allocates the globally unique project ID **before any external side effect**, and creates `tenants/{tenantCode}` as `pending`.
3. `onTenantProvisionRequested` transactionally claims that job. Duplicate Firestore event delivery cannot claim it twice.
4. The provisioner creates or reuses the Cloud project, links billing, enables APIs, adds Firebase, creates Firestore and Storage, enables email/password Auth, deploys rules, registers the one shared Android package, and seeds branding plus the first Admin staff record.
5. Private hooks deploy the tenant runtime artifact and send the owner's setup email.
6. Only after every required step succeeds does the tenant become `ready`.
7. The distributed app calls the App Check-protected `getTenantConfig` and initializes tenant-scoped Auth, Firestore, Functions, and Storage instances.

Failed jobs retain the same project ID and completed-step checkpoints. `retryTenantProvisioning` safely requeues an error or a provisioning lease older than 15 minutes. Google resource creation is implemented as ensure/get-or-create operations, while the two hooks receive idempotency keys.

## Files

- `index.ts` — Admin initialization and exported Functions.
- `onboardTenant.ts` — admin-only enqueue callable.
- `onTenantProvisionRequested.ts` — leased provisioning worker and status tracking.
- `projectProvisioner.ts` — idempotent Google/Firebase resource bootstrap.
- `getTenantConfig.ts` — App Check-protected resolver used by the distributed app.
- `listTenants.ts`, `retryTenantProvisioning.ts` — operations-console API.
- `control-plane.rules` — denies all direct browser access; the console uses callables.
- `web/` — Vite/Firebase internal onboarding console.
- `HOOK_CONTRACTS.md` — required runtime-deployment and owner-email integrations.
- `firebase.control-plane.example.json` — standalone multi-codebase/Hosting example.

## Prerequisites

### 1. Organization or folder

`CONTROL_PLANE_PARENT_RESOURCE` is mandatory and must be `organizations/NUMBER` or `folders/NUMBER`. Service-account project creation is not supported as an unparented personal project workflow. Confirm project-creation quota and applicable organization policies before onboarding real clients.

### 2. Dedicated provisioner identity

Create a dedicated service account and set `CONTROL_PLANE_PROVISIONER_SERVICE_ACCOUNT` to its email. Do not run the provisioning trigger as the default broad Functions identity.

Grant only what the pipeline needs, at the narrowest folder/billing scope. This normally includes project creation on the tenant folder, billing-account use, API enablement, Firebase administration, Firestore/Datastore administration, Firebase Auth administration, Rules administration, and Storage administration. New tenant projects must inherit the resource-level permissions needed by that identity. Test the exact permissions in a non-production folder; organization-policy constraints vary.

Keep deployment permissions on the separate runtime-deployment hook identity described in `HOOK_CONTRACTS.md`.

### 3. Control-plane parameters and secrets

The non-secret parameters are Firebase Functions parameterized configuration. Deployment prompts for values with no default; they can also be placed in the appropriate `.env.<control-project-id>` file:

```dotenv
CONTROL_PLANE_REGION=europe-west1
CONTROL_PLANE_PARENT_RESOURCE=folders/123456789012
CONTROL_PLANE_BILLING_ACCOUNT=billingAccounts/AAAAAA-BBBBBB-CCCCCC
CONTROL_PLANE_FIRESTORE_REGION=africa-south1
CONTROL_PLANE_ANDROID_PACKAGE_NAME=com.yourcompany.sharedpos
CONTROL_PLANE_PROVISIONER_SERVICE_ACCOUNT=tenant-provisioner@CONTROL_PROJECT.iam.gserviceaccount.com
TENANT_RUNTIME_DEPLOY_HOOK_URL=https://runtime-deployer.example.internal/deploy
TENANT_OWNER_EMAIL_HOOK_URL=https://mailer.example.internal/tenant-owner
```

Create the hook secrets without putting them in source control:

```bash
firebase functions:secrets:set TENANT_RUNTIME_DEPLOY_HOOK_SECRET --project CONTROL_PROJECT_ID
firebase functions:secrets:set TENANT_OWNER_EMAIL_HOOK_SECRET --project CONTROL_PROJECT_ID
```

### 4. Control-plane Auth and App Check

- Add a Web App to the control-plane Firebase project.
- Enable Email/Password Auth for internal operators.
- Create the first operator, authenticate locally with ADC for the control project, then run:

```powershell
$env:CONTROL_PLANE_PROJECT_ID='your-control-project-id'
npm run grant-super-admin -- admin@example.com
```

- Register the web console and the distributed Android app with App Check in the control-plane project. Enforce App Check on the callable Functions after testing valid tokens.
- Put the control-plane Web App values and reCAPTCHA site key in `web/src/firebase-config.js`.

## Build and deploy

From this folder:

```bash
npm install
npm run check
npm run build
npm --prefix web install
npm --prefix web run build
```

To deploy this folder as a separate Firebase Functions codebase, copy `firebase.control-plane.example.json` to `firebase.json` in this folder and run Firebase CLI against the control project. If merging into the repository's existing `functions/` codebase instead, copy the TypeScript modules into `functions/src/` and export the five functions from its existing `index.ts`; do not replace the app's existing tenant-runtime functions.

Deploy the control-plane Firestore rules and Hosting site only to the parent/control project, never to tenant projects.

## Flutter integration still required

The app must stop using default Firebase singletons for tenant data. After resolving the config, initialize one named app and pass it consistently to every product:

```dart
final tenantApp = await Firebase.initializeApp(
  name: tenantCode,
  options: FirebaseOptions(
    apiKey: config.apiKey,
    appId: config.appId,
    messagingSenderId: config.messagingSenderId,
    projectId: config.projectId,
    storageBucket: config.storageBucket,
    authDomain: config.authDomain,
  ),
);

final auth = FirebaseAuth.instanceFor(app: tenantApp);
final db = FirebaseFirestore.instanceFor(app: tenantApp);
final storage = FirebaseStorage.instanceFor(app: tenantApp);
final functions = FirebaseFunctions.instanceFor(app: tenantApp, region: 'YOUR_RUNTIME_REGION');
```

Wrap these in a tenant session/service rather than calling `FirebaseAuth.instance`, `FirebaseFirestore.instance`, `FirebaseStorage.instance`, or `FirebaseFunctions.instance` throughout the UI. Clear the tenant session on tenant switch and never mix a tenant user's token with control-plane calls.

## Production gates that remain environment-specific

- Implement and secure both hook services; onboarding intentionally cannot become `ready` without them.
- Add billing budgets/alerts, project-count quota monitoring, audit-log alerts, and an approved offboarding/retention workflow.
- Validate the generated rules against every app query/write with Emulator Suite tests. The included rules match the current `Admin`/`Manager`/`Cashier` and `staff/{uid}` model, but business permissions still need product approval.
- Pin and release an immutable tenant runtime artifact. Include its version in hook idempotency keys when upgrading tenants.
- Test the Firebase default-bucket management API in the target organization; that endpoint is versioned `v1alpha`, so keep it behind integration tests.
- Decide whether tenant project IDs/business metadata are acceptable in your organization inventory and logs.
