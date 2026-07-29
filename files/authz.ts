import { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

export function requireSuperAdmin(request: CallableRequest<unknown>): string {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in to the control plane first.');
  }
  if (request.auth.token.role !== 'superAdmin') {
    throw new HttpsError('permission-denied', 'A superAdmin account is required.');
  }
  return request.auth.uid;
}
