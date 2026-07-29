import { initializeApp } from 'firebase/app';
import {
  browserLocalPersistence,
  getAuth,
  onAuthStateChanged,
  setPersistence,
  signInWithEmailAndPassword,
  signOut,
} from 'firebase/auth';
import { initializeAppCheck, ReCaptchaV3Provider } from 'firebase/app-check';
import { getFunctions, httpsCallable } from 'firebase/functions';
import { controlPlaneConfig } from './firebase-config.js';
import './styles.css';

const app = initializeApp(controlPlaneConfig.firebase);
if (controlPlaneConfig.appCheckSiteKey !== 'REPLACE_ME') {
  initializeAppCheck(app, {
    provider: new ReCaptchaV3Provider(controlPlaneConfig.appCheckSiteKey),
    isTokenAutoRefreshEnabled: true,
  });
}

const auth = getAuth(app);
const functions = getFunctions(app, controlPlaneConfig.functionsRegion);
const api = {
  list: httpsCallable(functions, 'listTenants'),
  onboard: httpsCallable(functions, 'onboardTenant'),
  retry: httpsCallable(functions, 'retryTenantProvisioning'),
};

const elements = {
  notice: document.querySelector('#notice'),
  loginPanel: document.querySelector('#login-panel'),
  loginForm: document.querySelector('#login-form'),
  dashboard: document.querySelector('#dashboard'),
  email: document.querySelector('#signed-in-email'),
  signOut: document.querySelector('#sign-out'),
  onboardForm: document.querySelector('#onboard-form'),
  onboardSubmit: document.querySelector('#onboard-submit'),
  rows: document.querySelector('#tenant-rows'),
  refresh: document.querySelector('#refresh'),
};

let refreshTimer;

function showNotice(message, kind = 'info') {
  elements.notice.textContent = message;
  elements.notice.className = `notice ${kind}`;
}

function clearNotice() {
  elements.notice.className = 'notice hidden';
  elements.notice.textContent = '';
}

function readableError(error) {
  return error?.message?.replace(/^Firebase:\s*/i, '') ?? 'Something went wrong.';
}

function statusBadge(status) {
  const badge = document.createElement('span');
  badge.className = `badge ${status}`;
  badge.textContent = status;
  return badge;
}

function cell(text, className) {
  const value = document.createElement('td');
  value.textContent = text ?? '—';
  if (className) value.className = className;
  return value;
}

function renderTenants(tenants) {
  elements.rows.replaceChildren();
  if (!tenants.length) {
    const row = document.createElement('tr');
    const empty = cell('No tenants yet.', 'empty');
    empty.colSpan = 6;
    row.append(empty);
    elements.rows.append(row);
    return;
  }

  for (const tenant of tenants) {
    const row = document.createElement('tr');
    const identity = document.createElement('td');
    const title = document.createElement('strong');
    title.textContent = tenant.businessName;
    const subtitle = document.createElement('small');
    subtitle.textContent = `${tenant.tenantCode} · ${tenant.ownerEmail}`;
    identity.append(title, subtitle);
    row.append(identity, cell(tenant.projectId));

    const status = document.createElement('td');
    status.append(statusBadge(tenant.status));
    row.append(status);

    const step = document.createElement('td');
    const stepName = document.createElement('strong');
    stepName.textContent = tenant.progress?.step ?? '—';
    const stepMessage = document.createElement('small');
    stepMessage.textContent = tenant.error ?? tenant.progress?.message ?? '';
    step.append(stepName, stepMessage);
    row.append(step, cell(tenant.updatedAt ? new Date(tenant.updatedAt).toLocaleString() : '—'));

    const actions = document.createElement('td');
    if (tenant.status === 'error') {
      const retry = document.createElement('button');
      retry.type = 'button';
      retry.className = 'secondary compact';
      retry.textContent = 'Retry';
      retry.addEventListener('click', () => retryTenant(tenant.tenantCode, retry));
      actions.append(retry);
    }
    row.append(actions);
    elements.rows.append(row);
  }
}

async function loadTenants({ quiet = false } = {}) {
  try {
    if (!quiet) elements.refresh.disabled = true;
    const result = await api.list();
    renderTenants(result.data.tenants ?? []);
  } catch (error) {
    if (!quiet) showNotice(readableError(error), 'error');
  } finally {
    elements.refresh.disabled = false;
  }
}

async function retryTenant(tenantCode, button) {
  try {
    button.disabled = true;
    clearNotice();
    await api.retry({ tenantCode });
    showNotice(`Retry queued for ${tenantCode}.`, 'success');
    await loadTenants({ quiet: true });
  } catch (error) {
    showNotice(readableError(error), 'error');
  } finally {
    button.disabled = false;
  }
}

elements.loginForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  clearNotice();
  try {
    await setPersistence(auth, browserLocalPersistence);
    await signInWithEmailAndPassword(
      auth,
      document.querySelector('#login-email').value.trim(),
      document.querySelector('#login-password').value
    );
  } catch (error) {
    showNotice(readableError(error), 'error');
  }
});

elements.onboardForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  clearNotice();
  elements.onboardSubmit.disabled = true;
  try {
    const payload = {
      tenantCode: document.querySelector('#tenant-code').value.trim().toLowerCase(),
      businessName: document.querySelector('#business-name').value.trim(),
      ownerEmail: document.querySelector('#owner-email').value.trim(),
      firestoreRegion: document.querySelector('#firestore-region').value.trim(),
    };
    const result = await api.onboard(payload);
    showNotice(`Provisioning queued for ${result.data.tenantCode}.`, 'success');
    elements.onboardForm.reset();
    document.querySelector('#firestore-region').value = 'africa-south1';
    await loadTenants({ quiet: true });
  } catch (error) {
    showNotice(readableError(error), 'error');
  } finally {
    elements.onboardSubmit.disabled = false;
  }
});

elements.refresh.addEventListener('click', () => loadTenants());
elements.signOut.addEventListener('click', () => signOut(auth));

onAuthStateChanged(auth, async (user) => {
  clearInterval(refreshTimer);
  if (!user) {
    elements.loginPanel.classList.remove('hidden');
    elements.dashboard.classList.add('hidden');
    elements.signOut.classList.add('hidden');
    elements.email.textContent = '';
    return;
  }

  const token = await user.getIdTokenResult(true);
  if (token.claims.role !== 'superAdmin') {
    showNotice('This account does not have the superAdmin claim.', 'error');
    await signOut(auth);
    return;
  }

  elements.loginPanel.classList.add('hidden');
  elements.dashboard.classList.remove('hidden');
  elements.signOut.classList.remove('hidden');
  elements.email.textContent = user.email ?? user.uid;
  await loadTenants();
  refreshTimer = setInterval(() => loadTenants({ quiet: true }), 10000);
});
