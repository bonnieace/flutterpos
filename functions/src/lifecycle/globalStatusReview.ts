import {FieldPath, Firestore, Timestamp} from "firebase-admin/firestore";
import {getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {
  requireAuthenticatedUser,
  requirePlatformAdmin,
} from "../core/authorization";
import {requireDocumentId, requireObject} from "../core/validation";

const LOOKUP_LIMIT = 100;

export interface GetGlobalUserStatusReviewRequest {
  uid?: unknown;
}

interface ReviewDocument {
  id: string;
  data: Record<string, unknown>;
}

interface ReviewStaffDocument extends ReviewDocument {
  tenantId: string;
}

export type GetGlobalUserStatusReviewResponse =
  | {found: false}
  | {
    found: true;
    user: ReviewDocument;
    targetStaff: ReviewStaffDocument[];
    ownedTenants: ReviewDocument[];
    tenants: ReviewDocument[];
    administrativeStaff: ReviewStaffDocument[];
    administrativeRoots: ReviewDocument[];
  };

function safeRootDocument(
  snapshot: FirebaseFirestore.DocumentSnapshot
): ReviewDocument {
  const data = snapshot.data() ?? {};
  return {
    id: snapshot.id,
    data: {
      email: data.email,
      displayName: data.displayName ?? null,
      accountType: data.accountType,
      globalStatus: data.globalStatus,
      updatedAtMillis: data.updatedAt instanceof Timestamp ?
        data.updatedAt.toMillis() : null,
    },
  };
}

function safeTenantDocument(
  snapshot: FirebaseFirestore.DocumentSnapshot
): ReviewDocument {
  const data = snapshot.data() ?? {};
  return {
    id: snapshot.id,
    data: {
      name: data.name,
      slug: data.slug,
      ownerUid: data.ownerUid,
      status: data.status,
    },
  };
}

function tenantIdFromStaffPath(path: string): string | undefined {
  const segments = path.split("/");
  return segments.length === 4 &&
    segments[0] === "tenants" &&
    segments[2] === "staff" ? segments[1] : undefined;
}

function safeStaffDocument(
  snapshot: FirebaseFirestore.QueryDocumentSnapshot,
  expectedTenantId?: string
): ReviewStaffDocument {
  const tenantId = tenantIdFromStaffPath(snapshot.ref.path);
  if (!tenantId || (expectedTenantId && tenantId !== expectedTenantId)) {
    throw new HttpsError("data-loss", "Canonical staff path is invalid.");
  }
  const data = snapshot.data();
  return {
    tenantId,
    id: snapshot.id,
    data: {
      uid: data.uid,
      role: data.role,
      status: data.status,
    },
  };
}

async function requireBoundedQuery(
  query: FirebaseFirestore.Query,
  label: string
): Promise<FirebaseFirestore.QuerySnapshot> {
  const snapshot = await query.limit(LOOKUP_LIMIT + 1).get();
  if (snapshot.size > LOOKUP_LIMIT) {
    throw new HttpsError(
      "resource-exhausted",
      `${label} exceeds the exact-review limit.`
    );
  }
  return snapshot;
}

async function loadAdministrativeStaff(
  db: Firestore,
  tenantIds: readonly string[]
): Promise<ReviewStaffDocument[]> {
  const result: ReviewStaffDocument[] = [];
  for (let offset = 0; offset < tenantIds.length; offset += 10) {
    const batch = tenantIds.slice(offset, offset + 10);
    const snapshots = await Promise.all(batch.map((tenantId) =>
      requireBoundedQuery(
        db.collection("tenants").doc(tenantId).collection("staff")
          .where("role", "in", ["owner", "admin"]),
        "Administrative staff"
      )
    ));
    snapshots.forEach((snapshot, index) => {
      result.push(...snapshot.docs.map((document) =>
        safeStaffDocument(document, batch[index])
      ));
    });
  }
  return result;
}

export async function getGlobalUserStatusReviewCore(
  db: Firestore,
  uid: string
): Promise<GetGlobalUserStatusReviewResponse> {
  const root = await db.collection("users").doc(uid).get();
  if (!root.exists) return {found: false};
  const [staffSnapshot, ownerSnapshot] = await Promise.all([
    requireBoundedQuery(
      db.collectionGroup("staff")
        .where("uid", "==", uid)
        .orderBy(FieldPath.documentId()),
      "Canonical memberships"
    ),
    requireBoundedQuery(
      db.collection("tenants")
        .where("ownerUid", "==", uid)
        .orderBy(FieldPath.documentId()),
      "Canonical ownerships"
    ),
  ]);
  const targetStaff = staffSnapshot.docs
    .filter((document) => tenantIdFromStaffPath(document.ref.path) !== undefined)
    .map((document) => safeStaffDocument(document));
  const ownedTenants = ownerSnapshot.docs.map(safeTenantDocument);
  const tenantIds = new Set<string>(ownedTenants.map((tenant) => tenant.id));
  targetStaff.forEach((staff) => tenantIds.add(staff.tenantId));
  if (tenantIds.size > LOOKUP_LIMIT) {
    throw new HttpsError(
      "resource-exhausted",
      "Canonical tenant relationships exceed the exact-review limit."
    );
  }
  const missingTenantIds = [...tenantIds]
    .filter((tenantId) => !ownedTenants.some((tenant) => tenant.id === tenantId))
    .sort();
  const missingSnapshots = missingTenantIds.length > 0 ? await db.getAll(
    ...missingTenantIds.map((tenantId) => db.collection("tenants").doc(tenantId))
  ) : [];
  const tenants = [
    ...ownedTenants,
    ...missingSnapshots.filter((snapshot) => snapshot.exists)
      .map(safeTenantDocument),
  ].sort((left, right) => left.id.localeCompare(right.id));
  const administrativeStaff = await loadAdministrativeStaff(
    db,
    [...tenantIds].sort()
  );
  const administrativeUids = [...new Set(administrativeStaff
    .map((staff) => staff.id)
    .filter((staffUid) => staffUid !== uid))].sort();
  const administrativeRootSnapshots = administrativeUids.length > 0 ?
    await db.getAll(...administrativeUids.map((staffUid) =>
      db.collection("users").doc(staffUid)
    )) : [];
  return {
    found: true,
    user: safeRootDocument(root),
    targetStaff,
    ownedTenants,
    tenants,
    administrativeStaff,
    administrativeRoots: administrativeRootSnapshots
      .filter((snapshot) => snapshot.exists)
      .map(safeRootDocument),
  };
}

export const getGlobalUserStatusReview = onCall<
  GetGlobalUserStatusReviewRequest,
  Promise<GetGlobalUserStatusReviewResponse>
>(async (request: CallableRequest<GetGlobalUserStatusReviewRequest>) => {
  requireAuthenticatedUser(request, {allowUnverified: true});
  const data = requireObject(request.data);
  const uid = requireDocumentId(data.uid, "uid");
  const db = getFirestore();
  await requirePlatformAdmin(db, request);
  return getGlobalUserStatusReviewCore(db, uid);
});
