import {getAuth} from "firebase-admin/auth";
import {
  FieldValue,
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {
  assertVerifiedAuthIdentity,
  requireAuthenticatedUser,
  requireVerifiedTenantApplicant,
} from "../core/authorization";
import {runIdempotentFirestoreTransaction} from "../core/idempotency";
import {
  requireObject,
  requireRequestId,
  requireString,
} from "../core/validation";
import {staffSearchFields} from "../staff/search";
import {
  findTenantLimitViolation,
  resolveTenantLimits,
  TenantLimitViolation,
} from "./limits";

const TENANT_NAME_MIN_LENGTH = 2;
const TENANT_NAME_MAX_LENGTH = 100;
const TENANT_SLUG_MIN_LENGTH = 3;
const TENANT_SLUG_MAX_LENGTH = 48;
const TENANT_SLUG_PATTERN = /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])$/;
const TENANT_CURRENCY_PATTERN = /^[A-Z]{3}$/;
const REQUEST_WINDOW_MILLISECONDS = 24 * 60 * 60 * 1000;

/**
 * How long a self-serve request may trade before somebody has approved it.
 *
 * **Set once, here, and never moved.** A window that could be extended would be
 * a second way to grant access, reachable without the platform console and
 * without the audit trail `setTenantLifecycle` writes. Approval is the only way
 * out of it that adds time; everything else lets it run down.
 *
 * `firestore.rules` and `assertTenantMemberDocuments` both compare against the
 * instant this produces. Neither of them can compute it, which is why it is
 * written onto the tenant rather than derived from `createdAt` in two places.
 */
const PROVISIONAL_WINDOW_MILLISECONDS = 7 * 24 * 60 * 60 * 1000;

interface RequestTenantRequest {
  name?: unknown;
  slug?: unknown;
  currency?: unknown;
  requestId?: unknown;
}

interface RequestTenantResponse {
  tenantId: string;
  name: string;
  slug: string;
  currency: string;
  status: "pending";
}

function normalizeTenantName(value: unknown): string {
  const name = requireString(value, "name", {
    minLength: TENANT_NAME_MIN_LENGTH,
    maxLength: TENANT_NAME_MAX_LENGTH,
  }).replace(/\s+/g, " ");
  if (/\p{Cc}/u.test(name)) {
    throw new HttpsError("invalid-argument", "name contains unsupported characters.");
  }
  return name;
}

function normalizeTenantSlug(value: unknown): string {
  const slug = requireString(value, "slug", {
    minLength: TENANT_SLUG_MIN_LENGTH,
    maxLength: TENANT_SLUG_MAX_LENGTH,
  }).toLowerCase();
  if (!TENANT_SLUG_PATTERN.test(slug) || slug.includes("--")) {
    throw new HttpsError(
      "invalid-argument",
      "slug must contain only lower-case letters, numbers, and single hyphens."
    );
  }
  return slug;
}

/**
 * The ISO 4217 code the new business will trade in.
 *
 * **Asked for at creation because the alternative is a till that refuses every
 * sale.** `TenantCheckoutConfiguration` fails closed on a missing or malformed
 * currency and `tenant_setup_checklist.dart` exists to explain that state to a
 * brand-new owner - so a business born without one is born broken, and the
 * checklist's first item is an apology for this parameter not existing.
 *
 * The rule is deliberately the same one
 * `TenantCheckoutConfigurationPublisher.buildUpdateIntent` applies on the client:
 * three letters, upper-cased, because an ISO 4217 code has exactly one casing
 * and `kes` is a spelling of `KES` rather than a different setting.
 */
function normalizeTenantCurrency(value: unknown): string {
  const currency = requireString(value, "currency", {
    minLength: 3,
    maxLength: 3,
  }).toUpperCase();
  if (!TENANT_CURRENCY_PATTERN.test(currency)) {
    throw new HttpsError(
      "invalid-argument",
      "currency must be a three-letter ISO 4217 code."
    );
  }
  return currency;
}

/**
 * The owner's own number, or an empty string where there is not one to copy.
 *
 * Absent on every account created before signup asked for a phone, which is why
 * this degrades to the `""` this field held unconditionally until now rather
 * than refusing the request.
 */
function ownerPhone(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function advisoryCounter(value: unknown): number {
  return Number.isSafeInteger(value) && (value as number) >= 0 ? value as number : 0;
}

function throwLimitViolation(violation: TenantLimitViolation, limit: number): never {
  const messages: Record<TenantLimitViolation, string> = {
    max_pending_tenants: "The pending tenant request limit has been reached.",
    max_requests_per_24_hours: "The tenant request rate limit has been reached.",
    max_owned_active_tenants: "The active owned tenant limit has been reached.",
  };
  throw new HttpsError("resource-exhausted", messages[violation], {violation, limit});
}

function configuredLimitForViolation(
  violation: TenantLimitViolation,
  limits: ReturnType<typeof resolveTenantLimits>
): number {
  switch (violation) {
  case "max_pending_tenants":
    return limits.maxPendingTenantsPerUser;
  case "max_requests_per_24_hours":
    return limits.maxTenantRequestsPer24Hours;
  case "max_owned_active_tenants":
    return limits.maxOwnedActiveTenantsPerUser;
  }
}

export const requestTenant = onCall<RequestTenantRequest, Promise<RequestTenantResponse>>(
  async (request: CallableRequest<RequestTenantRequest>): Promise<RequestTenantResponse> => {
    const auth = requireAuthenticatedUser(request, {allowUnverified: true});
    // The Auth record, not the token: somebody who has just followed the link in
    // their mailbox still holds a token minted at sign-in that says otherwise,
    // for up to an hour. Read outside the transaction below, because a network
    // call inside one lengthens it and is re-issued on every contention retry.
    let authIdentity;
    try {
      authIdentity = await getAuth().getUser(auth.uid);
    } catch {
      throw new HttpsError("failed-precondition", "The current identity is unavailable.");
    }
    assertVerifiedAuthIdentity(auth.uid, authIdentity);
    const data = requireObject(request.data);
    const name = normalizeTenantName(data.name);
    const slug = normalizeTenantSlug(data.slug);
    const currency = normalizeTenantCurrency(data.currency);
    const requestId = requireRequestId(data.requestId);
    const db = getFirestore();
    const tenantRef = db.collection("tenants").doc();
    const requestedAt = Timestamp.now();
    const requestWindowStart = Timestamp.fromMillis(
      requestedAt.toMillis() - REQUEST_WINDOW_MILLISECONDS
    );
    const provisionalUntil = Timestamp.fromMillis(
      requestedAt.toMillis() + PROVISIONAL_WINDOW_MILLISECONDS
    );

    return runIdempotentFirestoreTransaction(db, {
      actorUid: auth.uid,
      operation: "requestTenant",
      requestId,
      input: {name, slug, currency},
    }, async (transaction) => {
      // Root eligibility is checked transactionally so identityTransition cannot
      // race this tenant creation.
      const applicant = await requireVerifiedTenantApplicant(db, request, transaction);
      const userRef = db.collection("users").doc(applicant.uid);
      const limitsSnapshot = await transaction.get(
        db.collection("platform_config").doc("limits")
      );
      const limits = resolveTenantLimits(limitsSnapshot.exists ? limitsSnapshot.data() : undefined);

      // These canonical queries intentionally ignore all root counters and mirrors.
      const pendingSnapshot = await transaction.get(
        db.collection("tenants")
          .where("ownerUid", "==", applicant.uid)
          .where("status", "==", "pending")
          .limit(Math.max(1, limits.maxPendingTenantsPerUser))
      );
      const activeOwnedSnapshot = await transaction.get(
        db.collection("tenants")
          .where("ownerUid", "==", applicant.uid)
          .where("status", "==", "active")
          .limit(Math.max(1, limits.maxOwnedActiveTenantsPerUser))
      );
      const recentRequestSnapshot = await transaction.get(
        userRef.collection("tenant_request_events")
          .where("createdAt", ">=", requestWindowStart)
          .limit(Math.max(1, limits.maxTenantRequestsPer24Hours))
      );
      const slugRef = db.collection("tenant_slugs").doc(slug);
      const slugSnapshot = await transaction.get(slugRef);

      const violation = findTenantLimitViolation({
        pendingTenants: pendingSnapshot.size,
        requestsInLast24Hours: recentRequestSnapshot.size,
        ownedActiveTenants: activeOwnedSnapshot.size,
      }, limits);
      if (violation) {
        throwLimitViolation(violation, configuredLimitForViolation(violation, limits));
      }
      if (slugSnapshot.exists) {
        throw new HttpsError("already-exists", "That tenant slug is already in use.");
      }

      // The verified Auth token is authoritative for the shared identity email;
      // the root-user copy is routing/profile data and may be stale.
      const ownerEmail = typeof auth.token.email === "string" ?
        auth.token.email.trim().toLowerCase() :
        "";
      if (!ownerEmail) {
        throw new HttpsError(
          "failed-precondition",
          "The verified account does not have an email address."
        );
      }
      const tokenName = typeof auth.token.name === "string" ? auth.token.name : "";
      const ownerName = (applicant.user.displayName ?? tokenName).trim();
      const staffRef = tenantRef.collection("staff").doc(applicant.uid);
      const checkoutRef = tenantRef.collection("configuration").doc("checkout");
      const mirrorRef = userRef.collection("tenant_memberships").doc(tenantRef.id);
      const lifecycleRef = tenantRef.collection("lifecycle_history").doc(requestId);
      const auditRef = tenantRef.collection("audit_logs").doc(requestId);
      const rateEventRef = userRef.collection("tenant_request_events").doc(tenantRef.id);
      const platformAuditRef = db.collection("platform_audit_logs").doc(tenantRef.id);

      transaction.create(tenantRef, {
        name,
        slug,
        status: "pending",
        ownerUid: applicant.uid,
        requestedBy: applicant.uid,
        // The provisional trading window. A client clock never sees this: it is
        // computed from `Timestamp.now()` on the server and compared against
        // `request.time` in the rules.
        provisionalUntil,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      // Exactly the keys the client publisher writes - `currency` and
      // `updatedBy` from `documentData()`, plus the server `updatedAt` its
      // writer adds - so the strict read model parses this and the settings
      // screen replaces it without noticing it was seeded rather than typed.
      transaction.create(checkoutRef, {
        currency,
        updatedBy: applicant.uid,
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(staffRef, {
        uid: applicant.uid,
        email: ownerEmail,
        name: ownerName,
        phone: ownerPhone(applicant.user.phone),
        role: "owner",
        status: "active",
        invitationStatus: "accepted",
        ...staffSearchFields(ownerName, ownerEmail),
        createdAt: FieldValue.serverTimestamp(),
        joinedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(mirrorRef, {
        tenantId: tenantRef.id,
        tenantName: name,
        tenantSlug: slug,
        role: "owner",
        membershipStatus: "active",
        tenantStatus: "pending",
        // Mirrored so the app can tell a window that is still open from one
        // that has shut without reading the tenant document first - the
        // selector draws that difference before any tenant is opened.
        provisionalUntil,
        invitationStatus: "accepted",
        isOwner: true,
        createdAt: FieldValue.serverTimestamp(),
        joinedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        mirrorVersion: 1,
      });
      transaction.update(userRef, {
        membershipCount: advisoryCounter(applicant.user.membershipCount) + 1,
        ownedTenantCount: advisoryCounter(applicant.user.ownedTenantCount) + 1,
        ownedActiveTenantCount: advisoryCounter(applicant.user.ownedActiveTenantCount),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(slugRef, {
        tenantId: tenantRef.id,
        slug,
        createdBy: applicant.uid,
        createdAt: FieldValue.serverTimestamp(),
      });
      transaction.create(lifecycleRef, {
        tenantId: tenantRef.id,
        eventType: "tenant_requested",
        fromStatus: null,
        toStatus: "pending",
        provisionalUntil,
        actorUid: applicant.uid,
        requestId,
        createdAt: FieldValue.serverTimestamp(),
      });
      transaction.create(auditRef, {
        tenantId: tenantRef.id,
        eventType: "tenant_requested",
        actorUid: applicant.uid,
        requestId,
        createdAt: FieldValue.serverTimestamp(),
      });
      transaction.create(platformAuditRef, {
        tenantId: tenantRef.id,
        eventType: "tenant_requested",
        actorUid: applicant.uid,
        requestId,
        createdAt: FieldValue.serverTimestamp(),
      });
      // The document ID is the successful canonical tenant ID and create()
      // keeps the rolling-window ledger immutable and one-record-per-request.
      transaction.create(rateEventRef, {
        tenantId: tenantRef.id,
        actorUid: applicant.uid,
        requestId,
        eventType: "tenant_requested",
        createdAt: requestedAt,
      });

      return {
        tenantId: tenantRef.id,
        name,
        slug,
        currency,
        status: "pending",
        provisionalUntil: provisionalUntil.toMillis(),
      };
    });
  }
);
