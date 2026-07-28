import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import {
  CONTROL_PLANE_REGION,
  PROVISIONER_SECRETS,
  PROVISIONER_SERVICE_ACCOUNT,
} from './config';
import { provisionTenantProject } from './projectProvisioner';
import { ProvisioningStep, TenantDoc } from './types';

export const onTenantProvisionRequested = onDocumentWritten(
  {
    document: 'tenants/{tenantCode}',
    timeoutSeconds: 1200,
    memory: '1GiB',
    region: CONTROL_PLANE_REGION,
    serviceAccount: PROVISIONER_SERVICE_ACCOUNT,
    secrets: PROVISIONER_SECRETS,
    retry: false,
  },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists || after.data()?.status !== 'pending') return;

    const ref = after.ref;
    const leaseId = event.id;
    const claimed = await getFirestore().runTransaction(async (transaction) => {
      const current = await transaction.get(ref);
      if (!current.exists || current.data()?.status !== 'pending') return false;
      transaction.update(ref, {
        status: 'provisioning',
        leaseId,
        attempt: FieldValue.increment(1),
        error: null,
        'progress.message': 'Provisioner claimed the job.',
        'progress.updatedAt': FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (!claimed) return;

    const tenant = (await ref.get()).data() as TenantDoc;
    const completed = new Set<ProvisioningStep>(tenant.progress?.completedSteps ?? []);

    const report = async (step: ProvisioningStep, message: string): Promise<void> => {
      completed.add(step);
      await getFirestore().runTransaction(async (transaction) => {
        const current = await transaction.get(ref);
        if (!current.exists || current.data()?.leaseId !== leaseId) return;
        transaction.update(ref, {
          progress: {
            step,
            message,
            completedSteps: [...completed],
            updatedAt: FieldValue.serverTimestamp(),
          },
          updatedAt: FieldValue.serverTimestamp(),
        });
      });
    };

    try {
      const config = await provisionTenantProject(
        {
          tenantCode: tenant.tenantCode,
          businessName: tenant.businessName,
          ownerEmail: tenant.ownerEmail,
          firestoreRegion: tenant.firestoreRegion,
          projectId: tenant.projectId,
        },
        completed,
        report
      );

      await getFirestore().runTransaction(async (transaction) => {
        const current = await transaction.get(ref);
        if (!current.exists || current.data()?.leaseId !== leaseId) return;
        transaction.update(ref, {
          status: 'ready',
          config,
          error: null,
          leaseId: FieldValue.delete(),
          progress: {
            step: 'complete',
            message: 'Tenant is ready.',
            completedSteps: [...completed, 'complete'],
            updatedAt: FieldValue.serverTimestamp(),
          },
          updatedAt: FieldValue.serverTimestamp(),
        });
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await getFirestore().runTransaction(async (transaction) => {
        const current = await transaction.get(ref);
        if (!current.exists || current.data()?.leaseId !== leaseId) return;
        transaction.update(ref, {
          status: 'error',
          error: message.slice(0, 2000),
          leaseId: FieldValue.delete(),
          'progress.message': `Failed: ${message}`.slice(0, 500),
          'progress.updatedAt': FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      });
      throw error;
    }
  }
);
