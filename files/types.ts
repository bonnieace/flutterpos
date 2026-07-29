export type TenantStatus = 'pending' | 'provisioning' | 'ready' | 'error';

export type ProvisioningStep =
  | 'queued'
  | 'project'
  | 'billing'
  | 'apis'
  | 'firebase'
  | 'firestore'
  | 'storage'
  | 'rules'
  | 'android-app'
  | 'tenant-seed'
  | 'runtime'
  | 'owner-invite'
  | 'complete';

export interface TenantOnboardingInput {
  tenantCode: string;
  businessName: string;
  ownerEmail: string;
  firestoreRegion?: string;
}

export interface TenantAndroidConfig {
  projectId: string;
  appId: string;
  apiKey: string;
  messagingSenderId: string;
  storageBucket: string;
  authDomain: string;
}

export interface TenantConfig {
  projectId: string;
  projectNumber: string;
  firestoreRegion: string;
  android: TenantAndroidConfig;
}

export interface TenantProgress {
  step: ProvisioningStep;
  message: string;
  completedSteps: ProvisioningStep[];
  updatedAt: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp;
}

export interface TenantDoc extends TenantOnboardingInput {
  projectId: string;
  status: TenantStatus;
  attempt: number;
  leaseId?: string;
  error?: string | null;
  config?: TenantConfig;
  progress: TenantProgress;
  createdBy: string;
  createdAt: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp;
}

export interface ProvisionTenantInput extends TenantOnboardingInput {
  projectId: string;
}

export interface ProvisioningProgressUpdate {
  step: ProvisioningStep;
  message: string;
}
