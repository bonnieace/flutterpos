import {getFunctions} from "firebase-admin/functions";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onTaskDispatched} from "firebase-functions/v2/tasks";
import {
  createTargetedTenantRepair,
  createTargetedUserRepair,
  createWeeklyFullRepair,
  listResumableMembershipRepairs,
  processMembershipRepairPage,
  recordMembershipRepairFailure,
} from "./membershipMirrorStore";
import {
  executeMembershipRepairTask,
  membershipRepairTaskId,
  RepairTaskPayload,
  RepairTaskRuntime,
} from "./repairRun";

const REPAIR_TASK_FUNCTION = "runMembershipRepairTask";

function taskAlreadyExists(error: unknown): boolean {
  if (!error || typeof error !== "object" || !("code" in error)) return false;
  const code = (error as {code?: unknown}).code;
  return code === "functions/task-already-exists" ||
    code === "already-exists" ||
    code === 6;
}

export async function enqueueMembershipRepairTask(
  payload: RepairTaskPayload
): Promise<void> {
  try {
    await getFunctions().taskQueue<RepairTaskPayload>(REPAIR_TASK_FUNCTION).enqueue(
      payload,
      {
        id: membershipRepairTaskId(payload),
        dispatchDeadlineSeconds: 300,
      }
    );
  } catch (error) {
    if (!taskAlreadyExists(error)) throw error;
  }
}

function deployedRuntime(): RepairTaskRuntime {
  const db = getFirestore();
  return {
    process: (payload) => processMembershipRepairPage(db, payload),
    enqueue: enqueueMembershipRepairTask,
    recordFailure: (payload, error) =>
      recordMembershipRepairFailure(db, payload, error),
  };
}

/** Private Cloud Tasks worker. Every dispatch advances at most one bounded page. */
export const runMembershipRepairTask = onTaskDispatched<RepairTaskPayload>({
  retryConfig: {
    maxAttempts: 10,
    minBackoffSeconds: 10,
    maxBackoffSeconds: 600,
    maxDoublings: 5,
  },
  rateLimits: {
    maxConcurrentDispatches: 10,
    maxDispatchesPerSecond: 20,
  },
  timeoutSeconds: 300,
}, async (request) => {
  await executeMembershipRepairTask(deployedRuntime(), request.data);
});

/** Consumes the durable fan-out record created by setTenantLifecycle. */
export const consumeTenantMembershipFanout = onDocumentCreated(
  "tenants/{tenantId}/membership_fanout_jobs/{operationId}",
  async (event) => {
    const tenantId = event.params.tenantId;
    const operationId = event.params.operationId;
    const sourceJobPath = event.data?.ref.path;
    if (!sourceJobPath) return;
    const payload = await createTargetedTenantRepair(
      getFirestore(),
      tenantId,
      `lifecycle:${tenantId}:${operationId}`,
      {sourceJobPath, sourceOperationId: operationId}
    );
    await event.data?.ref.set({
      repairRunId: payload.runId,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    await enqueueMembershipRepairTask(payload);
  }
);

/** Canonical staff writes get an independently resumable verification pass. */
export const repairCanonicalStaffMirror = onDocumentWritten(
  "tenants/{tenantId}/staff/{uid}",
  async (event) => {
    const payload = await createTargetedUserRepair(
      getFirestore(),
      event.params.uid,
      `staff-event:${event.id}`
    );
    await enqueueMembershipRepairTask(payload);
  }
);

/**
 * Covers tenant name/slug/owner changes not accompanied by a lifecycle job.
 * Lifecycle writes are consumed through their purpose-built fan-out document.
 */
export const repairTenantRoutingProjection = onDocumentUpdated(
  "tenants/{tenantId}",
  async (event) => {
    const before = event.data?.before.data() ?? {};
    const after = event.data?.after.data() ?? {};
    const routingChanged = before.name !== after.name ||
      before.slug !== after.slug ||
      before.status !== after.status ||
      before.ownerUid !== after.ownerUid;
    if (!routingChanged) return;
    const lifecycleJobCreated = after.membershipFanoutStatus === "pending" &&
      typeof after.membershipFanoutOperationId === "string" &&
      after.membershipFanoutOperationId !== before.membershipFanoutOperationId;
    if (lifecycleJobCreated) return;
    const payload = await createTargetedTenantRepair(
      getFirestore(),
      event.params.tenantId,
      `tenant-event:${event.id}`
    );
    await enqueueMembershipRepairTask(payload);
  }
);

function nairobiLocalDate(instant: string): string {
  const formatter = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Africa/Nairobi",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const parts = Object.fromEntries(
    formatter.formatToParts(new Date(instant)).map((part) => [part.type, part.value])
  );
  return `${parts.year}-${parts.month}-${parts.day}`;
}

/** Starts one deterministic discovery run each Sunday in the product timezone. */
export const startWeeklyMembershipRepair = onSchedule({
  schedule: "15 3 * * 0",
  timeZone: "Africa/Nairobi",
  retryCount: 3,
}, async (event) => {
  const payload = await createWeeklyFullRepair(
    getFirestore(),
    nairobiLocalDate(event.scheduleTime)
  );
  await enqueueMembershipRepairTask(payload);
});

/** Recovers a page committed before enqueue and leases left by crashed workers. */
export const retryMembershipRepairTasks = onSchedule({
  schedule: "every 10 minutes",
  retryCount: 1,
}, async () => {
  const tasks = await listResumableMembershipRepairs(getFirestore(), 100);
  await Promise.all(tasks.map(enqueueMembershipRepairTask));
});
