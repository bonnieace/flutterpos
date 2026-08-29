# Deploying this app to a live project

Everything a deploy needs that is not in the repository. None of it was written
down before; each item below was read out of the code it configures, and the
file that names it is cited so this can be checked rather than trusted.

> **Scope.** This is the backend and the release build. It does not cover
> choosing an application ID or a signing key — those are open decisions, see
> [Still open](#still-open).

---

## 1. Project

`.firebaserc` currently names one project for both aliases:

```json
{"projects": {"default": "multitenant-pos-b8326", "control": "multitenant-pos-b8326"}}
```

`functions/src/platform/grantPlatformAdmin.ts` labels that project **`dev`**, and
its CLI allowlist refuses to grant a platform administrator against a project the
environment does not match. The first live site runs on it anyway — a decision
taken on 2026-08-29 — which means **real sales share a project with development
data and development platform administrators, and there is no separate place
left to test.** Worth revisiting before a second site.

**Identity Platform must be enabled.** `bootstrapSelfSignupIdentity` is an Auth
blocking function (`functions/src/auth/identityBootstrap.ts`), and blocking
functions require Identity Platform rather than plain Firebase Auth. Without it
the deploy of that one function fails, and without that function **nobody can
sign themselves up**: `requestTenant` refuses an applicant with no
`users/{uid}` root document, and nothing else creates one.

---

## 2. Secrets

Six, in Secret Manager. Note that two constants do not match their secret names.

| Secret name | Read by | Notes |
|---|---|---|
| `EMAIL_RECIPIENT_HMAC_KEYRING` | `functions/src/email/config.ts` | Keyring, not a single key. Rotating it changes every recipient hash, so suppression lookups for old addresses stop matching. |
| `BREVO_API_KEY` | `functions/src/email/config.ts` (const `EMAIL_BREVO_API_KEY`) | Transactional sending. |
| `BREVO_WEBHOOK_SECRET` | `functions/src/email/config.ts` (const `EMAIL_BREVO_WEBHOOK_SECRET`) | Checked by `receiveBrevoEmailWebhook`. |
| `STAFF_INVITATION_HMAC_SECRET_V1` | `functions/src/staff/secret.ts` | **The literal is `…_V1`** while the constant is `STAFF_INVITATION_HMAC_SECRET`. Rotating invalidates every outstanding invitation token. |
| `TENANT_CURSOR_HMAC_SECRET` | `functions/src/tenants/routing.ts` | Signs `listMyTenants` pagination cursors. |
| `REMOVE_BG_API_KEY` | `functions/src/operations/productBackground.ts` | remove.bg. Only `removeProductBackground` needs it. |

```bash
firebase functions:secrets:set EMAIL_RECIPIENT_HMAC_KEYRING
firebase functions:secrets:set BREVO_API_KEY
firebase functions:secrets:set BREVO_WEBHOOK_SECRET
firebase functions:secrets:set STAFF_INVITATION_HMAC_SECRET_V1
firebase functions:secrets:set TENANT_CURSOR_HMAC_SECRET
firebase functions:secrets:set REMOVE_BG_API_KEY
```

## 3. Params

Eight, as environment configuration. Three are **URLs that must resolve to a page
that exists** — there is no hosting block in `firebase.json` yet, so these have
nowhere to point today.

| Param | What it is |
|---|---|
| `EMAIL_SENDER_ADDRESS` | From-address on every transactional email. |
| `EMAIL_SENDER_NAME` | From-name. |
| `PASSWORD_RESET_CONTINUE_URL` | Where a reset link returns the person. |
| `EMAIL_VERIFICATION_CONTINUE_URL` | Where a verification link returns them. |
| `STAFF_INVITATION_ACTION_BASE_URL` | Base of the emailed invitation link. |
| `STAFF_INVITATION_SENDER_EMAIL` | From-address for invitations specifically. |
| `STAFF_INVITATION_SENDER_NAME` | From-name for invitations. |
| `PLATFORM_ALERTS_URL` | Named in a platform alert email. |

---

## 4. Cloud Tasks queues

Six. Created by the first deploy of each `onTaskDispatched` function, but their
retry and rate settings live in code and are worth knowing:

| Queue | Attempts | Concurrency |
|---|---|---|
| `deliverPasswordReset` | 8 | 10 / 20 per sec |
| `deliverAccountVerification` | 8 | 10 / 20 per sec |
| `deliverPlatformAlertNotification` | — | 2 / 5 per sec |
| `runTenantReconciliationTask` | 12 | 10, 420 s, 512 MiB |
| `runReconciliationTenantDiscoveryTask` | 10 | 2, 300 s |
| `runMembershipRepairTask` | 10 | 10, 300 s |

`deliverPasswordReset` is `invoker: "private"`.

## 5. Cloud Scheduler

Ten jobs, all Africa/Nairobi. Created by deploying the `onSchedule` functions.

| When | Job |
|---|---|
| `30 5 * * *` | `startNightlyTenantReconciliation` |
| `45 4 * * *` | `startStaggeredMonthlyReconciliation` (day-of-month shard 1–28) |
| `30 4 * * 0` | `startWeeklyStockCheckpoints` |
| `15 3 * * 0` | `startWeeklyMembershipRepair` |
| every 10 min | `retryTenantReconciliationTasks`, `retryMembershipRepairTasks` |
| every 5 min | `retryGlobalUserStatusOperations`, `retryStaffInvitationDeliveries`, `retryPlatformAlertNotifications` |
| every 60 min | `cleanupAbandonedStaffIdentities` |

---

## 6. Rules and indexes

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage
```

`firestore.indexes.json` carries **42 composite indexes and 2 field overrides**.
Deploy them *before* first use: a missing composite index fails a query at
runtime with a console link, which is a poor way for a shop to discover it.

Verify the rules against the emulator first — this is the one suite that proves
the authorization boundary:

```bash
export JAVA_HOME="D:/firebase-emulator-tools/jdk21/jdk-21.0.12+8"
export PATH="/d/firebase-emulator-tools/jdk21/jdk-21.0.12+8/bin:$PATH"
cd rules-tests && npm run test:emulator      # 197 tests
```

`firebase-tools` refuses Java below 21; the machine's default `JAVA_HOME` is
JDK 17, which Gradle needs, so scope the override to the command.

---

## 7. Functions

```bash
cd functions && npm test && npm run deploy   # 438 tests, then 51 functions
```

## 8. Brevo

1. Create the account and an API key → `BREVO_API_KEY`.
2. Verify the sending domain for `EMAIL_SENDER_ADDRESS` and
   `STAFF_INVITATION_SENDER_EMAIL`.
3. Register the webhook at the deployed `receiveBrevoEmailWebhook` URL, with the
   shared secret as either an `Authorization` header or `x-brevo-webhook-secret`
   → `BREVO_WEBHOOK_SECRET`.

Without step 3 nothing ever records a bounce, so a suppressed address looks
like a delivery that simply never arrived.

## 9. Firebase Auth

Enable **Email/Password**. It is the only method this app has: `sign_in.dart`
and `account_registration.dart` do nothing else, and `operation-not-allowed` is
mapped to "not enabled for this app" precisely because that is the failure a
missed step here produces.

---

## 10. The first platform administrator

A chicken-and-egg the ordinary grant cannot solve: it requires an `--actor-uid`
who is already a platform administrator, and on a fresh project that is nobody.
Without one, **no requested business can ever be approved.**

1. Sign up in the app with the address that will own the platform. This creates
   the Auth identity and, through `bootstrapSelfSignupIdentity`, its root
   document. Note the UID.
2. Run the break-glass grant:

```bash
cd functions
npm run grant-platform-admin -- --bootstrap \
  --environment dev \
  --project-id multitenant-pos-b8326 \
  --confirm-project-id multitenant-pos-b8326 \
  --target-uid <UID> \
  --confirm-target-uid <UID> \
  --request-id platform-bootstrap-001 \
  --reason "Bootstrapping the first platform administrator."
```

It is refused the moment any platform administrator exists, so it works **once
per project** and then stops working. A failure that leaves the target
mid-transition is retried with the same `--request-id`; the saga resumes.

Afterwards, grant every further administrator with the ordinary form, which
requires a sitting administrator as `--actor-uid`.

## 11. Backfills

Only if data pre-dates the search-prefix fields:

```bash
cd functions
npm run backfill-product-search
npm run backfill-staff-search
```

---

## 12. A new business, end to end

What the first site actually walks through:

1. Sign up in the app → `bootstrapSelfSignupIdentity` writes `users/{uid}`.
2. Verify the email address (the *Request business* control refuses until then).
3. Request a business → `requestTenant` writes it `pending` **with a seven-day
   provisional window**, and it can trade immediately.
4. Set the currency, or the till refuses every sale
   (`configurationUnavailable`). Then business details, printer, products.
5. A platform administrator approves it, which is a status flip: every document
   was written at step 3.

**If nobody approves within the week**, the business becomes read-only — it keeps
every record and cannot trade — and the till stops accepting sales in the final
day while anything is still unsent, so nothing is stranded. **Rejection is
immediate and complete.** See `firestore.rules` (`tradingTenant`,
`readableTenant`) and `functions/src/core/authorization.ts`
(`tenantSatisfiesAccessMode`).

Nothing notifies a platform administrator that a request has arrived —
`requestTenant` writes `platform_audit_logs`, not `platform_alerts`. Somebody
has to look. See [Still open](#still-open).

---

## Still open

Known and deliberate, so a deploy is not surprised by them:

- **Application ID and signing.** `android/app/build.gradle.kts` still carries
  `com.example.flutter_application_1` and signs release with the **debug**
  keystore; the iOS bundle ID is the template default. Changing the ID needs a
  matching `google-services.json` from a newly registered app.
- **App Check is debug-only** (`lib/main.dart`). Release attestation needs Play
  Integrity, which needs the release keystore's SHA-256. Until then
  `requestPasswordReset` — the only `enforceAppCheck: true` callable — fails in
  a release build. The UI maps that to "this app could not prove itself".
- **No hosting.** The three continue-URL params have nowhere to point, and
  Android App Links need `/.well-known/assetlinks.json` on the same domain.
- **Emailed invitation links cannot open the app.** `Uri.base` on Android is a
  `file://` path, and there is no `app_links` dependency or intent-filter.
  Mobile staff must use the in-app visible-acceptance path in the selector.
- **Sentry is off in release**, deliberately: the DSN is cleartext `http://`.
- **No alert on a new business request**, above.
- **Returns never touch the money.** Reconciliation, `daily_metrics` and
  `getSalesComparison` aggregate `sales` only, and a return records no refund
  amount — so reported takings are gross of refunds.
- **No tax/VAT modelling**, no discounts, business day hardcoded to
  Africa/Nairobi, no receipt reprint, network ESC/POS printers only, barcode
  scanning unwired (a keyboard-wedge scanner works).
