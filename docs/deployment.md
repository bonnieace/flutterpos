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

**The Firestore database is not created by any of this.** A project can exist, be
on Blaze, and hold no database at all — `firebase firestore:databases:list` answers
"No databases found", and every rules or index deploy fails until one exists. Create
it explicitly, and note that **the location is permanent**:

```bash
firebase firestore:databases:create "(default)" --location us-central1
```

`us-central1` is chosen to match where the functions land. Nothing in this repo sets
a region, so all 51 deploy to `us-central1` by default and the two belong together;
a database in Europe with functions in Iowa pays a round trip on every read. Blocking
functions are the exception and are pinned elsewhere regardless — see
[Functions](#7-functions).

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

Eight, as environment configuration. A deploy reads them from
`functions/.env.<projectId>` — the deploy-time counterpart to `.env.local`, which
only the emulator ever reads. Without that file the CLI stops and prompts for each
`defineString` it cannot resolve, so a scripted deploy hangs rather than fails.
Nothing secret belongs in it; these values are visible in the deployed function's
configuration.

Three are **URLs that must resolve to a page that exists**, and the constraint is
sharper than it looks. Two are handed to `generateEmailVerificationLink` /
`generatePasswordResetLink` as `url:`, and **Auth refuses a continue URI on a domain
outside its authorized list**. A placeholder does not merely land nowhere — it
throws, the send fails, and nobody can verify an address. `<project>.web.app` is
authorized from day one, which is what [Hosting](#3b-hosting) exists to serve.

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

## 3b. Hosting

Four of the eight params point here, and two of them *must* — see
[Params](#3-params).

```bash
firebase deploy --only hosting
```

`public/` holds five static pages and a shared stylesheet, served at
`https://<project>.web.app`:

| Path | Reached by |
|---|---|
| `/auth/verified` | a person, after Firebase has verified their address |
| `/auth/password-reset-complete` | a person, after their password is changed |
| `/staff/invitation` | the emailed staff invitation link |
| `/platform/alerts` | a link inside a platform alert email |
| `/` | nothing — it exists so the bare domain is not a 404 |

They are deliberately inert: no sign-in, no state, and no script beyond reading
`tenantId` out of the query string on the invitation page. **Firebase's own action
handler does the verifying**; these pages are only where a person lands afterwards,
which is why a wrong value here breaks the send rather than the page.

`cleanUrls: true` in `firebase.json` maps `/auth/verified` to `auth/verified.html`,
so the params must not carry the `.html`.

The invitation page cannot accept an invitation, and says so. That link carries
`tenantId`, `uid`, `invitationVersion` and `invitationToken` as query parameters —
it *is* the payload, not a redirect to one — but nothing on Android can receive it,
so the page directs people to the in-app selector. The token is deliberately not
displayed. See [Still open](#still-open).

This is also where `/.well-known/assetlinks.json` goes if Android App Links are
ever wired up.

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

`firestore.indexes.json` carries **34 composite indexes and 4 field overrides**.
Deploy them *before* first use: a missing composite index fails a query at
runtime with a console link, which is a poor way for a shop to discover it.

**Eight entries had to be removed before the first deploy would pass.** Each was a
single field plus the automatic `__name__` tiebreak — which is what a single-field
index already is — and Firestore rejects them with

```
HTTP Error: 400, this index is not necessary, configure using single field index controls
```

Six were `COLLECTION`-scoped and simply redundant: Firestore maintains a
single-field index on every field in both directions, and all six already existed
in the project unasked. The other two were `COLLECTION_GROUP`-scoped and still
needed, but only a **field override** can express a collection-group single-field
index — `tenant_memberships.tenantId` (backing the repair sweep in
`functions/src/repair/membershipMirrorStore.ts`) and `stock_movements.tenantId`.
They now sit beside `staff.uid` and `staff_invitations.uid`, which were already
overrides for the same reason.

The error names one collection group per attempt, so this surfaces as a run of
consecutive failed deploys unless all six are fixed at once.

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
cd functions && npm test                     # 438 tests
firebase deploy --only functions --force     # 51 functions
```

**`--force` is not optional.** `consumePendingPlatformAlert` and
`mergeSaleReconciliationJob` declare a retry failure policy, and the CLI refuses:

```
Error: Pass the --force option to deploy functions with a failure policy
```

It aborts before deploying *anything*, so without the flag the run is a no-op that
looks like a crash. Be aware `--force` also suppresses the prompt before deleting
functions no longer present in source — harmless on a first deploy, less so later.

**Enable Identity Platform before deploying, not after.**
`bootstrapSelfSignupIdentity` is registered by patching the Identity Toolkit config,
which fails on a project that has not been upgraded:

```
OPERATION_NOT_ALLOWED : Blocking Functions may only be configured for GCIP projects.
```

The Cloud Function is still *created*, so `firebase functions:list` shows it and it
reads as deployed — while Auth never calls it and every self-signup silently gets no
root document. Enable at `console.cloud.google.com/customer-identity`, then deploy
that one function again. It lands in **`us-east1`**: `firebase-functions` pins
blocking functions there, and nothing in this repo chooses it.

**The first 2nd-gen deploy partially fails, and that is expected.** Eventarc's
service agent is created *during* the deploy and its permissions propagate
afterwards, so event-triggered functions fail with

```
Permission denied while using the Eventarc Service Agent
... Since this is your first time using 2nd gen functions, we need a little bit
longer to finish setting everything up. Retry the deployment in a few minutes.
```

Retry; it succeeds. Nothing needs fixing.

**Three functions always report a failed invoker, and always will.** A
`firebase-tools` bug, present through at least 15.28.2:

```
Unable to set the invoker for the IAM policy on the following functions:
        deliverAccountVerification, deliverPasswordReset, deliverPlatformAlertNotification
```

alongside a bare `Cannot read properties of undefined (reading 'filter')` that
swallows the real error. Those three are exactly the ones declaring
`invoker: "private"`. In `lib/gcp/cloudtasks.js`, `setEnqueuer` calls
`existing.bindings.filter(...)` on the queue's IAM policy — and a queue with no
bindings comes back from the IAM API **without a `bindings` field at all**.

`"private"` resolves to an empty member list, so the policy being written is "no
enqueuer binding" onto a queue that already has none. **It crashes computing a
no-op, and the queues are already in the state the code asks for.** Nothing is
broken. But the condition never clears — an empty policy *is* the correct end state
— so any deploy touching these three exits non-zero forever. Do not read that exit
code as a failed deploy in CI.

## 8. Brevo

1. Create the account and an API key → `BREVO_API_KEY`.
2. Verify the sending domain for `EMAIL_SENDER_ADDRESS` and
   `STAFF_INVITATION_SENDER_EMAIL`.
3. Register the webhook at the deployed `receiveBrevoEmailWebhook` URL, with the
   shared secret as either an `Authorization` header or `x-brevo-webhook-secret`
   → `BREVO_WEBHOOK_SECRET`.

Without step 3 nothing ever records a bounce, so a suppressed address looks
like a delivery that simply never arrived.

**Authenticating the domain takes four DNS records.** Brevo does not ask for SPF —
it authenticates with DKIM CNAMEs instead:

| Type | Name | Purpose |
|---|---|---|
| TXT | `@` | `brevo-code:…` ownership check |
| CNAME | `brevo1._domainkey` | DKIM |
| CNAME | `brevo2._domainkey` | DKIM |
| TXT | `_dmarc` | `v=DMARC1; p=none; …` |

Three further CNAMEs (`noreply`, `r.noreply`, `img.noreply`) are branding only —
they rebrand tracking links and images — and can be skipped.

**If the domain also forwards inbound mail, none of this disturbs it.** Forwarding
depends on the MX records and an existing SPF TXT, and Brevo touches neither. The
one thing that *would* break it is adding a **second** `v=spf1` record: a domain
may have exactly one, and two is a permanent error that takes out sending and
forwarding together. If Brevo ever does ask for SPF, merge the includes into the
existing record rather than adding another.

Adding a `noreply` CNAME does not affect the *address* `noreply@` — mail routes by
the apex MX, not by a `noreply` subdomain.

**Turn click tracking off for transactional email.** Brevo rewrites the links in
what it sends, and every link this app sends is single-use: a Firebase `oobCode` for
verification or reset, or an invitation token. Mail scanners and link-preview bots
follow rewritten URLs and consume the code before the recipient clicks. The symptom
is somebody reporting "invalid or expired link" about a link that has just
arrived.

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

## 10b. Running the whole thing locally, without seeding anything

Verified end to end on 2026-08-30: signup → root document → verified address →
business request → a provisional business writing to its own catalog, with an
empty emulator and no seed script.

```bash
export JAVA_HOME="D:/firebase-emulator-tools/jdk21/jdk-21.0.12+8"
export PATH="/d/firebase-emulator-tools/jdk21/jdk-21.0.12+8/bin:$PATH"
export FUNCTIONS_DISCOVERY_TIMEOUT=120
npx firebase emulators:start --only auth,firestore,functions
```

**Two traps, both of which look like something else.**

1. **`FUNCTIONS_DISCOVERY_TIMEOUT=120` is not optional here.** `functions/lib/index.js`
   takes about 4.4 s just to load on this machine, and discovery also has to spawn the
   process and serialise the backend spec inside its default 10 s. Over that budget the
   emulator prints *"Cannot determine backend specification"* and starts with **zero
   functions loaded** — while still announcing "All emulators ready", so it reads as a
   working suite in which every callable happens to 404.

2. **Secrets must be in `functions/.env.local`, not only `functions/.secret.local`.**
   With a secret missing from `.env.local` the emulator reaches for the *real* Secret
   Manager and fails the entire load with a 403 — including on a `demo-*` project, and
   including when the value is exported in the shell. The error names only the first
   unresolved secret, so it looks like one bad secret rather than a missing convention.
   All six belong in both files; local placeholder values are fine, except
   `EMAIL_RECIPIENT_HMAC_KEYRING`, which is parsed as JSON:
   `{"currentVersion":"v1","keys":{"v1":"<base64>"}}`.

**Verifying the address without a mail provider.** `sendAccountVerification` delivers
through Brevo, which a local run has no working key for — but the Auth emulator still
issues the code. Request it, then follow the link the emulator lists:

```bash
curl "http://127.0.0.1:9099/emulator/v1/projects/<project>/oobCodes"
```

`requestTenant` refuses an unverified applicant, so this step cannot be skipped.

**What no longer needs seeding.** `rules-tests/scripts/seed-dev-emulator.js` exists to
hand a developer "the smallest business that can actually ring up a sale". Since the
provisional window landed, a self-serve signup reaches the same place on its own: the
business trades for a week without anybody approving it. The seed script is still the
faster route to a *stocked* shop, and still the only way to get one without clicking
through signup.

---

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
- **Nothing enforces App Check.** `requestPasswordReset` was the only callable
  that did, and it stopped on 2026-09-24. It is also the only one a stranger
  can call, and it has no per-recipient cooldown, so a script can ask for reset
  mail to a real account over and over. The client still installs a debug-only
  provider (`lib/main.dart`); nothing checks the token it sends.
- **No App Links.** Hosting now exists (see [Hosting](#3b-hosting)), but
  `/.well-known/assetlinks.json` is not published and the app declares no intent
  filter, so no emailed link can open the app.
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
