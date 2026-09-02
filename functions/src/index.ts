import {getApps, initializeApp} from "firebase-admin/app";

if (getApps().length === 0) initializeApp();

// Runs inside account creation, so an Auth identity cannot exist without the
// canonical root document `requestTenant` requires of every applicant.
export {bootstrapSelfSignupIdentity} from "./auth/identityBootstrap";

// The rest of signing up: the name and phone that account creation had no way
// to carry, the first verification email nobody has to ask for, and the one
// window in which a never-verified address may still be corrected.
export {changeSignupEmail, completeSelfSignup} from "./auth/selfSignupProfile";

export {requestTenant} from "./tenants/onboarding";
export {listMyTenants, setDefaultTenant} from "./tenants/routing";

export {setTenantLifecycle} from "./lifecycle/tenantLifecycle";
export {setGlobalUserStatus} from "./lifecycle/globalStatus";
export {getGlobalUserStatusReview} from "./lifecycle/globalStatusReview";
export {retryGlobalUserStatusOperations} from "./lifecycle/retryWorker";

export {
  consumeTenantMembershipFanout,
  repairCanonicalStaffMirror,
  repairTenantRoutingProjection,
  retryMembershipRepairTasks,
  runMembershipRepairTask,
  startWeeklyMembershipRepair,
} from "./repair";

export {
  acceptTenantInvitation,
  acceptVisibleTenantInvitation,
  cancelTenantInvitation,
  inviteStaff,
  replacePendingStaffEmail,
  resendStaffInvitation,
  setStaffStatus,
  updateStaffUser,
} from "./staff";
export {cleanupAbandonedStaffIdentities} from "./staff/identityProvisioning";
export {
  deliverStaffInvitation,
  retryStaffInvitationDeliveries,
} from "./staff/invitationDelivery";

export {
  getMyEmailDeliveryStatus,
  requestPasswordReset,
  deliverPasswordReset,
} from "./email/passwordReset";
export {
  deliverAccountVerification,
  sendAccountVerification,
} from "./email/accountVerification";
export {reviewEmailSuppression} from "./email/suppression";
export {receiveBrevoEmailWebhook} from "./email/webhook";
export {
  consumePendingPlatformAlert,
  deliverPlatformAlertNotification,
  retryPlatformAlertNotifications,
} from "./email/platformAlert";

export {
  adjustStock,
  getSalesComparison,
  importProducts,
  removeProductBackground,
  updateProduct,
  updateProducts,
  verifyReturnAndRestoreStock,
} from "./operations";

export {
  amendShiftSummary,
  mergeSaleReconciliationJob,
  requestTenantReconciliation,
  retryTenantReconciliationTasks,
  runReconciliationTenantDiscoveryTask,
  runTenantReconciliationTask,
  startNightlyTenantReconciliation,
  startStaggeredMonthlyReconciliation,
  startWeeklyStockCheckpoints,
} from "./reconciliation";
