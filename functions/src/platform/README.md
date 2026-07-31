# Platform administrator grant CLI

`grantPlatformAdmin` is intentionally not exported as a callable. Operators
invoke the compiled Admin SDK CLI from `functions/` with Application Default
Credentials that are authorized for the selected project:

```powershell
npm run grant-platform-admin -- `
  --environment dev `
  --project-id multitenant-pos-b8326 `
  --confirm-project-id multitenant-pos-b8326 `
  --actor-uid PLATFORM_OPERATOR_UID `
  --target-uid EXACT_TARGET_UID `
  --confirm-target-uid EXACT_TARGET_UID `
  --request-id STABLE_REQUEST_ID `
  --reason "Reviewed reason"
```

The CLI checks the source-controlled environment/project allowlist before it
initializes Firebase. Production also requires `--confirm-production`. It
rejects real-project execution when emulator host variables are present.

Application Default Credentials authenticate the Admin SDK process. The
recorded operator UID is separately authorized against its enabled Auth record,
`platformRole=superAdmin` claim, and active `platform_admin` root. The target
UID is never discovered or inferred by the tool and must be typed twice.

Successful execution exits `0`. Invalid configuration exits `2`, operator
denial exits `3`, canonical ineligibility exits `4`, and a recoverable saga or
authorization-read failure exits `5`. Exit `1` is reserved for an unexpected
safe failure. When exit `5` occurs, fix the external failure and rerun the
identical command with the same request ID; the held identity transition is the
durable resume signal.

The `emulator` environment is test-only. It is accepted solely for the fixed
`demo-multitenant-invitation-integration` project while both Auth and Firestore
emulator hosts resolve to localhost.
