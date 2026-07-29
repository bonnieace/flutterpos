import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

const [email] = process.argv.slice(2);
const projectId = process.env.CONTROL_PLANE_PROJECT_ID;

if (!email || !projectId) {
  console.error(
    'Usage: set CONTROL_PLANE_PROJECT_ID and run: npm run grant-super-admin -- admin@example.com'
  );
  process.exitCode = 1;
} else {
  const app = initializeApp({ credential: applicationDefault(), projectId });
  const auth = getAuth(app);
  const user = await auth.getUserByEmail(email.trim().toLowerCase());
  const existing = user.customClaims ?? {};
  await auth.setCustomUserClaims(user.uid, { ...existing, role: 'superAdmin' });
  console.log(`Granted superAdmin to ${user.email} (${user.uid}) in ${projectId}.`);
}
