import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { CONTROL_PLANE_REGION } from './config';
import { requireSuperAdmin } from './authz';
import { generateProjectId, validateOnboardingInput } from './validation';

export const onboardTenant = onCall(
  { enforceAppCheck: true, region: CONTROL_PLANE_REGION },
  async (request) => {
    const createdBy = requireSuperAdmin(request);
    const input = validateOnboardingInput(request.data);
    const ref = getFirestore().collection('tenants').doc(input.tenantCode);
    const projectId = generateProjectId(input.tenantCode);

    await getFirestore().runTransaction(async (transaction) => {
      const existing = await transaction.get(ref);
      if (existing.exists) {
        throw new HttpsError('already-exists', `Tenant '${input.tenantCode}' already exists.`);
      }
      transaction.create(ref, {
        ...input,
        projectId,
        status: 'pending',
        attempt: 0,
        error: null,
        progress: {
          step: 'queued',
          message: 'Waiting for a provisioner.',
          completedSteps: [],
          updatedAt: FieldValue.serverTimestamp(),
        },
        createdBy,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });

    return { tenantCode: input.tenantCode, projectId, status: 'pending' };
  }
);
