import { randomBytes } from 'node:crypto';
import { HttpsError } from 'firebase-functions/v2/https';
import { TenantOnboardingInput } from './types';

const TENANT_CODE = /^[a-z][a-z0-9-]{2,19}$/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const REGION = /^[a-z][a-z0-9-]{1,30}[a-z0-9]$/;

function requiredString(value: unknown, field: string, maxLength: number): string {
  if (typeof value !== 'string' || !value.trim()) {
    throw new HttpsError('invalid-argument', `${field} is required.`);
  }
  const normalized = value.trim();
  if (normalized.length > maxLength) {
    throw new HttpsError('invalid-argument', `${field} must be at most ${maxLength} characters.`);
  }
  return normalized;
}

export function normalizeTenantCode(value: unknown): string {
  const code = requiredString(value, 'tenantCode', 20).toLowerCase();
  if (!TENANT_CODE.test(code)) {
    throw new HttpsError(
      'invalid-argument',
      'tenantCode must be 3-20 lowercase letters, numbers, or hyphens and start with a letter.'
    );
  }
  return code;
}

export function validateOnboardingInput(data: unknown): TenantOnboardingInput {
  const value = (data ?? {}) as Record<string, unknown>;
  const tenantCode = normalizeTenantCode(value.tenantCode);
  const businessName = requiredString(value.businessName, 'businessName', 100);
  const ownerEmail = requiredString(value.ownerEmail, 'ownerEmail', 254).toLowerCase();
  if (!EMAIL.test(ownerEmail)) {
    throw new HttpsError('invalid-argument', 'ownerEmail is not a valid email address.');
  }

  let firestoreRegion: string | undefined;
  if (value.firestoreRegion !== undefined && value.firestoreRegion !== null) {
    firestoreRegion = requiredString(value.firestoreRegion, 'firestoreRegion', 32).toLowerCase();
    if (!REGION.test(firestoreRegion)) {
      throw new HttpsError('invalid-argument', 'firestoreRegion is not a valid region identifier.');
    }
  }

  return { tenantCode, businessName, ownerEmail, firestoreRegion };
}

export function generateProjectId(tenantCode: string): string {
  const suffix = randomBytes(4).toString('hex');
  const prefix = `pos-${tenantCode}`.slice(0, 21).replace(/-+$/g, '');
  return `${prefix}-${suffix}`;
}
