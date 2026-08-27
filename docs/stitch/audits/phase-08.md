> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 08 audit - supported settings and printing

Date: 2026-08-21

Project: `7478406619239162026`

Operation: authorized `REPLACE`, followed by bounded device-specific `CORRECT` passes

Design system: Profound Verdant `assets/4c1cc58b4aed4b1693e6f8113ba1009a`, retained and not mutated

## Scope and product evidence

Phase 08 used screenshot groups 16, 36, and 37; the active checkout/printer configuration models and
panels; the durable print-job queue; printer failure vocabulary; receipt byte generator; and route
authorization. Owner/Administrator alone may open checkout and printer configuration. Every active
tenant role may open the device-local Receipts waiting queue.

The supported fields are exactly one ISO 4217 checkout currency plus direct-TCP printer address,
port, 32/48-column paper width, and cutter behavior. Printer test probes the typed endpoint without
printing. Receipt sending happens after sale durability, and transport success proves byte delivery
only, not that paper came out. A failed print never relabels or rolls back the sale.

Excluded concepts were VAT/tax, prices-include-tax, profile/registration/location/contact/support,
editable branding, language, sync interval, exchange-rate/rounding/payment settings, transport
selection, bridge token, receipt preview, and queue delete/edit/clear/dismiss/mark-printed actions.

## Initial replacement

The authorized replacement produced:

- ST-057 `297e9e7c97e5453f9ae269552f924c7f` - desktop, 2560x2048.
- ST-058 `218035ab052244c9b9c21aef8b87bf23` - mobile, 780x3158.

Fresh downloadable artifacts rejected both. ST-057 ended after four currency specimens and contained
none of the promised printer, queue, tablet, or interaction sections. ST-058 contained only basic
currency/printer/queue openings and used the unrelated `Staff Portal` heading.

## Bounded correction

A combined mixed-device correction was rejected as invalid before mutation. The same bounded work
was then issued by device and returned derived successors:

- ST-059 `0560439c79ce4be4b095a523c218261d` - desktop, 2560x5012.
- ST-060 `b38ea012bde44303a926c5c9ea54937d` - mobile, 780x12908.

Both returned artifacts were downloaded and inspected as HTML and full-height screenshots.

## Verified result

ST-059 visibly contains published/focused/malformed/invalid/absent/change/busy/committed currency
specimens, exact direct-TCP printer fields and physical width/cutter consequences, the populated
device-local queue, both receipt IDs/endpoints/tries/actions, and the exact unreadable-record callout.
It does not visibly contain most printer test/write/read outcomes, the queue empty/read-only/non-
retryable/busy/success/failure matrix, an 834px tablet transformation, or the interaction ledger.

ST-060 visibly contains published/absent/malformed/form/change/busy/committed/offline/ambiguous/read-
failure currency specimens; absent/configured/form/malformed/loading/busy/saved/test-success/test-
unreachable printer specimens; and device-local empty/populated/unreadable/sending/success/not-
configured/browser-unsupported queue specimens. It removes `Staff Portal` and uses only the supported
field set. Remaining defects are bounded: endpoint-change consequences and several printer write
outcomes are absent, the second waiting receipt omits its endpoint, and explicit read-only plus retry-
failure queue specimens are missing. The interaction ledger is incomplete.

The visible artifacts contain no unsupported settings, receipt preview, queue mutation control,
Manager/Cashier configuration form, generic settings navigation, or false claim that paper printed.
The screenshots establish composition and visible copy only; they do not prove keyboard focus,
physical target size, socket reachability, cutting, paper width, or physical printer behavior.

## Reopened correction

After the user explicitly requested correction, device-specific completion work produced:

- ST-061 `1701f2f2ad1546cd977e3d2cfd25cc16` - desktop, 2560x24000.
- ST-062 `9fb29b6ac7ba48489b9a5fb575a48f5f` - mobile, 780x12950.

Initial artifact review rejected the generation summaries: ST-061 still ended after the original
queue content and ST-062 retained bounded printer, queue, and interaction gaps. Exact-source edits
then returned concrete DOM operations rather than new screen IDs:

- Desktop printer outcomes: event `a1743554`.
- Mobile printer outcomes: event `585462bb`.
- Desktop queue recovery, 834px tablet, and ledger: event `3bc2e9ce`.
- Mobile full queue recovery and ledger: events `084cca77` and `cfa0d74a`.
- Desktop explicit 48px ledger: event `c0fa348b`.
- Mobile endpoint and disabled-loading micro-correction: event `8acd1124`.

The operation payloads cover the supported printer read/write/test states; device-local empty,
populated, unreadable, sending, success, setup, browser, read-only, and retry-failure queue states;
the desktop tablet specimen; and explicit currency/toggle/action ledgers. They also preserve the
truth that endpoint delivery is not proof of paper output and print failure leaves the completed sale
unchanged.

Individual `get_screen` retrieval still returns the pre-operation ST-061 file
`b7870f64505147cbbe83796140ebecab` and ST-062 file `74ac285281d54f449a6e25d113d5859d`.
The corrected pair is therefore mutation-reviewed, not visually approved.

## Rejected fresh fallback generations

Fresh generations were attempted to obtain immediately reviewable artifacts:

- ST-063 `d8c41fb7d7f6469191b21b281062e3b0` - mobile, 780x3020.
- ST-064 `52a6154f4d8e43d496a142cee1393ad8` - desktop, 2560x2048.

Their returned HTML and screenshots were downloaded and inspected. ST-063 ends during Printer
configuration and omits Receipts waiting and the interaction ledger. ST-064 renders only one currency
form, one printer form, and one populated queue row. Neither is a working successor or canonical
candidate. ST-063 was not yet individually retrievable; ST-064 was freshly retrievable.

## Repository and system impact

No Flutter, Firebase, schema, rules, indexes, functions, deployment, or design-system mutation was
made. Repository changes are limited to the Stitch index, coverage/reference ledgers, open-question
record, README, and this audit. No Stitch screen was deleted, hidden, moved, grouped, or archived.

## Final status

Phase 08 is `COMPLETED / RENDER REVIEW`:

- ST-061 is the desktop working successor and ST-062 is the mobile working successor.
- Neither is a canonical candidate until fresh canvas code and renders reflect the recorded DOM
  operations.
- ST-057 through ST-060 remain superseded evidence history; ST-063/ST-064 are rejected fallbacks.
- Canonical promotion is blocked by stale served artifacts, not by unresolved product scope.
