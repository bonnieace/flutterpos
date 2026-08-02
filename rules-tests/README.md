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

For the focused daily reporting boundary, run
`npm --prefix rules-tests run test:emulator:daily-metrics`. It proves that
owners and managers read the regenerated `daily_metrics` documents, that a day
which has not been reconciled yet still answers instead of being denied - the
normal state for today, which the summary reports as pending - that a cashier
reads no business-wide revenue, that no client may write or delete a metric,
and that a non-member or deactivated identity reads nothing.

`daily_metrics` is regenerated only by the reconciliation workers, so the client
never aggregates a replacement: a device holds only its own sales, and any total
it derived would disagree with the server's for a business using more than one
device.

For the focused returns boundary, run
`npm --prefix rules-tests run test:emulator:tenant-returns`. It proves that any
active member pages the returns recorded against one sale newest-first, that a
colleague's return is readable, that a sale with no returns still answers for
both a direct read and a query, that no client may write the verification
evidence or delete a return, that any active member may record a **pending**
return against any sale in the business, that a replayed deterministic ID is
refused as an update, that the create contract is exactly frozen, and that a
non-member or deactivated identity neither reads nor records anything. The
`return_verifications` ledger stays server-only.

The create rule freezes the key set with `hasOnly`, so no verification field and
no unknown field can be smuggled in beside the request. `itemsReturned` reuses
`validSaleLines`: a return line and a sale line are the same shape by
construction, and a return can never carry more lines than the sale it reverses,
which is capped at the same sixteen. The named sale must exist, because the
verification callable reads the immutable sale to bound the restoration and a
return filed against nothing could never be verified. `createdAt` must be
`request.time`, so a device clock never decides when a reversal was recorded.

Recording and verifying are deliberately separate privileges. Recording changes
no stock; restoration runs through the owner/admin/manager-only
`verifyReturnAndRestoreStock`, so the two steps are a two-person control rather
than one privilege. A customer returns to whoever is at the till, so a cashier
may record a return against a colleague's sale and `createdBy` records who did.

The returns read rule is deliberately as wide as the sale rule rather than as
narrow as the shift rule. `verifyReturnAndRestoreStock` bounds a restoration by
the immutable sale minus every prior verified return, so the quantity a cashier
may still request depends on returns other cashiers recorded. Narrowing this to
`createdBy` would hide exactly that evidence and let one cashier record a return
the server can never verify. The assertions in `a return stays a shared business
record for every active member` pin that decision.

For the focused receipt lookup, run
`npm --prefix rules-tests run test:emulator:receipt-lookup`. It proves that
every active member finds a sale by its receipt - including a colleague's,
because a receipt is looked up by whoever is at the till - that an unissued
receipt answers empty rather than failing, that the same receipt number in
another business is never reached, and that a non-member or deactivated identity
looks nothing up.

That suite also proves the query is servable at all: an equality filter on
`receiptNumber` with the default ascending key order is served by Firestore's
automatic single-field index, so the lookup needs no composite index. If that
ever stops being true the emulator rejects the query here, rather than the
client failing in production - the same class of discovery as the descending
key-scan rejection above.

For the focused per-product stock ledger, run
`npm --prefix rules-tests run test:emulator:stock-movements`. It proves that
owners and managers read and page a product's `stock_movements`, that a product
with no movements still answers for both a direct read and a query, that a
cashier reads the product document but never its ledger, that no client may
append, rewrite, or delete a movement, that another business's ledger is never
reached, and that a deactivated or non-member identity reads nothing.

`stock_movements` was previously denied outright by the tenant catch-all, so
this was a deliberate decision rather than an omission. The read is narrower
than the product document on purpose: the current quantity is operational
information every member needs at the till, while the ledger names damage,
waste, corrections, and who recorded them - management information in exactly
the way `daily_metrics` is. It is also the same set of roles `adjustStock`
enforces, so the surface that explains a stock figure and the surface that
changes it agree. The role check touches no document field, so an absent
movement still answers instead of raising an evaluation error.

Writing stays server-only. Every entry is created by a callable or a
reconciliation worker inside the same transaction that changes the quantity, so
a client that could append here could claim a movement that never happened.

That suite also issues the exact client page - ascending `__name__`, no filter,
one more document than the page size. Movement IDs are digests for adjustments
and `sale_{saleId}` for sales, so document order carries no time information; a
descending page would be neither newest-first nor servable without a composite
index, and the client renders each entry's own recorded instants instead.

For the focused business-wide stock ledger, run
`npm --prefix rules-tests run test:emulator:stock-movement-feed`. It proves that
owners and managers page **every** product's `stock_movements` at once and
narrowed to one `sourceType`, that the page resumes from a whole document path,
that an unfiltered group page is refused outright, that a cashier never reaches
it, that another business's ledger is never returned while that business's own
manager still pages it, that a single movement and an absent one still answer
through the per-product rule, that no client may append, rewrite, or delete a
movement, and that a deactivated or non-member identity pages nothing.

That surface needs a **collection group**, which is a different boundary from
the per-product one and is reasoned about on its own. A rule nested under
`tenants/{tenantId}/products/{productId}` does not apply to a group query at
all, so `match /{ledgerPath=**}/stock_movements/{movementId}` was added beside
it. Three things make it safe:

- It is `list` only. It authorizes a query and never an individual document, so
  the per-product rule stays the one authority on reading a single movement -
  including an absent one, which the group rule's `resource.data` comparison
  could not answer without raising an evaluation error.
- It authorizes by `resource.data.tenantId`, which Firestore can only resolve
  when the query itself carries that exact equality filter. An unfiltered group
  page - which would span every business in the database - is therefore refused
  outright, and the suite proves it. The client attaches the filter from its own
  live session and cannot drop it.
- The roles are the same owner/admin/manager set the per-product ledger and
  `stock_adjustments` use, so all three stock surfaces agree about who may see
  what moved.

Writing stays server-only everywhere, so a movement's `tenantId` is always the
one its own path encodes; the client re-proves that path before showing a row.

A group query is **not** served by the automatic single-field index the way the
key-ordered pages above are, so `firestore.indexes.json` gained two
`COLLECTION_GROUP`-scoped indexes on `stock_movements`: `tenantId`/`__name__`
and `tenantId`/`sourceType`/`__name__`. Both pages are ascending by document
path, which sorts by product first and then by record - arbitrary with respect
to time, which the screen says outright.

For the focused business-wide correction record, run
`npm --prefix rules-tests run test:emulator:stock-adjustments`. It proves that
owners and managers page `stock_adjustments` both business-wide and narrowed to
one product, that an unwritten adjustment, an uncorrected product, and a
business that has never corrected stock all still answer, that a cashier reads
the product document but never the corrections that explain it, that no client
may record, rewrite, or delete an adjustment, that another business's record is
never reached, and that a deactivated or non-member identity reads nothing.

`stock_adjustments` was previously denied outright by the tenant catch-all, so
this was another deliberate decision rather than an omission. The read is
owner/admin/manager: the same set of roles `adjustStock` enforces and the same
set that reads a product's ledger, so the surface that records a correction, the
surface that explains one product's stock figure, and the surface that lists
every correction agree about who may see them. It is deliberately wider than
`audit_logs`, which stays owner/admin: that collection is the whole business's
event trail, while this one is only the stock corrections a manager both records
and answers for. The role check touches no document field, so an absent
adjustment still answers. Writing stays server-only: a client that could create
here could claim a correction that never moved any stock, and one that could
update or delete could erase the only record of one that did.

That suite issues both exact client pages. The business-wide page is ascending
`__name__` with no filter; the narrowed page adds a single `productId ==`
equality on the same order, which Firestore's automatic single-field index
serves, so neither needs a composite index. An adjustment ID is `sa_` plus a
digest of the actor, operation, tenant, and request ID, so document order
carries no time information at all and each record states its own recorded
instant instead.

For the focused business activity log, run
`npm --prefix rules-tests run test:emulator:audit-logs`. It proves that an owner
and an admin page `tenants/{tenantId}/audit_logs` both business-wide and
narrowed to one event type, that an unwritten record, an event a business has
never caused, and a business whose trail has not started all still answer, that
a **manager reads the stock corrections but never the whole trail**, that a
cashier reads nothing from it, that a platform admin reads the trail it is the
actor on while the same identity without the claim does not, that no client -
including a platform admin - may record, rewrite, or delete an event, that
another business's trail is never reached, and that a deactivated or non-member
identity reads nothing.

The `audit_logs` boundary was **kept and proved rather than widened**. The read
stays owner/admin plus platform admin, which is deliberately narrower than the
owner/admin/manager `stock_adjustments` and `daily_metrics` surfaces: a manager
records and answers for stock corrections, while this collection also names who
was invited, deactivated, and recovered, and carries every lifecycle change and
critical administrative alert the platform caused. The platform reads it because
it is the actor on those records. The role check touches no document field, so an
absent record still answers. Writing stays server-only: a client that could
create here could fabricate evidence of an event that never happened, and one
that could update or delete could erase the only record of one that did.

That suite issues both exact client pages. The business-wide page is ascending
`__name__` with no filter; the narrowed page adds a single `eventType ==`
equality on the same order, which Firestore's automatic single-field index
serves, so neither needs a composite index. An audit ID is the operation,
request, or delivery ID the event belongs to - a digest for most writers and the
tenant ID itself for `tenant_requested` - so document order carries no time
information and each record states its own recorded instant instead.

For the focused reconciliation status surface, run
`npm --prefix rules-tests run test:emulator:reconciliation-status`. It proves
that a manager and an owner read one business day's
`tenants/{tenantId}/reconciliation_dirty_days/{businessDate}` record and page
the `tenants/{tenantId}/reconciliation_jobs` runs queued for that exact day,
that the page resumes from a bare document ID, that a business day the server
has never seen still answers as an absent record and an empty page, that a
cashier reads neither, that no client may write or delete either, that another
business's reconciliation state is never reached while that business's own
manager still reads its own, and that a deactivated or non-member identity reads
nothing.

Both reads are owner/admin/manager: the same set that reads `daily_metrics`,
because this is the explanation of business-wide revenue, so whoever may not see
the figure may not see why it is what it is either. It is deliberately wider
than `audit_logs`, which stays owner/admin - this is reporting rather than
governance. Neither role check touches a document field, so a business date with
no sales still answers, which is the whole point: the absence *is* the answer.
Writing stays server-only in both. A client that could write here could mark a
day clean so its sales were never aggregated, or clear the failure record of a
run that never succeeded; reconciliation is requested through the callable,
which enforces its own roles and idempotency.

That suite issues the exact client page: one `localDate ==` equality on
ascending `__name__`, which Firestore's automatic single-field index serves, so
no composite index is involved. The intake record is read by exact document path
rather than by query, because its ID **is** the business date and a query cannot
return a day that has no record. A run ID is `rj_` plus a digest for a scheduled
or manual run and `dirty_{bucket}` for a sale trigger, so document order carries
no time information and each run states its own instants instead.

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

## Running the Flutter app against local emulators

The suites above serve tests only. To drive the real app locally, start the
emulators declared in `firebase.json` - a different config from the two test
ones on purpose, so a local run and the test harness cannot break each other:

```powershell
npm --prefix rules-tests run emulators:dev
```

That builds Functions, writes local-only `functions/.secret.local` and
`functions/.env.local` values, starts Auth, Firestore, and Functions, seeds one
complete business, prints the sign-in details, and holds until Ctrl+C. Both
local files are removed on exit and neither is ever committed. The command
refuses to start if either already exists, so a real local configuration is
never overwritten.

Every `defineSecret`/`defineString` parameter without a default is supplied
there. Without them the emulator stops at startup to ask for values and, with no
terminal to answer, the run appears to hang after `Serving at port ...`.

Then run the app with the switch:

```powershell
flutter run --dart-define=USE_FIREBASE_EMULATORS=true
```

The host is derived: `10.0.2.2` for a native Android target, `127.0.0.1` for
everything else. A physical handset needs the machine's LAN address instead:

```powershell
flutter run --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=FIREBASE_EMULATOR_HOST=192.168.1.24
```

The switch is refused outside a debug build - it throws at startup rather than
silently falling back to the real project. See `lib/dev/firebase_emulators.dart`.

`scripts/seed-dev-emulator.js` refuses to run unless `FIRESTORE_EMULATOR_HOST`
and `FIREBASE_AUTH_EMULATOR_HOST` are already set, which is what makes
`firebase-admin` itself incapable of reaching a real project. Re-running it is
safe: it overwrites the same fixed document IDs and repairs the owner account.

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
