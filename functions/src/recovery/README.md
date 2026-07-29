# Owner recovery

`owner-recovery` is an operator-only Admin SDK command. It is not exported as a
Callable Function. Run it only with Application Default Credentials authorized
for the explicitly named Firebase project.

Build and inspect the command first:

```powershell
npm run owner-recovery -- --project-id PROJECT_ID `
  --operator-uid PLATFORM_UID `
  --tenant-id TENANT_ID `
  --replacement-uid REPLACEMENT_UID `
  --operation-id STABLE_OPERATION_ID `
  --reason "SUPPORT_REASON" `
  --dry-run
```

Keep the same operation ID when rerunning without `--dry-run`. A completed
operation with that ID is recognized idempotently; an ID used for different
arguments fails closed.

Normal recovery accepts only a globally active tenant user whose canonical
staff record is already `role=admin` and `status=active`.

Exceptional recovery additionally needs an unconsumed case document:

```text
/owner_recovery_cases/{caseId}
  tenantId
  oldOwnerUid
  replacementUid
  supportReference
  status                 // open | approved
```

Use all exceptional controls on both the dry run and execution:

```powershell
npm run owner-recovery -- --project-id PROJECT_ID `
  --operator-uid PLATFORM_UID `
  --tenant-id TENANT_ID `
  --replacement-uid REPLACEMENT_UID `
  --operation-id STABLE_OPERATION_ID `
  --reason "DOCUMENTED_REASON" `
  --exceptional `
  --case-id CASE_ID `
  --support-reference SUPPORT_REFERENCE `
  --confirm-tenant-slug EXACT_TENANT_SLUG `
  --confirm-old-owner-uid EXACT_OLD_UID `
  --confirm-replacement-uid EXACT_REPLACEMENT_UID `
  --confirm-exactly-one-owner `
  --dry-run
```

Exceptional mode requires a verified, enabled Auth identity backed by an
active, transition-free canonical `tenant_user` root. It rejects platform
claims and existing canonical membership in the target tenant. The transaction
creates that membership, consumes the case, makes the replacement the sole
active owner, and leaves the old owner as an inactive admin.

The command repairs ownership counters from canonical tenant queries, but all
root counters and membership mirrors remain routing data only. Authorization
continues to use the tenant and canonical staff documents.
