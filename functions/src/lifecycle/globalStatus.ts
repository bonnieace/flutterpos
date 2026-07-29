import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {
  requireAuthenticatedUser,
  requirePlatformAdmin,
} from "../core/authorization";
import {GLOBAL_STATUSES, GlobalStatus} from "../core/model";
import {
  requireDocumentId,
  requireObject,
  requireRequestId,
  requireString,
} from "../core/validation";
import {
  GlobalOperationStatus,
  GlobalUserStatusInput,
  runGlobalUserStatusSaga,
} from "./globalStatusCore";
import {createGlobalStatusSagaAdapter} from "./globalStatusStore";

export interface SetGlobalUserStatusRequest {
  uid?: unknown;
  status?: unknown;
  reason?: unknown;
  requestId?: unknown;
}

export interface SetGlobalUserStatusResponse {
  operationId: string;
  uid: string;
  status: GlobalOperationStatus;
  targetStatus: GlobalStatus;
  affectedTenantIds: readonly string[];
  attemptCount: number;
  lastErrorCode?: string;
}

export function requireGlobalStatus(value: unknown): GlobalStatus {
  if (typeof value !== "string" || !GLOBAL_STATUSES.includes(value as GlobalStatus)) {
    throw new HttpsError("invalid-argument", "status is not a supported global status.");
  }
  return value as GlobalStatus;
}

export function globalStatusResponse(
  operation: Awaited<ReturnType<typeof runGlobalUserStatusSaga>>
): SetGlobalUserStatusResponse {
  return {
    operationId: operation.requestId,
    uid: operation.uid,
    status: operation.status,
    targetStatus: operation.targetStatus,
    affectedTenantIds: operation.affectedTenantIds,
    attemptCount: operation.attemptCount,
    ...(operation.lastErrorCode ? {lastErrorCode: operation.lastErrorCode} : {}),
  };
}

export const setGlobalUserStatus = onCall<
  SetGlobalUserStatusRequest,
  Promise<SetGlobalUserStatusResponse>
>(async (
  request: CallableRequest<SetGlobalUserStatusRequest>
): Promise<SetGlobalUserStatusResponse> => {
  const authContext = requireAuthenticatedUser(request, {allowUnverified: true});
  const data = requireObject(request.data);
  const uid = requireDocumentId(data.uid, "uid");
  const targetStatus = requireGlobalStatus(data.status);
  const reason = requireString(data.reason, "reason", {minLength: 3, maxLength: 1000});
  const requestId = requireRequestId(data.requestId);
  const db = getFirestore();
  await requirePlatformAdmin(db, request);
  const input: GlobalUserStatusInput = {
    uid,
    targetStatus,
    requestedBy: authContext.uid,
    reason,
    requestId,
  };
  const operation = await runGlobalUserStatusSaga(
    createGlobalStatusSagaAdapter({
      db,
      auth: getAuth(),
      actorPlatformRole: authContext.token.platformRole,
      actorAuthTime: authContext.token.auth_time,
    }),
    input
  );
  return globalStatusResponse(operation);
});
