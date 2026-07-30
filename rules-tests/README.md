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

## Routing, invitation, and lifecycle callable integration tests

The invitation integration harness starts Auth, Firestore, and Functions under
the explicit `demo-multitenant-invitation-integration` project. It seeds Auth
and canonical Firestore state through the Admin SDK, signs in through the Auth
emulator, calls the real compiled callable endpoints, and verifies both the
response contracts and committed membership, routing-profile, or lifecycle
state. Lifecycle coverage includes pending approval/rejection, active
suspension, suspended reactivation, and rejected archival.

Use Node.js 24 and JDK 21 or newer, then run from the repository root:

```powershell
npm --prefix functions ci
npm --prefix rules-tests ci
npm --prefix rules-tests run test:emulator:invitations
```

The runner uses `firebase.invitation-test.json`, copies the current compiled
Functions output into an ignored fixture, and exports only the two real
invitation handlers plus `setDefaultTenant`, `requestTenant`, and
`setTenantLifecycle`. It supplies a deterministic local-only HMAC secret in a
temporary ignored file, removes it after the emulator exits, and refuses to
overwrite existing local configuration. It also refuses non-`demo-*` projects
or missing localhost emulator hosts. It does not read `.firebaserc` and cannot
target the configured development, staging, or production projects.

## Rules-language boundary

Firestore Rules do not provide a general loop or `every` operation for lists.
Sale-line validation is therefore capped at 16 items and explicitly checks all
16 positions to stay within Firestore's expression limit. Rules can enforce
that an immutable sale document ID equals its `checkoutId`, but cannot prove
how a client generated that ID or recompute its payload hash; the checkout
coordinator owns those deterministic algorithms.
