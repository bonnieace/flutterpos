# Firestore rules tests

This package runs only against the Firestore emulator. The harness requires
`FIRESTORE_EMULATOR_HOST` and hard-codes the `demo-multitenant-rules` project so
it cannot fall back to a real Firebase project.

Prerequisites: Node.js 20 or newer and JDK 21 or newer.

From the repository root:

```powershell
npm --prefix rules-tests install
npm --prefix rules-tests run test:emulator
```

`firebase emulators:exec` supplies `FIRESTORE_EMULATOR_HOST` to the test
process. To run against an emulator that is already listening on port 8180:

```powershell
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8180'
npm --prefix rules-tests test
```

For the focused checkout-confirmation read contract, run
`npm --prefix rules-tests run test:emulator:checkout-confirmation`. It starts
Firestore alone and proves exact deterministic-sale reads, missing documents,
malformed evidence, tenant isolation, and global-disable denial.

## Routing, invitation, and lifecycle callable integration tests

The invitation integration harness starts Auth, Firestore, and Functions under
the explicit `demo-multitenant-invitation-integration` project. It seeds Auth
and canonical Firestore state through the Admin SDK, signs in through the Auth
emulator, calls the real compiled callable endpoints, and verifies both the
response contracts and committed membership, routing-profile, or lifecycle
state. Lifecycle coverage includes pending approval/rejection, active
suspension, suspended reactivation, and rejected archival.
Global-user coverage includes claim-and-root-gated exact-UID review plus the
real disable/reactivate saga across Auth, root state, operation, alert, and
audit records.
The same local-only harness invokes the compiled `grant-platform-admin` CLI in
subprocesses and proves eligible completion, canonical-membership rejection,
resumable transition completion, custom claims, roots, and audit evidence.
It also exercises the compiled `revoke-platform-admin` CLI and private saga,
including last-admin denial, root/claim disagreement, canonical tenant
evidence, idempotent success, refresh-token cutoff, and recovery after an
ambiguous successful claim removal.

Use Node.js 24 and JDK 21 or newer, then run from the repository root:

```powershell
npm --prefix functions ci
npm --prefix rules-tests ci
npm --prefix rules-tests run test:emulator:invitations
```

The runner uses `firebase.invitation-test.json`, copies the current compiled
Functions output into an ignored fixture, and exports only the two real
invitation handlers plus `setDefaultTenant`, `requestTenant`, and
`setTenantLifecycle`, `getGlobalUserStatusReview`, and `setGlobalUserStatus`.
It supplies a deterministic local-only HMAC secret in a temporary ignored
file, removes it after the emulator exits, and refuses to overwrite existing
local configuration. It also refuses non-`demo-*` projects or missing
localhost emulator hosts. It does not read `.firebaserc` and cannot target the
configured development, staging, or production projects.

The runner defaults Firebase Functions HTTP discovery to 60 seconds because
the CLI's 10-second default is unreliable on constrained Windows hosts. Set
`FUNCTIONS_DISCOVERY_TIMEOUT` explicitly to override that bounded default.

For focused diagnosis, set `INTEGRATION_TEST_NAME_PATTERN` to a Node test-name
pattern before launching the runner. On memory-constrained Windows hosts, set
`NODE_OPTIONS=--max-old-space-size=512` for the Functions emulator workers.

## Rules-language boundary

Firestore Rules do not provide a general loop or `every` operation for lists.
Sale-line validation is therefore capped at 16 items and explicitly checks all
16 positions to stay within Firestore's expression limit. Rules can enforce
that an immutable sale document ID equals its `checkoutId`, but cannot prove
how a client generated that ID or recompute its payload hash; the checkout
coordinator owns those deterministic algorithms.
