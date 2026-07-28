import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { requireSuperAdmin } from './authz';
import { CONTROL_PLANE_REGION } from './config';
import { normalizeTenantCode } from './validation';

const STALE_AFTER_MS = 15 * 60 * 1000;

export const retryTenantProvisioning = onCall(
  { enforceAppCheck: true, region: CONTROL_PLANE_REGION },
  async (request) => {
    requireSuperAdmin(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const tenantCode = normalizeTenantCode(data.tenantCode);
    const ref = getFirestore().collection('tenants').doc(tenantCode);

    await getFirestore().runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw new HttpsError('not-found', 'Tenant not found.');

      const tenant = snapshot.data()!;
      if (tenant.status === 'ready') {
        throw new HttpsError('failed-precondition', 'This tenant is already ready.');
      }
      if (tenant.status === 'pending') return;
      if (tenant.status === 'provisioning') {
        const updatedAt = tenant.updatedAt as Timestamp | undefined;
        const isStale = !updatedAt || Date.now() - updatedAt.toMillis() >= STALE_AFTER_MS;
        if (!isStale) {
          throw new HttpsError('failed-precondition', 'Provisioning is still active.');
        }
      }

      transaction.update(ref, {
        status: 'pending',
        leaseId: FieldValue.delete(),
        error: null,
        'progress.message': 'Retry queued. Completed steps will be reused.',
        'progress.updatedAt': FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });

    return { tenantCode, status: 'pending' };
  }
);
