import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import { requireSuperAdmin } from './authz';
import { CONTROL_PLANE_REGION } from './config';

function timestampToIso(value: unknown): string | null {
  return value instanceof Timestamp ? value.toDate().toISOString() : null;
}

export const listTenants = onCall(
  { enforceAppCheck: true, region: CONTROL_PLANE_REGION },
  async (request) => {
    requireSuperAdmin(request);
    const snapshot = await getFirestore()
      .collection('tenants')
      .orderBy('createdAt', 'desc')
      .limit(100)
      .get();

    return {
      tenants: snapshot.docs.map((document) => {
        const data = document.data();
        return {
          tenantCode: document.id,
          businessName: data.businessName,
          ownerEmail: data.ownerEmail,
          projectId: data.projectId,
          firestoreRegion: data.firestoreRegion ?? null,
          status: data.status,
          attempt: data.attempt ?? 0,
          error: data.error ?? null,
          progress: {
            step: data.progress?.step ?? null,
            message: data.progress?.message ?? null,
            completedSteps: data.progress?.completedSteps ?? [],
          },
          createdAt: timestampToIso(data.createdAt),
          updatedAt: timestampToIso(data.updatedAt),
        };
      }),
    };
  }
);
