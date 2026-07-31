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

For the focused checkout submission batch, run
`npm --prefix rules-tests run test:emulator:checkout-submission`. It commits the
exact atomic write set produced by the sync worker and proves deterministic sale
identity, server-owned `createdAt`, exact tenant stock decrements into negative
stock, replay denial, cross-tenant denial, non-decrementing stock denial,
envelope spoofing denial, and inactive-cashier denial.

For the focused per-device receipt contract, run
`npm --prefix rules-tests run test:emulator:checkout-receipt`. It proves that
two cashiers sharing one device commit different receipt numbers while the sale
records each cashier UID separately, that sequences stay independent across
devices and business dates, and that a receipt disagreeing with its own sale
envelope, a malformed or missing receipt, a replayed receipt, and an inactive
cashier are all denied.

For the focused shift lifecycle, run
`npm --prefix rules-tests run test:emulator:shift-lifecycle`. It proves that a
cashier opens and closes exactly one server-timed shift, that the document must
repeat its own shift, tenant, device, and business-date identity, that a client
can neither choose the start instant nor pre-close a shift, that only the
shift's own cashier may close it once, that a closed shift is terminal and
undeletable, and that closing may not rewrite the envelope, skip the counted
cash, omit or contradict the sale-derived closing summary, or smuggle extra
fields.

For the focused shift-bound sale contract, run
`npm --prefix rules-tests run test:emulator:shift-sale-attribution`. It proves
that a sale bound to the cashier's own canonical shift commits, that a missing,
empty, non-string, or unknown `shiftId` is denied, that a colleague's shift
cannot be borrowed, that a sale must share its shift's device and business day,
that a closed shift still accepts a late offline sale, and that the largest
allowed sale still evaluates within the Rules budget.

For the focused shift-history read boundary, run
`npm --prefix rules-tests run test:emulator:shift-history`. It proves that a
cashier may page only its own closed shifts, that dropping the `staffId`
constraint or naming a colleague is denied for both a query and a direct read,
that owners, admins, and managers page every cashier's closed shifts, that a
deactivated or non-member identity reads nothing, and that history remains
read-only for every role.

The shift read rule was deliberately narrowed in that chunk: an active cashier
used to read every shift in the business. A cashier had no reason to read a
colleague's counted cash, the client already refused a foreign shift, and a
cashier's list query must therefore carry `staffId == uid`, which is exactly
what the history and open-shift-discovery repositories send.

For the focused sale-history read boundary, run
`npm --prefix rules-tests run test:emulator:sale-history`. It proves that a
cashier pages the sales of one shift and its own sales across shifts, that a
sale stays readable business-wide for every active member, that an absent sale
still answers, that a non-member or deactivated identity reads nothing, and that
a recorded sale is immutable for every role.

The sale read rule was deliberately left wider than the shift rule. A sale is
the business's shared record of a transaction - a receipt lookup, a return
against a colleague's sale, and the fail-closed confirmation of a deterministic
sale path all need it - while a shift is one cashier's own cash record.
Narrowing sales to `soldById` would also turn an unreadable foreign sale into an
endless submission retry instead of a reported mismatch. The three assertions in
`a sale stays a shared business record for every active member` pin that
decision, so a future narrowing has to change them on purpose.

Firestore refuses `orderBy(documentId(), "desc")` over a whole collection
("Firestore does not support descending key scans"), so every newest-first page
carries at least one equality filter. `TenantReadRepository` refuses to build an
unfiltered descending page at all, which turns that runtime query failure into
an immediate programming error.

For the focused canonical staff read boundary, run
`npm --prefix rules-tests run test:emulator:staff-directory-read`. It proves
that a cashier reads only its own staff record and cannot list the roster, that
owners, admins, and managers read every record, that an absent record still
answers, and that a deactivated or non-member identity reads nothing - not even
its own record, because canonical access ends with the membership.

That rule was narrowed deliberately: a canonical staff record carries the
member's email and phone number, and the staff directory screen is already
owner/admin/manager-only. History surfaces therefore resolve a colleague's name
for management and fall back to the UID for a cashier, which the client's name
resolver does on its own. The identity compared in the rule is the path
wildcard, not a document field, so an absent record still answers instead of
raising an evaluation error.

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

Receipt validation is subject to the same limit. Firestore evaluates at most
1000 expressions per request, and a sixteen-line sale batch already spends most
of that budget, so the receipt rule proves the shape, the embedded business
date, and the embedded sequence with one constructed pattern instead of several
comparisons. Adding the earlier multi-comparison version denied a legitimate
sixteen-line sale outright, which the maximum-size test in
`checkout-receipt.test.js` now guards against.

Rules cannot recompute the SHA-256 device code and cannot query other sales, so
global receipt uniqueness is not a server-enforced invariant. Uniqueness comes
from the device-local atomic counter; reconciliation is the place to detect a
duplicate that local tampering or a restored backup could still produce.

Binding every sale to its shift costs another document lookup, so the sale rule
reads the shift once into a `let` binding and reclaims budget elsewhere: the
receipt no longer type-checks `businessDate` and `deviceId` separately, and a
sale line no longer carries an explicit `is map` check. Both cases still deny,
because a value that cannot be split, compared to the shift's validated string,
or asked for a field produces an evaluation error. Repeating the shift lookup
per field denied a legitimate sixteen-line sale, which the maximum-size test in
`shift-sale-attribution.test.js` now guards against as well.
