import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { CONTROL_PLANE_REGION } from './config';
import { normalizeTenantCode } from './validation';

export const getTenantConfig = onCall(
  { enforceAppCheck: true, region: CONTROL_PLANE_REGION },
  async (request) => {
    const value = (request.data ?? {}) as Record<string, unknown>;
    const tenantCode = normalizeTenantCode(value.tenantCode);
    const snapshot = await getFirestore().collection('tenants').doc(tenantCode).get();
    if (!snapshot.exists) throw new HttpsError('not-found', 'Tenant not found.');

    const tenant = snapshot.data()!;
    if (tenant.status === 'error') {
      throw new HttpsError('internal', 'Tenant setup needs support intervention.');
    }
    if (tenant.status !== 'ready' || !tenant.config) {
      throw new HttpsError('unavailable', 'This tenant is still being set up.');
    }
    return { tenantCode, config: tenant.config };
  }
);
