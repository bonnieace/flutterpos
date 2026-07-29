# Provisioning hook contracts

The control plane deliberately does not run Firebase CLI deployments or send mail from the long-running Firestore trigger. It calls two private HTTPS services. Both services must:

- require the exact `Authorization: Bearer <configured-secret>` value;
- accept JSON only and reject oversized payloads;
- persist and deduplicate `idempotencyKey` before doing work;
- return a non-2xx response when work has not completed;
- never log the bearer token or owner setup link.

## Tenant runtime deployment

`TENANT_RUNTIME_DEPLOY_HOOK_URL` receives:

```json
{
  "event": "tenant.runtime.deploy",
  "idempotencyKey": "project-id:runtime-v1",
  "tenantCode": "acme-nairobi",
  "projectId": "pos-acme-nairobi-a1b2c3d4",
  "projectNumber": "1234567890",
  "firestoreRegion": "africa-south1",
  "androidPackageName": "com.example.sharedpos"
}
```

It must deploy the immutable, reviewed tenant runtime artifact to `projectId`. For this app that artifact currently needs the callable functions used by the Flutter client (`getSalesComparison`, `createStaffUser`, and `toggleStaffStatus`) plus any Firestore indexes. It should also apply per-project runtime service accounts, secrets, and minimum IAM.

Success response:

```json
{ "success": true, "runtimeVersion": "git-sha-or-release-id" }
```

The deployment service, not the control-plane trigger, should own the broad deployment IAM. A Cloud Build or CI service behind authenticated Cloud Run is a typical implementation.

## Owner invitation email

`TENANT_OWNER_EMAIL_HOOK_URL` receives:

```json
{
  "event": "tenant.owner.invite",
  "idempotencyKey": "project-id:owner:firebase-uid",
  "tenantCode": "acme-nairobi",
  "businessName": "Acme Nairobi",
  "projectId": "pos-acme-nairobi-a1b2c3d4",
  "recipient": "owner@example.com",
  "setupLink": "https://..."
}
```

It must send the one-time setup link through your transactional email provider and return:

```json
{ "accepted": true }
```

`accepted` means the provider accepted an idempotent send, not merely that the HTTP handler queued an untracked background task.
