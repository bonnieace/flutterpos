# Printer transport

How the multitenant checkout slice will print. The transport *shape* is borrowed
from [`bonnieace/printer_network`](https://github.com/bonnieace/printer_network);
everything behind the seam is written to this codebase's standards.

Nothing here is built yet. This document is the design we build against.

## Why borrow at all

That repo is a three-mode ESC/POS demo app (native TCP, Chrome IWA Direct
Sockets, Node HTTP bridge). It got one thing genuinely right — a single narrow
seam with per-platform implementations selected at compile time — and got most
of the durability, tenancy, and security work wrong. We take the seam and reject
the rest.

We do **not** vendor the repo, add it as a dependency, or copy its bridge. It is
an application, not a package: its own `main.dart`, onboarding screen, platform
scaffolding, and `com.example.printer` identifiers.

## Scope

In scope: getting a finished byte payload to a printer, reliably, once, on every
platform we ship, with the failure surfaced honestly.

Out of scope: building the bytes. `flutter_esc_pos_utils`' `Generator` +
`CapabilityProfile` already does that and already emits code-page selection —
which is precisely what `printer_network`'s hand-rolled `ReceiptBuilder` gets
wrong (it Latin-1 encodes bytes `0x80`–`0xFF` and never emits `ESC t`, so every
non-ASCII character prints as the printer's default code page instead). The
generator keeps its job. The transport only moves bytes.

## Phasing

**Phase 1 — mobile and desktop.** One `dart:io` transport covering Android, iOS,
Windows, macOS, and Linux, plus the durable job queue, tenant configuration, and
failure vocabulary. This is the whole of the work that matters.

**Phase 2 — web, later.** The Flask endpoint in §5. Deferred, and documented now
only so the seam is shaped to accept it without touching a call site.

The sections below mark anything that is Phase 2. Everything unmarked is Phase 1.
The practical consequence: on a web build the factory resolves to the unsupported
stub and printing throws `transport_unsupported`, which is the correct deferred
behaviour — honest and loud, not a silently dropped receipt.

---

## 1. What we take, and why each earns its place

### 1.1 One seam, compile-time platform selection

The whole idea. A single interface, one implementation per platform family, and
a conditional-import shim that resolves it:

```dart
// checkout_print_transport.dart
import 'checkout_print_transport_base.dart';
import 'checkout_print_transport_unsupported.dart'
    if (dart.library.io) 'checkout_print_transport_io.dart'
    if (dart.library.js_interop) 'checkout_print_transport_web.dart'
        as implementation;

export 'checkout_print_transport_base.dart';

PrinterTransport createPrinterTransport() =>
    implementation.createPrinterTransport();
```

Why this over `if (kIsWeb)` branching: `dart:io` and the web transport are never
both compiled into a binary, so neither platform pays for the other and neither
can accidentally reference the other's types. The unsupported stub throws rather
than silently no-oping, so a new platform target fails loudly at first print
instead of quietly dropping receipts.

**Phase 1 writes three of these four files** — the shim, `_base`, `_io`, and
`_unsupported`. `_web` does not exist yet, so the `dart.library.js_interop`
branch resolves to the stub. Keeping the shim now rather than importing
`dart:io` directly is the entire reason Phase 2 is a new file instead of a
refactor of every call site, and it costs about forty lines. Note the legacy
[thermal_printer_service.dart](../lib/services/thermal_printer_service.dart)
imports `dart:io` unconditionally, so an unguarded `dart:io` import is already
the status quo we are improving on.

### 1.2 The transport never touches UI, and never owns state

In `printer_network` the transport returns a `PrinterTransportResult`
value — no snackbars, no `BuildContext`. That is the right instinct and it is the
opposite of what the legacy code here does, where the HTTP call, the retry
decision, and `ScaffoldMessenger.of(context).showSnackBar` are interleaved in one
method inside a 3,000-line widget ([pos.dart:849-920](../lib/pos/pos.dart#L849-L920)).

We keep the separation and change the mechanism: failures are thrown as
`PrinterTransportException(code)`, matching `CheckoutOutboxException` and
`TenantAuditLogException`. Codes are enumerable, so they can be stored as an
outbox `attentionReason`, asserted in tests, and mapped to operator-facing text
at the UI edge — none of which works with the repo's free-text
`'Could not reach $host:$port. $detail'`.

### 1.3 Probe as a first-class operation

`testConnection` separate from `printBytes`. Onboarding needs "is this printer
reachable?" without wasting paper, and the answer is diagnostic gold when a shop
phones in. Keep it.

### 1.4 A connection per job, never pooled

Both of the repo's real transports open a socket, write, close. Correct for
ESC/POS: printers drop idle connections without notice, and a pooled socket that
looks alive but isn't turns into a silently lost receipt. Keep it.

### 1.5 Distinct connect and write timeouts, on every operation

The repo separates connect (5 s) from write (8 s). Worth keeping as a shape: a
printer that never answers TCP is a different fault from one that accepts the
connection and then stalls on a paper jam, and the operator guidance differs.

### 1.6 Capability introspection for the UI

The repo exposes `modeLabel` and `usesBridge` so the setup screen can explain
which path is active. Operators debugging "it doesn't print" need to know whether
the tablet is talking to the printer or to a bridge. Keep it as a typed
`PrinterTransportCapability`, not two loose booleans.

---

## 2. What we deliberately do not take

Each of these was reproduced against the repo at commit `95b07d4`.

| Their behaviour | Why it fails our bar |
|---|---|
| Config load does `catch (_)` then falls back to built-in defaults | Fails **open**. A corrupt record silently redirects printing to `192.168.100.100`, which on a customer LAN is someone else's device. Our durable state fails closed — see `malformed_receipt_counter` in [checkout_receipt.dart](../lib/checkout/checkout_receipt.dart) |
| One global `SharedPreferences` key, `network_printer_config_v1` | No tenant scoping. Switching tenants would inherit the previous tenant's printer |
| Bridge token in plaintext `SharedPreferences` (localStorage on web) | Readable by any script on the origin serving the app |
| No serialization of print jobs anywhere | Most ESC/POS printers accept one connection on `:9100`. Concurrent jobs interleave or get refused |
| `printReceipt` exposes `isBusy` but never checks it | Two concurrent calls race on shared status and open two sockets |
| Transport bundled into a `ChangeNotifier` with mutable status | Mixes state machine, presentation state, and transport in one class |
| `on TimeoutException` around `Socket.connect(timeout:)` | Dead branch — verified: `Socket.connect` throws `SocketException` (errno 10060) on timeout, so the more helpful message never renders |
| Node bridge: `token: ""`, `allowedOrigin: "*"`, `lockPrinter: false`, client-supplied printer host | Verified as an unauthenticated TCP proxy and port scanner onto the LAN, plus a path traversal escaping the web root. We are not deploying it |
| `filePath.startsWith(webRoot)` as a containment check | Verified traversal to sibling directories. Use `path.relative` if we ever write a static server |
| IWA / Direct Sockets mode | Verified non-functional as scripted (CanvasKit loads from `gstatic` by default, blocked by the IWA CSP `script-src 'self'`), and Chrome still gates distribution. Not worth the surface |

---

## 3. The interface

House conventions: `final class`, `abstract interface class` for seams, injected
`typedef` clocks, exceptions carrying a stable string code, immutable value
objects, `schemaVersion` on everything durable.

```dart
/// A printer address. Immutable, validated at construction; there is no way to
/// hold an instance describing an address we would refuse to dial.
final class PrinterEndpoint {
  factory PrinterEndpoint({required String host, required int port}) { ... }

  final String host;
  final int port;
}

enum PrinterTransportKind {
  directTcp,   // dart:io Socket — Android, iOS, Windows, macOS, Linux
  httpBridge,  // Flask endpoint — web
}

final class PrinterTransportCapability {
  final PrinterTransportKind kind;

  /// True when the endpoint the operator configures is the printer itself,
  /// false when it is a bridge that decides the printer server-side.
  final bool endpointIsPrinter;

  /// Operator-facing mode name, e.g. 'Direct network printing'.
  final String label;
}

/// Raised for every transport failure. The code is stable and enumerable so it
/// can be persisted as an outbox attention reason and asserted in tests.
final class PrinterTransportException implements Exception {
  const PrinterTransportException(this.code);
  final String code;
}

/// Moves bytes to a printer. Never touches UI, never holds mutable state, and
/// never decides whether to retry — that belongs to the job queue.
abstract interface class PrinterTransport {
  PrinterTransportCapability get capability;

  /// Confirms reachability without printing. Throws on failure.
  Future<void> probe(PrinterEndpoint endpoint);

  /// Sends one complete payload. Throws on failure. Returning normally means
  /// the transport handed every byte off; it does not prove paper moved.
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes);

  Future<void> dispose();
}
```

`send` returning normally means *delivered*, not *printed*. No ESC/POS network
transport can prove the latter without reading printer status back, which we are
not doing in v1. Every operator-facing string must be honest about that
distinction — "Receipt sent to the printer", never "Receipt printed".

## 4. Platform matrix

| Target | Implementation | Notes |
|---|---|---|
| Android, iOS | `dart:io` `Socket.connect` | Android needs `INTERNET`; iOS needs `NSLocalNetworkUsageDescription` and will show the local-network prompt on first connect |
| Windows, macOS, Linux | same `dart:io` path | macOS `Release.entitlements` needs `com.apple.security.network.client`. Already present in this repo |
| Web | *Phase 2* — Flask endpoint (§5). Stub until then | Browsers cannot open raw TCP. Non-negotiable when it lands |

One `dart:io` implementation covers all five Phase 1 targets, which is why
deferring web costs so little: the transport is roughly forty lines plus the job
queue behind it.

## 5. Web transport (Phase 2): the existing Flask endpoint

Deferred. Recorded now so the seam is shaped correctly and so the contract is
captured while it is fresh — the legacy call sites that document it are on the
list to delete.

When web arrives we use the Flask print endpoint this codebase already talks to,
**not** the repo's Node bridge. The contract below is the one the legacy call sites use
([pos.dart:849](../lib/pos/pos.dart#L849),
[Receipt_service.dart:164](../lib/services/Receipt_service.dart#L164)) and it is
already deployed:

```
POST http://<bridge-host>:5000/print
Content-Type: application/json

[27,64,27,97,1, ...]          # JSON array of byte values

200 {"success": true}
200 {"success": false, "error": "..."}
```

Anything other than `200` with `success == true` is a failure. Timeout 10 s.

Notes carried into the implementation:

- **Its shape is safer than the Node bridge's.** The printer address lives
  server-side; the client sends only bytes. That removes the SSRF and port-scan
  surface entirely — the class of hole the Node bridge has. This is why
  `PrinterTransportCapability.endpointIsPrinter` is `false` here: on web the
  operator configures a *bridge*, and the printer field must be hidden rather
  than shown and ignored.
- **It still needs authentication.** Anything on the LAN can currently POST to
  it and print. Adding a shared token and an `Origin` check is server work
  outside this document, but the transport must be built to carry a token header
  from day one so enabling it is a config change, not a code change.
- **The wire format is ~4× larger than it needs to be.** `[27,64,...]` costs
  about four characters per byte where base64 costs 1.33. A 20 KB receipt with a
  logo becomes ~80 KB of JSON. We keep the existing contract because it is
  deployed and changing it means changing the server; if the endpoint ever gains
  a base64 field, switch.
- **Bridge URL default.** When the web app is served from the same host as the
  bridge, resolve against the page origin so the deployment needs no
  configuration. Note the repo's version resolves against `Uri.base` root, which
  breaks under a non-root `--base-href`; resolve against the base href instead.

## 6. Configuration

Printer configuration is tenant-owned operational data, so it follows
[checkout_configuration.dart](../lib/checkout/checkout_configuration.dart)
exactly rather than inventing a second pattern:

- Canonical document at `tenants/{tenantId}/configuration/printer`, read through
  `TenantReadRepository` — never a raw Firestore read from a composition root.
- A strict `fromMap` that throws `FormatException` on anything malformed.
  Unknown fields ignored so later settings do not break this slice; every field
  we depend on exactly valid.
- Mirrored into the encrypted offline cache as a minimal projection, the way
  `TenantCheckoutConfiguration.toCacheEntry` does.
- **Missing or malformed fails closed.** No default printer address, ever. A
  checkout completes and the receipt stays queued with a clear reason; it does
  not get dialed at a guessed IP.

Fields: transport kind, host, port, optional bridge token, paper width, whether
the printer has a cutter.

## 7. Print jobs: durable, serialized, idempotent

This is the part `printer_network` has no concept of — it prints
fire-and-forget and returns a `bool`. Checkout already survives being offline and
crashing ([checkout_outbox.dart](../lib/checkout/checkout_outbox.dart),
[checkout_recovery.dart](../lib/checkout/checkout_recovery.dart)); printing has
to survive the same things.

**Storage.** An encrypted Hive box `checkout-print-jobs-v1`, sharing the checkout
outbox encryption key. Same reasoning as
[checkout_receipt.dart](../lib/checkout/checkout_receipt.dart): a queued receipt
holds the same sale detail as the evidence it was printed from, so the two must
share exactly one fate. A key rotation must never leave readable receipt bytes
beside a wiped outbox.

**Identity.** The job key is the receipt number already allocated by
`HiveCheckoutReceiptCounters` — `CT-A7F-20260729-0042`. It is unique per device
per business date by construction, which makes it a free idempotency key: a crash
mid-print recovers into the *same* job, not a second one.

**States.** `queued → printing → printed`, with `needsAttention` as the terminal
failure, mirroring `CheckoutOutboxState`. Illegal moves throw
`invalid_transition`. Malformed durable records throw `malformed_print_job`
rather than being repaired by guessing.

**Serialization.** One printer accepts one connection, so jobs run through a
per-endpoint `_serialized` mutex — the same `_operationTails` pattern used in the
outbox and the receipt counters. Never two concurrent sends to one address.

**Reprints are explicit and audited.** Reaching `printed` means the queue never
re-sends on its own; a duplicate receipt is a cash-handling problem, not a
convenience. An operator reprint is a separate deliberate action that writes a
`TenantAuditEventType` — `receipt_reprinted` — alongside the existing
`stock_adjusted` and `return_verified_stock_restored` events.

**Retries.** Attempt count and `retryAt` on the record, backoff owned by the
queue, never by the transport. The transport's only job is to throw a code.

## 8. Failure codes

Stable, enumerable, and the only vocabulary the UI maps to text:

| Code | Meaning | What the operator is told |
|---|---|---|
| `printer_unreachable` | TCP connect refused or unroutable | Check the printer is on and on this network |
| `printer_connect_timeout` | Connect timed out | Check the printer IP and the Wi-Fi network |
| `printer_write_timeout` | Connected, then stalled mid-payload | Check for a paper jam or open cover |
| `printer_not_configured` | No valid tenant printer configuration | Finish printer setup |
| `transport_unsupported` | Platform has no transport — a web build, in Phase 1 | Printing is not available in the browser yet |
| `bridge_unreachable` | *Phase 2.* The Flask host did not answer | Check the print bridge computer is running |
| `bridge_rejected` | *Phase 2.* `success: false`, or a non-200 | Surface the server's reason verbatim |
| `bridge_unauthorized` | *Phase 2.* Token missing or wrong | Re-enter the print token |

Mapping happens at the UI edge. The transport never builds a sentence.

## 9. Tests

Matching the existing bar — [test/checkout/](../test/checkout/) has 17 files, one
per source file. Non-negotiable coverage:

- `PrinterEndpoint` validation, including hosts we must refuse.
- Every failure code, produced by a fake transport, asserted by code not message.
- The `dart:io` transport against a real `ServerSocket` in-test: accepts and
  verifies bytes; accepts then stalls (write timeout); refuses (unreachable).
- The unsupported stub throws `transport_unsupported` rather than no-oping.
- Job state machine: every legal transition, and every illegal one throwing.
- Idempotence: two `send` calls for one receipt number produce one delivery.
- Serialization: two concurrent jobs to one endpoint never overlap.
- Fail-closed: a malformed durable record throws rather than resetting, and
  absent configuration refuses rather than defaulting.
- Recovery: a job interrupted in `printing` resumes as the same job.

Phase 2 adds the web transport against a stubbed `http.Client`: the exact
JSON-array body, the token header, `success: false`, a non-200, and a timeout.

Nothing merges with a red suite. For the record, the source repo's own committed
widget test fails on a clean checkout — its notes state the Flutter SDK was never
available to run it.

## 10. Open decisions

Settled: web is Phase 2, so Phase 1 is mobile and desktop on one `dart:io`
transport.

1. **One printer per device, or several?** This design assumes one configured
   printer per device. Kitchen-plus-counter routing would make the endpoint a
   per-job property rather than tenant configuration, and it is far cheaper to
   decide now than to retrofit — it changes the shape of the job record, not just
   the transport. The most consequential question left.
2. **Printer status readback.** Out of scope for Phase 1, which is why we say
   "sent" and not "printed". Worth revisiting if shops report silent paper-out
   losses.
3. **When do the legacy print paths get deleted?** `pos/pos.dart`,
   `Receipt_service.dart`, and `thermal_printer_service.dart` all still carry
   printing code — the last of those is already unreachable. They are the only
   remaining record of the Flask contract in §5, so Phase 1 should land before
   they go, not after.
4. **Who authenticates the Flask endpoint, and when?** Phase 2's question, but
   worth raising early since it is server work with its own lead time. The
   transport carries a token header regardless.
