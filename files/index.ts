import { getApps, initializeApp } from 'firebase-admin/app';

if (getApps().length === 0) initializeApp();

export { getTenantConfig } from './getTenantConfig';
export { listTenants } from './listTenants';
export { onboardTenant } from './onboardTenant';
export { onTenantProvisionRequested } from './onTenantProvisionRequested';
export { retryTenantProvisioning } from './retryTenantProvisioning';
