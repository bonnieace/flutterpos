import {App, getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";

/**
 * Empties a Firebase project of everything a run of this app puts in it.
 *
 * **This exists because "clear SIT" is four separate deletions in three
 * consoles**, and the one people forget - Auth - fails in a way that does not
 * look like leftover state. An Auth account that outlives its `users/{uid}`
 * document makes the next signup fail as though signup itself were broken.
 *
 * Firestore, Auth, Storage and the Cloud Tasks queues, in that order. What it
 * deliberately does not touch: Secret Manager, Firestore indexes, Hosting, the
 * scheduler jobs and the deployed functions themselves. Those are configuration
 * and code, not the data a test run leaves behind.
 *
 * **Dry run by default**, like every other CLI here, and `--apply` needs
 * `--project` and `--confirm` to name the same project. The project ID is typed
 * twice on purpose: this is the one script in the repository whose whole job is
 * destroying data, and a shell-history recall with the wrong `--project` should
 * not be one keystroke away from emptying a live project.
 */
export interface Options {
  apply: boolean;
  projectId: string;
  skip: ReadonlySet<Surface>;
  location: string;
}

export const SURFACES = ["firestore", "auth", "storage", "tasks"] as const;
export type Surface = (typeof SURFACES)[number];

function valueAfter(args: string[], flag: string): string | undefined {
  const at = args.indexOf(flag);
  return at < 0 ? undefined : args[at + 1];
}

export function optionsOf(args: string[]): Options {
  const apply = args.includes("--apply");
  const projectId = valueAfter(args, "--project");
  const confirm = valueAfter(args, "--confirm");
  const location = valueAfter(args, "--location") ?? "us-central1";
  if (!projectId || !/^[a-z][a-z0-9-]{4,29}$/.test(projectId)) {
    throw new Error("--project requires one Firebase project ID.");
  }
  if (apply && confirm !== projectId) {
    throw new Error(
      "--apply requires --confirm to repeat the project ID exactly."
    );
  }
  if (!/^[a-z0-9-]{1,40}$/.test(location)) {
    throw new Error("--location requires one Cloud Tasks location ID.");
  }
  const skip = new Set<Surface>();
  for (const surface of SURFACES) {
    if (args.includes(`--skip-${surface}`)) skip.add(surface);
  }
  if (skip.size === SURFACES.length) {
    throw new Error("Every surface is skipped, so there is nothing to do.");
  }
  return {apply, projectId, skip, location};
}

export interface SurfaceReport {
  counted: number;
  deleted: number;
}

function report(counted: number, deleted: number): SurfaceReport {
  return {counted, deleted};
}

/** Root collections, deleted recursively so subcollections go with them. */
async function wipeFirestore(apply: boolean): Promise<SurfaceReport> {
  const db = getFirestore();
  const collections = await db.listCollections();
  if (!apply) return report(collections.length, 0);
  for (const collection of collections) await db.recursiveDelete(collection);
  return report(collections.length, collections.length);
}

/**
 * Every Auth account, 1000 at a time.
 *
 * `deleteUsers` reports per-UID failures rather than throwing, so a partial
 * batch is counted honestly instead of being assumed complete.
 */
async function wipeAuth(apply: boolean): Promise<SurfaceReport> {
  const auth = getAuth();
  let counted = 0;
  if (!apply) {
    let pageToken: string | undefined;
    do {
      const page = await auth.listUsers(1000, pageToken);
      counted += page.users.length;
      pageToken = page.pageToken;
    } while (pageToken !== undefined);
    return report(counted, 0);
  }
  // **Each pass lists from the start rather than paging.** Deleting a page
  // invalidates the token that would have followed it, so the wipe re-lists and
  // stops on the first pass that deletes nothing - which is either an empty
  // project or a page the API refused, and both must end the loop.
  let deleted = 0;
  for (;;) {
    const page = await auth.listUsers(1000);
    if (page.users.length === 0) break;
    counted += page.users.length;
    const result = await auth.deleteUsers(page.users.map((user) => user.uid));
    deleted += result.successCount;
    for (const failure of result.errors) {
      process.stderr.write(
        `Could not delete Auth user: ${failure.error.message}\n`
      );
    }
    if (result.successCount === 0) break;
  }
  return report(counted, deleted);
}

/** Every object in the default bucket. */
async function wipeStorage(apply: boolean): Promise<SurfaceReport> {
  const bucket = getStorage().bucket();
  const [files] = await bucket.getFiles();
  if (!apply) return report(files.length, 0);
  await bucket.deleteFiles({force: true});
  return report(files.length, files.length);
}

interface TaskQueue {
  name: string;
}

/**
 * Purges the Cloud Tasks queues the task-dispatched functions own.
 *
 * Queues are listed rather than named, because the queue ID is the deployed
 * function's ID and a hard-coded list goes stale the first time a function is
 * added. Uses the admin credential directly: `firebase-admin` has no Tasks
 * client, and pulling in `@google-cloud/tasks` for two REST calls would be a
 * dependency for the whole functions package.
 */
async function wipeTasks(
  app: App,
  projectId: string,
  location: string,
  apply: boolean
): Promise<SurfaceReport> {
  const token = await app.options.credential?.getAccessToken();
  if (!token) throw new Error("The admin credential issued no access token.");
  const parent =
    `projects/${projectId}/locations/${location}`;
  const headers = {authorization: `Bearer ${token.access_token}`};
  const listed = await fetch(
    `https://cloudtasks.googleapis.com/v2/${parent}/queues?pageSize=1000`,
    {headers}
  );
  if (!listed.ok) {
    throw new Error(
      `Cloud Tasks queues could not be listed: ${listed.status} ` +
      `${await listed.text()}`
    );
  }
  const queues = ((await listed.json()) as {queues?: TaskQueue[]}).queues ?? [];
  if (!apply) return report(queues.length, 0);
  let deleted = 0;
  for (const queue of queues) {
    const purged = await fetch(
      `https://cloudtasks.googleapis.com/v2/${queue.name}:purge`,
      {method: "POST", headers: {...headers, "content-type": "application/json"}, body: "{}"}
    );
    if (purged.ok) {
      deleted += 1;
      continue;
    }
    process.stderr.write(
      `Could not purge ${queue.name}: ${purged.status} ${await purged.text()}\n`
    );
  }
  return report(queues.length, deleted);
}

/**
 * Fails on the credential before it fails on a delete.
 *
 * Without this the first Firestore call throws "Could not load the default
 * credentials" from inside `google-gax`, six frames deep and with no mention of
 * which of the several ways to supply them this script wants.
 */
async function assertCredentials(app: App): Promise<void> {
  try {
    const token = await app.options.credential?.getAccessToken();
    if (token?.access_token) return;
  } catch {
    // Falls through to the same instruction: an unusable credential and an
    // absent one need the same fix.
  }
  throw new Error(
    "No usable Google credentials. Generate a service-account key in Firebase " +
    "Console -> Project Settings -> Service accounts, then set " +
    "GOOGLE_APPLICATION_CREDENTIALS to its path. The key needs Firestore, " +
    "Firebase Auth, Storage and Cloud Tasks permissions."
  );
}

export async function run(): Promise<void> {
  const options = optionsOf(process.argv.slice(2));
  const app = getApps().length === 0 ?
    initializeApp({projectId: options.projectId}) :
    getApps()[0];
  await assertCredentials(app);
  const summary: Record<string, SurfaceReport | "skipped"> = {};

  summary.firestore = options.skip.has("firestore") ?
    "skipped" : await wipeFirestore(options.apply);
  summary.auth = options.skip.has("auth") ?
    "skipped" : await wipeAuth(options.apply);
  summary.storage = options.skip.has("storage") ?
    "skipped" : await wipeStorage(options.apply);
  summary.tasks = options.skip.has("tasks") ?
    "skipped" :
    await wipeTasks(app, options.projectId, options.location, options.apply);

  process.stdout.write(JSON.stringify({
    mode: options.apply ? "apply" : "dry-run",
    projectId: options.projectId,
    ...summary,
  }) + "\n");
  if (!options.apply) {
    process.stdout.write(
      "Nothing was deleted. Re-run with " +
      `--apply --confirm ${options.projectId} to empty the project.\n`
    );
  }
}

if (require.main === module) {
  run().catch((error: unknown) => {
    process.stderr.write(`${error instanceof Error ? error.message : error}\n`);
    process.exitCode = 1;
  });
}
