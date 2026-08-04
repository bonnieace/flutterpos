const { getApps, initializeApp } = require("firebase-admin/app");

if (getApps().length === 0) initializeApp();

// Only the reconciliation entry points a sale and its correction actually reach.
// Exporting the whole index would pull in every `defineSecret`/`defineString`
// parameter in the codebase, and each one without a default makes the emulator
// stop and ask for a value at startup - which, with no terminal to answer, is a
// run that appears to hang forever after "Serving at port ...". The invitation
// fixture exports seven functions for the same reason.
//
// `amendShiftSummary` was checked against that rule before it was added here:
// its require closure is `core/authorization`, `core/idempotency`,
// `core/validation`, `operations/domain`, and `reconciliation/model`, and not
// one of them reaches `firebase-functions/params`. Anything added later must be
// checked the same way: follow its `require` calls in `functions/lib` until they
// close, and confirm none of them reaches that module.
const {
  mergeSaleReconciliationJob,
  runTenantReconciliationTask,
} = require("./lib/reconciliation/handlers");
const { amendShiftSummary } = require("./lib/reconciliation/amendments");

exports.mergeSaleReconciliationJob = mergeSaleReconciliationJob;
exports.runTenantReconciliationTask = runTenantReconciliationTask;
exports.amendShiftSummary = amendShiftSummary;
