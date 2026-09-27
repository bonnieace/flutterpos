param(
  [Parameter(Mandatory = $true)] [string] $Device,
  [Parameter(Mandatory = $true)] [string] $Email,
  [Parameter(Mandatory = $true)] [string] $Password
)

$ErrorActionPreference = 'Stop'
$package = 'ke.co.uzapay.pos'
$test = 'integration_test/offline_cold_start_test.dart'
$common = @(
  'test', $test, '-d', $Device,
  '--dart-define=USE_FIREBASE_EMULATORS=true'
)

try {
  & flutter @common `
    '--dart-define=OFFLINE_ACCEPTANCE_PHASE=prime' `
    "--dart-define=OFFLINE_ACCEPTANCE_EMAIL=$Email" `
    "--dart-define=OFFLINE_ACCEPTANCE_PASSWORD=$Password"
  if ($LASTEXITCODE -ne 0) { throw 'The online priming phase failed.' }

  & adb -s $Device shell am force-stop $package
  & adb -s $Device shell svc wifi disable
  & adb -s $Device shell svc data disable

  & flutter @common '--dart-define=OFFLINE_ACCEPTANCE_PHASE=verify'
  if ($LASTEXITCODE -ne 0) { throw 'The offline cold-start phase failed.' }
}
finally {
  & adb -s $Device shell svc wifi enable
  & adb -s $Device shell svc data enable
}
