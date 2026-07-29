import {
  DocumentData,
  DocumentReference,
  FieldPath,
  FieldValue,
  getFirestore,
  Query,
  Timestamp,
} from "firebase-admin/firestore";
import {defineSecret} from "firebase-functions/params";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {
  assertActiveRootUser,
  requireAuthenticatedUser,
  requireTenantMember,
} from "../core/authorization";
import {runIdempotentFirestoreTransaction} from "../core/idempotency";
import {RootUserRecord} from "../core/model";
import {
  optionalPageSize,
  optionalString,
  requireDocumentId,
  requireObject,
  requireRequestId,
} from "../core/validation";
import {
  decodeTenantCursor,
  encodeTenantCursor,
  InvalidTenantCursorError,
  InvalidTenantCursorSecretError,
  TenantCursorPosition,
} from "./cursor";
import {
  CanonicalStaffOverlayRecord,
  overlayCanonicalTenantState,
  TenantListItem,
  TenantMirrorRecord,
  TenantOverlayRecord,
} from "./overlay";

const TENANT_CURSOR_HMAC_SECRET = defineSecret("TENANT_CURSOR_HMAC_SECRET");

interface ListMyTenantsRequest {
  pageSize?: unknown;
  cursor?: unknown;
}

interface ListMyTenantsResponse {
  items: TenantListItem[];
  nextCursor: string | null;
  hasMore: boolean;
}

interface SetDefaultTenantRequest {
  tenantId?: unknown;
  requestId?: unknown;
}

interface SetDefaultTenantResponse {
  tenantId: string;
  defaultTenantId: string;
}

function requestData(value: unknown): Record<string, unknown> {
  return value === undefined || value === null ? {} : requireObject(value);
}

function cursorSecret(): string {
  const secret = TENANT_CURSOR_HMAC_SECRET.value();
  if (Buffer.byteLength(secret, "utf8") < 32) {
    throw new HttpsError(
      "failed-precondition",
      "Tenant pagination is not configured."
    );
  }
  return secret;
}

function decodeCursor(
  cursor: string | undefined,
  uid: string,
  secret: string
): TenantCursorPosition | undefined {
  if (!cursor) return undefined;
  try {
    return decodeTenantCursor(cursor, uid, secret);
  } catch (error) {
    if (error instanceof InvalidTenantCursorError) {
      throw new HttpsError("invalid-argument", error.message);
    }
    if (error instanceof InvalidTenantCursorSecretError) {
      throw new HttpsError("failed-precondition", "Tenant pagination is not configured.");
    }
    throw error;
  }
}

function timestampPosition(value: unknown, tenantId: string): TenantCursorPosition {
  if (!(value instanceof Timestamp)) {
    throw new HttpsError(
      "internal",
      "A tenant membership has an invalid pagination timestamp."
    );
  }
  return {
    createdAtSeconds: value.seconds,
    createdAtNanoseconds: value.nanoseconds,
    tenantId,
  };
}

export const listMyTenants = onCall<ListMyTenantsRequest, Promise<ListMyTenantsResponse>>(
  {secrets: [TENANT_CURSOR_HMAC_SECRET]},
  async (request: CallableRequest<ListMyTenantsRequest>): Promise<ListMyTenantsResponse> => {
    const auth = requireAuthenticatedUser(request, {allowUnverified: true});
    const data = requestData(request.data);
    const pageSize = optionalPageSize(data.pageSize, 20, 50);
    const cursor = optionalString(data.cursor, "cursor", {maxLength: 2048});
    const secret = cursorSecret();
    const position = decodeCursor(cursor, auth.uid, secret);
    const db = getFirestore();
    const userRef = db.collection("users").doc(auth.uid);
    let membershipQuery: Query<DocumentData> = userRef
      .collection("tenant_memberships")
      .orderBy("createdAt", "desc")
      .orderBy(FieldPath.documentId(), "asc")
      .limit(pageSize + 1);
    if (position) {
      membershipQuery = membershipQuery.startAfter(
        new Timestamp(position.createdAtSeconds, position.createdAtNanoseconds),
        position.tenantId
      );
    }

    const [membershipSnapshot, userSnapshot] = await Promise.all([
      membershipQuery.get(),
      userRef.get(),
    ]);
    const hasMore = membershipSnapshot.docs.length > pageSize;
    const pageDocuments = membershipSnapshot.docs.slice(0, pageSize);
    const canonicalReferences: DocumentReference<DocumentData>[] = [];
    for (const membershipDocument of pageDocuments) {
      const tenantRef = db.collection("tenants").doc(membershipDocument.id);
      canonicalReferences.push(tenantRef, tenantRef.collection("staff").doc(auth.uid));
    }
    const canonicalSnapshots = canonicalReferences.length > 0 ?
      await db.getAll(canonicalReferences[0], ...canonicalReferences.slice(1)) :
      [];
    const user = assertActiveRootUser(
      auth.uid,
      userSnapshot.exists ? userSnapshot.data() as RootUserRecord : undefined
    );
    if (user.accountType !== "tenant_user") {
      throw new HttpsError(
        "permission-denied",
        "Platform identities cannot have tenant memberships."
      );
    }
    const items = pageDocuments.map((membershipDocument, index) => {
      const tenantSnapshot = canonicalSnapshots[index * 2];
      const staffSnapshot = canonicalSnapshots[index * 2 + 1];
      return overlayCanonicalTenantState(
        auth.uid,
        membershipDocument.id,
        membershipDocument.data() as TenantMirrorRecord,
        user,
        tenantSnapshot?.exists ? tenantSnapshot.data() as TenantOverlayRecord : undefined,
        staffSnapshot?.exists ? staffSnapshot.data() as CanonicalStaffOverlayRecord : undefined
      );
    });

    let nextCursor: string | null = null;
    if (hasMore && pageDocuments.length > 0) {
      const lastDocument = pageDocuments[pageDocuments.length - 1];
      nextCursor = encodeTenantCursor(
        auth.uid,
        timestampPosition(lastDocument.get("createdAt"), lastDocument.id),
        secret
      );
    }
    return {items, nextCursor, hasMore};
  }
);

export const setDefaultTenant = onCall<SetDefaultTenantRequest, Promise<SetDefaultTenantResponse>>(
  async (
    request: CallableRequest<SetDefaultTenantRequest>
  ): Promise<SetDefaultTenantResponse> => {
    const auth = requireAuthenticatedUser(request, {allowUnverified: true});
    const data = requireObject(request.data);
    const tenantId = requireDocumentId(data.tenantId, "tenantId");
    const requestId = requireRequestId(data.requestId);
    const db = getFirestore();

    return runIdempotentFirestoreTransaction(db, {
      actorUid: auth.uid,
      operation: "setDefaultTenant",
      tenantId,
      requestId,
      input: {tenantId},
    }, async (transaction) => {
      // This canonical authorization read is deliberately inside the same
      // transaction that persists both the default and its idempotency result.
      await requireTenantMember(db, request, tenantId, undefined, transaction);
      transaction.update(db.collection("users").doc(auth.uid), {
        defaultTenantId: tenantId,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {tenantId, defaultTenantId: tenantId};
    });
  }
);
