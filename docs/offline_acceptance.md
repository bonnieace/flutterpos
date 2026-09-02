# Android offline cold-process acceptance

Run the Firebase emulators and seed an active owner with a usable tenant,
catalog, checkout configuration, and open shift. Then run:

```powershell
.\tool\android_offline_cold_start.ps1 `
  -Device emulator-5554 `
  -Email owner@example.test `
  -Password test-password
```

The first phase authenticates and primes the device. The script force-stops the
package, disables emulator Wi-Fi and mobile data without clearing app storage,
and launches the second phase. It requires the cached tenant home within two
seconds, the persistent device-data banner, and a usable register. When the
seed exposes a sellable cached product, it also saves a checkout offline.

The `finally` block restores both network transports even when an assertion
fails.
