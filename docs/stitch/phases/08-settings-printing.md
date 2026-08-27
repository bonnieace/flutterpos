> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 08 — Supported settings and printing

## Objective

Replace generic business settings with the configuration the app actually supports, and select a
canonical printer/receipt recovery experience.

## Evidence to open

- Screenshot groups 16, 36, 37.
- Checkout currency, printer endpoint/paper/cutter/test, queue, branding read, and receipt body code.
- Stitch ST-003, ST-004, ST-010, ST-017, ST-024.

## Required screens/states

- Currency configuration for owner/admin.
- Printer host, port, paper width, cutter behavior, test result, unconfigured/unreachable states.
- Receipts-waiting queue, unreadable record, retry busy/success/failure.
- Receipt preview only if it accurately represents immutable queued bytes and configured width.

## Exclusions

- VAT, prices-include-tax, registration/location/contact/support, language, sync interval, or editable
  branding unless separately approved and implemented.

## Acceptance criteria

- Configuration fields correspond one-for-one with active persistence and validation.
- Print failure never relabels a durable sale as failed.
- Queue scope is clearly device-local.
- Width/cutter choices communicate physical consequences without promising device proof from Stitch.
