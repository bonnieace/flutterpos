import { defineSecret, defineString } from 'firebase-functions/params';

export const CONTROL_PLANE_REGION = defineString('CONTROL_PLANE_REGION', {
  default: 'europe-west1',
});

export const BILLING_ACCOUNT = defineString('CONTROL_PLANE_BILLING_ACCOUNT');
export const PARENT_RESOURCE = defineString('CONTROL_PLANE_PARENT_RESOURCE');
export const DEFAULT_FIRESTORE_REGION = defineString('CONTROL_PLANE_FIRESTORE_REGION', {
  default: 'africa-south1',
});
export const ANDROID_PACKAGE_NAME = defineString('CONTROL_PLANE_ANDROID_PACKAGE_NAME');
export const PROVISIONER_SERVICE_ACCOUNT = defineString(
  'CONTROL_PLANE_PROVISIONER_SERVICE_ACCOUNT'
);
export const RUNTIME_DEPLOY_HOOK_URL = defineString('TENANT_RUNTIME_DEPLOY_HOOK_URL');
export const OWNER_EMAIL_HOOK_URL = defineString('TENANT_OWNER_EMAIL_HOOK_URL');

export const RUNTIME_DEPLOY_HOOK_SECRET = defineSecret('TENANT_RUNTIME_DEPLOY_HOOK_SECRET');
export const OWNER_EMAIL_HOOK_SECRET = defineSecret('TENANT_OWNER_EMAIL_HOOK_SECRET');

export const PROVISIONER_SECRETS = [RUNTIME_DEPLOY_HOOK_SECRET, OWNER_EMAIL_HOOK_SECRET];
