const { getApps, initializeApp } = require("firebase-admin/app");

if (getApps().length === 0) initializeApp();

// Only the two reconciliation entry points a sale actually reaches. Exporting
// the whole index would pull in every `defineSecret`/`defineString` parameter in
// the codebase, and each one without a default makes the emulator stop and ask
// for a value at startup - which, with no terminal to answer, is a run that
// appears to hang forever after "Serving at port ...". The invitation fixture
// exports seven functions for the same reason.
const {
  mergeSaleReconciliationJob,
  runTenantReconciliationTask,
} = require("./lib/reconciliation/handlers");

exports.mergeSaleReconciliationJob = mergeSaleReconciliationJob;
exports.runTenantReconciliationTask = runTenantReconciliationTask;
