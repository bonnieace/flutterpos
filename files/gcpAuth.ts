import { applicationDefault } from 'firebase-admin/app';

export class GoogleApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly responseBody: unknown,
    message: string
  ) {
    super(message);
    this.name = 'GoogleApiError';
  }
}

async function getAccessToken(): Promise<string> {
  const token = await applicationDefault().getAccessToken();
  if (!token.access_token) {
    throw new Error('Failed to obtain a control-plane service-account access token.');
  }
  return token.access_token;
}

export async function gfetch<T = unknown>(url: string, init: RequestInit = {}): Promise<T> {
  const token = await getAccessToken();
  const response = await fetch(url, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new GoogleApiError(
      response.status,
      body,
      `${init.method ?? 'GET'} ${url} -> ${response.status}: ${JSON.stringify(body)}`
    );
  }
  return body as T;
}

export function isGoogleApiStatus(error: unknown, ...statuses: number[]): boolean {
  return error instanceof GoogleApiError && statuses.includes(error.status);
}

export async function pollOperation<T = unknown>(
  operationUrl: string,
  { intervalMs = 3000, timeoutMs = 8 * 60 * 1000 } = {}
): Promise<T> {
  const startedAt = Date.now();
  while (true) {
    const operation = await gfetch<{
      done?: boolean;
      error?: unknown;
      response?: T;
    }>(operationUrl);
    if (operation.done) {
      if (operation.error) {
        throw new Error(`Google operation failed: ${JSON.stringify(operation.error)}`);
      }
      return operation.response as T;
    }
    if (Date.now() - startedAt > timeoutMs) {
      throw new Error(`Google operation timed out after ${timeoutMs}ms: ${operationUrl}`);
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
}

export async function postHook<T>(
  url: string,
  secret: string,
  payload: Record<string, unknown>
): Promise<T> {
  if (!url) throw new Error('A required provisioning hook URL is not configured.');
  if (!secret) throw new Error('A required provisioning hook secret is not configured.');

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${secret}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`Provisioning hook ${url} -> ${response.status}: ${JSON.stringify(body)}`);
  }
  return body as T;
}
