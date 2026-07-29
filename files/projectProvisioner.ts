import { App, deleteApp, getApp, initializeApp } from 'firebase-admin/app';
import { getAuth, UserRecord } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import {
  ANDROID_PACKAGE_NAME,
  BILLING_ACCOUNT,
  DEFAULT_FIRESTORE_REGION,
  OWNER_EMAIL_HOOK_SECRET,
  OWNER_EMAIL_HOOK_URL,
  PARENT_RESOURCE,
  RUNTIME_DEPLOY_HOOK_SECRET,
  RUNTIME_DEPLOY_HOOK_URL,
} from './config';
import { gfetch, isGoogleApiStatus, pollOperation, postHook } from './gcpAuth';
import {
  ProvisionTenantInput,
  ProvisioningProgressUpdate,
  ProvisioningStep,
  TenantConfig,
} from './types';

const CLOUD_RESOURCE_MANAGER = 'https://cloudresourcemanager.googleapis.com/v3';
const FIREBASE_MGMT = 'https://firebase.googleapis.com/v1beta1';
const SERVICE_USAGE = 'https://serviceusage.googleapis.com/v1';
const CLOUD_BILLING = 'https://cloudbilling.googleapis.com/v1';
const FIRESTORE = 'https://firestore.googleapis.com/v1';
const FIREBASE_RULES = 'https://firebaserules.googleapis.com/v1';
const FIREBASE_STORAGE = 'https://firebasestorage.googleapis.com/v1alpha';
const IDENTITY_TOOLKIT = 'https://identitytoolkit.googleapis.com/admin/v2';

const REQUIRED_APIS = [
  'firebase.googleapis.com',
  'firestore.googleapis.com',
  'identitytoolkit.googleapis.com',
  'firebaserules.googleapis.com',
  'firebasestorage.googleapis.com',
  'storage.googleapis.com',
  'cloudfunctions.googleapis.com',
  'cloudbuild.googleapis.com',
  'artifactregistry.googleapis.com',
  'run.googleapis.com',
  'eventarc.googleapis.com',
  'pubsub.googleapis.com',
];

const FIRESTORE_RULES = `rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function staffRecord() {
      return get(/databases/$(database)/documents/staff/$(request.auth.uid)).data;
    }
    function activeStaff() {
      return request.auth != null && staffRecord().status == 'Active';
    }
    function roleIs(role) {
      return activeStaff() && staffRecord().role == role;
    }
    function canManage() {
      return roleIs('Admin') || roleIs('Manager');
    }
    function cashierOperationalWrite(collection) {
      return roleIs('Cashier') && collection in ['alcoholsales', 'returns', 'shifts'];
    }

    match /{collection}/{document} {
      allow read: if activeStaff();
      allow create, update: if canManage() || cashierOperationalWrite(collection);
      allow delete: if canManage();
    }
    match /{document=**} {
      allow read, write: if false;
    }
  }
}`;

const STORAGE_RULES = `rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    function staffRecord() {
      return firestore.get(/databases/(default)/documents/staff/$(request.auth.uid)).data;
    }
    function activeStaff() {
      return request.auth != null && staffRecord().status == 'Active';
    }
    function canManage() {
      return activeStaff() && staffRecord().role in ['Admin', 'Manager'];
    }
    match /{path=**} {
      allow read: if activeStaff();
      allow write: if canManage() && request.resource.size < 10 * 1024 * 1024;
    }
  }
}`;

interface CloudProject {
  name?: string;
  projectId: string;
}

interface AndroidApp {
  name?: string;
  appId?: string;
  packageName?: string;
}

type ProgressReporter = (step: ProvisioningStep, message: string) => Promise<void>;

function requireConfiguration(value: string, name: string, pattern?: RegExp): string {
  const normalized = value.trim();
  if (!normalized || (pattern && !pattern.test(normalized))) {
    throw new Error(`${name} is missing or invalid.`);
  }
  return normalized;
}

async function getProject(projectId: string): Promise<CloudProject | null> {
  try {
    return await gfetch<CloudProject>(`${CLOUD_RESOURCE_MANAGER}/projects/${projectId}`);
  } catch (error) {
    if (isGoogleApiStatus(error, 404)) return null;
    throw error;
  }
}

async function ensureProject(input: ProvisionTenantInput): Promise<CloudProject> {
  const existing = await getProject(input.projectId);
  if (existing) return existing;

  const parent = requireConfiguration(
    PARENT_RESOURCE.value(),
    'CONTROL_PLANE_PARENT_RESOURCE',
    /^(folders|organizations)\/\d+$/
  );
  const operation = await gfetch<{ name: string }>(`${CLOUD_RESOURCE_MANAGER}/projects`, {
    method: 'POST',
    body: JSON.stringify({
      projectId: input.projectId,
      displayName: input.businessName,
      parent,
      labels: { tenant: input.tenantCode, managed_by: 'pos-control-plane' },
    }),
  });
  await pollOperation(`${CLOUD_RESOURCE_MANAGER}/${operation.name}`);
  const created = await getProject(input.projectId);
  if (!created) throw new Error(`Project ${input.projectId} was created but cannot be read.`);
  return created;
}

function projectNumber(project: CloudProject): string {
  const value = project.name?.split('/').pop();
  if (!value) throw new Error(`Cloud project ${project.projectId} has no project number.`);
  return value;
}

async function ensureBilling(projectId: string): Promise<void> {
  const billingAccountName = requireConfiguration(
    BILLING_ACCOUNT.value(),
    'CONTROL_PLANE_BILLING_ACCOUNT',
    /^billingAccounts\/[A-Z0-9-]+$/i
  );
  const url = `${CLOUD_BILLING}/projects/${projectId}/billingInfo`;
  const current = await gfetch<{ billingAccountName?: string; billingEnabled?: boolean }>(url);
  if (current.billingEnabled && current.billingAccountName === billingAccountName) return;
  await gfetch(url, {
    method: 'PUT',
    body: JSON.stringify({ billingAccountName }),
  });
}

async function ensureApis(projectId: string): Promise<void> {
  const operation = await gfetch<{ name?: string }>(
    `${SERVICE_USAGE}/projects/${projectId}/services:batchEnable`,
    { method: 'POST', body: JSON.stringify({ serviceIds: REQUIRED_APIS }) }
  );
  if (operation.name) await pollOperation(`${SERVICE_USAGE}/${operation.name}`);
}

async function ensureFirebase(projectId: string): Promise<void> {
  try {
    await gfetch(`${FIREBASE_MGMT}/projects/${projectId}`);
    return;
  } catch (error) {
    if (!isGoogleApiStatus(error, 404)) throw error;
  }
  const operation = await gfetch<{ name: string }>(
    `${FIREBASE_MGMT}/projects/${projectId}:addFirebase`,
    { method: 'POST', body: '{}' }
  );
  await pollOperation(`${FIREBASE_MGMT}/${operation.name}`);
}

async function ensureFirestore(projectId: string, region: string): Promise<void> {
  const databaseUrl = `${FIRESTORE}/projects/${projectId}/databases/(default)`;
  try {
    await gfetch(databaseUrl);
    return;
  } catch (error) {
    if (!isGoogleApiStatus(error, 404)) throw error;
  }
  const operation = await gfetch<{ name: string }>(
    `${FIRESTORE}/projects/${projectId}/databases?databaseId=(default)`,
    {
      method: 'POST',
      body: JSON.stringify({ locationId: region, type: 'FIRESTORE_NATIVE' }),
    }
  );
  await pollOperation(`${FIRESTORE}/${operation.name}`);
}

async function ensureStorage(projectId: string, region: string): Promise<string> {
  const url = `${FIREBASE_STORAGE}/projects/${projectId}/defaultBucket`;
  const nameFrom = (value?: string): string =>
    value?.split('/').pop() || `${projectId}.firebasestorage.app`;
  try {
    const existing = await gfetch<{ bucket?: { name?: string }; name?: string }>(url);
    return nameFrom(existing.bucket?.name ?? existing.name);
  } catch (error) {
    if (!isGoogleApiStatus(error, 404)) throw error;
  }
  try {
    const created = await gfetch<{ bucket?: { name?: string }; name?: string }>(url, {
      method: 'POST',
      body: JSON.stringify({ location: region }),
    });
    return nameFrom(created.bucket?.name ?? created.name);
  } catch (error) {
    if (!isGoogleApiStatus(error, 409)) throw error;
    return `${projectId}.firebasestorage.app`;
  }
}

async function deployRules(
  projectId: string,
  releaseId: string,
  filename: string,
  content: string
): Promise<void> {
  const ruleset = await gfetch<{ name: string }>(`${FIREBASE_RULES}/projects/${projectId}/rulesets`, {
    method: 'POST',
    body: JSON.stringify({ source: { files: [{ name: filename, content }] } }),
  });
  const releaseName = `projects/${projectId}/releases/${releaseId}`;
  const releaseUrl = `${FIREBASE_RULES}/${releaseName}`;
  try {
    await gfetch(releaseUrl);
    await gfetch(`${releaseUrl}?updateMask=ruleset_name`, {
      method: 'PATCH',
      body: JSON.stringify({ name: releaseName, rulesetName: ruleset.name }),
    });
  } catch (error) {
    if (!isGoogleApiStatus(error, 404)) throw error;
    await gfetch(`${FIREBASE_RULES}/projects/${projectId}/releases`, {
      method: 'POST',
      body: JSON.stringify({ name: releaseName, rulesetName: ruleset.name }),
    });
  }
}

async function ensureAuthEmailProvider(projectId: string): Promise<void> {
  await gfetch(
    `${IDENTITY_TOOLKIT}/projects/${projectId}/config?updateMask=signIn.email`,
    {
      method: 'PATCH',
      body: JSON.stringify({ signIn: { email: { enabled: true, passwordRequired: true } } }),
    }
  );
}

async function ensureAndroidApp(projectId: string, packageName: string): Promise<AndroidApp> {
  const list = await gfetch<{ apps?: AndroidApp[] }>(
    `${FIREBASE_MGMT}/projects/${projectId}/androidApps?pageSize=100`
  );
  const existing = list.apps?.find((app) => app.packageName === packageName);
  if (existing) return existing;

  const operation = await gfetch<{ name: string }>(
    `${FIREBASE_MGMT}/projects/${projectId}/androidApps`,
    {
      method: 'POST',
      body: JSON.stringify({ packageName, displayName: 'Shared POS Android' }),
    }
  );
  return pollOperation<AndroidApp>(`${FIREBASE_MGMT}/${operation.name}`);
}

function androidAppId(app: AndroidApp): string {
  const value = app.appId ?? app.name?.split('/').pop();
  if (!value) throw new Error('The Firebase Android app has no app ID.');
  return value;
}

async function fetchAndroidConfig(
  projectId: string,
  appId: string,
  number: string,
  storageBucket: string,
  firestoreRegion: string
): Promise<TenantConfig> {
  const result = await gfetch<{ configFileContents: string }>(
    `${FIREBASE_MGMT}/projects/${projectId}/androidApps/${appId}/config`
  );
  const parsed = JSON.parse(Buffer.from(result.configFileContents, 'base64').toString('utf8')) as {
    project_info?: { storage_bucket?: string };
    client?: Array<{ api_key?: Array<{ current_key?: string }> }>;
  };
  const apiKey = parsed.client?.[0]?.api_key?.[0]?.current_key;
  if (!apiKey) throw new Error('The generated Android Firebase config has no API key.');
  return {
    projectId,
    projectNumber: number,
    firestoreRegion,
    android: {
      projectId,
      appId,
      apiKey,
      messagingSenderId: number,
      storageBucket: parsed.project_info?.storage_bucket ?? storageBucket,
      authDomain: `${projectId}.firebaseapp.com`,
    },
  };
}

function tenantAdminApp(projectId: string, storageBucket: string): App {
  try {
    return getApp(`tenant-${projectId}`);
  } catch {
    return initializeApp({ projectId, storageBucket }, `tenant-${projectId}`);
  }
}

async function findOrCreateOwner(app: App, email: string, businessName: string): Promise<UserRecord> {
  const auth = getAuth(app);
  let user: UserRecord;
  try {
    user = await auth.getUserByEmail(email);
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code !== 'auth/user-not-found') throw error;
    user = await auth.createUser({ email, emailVerified: false, displayName: businessName });
  }
  await auth.setCustomUserClaims(user.uid, { role: 'Admin' });
  return user;
}

async function seedTenant(
  input: ProvisionTenantInput,
  storageBucket: string
): Promise<{ app: App; owner: UserRecord }> {
  const app = tenantAdminApp(input.projectId, storageBucket);
  const owner = await findOrCreateOwner(app, input.ownerEmail, input.businessName);
  const database = getFirestore(app);
  const batch = database.batch();
  batch.set(
    database.collection('staff').doc(owner.uid),
    {
      uid: owner.uid,
      name: owner.displayName ?? input.businessName,
      email: input.ownerEmail,
      phone: '',
      role: 'Admin',
      status: 'Active',
      lastLogin: null,
      avatarInitials: (owner.displayName ?? input.businessName)
        .split(/\s+/)
        .slice(0, 2)
        .map((part) => part[0]?.toUpperCase())
        .join(''),
      createdAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  batch.set(
    database.collection('app_config').doc('branding'),
    {
      businessName: input.businessName,
      tenantCode: input.tenantCode,
      logoUrl: null,
      primaryColor: null,
      receiptFooter: null,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  await batch.commit();
  return { app, owner };
}

async function deployTenantRuntime(
  input: ProvisionTenantInput,
  config: TenantConfig,
  packageName: string
): Promise<void> {
  const response = await postHook<{ success?: boolean; runtimeVersion?: string }>(
    RUNTIME_DEPLOY_HOOK_URL.value(),
    RUNTIME_DEPLOY_HOOK_SECRET.value(),
    {
      event: 'tenant.runtime.deploy',
      idempotencyKey: `${input.projectId}:runtime-v1`,
      tenantCode: input.tenantCode,
      projectId: input.projectId,
      projectNumber: config.projectNumber,
      firestoreRegion: config.firestoreRegion,
      androidPackageName: packageName,
    }
  );
  if (!response.success) throw new Error('The tenant runtime deployment hook did not confirm success.');
}

async function sendOwnerInvite(
  app: App,
  input: ProvisionTenantInput,
  owner: UserRecord
): Promise<void> {
  const setupLink = await getAuth(app).generatePasswordResetLink(input.ownerEmail);
  const response = await postHook<{ accepted?: boolean }>(
    OWNER_EMAIL_HOOK_URL.value(),
    OWNER_EMAIL_HOOK_SECRET.value(),
    {
      event: 'tenant.owner.invite',
      idempotencyKey: `${input.projectId}:owner:${owner.uid}`,
      tenantCode: input.tenantCode,
      businessName: input.businessName,
      projectId: input.projectId,
      recipient: input.ownerEmail,
      setupLink,
    }
  );
  if (!response.accepted) throw new Error('The owner email hook did not accept the invitation.');
}

export async function provisionTenantProject(
  input: ProvisionTenantInput,
  completedSteps: ReadonlySet<ProvisioningStep>,
  report: (update: ProvisioningProgressUpdate['step'], message: string) => Promise<void>
): Promise<TenantConfig> {
  const firestoreRegion = input.firestoreRegion ?? DEFAULT_FIRESTORE_REGION.value();
  const packageName = requireConfiguration(
    ANDROID_PACKAGE_NAME.value(),
    'CONTROL_PLANE_ANDROID_PACKAGE_NAME',
    /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$/
  );
  const progress: ProgressReporter = report;

  const project = await ensureProject(input);
  await progress('project', `Cloud project ${input.projectId} exists.`);

  await ensureBilling(input.projectId);
  await progress('billing', 'Billing is linked.');

  await ensureApis(input.projectId);
  await progress('apis', 'Required Google APIs are enabled.');

  await ensureFirebase(input.projectId);
  await progress('firebase', 'Firebase is attached to the project.');

  await ensureFirestore(input.projectId, firestoreRegion);
  await ensureAuthEmailProvider(input.projectId);
  await progress('firestore', `Firestore and email/password auth are configured in ${firestoreRegion}.`);

  const storageBucket = await ensureStorage(input.projectId, firestoreRegion);
  await progress('storage', `Default Storage bucket ${storageBucket} exists.`);

  await deployRules(input.projectId, 'cloud.firestore', 'firestore.rules', FIRESTORE_RULES);
  await deployRules(
    input.projectId,
    `firebase.storage/${storageBucket}`,
    'storage.rules',
    STORAGE_RULES
  );
  await progress('rules', 'Firestore and Storage rules are deployed.');

  const androidApp = await ensureAndroidApp(input.projectId, packageName);
  const config = await fetchAndroidConfig(
    input.projectId,
    androidAppId(androidApp),
    projectNumber(project),
    storageBucket,
    firestoreRegion
  );
  await progress('android-app', 'The shared Android application is registered.');

  const { app, owner } = await seedTenant(input, storageBucket);
  await progress('tenant-seed', 'Tenant branding and the first Admin account are seeded.');

  try {
    if (!completedSteps.has('runtime')) {
      await deployTenantRuntime(input, config, packageName);
    }
    await progress('runtime', 'Tenant Cloud Functions and indexes are deployed.');

    if (!completedSteps.has('owner-invite')) {
      await sendOwnerInvite(app, input, owner);
    }
    await progress('owner-invite', `The setup email was accepted for ${input.ownerEmail}.`);
  } finally {
    await deleteApp(app);
  }

  return config;
}
