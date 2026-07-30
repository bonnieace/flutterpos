const { getApps, initializeApp } = require("firebase-admin/app");

if (getApps().length === 0) initializeApp();

const {
  acceptTenantInvitation,
  acceptVisibleTenantInvitation,
} = require("./lib/staff/acceptance");
const { setDefaultTenant } = require("./lib/tenants/routing");

exports.acceptTenantInvitation = acceptTenantInvitation;
exports.acceptVisibleTenantInvitation = acceptVisibleTenantInvitation;
exports.setDefaultTenant = setDefaultTenant;
