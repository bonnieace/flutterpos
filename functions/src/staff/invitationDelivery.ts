import {randomUUID} from "node:crypto";
import {getAuth} from "firebase-admin/auth";
import {getFunctions} from "firebase-admin/functions";
import {
  DocumentReference,
  DocumentSnapshot,
  FieldPath,
  FieldValue,
  Firestore,
  getFirestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {defineString} from "firebase-functions/params";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onTaskDispatched} from "firebase-functions/v2/tasks";
import {RootUserRecord} from "../core/model";
import {
  EMAIL_BREVO_API_KEY,
  EMAIL_RECIPIENT_HMAC_KEYRING,
} from "../email/config";
import {EmailProviderError} from "../email/contracts";
import {
  parseRecipientHmacKeyring,
  RecipientHmacKeyring,
  normalizeEmail,
} from "../email/recipientHash";
import {
  bindRecipientPrivacy,
  hasActiveEmailSuppression,
  RecipientPrivacyBinding,
} from "../email/suppressionLookup";
import {staffInvitationEmail} from "../email/templates";
import {
  createInvitationProof,
  INVITATION_LIFETIME_MILLISECONDS,
  verifyInvitationProof,
} from "./invitationProof";
import {STAFF_INVITATION_HMAC_SECRET, invitationHmacSecretValue} from "./secret";
import {storedCredentialBootstrapRequired} from "./shared";
import {
  StoredInvitationRecord,
  StoredStaffRecord,
  StoredTenantRecord,
} from "./types";

export const STAFF_INVITATION_ACTION_BASE_URL = defineString(
  "STAFF_INVITATION_ACTION_BASE_URL"
);
export const STAFF_INVITATION_SENDER_EMAIL = defineString(
  "STAFF_INVITATION_SENDER_EMAIL"
);
export const STAFF_INVITATION_SENDER_NAME = defineString(
  "STAFF_INVITATION_SENDER_NAME",
  {default: "UzaPay"}
);

const DELIVERY_QUEUE_FUNCTION = "deliverStaffInvitation";
const DELIVERY_LEASE_MILLISECONDS = 10 * 60 * 1000;
const MAX_INVITATION_DELIVERY_ATTEMPTS = 8;

export interface InvitationDeliveryTask {
  deliveryId: string;
  tenantId: string;
  targetUid: string;
  invitedEmail: string;
  invitationVersion: number;
  invitationToken: string;
  invitationPath: string;
  dispatchAttempt: number;
  credentialBootstrapRequired: boolean;
}

export type EnqueueInvitationDelivery = (
  task: InvitationDeliveryTask,
  taskId: string
) => Promise<void>;

interface StoredDelivery {
  deliveryId?: unknown;
  deliveryType?: unknown;
  status?: unknown;
  tenantId?: unknown;
  targetUid?: unknown;
  invitationVersion?: unknown;
  invitationPath?: unknown;
  attemptCount?: unknown;
  dispatchLeaseId?: unknown;
  dispatchLeaseExpiresAt?: unknown;
  nextAttemptAt?: unknown;
  recipientHash?: unknown;
  recipientHashKeyVersion?: unknown;
}

interface StaffDeliveryAuthIdentity {
  uid: string;
  email?: string;
  disabled: boolean;
}

export function isEligibleStaffInvitationRecipient(
  task: InvitationDeliveryTask,
  authIdentity: StaffDeliveryAuthIdentity | undefined,
  root: RootUserRecord | undefined,
  tenant: StoredTenantRecord | undefined,
  staff: StoredStaffRecord | undefined
): boolean {
  const currentEmail = normalizeEmail(authIdentity?.email);
  return !!authIdentity &&
    authIdentity.uid === task.targetUid &&
    authIdentity.disabled !== true &&
    currentEmail === task.invitedEmail &&
    root?.accountType === "tenant_user" &&
    root.globalStatus === "active" &&
    root.identityTransition === undefined &&
    tenant?.status === "active" &&
    staff?.uid === task.targetUid &&
    staff.status === "pending" &&
    staff.role !== "owner" &&
    ["pending", "sent"].includes(String(staff.invitationStatus)) &&
    normalizeEmail(staff.email) === task.invitedEmail;
}

/**
 * Mirrors what the delivery subsystem knows onto the canonical staff record.
 *
 * **The staff directory reads canonical staff and nothing else.** Delivery
 * state lived in `email_deliveries` and in the invitation's own record, and a
 * device may read neither - so an invitation emailed an hour ago still read as
 * *Not sent yet* on the only screen an administrator has, and the recovery they
 * reached for was to send it a second time.
 *
 * **Deliberately not `invitationStatus`.** That field is where the membership
 * stands, it is only ever `pending` or `accepted` on this record, and three
 * server gates read it: `requirePendingStaffInvitation` for resend, cancel and
 * email replacement, and `acceptancePolicy` for acceptance itself. Folding a
 * delivery outcome into it would have refused the recipient's acceptance and
 * the administrator's replace-the-address - the two recoveries a failed
 * delivery exists to prompt. An email's fate is a different fact from a
 * membership's, so it gets a different field.
 *
 * **Guarded, and silent when the guard fails.** This worker runs long after the
 * transaction that queued it, and by the time it lands the member may have
 * accepted, or the invitation may have been cancelled and this record deleted.
 * Writing regardless would either fail the task into a retry loop against a
 * document that is never coming back, or hang a delivery label on a membership
 * that is no longer pending. Neither is worth a label, so a mirror that no
 * longer applies is dropped.
 */
export function mirrorDeliveryStateOntoStaff(
  transaction: Transaction,
  staffRef: DocumentReference,
  staffSnapshot: DocumentSnapshot,
  fields: Record<string, unknown>
): void {
  if (!staffSnapshot.exists) return;
  const staff = staffSnapshot.data() as StoredStaffRecord;
  if (staff.uid !== staffRef.id || staff.status !== "pending") return;
  transaction.update(staffRef, {
    ...fields,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

async function terminalizeStaffDelivery(
  db: Firestore,
  deliveryRef: DocumentReference,
  task: InvitationDeliveryTask,
  status: "cancelled" | "superseded" | "permanent_failure",
  errorCode: string
): Promise<void> {
  const staffRef = db.collection("tenants").doc(task.tenantId)
    .collection("staff").doc(task.targetUid);
  await db.runTransaction(async (transaction) => {
    const [current, staffSnapshot] = await transaction.getAll(
      deliveryRef,
      staffRef
    );
    if (
      current.data()?.invitationVersion !== task.invitationVersion ||
      current.data()?.attemptCount !== task.dispatchAttempt ||
      [
        "sent",
        "suppressed",
        "permanent_failure",
        "cancelled",
        "superseded",
      ].includes(current.data()?.status)
    ) return;
    transaction.update(deliveryRef, {
      status,
      sendable: false,
      retryable: false,
      nextAttemptAt: FieldValue.delete(),
      dispatchLeaseId: FieldValue.delete(),
      dispatchLeaseExpiresAt: FieldValue.delete(),
      lastErrorCode: errorCode,
      updatedAt: FieldValue.serverTimestamp(),
    });
    // **Only `permanent_failure` is the member's business.** `cancelled` has
    // already deleted this record, and `superseded` means a newer delivery owns
    // the projection and is mid-flight with it.
    if (status !== "permanent_failure") return;
    mirrorDeliveryStateOntoStaff(transaction, staffRef, staffSnapshot, {
      invitationDeliveryState: "failed",
    });
  });
}

export function bindStaffDeliveryRecipient(
  email: unknown,
  delivery: Pick<StoredDelivery, "recipientHash" | "recipientHashKeyVersion">,
  keyring: RecipientHmacKeyring
): RecipientPrivacyBinding | undefined {
  const binding = bindRecipientPrivacy(email, keyring);
  const persistedBindingIsSupported = binding?.supported.some((candidate) =>
    delivery.recipientHash === candidate.recipientHash &&
    delivery.recipientHashKeyVersion === candidate.keyVersion
  ) === true;
  return persistedBindingIsSupported ? binding : undefined;
}

function safeAttempt(value: unknown): number {
  return Number.isSafeInteger(value) && (value as number) >= 0 ? value as number : 0;
}

function retryDelayMilliseconds(attempt: number): number {
  return Math.min(6 * 60 * 60 * 1000, 30_000 * (2 ** Math.min(attempt, 10)));
}

export function validateInvitationDeliveryTask(value: unknown): InvitationDeliveryTask {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Invitation delivery task is invalid.");
  }
  const data = value as Record<string, unknown>;
  const stringFields = [
    "deliveryId",
    "tenantId",
    "targetUid",
    "invitedEmail",
    "invitationToken",
    "invitationPath",
  ] as const;
  for (const field of stringFields) {
    if (typeof data[field] !== "string" || !(data[field] as string)) {
      throw new Error(`Invitation delivery task ${field} is invalid.`);
    }
  }
  if (
    !Number.isSafeInteger(data.invitationVersion) ||
    (data.invitationVersion as number) < 1 ||
    !Number.isSafeInteger(data.dispatchAttempt) ||
    (data.dispatchAttempt as number) < 1
  ) {
    throw new Error("Invitation delivery task version is invalid.");
  }
  if (typeof data.credentialBootstrapRequired !== "boolean") {
    throw new Error("Invitation delivery task bootstrap policy is invalid.");
  }
  return data as unknown as InvitationDeliveryTask;
}

async function defaultEnqueue(task: InvitationDeliveryTask, taskId: string): Promise<void> {
  await getFunctions().taskQueue<InvitationDeliveryTask>(DELIVERY_QUEUE_FUNCTION).enqueue(
    task,
    {id: taskId, dispatchDeadlineSeconds: 60}
  );
}

/**
 * Rotates proof material transactionally, then passes the plaintext proof only
 * to Cloud Tasks. Firestore stores only its HMAC and delivery metadata.
 */
export async function dispatchInvitationDelivery(
  db: Firestore,
  deliveryId: string,
  secret: string,
  enqueue: EnqueueInvitationDelivery = defaultEnqueue
): Promise<"queued" | "retry_pending" | "not_pending"> {
  let task: InvitationDeliveryTask | undefined;
  let leaseId = "";
  const deliveryRef = db.collection("email_deliveries").doc(deliveryId);
  const now = Timestamp.now();
  const claimed = await db.runTransaction(async (transaction) => {
    const deliverySnapshot = await transaction.get(deliveryRef);
    if (!deliverySnapshot.exists) return false;
    const delivery = deliverySnapshot.data() as StoredDelivery;
    const attemptCount = safeAttempt(delivery.attemptCount);
    const leaseActive = delivery.dispatchLeaseExpiresAt instanceof Timestamp &&
      delivery.dispatchLeaseExpiresAt.toMillis() > now.toMillis();
    if (
      ![
        "pending_enqueue",
        "retry_pending",
        "provider_retry_pending",
        "enqueueing",
      ].includes(String(delivery.status)) ||
      (delivery.status === "enqueueing" && leaseActive) ||
      typeof delivery.invitationPath !== "string" ||
      typeof delivery.tenantId !== "string" ||
      typeof delivery.targetUid !== "string"
    ) return false;
    if (attemptCount >= MAX_INVITATION_DELIVERY_ATTEMPTS) {
      transaction.update(deliveryRef, {
        status: "permanent_failure",
        sendable: false,
        retryable: false,
        nextAttemptAt: FieldValue.delete(),
        dispatchLeaseId: FieldValue.delete(),
        dispatchLeaseExpiresAt: FieldValue.delete(),
        lastErrorCode: "delivery_attempts_exhausted",
        updatedAt: FieldValue.serverTimestamp(),
      });
      return false;
    }
    const invitationRef = db.doc(delivery.invitationPath);
    const staffRef = db.collection("tenants").doc(delivery.tenantId)
      .collection("staff").doc(delivery.targetUid);
    const [invitationSnapshot, staffSnapshot] = await transaction.getAll(
      invitationRef,
      staffRef
    );
    if (!invitationSnapshot.exists) return false;
    const invitation = invitationSnapshot.data() as StoredInvitationRecord;
    if (
      invitation.uid !== delivery.targetUid ||
      invitation.tenantId !== delivery.tenantId ||
      invitation.latestDeliveryId !== deliveryId ||
      !["pending", "sent"].includes(String(invitation.invitationStatus)) ||
      typeof invitation.invitedEmail !== "string"
    ) return false;
    const oldVersion = Number.isSafeInteger(invitation.invitationVersion) ?
      invitation.invitationVersion as number : 0;
    const invitationVersion = attemptCount === 0 ? oldVersion : oldVersion + 1;
    if (invitationVersion < 1) return false;
    const proof = createInvitationProof({
      tenantId: delivery.tenantId,
      uid: delivery.targetUid,
      invitedEmail: invitation.invitedEmail,
      invitationVersion,
    }, secret);
    const dispatchAttempt = attemptCount + 1;
    leaseId = randomUUID();
    task = {
      deliveryId,
      tenantId: delivery.tenantId,
      targetUid: delivery.targetUid,
      invitedEmail: invitation.invitedEmail,
      invitationVersion,
      invitationToken: proof.token,
      invitationPath: delivery.invitationPath,
      dispatchAttempt,
      credentialBootstrapRequired: storedCredentialBootstrapRequired(invitation),
    };
    const invitationExpiresAt = Timestamp.fromMillis(
      now.toMillis() + INVITATION_LIFETIME_MILLISECONDS
    );
    transaction.update(invitationRef, {
      invitationVersion,
      invitationTokenHash: proof.tokenHash,
      invitationTokenKeyVersion: proof.tokenKeyVersion,
      invitationIssuedAt: now,
      invitationExpiresAt,
      invitationTokenUsedAt: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    // **The deadline is minted here, so this is where the directory learns it.**
    // `staff_invitations` is unreadable by every client, and the expiry only
    // exists once a token does - an invitation whose first delivery has not been
    // claimed has no deadline to show. The status goes back to `pending` with
    // it because that is the truth about *this* attempt: a resend mints fresh
    // proof and has not delivered it yet, so a row still reading `sent` from the
    // previous round would be describing an email that no longer opens anything.
    mirrorDeliveryStateOntoStaff(transaction, staffRef, staffSnapshot, {
      invitationDeliveryState: "pending",
      invitationExpiresAt,
    });
    transaction.update(deliveryRef, {
      status: "enqueueing",
      invitationVersion,
      attemptCount: dispatchAttempt,
      dispatchLeaseId: leaseId,
      dispatchLeaseExpiresAt: Timestamp.fromMillis(
        now.toMillis() + DELIVERY_LEASE_MILLISECONDS
      ),
      nextAttemptAt: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!claimed || !task) return "not_pending";

  try {
    await enqueue(task, `${deliveryId}-${task.dispatchAttempt}`);
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(deliveryRef);
      if (
        snapshot.data()?.status !== "enqueueing" ||
        snapshot.data()?.dispatchLeaseId !== leaseId
      ) return;
      transaction.update(deliveryRef, {
        status: "queued",
        enqueuedAt: FieldValue.serverTimestamp(),
        dispatchLeaseId: FieldValue.delete(),
        dispatchLeaseExpiresAt: FieldValue.delete(),
        lastErrorCode: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    return "queued";
  } catch (error) {
    const nextAttemptAt = Timestamp.fromMillis(
      Date.now() + retryDelayMilliseconds(task.dispatchAttempt)
    );
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(deliveryRef);
      if (snapshot.data()?.dispatchLeaseId !== leaseId) return;
      transaction.update(deliveryRef, {
        status: "retry_pending",
        nextAttemptAt,
        dispatchLeaseId: FieldValue.delete(),
        dispatchLeaseExpiresAt: FieldValue.delete(),
        lastErrorCode: "task_enqueue_failed",
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    return "retry_pending";
  }
}

function invitationActionUrl(task: InvitationDeliveryTask, baseUrl: string): string {
  if (!/^https:\/\//i.test(baseUrl)) {
    throw new Error("STAFF_INVITATION_ACTION_BASE_URL must be an HTTPS URL.");
  }
  const url = new URL(baseUrl);
  url.searchParams.set("tenantId", task.tenantId);
  url.searchParams.set("uid", task.targetUid);
  url.searchParams.set("invitationVersion", String(task.invitationVersion));
  url.searchParams.set("invitationToken", task.invitationToken);
  return url.toString();
}

export type GenerateCredentialBootstrapLink = (
  email: string,
  continueUrl: string
) => Promise<string>;

async function defaultGenerateCredentialBootstrapLink(
  email: string,
  continueUrl: string
): Promise<string> {
  return getAuth().generatePasswordResetLink(email, {
    url: continueUrl,
    handleCodeInApp: false,
  });
}

/** Selects a direct proof link or a transient Firebase credential-setup link. */
export async function invitationDeliveryLink(
  task: InvitationDeliveryTask,
  generateCredentialBootstrapLink: GenerateCredentialBootstrapLink =
    defaultGenerateCredentialBootstrapLink,
  actionBaseUrl = STAFF_INVITATION_ACTION_BASE_URL.value()
): Promise<string> {
  const proofActionUrl = invitationActionUrl(task, actionBaseUrl);
  if (!task.credentialBootstrapRequired) return proofActionUrl;
  return generateCredentialBootstrapLink(task.invitedEmail, proofActionUrl);
}

async function sendWithBrevo(task: InvitationDeliveryTask): Promise<string> {
  const senderEmail = STAFF_INVITATION_SENDER_EMAIL.value();
  if (!senderEmail.includes("@")) {
    throw new EmailProviderError("provider_not_configured", false);
  }
  let actionUrl: string;
  try {
    actionUrl = await invitationDeliveryLink(task);
  } catch {
    throw new EmailProviderError("credential_link_unavailable", true);
  }
  // The copy differs by whether the link sets a password on the way through,
  // which is the same flag `invitationDeliveryLink` just branched on.
  const rendered = staffInvitationEmail(
    actionUrl,
    task.credentialBootstrapRequired
  );
  let response: Response;
  try {
    response = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: {
        accept: "application/json",
        "api-key": EMAIL_BREVO_API_KEY.value(),
        "content-type": "application/json",
      },
      body: JSON.stringify({
        sender: {
          email: senderEmail,
          name: STAFF_INVITATION_SENDER_NAME.value(),
        },
        to: [{email: task.invitedEmail}],
        subject: rendered.subject,
        textContent: rendered.text,
        htmlContent: rendered.html,
        headers: {
          "Idempotency-Key": `${task.deliveryId}-${task.dispatchAttempt}`,
          "X-Mailin-Track-Clicks": "0",
          "X-Mailin-Track-Opens": "0",
        },
        tags: ["staff-invitation"],
      }),
    });
  } catch {
    throw new EmailProviderError("provider_transport_failure", true);
  }
  if (!response.ok) {
    const retryable = response.status === 408 || response.status === 409 ||
      response.status === 425 || response.status === 429 || response.status >= 500;
    throw new EmailProviderError(`provider_http_${response.status}`, retryable);
  }
  let body: {messageId?: unknown};
  try {
    body = await response.json() as {messageId?: unknown};
  } catch {
    throw new EmailProviderError("provider_invalid_response", true);
  }
  if (typeof body.messageId !== "string" || !body.messageId) {
    throw new EmailProviderError("provider_invalid_response", true);
  }
  return body.messageId;
}

export const deliverStaffInvitation = onTaskDispatched<InvitationDeliveryTask>(
  {
    secrets: [
      STAFF_INVITATION_HMAC_SECRET,
      EMAIL_RECIPIENT_HMAC_KEYRING,
      EMAIL_BREVO_API_KEY,
    ],
    retryConfig: {maxAttempts: 8, minBackoffSeconds: 30, maxBackoffSeconds: 3600},
    rateLimits: {maxConcurrentDispatches: 10},
    timeoutSeconds: 60,
  },
  async (request) => {
    const task = validateInvitationDeliveryTask(request.data);
    const db = getFirestore();
    const deliveryRef = db.collection("email_deliveries").doc(task.deliveryId);
    const invitationRef = db.doc(task.invitationPath);
    const rootRef = db.collection("users").doc(task.targetUid);
    const tenantRef = db.collection("tenants").doc(task.tenantId);
    const staffRef = tenantRef.collection("staff").doc(task.targetUid);
    const [
      deliverySnapshot,
      invitationSnapshot,
      rootSnapshot,
      tenantSnapshot,
      staffSnapshot,
    ] = await db.getAll(
      deliveryRef,
      invitationRef,
      rootRef,
      tenantRef,
      staffRef
    );
    if (!deliverySnapshot.exists) return;
    const delivery = deliverySnapshot.data() as StoredDelivery;
    if ([
      "sent",
      "suppressed",
      "permanent_failure",
      "cancelled",
      "superseded",
    ].includes(String(delivery.status))) return;
    if (
      delivery.deliveryType !== "staff_invitation" ||
      !["enqueueing", "queued", "provider_retry_pending"].includes(
        String(delivery.status)
      ) ||
      delivery.deliveryId !== task.deliveryId ||
      delivery.tenantId !== task.tenantId ||
      delivery.targetUid !== task.targetUid ||
      delivery.invitationPath !== task.invitationPath ||
      delivery.invitationVersion !== task.invitationVersion ||
      delivery.attemptCount !== task.dispatchAttempt
    ) return;
    if (!invitationSnapshot.exists) {
      await terminalizeStaffDelivery(
        db,
        deliveryRef,
        task,
        "permanent_failure",
        "invitation_missing"
      );
      return;
    }
    const invitation = invitationSnapshot.data() as StoredInvitationRecord;
    if (
      invitation.uid !== task.targetUid ||
      invitation.tenantId !== task.tenantId ||
      normalizeEmail(invitation.invitedEmail) !== task.invitedEmail
    ) {
      await terminalizeStaffDelivery(
        db,
        deliveryRef,
        task,
        "permanent_failure",
        "invitation_identity_mismatch"
      );
      return;
    }
    if (
      invitation.invitationVersion !== task.invitationVersion ||
      invitation.latestDeliveryId !== task.deliveryId
    ) {
      await terminalizeStaffDelivery(
        db,
        deliveryRef,
        task,
        "superseded",
        "invitation_superseded"
      );
      return;
    }
    if (
      !["pending", "sent"].includes(String(invitation.invitationStatus)) ||
      invitation.invitationTokenUsedAt !== null
    ) {
      await terminalizeStaffDelivery(
        db,
        deliveryRef,
        task,
        "cancelled",
        "invitation_no_longer_pending"
      );
      return;
    }
    if (
      typeof invitation.invitationTokenHash !== "string" ||
      !verifyInvitationProof({
        tenantId: task.tenantId,
        uid: task.targetUid,
        invitedEmail: task.invitedEmail,
        invitationVersion: task.invitationVersion,
      }, task.invitationToken, invitation.invitationTokenHash,
      invitation.invitationTokenKeyVersion, invitationHmacSecretValue())
    ) {
      await terminalizeStaffDelivery(
        db,
        deliveryRef,
        task,
        "permanent_failure",
        "invitation_proof_invalid"
      );
      return;
    }

    let authIdentity: StaffDeliveryAuthIdentity | undefined;
    try {
      const authUser = await getAuth().getUser(task.targetUid);
      authIdentity = {
        uid: authUser.uid,
        email: authUser.email,
        disabled: authUser.disabled,
      };
    } catch (error) {
      const code = error && typeof error === "object" && "code" in error ?
        String((error as {code?: unknown}).code) : undefined;
      if (code !== "auth/user-not-found") throw error;
    }
    if (!isEligibleStaffInvitationRecipient(
      task,
      authIdentity,
      rootSnapshot.exists ? rootSnapshot.data() as RootUserRecord : undefined,
      tenantSnapshot.exists ? tenantSnapshot.data() as StoredTenantRecord : undefined,
      staffSnapshot.exists ? staffSnapshot.data() as StoredStaffRecord : undefined
    )) {
      await terminalizeStaffDelivery(
        db,
        deliveryRef,
        task,
        "permanent_failure",
        "recipient_no_longer_eligible"
      );
      return;
    }

    const recipient = bindStaffDeliveryRecipient(
      task.invitedEmail,
      delivery,
      parseRecipientHmacKeyring(EMAIL_RECIPIENT_HMAC_KEYRING.value())
    );
    if (!recipient) {
      await terminalizeStaffDelivery(
        db,
        deliveryRef,
        task,
        "permanent_failure",
        "recipient_hash_unsupported"
      );
      return;
    }
    if (await hasActiveEmailSuppression(db, recipient)) {
      await db.runTransaction(async (transaction) => {
        const [current, staffSnapshot] = await transaction.getAll(
          deliveryRef,
          staffRef
        );
        if (
          current.data()?.invitationVersion !== task.invitationVersion ||
          current.data()?.attemptCount !== task.dispatchAttempt
        ) return;
        transaction.update(deliveryRef, {
          status: "suppressed",
          sendable: false,
          retryable: false,
          dispatchLeaseId: FieldValue.delete(),
          dispatchLeaseExpiresAt: FieldValue.delete(),
          nextAttemptAt: FieldValue.delete(),
          lastErrorCode: "recipient_suppressed",
          updatedAt: FieldValue.serverTimestamp(),
        });
        // A suppressed recipient is not a transient failure and resending will
        // not reach them; the recovery is a different address.
        mirrorDeliveryStateOntoStaff(transaction, staffRef, staffSnapshot, {
          invitationDeliveryState: "failed",
        });
      });
      return;
    }

    let providerMessageId: string;
    try {
      providerMessageId = await sendWithBrevo(task);
    } catch (error) {
      const safeCode = error instanceof EmailProviderError ?
        error.safeCode : "provider_send_failed";
      const retryable = (error instanceof EmailProviderError ? error.retryable : true) &&
        task.dispatchAttempt < MAX_INVITATION_DELIVERY_ATTEMPTS;
      await db.runTransaction(async (transaction) => {
        const [current, staffSnapshot] = await transaction.getAll(
          deliveryRef,
          staffRef
        );
        if (
          current.data()?.invitationVersion !== task.invitationVersion ||
          current.data()?.attemptCount !== task.dispatchAttempt
        ) return;
        transaction.update(deliveryRef, {
          status: retryable ? "provider_retry_pending" : "permanent_failure",
          sendable: retryable,
          retryable,
          ...(retryable ? {
            nextAttemptAt: Timestamp.fromMillis(
              Date.now() + retryDelayMilliseconds(task.dispatchAttempt)
            ),
          } : {nextAttemptAt: FieldValue.delete()}),
          dispatchLeaseId: FieldValue.delete(),
          dispatchLeaseExpiresAt: FieldValue.delete(),
          lastErrorCode: safeCode,
          updatedAt: FieldValue.serverTimestamp(),
        });
        // **A retry is not news.** The worker is still trying and the row
        // already says `Not sent yet`, which stays true; only running out of
        // attempts changes what the administrator should do about it.
        if (retryable) return;
        mirrorDeliveryStateOntoStaff(transaction, staffRef, staffSnapshot, {
          invitationDeliveryState: "failed",
        });
      });
      if (retryable) throw error;
      return;
    }
    await db.runTransaction(async (transaction) => {
      const [current, staffSnapshot] = await transaction.getAll(
        deliveryRef,
        staffRef
      );
      if (
        current.data()?.invitationVersion !== task.invitationVersion ||
        current.data()?.attemptCount !== task.dispatchAttempt
      ) return;
      transaction.update(deliveryRef, {
        status: "sent",
        provider: "brevo",
        providerMessageId,
        sentAt: FieldValue.serverTimestamp(),
        dispatchLeaseId: FieldValue.delete(),
        dispatchLeaseExpiresAt: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.update(invitationRef, {
        invitationStatus: "sent",
        updatedAt: FieldValue.serverTimestamp(),
      });
      // The half that was missing: three records knew this had been emailed and
      // the one the directory reads was not among them.
      mirrorDeliveryStateOntoStaff(transaction, staffRef, staffSnapshot, {
        invitationDeliveryState: "sent",
      });
    });
  }
);

export const retryStaffInvitationDeliveries = onSchedule(
  {
    schedule: "every 5 minutes",
    secrets: [STAFF_INVITATION_HMAC_SECRET],
    timeoutSeconds: 300,
    maxInstances: 1,
  },
  async () => {
    const db = getFirestore();
    const now = Timestamp.now();
    const [due, expiredEnqueueing] = await Promise.all([
      db.collection("email_deliveries")
        .where("deliveryType", "==", "staff_invitation")
        .where("status", "in", [
          "pending_enqueue",
          "retry_pending",
          "provider_retry_pending",
        ])
        .where("nextAttemptAt", "<=", now)
        .orderBy("nextAttemptAt", "asc")
        .orderBy(FieldPath.documentId())
        .limit(50)
        .get(),
      db.collection("email_deliveries")
        .where("deliveryType", "==", "staff_invitation")
        .where("status", "==", "enqueueing")
        .where("dispatchLeaseExpiresAt", "<=", now)
        .orderBy("dispatchLeaseExpiresAt", "asc")
        .orderBy(FieldPath.documentId())
        .limit(50)
        .get(),
    ]);
    const candidates = new Map([
      ...due.docs,
      ...expiredEnqueueing.docs,
    ].map((document) => [document.id, document]));
    for (const document of candidates.values()) {
      await dispatchInvitationDelivery(
        db,
        document.id,
        invitationHmacSecretValue()
      );
    }
  }
);
